---
title : Muduo库源码剖析(6) TcpServer
date: 2025.4.23 09:22:00
tags: [Muduo]
---

> TcpServer类详解

TcpServer将会作为Muduo库对外开放的核心类, 其提供接口开启服务器并设置设置回调函数与线程数量.

我们可以先预测一下TcpServer将要实现的功能 : 

- 构造Acceptor并控制listen决定开始监听的时机.
- 构造EventLoopThreadPool并开辟设置的线程数量.
- 处理Acceptor监听到的每个connfd, 构建对应的TcpConnection, 并把该连接保存下来.
- 对外提供开始监听, 设置回调, 设置线程数量等接口.

```cpp
// TcpServer.h
#pragma once

#include "EventLoop.h"
#include "EventLoopThreadPool.h"
#include "Accept.h"
#include "InetAddress.h"
#include "UnCopyable.h"
#include "Callbacks.h"
#include "TcpConnection.h"
#include "Buffer.h"
#include "Logger.h"

#include <atomic>
#include <unordered_map>

class TcpServer : UnCopyable
{
public:
    using ThreadInitCallback = std::function<void(EventLoop *)>;

    enum Option // 表明对端口是否可重用
    {
        kNoReusePort,
        kReusePort,
    };

    TcpServer(EventLoop *loop, const InetAddress &listenAddr, const std::string name, Option option = kNoReusePort);
    ~TcpServer();

    void setThreadInitcallback(const ThreadInitCallback &cb) { _threadInitCallback = cb; }
    void setConnectionCallback(const ConnectionCallback &cb) { _connectionCallback = cb; }
    void setMessageCallback(const MessageCallback &cb) { _messageCallback = cb; }
    void setWriteCommpleteCallback(const WriteCompleteCallback &cb) { _writeCompleteCallback = cb; }

    void setThreadNum(int numThreads) { _threadPool->setThreadNum(numThreads); }

    // 开启服务器监听
    void start();

private:
    void newConnection(int sockfd, const InetAddress &peerAddr);
    void removeConnection(const TcpConnectionPtr &conn);
    void removeConnectionInLoop(const TcpConnectionPtr &conn);

    using ConnectionMap = std::unordered_map<std::string, TcpConnectionPtr>;

    EventLoop *_mainloop;
    const std::string _ipPort;
    const std::string _name;

    std::unique_ptr<Acceptor> _acceptor;
    std::shared_ptr<EventLoopThreadPool> _threadPool; // one loop per thread

    ConnectionCallback _connectionCallback;
    MessageCallback _messageCallback;
    WriteCompleteCallback _writeCompleteCallback;

    ThreadInitCallback _threadInitCallback;

    std::atomic_int _started;

    int _nextConnId;
    ConnectionMap _connections;
};
```

我们先来看成员变量 : 

- _mainloop : 这个mainloop是由用户传入的, 用户会决定何时调用`loop.loop();`来开启循环.
- _acceptor : 维护listensocketfd对新连接进行监听.
- _threadPool : 维护线程池提供subloop的指针, 在建立TcpConnection时为其轮询挑提供subloop.
- 各类回调函数 : 这里主要是用户提供给TcpConnection建立时设置的各种回调.
- _connections : 维护所有建立的连接.

```cpp
// TcpServer.cpp
#include "TcpServer.h"
#include "Logger.h"

#include <strings.h>

static EventLoop *CheckLoopNotNull(EventLoop *loop)
{
    if (loop == nullptr)
        LOG_FATAL("%s:%s:%d mainLoop is null!", __FILE__, __FUNCTION__, __LINE__);
    return loop;
}

TcpServer::TcpServer(EventLoop *loop, const InetAddress &listenAddr, const std::string name, Option option)
    : _mainloop(CheckLoopNotNull(loop))
    , _ipPort(listenAddr.toIpPort())
    , _name(name)
    , _acceptor(new Acceptor(loop, listenAddr, option == kReusePort))
    , _threadPool(new EventLoopThreadPool(loop, name))
    , _connectionCallback()
    , _messageCallback()
    , _nextConnId(1)
    , _started(0)
{
    // 当有新用户连接时, 会执行newConnection
    _acceptor->setNewConnectionCallback(std::bind(&TcpServer::newConnection, this,
          std::placeholders::_1, std::placeholders::_2));
}

TcpServer::~TcpServer()
{
    for (auto &item : _connections)
    {
        TcpConnectionPtr conn(item.second); // 局部强智能指针对象会自动释放
        item.second.reset();                // 原map中放弃对强指针的使用

        conn->getLoop()->runInLoop(std::bind(&TcpConnection::connectDestoryed, conn));
    }
}

void TcpServer::start()
{
    if (_started++ == 0) // 防止被重复启动多次
    {
        _threadPool->start(_threadInitCallback);
        _mainloop->runInLoop(std::bind(&Acceptor::listen, _acceptor.get()));
    }
}

// 在TcpServer中具体是轮询找到subLoop, 唤醒该loop
// 把sockfd封装成channel加入到subLoop中
void TcpServer::newConnection(int sockfd, const InetAddress &peerAddr)
{
    EventLoop *subLoop = _threadPool->getNextLoop();
    char buf[64] = {0};
    snprintf(buf, sizeof buf, "-%s#%d", _ipPort.c_str(), _nextConnId);
    ++_nextConnId;
    std::string connName = _name + buf;
    LOG_INFO("TcpServer::newConnection [%s] - new connection [%s] from %s \n",
             _name.c_str(), connName.c_str(), peerAddr.toIpPort().c_str());
    // 通过sockfd直接获取绑定的ip+port
    sockaddr_in local;
    bzero(&local, sizeof local);
    socklen_t addrlen = sizeof local;
    if (getsockname(sockfd, (sockaddr *)&local, &addrlen) < 0)
        LOG_ERROR("sockets::getLocalAddr");

    InetAddress localAddr(local);

    // 根据连接成功的sockfd, 创建TcpConnection连接对象
    TcpConnectionPtr conn(new TcpConnection(subLoop, connName, sockfd, localAddr, peerAddr));
    // 存储连接名字与对应连接的映射
    _connections[connName] = conn;
    // 下面的回调都是用户设置给TcpServer的
    conn->setConnectionCallback(_connectionCallback);
    conn->setMessageCallback(_messageCallback);
    conn->setWriteCompleteCallback(_writeCompleteCallback);
    // 设置了如何关闭连接的回调
    conn->setCloseCallback(std::bind(&TcpServer::removeConnection, this, std::placeholders::_1));
    // 直接调用TcpConnection::connectEstablished
    // 代表连接建立成功
    subLoop->runInLoop(std::bind(&TcpConnection::connectEstablished, conn));
}

void TcpServer::removeConnection(const TcpConnectionPtr &conn)
{
    _mainloop->runInLoop(std::bind(&TcpServer::removeConnectionInLoop, this, conn));
}

void TcpServer::removeConnectionInLoop(const TcpConnectionPtr &conn)
{
    LOG_INFO("TcpServer::removeConnectionInLoop [%s] - connection %s\n",
             _name.c_str(), conn->name().c_str());

    _connections.erase(conn->name());
    EventLoop *subloop = conn->getLoop();
    subloop->queueInLoop(std::bind(&TcpConnection::connectDestoryed, conn));
}
```

通过源文件来分析成员函数 : 

- 构造函数 : 

  接收loop, ip端口, 服务器名, 利用接收到的loop和ip端口直接构造_acceptor, 利用接收到的loop和name直接构造ThreadPool. 这里为 _acceptor中设置了其新连接建立回调函数, 这个函数会在listensocketfd读事件触发时被调用, 回调函数newConnection是TcpServer的核心函数, 我们将会再后面着重讲解.

- 析构函数 : 

  这里就是遍历_connections对每个连接进行销毁, 将每个智能指针做完局部变量取出再让原map放弃对该指针的使用, 这样调用对应的connectDestoryed后就会离开作用域自动析构.

- start : 

  调用_threadPool的start, 让其构造出多个线程备用. 调用 _acceptor的listen, 开启对listensocketf的监听.

- newConnection :

  核心函数, 在_acceptor接收到新连接后调用, 其从 _threadPool中轮询取出一个工作线程, 再将自身的地址取出, 并以此构造出对应的TcpConnection, 然后将用户设置的回调函数再设置到TcpConnection中, 一切设置完毕后, 调用connectEstablished注册其内部 _channel中的读事件以真正开启对socket读事件的监听.

- removeConnection / removeConnectionInLoop : 

  先将该连接从_connections中移除,再去调用connectDestoryed.

  

  

  

  

  

  













