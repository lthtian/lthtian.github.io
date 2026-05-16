---
title: Linux多线程服务端编程 读书笔记2
date: 2025-7-14 17:00:00
tags: [文件传输, io_uring]
---

> 第二部分 Muduo网络库

### 文件传输

- 如何完整高效地传输一个文件?

文件传输过程一般如下 : 

- 磁盘 -> 内核页缓冲 -> 用户缓冲区 -> Tcp发送缓冲区 -> 网卡等

最简单的传输方式当然就是fread + send 一口气传出, 但是这样如果文件非常大的话, 服务器扛不住几个连接, 因为这样的内存消耗非常大. 

书中提出了一种解决内存占用过多的方法 : **流水线 --- 分块传输**.

```cpp
#include <muduo/net/TcpConnection.h>
#include <muduo/base/Logging.h>
#include <boost/any.hpp>
#include <memory>

using namespace muduo;
using namespace muduo::net;

// 自定义删除器，用于自动 fclose
void customDeleter(FILE* fp)
{
    if (fp)
    {
        ::fclose(fp);
        LOG_INFO << "FILE* closed";
    }
}

using FilePtr = std::shared_ptr<FILE>;

void onConnection(const TcpConnectionPtr& conn)
{
    if (conn->connected())
    {
        const char* filename = "example.txt";  // 假设传输该文件
        FILE* fp = ::fopen(filename, "rb");

        if (fp)
        {
            // 使用 shared_ptr + 自定义 deleter 管理 FILE*
            FilePtr ctx(fp, customDeleter);
            conn->setContext(ctx);

            char buf[64 * 1024];
            size_t nread = ::fread(buf, 1, sizeof buf, fp);
            if (nread > 0)
            {
                conn->send(buf, nread);
            }
        }
        else
        {
            LOG_INFO << "FileServer - no such file";
            conn->shutdown();
        }
    }
    else
    {
        LOG_INFO << "FileServer - connection closed";
    }
}

void onWriteComplete(const TcpConnectionPtr& conn)
{
    FilePtr fp = boost::any_cast<FilePtr>(conn->getContext());

    if (fp && *fp)
    {
        char buf[64 * 1024];
        size_t nread = ::fread(buf, 1, sizeof buf, fp.get());

        if (nread > 0)
        {
            conn->send(buf, nread);  // 下一块数据
        }
        else
        {
            // 自动关闭 FILE*（shared_ptr 析构时调用 fclose）
            conn->setContext(FilePtr());  // 清空 context，触发析构
            conn->shutdown();             // 主动关闭连接
            LOG_INFO << "FileServer - done";
        }
    }
}
```

这里在建立连接时, 我们只读发了一个64kb, 在写完后才会自动调用Muduo的写完回调, 写完回调中还会继续发送64kb, 发完又会执行写完回调, 直到发完为止. 这是一个很典型的异步循环事件, 可以减少线程阻塞时间与内存占用.

流水线传输的优势 : 

- 内存占用少
- 防止长时间阻塞等待, 除非你用了非阻塞 + epoll
- 可以配合流控动态调整(HighWaterMark)
- 可以便于实现限速 / 动态生成内容 / 生成日志等操作

当然这是最普遍的跨平台做法, 如果目光放在Linux平台上就有更快捷的方法 : 

- **sendfile** : 

  这是专门用来发送文件到socket的内核态函数, 也就是说可以直接跳过内核页缓存到用户缓冲区的拷贝, 直接发给socket, 这样直接砍掉了大部分的内存消耗并且效率极高. 当然sendfile也不是说就可以直接全读全发了, 例如Nginx就还是采取了流水线分块的方式使用sendfile, 这主要还是因为除了内存占用, 其还有其他优势.

- io_uring : 后面详解.

### TCP分包

- 针对短连接TCP(需求可靠传输少量数据)的情况, 一般不用考虑分包, 只要等待对方关闭连接, 我方返回0时就可以确定拿到所有数据.
- 针对长连接TCP, 有四种方法 : 
  - 消息长度固定
  - 用特殊的字符或字符串为边界, 如HTTP
  - 每个消息都加入一个长度字段, 表示之后要发来的消息长度
  - 消息本身就有自己的格式 : json / protobuf 

### Buffer设计

- 非阻塞 + IO复用 的网络编程中, 应用层的Buffer是必须的 : 
  - output buffer : 因为程序最好不要在write时阻塞, 这种情况受限于网络传输状态, 必须要配置输出缓存, 其作用是在一次write无法全部写出去时, 将剩余的部分存到buffer中, 并且设置回调, 当TCP发送缓冲区可写时再调用回调, 也许可以调用io_uring异步IO提高效率. **可加强**



### Protobuf使用

- 特性 : 
  - protobuf是一个内容格式, 并非传输协议, 因此其并为封装消息长度, 消息类型之类的东西.
  - 便捷的是, 如果我们不要Tcp长连接, 需求类型单一, 就可以直接凭借字段解析, 无需依靠长度和类型, 就可以拿到我们想要的数据.
  - 如果需要Tcp长连接, 可以考虑追加header, 其中包含服务名和方法名/类型名, 我们接收到可以利用Descriptor加这些名字自动构建对应的服务方法类型. 
- ProtobufCodec
- ProtobufDispatcher

### 限制服务器的最大并发连接数

- 可以通过调高进程的文件描述符数目缓解, 但是不宜过多会拖慢进程.

- 最方便快捷的就是设置一个最大连接数, 这个数据在多线程情况下应当线程安全, 当连接数超过这个数, 就直接把连接断掉, 不继续处理.

- 不这样做会发生什么?  

  新连接一直不会得到处理, epoll_wait会被极频繁触发, 极大提高cpu占有率.

### 检测并清理无效连接

方法一般就是两大类 : 踢掉空闲连接 和 设置心跳协议.

前者可以当作权益之计, 但是够轻量, 够便捷, 基本思路就是维护一些桶, 将超时桶中的连接关闭, 一旦有新连接就更新所在桶.

后者更加稳定有效, 虽然内部会比较冗杂, 但是又很多现代的优化方式, 比如操作系统内核层的心跳机制, 用io_uring + kqueue直接实现精准定时发送.

### io_uring

#### 简易理解

- 目的 : 减少系统调用(减少状态转换开销), 减少无效拷贝, 异步实现接口.
- 实现 : 内部维护一个请求队列和一个结果队列, 会利用mmap申请一块共享内存, 系统存放数据和用户取出数据都在这块内存上进行, 可以有效减少内核函数调用, 并且纯异步可以有效提高并发.
- 使用 : 在此实现上, io_uring提供了很多便利各种服务的接口, 支持读、写、accept、connect、send、recv、splice、sendfile 等统一异步接口, 也就是它们的异步高效版.

#### 使用

- 初始化与销毁 : 

  | 函数                    | 说明                              |
  | ----------------------- | --------------------------------- |
  | `io_uring_queue_init()` | 初始化 io_uring（内核分配 SQ/CQ） |
  | `io_uring_queue_exit()` | 清理资源，解除映射                |

- 提交请求(提交异步事件) : 

  | 函数                         | 说明                                                         |
  | ---------------------------- | ------------------------------------------------------------ |
  | `io_uring_get_sqe()`         | 获取一个空的提交项（SQE）指针                                |
  | `io_uring_prep_*()`          | 填充 SQE，不同操作有不同函数，如 `io_uring_prep_read()`、`io_uring_prep_accept()` |
  | `io_uring_sqe_set_data()`    | 给 SQE 绑定用户数据（上下文结构体）                          |
  | `io_uring_submit()`          | 将 SQE 正式提交到内核队列                                    |
  | `io_uring_submit_and_wait()` | 提交并等待至少 N 个事件完成（阻塞）                          |

  sqe简单来说就是一个请求句柄, 我们可以用其注册不同的事件, 当然如果有需要的资源(如buf, fd)我们需要填入, 当然在获取对应cqe的时候我们会希望获取一些上下文信息, 可以利用`io_uring_sqe_set_data()`传入我们自定义结构体的指针, 之后我们就可以利用`io_uring_cqe_get_data()`获取.

- 获取完成结果 :

  | 函数                      | 说明                                                         |
  | ------------------------- | ------------------------------------------------------------ |
  | `io_uring_wait_cqe()`     | 阻塞直到有一个 CQE 可用                                      |
  | `io_uring_peek_cqe()`     | 非阻塞地获取一个 CQE，如果没有返回 NULL                      |
  | `io_uring_cqe_get_data()` | 获取你当初绑定的上下文指针（通过 `io_uring_sqe_set_data` 传入） |
  | `io_uring_cqe_seen()`     | 标记这个 CQE 已处理完毕，释放 CQ 空间                        |

  `io_uring_wait_cqe()`会返回cqe对象, cqe->res中存储的是你在sqe中请求任务函数的返回值, 比如read就会返回int表明是否读取成功与读取长度, accept就会返回新连接的fd.

#### 文件读取

以下是最简使用io_uring读取一个文件的代码 :

```cpp
#include <liburing.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <iostream>

int main()
{
    const char *path = "testconf.txt";
    char buffer[4096] = {0};

    // 打开文件
    int fd = open(path, O_RDONLY);
    if (fd < 0)
    {
        perror("open");
        return 1;
    }

    // 初始化 io_uring（默认 8 项）
    io_uring ring;
    io_uring_queue_init(8, &ring, 0);

    // 准备提交一个 read 操作
    struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
    io_uring_prep_read(sqe, fd, buffer, sizeof(buffer) - 1, 0); // 类似 read(fd, buf, 4096, offset=0)
    io_uring_submit(&ring);                                     // 通知内核提交任务

    // 等待结果
    struct io_uring_cqe *cqe;
    io_uring_wait_cqe(&ring, &cqe);
    if (cqe->res < 0)
    {
        std::cerr << "read failed: " << strerror(-cqe->res) << std::endl;
    }
    else
    {
        std::cout << "Read success, bytes: " << cqe->res << std::endl;
        std::cout << "Content: \n"
                  << buffer << std::endl;
    }

    io_uring_cqe_seen(&ring, cqe);
    io_uring_queue_exit(&ring);
    close(fd);
    return 0;
}
```

#### 回显服务器

```cpp
#include <liburing.h>
#include <string.h>
#include <unistd.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <iostream>
#include <errno.h>

#define PORT 8888
#define BACKLOG 512
#define BUFFER_SIZE 2048
#define QUEUE_DEPTH  256

enum {
    ACCEPT,
    READ,
    WRITE
};

struct conn_info {
    int fd;
    int type;
};

void add_accept(struct io_uring* ring, int server_fd, sockaddr_in* client_addr, socklen_t* client_len) {
    io_uring_sqe* sqe = io_uring_get_sqe(ring);

    auto* ci = new conn_info{server_fd, ACCEPT};

    io_uring_prep_accept(sqe, server_fd, (sockaddr*)client_addr, client_len, 0);
    io_uring_sqe_set_data(sqe, ci);
    io_uring_submit(ring);
}

void add_read(struct io_uring* ring, int client_fd, char* buf) {
    io_uring_sqe* sqe = io_uring_get_sqe(ring);

    auto* ci = new conn_info{client_fd, READ};

    io_uring_prep_recv(sqe, client_fd, buf, BUFFER_SIZE, 0);
    io_uring_sqe_set_data(sqe, ci);
    io_uring_submit(ring);
}

void add_write(struct io_uring* ring, int client_fd, char* buf, size_t len) {
    io_uring_sqe* sqe = io_uring_get_sqe(ring);

    auto* ci = new conn_info{client_fd, WRITE};

    io_uring_prep_send(sqe, client_fd, buf, len, 0);
    io_uring_sqe_set_data(sqe, ci);
    io_uring_submit(ring);
}

int make_socket_non_blocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    addr.sin_addr.s_addr = INADDR_ANY;

    bind(server_fd, (sockaddr*)&addr, sizeof(addr));
    listen(server_fd, BACKLOG);
    make_socket_non_blocking(server_fd);

    io_uring ring;
    io_uring_queue_init(QUEUE_DEPTH, &ring, 0);

    sockaddr_in client_addr{};
    socklen_t client_len = sizeof(client_addr);
    add_accept(&ring, server_fd, &client_addr, &client_len);

    char* buffers[QUEUE_DEPTH] = {nullptr};
    for (int i = 0; i < QUEUE_DEPTH; ++i)
        buffers[i] = new char[BUFFER_SIZE];

    while (true) {
        io_uring_cqe* cqe;
        int ret = io_uring_wait_cqe(&ring, &cqe);
        if (ret < 0) {
            std::cerr << "wait_cqe failed: " << strerror(-ret) << "\n";
            break;
        }

        auto* ci = static_cast<conn_info*>(io_uring_cqe_get_data(cqe));
        int client_fd = ci->fd;
        int type = ci->type;
        int res = cqe->res;

        if (type == ACCEPT) {
            if (res >= 0) {
                make_socket_non_blocking(res);
                add_read(&ring, res, buffers[res % QUEUE_DEPTH]);
            }
            add_accept(&ring, server_fd, &client_addr, &client_len);
        }
        else if (type == READ) {
            if (res <= 0) {
                close(client_fd);
            } else {
                add_write(&ring, client_fd, buffers[client_fd % QUEUE_DEPTH], res);
            }
        }
        else if (type == WRITE) {
            add_read(&ring, client_fd, buffers[client_fd % QUEUE_DEPTH]);
        }

        delete ci;
        io_uring_cqe_seen(&ring, cqe);
    }

    io_uring_queue_exit(&ring);
    for (int i = 0; i < QUEUE_DEPTH; ++i)
        delete[] buffers[i];

    return 0;
}
```

我们可以看到其中循环读取cqe, 其实和epoll_wait非常像, 但是本质不一样, cqe得到的是已经通过异步完成的结果, 而epoll_wait得到是事件发送的通知. 不过io_uring_wait_cqe只能读取一个完成事件, 如果想一次性像epoll_wait多个读取事件集的话, 可以使用`io_uring_peek_batch_cqe()`非阻塞地获取ceq集.

```cpp
unsigned count = io_uring_peek_batch_cqe(&ring, cqe_array, max_count);
```

#### Buffer相关

我们可以将自己申请的buffer提前注册到io_uring服务中, 这样io_uring就会将我们用户态的缓冲区注册到内核中, 人话说就是, **io_uring会把我们的申请的用户态缓冲区当作内核缓冲区来用.** 这样就可以省去内核态缓冲区到用户缓冲区的拷贝, 可以提高效率, 甚至部分操作还可以实现零拷贝.

- 首先我们需要自己把需要注册的缓冲区new出来并注册 : 

  ```cpp
  std::vector<char *> buffers;
  iovec iovecs[QUEUE_DEPTH];
  
  for (int i = 0; i < QUEUE_DEPTH; ++i)
  {
      char *buf = new char[BUFFER_SIZE];
      buffers.push_back(buf);
      iovecs[i].iov_base = buf;
      iovecs[i].iov_len = BUFFER_SIZE;
  }
  io_uring_register_buffers(&ring, iovecs, QUEUE_DEPTH);
  ```

  需要注意的是, io_uring要求绑定的缓冲区必须是iovec数组, 这个结构体常用于readv/writev中, 其中存放指向缓冲区的指针和大小.

- 那么在之后的`io_uring_prep_*`各种操作中就可以直接使用我们注册的缓冲区.

- 对于缓冲区的使用有两种使用模式 : 

  - Fixed Buffer 模式 : 由用户选择注册缓冲区中的那块buf(其实就是iovec数组的哪个下标), 便于用户细化控制.

  - Buffer Selection 模式 : 内部将用户注册的内存投放到内存池中, 由系统自动随机选择未被使用的buf, 用户可以从cqe中提取出系统的选择结果, 代码更加方便, 并且内存分配更有效, 适合高并发场景. 

  - 可以通过seq请求句柄设置我们使用哪个buffer模式 : 

    ```cpp
    sqe->flags |= IOSQE_BUFFER_FIXED;
    sqe->flags |= IOSQE_BUFFER_SELECT;
    ```

  后面提供两种版本的回显服务器优化.

#### Fixed Buffer优化的回显服务器

```cpp
#include <liburing.h>
#include <string.h>
#include <unistd.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <iostream>
#include <errno.h>
#include <vector>

#define PORT 8888
#define BACKLOG 512
#define BUFFER_SIZE 2048
#define QUEUE_DEPTH 256

enum
{
    ACCEPT,
    READ,
    WRITE
};

struct conn_info
{
    int fd;
    int type;
    int buf_index;
};

// 全局缓冲区信息
std::vector<char *> buffers;
iovec iovecs[QUEUE_DEPTH];

int make_socket_non_blocking(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

void add_accept(io_uring *ring, int server_fd, sockaddr_in *client_addr, socklen_t *client_len)
{
    io_uring_sqe *sqe = io_uring_get_sqe(ring);
    auto *ci = new conn_info{server_fd, ACCEPT, -1};
    io_uring_prep_accept(sqe, server_fd, (sockaddr *)client_addr, client_len, 0);
    io_uring_sqe_set_data(sqe, ci);
}

void add_read(io_uring *ring, int client_fd, int buf_index)
{
    io_uring_sqe *sqe = io_uring_get_sqe(ring);
    auto *ci = new conn_info{client_fd, READ, buf_index};

    io_uring_prep_read_fixed(sqe, client_fd, iovecs[buf_index].iov_base, BUFFER_SIZE, 0, buf_index);
    io_uring_sqe_set_data(sqe, ci);
}

void add_write(io_uring *ring, int client_fd, int buf_index, size_t len)
{
    io_uring_sqe *sqe = io_uring_get_sqe(ring);
    auto *ci = new conn_info{client_fd, WRITE, buf_index};

    io_uring_prep_write_fixed(sqe, client_fd, iovecs[buf_index].iov_base, len, 0, buf_index);
    io_uring_sqe_set_data(sqe, ci);
}

int main()
{
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    addr.sin_addr.s_addr = INADDR_ANY;

    bind(server_fd, (sockaddr *)&addr, sizeof(addr));
    listen(server_fd, BACKLOG);
    make_socket_non_blocking(server_fd);

    io_uring ring;
    io_uring_queue_init(QUEUE_DEPTH, &ring, 0);

    // 注册固定缓冲区
    for (int i = 0; i < QUEUE_DEPTH; ++i)
    {
        char *buf = new char[BUFFER_SIZE];
        buffers.push_back(buf);
        iovecs[i].iov_base = buf;
        iovecs[i].iov_len = BUFFER_SIZE;
    }
    io_uring_register_buffers(&ring, iovecs, QUEUE_DEPTH);

    sockaddr_in client_addr{};
    socklen_t client_len = sizeof(client_addr);
    add_accept(&ring, server_fd, &client_addr, &client_len);
    io_uring_submit(&ring);

    while (true)
    {
        io_uring_cqe *cqe;
        int ret = io_uring_wait_cqe(&ring, &cqe);
        if (ret < 0)
        {
            std::cerr << "wait_cqe failed: " << strerror(-ret) << "\n";
            break;
        }

        auto *ci = static_cast<conn_info *>(io_uring_cqe_get_data(cqe));
        int client_fd = ci->fd;
        int type = ci->type;
        int res = cqe->res;

        if (type == ACCEPT)
        {
            if (res >= 0)
            {
                make_socket_non_blocking(res);
                int buf_index = res % QUEUE_DEPTH;
                add_read(&ring, res, buf_index);
            }
            add_accept(&ring, server_fd, &client_addr, &client_len);
        }
        else if (type == READ)
        {
            if (res <= 0)
            {
                close(client_fd);
            }
            else
            {
                int buf_index = ci->buf_index;
                add_write(&ring, client_fd, buf_index, res);
            }
        }
        else if (type == WRITE)
        {
            int buf_index = ci->buf_index;
            add_read(&ring, client_fd, buf_index);
        }

        delete ci;
        io_uring_cqe_seen(&ring, cqe);
        io_uring_submit(&ring);
    }

    io_uring_queue_exit(&ring);
    for (auto *buf : buffers)
        delete[] buf;

    return 0;
}
```

- io_uring_prep_read_fixed : 

  这是一个便利函数, 其内部相当于调用了原函数, 设置使用Fixed Buffer模式, 设定使用的buffer_index.

  ```cpp
  io_uring_prep_read(sqe, fd, my_buffer, BUF_SIZE, 0);
  sqe->flags |= IOSQE_BUFFER_FIXED;  // 告诉内核这个 buffer 是固定注册的
  sqe->buf_index = 0; 
  ```

- 分析代码可以看出, 这里每次accept接收到新连接后都会为每个连接分配一个新的缓冲区下标, 以此做到每个连接对应一个缓冲区, 彼此不会相互影响.

- 当然我们发送的消息有可能一个缓冲区接收不了, 那么就只会读满缓冲区然后返回, 剩下的都会留在内核接收缓冲区中. 因此如果想解决这种情况, 可以判断接收大小是否等于BUF_SIZE, 如果等于就再提交一次异步读任务.

### 细碎知识

- 使用前向声明可以简化头文件之间的依赖关系, 避免将内部类暴露给用户.

- 流复用 + 均衡控制

- TLS加密/压缩

- 定时器内部使用gettimeofday(2)获取当前时间, 使用timerfd_*系列函数处理定时任务, 将定时器转化为fd, 可以用处理IO的方式处理超时事件.

- 往返时间 = round trip time = RTT.

  往返时间 / 2 一般不可代表单程延迟, 因为时间域不同, 双方发送路径可能不同.

- 基于 io_uring / kqueue 的高效超时检测 