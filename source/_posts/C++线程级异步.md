---
title: C++线程级异步
date: 2025-9-3 21:00:00
tags: [异步]
---

### async

async做到的只是简单的线程级异步, 并非像boost:asio那样的内核级异步, 其优势大概也就是简单了.

因此只适合做一些简单的异步任务, 但是其功能和线程池重合, 如果使用了线程池就没有必要使用async了.

```cpp
// 启动异步任务
std::future<int> fut = std::async(compute, 10, 20);
// 获取结果（会阻塞直到结果可用）
int result = fut.get();
```

### future

future内部可以封装一个类型, 这个类型的值在一开始可能并没有被计算出来, future可以通过调用get获取这个值, 如果值已被计算出来就马上返回, 还没就阻塞在这里等待.

```cpp
std::future<int> fut = std::async(std::launch::async, computeSomething);
// ...
int result = fut.get();
```

其关键点在于 : 

- 存在时间跨度 : 

  先给出future, 在之后再调用get, 在获取结果之前可以有更丰富的操作, 并且有时间跨度才能有对异步的支持.

- 对异步并行的支持 : 

  **有时间跨度 + 线程间通信**, 使得future可以让异步操作有了返回值的功能, 可以跨线程接收异步操作的结果, 当我们可以使用其他线程执行任务并返回内容到主线程时, 我们可以利用并行的优势提高运行效率.

那么关键在于**如何产生一个future**?

大体有三种办法 : 

- async : 

  async可以接收一个函数对象, 将其放到一个线程中去执行, 会返回一个future对象, 其封装类型就是该函数的返回值, 当另一个线程中的该函数执行完就会填充这个future.

  ```cpp
  // 利用future + async可以实现并行计算
  #include <vector>
  #include <future>
  #include <numeric>
  
  int parallelSum(const std::vector<int>& data, size_t start, size_t end) {
      return std::accumulate(data.begin()+start, data.begin()+end, 0);
  }
  
  int main() {
      std::vector<int> data(1000, 1); // 1000个1
      
      // 分成4部分并行计算
      std::future<int> fut1 = std::async(std::launch::async, parallelSum, std::ref(data), 0, 250);
      std::future<int> fut2 = std::async(std::launch::async, parallelSum, std::ref(data), 250, 500);
      std::future<int> fut3 = std::async(std::launch::async, parallelSum, std::ref(data), 500, 750);
      std::future<int> fut4 = std::async(std::launch::async, parallelSum, std::ref(data), 750, 1000);
      
      // 合并结果
      int total = fut1.get() + fut2.get() + fut3.get() + fut4.get();
      std::cout << "Total sum: " << total << std::endl;
      
      return 0;
  }
  ```

- promise : 

  向promise中填充类型, 使用get_future()便可以返回对应类型的future. 可以让其他线程传入promise对象, 其他线程可以在适合的场景调用set_value来填充future. 这算是future最基础的用法.

  ```cpp
  std::promise<int> result_promise;
  auto result_future = result_promise.get_future();
  
  std::thread t([&] {
      // 耗时计算
      int result = heavy_computation();
      result_promise.set_value(result);
  });
  
  // 主线程可以做其他事情
  do_something_else();
  
  // 当需要结果时
  int final_result = result_future.get();
  t.join();
  ```

- packaged_task : 

  该类型可以封装任务(函数回调), 并返回获取该任务对应的返回值future. 人话说就是对一个函数进行改造, 使其return的那个返回值可以被future获取.

  ```cpp
  int foo(double, char);  // 函数签名是 int(double, char)
  std::packaged_task<int(double, char)> task(foo);  // 匹配签名
  ```

  可以理解为**functional和promise的组合**, 我们可以传入函数来放入packaged_task, 注意前面模板参数存入的函数前面要与放入的实际函数匹配.

  于是我们就可以从中获取future : 

  ```cpp
  std::future<int> fut = task.get_future();
  // ...
  int ret = fut.get();
  ```

有了上面三种产生future的方法后, 我们就可以将future嵌入到一些需求异步的场景中 : 

以**线程池**为例, 下面是最简单的一种线程池 : 

```cpp
#pragma once
#include <vector>
#include <thread>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <functional>
#include <future>

#include "uncopyable.h"
using namespace std;

class ThreadPool : public Uncopyable {
public:
	using Task = function<void()>;

    ThreadPool(size_t n = thread::hardware_concurrency())
        : isstop(false), running_cnt(0)
    {
        if (n == 0) n = 1;
        pool_.reserve(n);
        for (size_t i = 0; i < n; ++i) {
            pool_.emplace_back([this] { thread_work(); });
        }
    }

    bool push(Task task) {
        lock_guard<mutex> lk(m_);
        if (isstop) return false;
        q_.push(move(task));
        cond_.notify_one();
        return true;
    }

    // 等待所有任务执行完
    void wait_all() {
        unique_lock<mutex> lk(m_);
        waitall.wait(lk, [this] {
            return q_.empty() && running_cnt == 0;
        });
    }

    void stop() {
        if (isstop) return;
        {
            lock_guard<mutex> lk(m_);
            isstop = true;
        }
        cond_.notify_all();
        for (auto& t : pool_) {
            if (t.joinable()) t.join();
        }
        pool_.clear();
    }

private:
    void thread_work() {
        while(true) 
        {
            Task task;

            {
                unique_lock<mutex> lk(m_);
                cond_.wait(lk, [this] {
                    return isstop || !q_.empty();
                    });
                if (isstop && q_.empty()) return;

                task = move(q_.front());
                q_.pop();
                ++running_cnt;
            }

            task();

            {
                lock_guard<mutex> lk(m_);
                if (--running_cnt == 0 && q_.empty()) {
                    waitall.notify_all();
                }
            }
        }
    }

	vector<thread> pool_;
    queue<Task> q_;
    mutex m_;
    condition_variable cond_;
    condition_variable waitall;
    bool isstop;
    int running_cnt; // 记录有多少线程正在执行任务
};
```

我们会发现这个线程池非常僵硬的一个点, 就是**只能投放无参数无返回值的任务**, 其他任何类型的任务都无法执行. 在学习了**可变参数和函数绑定**后, 我们可以实现**投放任意参数的任务** : 

```cpp
template<typename F, typename... Args>
void push(F&& f, Args&&... args) 
{
    auto task = std::bind(std::forward<F>(f), std::forward<Args>(args)...);
    {
        std::lock_guard<std::mutex> lk(m_);
        if (isstop) return;
        q_.push([task]() { task(); });
    }
    cond_.notify_one();
}
```

这里我们的思路是 : 

每个任务线程都会从队列中取出任务并通过`task();`执行, 这种形式最好不变, 因此任务线程拿到的任务都是无参数的任务. 我们的操作要将传入的有参函数转化为无参函数, 这就要依赖可变参数和函数绑定了.

我们通过可变参数接收各种类型的参数, 只要函数重载匹配, 就可以将其绑定到对应函数中, 把**原来需要的参数填满, 自然就变成无参函数了**, 那么我们就可以将其推入队列中, 注意这里推入的是`[task]() { task(); }`而非`task`, 因为就算绑定了类型也还未转变, 前者是在将函数调用的类型转化为`function<void()>`, 让其可以存入队列中.

因此我们可以通过如下方式处理带参数的任务 :

```cpp
int add(int a, int b) { return a + b; }
// ...
pool_.push(add, 1, 2);
```

但是我们会发现, 虽然现在线程池可以处理带参数的任务, 但是其实是**获取不到返回值**的!

仔细思考, **获取线程池任务返回值**其实是一个**经典的异步场景** : 

- 任务会被投入线程池中, 在一个线程中去运行.
- 投入任务后主线程希望获取返回值, 但不知道线程什么时候执行完成并返回.
- 任务在线程中需要有一个手段可以**与主线程通信并且传输返回值**.

那么这个手段就是使用future, 我们来看使用future升级后的push函数 : 

```cpp
template<typename F, typename... Args>
auto push(F&& f, Args&&... args) -> std::future<typename std::invoke_result_t<F, Args...>>
{
    using return_type = std::invoke_result_t<F, Args...>;

    auto task = std::make_shared<std::packaged_task<return_type()>>(
        std::bind(std::forward<F>(f), std::forward<Args>(args)...)
    );

    std::future<return_type> res = task->get_future();
    {
        std::lock_guard<std::mutex> lk(m_);
        if (isstop) return;
        q_.push([task]() { (*task)(); });
    }
    cond_.notify_one();
    return res;
}
```

我们的思路是 : 

既然希望获取任务的返回值, 那么我们**先确定这个任务返回值的类型**, 并以此**包装一个future**, **交给主线程**, 然后主线程再**利用get获取返回值**. 

我们来一步一步分析代码 : 

- `invoke_result_t`  : 

  这是C++17引入的一种模板元编程, 其最终表现为一种类型, 该类型是**其模板参数传入的函数回调及参数所指定函数版本的返回值类型**, 人话说就是给一个函数和其参数类型, 我去帮你找对应的返回值类型, 这里面包含了对函数重载的考虑.

  `invoke_result_t<F, Args...>`就是函数为F, 参数为Args...对应的返回值类型.

- `std::future<typename std::invoke_result_t<F, Args...>>`  : 

  实际返回一个包含了返回值类型的future对象, 外部就会通过这个对象调用get获取返回值.

- `return_type` : 记录返回值类型.

- `std::bind(std::forward<F>(f), std::forward<Args>(args)...)` : 

  和上一个版本一样, 将参数绑定到对应函数中, 返回的是一个**参数被填满的函数调用**.

- `std::packaged_task<return_type()>(bind(...))` :

  - 模板参数是`return_type()`, 表示返回值类型为return_type, 无参.
  - packaged_task将bind返回的函数对象进行包装, 返回一个**可执行的并把返回值存入futuer对象的任务**.

- `make_shared` :

  用来为包装过的任务对象添加智能指针. 主要原因是`packaged_task`包装的任务C++**禁止拷贝**, 但是我们希望传给其他线程进行调用, 那么就只能使用智能指针共享了.

- res : 从task中取出的future对象, 用来传到外部.

- `[task]() { (*task)(); }` : 

  和上一个版本同理, 但这里由于我们把任务封装进智能指针中了, 就需要先解引用出来.

至此我们可以向线程池中投入有无返回值, 参数任意的任务了!

```cpp
void func1() { ... }
void func2(int x) { ... }
int add(int a, int b) { return a + b; }
// ... 
pool.push(func1);
pool.push(func2, 1);
auto future = pool.push(add, 1, 2);
auto ret = future.get();
cout << ret << endl;
```



by 天目中云

