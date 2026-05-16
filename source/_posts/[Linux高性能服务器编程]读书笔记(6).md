---
title: Linux高性能服务器编程 读书笔记(6)
date: 2025-2-19 17:36:00
tags: [Linux高性能服务器编程]
---

> 第10章 信号
>
> 第11章 定时器
>
> 第12章 libevent

网络服务器一般有三种事件需要处理 : IO事件, 信号事件, 定时器事件.

这三种事件都可以通过epoll函数来进行统一处理.

## 信号

#### 信号有什么作用?

其实主要是为了处理一些特殊事件, 比如中断系统调用, 触发定时器信号, 管道读写失败发出的信号. 比如说中断进程, 在服务器上直接中断一般不是一个合理的做法, 一般会捕获中断信号, 在做出中断的准备后(如关闭连接, 释放内存, 记录日志)在进行中断进程.

#### 最重要的两个信号捕获函数 

```cpp
#include＜signal.h＞
_sighandler_t signal(int　sig, _sighandler_t_handler);
int sigaction(int sig, const struct sigaction*act, struct sigaction*oact);
```

#### 信号来源

❑对于前台进程，用户可以通过输入特殊的终端字符来给它发送信号。比如输入Ctrl+C通常会给进程发送一个中断信号。

❑系统异常。比如浮点异常和非法内存段访问。

❑系统状态变化。比如alarm定时器到期将引起SIGALRM信号。

❑运行kill命令或调用kill函数。

服务器程序必须处理（或至少忽略）一些常见的信号，以免异常终止。

#### 统一事件源

听起来比较高端, 但其实就是把信号事件注册到epoll上, 让epoll可以通过if在处理IO事件的同时可以一并处理信号事件.

最基础的做法就是 : 

- 用signal或sigaction把需要捕获的信号获取
- 设置一个管道, 在信号回调函数中将信号转发给管道写端.
- 将管道的读端的读事件注册进内核事件表中.
- 在epoll_wait所在的循环中对管道的读端额外进行监视.

你可以理解为对于IO事件, epoll通过将sockfd注册进事件表进行监视; 对于信号事件, epoll通过将管道读端注册进内核事件表进行监视.

以下是一个统一事件源的代码 :

```cpp
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <assert.h>
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <pthread.h>

#define MAX_EVENT_NUMBER 1024

static int pipefd[2];

int setnonblocking(int fd) {
    int old_option = fcntl(fd, F_GETFL);
    int new_option = old_option | O_NONBLOCK;
    fcntl(fd, F_SETFL, new_option);
    return old_option;
}

void addfd(int epollfd, int fd) {
    epoll_event event;
    event.data.fd = fd;
    event.events = EPOLLIN | EPOLLET;
    epoll_ctl(epollfd, EPOLL_CTL_ADD, fd, &event);
    setnonblocking(fd);
}

/* 信号处理函数 */
void sig_handler(int sig) {
    int save_errno = errno;
    int msg = sig;
    send(pipefd[1], (char*)&msg, 1, 0);  /* 将信号值写入管道，以通知主循环 */
    errno = save_errno;
}

/* 设置信号的处理函数 */
void addsig(int sig) {
    struct sigaction sa;
    memset(&sa, '\0', sizeof(sa));
    sa.sa_handler = sig_handler;
    sa.sa_flags |= SA_RESTART;
    sigfillset(&sa.sa_mask);
    assert(sigaction(sig, &sa, NULL) != -1);
}

int main(int argc, char* argv[]) {
    if (argc <= 2) {
        printf("usage: %s ip_address port_number\n", basename(argv[0]));
        return 1;
    }

    const char* ip = argv[1];
    int port = atoi(argv[2]);
    int ret = 0;
    struct sockaddr_in address;
    bzero(&address, sizeof(address));
    address.sin_family = AF_INET;
    inet_pton(AF_INET, ip, &address.sin_addr);
    address.sin_port = htons(port);

    int listenfd = socket(PF_INET, SOCK_STREAM, 0);
    assert(listenfd >= 0);
    ret = bind(listenfd, (struct sockaddr*)&address, sizeof(address));
    if (ret == -1) {
        printf("errno is %d\n", errno);
        return 1;
    }

    ret = listen(listenfd, 5);
    assert(ret != -1);

    epoll_event events[MAX_EVENT_NUMBER];
    int epollfd = epoll_create(5);
    assert(epollfd != -1);

    addfd(epollfd, listenfd);

    /* 使用 socketpair 创建管道，注册 pipefd[0] 上的可读事件 */
    ret = socketpair(PF_UNIX, SOCK_STREAM, 0, pipefd);
    assert(ret != -1);
    setnonblocking(pipefd[1]);
    addfd(epollfd, pipefd[0]);  

    /* 设置一些信号的处理函数 */
    addsig(SIGHUP);
    addsig(SIGCHLD);
    addsig(SIGTERM);
    addsig(SIGINT);

    bool stop_server = false;
    while (!stop_server) {
        int number = epoll_wait(epollfd, events, MAX_EVENT_NUMBER, -1);
        if ((number < 0) && (errno != EINTR)) {
            printf("epoll failure\n");
            break;
        }

        for (int i = 0; i < number; i++) {
            int sockfd = events[i].data.fd;

            /* 如果就绪的文件描述符是 listenfd，则处理新的连接 */
            if (sockfd == listenfd) {
                struct sockaddr_in client_address;
                socklen_t client_addrlength = sizeof(client_address);
                int connfd = accept(listenfd, (struct sockaddr*)&client_address, &client_addrlength);
                addfd(epollfd, connfd);
            }
            /* 如果就绪的文件描述符是 pipefd[0]，则处理信号 */
            else if ((sockfd == pipefd[0]) && (events[i].events & EPOLLIN)) {
                int sig;
                char signals[1024];
                ret = recv(pipefd[0], signals, sizeof(signals), 0);
                if (ret == -1) continue;
                else if (ret == 0) continue;
                else {
                    for (int i = 0; i < ret; ++i) {
                        switch (signals[i]) {
                            case SIGCHLD:
                            case SIGHUP:
                                continue;
                            case SIGTERM:
                            case SIGINT:
                                stop_server = true;
                        }
                    }
                }
            }
        }
    }

    printf("close fds\n");
    close(listenfd);
    close(pipefd[1]);
    close(pipefd[0]);
    return 0;
}
```

这段代码中比较重点的是 : 

- `ret = socketpair(PF_UNIX, SOCK_STREAM, 0, pipefd);` 通过socketpair激活pipefd对应的管道
- `addfd(epollfd, pipefd[0]);`  将管道读端注册进内核事件表
- `addsig`函数将需要捕获的信号进行捕获
- `else if ((sockfd == pipefd[0]) && (events[i].events & EPOLLIN))` 在循环中额外对信号事件做处理.

---

## 定时器

其实就是服务器有可能需要有定时触发的机制存在, 所以需要用到Linux中的定时机制.

Linux提供了三种定时方法，它们是：

❑socket选项SO_RCVTIMEO和SO_SNDTIMEO。

❑SIGALRM信号。

❑I/O复用系统调用的超时参数。

这里比较重要的就是信号触发, SIGALRM是通过调用alarm函数传入触发时间来传出的, 很多定时器都基于这个实现.

定时器就是一个结构体, 里面一般包含了超时时间和回调函数, 我们在回调函数中处理定时任务.

最重要的如何实现定时触发, 一般是通过循环调用alarm实现每隔一段时间向系统发送一个SIGALRM信号, 通过统一事件源对SIGALRM信号做对应处理, 一般会调用一个心搏函数(tick), 对所有时间已经超时的定时器调用其回调函数执行定时任务.

这里还要思考的一个问题是, 定时任务有可能会很多, 我们需要一个容器来装载这些定时器, 考虑到一定是离超时时间越近的会越先被处理, 那么这个用来存储的容器就有一个需要排序的需求, 超时时间越小就越靠前.

这里有三种容器可供选择 : 链表, 时间轮, 时间堆.

- 链表 : 从链表的性质判断, 如果要保持链表有序, 插入效率O(N), 删除和执行的效率都是O(1).

  其实这个效率已经不错了, 虽然在理论上不一定比后两种强, 但是考虑到定时器事件在一般情况下需求量很小, 由于链表没有多余操作反而效率会高, 因此libevent也是依据情况在链表和时间堆直接进行选择的.

- 时间轮 : 你可以理解为这是一个环状的哈希表, 每收到一次定时信号就触发环上的一块, 轮转触发.

- 时间堆 : 这就是一个小根堆, 你甚至可以直接用C++的priority_queue来实现这个时间堆, 其插入效率O(lgn), 删除和执行都是O(1), 在理论上确实优于链表.

----

## Libevent --- 高性能I/O框架库

其实就是一个对我们之前学的I/O复用函数和信号和定时器进行分装的一个库.

它实现了 : 统一事件源 / 可移植性 / 对并发编程的支持.

使用方法和epoll有类似的地方, 但是简化了大量的步骤, 并且可以用非常接近的使用方法设置IO事件/信号事件/定时器事件的回调函数.

- event_base_new(); 

  用于创建一个event_base对象, 你可以理解为这就是一个Reactor实例(基于IO复用的事件处理器).

- event_new(...) 

  ```cpp
  struct event* event_new(struct event_base *base,			// 对应的Reactor实例
                          evutil_socket_t fd,					// 对应事件的文件描述符
                          int events,							// 要注册的事件
                          event_callback_fn callback,			// 事件回调函数
                          void *arg);							// 事件回调函数需要的参数
  ```

  这个函数用于注册事件,  三种事件都可以在这个函数中处理 : 

  - fd : 文件描述符, IO事件就是对应socket, 信号事件是对应信号枚举, 定时器事件设置为-1.

  - events : 主要用于描述事件

    `EV_READ`：表示关注文件描述符上的读事件。

    `EV_WRITE`：表示关注文件描述符上的写事件。

    `EV_SIGNAL`：表示关注特定信号事件。

    `EV_TIMEOUT`：表示关注超时事件（定时器）。

    `EV_PERSIST`：表示该事件在触发后不会自动移除，必须手动移除事件。

    `EV_ET`：表示使用边缘触发模式（Edge Triggered）。

  - callback :  需要放入一个event_callback_fn类型的回调函数.

    ```cpp
    void(*回调函数名)(evutil_socket_t,short,void*arg);  // 所有回调函数形式必须是这样
    ```

  - arg : 用于存放callback需要的参数, 你可以和线程创建相类比.

- event_add(...)

  ```cpp
  int event_add(struct event *ev, const struct timeval *tv);
  ```

  这个函数用于激活base中的这个事件, event_new负责注册事件, 这个负责激活事件.

  - ev : 用event_new构建出来的事件处理器.
  - tv : 一个时间参数, IO和信号填NULL就行, 定时器事件需要在这里填入所确定的延时.

- event_base_dispatch(base); 

  这个函数就是触发事件处理器开始循环监视的参数, 进程将阻塞在这里.

-  event_free(struct event *ev); 

  释放事件结构体.

- event_base_free(struct event_base *base);

  释放事件处理器结构体.

还要注意的是这里的事件被event_new出来并没有被激活, 只有在event_add后才算被激活, 只有激活的事件才会在event_base_dispatch中被处理, 另外如果没有给事件设置`EV_PERSIST`属性, 事件在触发一次后就会自动被删除, 必须重新add, 但是如果有这个属性, 那么在触发后会依旧处于激活状态, 除非手动event_del.