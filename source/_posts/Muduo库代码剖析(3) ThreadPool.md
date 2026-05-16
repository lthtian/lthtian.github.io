---
title: Muduo库代码剖析(3) ThreadPool
date: 2025-4-16 11:01:00
tags: [Muduo]
---

> ThreadPool相关

本章我们将把EventLoop和C++11的thread结合, 实现Thread / EventLoopThread / EventLoopThreadPool. 

首先我们应当明晰将创建的三个类的意义何在 : 

- Thread : 这是对thread库的封装, 会增加对各种线程运行状态与数据的维护.

- EventLoopThread :

  将Thread和EventLoop组合, 真正实现 **one loop per thread** 思想的地方, 最终达成的效果就是创建一个线程并在线程中创建一个loop并运行该loop.

- EventLoopThreadPool : 

  学到这里线程池的作用应该都知道, 就是提前创建线程以减少运行开销, 这里就是开一个池填充EventLoopThread, 我们最后的TcpServer中就会维护这样一个线程池存放subLoop.

## Thread

对C++11的thread库封装 : 

```cpp
// Thread.h
#pragma once

#include "UnCopyable.h"
#include <functional>
#include <thread>
#include <memory>
#include <unistd.h>
#include <atomic>
#include <string>

// 一个Thread对象记录的就是一个新线程的详细信息
class Thread : UnCopyable
{
public:
    using ThreadFunc = std::function<void()>;

    explicit Thread(ThreadFunc, const std::string &name = std::string());
    ~Thread();

    void start();
    void join();

    bool started() const { return _started; }
    pid_t tid() const { return _tid; }
    const std::string &name() { return _name; }

private:
    void setDefaultName();

    bool _started;
    bool _joined;
    std::shared_ptr<std::thread> _thread;
    pid_t _tid;
    ThreadFunc _func;
    std::string _name;
    static std::atomic_int32_t _numCreated; // 记录产生的线程个数
};
```

```cpp
// Thread.cpp
#include "Thread.h"
#include "CurrentThread.h"

#include <semaphore.h>

std::atomic_int Thread::_numCreated(0);

Thread::Thread(ThreadFunc func, const std::string &name)
    : _started(false), _joined(false), _tid(0), _func(std::move(func)), _name(name)
{
    setDefaultName();
}

Thread::~Thread()
{
    if (_started && !_joined)
        _thread->detach();
}

void Thread::start()
{
    _started = true;
    sem_t sem;
    sem_init(&sem, false, 0);
    _thread = std::make_shared<std::thread>([this, &sem](){
        _tid = CurrentThread::tid();
        sem_post(&sem);
        _func(); 
    });
    // 确保子线程tid已经确定
    sem_wait(&sem);
}

void Thread::join()
{
    _joined = true;
    _thread->join();
}

void Thread::setDefaultName()
{
    int num = ++_numCreated;
    if (_name.empty())
    {
        char buf[32] = {0};
        snprintf(buf, sizeof buf, "Thread%d", num);
        _name = buf;
    }
}
```

进行封装的主要目的除了进行信息记录之外, 就是可以**控制创建线程的时机**. 对于C++11thread库中的thread类来说, 只要创建出对象就代表了线程开启, 这样就没有进行初始化准备的时间了, 我们在封装中用智能指针维护thread类, 在start中才真正传入回调函数并创建thread对象开启线程.

这里还需要注意的一点就是为了在Thread对象中维护线程的tid, 需要使用条件变量进行线程间通信, 以获取到创建线程的tid并存储在Thread对象中.

这里补充一下CurrentThread类, 其可以获取当前线程的tid, 在上一章的EventLoop中也有使用过, 用来判断是不是当前进程 : 

```cpp
// CurrentThread.h
#pragma once
namespace CurrentThread
{
    extern __thread int t_cachedTid;

    void cacheTid();

    inline int tid()
    {
        if (__builtin_expect(t_cachedTid == 0, 0))
            cacheTid();
        return t_cachedTid;
    }
}

// CurrentThread.cpp
#include "CurrentThread.h"
#include <sys/syscall.h>
#include <unistd.h>

namespace CurrentThread
{
    __thread int t_cachedTid = 0;
    void cacheTid()
    {
        if (t_cachedTid == 0)
        {
            t_cachedTid = static_cast<pid_t>(::syscall(SYS_gettid));
        }
    }
}
```

## EventLoopThread

EventLoopThread类内部提供了线程函数来实现构建一个EventLoop并运行的效果.

```cpp
#pragma once

#include "UnCopyable.h"
#include "EventLoop.h"
#include "Thread.h"

#include <functional>
#include <mutex>
#include <condition_variable>

class EventLoopThread : UnCopyable
{
public:
    using ThreadInitCallback = std::function<void(EventLoop *)>;
    EventLoopThread(const ThreadInitCallback &cb = ThreadInitCallback(),
                    const std::string &name = std::string());
    ~EventLoopThread();

    EventLoop *startLoop();

private:
    void threadFunc();

    EventLoop *_loop;	// 记录Thread中创建出来的唯一的loop的指针
    bool _exiting;		
    Thread _thread;		
    std::mutex _mutex;
    std::condition_variable _cond;
    ThreadInitCallback _cb;
};
```

```cpp
#include "EventLoopThread.h"

EventLoopThread::EventLoopThread(const ThreadInitCallback &cb,
                                 const std::string &name)
    : _loop(nullptr)
    , _exiting(false)
    , _thread(std::bind(&EventLoopThread::threadFunc, this), name)
    , _mutex()
    , _cond()
    , _cb(cb)
{}

EventLoopThread::~EventLoopThread()
{
    _exiting = true;
    if (_loop != nullptr)
    {
        _loop->quit();
        _thread.join();
    }
}

// 获取一个新线程中单独运行的EventLoop对象指针
// 利用条件变量 + 共享内存实现了线程间通信
EventLoop *EventLoopThread::startLoop()
{
    _thread.start();

    EventLoop *loop = nullptr;
    {
        std::unique_lock<std::mutex> lock(_mutex);
        while (_loop == nullptr)
        {
            _cond.wait(lock);
        }
        loop = _loop;
    }
    return loop;
}

// 在单独的新线程里面运行
void EventLoopThread::threadFunc()
{
    // one loop per thread
    EventLoop loop;
    if (_cb) _cb(&loop);

    {
        std::unique_lock<std::mutex> lock(_mutex);
        _loop = &loop;
        _cond.notify_one();
    }

    loop.loop();
    std::unique_lock<std::mutex> lock(_mutex);
    _loop = nullptr;
}
```

- threadFunc :

  该函数是Muduo库的核心函数, 是每个线程中将要执行的代码, 里面有很多需要学习的设计 : 

  - `EventLoop loop;`  

    我们知道线程的栈空间是独立的, 这里就是直接在栈上开辟了这个loop, 使得这个loop和当前线程强绑定, 线程结束该loop也会析构, 遵循了 one loop per thread 的理念.

  - `if (_cb) _cb(&loop);` 

    _cb的类型是`ThreadInitCallback`, 其并不是必要的, 只是如果有在线程刚建立时的初始化需求的话, 可以在构造函数中传入想执行的初始化操作.

  - 接下来的代码中, 线程将在栈上构造出的loop的指针存储到_loop中, 这里使用条件变量进行线程通信, 主线程就可以知道它所开辟的新线程上loop的指针何在了.

  - `loop.loop();`

    这里直接调用loop开启事件循环.

  - `, _thread(std::bind(&EventLoopThread::threadFunc, this), name)`

    还需要注意的一点是这个函数会在构造函数构造_thread时绑定到 _thread中, 在startLoop中被触发.

我们来梳理一遍EventLoopThread的使用流程 :

已知其上层还有EventLoopThreadPool会存入很多EventLoopThread, 并且其内部也会记录每个EventLoopThread中loop的指针, 那么实际调用流程就是 : 

- EventLoopThreadPool创建EventLoopThread对象.
- 调用startLoop函数, 创建线程并执行threadFunc.

- threadFunc中, 在栈上构造loop并将_loop修改, 用条件变量唤醒startLoop.
- startLoop将获取到的_loop作为返回值传出.

而这个返回值将被存入EventLoopThreadPool的_loops中.

## EventLoopThreadPool

EventLoopThreadPool会构建多个EventLoopThread并储存, 而在Muduo库中是通过轮询的方式实现subLoopd的选择的, 也就是说这个线程池内部提供了轮询方法将loop指针提供出去.

```cpp
#pragma once
#include "UnCopyable.h"
#include "EventLoopThread.h"

#include <functional>
#include <string>
#include <vector>
#include <memory>

class EventLoop;
class EventLoopThreadPool : UnCopyable
{
public:
    using ThreadInitCallback = std::function<void(EventLoop *)>;

    EventLoopThreadPool(EventLoop *mainloop, const std::string &name);
    ~EventLoopThreadPool();

    void setThreadNum(int numThreads) { _numThreads = numThreads; }

    void start(const ThreadInitCallback &cb = ThreadInitCallback());

    // 如果工作在多线程中, ThreadPool以轮循的方式分配subloop
    EventLoop *getNextLoop();
    std::vector<EventLoop *> getAllLoops();
    bool started() const { return _started; }
    const std::string name() const { return _name; }

private:
    EventLoop *_mainLoop;
    std::string _name;
    bool _started;
    int _numThreads;
    int _next;
    std::vector<std::unique_ptr<EventLoopThread>> _threads;
    std::vector<EventLoop *> _loops;
};
```

先来介绍一下成员变量 : 

- _mainLoop : 这就是主线程构建的loop, 也就是我们作为用户一开始向TcpServer手动传入的loop的指针, 在EventLoopThreadPool中其存在价值在于当线程池中创建线程数为0时, 作为替补方案用来执行subLoop的工作.
- _numThreads : 我们可以通过setThreadNum来设置线程池中需要有多少个线程, 也就是有多少个subLoop.
- _threads : 存储线程对象的vector.
- _loops : 存储每个线程中构建的loop指针.
- _next : 记录当前轮询到 _loop中的哪一个.

```cpp
#include "EventLoopThreadPool.h"
#include "EventLoopThread.h"

#include <memory>

EventLoopThreadPool::EventLoopThreadPool(EventLoop *mainloop, const std::string &name)
    : _mainLoop(mainloop), _name(name), _started(false), _numThreads(0), _next(0)
{
}

EventLoopThreadPool::~EventLoopThreadPool()
{
    // 线程上绑定的对象都是栈上的的对象, 无需关心析构
}

void EventLoopThreadPool::start(const ThreadInitCallback &cb)
{
    _started = true;

    for (int i = 0; i < _numThreads; i++)
    {
        char buf[_name.size() + 32];
        snprintf(buf, sizeof buf, "%s%d", _name.c_str(), i);
        EventLoopThread *t = new EventLoopThread(cb, buf);
        _threads.push_back(std::unique_ptr<EventLoopThread>(t));
        _loops.push_back(t->startLoop());
    }

    // 整个服务端只有一个线程, 让mainloop来运行
    if (_numThreads == 0 && cb)
    {
        cb(_mainLoop);
    }
}

// 如果工作在多线程中, mainLoop以轮询的方式分配channel给subloop
EventLoop *EventLoopThreadPool::EventLoopThreadPool::getNextLoop()
{
    EventLoop *loop = _mainLoop;

    // 轮询
    if (!_loops.empty())
    {
        loop = _loops[_next];
        ++_next;
        if (_next >= _loops.size())
            _next = 0;
    }

    return loop;
}

std::vector<EventLoop *> EventLoopThreadPool::EventLoopThreadPool::getAllLoops()
{
    if (_loops.empty())
        return std::vector<EventLoop *>(1, _mainLoop);
    else
        return _loops;
}
```

总共有两个重要的函数要解释 : 

- start : 

  可以见得其依据_numThreads的数目构建EventLoopThread, 将创建出的对象存入 _threads, 然后再调用该对象的startLoop方法, 开启线程中的事件循环, 将其返回的loop指针存入 _loops.

- getNextLoop : 

  这个函数将供给上层TcpServer调用, 以轮询方式提供出一个subLoop的指针, TcpServer则会将利用runInLoop将任务发配到该subLoop上, 当然如果一个subLoop都没有, 就还由mainLoop执行这些任务.



by 天目中云