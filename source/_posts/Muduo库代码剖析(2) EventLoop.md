---
title: Muduo库代码剖析(2) EventLoop 
date: 2025-4-15 17:02:00
tags: [Muduo]
---

> EventLoop 详解

EventLoop类似于Reactor模型中的**反应堆**(Reactor)和**事件分发器**(Demultiplex)的合并, 其目的在于高效的接收事件, 并正确分配给对应的事件处理器.

EventLoop中有两类关键的子控件 : **Channel 和 Poller**.

- Channel 即通道, 其负责对单个文件描述符的事件管理, 存储该文件描述符感兴趣的事件与对应回调函数, 该类与EventLoop类联通, EventLoop会将从Poller中得到的发生的事件传给Channel, Channel再调用对应的回调.
- Poller 即轮询器或检测器, 其负责IO复用函数(poll / epoll)的调用, 将从epoll上检测到的事件发生传递给Channel和EventLoop, 如果选用epoll, 其内部会封装epoll系列函数.

- EventLoop 即一个事件循环, 其内部维护了一个事件循环要关心和处理的所有信息.
  - 一个EventLoop包含多个Channel, 维护多个文件描述符的资源.
  - 一个EventLoop包含一个Poller, 使用该轮循器执行核心的IO复用函数.
  - EventLoop负责管理事件循环的开始, 结束, 线程管理与Channel和Poller之间的互动.

---

## Channel

可以先通过头文件来了解其功能 : 

```cpp
#pragma once
#include "UnCopyable.h"
#include "Timestamp.h"
#include <functional>
#include <memory>
class EventLoop;

// 通道, 封装了sockfd和其感兴趣的event, 如EPOLLIN, EPOLLOUT
// 需要和Poller互动, Channel向Poller设置感兴趣的事件, Poller向Channel返回发生的事件

class Channel : UnCopyable
{
public:
    using EventCallback = std::function<void()>;
    using ReadEventCallback = std::function<void(Timestamp)>;

    Channel(EventLoop *Loop, int fd);
    ~Channel();

    // fd得到poller通知以后, 处理事件的函数
    void handleEvent(Timestamp receiveTime);

    // 这个函数暂不解释
    void tie(const std::shared_ptr<void> &);

    int fd() const { return _fd; }
    int events() const { return _events; }
    // Channel本身无法取得发生的事件, 是Poller取得发生的事件设置到Channel中的
    void set_revents(int revt) { _revents = revt; }

    bool isNoneEvent() const { return _events == kNoneEvent; }
    bool isWriting() const { return _events & kWriteEvent; }
    bool isReading() const { return _events & kReadEvent; }
    
    // 设置回调函数对象
    void setReadCallback(ReadEventCallback cb) { _readCallback = std::move(cb); }
    void setWriteCallback(EventCallback cb) { _writeCallback = std::move(cb); }
    void setCloseCallback(EventCallback cb) { _closeCallback = std::move(cb); }
    void setErrorCallback(EventCallback cb) { _errorCallback = std::move(cb); }

    // 设置fd相应的事件状态
    void enableReading() { _events |= kReadEvent, update(); }
    void disableReading() { _events &= ~kReadEvent, update(); }
    void enableWriting() { _events |= kWriteEvent, update(); }
    void disableWriting() { _events &= ~kWriteEvent, update(); }
    void disableAll() { _events = kNoneEvent, update(); }

    int state() { return _state; }
    void set_state(int idx) { _state = idx; }

    // 每个Channel都属于一个EventPool, EventPool可以有多个Channel
    EventLoop *ownerLoop() { return _loop; }
    void remove();

private:
    void update();
    void handleEventWithGuard(Timestamp receiveTime);

    // 表示当前fd的状态
    static const int kNoneEvent;  // 没有对任何事件感兴趣
    static const int kReadEvent;  // 对读事件感兴趣
    static const int kWriteEvent; // 对写事件感兴趣

    EventLoop *_loop; // 事件循环
    const int _fd;    // 监听对象
    int _events;      // 注册fd感兴趣的事件
    int _revents;     // fd上发生的事件
    int _state;

    // 防止回调函数在 Channel 所绑定的对象已析构的情况下仍然被调用
    std::weak_ptr<void> _tie;
    bool _tied;

    // 因为channel通道里可以获知fd发生的具体事件, 所以其负责调用具体的事件回调
    ReadEventCallback _readCallback;
    EventCallback _writeCallback;
    EventCallback _closeCallback;
    EventCallback _errorCallback;
};
```

先从成员变量分析 : 

- _loop : 维护一个loop指针便于通过EventLoop与Poller互动.
- _fd / _events / _revents : 维护的文件描述符, 其上关心的事件, 通过Poller获知的真正发生的事件.
- _state : 这个变量用于表示与Poller互动的状态, 因为Poller中要存储Channel*, 可以通过该变量判断将要采取的行为, 现在不理解也没关系, 后面会见到.
- 各种Callback : Channel会持有各种事件处理的回调函数.

- _tie / _tied : 防止回调函数在 Channel 所绑定的对象已析构的情况下仍然被调用, 这样看可能比较抽象, 在后文配合cpp文件理解.

再看成员函数 ： 

- set_revents : 当Poller监听到有事件发生时, 会先触发该函数给对应Channel设置revents, 可以让之后触发的handleEvent知道要处理哪些事件.
- handleEvent : 当Poller监听到有事件发生时, 会通知EventLoop, EventLoop会调用对应Channel的该函数以执行回调函数.

set_revents 供 Poller 调用, 因为Poller是轮询器, 它的作用是检测状态, 职责是把检测到的状态传递给目标类, 其内部不做任何其他操作. handleEvent 供 EventLoop 调用, 因为其负责事件的分发与调配, 触发回调函数是其的职责, 因此Poller检测到事件发生应当将其提供给EventLoop, 让EventLoop判断是否调用回调函数. 这涉及到职责分配和设计哲学.

- setXXXCallback系列函数 : 提供给EventLoop用来从外部传入各种事件回调函数的事件.
- eable / disable 系列函数 : 确定当前Channel中fd真正关心的事件, 当前不关心的事件就算被设置了也不会被触发.

接下来给出cpp文件, 之后再继续深入解释一些细节 : 

```cpp
#include "Channel.h"
#include "Logger.h"
#include "EventLoop.h"

#include <sys/epoll.h>

const int Channel::kNoneEvent = 0;
const int Channel::kReadEvent = EPOLLIN | EPOLLPRI;
const int Channel::kWriteEvent = EPOLLOUT;

Channel::Channel(EventLoop *Loop, int fd)
    : _loop(Loop), _fd(fd), _events(0), _revents(0), _state(-1), _tied(false)
{
}

Channel::~Channel()
{
}

void Channel::tie(const std::shared_ptr<void> &obj)
{
    _tie = obj;
    _tied = true;
}

void Channel::update()
{
    // 通过channel所属的EventLoop, 调用poller对应的方法, 注册fd的事件
    _loop->updateChannel(this);
}

// 在channel所属的EventLoop中删除该channel
void Channel::remove()
{
    _loop->removeChannel(this);
}

void Channel::handleEvent(Timestamp receiveTime)
{
    if (_tied)
    {
        std::shared_ptr<void> guard = _tie.lock();
        if (guard)
            handleEventWithGuard(receiveTime);
    }
    else
        handleEventWithGuard(receiveTime);
}

// 根据当前设置的事件执行相应的回调操作
void Channel::handleEventWithGuard(Timestamp receiveTime)
{
    LOG_INFO("channle handleEvent revents: %d\n", _revents);
    if ((_revents & EPOLLHUP) && !(_revents & EPOLLIN))
    {
        // 回调不为空则执行回调
        if (_closeCallback)
            _closeCallback();
    }

    if (_revents & EPOLLERR)
    {
        if (_errorCallback)
            _errorCallback();
    }

    if (_revents & EPOLLOUT)
    {
        if (_writeCallback)
            _writeCallback();
    }

    if (_revents & (EPOLLIN | EPOLLPRI))
    {
        if (_readCallback)
            _readCallback(receiveTime);
    }
}
```

- 上面还没有解释update/remove, 这里可以看到其中调用了_loop的成员函数, 其实 _loop 也会继续调用其内部的poller, 从宏观角度来看就是Channel一旦设定/改变/删除了自己关心的事件, 就应当通知poller对监听事件进行相应的改变, 细致说就是再poller中调用epoll_ctl修改内核事件表.
- 继续解释一下上文的_tie,  这是一个weak_ptr, 再handleEvent中调用了`std::shared_ptr<void> guard = _tie.lock();`  , 这里lock()函数的作用是**尝试将一个 `weak_ptr` 升级为 `shared_ptr`, 前提是被观察的对象还没有被析构**, 因此就算对象已经被析构也不会崩溃, guard也只会变为nullptr. **所以为什么Channel可能调用到已析构对象的成员函数呢?** 是因为Muduo还有个类叫做TcpConnection, 这个类类似于Channel的上级部件, 其内部会封装一个channel, 而这个channel的各种回调函数是由TcpConnection设定的, 然而**TcpConnection是一个用户可以使用的类, 用户可以随时销毁它**, 因此一旦TcpConnection对象开始销毁, 而还没有来得及从Poller上移除Channel, 如果有对应事件到来, 调用的回调函数还在那个对象中, 如果不利用tie提前检测, 一旦调用就会崩溃.

## Poller

Poller主要管理对IO复用函数的调用, 这里Muduo库为了实现对poll和epoll共同支持, 先写了一个抽象基类Poller, 之后再分别写了调用poll和epoll的子类, 这里只介绍epoll的EPollPoller类.

```cpp
// Poller.h
#pragma once

#include "Channel.h"
#include "Timestamp.h"

#include <vector>
#include <unordered_map>

// muduo库中多路事件分发器中的核心, 用于触发IO复用
// 此层为抽象基类, 用于作为Epoll和Poll的基类

class Poller : UnCopyable
{
public:
    using ChannelList = std::vector<Channel *>;
    Poller(EventLoop *loop) : _ownerLoop(loop) {}
    virtual ~Poller() = default;

    virtual Timestamp poll(int timeoutMs, ChannelList *activeChannels) = 0;
    virtual void updateChannel(Channel *channel) = 0;
    virtual void removeChannel(Channel *channel) = 0;

    // 判断参数channel是否在当前Poller中
    bool hasChannel(Channel *channel) const;

    // EventLoop可以通过该接口获取默认Poller
    static Poller *newDefaultPoller(EventLoop *loop);

protected:
    using ChannelMap = std::unordered_map<int, Channel *>;
    // 每个loop真正是在这里维护监听的channel
    ChannelMap _channels;

public:
    EventLoop *_ownerLoop;
};
```

先看成员变量 : 

- _channels : 其类型底层是`vector<Channel*>`,  其作用在于储存了所有监视过的Channel, 其作用仅在提供安全性检查(例如检查某个Channel是否已经注册在内核事件表中), 也可以为上层提供这种检查的方法.

再看一些关键的成员函数 : 

- Poller构造函数 : 既然要调用epoll系列函数, 那么epoll_create一般就会在构造函数中直接调用.

- poll : 执行轮询的核心函数, 在epoll中就是调用epoll_wait, 传入的`ChannelList *activeChannels`就会用做epoll_wait的第二个输出型参数, 返回活跃的事件.
- update/removeChannel : 可以感觉到这就是在调用epoll_ctl.
- newDefaultPoller : 这个函数使poller在堆上开辟默认的poller对象, 这里默认EPollPoller.

```cpp
// EPollPoller.h
#pragma once
#include "Poller.h"

#include <vector>
#include <sys/epoll.h>

class Channel;

class EPollPoller : public Poller
{
public:
    EPollPoller(EventLoop *loop);
    ~EPollPoller() override;

    virtual Timestamp poll(int timeoutMs, ChannelList *activeChannels) override;
    virtual void updateChannel(Channel *channel) override;
    virtual void removeChannel(Channel *channel) override;

private:
    static const int kInitEventListSize = 16;

    // epoll_wait得到活跃的事件进行填入
    void fillActiveChannels(int numEvents, ChannelList *activeChannels) const;
    // 更新epoll的内核事件表, 就是使用epoll_ctl
    void update(int operation, Channel *channel);

    using EventList = std::vector<epoll_event>;
    int _epollfd;
    EventList _events; // 存储发生的事件
};
```

- fillActiveChannels : 这个是EPollPoller独有的函数, 一旦监视到活跃的事件就会触发该函数, 其向EventLoop传递活跃的Channel, 让其执行回调函数的调用, 同时还重新设置每个活跃Channel的revents, 切实做到了其作为轮询器的检测职能.

以下是cpp具体实现 : 

```cpp
// EPollPoller.cpp
#include "EPollPoller.h"
#include "Logger.h"
#include "Channel.h"

#include <errno.h>
#include <unistd.h>
#include <cstring>

// 有一个channel还没有添加到poller里, 与channel的成员_index初始值相同
const int kNew = -1;
// channel已添加到poller中
const int kAdded = 1;
// channel从poller中删除
const int kDeleted = 2;

EPollPoller::EPollPoller(EventLoop *loop)
    : Poller(loop), _epollfd(::epoll_create1(EPOLL_CLOEXEC)) // 子进程继承的epid会在调用exec后关闭
    , _events(kInitEventListSize) // vector初始长度设置为16
{
    if (_epollfd < 0)
        LOG_FATAL("epoll_create error: %d\n", errno);
}

EPollPoller::~EPollPoller()
{
    ::close(_epollfd);
}

// virtual Timestamp poll(int timeoutMs, ChannelList *activeChannels) override;

// 对应epoll_ctl
void EPollPoller::updateChannel(Channel *channel)
{
    const int state = channel->state();
    LOG_INFO("func=%s fd=%d events=%d index=%d \n", __FUNCTION__, channel->fd(), channel->events(), state);

    if (state == kNew || state == kDeleted)
    {
        if (state == kNew)
        {
            int fd = channel->fd();
            _channels[fd] = channel;
        }
        channel->set_state(kAdded);
        update(EPOLL_CTL_ADD, channel);
    }
    else
    {
        int fd = channel->fd();
        // 不是新增, 如果发现fd已经没有关心的事件, 就直接取消对fd的监视
        if (channel->isNoneEvent())
        {
            update(EPOLL_CTL_DEL, channel);
            channel->set_state(kDeleted);
        }
        else
        {
            update(EPOLL_CTL_MOD, channel);
        }
    }
}

void EPollPoller::update(int operation, Channel *channel)
{
    // 这里通过ctl将event存入内核中, 之后会通过wait把data原封不动地返回回来
    epoll_event event;
    bzero(&event, sizeof event);
    event.events = channel->events();
    event.data.ptr = channel;
    int fd = channel->fd();

    if (::epoll_ctl(_epollfd, operation, fd, &event) < 0)
    {
        if (operation == EPOLL_CTL_DEL)
            LOG_ERROR("epoll_ctl del error: %d\n", errno);
        else
            LOG_FATAL("epoll_ctl add/mod: %d\n", errno);
    }
}

void EPollPoller::removeChannel(Channel *channel)
{
    int fd = channel->fd();
    _channels.erase(fd);

    LOG_INFO("func=%s fd=%d\n", __FUNCTION__, fd);

    int state = channel->state();
    if (state == kAdded)
        update(EPOLL_CTL_DEL, channel);
    channel->set_state(kNew);
}

// 通过epoll_wait监听到哪些事件发生, 并把发生的事件填入EventLoop提供的ChannelList中
Timestamp EPollPoller::poll(int timeoutMs, ChannelList *activeChannels)
{
    LOG_INFO("func=%s => fd total count: %lu \n", __FUNCTION__, _channels.size());
    // epoll_wait第二个参数要求原生数组, 但是用下面的方式可以改为使用vector, 便于扩容
    int numEvents = ::epoll_wait(_epollfd, &*_events.begin(), static_cast<int>(_events.size()), timeoutMs);
    int saveErron = errno; // errno是全局变量, 可以先存起来防止线程问题
    Timestamp now(Timestamp::now());

    if (numEvents > 0)
    {
        LOG_INFO("%d events happened \n", numEvents);
        fillActiveChannels(numEvents, activeChannels);
        // 如果监听到发生的事件数量已经等于数组大小
        // 说明有可能更多, 需要扩容
        if (numEvents == _events.size())
        {
            _events.resize(_events.size() * 2);
        }
    }
    else if (numEvents == 0)
    {
        LOG_DEBUG("%s timeout! \n", __FUNCTION__);
    }
    else
    {
        if (saveErron != EINTR)
        {
            errno = saveErron;
            LOG_ERROR("poll() error!");
        }
    }
    return now;
}

void EPollPoller::fillActiveChannels(int numEvents, ChannelList *activeChannels) const
{
    // 遍历返回的活跃事件, 将每个事件存入EventLoop的活跃数组, 并修改对应Channel
    for (size_t i = 0; i < numEvents; i++)
    {
        Channel *channel = static_cast<Channel *>(_events[i].data.ptr);
        channel->set_revents(_events[i].events);
        activeChannels->push_back(channel);
    }
}

// DefaultPoller.cpp
#include "Poller.h"
#include "EPollPoller.h"
#include <stdlib.h>

// EventLoop可以通过该接口获取默认Poller
Poller *Poller::newDefaultPoller(EventLoop *loop)
{
    if (::getenv("MUDUO_USE_POLL"))
        return nullptr;
    else
        return new EPollPoller(loop);
}
```

这里再摘出源文件中需要进一步理解的点 : 

- epoll_create1 : 

  这里使用的是epoll_create1而非epoll_create, 目的是向其中传入`EPOLL_CLOEXEC`这个选项, 使得调用了exec系列函数就会直接关闭传出的epfd, 防止子进程继承该文件描述符, 使其变为当前进程独享.

- kNew / KAdded / KDetele : 

  这里三个const变量的作用更像是enum类型, 其表示了每个Channel类型对于Poller可能有的三种状态(新 / 已添加 / 没有关心的事件), 而我们在updateChannel和removeChannel中就会通过调用Channel的state()获取其状态并与这三个const变量做对比, 进而实现不同的epoll_ctl操作.

- updateChannel和removeChannel中都是在通过上面的三种const变量决定epoll_ctl的参数如何设置, 在update函数才执行真正的epoll_ctl函数, 并且这里需要注意的一点是 : `event.data.ptr = channel;`这里直接将channel指针存入了内核事件表中, 实际是非常便利快捷的操作, 后续使用中可以在epoll_wait返回的活跃事件中直接调用. 

## EventLoop

EventLoop内含Poller实现Demultiplex(事件分发器)的作用, Poller的内核事件表中维护了所有关心的Channel,  而EventLoop(事件循环)本身所起到作用类似于Reactor模型中的Reactor(反应堆).

我们首先要明晰EventLoop的职能, 主要就是三部分 : 

1. 决定事件循环的开始和结束(loop / quit).
2. 使用Poller和Channel(接受Poller的状态检测结果并调用Channel的回调函数, 这就是所谓的"反应").
3. 线程调度(最难懂的部分, 有关one loop per thread的设计哲学).

先来看头文件 : 

```cpp
#pragma once

#include "UnCopyable.h"
#include "Timestamp.h"
#include "CurrentThread.h"

#include <functional>
#include <vector>
#include <atomic>
#include <memory>
#include <mutex>

class Channel;
class Poller;

class EventLoop : UnCopyable
{
public:
    using Functor = std::function<void()>;

    EventLoop();
    ~EventLoop();
    
    Timestamp pollReturnTime() const { return _pollReturnTime; }

    // 1
    void loop(); // 开启事件循环
    void quit(); // 退出事件循环
    
    // 2
    // Channel -> EventLoop -> Poller的方法
    void updateChannel(Channel *channel);
    void removeChannel(Channel *channel);
    bool hansChannel(Channel *channel);

    // 3
    // 判断对象是否在自己的线程里
    bool isInLoopThread() const { return _threadId == CurrentThread::tid(); }
    
    void runInLoop(Functor cb);   // 先判断是否是在自己的线程中, 是就使用回调, 不是就放入队列
    void queueInLoop(Functor cb); // 把cb放入队列中, 唤醒loop所在的线程, 执行cb

    void wakeup();

private:
    void handleRead();        // weak up
    void doPendingFunctors(); // 执行回调

    using ChannelList = std::vector<Channel *>;
    std::atomic_bool _looping;
    std::atomic_bool _quit;                   // 标识退出loop循环
    std::atomic_bool _callingPendingFunctors; // 标识当前loop是否有需要执行的回调操作
    const pid_t _threadId;                    // 记录创建该loop所在的线程id
    Timestamp _pollReturnTime;                // poller返回发生事件的channels的时间点
    
    std::unique_ptr<Poller> _poller;
    // 由eventfd()创建, 当mainLoop获取一个新用户的channel, 通过轮循算法选择一个subLoop, 唤醒该成员
    int _wakeupFd;
    std::unique_ptr<Channel> _wakeupChannel;

    ChannelList _activeChannels;

    // 这个资源有可能被其他线程访问, 需要上锁
    std::vector<Functor> _pendingFunctors; // 存储loop需要执行的所有回调操作d
    std::mutex _mutex;
};
```

我们可以先理解部分函数 : 

- _poller + loop() / quit() :

  这里可以理解到loop中就是再一个循环中调用_poller的poll方法, quit可以打破循环.

- _activeChannels + update / removeChannel() : 

  这里的逻辑链路是 : EventLoop会将_activeChannels传给Poller的poll中, EventLoop会及时得到活跃的事件, 

  然后调用原先设置的Channel对应的回调.

接下来我们需要静下心来理解EventLoop中线程调度的必要性 : 

首先是Muduo库的设计哲学 : **one loop per thread**.

每个线程只运作一个事件循环, 可以达到非常高的处理效率, 而一个loop中会内含一个poller和多个channel, 包括我们看到的成员变量(各种状态判断标记 / _activeChannels / _pendingFunctors等), 这些资源都是每个loop**独有**的.

也就是说其实**每个loop和创建其的线程其实是绑定的**, 如果一个loop的功能如果不在创建其的线程中被调用, 就会导致逻辑不一致而失败甚至崩溃. **因此如果产生这种情况, 我们要将线程切换到loop对应的线程**. 而切换的方法就是利用_wakeupfd , _wakeupChannel, 和第三部分的一系列函数, 具体实现我们一会再说. 

那么问题来了,  **一个loop为什么会不在创建其的线程中被调用呢?** 答案在于Muduo库的框架设计中有两种EventLoop, 一种是mainLoop(一个), 处理连接与分配, 一种是subLoop(多个), 处理每个连接的回调事务. 我们在使用Muduo库时创建并传入TcpServer的loop就是mainLoop, 而当mainLoop接收到新连接时, 就会分配给subLoop(实现会存储每个subLoop的指针), 而分配的方式就是**把希望subLoop执行的回调函数加入其线程专属的_pendingFunctors中, 然后通过某种方式切换到subLoop所在的线程并且执行该回调**(例如将新连接注册到自己的Poller中), 而这就是 **runInLoop / queueInLoop / wakeup** 这一系列函数可以实现的事情.  

我们来看cpp文件了解他们的具体实现 : 

```cpp
#include "EventLoop.h"
#include "Logger.h"
#include "Poller.h"

#include <sys/eventfd.h>
#include <unistd.h>
#include <fcntl.h>

// 线程局部全局变量指针
// 防止一个线程创建多个EventLoop
__thread EventLoop *t_loopInThread = nullptr;

// 定义默认IO复用接口的超时时间
const int kPollTimeMs = 10000;

// 创建wakeupfd, 用来notify唤醒subReactor处理新来的channel
int createEventfd()
{
    int efd = ::eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    if (efd < 0)
        LOG_FATAL("eventfd error: %d \n", errno);
    return efd;
}

// 一个线程启用一个EventLoop, 一个EventLoop在创立之初确立一个该线程该loop专属的_weakfd
EventLoop::EventLoop()
    : _looping(false)
    , _quit(false)
    , _callingPendingFunctors(false)
    , _threadId(CurrentThread::tid())
    , _poller(Poller::newDefaultPoller(this))
    , _wakeupFd(createEventfd())
    , _wakeupChannel(new Channel(this, _wakeupFd))
{
    if (t_loopInThread)
        LOG_FATAL("Another EventLoop %p exists int this thread %d \n", t_loopInThread, _threadId);
    else
        t_loopInThread = this;

    // 设置wakeupfd的读事件回调
    _wakeupChannel->setReadCallback(std::bind(&EventLoop::handleRead, this));
    // 使当前loop监听_wakeupfd的EPOLLIN读事件
    _wakeupChannel->enableReading();
}

EventLoop::~EventLoop()
{
    _wakeupChannel->disableAll();
    _wakeupChannel->remove();
    ::close(_wakeupFd);
    t_loopInThread = nullptr;
}

// 触发这个事件只是为了触发离开循环后的回调
void EventLoop::handleRead()
{
    uint64_t one = 1;
    ssize_t n = read(_wakeupFd, &one, sizeof one);
    if (n != sizeof one)
    {
        LOG_FATAL("EventLoop::handleRead() reads %lu bytes instead of 8", n);
    }
}

void EventLoop::loop()
{
    _looping = true;
    _quit = false;

    LOG_INFO("EventLoop %p start looping \n", this);

    while (!_quit)
    {
        _activeChannels.clear();
        _pollReturnTime = _poller->poll(kPollTimeMs, &_activeChannels);
        // 处理自己本身监听的事件
        for (Channel *channel : _activeChannels)
        {
            // 通知每个channel处理对应的事件
            channel->handleEvent(_pollReturnTime);
        }
        // 处理mainLoop/其他subLoop发配给自己的任务(注册新channel, 修改channel)
        // 执行当前EventLoop事件循环需要处理的回调操作
        doPendingFunctors();
    }
    LOG_INFO("EventLoop %p stop looping \n", this);
    _looping = false;
}

void EventLoop::quit()
{
    _quit = true;
    // 要判断当前工作线程是不是IO线程, 如果不是, 则唤醒主线程
    // 由于_quit线程是共享资源的, 在工作线程修改的_quit会在IO线程产生效果, 从而真正在主线程quit
    if (!isInLoopThread())
        wakeup();
}

// Channel -> EventLoop -> Poller的方法
void EventLoop::updateChannel(Channel *channel)
{
    _poller->updateChannel(channel);
}
void EventLoop::removeChannel(Channel *channel)
{
    _poller->removeChannel(channel);
}
bool EventLoop::hansChannel(Channel *channel)
{
    return _poller->hasChannel(channel);
}

// 在当前的loop执行cb
void EventLoop::runInLoop(Functor cb)
{
    if (isInLoopThread())
        cb();
    else
        queueInLoop(cb);
}

// 把cb放入队列中, 唤醒loop所在的线程, 执行cb
void EventLoop::queueInLoop(Functor cb)
{
    {
        std::unique_lock<std::mutex> lock(_mutex);
        _pendingFunctors.emplace_back(cb);
    }

    // 唤醒相应loop
    // 不在对应线程 | 在对应线程但是正在执行回调(执行完会回到阻塞, 可用wakeup触发)
    if (!isInLoopThread() || _callingPendingFunctors)
        wakeup();
}

// 唤醒loop所在的线程 向wakeupfd写一个数据
void EventLoop::wakeup()
{
    uint64_t one = 1;
    ssize_t n = write(_wakeupFd, &one, sizeof one);
    if (n != sizeof one)
    {
        LOG_ERROR("EventLoop::wakeup() writes %lu bytes instead of 8 \n", n);
    }
}

void EventLoop::doPendingFunctors()
{
    std::vector<Functor> functors;
    _callingPendingFunctors = true;

    {
        std::unique_lock<std::mutex> lock(_mutex);
        functors.swap(_pendingFunctors);
    }

    for (const Functor &functor : functors)
    {
        functor(); // 执行当前loop需要执行的回调操作
    }

    _callingPendingFunctors = false;
}
```

让我们逐一讲解重要的实现 : 

- 构造函数 : 

  在这里new出了内部调用的Poller, 创建出了每个线程专属的_wakeupfd, 并且把这个fd封装进了 _wakeupChannel中, 在其中设置了这个fd读事件发送的回调函数并且关注读事件, 至于这里为什么创建 _wakeupfd和设置回调, 后面详述.

  - eventfd() : 你可以理解为一个类似于socket可以创建出fd的函数, 但是该fd只能发送64位数据用于线程间通信.

- loop : 

  这里循环调用poller的poll函数, 是整个EventLoop的核心逻辑, 当有事件发生就会离开阻塞, 然后处理两类事件:

  - 其一处理poll返回的loop本身关心的事件.
  - 其二处理mainLoop或其他subLoop希望当前subLoop执行的加入到_pendingFunctors中的回调函数.

- quit : 

  这里quit希望退出循环, 就把目标subLoop的_quit置成true, 然后唤醒目标subLoop的线程, 目标线程的loop中就会感知到 _quit的变化并作出判断.

- update / remove / hasChannel : 

  这里其实就是Channel通过EventLoop修改Poller的途径, 具体可以再回忆一下Poller中对应的函数.

- runInLoop / queueInLoop / wakeup / doPendingFunctors : 

  这一部分是线程调度的核心 : 

  - 当mainLoop/subLoop希望某个Loop执行某个函数时, 其就会调用该loop的runInLoop把回调函数传进去.
  - 如果当前线程就是创建该loop的线程, 则会直接执行该函数.
  - 反之就会执行以下逻辑 : 
    - 将该函数加入该loop的_pendingFunctors.
    - 调用wakeup()向该loop的_wakeupfd发送一个数据.
    - 在上文中我们知道在构造函数中已经设置了对应_wakeupfd的读事件回调, 那么这个loop如果原来阻塞在epoll_wait, 就会离开阻塞向下执行.
    - 关键不在我们设置的读事件回调handleRead(它只是读了一个没有用的数据而已), 而在于loop的事件循环不再处于阻塞状态, 就可以继续执行之后的doPendingFunctors函数了 !
    - 而在doPendingFunctors函数中就会执行我们在第一步存入_pendingFunctors中的回调函数 !

  这里确实比较难懂, 如果想真正理解, 最好认识到每个Loop的资源都是独立且和线程绑定的, 在运行中会有很多不同的Loop资源存在, **当mainLoop希望subLoop执行函数时, 其手上会有目标subLoop的指针, 借着这个指针找到该subLoop对应的资源, 利用该资源中的_weakupfd唤醒该subLoop, 也就是切换到subLoop对应线程, 让这个subLoop执行函数.**

## 尾声

至此整个EvnetLoop已经讲解完毕, 但我认为很多地方还是比较晦涩难懂的.

在整体框架上就是一个EventLoop内置一个Poller管理多个Channel上发生事件的模型, Poller负责轮询, EvnetLoop根据Poller返回的活跃事件进行函数回调.

在此基础上, 由于mainLoop和subLoop的设计理念, 需要实现Loop之间的互动与函数传递, 其实这种行为用生产者消费者模型就可以实现(例如mainLoop当S, subLoop当C, 中间维护一个任务队列), 但这种模型其实效率并不高, 肉眼可见的要使用很多锁来维护任务队列.

反观Muduo库的设计, 虽然设计比较复杂, 但是几乎没有用到锁的地方, 除了_pendingFunctors的使用, 因为有可能有多个线程同时使用 _pendingFunctors 向其中加入回调函数, 而且对于线程的切换由于weakup()的存在, 都是精确且没有过多消耗的, 避免了主动轮询或额外线程开销, 足以见得其效率. 

而且和libevent库很像的一点是都有**统一事件源**的思想内核, 比如这里设计的基于Channel/Poller/EventLoop的一套监测/分发/处理的流程, 既可以用在处理普通socketfd的读写事件上, 也可以处理_weakupfd这种线程切换事件上, 在之后还可以用来处理Acceptor的listensocketfd的连接建立事件上, 其实就是掌握了不同事件之间的相通点(用fd进行事件读写), 进而转化为统一的处理方式.

by 天目中云
