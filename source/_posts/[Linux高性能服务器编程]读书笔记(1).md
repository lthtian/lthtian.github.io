---
title: Linux高性能服务器编程 读书笔记(1)
date: 2025-2-10
tags: [高性能服务器编程]
---

> **第五章  Linux网络编程基础API**

## 字节序

###  什么是大小端字节序?

这里以32位机举例, 32位机CPU一次可以装载4字节,  那么这4个字节不同的排序方式就对应了不同的字节序 : 

- 大端字节序 : 顺着排, 0x12345678 将被排序为 12  34  56  78.
- 小端字节序 : 逆着排, 0x12345678 将被排序为 78  56  34  12.

### 为什么要分大小端?

其实更多还是因为**历史原因**,  早期都是按照大端字节序来设计的, 因为顺着排更符合人类的阅读习惯, 早期网络协议设计都是按大端设计的, 并且网络协议一旦实施就不好改了, 所以直到现在网络传输的字节序都是大端字节序, 因此大端字节序又称为网络字节序.

后来人们发现小端字节序更符合CPU的运算逻辑, 使用小段字节序编码可以让CPU运行更加高效, 因此之后的主机大都采用小端字节序, 因此小段字节序又称为主机字节序.

```c
unsigned long int htonl(unsigned long int hostlong); // host to network long 
```

以上为long类型端口从主机字节序转为网络字节序的函数.

----

## Socket

### shutdown关闭socket

```cpp
int shutdown(int sockfd, int howto);
```

shoudown类似于进阶版的close, close是直接断开读写, shoudown可以分别关闭读端写端.

howto为选项 : 

- SHUT_RD : 只关闭写端.
- SHUT_WR : 只关闭读端.
- SHUT_RDWR : 双端关闭. 

应用场景 : 半双工实现, 客户端收到EOF可以直接关闭读端, 写端不关闭可以继续处理没有处理完的事务.

其实就是读端和写端都会占用资源, close只能同时释放, showdown可以根据具体情况选择只读不写/只写不读, 提前释放部分资源.

### socket选项

- SO_REUSEADDR : 强制使用处于TIME_WAIT状态的连接占用的socket地址.

  - TIME_WAIT作用 : TCP连接发送的数据可能滞后, 如果崩溃立即重启, 可能接收到旧数据包造成混乱. 

  SO_REUSEADDR作用 : 

  1. 可以避免服务器崩溃后进入TIME_WAIT状态, 配合systemd可以实现快速重启服务.
  2. 支持多个进程同时绑定同一个端口(仅限UDP), 用于视频影音等高并发用多个进程同时处理发送到同一个端口上的信息.

  ```c
  int reuse = 1;  // 表示启用设置
  setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
  ```

- SO_RCVBUF/SO_SNDBUF : 用于修改TCP发送和接收缓冲区的大小.

  缓冲区大小最小为256字节, 大小会按设置的大小的两倍计算.

  ```cpp
  int bufsize = 2000; // 标定新的缓冲区大小
  setsockopt(sockfd, SOL_SOCKET, SO_RCV, &bufsize, sizeof(bufsize))
  ```

---

## 网络信息API

在现实生活中我们习惯**用域名代替IP地址, 用服务名代替端口号**, 使用网络信息API便可以**实现<域名+服务名>到<IP+port>的双向转化**, 便于我们socket等操作的进行. 主要是两大函数`getaddrinfo`和`getnameinfo`, 这两个函数**线程安全并且支持各种地址族和协议类型**, 可以使socket进行动态设置以实现**动态实时处理与跨平台性**.

### getaddrinfo

这个函数可以通过主机名获得IP地址, 通过服务名获得端口号.

```cpp
#include <netdb.h>
#include <sys/types.h>
#include <sys/socket.h>

int getaddrinfo(const char *node,                   // 主机名 / 字符串形式的IP地址
                const char *service,				// 服务名
                const struct addrinfo *hints, 		// 传入一些必要的信息
                struct addrinfo **res				// 存储返回结果, 输出型参数
);

struct addrinfo {
    int              ai_flags;        // 地址信息标志
    int              ai_family;       // 地址族 (AF_INET, AF_INET6 等)
    int              ai_socktype;     // 套接字类型 (SOCK_STREAM, SOCK_DGRAM 等)
    int              ai_protocol;     // 协议类型 (IPPROTO_TCP, IPPROTO_UDP 等), 默认为0即可
    size_t           ai_addrlen;      // 地址长度
    struct sockaddr *ai_addr;         // 指向套接字地址的指针
    char            *ai_canonname;    // 完整主机名
    struct addrinfo *ai_next;         // 下一个地址信息链表
};
```

我们可以利用获取的信息直接建立socket : 

```cpp
struct addrinfo hints, *res;
memset(&hints, 0, sizeof(hints));
hints.ai_family = AF_UNSPEC;   // 支持 IPv4 和 IPv6
hints.ai_socktype = SOCK_STREAM; // TCP

// 获取目标主机的地址信息
int status = getaddrinfo("www.example.com", "http", &hints, &res);
if (status != 0) {
    // 错误处理
    return;
}

// 使用返回的地址信息创建套接字并进行连接
int sockfd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
if (sockfd == -1) {
    // 错误处理
    return;
}

freeaddrinfo(res);
freeaddrinfo(hints);  // addrinfo类型需要释放内存
```

### getnameinfo

通过socket地址返回主机名/服务名, 和getaddrinfo是相反的作用.

```c
int getnameinfo(const struct sockaddr *sa, socklen_t salen, // 目标网络地址结构体
                char *host, size_t hostlen,					// 返回的主机名, 输出型参数
                char *serv, size_t servlen,					// 返回的服务名/端口号, 输出型参数
                int flags									// 确定函数行为
);
```

```cpp
	struct sockaddr_in sa;
    char host[NI_MAXHOST], service[NI_MAXSERV];
    
    // 构造一个IPv4地址，假设是127.0.0.1，端口是80
    sa.sin_family = AF_INET;
    sa.sin_port = htons(80);
    inet_pton(AF_INET, "127.0.0.1", &(sa.sin_addr));

    // 获取主机名和服务名
    int result = getnameinfo((struct sockaddr*)&sa, sizeof(sa),
                             host, NI_MAXHOST, service, NI_MAXSERV, 0);
    if (result == 0) {
        printf("Host: %s\n", host);
        printf("Service: %s\n", service);
    }
```