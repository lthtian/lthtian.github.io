---
title: Rpc分布式网络通信框架(8) Logger
date: 2025-6-26 15:00:00
tags: [RPC, 日志系统]
---

> asyncqueue + Logger

本章处理一下Rpc框架的遗留问题---日志处理. 

最普通的日志处理就是直接在一个文件中写入, 但是这属于磁盘I/O, 效率极低, 我们不会希望在高性能Rpc通信框架中仅仅为了日志在过程中加入磁盘I/O的过程, 那么如何解决呢?

- **可以将要写入磁盘文件的日志先存入队列, 再开一个专门进行日志磁盘I/O的线程从队列取出进行写入.**

很经典的c/s模型, 并且把业务和日志分配到两个线程中, 不会影响到业务速度.

另外还有一个问题, 我们的RpcProvider借用muduo网络库实现网络功能, 其内部是epoll多线程的, 也就是说有可能会有多个线程同时向队列中插入日志, 为了线程安全, 我们需要**用互斥锁保证线程安全**. 

细节已经详述清楚, 接下来展示代码 : 

```cpp
// asyncqueue.h
#pragma once
#include <queue>
#include <thread>
#include <mutex>
#include <condition_variable>

template <typename T>
class AsyncQueue
{
public:
    void push(const T &data)
    {
        std::lock_guard<std::mutex> lock(_mutex);
        _queue.push(data);
        _cond.notify_one();
    }

    T pop()
    {
        std::unique_lock<std::mutex> lock(_mutex);
        while (_queue.empty())
        {
            _cond.wait(lock);
        }

        T top = _queue.front();
        _queue.pop();
        return top;
    }

private:
    std::queue<T> _queue;
    std::mutex _mutex;
    std::condition_variable _cond;
};
```

一个简单的线程安全队列, 保证插入和弹出操作是安全的, 并且利用条件变量在队列中没有日志时会挂起等待, 有日志插入时再唤醒.

```cpp
#pragma once
#include "asyncqueue.h"

namespace mprpc
{
    enum RpcLogLevel
    {
        info,
        error,
    };

    // Rpc框架提供的日志系统
    class RpcLogger
    {
    public:
        void SetLogLevel(RpcLogLevel lv);
        void Log(std::string msg);

        static RpcLogger &getInstance();

    private:
        RpcLogger();
        RpcLogger(const RpcLogger &) = delete;
        RpcLogger(RpcLogger &&) = delete;

        int _loglevel; // 记录日志级别
        AsyncQueue<std::string> _asyncQueue;
    };

#define log_info(logmsgformat, ...)                     \
    do                                                  \
    {                                                   \
        RpcLogger &logger = RpcLogger::getInstance();   \
        logger.SetLogLevel(info);                       \
        char c[1024] = {0};                             \
        snprintf(c, 1024, logmsgformat, ##__VA_ARGS__); \
        logger.Log(c);                                  \
    } while (0)

#define log_error(logmsgformat, ...)                    \
    do                                                  \
    {                                                   \
        RpcLogger &logger = RpcLogger::getInstance();   \
        logger.SetLogLevel(error);                      \
        char c[1024] = {0};                             \
        snprintf(c, 1024, logmsgformat, ##__VA_ARGS__); \
        logger.Log(c);                                  \
    } while (0)
}
```

日志系统保证单例, 另外还define了两种快捷写日志的方式.

```cpp
#include "logger.h"
#include <iostream>
#include <time.h>
using std::cout;
using std::endl;

namespace mprpc
{
    RpcLogger::RpcLogger()
    {
        // 启动专门的写日志线程
        std::thread writeLogTask([&]()
                                 {
        while(true)
        {
            // 获取当前的日期, 然后获取日志信息, 写入相应的日志文件
            time_t now = time(nullptr);
            tm* nowtm = localtime(&now);

            char file_name[128];
            sprintf(file_name, "%d-%d-%d-log.txt", 
                nowtm->tm_year + 1900, nowtm->tm_mon + 1, nowtm->tm_mday);
            FILE* pf = fopen(file_name, "a+");
            if(!pf)
            {
                cout << "logger file: " << file_name << " open error!" << endl;
                exit(EXIT_FAILURE);
            }

            std::string msg = _asyncQueue.pop();

            char time_buf[128] = {0};

            sprintf(time_buf, "%d:%d:%d =>[%s] ",
                nowtm->tm_hour, nowtm->tm_min, nowtm->tm_sec,
                (_loglevel == info ? "info" : "error"));
            msg.insert(0, time_buf);
            msg.append("\n");

            fputs(msg.c_str(), pf);
            fclose(pf);
        } });
        // 设置线程分离
        writeLogTask.detach();
    }

    void RpcLogger::SetLogLevel(RpcLogLevel lv)
    {
        _loglevel = lv;
    }

    void RpcLogger::Log(std::string msg)
    {
        _asyncQueue.push(msg);
    }

    RpcLogger &RpcLogger::getInstance()
    {
        static RpcLogger logger;
        return logger;
    }
}
```

这里一旦日志系统的单例被构造, 就会开辟一个线程持续从队列中取出日志进行磁盘写入, 在没有日志会阻塞在`_asyncQueue.pop()`处.

至此只要带上日志头文件, 就是可以在这个高性能且多线程的框架中快捷进行日志操作了.



by 天目中云