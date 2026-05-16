---
title: Muduo库源码剖析(4) Acceptor
date: 2025-4-17 10:13:00
tags: [Muduo]
---

> Socket + Acceptor 详解

本章我们将学习Socket类和Acceptor类, 首先应当明确其在Muduo库中的职责所在 : 

- Socket就是对原生socketAPI的封装, 供Acceptor使用. 

- Acceptor简单来说是用来处理新连接的建立的. 我们来认识一下Acceptor的调用流程

  TcpServer中会维护一个Acceptor作为成员变量, 由TcpServer向Acceptor设置建立新连接的回调函数, Acceptor则内含一个Socket和一个Channel, 其利用Socket维护listensocketfd, 控制listen的时机, 也利用Channel让Poller帮自己监听listensocketfd上的读事件, 设置的读事件回调就会调用accept获取新连接的connfd, 然后利用得到的connfd去调用TcpServer传入的回调函数, 让TcpServer帮自己处理新连接事务.

## Socket

```cpp
// Socket.h
#pragma once

#include "UnCopyable.h"
#include "InetAddress.h"

class Socket : UnCopyable
{
public:
    explicit Socket(int sockfd) : _sockfd(sockfd) {}
    ~Socket();

    int fd() const { return _sockfd; }
    void bindAddress(const InetAddress &localaddr);
    void listen();
    int accept(InetAddress *peeraddr);

    void shutdownWrite();
    void setTcpNoDelay(bool on);
    void setReuseAddr(bool on);
    void setReusePort(bool on);
    void setKeepAlive(bool on);

public:
    const int _sockfd;
};
```

```cpp
// Socket.cpp
#include "Socket.h"
#include "Logger.h"

#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <strings.h>
#include <netinet/tcp.h>

Socket::~Socket()
{
    ::close(_sockfd);
}

void Socket::bindAddress(const InetAddress &localaddr)
{
    if (0 != ::bind(_sockfd, (sockaddr *)localaddr.getSockAddr(), sizeof(sockaddr_in)))
    {
        LOG_FATAL("bind sockfd:%d fail \n", _sockfd);
    }
}

void Socket::listen()
{
    if (0 != ::listen(_sockfd, 1024))
    {
        LOG_FATAL("listen sockfd:%d fail \n", _sockfd);
    }
}

int Socket::accept(InetAddress *peeraddr)
{
    sockaddr_in addr;
    bzero(&addr, sizeof addr);
    socklen_t len(sizeof addr);
    // accept4可以直接给接受到的sockfd设置选项(非阻塞)
    int connfd = ::accept4(_sockfd, (sockaddr *)&addr, &len, SOCK_CLOEXEC | SOCK_NONBLOCK);
    if (connfd >= 0)
    {
        peeraddr->setSockAddr(addr);
    }
    return connfd;
}

void Socket::shutdownWrite()
{
    ::shutdown(_sockfd, SHUT_WR);
}

void Socket::setTcpNoDelay(bool on)
{
    int op = on ? 1 : 0;
    ::setsockopt(_sockfd, IPPROTO_TCP, TCP_NODELAY, &op, sizeof op);
}

void Socket::setReuseAddr(bool on)
{
    int op = on ? 1 : 0;
    ::setsockopt(_sockfd, SOL_SOCKET, SO_REUSEADDR, &op, sizeof op);
}

void Socket::setReusePort(bool on)
{
    int op = on ? 1 : 0;
    ::setsockopt(_sockfd, SOL_SOCKET, SO_REUSEPORT, &op, sizeof op);
}

void Socket::setKeepAlive(bool on)
{
    int op = on ? 1 : 0;
    ::setsockopt(_sockfd, SOL_SOCKET, SO_KEEPALIVE, &op, sizeof op);
}
```

外部通过socket函数将listensocketfd传入Socket, 将其维护在Socket内, 便于简便的调用bind / listen / accept.

## Acceptor

```cpp
// Acceptor.h
#pragma once

#include "UnCopyable.h"
#include "Channel.h"
#include "Socket.h"
#include "InetAddress.h"

#include <functional>

class EventLoop;

class Acceptor : UnCopyable
{
public:
    using NewConnectionCallback = std::function<void(int sockfd, const InetAddress &)>;

    Acceptor(EventLoop *loop, const InetAddress &listenAddr, bool reuseport);
    ~Acceptor();

    void setNewConnectionCallback(const NewConnectionCallback &cb) { _newConnectionCallback = move(cb); }

    bool listenning() const { return _listenning; }
    void listen();

private:
    void handleRead();

    EventLoop *_loop;		// 用来标注这个Acceptor属于的mainLoop
    Socket _acceptSocket;	// 存储listensocketfd
    Channel _acceptChannel;	// 对listensocketfd进行封装的Channel, 便于注册读事件
    NewConnectionCallback _newConnectionCallback;	// TcpServer给其设置的新连接回调函数
    bool _listenning;	// 是否正在监听
};
```

```cpp
// Acceptor.cpp
#include "Accept.h"
#include "Logger.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>

static int createNonblocking()
{
    int sockfd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (sockfd < 0)
    {
        LOG_FATAL("%s:%s:%d listen socket create error:%d", __FILE__, __FUNCTION__, __LINE__, errno);
    }
    return sockfd;
}

// 创建socket, 封装进Channel, 往当前loop的poller中添加
Acceptor::Acceptor(EventLoop *loop, const InetAddress &listenAddr, bool reuseport)
    : _loop(loop), _acceptSocket(()), _acceptChannel(loop, _acceptSocket.fd()), _listenning(false)
{
    _acceptSocket.setReuseAddr(true);
    if (reuseport)
        _acceptSocket.setReusePort(true);
    _acceptSocket.bindAddress(listenAddr);

    // 一旦有一个新用户的连接, 就需要执行回调, connfd -> channel -> subloop
    // 具体回调由TcpServer给出
    _acceptChannel.setReadCallback(std::bind(&Acceptor::handleRead, this));
}
Acceptor::~Acceptor()
{
    _acceptChannel.disableAll();
    _acceptChannel.remove();
}

void Acceptor::listen()
{
    _listenning = true;
    _acceptSocket.listen();
    _acceptChannel.enableReading(); // 把acceptChannel注册到poller中监听读事件
}

// 在listenfd读事件触发时调用
void Acceptor::handleRead()
{
    InetAddress peerAddr;
    int connfd = _acceptSocket.accept(&peerAddr);
    if (connfd >= 0)
    {
        // 在TcpServer中具体是轮询找到subLoop, 唤醒该loop, 将该sockfd分发到其中
        if (_newConnectionCallback)
            _newConnectionCallback(connfd, peerAddr);
        else
            ::close(connfd);
    }
    else
    {
        LOG_ERROR("%s:%s:%d accept error:%d", __FILE__, __FUNCTION__, __LINE__, errno);
        if (errno == EMFILE)
        {
            LOG_ERROR("%s:%s:%d sockfd reached limit!", __FILE__, __FUNCTION__, __LINE__);
        }
    }
}
```

- createNonblocking : 我们可以看到这个函数在Accept构造函数中被调用, 也就是说在Acceptor构造时会调用该函数构造一个非阻塞的listensocketfd.
- 构造函数 : 首先是调用createNonblocking构造出listensocketfd存入Socket, 随后将listensocketfd封装进Channel, 接下来设置Socket中fd的各种属性并bind, 最后将handleRead读事件回调注册进Channel.
- listen : 该函数控制何时开始监听listensocketfd并注册读事件, 一般由上层TcpServer控制.
- handleRead : listensocketfd封装的Channel将被放到mainLoop的Poller中监听读事件, 而触发的回调就是该函数, handleRead将调用accept获取新连接的connfd, 随后将其传给TcpServer设置的回调函数.

为什么要调用TcpServer的新连接回调呢? 因为Acceptor的职责仅仅在于构造listensocketfd和对新连接及时做出反应并报告给TcpServer, TcpServer才是真正处理新连接的核心, 其拥有的资源远超过Acceptor(例如线程池), 有了这些资源才能真正处理新连接.



by 天目中云
