---
title: C++线程库使用详解
date: 2025-2-27 18:56:00
tags: [多线程]
---

## 核心操作

### 线程创建

```cpp
// 需要传入回调函数, 如果有参数紧跟在后面
std::thread t1(print_hello, 1);  
// 当然lambda也可以当作回调函数传进去
std::thread t([]() {
    std::cout << "Hello from lambda thread!" << std::endl;
});
// 也可以创建时传入回调函数
std::thread t(calculate_sum, 3, 5, print_result);
```

### 线程等待

```cpp
t1.join();
```

- 为什么需要线程等待?

  目的在于**接收信息和同步**.

   join中并没有实际和接收信息相关的操作, 信息交流是靠其他几种线程间通信的方式来实现的. 关键在于如果不用join, 将无法安全使用线程间通信得来的信息, 因为如果不等待子线程运行结束, 主线程和子线程并发运行, 主线程没有办法确定什么时候子线程会得到结果并发送过来, 简单来说就是无法实现同步.

- 可以通过joinable()函数来确定线程是否可join而未被分离.

### 线程分离

```cpp
t1.detach();
```

线程分离就是为了实现和线程等待相反的目的, 也就是不需要同步的情况, 当代码不需要和主线程互通有无的时候便可以调用detach, 让线程自己干自己的去.

---

## 线程间通信

这里线程间通信的定义其实很广泛, 可以细化为线程间权限申请, 数据交互, 函数调用等.

### 锁

- 互斥锁

```cpp
mutex mtx;
mtx.lock();
//....
mtx.unlock();
```

- RAII风格的锁

```cpp
mutex mtx;
{
	lock_guard<std::mutex> lock(mtx); // 离开作用域自动调用析构函数解锁
 	// ... 使用lock_guard需要控制作用域   
}
```

### 条件变量

```cpp
template <typename Predicate>
void wait(std::unique_lock<std::mutex>& lock, Predicate pred);
```

条件变量需要和互斥锁绑定, 并且需要条件撑腰, 在等待时是否原先持有的锁, 被唤醒时重新取回拥有的锁并进行之后的代码, 有两种方式判断条件 : 

- 直接套在while循环里, 只有符合条件才能离开循环, 这里循环不是意味着要频繁判断, wait本身是阻塞的, 而是为了避免虚假唤醒的情况, 可以理解为系统问题.

```cpp
std::mutex mtx;                    // 互斥量
std::condition_variable cv;         // 条件变量
// ...
std::unique_lock<std::mutex> lck(mtx);
while (!ready) {               // 使用while循环避免虚假唤醒
    cv.wait(lck);               // 等待通知
}
// ... 另一个线程
cv.notify_all(); 
cv.notify_one();
```

- 使用wait的第二个参数, 传入一个返回值为bool类型的回调函数, 官方称其为谓词.

  谓词只在第一次触发wait和被唤醒之后发生, 如果谓词返回值为true, 则继续后面的代码, 反之继续阻塞挂起.

```cpp
condition.wait(lock, [this] {  // 捕获this,使之可以使用成员函数和变量
    return stop || !taskQueue.empty();
});
```

其实底层就是对C风格互斥锁和条件变量的封装.

### 共享内存

这是一个非常宽泛的概念, 我们知道一个进程的不同线程间数据块,堆都是共享的, 所以在其中申请的资源都是共享内存, 锁也是为了应对使用共享内存的情况而被设计的.

### 消息队列

其实就是STL中的queue, 这个容器其实非常强大, 因为其是线程安全的, 例如我们就可以直接在生产者线程中将产物push进queue, 然后直接在消费者线程中从queue中取出, 这其中没有任何线程安全问题!

### future和promise 

future可以得到未来从其他线程传来的一个结果. 

这里只介绍future在线程中的普通用法, 一般和promise共用.

- future : 未来, 用于表示在未来这里会获取一个结果.
- promise : 承诺, 可以和future关联, 承诺会设置future要获取的结果.

```cpp
std::promise<int> prom;  
std::future<int> fut = prom.get_future(); // 将promise和future关联

std::thread t([&prom]() { // 捕获prom传入线程
    int result = 42; // 模拟计算
    prom.set_value(result); // promise将结果传递给future
});

int value = fut.get(); // 阻塞直到获取结果
t.join();
std::cout << "Result: " << value << "\n";
```

- async  : `async` 是 **asynchronous** 的缩写，表示“异步”的意思. 不过异步这个意义很宽泛, 很多都可以被视为异步. 有些异步相对复杂, 比如异步I/O, 有些有十分简单, 比如我们现在学的async.

  其实它的实际功效就是上面future + promise + thread的统合, 可以理解为**和future强绑定的thread**.

  可以向async中传入一个回调函数, async会直接在一个新线程中运行它, 会返回一个future对象, 新线程运行结束会将结果设置到future对象中.

  ```cpp
  template< class F, class... Args >
  std::future<std::invoke_result_t<F, Args...>> 
    async(F&& f, Args&&... args);
  ```

  - f : 用于确定async的启动策略, 一般写`std::launch::async`, 代表强制任务在新线程中执行.
  - args : 可变参数, 传入回调函数需要的参数.

  ```cpp
  // 使用 std::async 启动一个异步任务
  std::future<int> fut = std::async(std::launch::async, []() {
      int result = 42; // 模拟计算
      return result;   // 返回结果
  });
  // 获取结果（会阻塞直到任务完成）
  int value = fut.get();
  std::cout << "Result: " << value << "\n";
  ```

### 共享内存 vs 消息队列 vs future

这三个其实都可以做到线程间传递数据, 但是应用场景不同.

- 共享内存 : 用于多数据, 需求复杂的情况, 需要互斥锁和条件变量维护.
- 消息队列 : 适合生产者消费者模型, 简单易用, 线程安全, 但是需要排队, 可能需要条件变量配合.
- future : 只传递单数据, 简单易用, 并且线程安全不需要考虑额外内容.

### atomic

原子操作本身和线程间通信没关系, 只是它本身就是为了服务多线程环境的一种语法, 可以减少线程间通信的发生, 取消部分资源对互斥锁的使用, 毕竟它是原子的, 根本不需要锁.

```cpp
std::atomic<int> x{0};  // 初始化原子变量
x.store(10);  // 使用 store 进行赋值
int value = x.load();  // 返回原子变量 x 的值
int old1 = x.fetch_add(1);  // 先返回 x 的值，然后将其加 1
int old2 = x.fetch_sub(1);  // 先返回 x 的值，然后将其减 1
int old_value = x.exchange(20);  // 将 x 的值设为 20，返回原来的值
// 如果当前值等于 expected，则将其替换为 desired，返回是否成功
bool success = x.compare_exchange_strong(expected, desired); 
int old3 = x.fetch_and(0xFF);  // 与 0xFF 进行按位与操作
int old4 = x.fetch_or(0xFF);  // 与 0xFF 进行按位或操作
int old5 = x.fetch_xor(0xFF);  // 与 0xFF 进行按位异或操作
```

需要注意的atomic的模板类必须是普通类型, 还有一种情况是 : 在一个自定义类型中全是普通类型允许填入, 术语叫做POD.

---

## this_thread

这是 C++11 引入的一个命名空间，用来提供一些和当前线程相关的操作.

```cpp
void sleep_for(const std::chrono::duration& d); // 使当前线程挂起指定的时间
std::this_thread::sleep_for(std::chrono::seconds(2));  // 休眠2秒

void sleep_until(const std::chrono::time_point& t);  // 使进程挂起到指定的时间
auto wakeup_time = std::chrono::system_clock::now() + std::chrono::seconds(3);  // 3秒后
std::this_thread::sleep_until(wakeup_time);  // 休眠直到指定时间

void yield(); // 一个请求, 表示当前线程愿意让出cpu的时间片, 假如线程间的优先度不同可以使用
std::this_thread::yield();
```

---

## thread的移动语义

线程对象不可复制, 因为线程本身就不好复制, 从底层来讲thread类的拷贝构造函数本身就是删除的.

但是thread类可以被移动, 其实就相当于转移控制权, 可以使用move转换.

假如我们想把多个线程存入一个vector中, 可以使用emplace_back在vector中直接构建, 也可以选择在外部构建然后用move移动进去.

```cpp
std::thread t(task);  // 创建一个线程对象 t
threads.push_back(std::move(t));
```

---

## 简易线程池

AI生成仅供学习 : 

```cpp
#include <iostream>
#include <thread>
#include <vector>
#include <queue>
#include <functional>
#include <mutex>
#include <condition_variable>
#include <atomic>

// 线程池类
class ThreadPool {
public:
    ThreadPool(size_t numThreads) {
        // 启动指定数量的工作线程
        for (size_t i = 0; i < numThreads; ++i) {
            workers.emplace_back([this] {
                while (true) {
                    std::function<void()> task;
                    {
                        std::unique_lock<std::mutex> lock(queueMutex);
                        condition.wait(lock, [this] {
                            return stop || !taskQueue.empty();
                        }); // 直到return 返回 ture才能进行
                        
                        // 如果线程池停止且任务队列为空，退出线程
                        if (stop && taskQueue.empty()) {
                            return;
                        }
						// 取出队列不能拷贝, 要移动
                        task = std::move(taskQueue.front()); 
                        taskQueue.pop();
                    }
                    // 执行任务
                    task();
                }
            });
        }
    }

    // 提交任务
    template <class F>
    void enqueue(F&& f) {
        {
            std::unique_lock<std::mutex> lock(queueMutex);
            if (stop) {
                throw std::runtime_error("ThreadPool is stopped");
            }
            taskQueue.push(std::forward<F>(f)); // 完美转发到队列中
        }
        condition.notify_one(); // 传入一个任务, 就激活等待中的一个线程
    }

    // 停止线程池
    void stopPool() {
        {
            std::unique_lock<std::mutex> lock(queueMutex);
            stop = true;
        }
        condition.notify_all();

        for (std::thread& worker : workers) {
            worker.join();
        }
    }

    ~ThreadPool() {
        if (!stop) {
            stopPool();
        }
    }

private:
    std::vector<std::thread> workers;           // 工作线程
    std::queue<std::function<void()>> taskQueue;  // 任务队列
    std::mutex queueMutex;                      // 任务队列互斥锁
    std::condition_variable condition;          // 条件变量
    std::atomic<bool> stop{false};              // 是否停止线程池
};

int main() {
    ThreadPool pool(4);  // 创建一个包含4个线程的线程池
    // 提交几个任务给线程池执行
    for (int i = 0; i < 10; ++i) {
        pool.enqueue([i] {
            std::cout << "Task " << i << " is being executed by thread " 
                      << std::this_thread::get_id() << std::endl;
        });
    }
    // 停止线程池
    pool.stopPool();
    return 0;
}
```

## 关于对线程库的进一步封装

通过对线程库的使用我们可以发现, 一旦我们生成thread对象, 线程就已经开始了, 这其实不利于我们对每个线程做精细化处理与记录线程的状态, 我们可以对线程库做进一步封装, 让我们可以随时控制线程的开始与结束并记录线程的状态.

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

static std::atomic_int32_t _numCreated = 0;

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
    _thread = std::make_shared<std::thread>(new std::thread([&](){
        _tid = CurrentThread::tid();
        sem_post(&sem);
        _func(); 	// 在这里真正执行传入的回调函数
    }));

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

我们用智能指针控制thread, 直到我们使用start()才会时线程真正开始, 并且也记录了线程的运作状态与线程id.
