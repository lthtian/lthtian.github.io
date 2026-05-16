---
title: HTTP/1
date: 2025-7-20 17:00:00
tags: [HTTP]
---

## HTTP/1.0

短连接(非持久性连接)

每次HTTP请求都要创建一个新的TCP连接, 响应完就关闭连接.

---

## HTTP/1.1

长连接, 使用最广泛的HTTP协议

### keep-alive : 持久连接

`Connection: keep-alive` : 表示复用已有的TCP连接连续发送多个请求, 不断开当前的TCP连接.

`Connection: close` : 表示想确实关闭连接.

### 分块传输编码(Chunked Transfer Encoding)

HTTP/1.1的重要功能模块, 其核心功能在于允许**不知道总内容长度**的前提下, 将响应内容**一块一块发给客户端**.

其赋予了HTTP请求**实时性**, 也就是说不必在发送前就要确定全部要发送的内容, 而是可以有一点发一点, 服务器持续发送, 客户端持续接收, 这对某些实时生成的信息的发送有很大帮助, 比如日志, 动态渲染, 聊天等等.

先看一条chunked的响应是怎样的 : 

```http
HTTP/1.1 200 OK
Transfer-Encoding: chunked
Content-Type: text/plain

5\r\n
Hello\r\n
6\r\n
 world\r\n
0\r\n
\r\n
```

- 首先我们不需要填写`Content-Length`这一属性, 因为我们本身就不确定长度.

- 我们需要添加`Transfer-Encoding: chunked`, 该字段表明我们是chunked响应, 如果客户端有针对正常响应和chunked响应进行分类处理, 就会根据此字段选择合适的处理方式.

- 一个check的结构如下 : 

  ```http
  <chunk-size>\r\n
  <chunk-data>\r\n
  ```

  我们可以不断发送这样的结构让客户端持续接收, 直到我们想结束这次响应, 我们可以将chunk-size设置为0, 发送如下字段表示结束 : 

  ```http
  0\r\n
  \r\n
  ```

也就是说我们在服务端自己决定什么时候开始响应, 响应什么, 什么时候结束响应, 就像下面 : 

```cpp
// 开始响应, 先发送5个字节
HTTP/1.1 200 OK
Transfer-Encoding: chunked
Content-Type: text/plain

5\r\n
Hello\r\n
    
// 等一会, 再发送6个字节
6\r\n
 world\r\n
    
// 再等一会, 确定没有后结束响应
0\r\n
\r\n
```

类比到日志流, 有新日志我们可以先开始响应发出去, 然后循环等待新的日志生成, 我们再发送出去. 这样实现的效果是 : 客户端只要接收到一块就可以进行处理并呈现在界面上, 但响应只要没有结束, 我们就可以持续发送并让客户端实时接收.

因此这样的客户端的解析器应拥有什么功能?

- 每个chunk模块的循环读取功能, 可以将每个chunk模块取出.
- 利用buf解决TCP粘包问题, 毕竟还是依赖于TCP.

下面给出一个解析器模板 : 

```cpp
#include <iostream>
#include <string>
#include <sstream>
#include <cstring>
#include <sys/socket.h>
#include <unistd.h>
#include <netinet/in.h>
#include <arpa/inet.h>

enum class ParseState {
    ReadingChunkSize,
    ReadingChunkData,
    ReadingChunkCRLF,
    Done
};

class ChunkedParser {
public:
    ChunkedParser() : state(ParseState::ReadingChunkSize), chunkSize(0) {}

    void feed(const std::string& data) {
        buffer += data;
        parse();
    }

    bool isFinished() const {
        return state == ParseState::Done;
    }

private:
    std::string buffer;
    ParseState state;
    size_t chunkSize;

    void parse() {
        while (true) {
            if (state == ParseState::ReadingChunkSize) {
                size_t pos = buffer.find("\r\n");
                if (pos == std::string::npos) return;  // incomplete line
                std::string sizeStr = buffer.substr(0, pos);
                std::stringstream ss;
                ss << std::hex << sizeStr;
                ss >> chunkSize;
                buffer.erase(0, pos + 2);
                if (chunkSize == 0) {
                    state = ParseState::Done;
                    std::cout << "[Parser] Reached end of chunked stream.\n";
                    return;
                }
                state = ParseState::ReadingChunkData;
            }

            if (state == ParseState::ReadingChunkData) {
                if (buffer.size() < chunkSize) return;  // wait for more data
                std::string chunk = buffer.substr(0, chunkSize);
                std::cout << "[Chunk] " << chunk << "\n";
                buffer.erase(0, chunkSize);
                state = ParseState::ReadingChunkCRLF;
            }

            if (state == ParseState::ReadingChunkCRLF) {
                if (buffer.size() < 2) return;
                if (buffer.substr(0, 2) != "\r\n") {
                    std::cerr << "[Error] Expected \\r\\n after chunk data.\n";
                    state = ParseState::Done;
                    return;
                }
                buffer.erase(0, 2);
                state = ParseState::ReadingChunkSize;
            }
        }
    }
};
```

- 另外需要注意的一点是chunked模式是会长时间占用一个TCP连接的, 使用期间是不能穿插其他信息发送的, 因此相对更适合发送**类型单一且不连续**的信息和**极端要求实时性**的信息.

### 缓存控制机制

简单来说就是你可以设置一些选项如`Cache-Control`, 来**告知客户端你的响应内容可以被怎样缓存, 缓存多久**. 在正常的浏览器一般都会遵从服务器的决定, 在部分情况浏览器也会进行调优, 这些选项是否被执行都是非强制的, 主导权在客户端方面.

对于缓存的理解相对简单, 就是浏览器或其他客户端可以把从服务器得到的响应资源缓存下来, 在下一次访问相同目标时就会先从缓存中读取, 可以**降低服务器的压力**.

我们的缓存选项就是对客户方的缓存行为进行指导, 是否遵从主权在于客户方.

下面是`Cache-Control`字段的各种指令 : 

| 指令               | 说明                                                |
| ------------------ | --------------------------------------------------- |
| `public`           | 可以被任何缓存（包括中间代理）缓存                  |
| `private`          | 只能被客户端缓存，禁止中间代理缓存                  |
| `no-cache`         | **不代表不能缓存**，而是每次使用前必须协商验证      |
| `no-store`         | 不允许缓存任何内容（如银行、支付页面）              |
| `max-age=秒`       | 缓存的最大有效时间，超过就需要验证                  |
| `s-maxage=秒`      | 专门给共享缓存（CDN、代理）用，优先级高于 `max-age` |
| `must-revalidate`  | 缓存过期后必须向服务器验证，不能使用过期内容        |
| `proxy-revalidate` | 类似于 `must-revalidate`，但仅针对代理服务器        |

### 虚拟主机支持

简单来说就是增加了新报头`Host`, 可以使**一个服务器提供多个服务(多个网站)**, 多个域名可以共享一个服务器.

在HTTP/1.0, HTTP请求发送的目标就是我们Tcp连接到的那个ip:port, 但是在HTTP/1.1中我们可以利用Nginx监听这个端口, 再由nginx根据我们`Host`中写入的域名选择正确的路径, 使得相同的地址因为不同的域名可以导向不同的服务, 实现**“路径级别”的路由**.

在HTTP/1.1中, 所有请求中都要带`Host`字段.

下面是一个简单的http请求 : 

```bash
http://www.example.com/index.html
```

浏览器会将其转换成一下的http请求 : 

```bash
GET /index.html HTTP/1.1
Host: www.example.com
```

当浏览器通过DNS找到对应地址后, 我们假定这是一个nginx代理, 其会取出我们的Host字段分析再给出我们正确的路径 : 

```nginx
server {
    listen 80;
    server_name www.example.com;
    root /var/www/example;
}
```

结合请求路径`/index.html`, 就可以得到正确路径`/var/www/example/index.html`, 服务器会将该路径下的文件发送给客户.

`Host`字段可以不用, 但是在需要服务器搭载多个服务的情况下可以发挥很大的作用.

### 断点续传

`Range` / `Content-Range` : 

可以在报头中就声明要求获取文件的哪个字节段.

### 内容压缩

`Content-Encoding` :

可以在报头中声明本次发送的内容被怎样的方式压缩.

### 局限性

- 队头阻塞 : 一个连接只能同时处理一个请求, 只可串行化.
- 为了实现并发只能开多个TCP连接.
- 报头冗余字段过多, 效率低.

