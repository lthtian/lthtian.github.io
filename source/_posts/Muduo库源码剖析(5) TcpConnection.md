---
title: Muduo库源码剖析(5) TcpConnection
date: 2025.4.21 11:12:00
tags: [Muduo]
---

> Buffer 和 TcpConnection 详解

本章我们将学习Buffer类和其上级类TcpConnection, 先了解两个类的职能 : 

- Buffer

  和通常的缓冲区认知类似, 目的在于提升传入传出的效率, 就是在read中可以提前把数据从内核接收缓冲区中读出, 便于对端再向内核接收缓冲区输入. 在write中可以提前把要写入的数据存进缓冲区, 等待内核发送缓冲区空余.

- TcpConnection

  专门用来维护每条与客户端的连接的类, 也就是对Acceptor中得到的connfd进行封装, 包括其对应的Socket和Channel类. 并且连接也代表了**有连接的建立与断开, 数据的传入与传出等**活动, 这些活动中, 一部分需要**上级设置的回调函数**来处理(例如连接建立断开, 数据传入, 都需要网络库调用者设置), 一部分需要TcpConnection**利用自己手头的资源自行处理**(例如数据传出, 需要调用自己的send函数). 既然与数据的传入传出有关, 其内部也内置Buffer类来优化传入传出的效率.

## Buffer

先看源码 : 

```cpp
// Buffer.h
#pragma once

#include <vector>
#include <string>
#include <sys/uio.h>

class Buffer
{
public:
    static const size_t kCheapPrepend = 8;
    static const size_t kInitialSize = 1024;

    explicit Buffer(size_t initialSize = kInitialSize)
        : _buffer(kCheapPrepend + initialSize), _readerIndex(kCheapPrepend), _writerIndex(kCheapPrepend)
    {
    }

    size_t readableBytes() const { return _writerIndex - _readerIndex; }
    size_t writableBytes() const { return _buffer.size() - _writerIndex; }
    size_t prependableBytes() const { return _readerIndex; }
    // 返回缓冲区中可读区域的起始地址
    const char *peek() const { return begin() + _readerIndex; }

    void retrieve(size_t len)
    {
        if (len < readableBytes())
            _readerIndex += len; // 只读取了可读缓冲区的一部分
        else
            retrieveAll();
    }

    void retrieveAll()
    {
        _readerIndex = _writerIndex = kCheapPrepend; // 全读了, 复位
    }
    // Buffer -> string
    std::string retrieveAllAsString() { return retrieveAsString(readableBytes()); }

    std::string retrieveAsString(size_t len)
    {
        std::string res(peek(), len);
        retrieve(len);
        return res;
    }

    void ensureWriteableBytes(size_t len)
    {
        if (writableBytes() < len)
            makeSpace(len);
    }

    // 向缓冲区中追加数据[data, data + len]
    void append(const char *data, size_t len)
    {
        ensureWriteableBytes(len);
        std::copy(data, data + len, beginWrite());
        _writerIndex += len;
    }

    char *beginWrite() { return begin() + _writerIndex; }
    const char *beginWrite() const { return begin() + _writerIndex; }

    // 从fd上读取数据, Poller工作在LT模式
    // Buffer缓冲区是有大小的, 但从fd上读数据时却不知道tcp数据最终的大小
    ssize_t readFd(int fd, int *saveErrno);
    ssize_t writeFd(int fd, int *saveErrno);

private:
    char *begin() { return &*_buffer.begin(); }
    const char *begin() const { return &*_buffer.begin(); }

    void makeSpace(size_t len)
    {
        // 后面真正可写的 + 前面读出来空余的 < 要求的大小
        if (writableBytes() + _readerIndex < len + kCheapPrepend)
            _buffer.resize(_writerIndex + len);
        else // 如果够, 把后面未读的移到前面, 给后面空出来
        {
            size_t readable = readableBytes();
            std::copy(begin() + _readerIndex, begin() + _writerIndex, begin() + kCheapPrepend);
            _readerIndex = kCheapPrepend;
            _writerIndex = kCheapPrepend + readable;
        }
    }

    std::vector<char> _buffer;
    size_t _readerIndex;
    size_t _writerIndex;
};
```

```cpp
// Buffer.cpp
#include "Buffer.h"
#include <unistd.h>

ssize_t Buffer::readFd(int fd, int *saveErrno)
{
    char extrabuf[65536] = {0}; // 栈上的内存空间 64k
    struct iovec vec[2];
    const size_t writable = writableBytes();
    vec[0].iov_base = begin() + _writerIndex;
    vec[0].iov_len = writable;
    vec[1].iov_base = extrabuf;
    vec[1].iov_len = sizeof extrabuf;

    const int iovcnt = (writable < sizeof extrabuf) ? 2 : 1;
    // 在非连续的区块中依次写入同一个fd传入的信息
    const ssize_t n = ::readv(fd, vec, iovcnt);
    if (n < 0)
        *saveErrno = errno;
    else if (n <= writable) // 已经够了不需要扩容
    {
        _writerIndex += n;
    }
    else // extrabuf中也写入了数据, 需要扩容加进去
    {
        _writerIndex = _buffer.size();
        append(extrabuf, n - writable);
    }
    return n;
}

ssize_t Buffer::writeFd(int fd, int *saveErrno)
{
    int n = ::write(fd, peek(), readableBytes());
    if (n < 0)
    {
        *saveErrno = errno;
    }
    return n;
}
```

先看成员变量 : 

- _buffer : 用vector存储数据, 便于扩容.

- _readerIndex / _writerIndex : 

  这两个参数标定了可读区域和可写区域的大小. 想要理解这两个参数, 需要理解Buffer中对_buffer的划分 : 

  ```cpp
  |<---- prependable ---->|<---- readable ---->|<---- writable ---->|
  |-----------------------|--------------------|--------------------|
  ^                        ^                    ^                     
  begin()           _readerIndex          _writerIndex         
  ```

  - prependable : 前置空余区域, 当我们发送消息时, 如果向要加一些报头之类的信息, 可以便于向其中填入, 在Muduo库中作用不大.
  - readable : 已经有数据存入的部分, 如果当前要读出, 则这部分是可读部分, 如果当前要写入, 则这部分是已填充完毕的区域.
  - writeable : 还没有数据的部分, 如果当前要读入, 则这部分是空余空间, 如果当前要写入, 则这部分是可以继续写入的部分.

  我们可以看出Buffer既可以处理read也可以处理write, 其对应的readable和writeable区域也有不同的作用. 在TcpConnection就封装了两个Buffer, _inputBuffer和 _outputBuffer, 共同处理了缓冲任务.

再看成员函数 :

- readable/writable/prependableBytes : 返回对应区域的字节数大小.

- begin : 返回_buffer的首元素地址.

- peek :  返回缓冲区中可读区域的起始地址.

- makespace :

  扩容函数, 确保_buffer有参数len的大小使write成功, 如果可写的空间不够就扩容, 够用就经过调整把前面的空余和后面的空余合并一块放在后面.

- retrieve / retrieveAll : 

​	这个函数一般会在下面的retrieveAsString中使用, 或是调用readfd/writefd后使用, 用来进行两个Index的置位.

- retrieveAsString / retrieveAllAsString : 

  **从_buffer中读出数据的函数**, 这个函数会将可读区域中len长度的数据当作string读出来, 并在调用retrieve后返回, 通常被客户用来从Buffer中直接读出接收到的数据.

- ensureWriteableBytes : 对makeSpace的调用.

- append :

  **从_buffer中追加数据的函数**, 向缓冲区中追加数据[data, data + len], 空间不够时会调用ensureWriteableBytes.

- readFd : 

  核心函数, 目的是**高效从一个fd上读取传来的数据到 _buffer 中**, 其高效在于使用到了readv函数, 这个函数不细讲, 不知道可以去查, 简单来说就是就是其实现了**在非连续的区块中依次写入同一个fd传入的信息**, 函数中划分了两块区域, 一块是 _buffer的可写区域, 一块是我们在栈上开辟的64K临时空间, readv可以实现先向可写区域中写, 可写区域写满了再读入我们开辟的临时空间, 读完后加入临时空间有读入, 我们再用append加进去就行, 这样实现了灵活应对读入不同大小的情况.

- writeFd : 

  这个就比较简单了, 因为网络输出缓冲区就一个, 就不需要考虑writev的使用, 直接调用write从Buffer中将有数据的部分发送出去即可.

## TcpConnection

> 专门用来维护每条与客户端的连接的类, 也就是对Acceptor中得到的connfd进行封装, 包括其对应的Socket和Channel类. 并且连接也代表了**有连接的建立与断开, 数据的传入与传出等**活动, 这些活动中, 一部分需要**上级设置的回调函数**来处理(例如连接建立断开, 数据传入, 都需要网络库调用者设置), 一部分需要TcpConnection**利用自己手头的资源自行处理**(例如数据传出, 需要调用自己的send函数). 既然与数据的传入传出有关, 其内部也内置Buffer类来优化传入传出的效率.

通过上文我们的对TcpConnection的描述, 我们可以将其分为以下几个功能模块 : 

- 构造 / 析构函数
- TcpServer对TcpConnection设置连接建立回调, 断开回调, 消息回调等, 正式开启/关闭连接.
- TcpConnection对自己负责的connfd相关联的Channel类设置读/写/关闭/错误回调.
- 用户发送信息所调用的send函数, 手动关闭连接所调用的shutdown函数.

让我们先分析头文件 : 

```cpp
#pragma once
#include "UnCopyable.h"
#include "InetAddress.h"
#include "Callbacks.h"
#include "Buffer.h"
#include "Timestamp.h"

#include <memory>
#include <string>
#include <atomic>
#include <string>

class Channel;
class EventLoop;
class Socket;

// TcpServer -> Acceptor -> 新连接 -> accept得到connfd -> 打包回调到TcpConnection
// -> 回调设置给Channel -> Poller -> Channel的回调操作

// 各种回调函数 : 用户 -> TcpServer -> TcpConnection -> Channel

class TcpConnection : UnCopyable, public std::enable_shared_from_this<TcpConnection>
{
public:
    TcpConnection(EventLoop *loop, const std::string name, int sockfd, const InetAddress &LocalAddr, const InetAddress &peerAddr);
    ~TcpConnection();

    EventLoop *getLoop() const { return _loop; }
    const std::string &name() const { return _name; }
    const InetAddress &localAddress() const { return _localAddr; }
    const InetAddress &peerAddress() const { return _peerAddr; }

    bool connected() const { return _state == kConnected; }

    void setConnectionCallback(const ConnectionCallback &cb) { _connectionCallback = cb; }
    void setMessageCallback(const MessageCallback &cb) { _messageCallback = cb; }
    void setWriteCompleteCallback(const WriteCompleteCallback &cb) { _writeCompleteCallback = cb; }
    void setHighWaterMarkCallback(const HighWaterMarkCallback &cb) { _highWaterMarkCallback = cb; }
    void setCloseCallback(const CloseCallback &cb) { _closeCallback = cb; }

    void connectEstablished(); // 连接建立
    void connectDestoryed();   // 连接销毁

    // 发送数据
    void send(std::string buf);
    // 关闭Tcp连接
    void shutdown();

private:
    void handleRead(Timestamp receiveTime);
    void handleWrite();
    void handleClose();
    void handleError();

    void sendInLoop(const void *message, size_t len);
    void shutdownInLoop();

    enum StateE
    {
        kDisconnected,
        kConnecting,
        kConnected,
        kDisconnecting
    };

    void setState(StateE state) { _state = state; }

    EventLoop *_loop; // 这里只会是subLoop
    const std::string _name;
    std::atomic_int _state;
    bool _reading;
    // 管理的_socket / _channel
    std::unique_ptr<Socket> _socket;
    std::unique_ptr<Channel> _channel;

    const InetAddress _localAddr; // 主机addr
    const InetAddress _peerAddr;  // 对端客户addr
    // 回调
    ConnectionCallback _connectionCallback;
    MessageCallback _messageCallback;
    WriteCompleteCallback _writeCompleteCallback;
    HighWaterMarkCallback _highWaterMarkCallback;
    CloseCallback _closeCallback;
    size_t _highWaterMark;
    // 缓冲区
    Buffer _inputBuffer;
    Buffer _outputBuffer;
};
```

这里先介绍一下公开继承enable_shared_from_this的作用 : 

其可以让继承其的类的成员函数可以调用shared_from_this()函数, 作用是返回当前类对象的智能指针封装, 也就是把this指针包到智能指针中再传出来, 所以使用他的原因主要是TcpConnection对象可能随使销毁, 传出的this指针随时可能失效, 但如果我们本身传出的就是智能指针, 就可以有效防止提前销毁.

了解一下成员变量 : 

- _loop : 这里保存自己所在subLoop的指针, 是为了将需要调用的函数加入到事件循环中.
- _state : 用来记录一个连接的各种状态, 状态同一时间只能有一种, 所以是atomic类型.
- _socket / _channel : 将Acceptor接收到的connfd封装为Socket和Channel.
- ...Callback : 各种有关于连接的事件回调.
- _inputBuffer / _outputBuffer : 分别处理TcpConnection的消息接受和发送.

```cpp
#include "TcpConnection.h"
#include "Logger.h"
#include "Socket.h"
#include "Channel.h"
#include "EventLoop.h"

#include <memory>
#include <unistd.h>

// 为什么用static可防止名字冲突
static EventLoop *CheckLoopNotNull(EventLoop *loop)
{
    if (loop == nullptr)
        LOG_FATAL("%s:%s:%d mainLoop is null!", __FILE__, __FUNCTION__, __LINE__);
    return loop;
}

TcpConnection::TcpConnection(EventLoop *loop, const std::string name, int sockfd, const InetAddress &localAddr, const InetAddress &peerAddr)
    : _loop(CheckLoopNotNull(loop)), _name(name), _state(kConnecting), _reading(true), _socket(new Socket(sockfd)), _channel(new Channel(loop, sockfd)), _localAddr(localAddr), _peerAddr(peerAddr), _highWaterMark(64 * 1024 * 1024) // 64MB
{
    // 把回调设置进channel, TcpConnection有一套自己的回调函数
    _channel->setReadCallback(std::bind(&TcpConnection::handleRead, this, std::placeholders::_1));
    _channel->setWriteCallback(std::bind(&TcpConnection::handleWrite, this));
    _channel->setCloseCallback(std::bind(&TcpConnection::handleClose, this));
    _channel->setErrorCallback(std::bind(&TcpConnection::handleError, this));

    LOG_INFO("TcpConnection::ctor[%s] at fd=%d\n", _name.c_str(), sockfd);
    _socket->setKeepAlive(true);
}

TcpConnection::~TcpConnection()
{
    LOG_INFO("Tcpconnection::dtor[%s] at fd=%d state=%d \n", _name.c_str(), _channel->fd(), (int)_state);
}

void TcpConnection::handleRead(Timestamp receiveTime)
{
    int savedErrno = 0;
    ssize_t n = _inputBuffer.readFd(_channel->fd(), &savedErrno);
    if (n > 0)
    {
        // 有可读事件发生, 调用用户传入的回调操作
        _messageCallback(shared_from_this(), &_inputBuffer, receiveTime);
    }
    else if (n == 0)
    {
        handleClose();
    }
    else
    {
        errno = savedErrno;
        LOG_ERROR("TcpConnection::handleRead");
        handleError();
    }
}

void TcpConnection::handleWrite()
{
    if (_channel->isWriting())
    {
        int savedErrno = 0;
        ssize_t n = _outputBuffer.writeFd(_channel->fd(), &savedErrno);
        if (n > 0)
        {
            _outputBuffer.retrieve(n);
            if (_outputBuffer.readableBytes() == 0) // 已经发送完成
            {
                _channel->disableWriting();
                if (_writeCompleteCallback)
                {
                    _loop->queueInLoop(std::bind(_writeCompleteCallback, shared_from_this()));
                }
                if (_state == kDisconnecting)
                {
                    shutdownInLoop();
                }
            }
        }
        else
            LOG_ERROR("TcpConnection::handleWrite");
    }
    else
        LOG_ERROR("TcpConnection fd=%d is down, no more writing", _channel->fd());
}

void TcpConnection::handleClose()
{
    LOG_INFO("fd=%d state=%d \n", _channel->fd(), (int)_state);
    setState(kDisconnected);
    _channel->disableAll();

    // 获取当前的Connention对象
    TcpConnectionPtr connPtr(shared_from_this());
    _connectionCallback(connPtr);
    _closeCallback(connPtr); // 关闭连接, 执行TcpServer::removeConnection
}

void TcpConnection::handleError()
{
    int op;
    socklen_t optlen = sizeof op;
    int err = 0;
    if (::getsockopt(_channel->fd(), SOL_SOCKET, SO_ERROR, &op, &optlen) < 0)
    {
        err = errno;
    }
    else
        err = op;

    LOG_ERROR("TcpConnection::handleErrno name:%s - SO_ERROR:%d \n", _name.c_str(), err);
}

void TcpConnection::connectEstablished() // 连接建立
{
    setState(kConnected);
    // 把自己的指针传给负责的channel, 让其知晓自己的存在状态
    // 防止上层TcpConnection析构后下层channel依旧运行
    // 根本原因是TcpConnection要给到用户手里, 不确定何时析构
    _channel->tie(shared_from_this());
    _channel->enableReading(); // 注册Channel读事件

    // 新连接已经建立, 执行连接建立回调
    _connectionCallback(shared_from_this());
}

void TcpConnection::connectDestoryed() // 连接销毁
{
    if (_state == kConnected)
    {
        setState(kDisconnected);
        _channel->disableAll();
        _connectionCallback(shared_from_this());
    }
    _channel->remove();
}

// 发送数据
void TcpConnection::send(const std::string buf)
{
    if (_state == kConnected)
    {
        if (_loop->isInLoopThread())
        {
            sendInLoop(buf.c_str(), buf.size());
        }
        else
        {
            _loop->runInLoop(std::bind(&TcpConnection::sendInLoop, this, buf.c_str(), buf.size()));
        }
    }
}

// 发送数据时, 应用写的快, 而内核发送数据慢, 需要把待发送的数据写入缓冲区并设置水位回调
// 该函数实现对写事件的缓冲
void TcpConnection::sendInLoop(const void *data, size_t len)
{
    ssize_t nwrite = 0;
    size_t remaining = len;
    bool faultError = false;
    // 之前调用过shutdown
    if (_state == kDisconnected)
    {
        LOG_ERROR("disconnected, give up writing!");
        return;
    }
    // _channel第一次开始写数据, 并且缓冲区没有待发送数据
    if (!_channel->isWriting() && _outputBuffer.readableBytes() == 0)
    {
        nwrite = ::write(_channel->fd(), data, len);
        if (nwrite >= 0)
        {
            remaining = len - nwrite;
            // 如果已经直接发送完了, 不需要缓冲, 如果有设置写入完成回调就触发
            if (remaining == 0 && _writeCompleteCallback)
                _loop->queueInLoop(std::bind(_writeCompleteCallback, shared_from_this()));
        }
        else // nwrote < 0
        {
            nwrite = 0;
            if (errno != EWOULDBLOCK)
            {
                LOG_ERROR("TcpConnection::sendInLoop");
                if (errno == EPIPE || errno == ECONNRESET)
                    faultError = true;
            }
        }
    }
    // 一次write并没有一次发送出去, 需要保存到缓冲区
    // 要给channel设置epollout事件, poller发现tcp发送缓冲区有空间
    // 调用writeCallback -> handleWrite, 把发送缓冲区的数据全部发送完成
    if (!faultError && remaining > 0)
    {
        // 目前发送缓冲区剩余的待发送数据长度
        size_t oldlen = _outputBuffer.readableBytes();
        if (oldlen + remaining >= _highWaterMark && oldlen < _highWaterMark && _highWaterMark)
            _loop->queueInLoop(std::bind(_highWaterMarkCallback, shared_from_this(), oldlen + remaining));
        _outputBuffer.append((char *)data + nwrite, remaining);
        if (!_channel->isWriting())
        {
            _channel->enableWriting(); // 注册channel的写事件, 否则poller不会给channel通知EPOLLOUT,
        }
    }
}

// 关闭Tcp连接
void TcpConnection::shutdown()
{
    if (_state == kConnected)
    {
        setState(kDisconnecting);
        _loop->runInLoop(std::bind(&TcpConnection::shutdownInLoop, this));
    }
}

void TcpConnection::shutdownInLoop()
{
    if (!_channel->isWriting()) // 说明发送缓冲区已经全部发送完成
    {
        _socket->shutdownWrite(); // 关闭写端
        // 之后poller会通知channel触发_closeCallback, 会触发TcpConnection中的handleClose
    }
}
```

配合源文件来分析成员函数 : 

- 构造函数 :

  掌握一个不为空的loop指针, 利用传进的connfd构造_socket和 _channel. 随后设置 _channel的读写关闭错误回调, 就像Acceptor对 listensocketfd 设置读事件回调一样, 普通连接connfd四种事件都要关注, 所以我们四种事件都设置回调, 而回调函数分别是下面的handleRead/Write/Colse/Error.

- handleRead :

  当connfd的读事件触发时, 会触发该函数, 向 _inputBuffer中读入数据, 然后调用TcpServer设置的消息回调函数, 这个回调函数中一般会调用retrieveAsString从 _inputBuffer中读出数据然后进行客户希望的处理.

- handleWrite : 

  当connfd的读事件触发时, 说明对端可写, 从_outputBuffer中读出所有或部分向对端写入, 如果全写了, 就取消对 _channel的写事件关心然后调用写完回调(如果有的话); 如果没写完就不做处理.

- handleClose :

  当我们关闭connfd的写端时, 就会默认触发EPOLLHUP事件, 进而调用该函数, 取消_channel对所有事件的关心, 然后调用连接建立/断开回调.

- connectEstablished : 

  这个函数用来开启_channel读事件的关注, 也就是说在这之后就可以读connfd上传来的信息了. 至于为什么单独分出一个函数处理, 原因是在TcpConntion对象在TcpServer中创建后不能直接开启读事件, 还要进行回调函数的设置和数据处理, 在这些准备工作都做完后才可以真正开启读事件.

- connectDestoryed : 

  这个函数用于在最后销毁连接并移除_channel, 属于销毁链路的最后一环, 由TcpServer在合适时机调用, 我们可以在后面的shutdownInLoop中有更深的认识.

- send : 

  这个函数是提供给用户调用的, 所以调用时不一定在当前线程, 所以需要判断是否换线程.

- sendInLoop : 

  前面handleWrite函数是在写事件触发时从_outputBuffer中读取数据, 那么这个函数就是直接发送或将要发送的数据写入 _outputBuffer.

  首先如果_channel第一次开始写数据, 并且缓冲区没有待发送数据, 就直接先写一部分, 最后如果还是没写完, 说明对端接收缓冲区已经满了, 就追加到 _outputBuffer中, 再关注读事件, 那么当对端接收缓冲区可写时就会调用handleWrite从 _outputBuffer中读取数据.

- shutdown : 

  这个函数也是提供给用户调用的, 需要判断换线程.

- shutdownInLoop : 

  这里操作很简单, 关闭connfd写端就行, 主要是了解其中的连锁反应 : 

  关闭写端 -> 触发EPOLLHUP -> _channel调用handleClose -> handleClose调用TcpServer设置的回调函数 -> TcpServer设置的回调函数再调用TcpConnection中的connectDestoryed.

  这样一看这个过程非常繁琐, 其主要是为了让TcpServer可以及时对关闭的连接进行反应并修改内部资源.

