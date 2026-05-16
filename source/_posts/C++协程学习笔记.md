---
title: C++ 协程学习笔记
date: 2025-7-7 19:00:00
tags: [协程]
---

协程是可以理解为一个可以被暂停(挂起)和唤醒的函数, 系统会帮助你保存协程函数中的局部变量.

## 协程 vs 线程

协程和线程几乎没有任何联系, 它们是相互独立的. 

- 对于执行时间比较短的任务, 不建议用线程来处理, 线程的创建, 调度, 销毁都是会占用资源的.
- 线程适合那些长时间的任务, 比如轮循或监控.
- 线程是一个实际的需要操作系统进行调度的对象, 而协程只是函数外加一些在底层跳来跳去的指令.

## C++协程特性

- **无栈**

  首先要理解每个函数建立都会申请自己的栈帧, 栈帧中存储的是自己当前的局部变量, 当函数调用return后属于该函数的栈帧也会随之销毁, 在栈中有比较明确的后进先出的顺序, 这和函数调用的方式也是一致的. 而协程也可以被视为一个函数, 但是有暂停和唤醒的功能, C++的协程是无栈的, 其实是说协程函数没有自己的栈帧, 取而代之的是其会在堆上申请一片区域代替栈帧的作用, 替自己记录局部变量及协程信息, 在堆上也契合其要暂停唤醒的功能. 

## C++20协程使用

现在开始我们将会开始以关键字`co_await`为中心, 实现一个最简易的协程调用.

先认识一下`co_await` :  

这是在协程函数中进行协程挂起的关键字, 其后方要加上可挂起类(Awaitable)来辅助协程的挂起和恢复, 形如`co_wait Awaitable;` , 可挂起类后面细讲, 只要知道协程函数执行到co_await处就会进行暂停返回调用方(也不一定非得是调用方)就行了.

### 两个核心类

首先我们要明确实现协程需要两个核心类, 这两个类C++20协程中有明确规定要符合一定的规范 : 

- **返回对象类** : 构建返回对象类的原因有两点.

  - 协程作为函数, 调用方可能需要协程函数返回一些结果, 因此可以存在返回对象类中.

  - 协程的效果是可以被暂停和唤醒, 暂停是协程函数内部执行的, 但唤醒需要调用方执行, 因此返回对象类还要有可以恢复协程运行的功能.

  - **编写规范** : 形如下 

    ```cpp
    // 返回对象类
    // 持有整个协程的句柄, 在协程被挂起时其被交给调用方, 用其可再次唤醒协程
    struct CoRet
    {
        struct promise_type
        {
            // 控制协程开始和结束时是否暂停的函数
            suspend_never initial_suspend() { return {}; }
            suspend_never final_suspend() noexcept { return {}; }
            // 控制发生异常时的调用
            void unhandled_exception() {}
            // 控制协程最后返回得到的对象
            CoRet get_return_object()
            {
                return {coroutine_handle<promise_type>::from_promise(*this)};
            }
        };
        coroutine_handle<promise_type> _h;
    };
    ```

    - 类名怎么起都行, 但是内部一定要有名为`promise_type`的结构体, 其中必须编写所示的四个函数, 功能都有标注, 要注意的是promise_type对象是可以实际被协程句柄调用到的, 也就是说我们可以在其中存自定义句段存储数据. 
    - 前两个函数的返回值可以改, 返回`suspend_never`代表不暂停, 返回`suspend_always`代表暂停.
    - 最后一个函数可以返回当前类对象的指针, 可以让调用方获取返回类对象.
    - 一定要有类型为`coroutine_handle<promise_type>`的`_h`作为协程句柄, 这就是前面说的让调用方可以控制协程唤醒的关键, 这个类型中有成员函数`resume()`, 调用即可唤醒.

- **可挂起类** : 

  可挂起类用来辅助co_await进行线程的暂停和唤醒, 那么可以帮些什么呢?

  - 可以用来确定co_await是否生效, 也就是说是否真的要暂停.
  - 可以决定线程暂停前和唤醒时调用的回调.

  - 编写规范 : 形如下 

    ```cpp
    struct Input
    {
        Note &note;
        // 当前对象是否不需要挂起, 返回ture就会立即往下执行, 返回false会立即挂起, 等待外部resume
        bool await_ready() { return false; }
        // 如果前面返回false, 在挂起前会调用此函数, 做挂起前的准备
        void await_suspend(coroutine_handle<CoRet::promise_type> h)
        {
            // h.promise()
        }
        // 被唤醒后调用的函数
        int await_resume() { return note.val; }
    };
    ```

    - 还是类名怎么起都行, 先不管Note类, 下面的三个函数必须要有, 作用已经标注.

    - 注意三个函数中只有await_suspend可以获取到协程句柄, 也就是说其可以通过句柄控制唤醒的时机(比如异步设置一个回调, 回调中触发resume()). 如果await_resume也想要用句柄, 需要提前在await_suspend中保存下句柄才行.

    - await_resume有一个返回值, 你可以填void, 也就是什么都不返回, 但如果协程被唤醒时, 你有想从调用方获取的数据时, 可以通过此处设置返回类型. 也就是说我们可以这样写 : 

      ```cpp
      int g = co_await input;
      ```

      我们在await_resume中返回的值就会在协程函数中被g获取.
      
    - 其实前面在返回对象类中前两个函数的返回值suspend_never和suspend_always其实就是协程库内置的标准可挂起类, 没有其他任何作用, 只是为了确定是否要暂停线程. 所以如果完全不需要数据传输等别的功能, 也可以直接`co_await suspend_always{};`来实现暂停. 

### 协程函数与main函数的编写

在构建出上面两个类后, 我们来考虑编写出一个最简单的协程 : 

```cpp
#include <coroutine>
#include <iostream>
#include <optional>
using namespace std;

// 返回对象类
// 持有整个协程的句柄, 在协程被挂起时其被交给调用方, 用其可再次唤醒协程
struct CoRet
{
    struct promise_type
    {
        // 控制协程开始和结束时是否跳回的函数
        suspend_never initial_suspend() { return {}; }
        suspend_never final_suspend() noexcept { return {}; }
        void unhandled_exception() {}
        // 控制协程最后返回得到的对象
        CoRet get_return_object()
        {
            return {coroutine_handle<promise_type>::from_promise(*this)};
        }
    };
    coroutine_handle<promise_type> _h;
};

// ----------------------------------------------------------------------------------- //

struct Note
{
    int val;
    void set(int x) { val = x; }
};

// Awaitable 可挂起对象
// 协程函数中会有co_await等关键字, 与其相关的类必须符合Awaitable的标准(三个函数)
// 其用来帮助执行挂起的行为, 使得调用方可以和协程内部进行数据沟通
struct Input
{
    Note &note;
    // 当前对象是否不需要挂起, 返回ture就会立即往下执行, 返回false会立即挂起, 等待外部resume
    bool await_ready() { return false; }
    // 如果前面返回false, 在挂起前会调用此函数, 做挂起前的准备
    void await_suspend(coroutine_handle<CoRet::promise_type> h)
    {
        // h.promise()
    }
    // 被唤醒后调用的函数
    int await_resume() { return note.val; }
};

// ----------------------------------------------------------------------------------- //
// 协程函数
CoRet Guess(Note &note)
{
    // 协程函数最初都会生成一个promise_type的对象, 其负责一切管理协程生命周期内的一切行为
    // CoRet::promise_type promise;
    // 设置协程最后的返回对象, 其实就是把协程句柄传出去, 使外部可以获取协程内部的数据.
    // CoRet ret = promise.get_return_object();
    // co_await promise.initial_suspend();

    Input input{note};
    int g = co_await input;
    cout << "coroutine: You guess " << g << endl;

    // co_await promise.final_suspend();
}

// ----------------------------------------------------------------------------------- //

int main()
{
    Note note;
    auto ret = Guess(note);
    cout << "main : make a guess ..." << endl;

    note.set(6);

    // 恢复协程的运行
    ret._h.resume();
}
```

执行可执行文件我们可以得到 : 

```cpp
main : make a guess ...
coroutine: You guess 6
```

先说明这个协程干了些什么 : main函数中调用协程函数, 协程函数利用传入的note构造Input对象, 执行到co_await暂停, main函数设置note值后恢复协程, 协程打印我们在main中设置的note值.

- 这里面有关note值的设置, 目的是为了展示调用方和协程之间的数据交互, 我们可以看到note在main中构造后传入协程函数, 将其记录在input中, 于是我们便可以在main中设置note值让协程中的input看到, 进而提供给协程函数.

- 可以看到协程函数中有很多注释, 这些其实是运行时内部会加上去的代码, 其会根据我们构建的promise_type生成对象, 并以此调用我们设置的函数. 由此我们可以很明显地感觉到, 返回对象类的作用在于整个协程的把握, 其控制住了整个函数的始终与返回值. 而可挂起对象则辅助我们更好地实现协程函数的暂停和唤醒.

### co_yield / co_return

学习完了`co_await`后再去学习`co_yield`就简单多了, 这个其实类似于一个语法糖, 其在底层会被替换为co_await : 

```cpp
co_yield 42;
co_await promise.yield_value(42);  // 替换为
```

根据替换的形式, 可以推断我们需要在promise_type中构造一个yield_value函数, 形如 : 

```cpp
int _out;
// ...
suspend_always yield_value(int x)
{
	_out = x;
    return {};
}
```

- _out 是我们在promise_type中自定义的句段, 用来存储想告诉调用方的信息.
- yield_value必须返回一个awaitable对象, 这里我们直接使用内部自带的suspend_always, 表示我们需要暂停.

于是我们就是可以在外部通过句柄取得_out值来进行通信了, 其实 co_yield 在底层只是实现了一层替换, 其他什么都没有做, 但是其本身的目的是**产生一个值并跳转返回给调用方**, 所以我们需要自己在 promise_type中自定义句段存储传入的值, 再在外部取出, 做法相当原始, 但就是这样.

`co_return`就更简单了, 其只负责让我们自己记录希望给调用方的返回值, 一般被放置在协程函数的最后表示协程的结束, 底层替换如下 : 

```cpp
co_return res;
promise.return_value(res); // 替换为
```

替换完其实就帮我调用了return_value这个函数, 其形如 : 

```cpp
int _res;
// ...
void return_value(int r)
{
    _res = r;
}
```

其实还是要我们自己手动记录, 非常原始. 

至此我们可以进行一次简单的猜数字 : 

```cpp
#include <coroutine>
#include <iostream>
#include <optional>
using namespace std;

struct CoRet
{
    struct promise_type
    {
        int _out;
        int _res;
        // 控制协程开始和结束时是否跳回的函数
        suspend_never initial_suspend() { return {}; }
        suspend_always final_suspend() noexcept { return {}; }
        void unhandled_exception() {}
        // 控制协程最后返回得到的对象
        CoRet get_return_object()
        {
            return {coroutine_handle<promise_type>::from_promise(*this)};
        }

        suspend_always yield_value(int x)
        {
            _out = x;
            return {};
        }

        void return_value(int r)
        {
            _res = r;
        }
    };
    coroutine_handle<promise_type> _h;
};

struct Note
{
    int val;
    void set(int x) { val = x; }
};

struct Input
{
    Note &note;
    bool await_ready() { return false; }
    void await_suspend(coroutine_handle<CoRet::promise_type> h) {}
    int await_resume() { return note.val; }
};

CoRet Guess(Note &note)
{
    int res = (rand() % 30) + 1;
    Input input{note};
    int g = co_await input;
    cout << "coroutine: You guess " << g << endl;

    co_yield (res < g ? 1 : (res == g ? 0 : -1));
    // co_await promise.yield_value();

    co_return res;
    // promise.return_value();
    // co_await promise.final_suspend();
}

int main()
{
    srand(time(nullptr));
    Note note;
    auto ret = Guess(note);
    cout << "main : make a guess ..." << endl;

    note.set(6);

    // 恢复协程的运行
    ret._h.resume();

    cout << "main: your guess is " << ((ret._h.promise()._out) == 1 ? "larger" : ((ret._h.promise()._out == 0) ? "the same" : "smaller")) << endl;

    ret._h.resume();

    if (ret._h.done())
    {
        cout << "main: the result is " << ret._h.promise()._res << endl;
    }
    ret._h.destory();
    return 0;
}
```

运行后的结果如下 : 

```cpp
➜  boostasiolearn ./coroutinetest                                            
main : make a guess ...
coroutine: You guess 6
main: your guess is smaller
main: the result is 7
```

- done : 其作用在于**判断当前协程是否进入了 `final_suspend()` 并且已挂起**, 也就是说这是一个调用方用来判断线程是否结束的函数, 如果已经结束, 就可以通过句柄取出希望的结果.
- destory : 销毁协程资源, 必须调用, 否则会内存泄露.

### 完整的猜数字游戏

```cpp
#include <coroutine>
#include <iostream>
#include <optional>
using namespace std;

struct CoRet
{
    struct promise_type
    {
        int _out;
        int _res;
        // 控制协程开始和结束时是否跳回的函数
        suspend_never initial_suspend() { return {}; }
        suspend_always final_suspend() noexcept { return {}; }
        void unhandled_exception() {}
        // 控制协程最后返回得到的对象
        CoRet get_return_object()
        {
            return {coroutine_handle<promise_type>::from_promise(*this)};
        }

        suspend_always yield_value(int x)
        {
            _out = x;
            return {};
        }

        void return_value(int r)
        {
            _res = r;
        }
    };
    coroutine_handle<promise_type> _h;
};

struct Note
{
    int val;
    void set(int x) { val = x; }
};

struct Input
{
    Note &note;
    bool await_ready() { return false; }
    void await_suspend(coroutine_handle<CoRet::promise_type> h) {}
    int await_resume() { return note.val; }
};

CoRet Guess(Note &note)
{
    int res = (rand() % 99) + 1;

    Input input{note};

    while (true)
    {
        int g = co_await input;

        co_yield (res < g ? 1 : (res == g ? 0 : -1));
        if (res == g)
            break;
    }

    co_return res;
}

int main()
{
    srand(time(nullptr));
    Note note;
    auto ret = Guess(note);
    cout << "main : make a guess ..." << endl;

    while (true)
    {
        cout << "please input your guess: ";
        int x;
        cin >> x;
        note.set(x);
        // 恢复协程的运行
        ret._h.resume();
        cout << "your guess is " << ((ret._h.promise()._out) == 1 ? "larger" : ((ret._h.promise()._out == 0) ? "the same" : "smaller")) << endl;
        if (ret._h.promise()._out == 0)
            break;
        ret._h.resume();
    }

    // 执行到co_return
    ret._h.resume();

    if (ret._h.done())
    {
        cout << "the result is " << ret._h.promise()._res << endl;
    }
    ret._h.destroy();
    return 0;
}
```

运行如下 : 

```cpp
➜  boostasiolearn ./coroutinetest                                            
main : make a guess ...
please input your guess: 50
your guess is larger
please input your guess: 25
your guess is larger
please input your guess: 15
your guess is smaller
please input your guess: 20
your guess is the same
the result is 20
```

### 与boost::asio网络库联动

asio网络库对C++20协程提供了原生支持, 也就是说我们可以用aiso网络库更简便的实现代码编写, 在前面学习协程使用时, 相信大家都会认为为了使用协程还要编写两个核心类很麻烦, 但那很多时候不一定非得是我们的工作, 之后会有更多的协程库会帮我实现这些类的编写, asio网络库就是其中之一, 我们只需要关注于协程函数的编写就行了.

下面是利用boost::asio网络库编写的简易Tcp回显服务器 : 

```cpp
#include <boost/asio.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/asio/detached.hpp>
#include <iostream>

using boost::asio::ip::tcp;
using namespace boost::asio;
using namespace std::literals;

// Echo 处理协程
awaitable<void> echo_session(tcp::socket socket)
{
    try
    {
        char data[1024];
        for (;;)
        {
            // 异步读取数据
            std::size_t n = co_await socket.async_read_some(buffer(data), use_awaitable);
            // 异步写回数据
            co_await async_write(socket, buffer(data, n), use_awaitable);
        }
    }
    catch (std::exception &e)
    {
        std::cerr << "Session ended: " << e.what() << "\n";
    }
}

// 接受连接并启动协程
awaitable<void> listener(uint16_t port)
{
    // 获取绑定当前协程的executor, 可以通过其获取io_context
    auto executor = co_await this_coro::executor;
    tcp::acceptor acceptor(executor, tcp::endpoint(tcp::v4(), port));

    for (;;)
    {
        // 异步等待连接事件发生返回socket
        tcp::socket socket = co_await acceptor.async_accept(use_awaitable);
        // 再注册新的协程函数并触发
        co_spawn(executor, echo_session(std::move(socket)), detached);
    }
}

int main()
{
    try
    {
        io_context io;
        // 启动协程
        co_spawn(io, listener(12345), detached);
        io.run(); // 开始事件循环
    }
    catch (const std::exception &e)
    {
        std::cerr << "Server error: " << e.what() << "\n";
    }

    return 0;
}
```

可以看到代码行数非常少, 并且代码风格不像异步那样复杂, 是否解决同步, 但底层却是异步的!

如果没有学过asio网络库可能有些难以理解, 我之后的博客会出, 最好先学习过再理解.

- co_spawn : 

  其作用是将协程函数作为任务绑定到事件循环的调度器中去, 会先执行协程函数, 并且这里awaitable在内部promise_type中的起始回调会被设置为suspend_always, 会由调度器发布任务到事件循环中来resume协程.

- 我们可以看到很多co_await后面都会跟着一些网络库函数, 这些其实就是这些网络库函数的协程重载版本, 也可以隐约感觉到其肯定会返回一个awaitable对象, 以`async_accept`为例, 其返回的对象类型大概是这样的 : 

  ```cpp
  template <>
  class awaitable<tcp::socket>
  {
  public:
      struct awaiter
      {
          tcp::acceptor& acceptor_;
          tcp::socket socket_;
          std::coroutine_handle<> handle_;
          boost::system::error_code ec_;
  
          bool await_ready() const noexcept { return false; }
  
          void await_suspend(std::coroutine_handle<> h)
          {
              handle_ = h;
              acceptor_.async_accept(
                  socket_,
                  [this](boost::system::error_code ec)
                  {
                      ec_ = ec;
                      handle_.resume();
                  });
          }
  
          tcp::socket await_resume()
          {
              if (ec_)
                  throw boost::system::system_error(ec_);
              return std::move(socket_);
          }
      };
  
      awaiter operator co_await() const
      {
          return awaiter{...};  // 用构造器填入 acceptor/socket 等
      }
  };
  ```

  可以看到其在协程暂停前的回调中会调用自己的普通版函数, 将异步任务发布给事件循环, 当socket触发后, 事件循环就会帮我们执行这段代码进而resume协程. 也就是说其思路其实是把resume的时机交给事件循环判断, 非常高明.

回显服务器只是boost::asio网络库与C++20最简单的联动, 还有很多更复杂的设计值得学习, 比如利用strand串行化调度实现协程间资源共享, 这里就不再详述.



by  天目中云
