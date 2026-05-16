---
title: boost::asio网络库
date: 2025-7-8 19:00:00
tags: [boost::asio]
---

> 主要学习asio网络库有关异步方面的使用 

这里先给出一个最简便的TCP异步echo服务器 : 

```cpp
// async_echo_server.cpp
#include <boost/asio.hpp>
#include <iostream>
#include <memory>

using boost::asio::ip::tcp;

class Session : public std::enable_shared_from_this<Session>
{
public:
    Session(tcp::socket socket) : socket_(std::move(socket)) {}

    void start() { do_read(); }

private:
    void do_read()
    {
        auto self(shared_from_this());
        socket_.async_read_some(boost::asio::buffer(data_, max_length),
                                [this, self](boost::system::error_code ec, std::size_t length)
                                {
                                    if (!ec)
                                        do_write(length);
                                });
    }

    void do_write(std::size_t length)
    {
        auto self(shared_from_this());
        boost::asio::async_write(socket_, boost::asio::buffer(data_, length),
                                 [this, self](boost::system::error_code ec, std::size_t /*length*/)
                                 {
                                     if (!ec)
                                         do_read();
                                 });
    }

    tcp::socket socket_;
    enum
    {
        max_length = 1024
    };
    char data_[max_length];
};

class Server
{
public:
    Server(boost::asio::io_context &io_context, short port)
        : acceptor_(io_context, tcp::endpoint(tcp::v4(), port))
    {
        do_accept();
    }

private:
    void do_accept()
    {
        acceptor_.async_accept(
            [this](boost::system::error_code ec, tcp::socket socket)
            {
                if (!ec)
                    std::make_shared<Session>(std::move(socket))->start();
                do_accept();
            });
    }

    tcp::acceptor acceptor_;
};

int main()
{
    try
    {
        boost::asio::io_context io_context;
        Server server(io_context, 12345);
        io_context.run(); // 事件循环
    }
    catch (std::exception &e)
    {
        std::cerr << "Exception: " << e.what() << "\n";
    }
    return 0;
}
```

- main部分 : 
  - io_context : 事件循环核心句柄, 通过调用run来开始运作.
- Server : 服务器类, 使用acceptor接受并处理连接.
  - acceptor : 这里网络库自带的acceptor类, 只要我们把句柄和绑定需要的数据传入, 在其构造函数中就会自动调用socket + bind + listen.
  - endpoint : 这就是一个存放用于绑定数据的类.
  - async_accept : 在新连接建立时, 会调用传入的回调函数, 参数要求为(boost::system::error_code ec, tcp::socket socket), 这样就可以取出socket进行操作, 这里调用了Session类的start, 会针对连接进行处理.
- Session : 会话类, 处理每一条的连接的读写.
  - async_read_some : 在读事件触发时向准备好的缓冲区存入读到的数据, 然后触发其中给出的回调函数, 可以在回调中进行数据处理, echo服务器所以直接调用do_write准备发回.
  - async_write : 传入目标socket, 数据缓冲区, 回调函数, 就可以在发送完数据后调用回调再度调用do_read进入读事件等待阶段.

### 有关异步使用递归回调的设计哲学

在同步Reactor模型中,  处理事件循环我们往往会使用while直接处理, 就像下面这样 : 

```cpp
while(true)
{
	read();     // 这里一般是阻塞的
	process();
	write();
}
```

但是while在异步中是使用不了的, 异步强调的是控制流的保持, 其没有任何地方是会阻塞的, 核心全在于回调函数如何处理, 假如我们要让逻辑实现一个闭环, 那就要使用递归回调实现类似于循环的效果.

```cpp
async_read(..., [](...) {
    process();
    async_write(..., [](...) {
        again_read();
    });
});
```

上面的echo就是这样的逻辑, 读完进行处理, 处理完发送, 发送完再注册读事件, 这样就类似于实现了一个天然的状态机, 并且可以使线程资源最大化.

### enable_shared_from_this

我们可以看到Session类继承了该类, 其作用在于可以使成员函数内部调用`shared_from_this()`, 该函数会返回当前类对象的智能指针, 其实就是对this进行了封装.

其作用的核心在于**延长对象的生命周期**. 这里应用到异步中, 就是可以使构建出来的Session对象始终不被析构, 就算没有实际的对象去管理它们. 因为我们的self对象会一直被lambda捕获, 其内部Session对象就不会被析构. 这里要明白一个知识 : **只要 lambda 回调函数中捕获了 `shared_ptr`(哪怕它还没执行),对象的引用计数就会保持 +1**. 

更进一步理解, 我们可以发现, Session类在accept函数中被make_shared出来, 在离开了这个回调函数后其实shared_ptr计数就会-1. 但是Session并不会析构, 因为已经调用了start, 整个逻辑链路已经开启, 在do_read和do_write中都会在lambda中捕获self, 计数永远不会降到0, 也就是**其生命周期不再和作用域有关, 会一直在这个逻辑链路中存在下去**.

### 多线程版本

上面只是单线程版本的, 但是并发量由于异步存在已经足够高, 几万并发没什么问题, 当然我们也可以写多线程版本的, 其实只要再main函数中做修改就可以了 : 

```cpp
int main()
{
    try
    {
        boost::asio::io_context io_context;

        Server server(io_context, 12345);

        // 获取系统线程数（你也可以写固定值如 4）
        int thread_count = std::thread::hardware_concurrency();
        std::cout << "Start with " << thread_count << " threads\n";

        // 创建线程池，所有线程调用 io_context.run()
        std::vector<std::thread> threads;
        for (int i = 0; i < thread_count; ++i)
        {
            threads.emplace_back([&io_context]() {
                io_context.run();
            });
        }

        // 等待所有线程结束（实际永不结束）
        for (auto &t : threads)
            t.join();
    }
    catch (std::exception &e)
    {
        std::cerr << "Exception: " << e.what() << "\n";
    }
    return 0;
}
```

io_context作为核心句柄, 你可以理解其内部存在一个线程安全的消息队列, 用其在不同线程调用run(), 其实是让每个线程都可以从自己的消息队列中利用互斥锁线程安全地获取任务.

当然如果学过muduo, 我们也可以采用`one loop per thread`的思想, 一个事件循环对应一个线程, 这样就可以避免消息队列中的锁竞争了, 下面是多io_context多线程版本 : 

```cpp
#include <boost/asio.hpp>
#include <iostream>
#include <memory>
#include <thread>
#include <vector>

using boost::asio::ip::tcp;

// 一个 echo 会话
class Session : public std::enable_shared_from_this<Session>
{
public:
    Session(tcp::socket socket) : socket_(std::move(socket)) {}

    void start() { do_read(); }

private:
    void do_read()
    {
        auto self = shared_from_this();
        socket_.async_read_some(boost::asio::buffer(data_),
                                [this, self](boost::system::error_code ec, std::size_t length)
                                {
                                    if (!ec)
                                        do_write(length);
                                });
    }

    void do_write(std::size_t length)
    {
        auto self = shared_from_this();
        boost::asio::async_write(socket_, boost::asio::buffer(data_, length),
                                 [this, self](boost::system::error_code ec, std::size_t /*len*/)
                                 {
                                     if (!ec)
                                         do_read();
                                 });
    }

    tcp::socket socket_;
    enum
    {
        max_length = 1024
    };
    char data_[max_length];
};

// 每个 worker 包含一个 io_context 和它自己的线程
struct Worker
{
    boost::asio::io_context io_context;
    boost::asio::executor_work_guard<boost::asio::io_context::executor_type> work_guard;
    std::thread thread;

    Worker() : work_guard(boost::asio::make_work_guard(io_context)) {}

    void run()
    {
        thread = std::thread([this]()
                             { io_context.run(); });
    }

    void stop()
    {
        io_context.stop();
        if (thread.joinable())
            thread.join();
    }
};

// Server 只负责监听和分发连接
class Server
{
public:
    Server(boost::asio::io_context &main_io_context, short port, std::vector<std::shared_ptr<Worker>> &workers)
        : acceptor_(main_io_context, tcp::endpoint(tcp::v4(), port)), workers_(workers)
    {
        do_accept();
    }

private:
    void do_accept()
    {
        acceptor_.async_accept(
            [this](boost::system::error_code ec, tcp::socket socket)
            {
                if (!ec)
                {
                    // Round-Robin 分发连接
                    auto &worker = workers_[next_worker_];
                    boost::asio::post(worker->io_context, [sock = std::move(socket)]() mutable
                                      { std::make_shared<Session>(std::move(sock))->start(); });
                    next_worker_ = (next_worker_ + 1) % workers_.size();
                }
                do_accept(); // 继续接受
            });
    }

    tcp::acceptor acceptor_;
    std::vector<std::shared_ptr<Worker>> &workers_;
    std::size_t next_worker_ = 0;
};

int main()
{
    try
    {
        const int thread_count = std::thread::hardware_concurrency();
        std::cout << "Starting server with " << thread_count << " threads\n";

        // 主 io_context 只用于 acceptor
        boost::asio::io_context main_io_context;

        // 创建 worker 池
        std::vector<std::shared_ptr<Worker>> workers;
        for (int i = 0; i < thread_count; ++i)
        {
            auto w = std::make_shared<Worker>();
            w->run();
            workers.push_back(w);
        }

        // 启动服务器（监听 + 分发连接）
        Server server(main_io_context, 12345, workers);

        // 主线程运行 acceptor 的 io_context
        main_io_context.run();

        // 停止所有工作线程（程序退出时）
        for (auto &w : workers)
            w->stop();
    }
    catch (std::exception &e)
    {
        std::cerr << "Exception: " << e.what() << "\n";
    }

    return 0;
}
```

这里的核心修改在Server和Worker中, Session中没有变动.

- 主体思路就是由主io_context控制Server, 生成Worker线程存入线程池中, Server将新连接分发到Worker中.

- Worker : 

  - 每个Worker中都会控制一个io_context, work_guard 和 thread.
  - io_context 用来在run时在线程中开始监听.
  - work_guard 的作用是**防止io_context在调用run时因为没有任务而立刻退出**, 所以我们如果要在多线程情况下使用线程池的话, 必须要使用work_guard, 其会时run函数就算没有任务, 也会在此阻塞等待任务.

- Server : 

  - workers_ : main函数中会创建worker线程存入数组, Server构造函数需要传入这个数组.

  - 每当接收到一个新连接时, 就会轮询取出一个工作线程, 利用asio库中的post向指定的工作线程中建立监听.

    - ```cpp
      boost::asio::post(worker->io_context, [sock = std::move(socket)]() mutable { std::make_shared<Session>(std::move(sock))->start(); });
      ```

      我们在每个worker中都会存入其对应的io_context, 再在回调函数中建立新的会话, 就可以让工作线程执行对新连接的监听了.

    - 注意这里的mutable是针对lambda的一种写法, 因为默认情况下, lambda表达式被捕获的变量是不可以被修改的, 因为lambda本身是const的, 但是如果加上mutable就可以进行任意修改了, 这里我们就是希望直接接管socket的使用权, 因此使用了mutable.

---

### executor(调度器)

调度器, 其实asio库用于调度的核心组件, 用于告诉任务应该在哪里(线程 / io_context / strand)执行, 在普通单线程和多线程异步中并没有提及, 是其在背后隐式调用. 但是我们后面会学习协程, 其需要显式调用调度器找到自己工作的线程与io_context,  故在此先行介绍.

一个 `io_context` 对应一个唯一的 `executor` 实例, 因此我们也可以通过`io.get_executor();`来直接获取调度器. 

在一个绑定了io_context的协程函数中我们就可以这样获取调度器 : 

```cpp
auto executor = co_await this_coro::executor;
```

### 协程版本

asio网络库也支持协程, 其配合C++20的协程可以写出更加简短的同步风格的异步代码 : 

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

可以看到代码非常短, 并且和同步代码风格非常相似, 但也有很多要点需要解读 : 

- 如果没有学过C++20协程编程可以看我往期的博客, 不然无法理解里面co_await的用法.

- co_spawn(事件循环句柄, 协程函数, 结束方式) :

  本函数用来将一个协程注册进入事件循环的executor(调度器)中, 其会先执行协程函数, 然后其中promise_type中起始回调设置的是suspend_always, 在开始就会暂停, 然后调用器会发布任务到事件循环中resume这个协程函数.

- `auto executor = co_await this_coro::executor;`

  获取绑定当前协程的executor, 可以当作固定不变的一步, 因为我们需要executor来构建acceptor.

- acceptor : 

  这里构建acceptor的构造可以理解为调用了其针对协程的特殊版本, 用executor来告诉其新连接建立时应把任务提交给对应的io_context.

- async_accept(use_awaitable) : 

  我们可以看到这里`async_accept`有对应的协程版本, 传入的`use_awaitable`代表将协程挂起, 其内部其实也会调用普通版本的`async_accept`, 只不过是在挂起前调用的回调函数中调用并进行异步处理, 在回调触发后再调用resume唤醒协程, 这些asio库都会在内部帮我们实现. 后面的`async_read_some`和`async_write`同理.

### strand(串行化)

它就是**对executor的进一步封装**, 也就是特殊的调度器. 用这个调度器发布的任务会**串行执行**, 也就是说其真正作用是**帮助协程间共享内存**, 是一种另类高效的**协程间通信**, 甚至你可以理解为一种**另类的锁**.

下面是一个使用共享map实现name记录的echo服务器, 我们只需要关系里面有关strand和map的内容即可 : 

```cpp
#include <boost/asio.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/asio/strand.hpp>

#include <iostream>
#include <unordered_map>
#include <memory>
#include <atomic>
#include <string>
#include <vector>
#include <thread>

using namespace boost::asio;
using namespace boost::asio::ip;
using namespace std::literals;

using awaitable_void = awaitable<void>;
using executor_t = any_io_executor;

std::unordered_map<int, std::string> nicknames;
std::shared_ptr<strand<executor_t>> strand_ptr;
std::atomic<int> connection_id{0};

/// 清理昵称（提取到独立协程）
awaitable_void cleanup_nickname(int id)
{
    co_await boost::asio::post(*strand_ptr, use_awaitable);
    nicknames.erase(id);
    co_return;
}

awaitable_void handle_client(tcp::socket socket)
{
    auto executor = co_await this_coro::executor;
    int id = connection_id.fetch_add(1);
    char data[1024];
    std::string nickname;

    try
    {
        std::string prompt = "请输入昵称: ";
        co_await async_write(socket, buffer(prompt), use_awaitable);

        std::size_t n = co_await socket.async_read_some(buffer(data), use_awaitable);
        nickname = std::string(data, data + n - 1); // 去掉换行符

        // 加入 nickname 映射（串行化）
        co_await boost::asio::post(*strand_ptr, use_awaitable);
        nicknames[id] = nickname;

        std::string hello = "你好，" + nickname + "！你现在可以发消息，我会帮你回显。\n";
        co_await async_write(socket, buffer(hello), use_awaitable);

        for (;;)
        {
            std::size_t len = co_await socket.async_read_some(buffer(data), use_awaitable);
            std::string input(data, data + len);

            std::string name;

            // 获取当前昵称（串行化）
            co_await boost::asio::post(*strand_ptr, use_awaitable);
            name = nicknames[id];

            std::string msg = "[" + name + "] 你说的是：" + input;
            co_await async_write(socket, buffer(msg), use_awaitable);
        }
    }
    catch (...)
    {
        // 不能在 catch 内使用 co_await，使用 co_spawn 调度清理任务
        co_spawn(executor, cleanup_nickname(id), detached);
    }
}

awaitable_void listener(uint16_t port)
{
    auto executor = co_await this_coro::executor;
    tcp::acceptor acceptor(executor, {tcp::v4(), port});

    for (;;)
    {
        tcp::socket socket = co_await acceptor.async_accept(use_awaitable);
        co_spawn(executor, handle_client(std::move(socket)), detached);
    }
}

int main()
{
    try
    {
        io_context io;

        // 创建全局 strand
        strand_ptr = std::make_shared<strand<executor_t>>(io.get_executor());

        // 启动监听协程
        co_spawn(io, listener(12345), detached);

        // 多线程 run
        std::vector<std::thread> threads;
        int n = std::thread::hardware_concurrency();
        for (int i = 0; i < n; ++i)
        {
            threads.emplace_back([&io]()
                                 { io.run(); });
        }

        for (auto &t : threads)
            t.join();
    }
    catch (const std::exception &e)
    {
        std::cerr << "Server error: " << e.what() << "\n";
    }

    return 0;
}
```

- `std::shared_ptr<strand<executor_t>> strand_ptr;`

  在全局设置一个串行化调度器的智能指针.

- `strand_ptr = std::make_shared<strand<executor_t>>(io.get_executor());`

  取出io_context对应的executor.

- `co_await boost::asio::post(*strand_ptr, use_awaitable);`

  在协程函数中, 所有有关全局变量map的操作前都会加这么一段代码, 其post的任务并没有什么实际作用, 其目的只在于**让后面的代码串行化执行**, 以此防止共享资源的竞争. 当我们把这段代码当成一个锁来看, 就会豁然开朗许多, 那么这个锁的范围是什么? 答案是**下一次挂起(co_await)或最后返回(co_return)时**, 在这之后才会串行化执行后面的任务. 

  当然这里只是利用strand实现协程间资源共享, 普通的线程间资源共享也是可以实现的 : 

  ```cpp
  boost::asio::post(strand, [key, value]() {
      shared_map[key] = value;  // 串行安全访问
  }); // 像这样子普通在一个线程中使用串行也是可行的!
  ```

---

### boost::asio的优势

- 支持回调, 协程等多种异步模型.
- 跨平台
- 对于C++20协程原生支持
- 有strand实现多线程多协程下的资源共享
