---
title: Rpc分布式网络通信框架(7) Zookeeper
date: 2025-6-26 12:00:00
tags: [RPC]
---

> 本章了解zookeeper的作用与简易的使用方式.

Zookeeper是一个使用非常广泛的**服务发现中间件**. 这个中间件为c/s模式, 也就是其会运行在一个服务器上, 其内部维护了一个特殊的文件系统, 可以存储大量的服务信息, 供客户端提取.

以本项目为例, 在上一章RpcChannel想要获取远程调用服务, 就必须知道提供该服务服务器的ip和port并存入配置文件中, 这样操作是非常原始且低效的. Zookeeper提供的解决方案是 : 我自己在服务器上提供一个服务, 可以存储各种服务名, 方法名及其对应的ip, port和各种服务信息, 供外部查询, 这样只要有了zookeeper的ip和port, 去这里查询有没有对应的服务及其方法就可以了, 在服务和方法量大时这种方式的处理就会尤其高效.

### znode节点

zookeeper服务专属的数据存储节点, 类似一个树, 用来存储服务, 一个节点最多存储1兆数据. 这就是zookeeper来存储服务方法信息的数据结构.

这些节点分为永久性节点和临时性节点, 永久性节点zk服务器不会删, 临时性节点在与zk服务器断连一段时间后就会自动删除, 我们一般非常乐意使用临时性节点, 在服务端正常提供服务时zk服务器可以正常搜索到, 在不提供服务时zk服务器就会及时删除.

另外我们在这里同时存储服务和方法, 你可以理解为方法一定是叶节点, 服务则都可.

### ZkCli使用

安装好zookeeper后, 我可以通过指令打开zookeeper的客户端 : 

```bash
./ZkCli.sh
```

zookeeper的主要操作就是在一棵树上创建/删除节点并设置数据 : 

- ls + 路径  :  查询当该处路径的所有子节点

  ```cpp
  [zk: localhost:2181(CONNECTED) 14] ls /
  [UserServiceRpc, sl, zookeeper]
  ```

  这里就表示根目录下有三个节点.

- create + 路径 + (数据) : 在指定路径创造节点并存入数据

  ```zookeeper
  [zk: localhost:2181(CONNECTED) 15] create /aaa 1
  Created /aaa
  [zk: localhost:2181(CONNECTED) 16] ls /
  [UserServiceRpc, aaa, sl, zookeeper]
  ```

- get + 路径 : 获取当前节点数据.

  ```cpp
  [zk: localhost:2181(CONNECTED) 17] get /aaa
  1
  ```

- delete + 路径 : 删除指定节点

  ```cpp
  [zk: localhost:2181(CONNECTED) 18] delete /aaa
  [zk: localhost:2181(CONNECTED) 19] ls /
  [UserServiceRpc, sl, zookeeper]
  ```

### watcher机制

如其名, 这个机制用来监视zookeeper变化, 客户端可以编写watcher函数作为回调函数, **当zookeeper中发生你关注的变化时, 会触发该回调**. 这种变化非常多样, 大到连接的建立, 小到各种节点的增删改查, 我们可以通过编写不同的watcher函数产生作用各异的监视效果.

这个机制可以挖掘的地方非常多, 但本项目先只用其帮助我们建立于zk服务器的连接, 在之后会细讲.

### Zookeeper 原生 CAPI 使用

下面介绍一下我们之后会用的原生API接口 : 

- zookeeper_init : 初始化 Zookeeper 客户端连接，返回一个 `zhandle_t*` 的句柄。所有操作都依赖这个句柄。

  ```cpp
  zhandle_t* zookeeper_init(
      const char* host,                  // ip:port, 如 "127.0.0.1:2181"
      watcher_fn watcher,                // 默认的 watcher 回调函数
      int recv_timeout,                  // session 超时时间（毫秒）
      const clientid_t* clientid,        // 恢复会话时使用，首次连接传 nullptr
      void* context,                     // 可传任意上下文信息
      int flags                          // 通常传 0
  );
  ```

  - 这里host字符串必须是`"ip:port"`这个样式, 属于一种约定.

  - 这里watcher需要我们填入一个默认的全局watcher回调函数, 这个函数的实际作用是帮我们**监听与zk服务器的会话状态**, 也就是连接相关的事物, 其参数是固定的, 我们在后文会深入说明.

- zoo_create : 建立一个znode节点.

  ```cpp
  int zoo_create(
      zhandle_t* zh,
      const char* path,                 // 节点路径
      const char* data,                 // 要存的数据
      int datalen,                      // 数据长度
      const struct ACL_vector* acl,    // 权限，通常传 &ZOO_OPEN_ACL_UNSAFE
      int flags,                        // 创建类型（见下）
      char* path_buffer,                // 实际创建的路径（可为顺序节点）
      int path_buffer_len
  );
  ```

  - 这里flags控制节点类型, 0为永久节点, `ZOO_EPHEMERAL`为临时节点.

- zoo_get : 获取目标节点下的数据.

  ```cpp
  int zoo_get(
      zhandle_t* zh,
      const char* path,
      int watch,		
      char* buffer,
      int* buffer_len,
      struct Stat* stat
  );
  ```

  - 注意这里watch填0无效果, 填1会帮你监视目标节点变化, 变化就调用我们在zoo_init中填入的默认watcher, 一般不会用, 如果真的需要监视节点变化, 一般会再写一个另外的watcher函数配合zoo_awget函数进行监视, 这里不再详述.

### 封装zookeeper类

因为zookeeper的原生API使用还是有些繁琐, 我们一般会写一个类封装这些行为 : 

```cpp
// zkcil.h
#pragma once
#include <semaphore.h> // 与zk客户端建立连接需要用到信号量
#define THREADED
extern "C"
{
#include <zookeeper/zookeeper.h>
}
#include <string>

class ZkClient
{
public:
    ZkClient();
    ~ZkClient();
    void start();
    void create(const char *path, const char *data, int datalen, int state = 0);
    std::string getData(const char *path);

private:
    zhandle_t *_zhandle; // 存储zoo_init返回的zk句柄
};
```

```cpp
// zkcil.cpp
#include "zookeepercli.h"
#include "mprpcapplication.h"
#include <iostream>

void global_watcher(zhandle_t *zh, int type, int state, const char *path, void *watcherCtx)
{
    if (type == ZOO_SESSION_EVENT && state == ZOO_CONNECTED_STATE)
    {
        sem_t *sem = (sem_t *)zoo_get_context(zh);
        sem_post(sem);
    }
}

ZkClient::ZkClient() : _zhandle(nullptr)
{
}

ZkClient::~ZkClient()
{
    if (_zhandle != nullptr)
        zookeeper_close(_zhandle);
}

void ZkClient::start()
{
    std::string ip = MprpcApplication::GetInstance().getConfig().Load("zookeeperip");
    std::string port = MprpcApplication::GetInstance().getConfig().Load("zookeeperport");
    std::string connstr = ip + ":" + port;

    // zookeeper_mt 多线程版本
    // zookeeper的API提供三个线程
    // API调用线程 / 网络IO线程 / watchar回调线程

    // 这部分只是本地内容准备, 需要后面等待连接服务端
    _zhandle = zookeeper_init(connstr.c_str(), global_watcher, 30000, nullptr, nullptr, 0);
    if (!_zhandle)
    {
        std::cout << "zookeeper init fail!" << std::endl;
        exit(EXIT_FAILURE);
    }

    sem_t sem;
    sem_init(&sem, 0, 0);
    zoo_set_context(_zhandle, &sem);

    sem_wait(&sem);
    std::cout << "zookeeper init success!" << std::endl;
}

// 要新开辟的路径, 存入对应路径节点的数据(ip/port), 数据长度, 是永久还是临时
void ZkClient::create(const char *path, const char *data, int datalen, int state)
{
    char path_buf[128];
    int bufferlen = sizeof path_buf;
    // 先判断path表示的节点是否存在
    int flag = zoo_exists(_zhandle, path, 0, nullptr);

    if (ZNONODE == flag)
    {
        flag = zoo_create(_zhandle, path, data, datalen,
                          &ZOO_OPEN_ACL_UNSAFE, state, path_buf, bufferlen);
        if (flag == ZOK)
        {
            std::cout << "znode create success, path: " << path << std::endl;
        }
        else
        {
            std::cout << "znode create error, path " << path << std::endl;
            exit(EXIT_FAILURE);
        }
    }
}

// 访问一个服务
std::string ZkClient::getData(const char *path)
{
    char buf[64];
    int buflen = sizeof buf;
    int flag = zoo_get(_zhandle, path, 0, buf, &buflen, nullptr);
    if (flag == ZOK)
        return buf;
    else
    {
        std::cout << "get znode error!" << std::endl;
        return "";
    }
}
```

这里需要额外解释一下有关watcher和信号量的问题 : 

**为什么要使用信号量** : 目的是为了实现线程间通信, 因为我们这里使用的是zk的多线程版本, 你可以理解为有三个线程会存在, 一个是调用api的当前线程, 一个是进行网络IO的线程, 一个是准备调用watcher回调的线程. 我们当前线程需要获知网络IO线程是否与zk服务器建立了连接, 需要信号量来保持同步.

**信号量使用过程** : 

- API调用线程 使用`zoo_set_context(_zhandle, &sem)`, 将句柄与信号量绑定, 你可以认为其将信号量存入了一块共享内存中.
- API调用线程 使用`sem_wait(&sem)`进行等待.

- 网络IO线程 与zk服务器成功建立连接后, 会通过系列操作触发watcher回调线程.
- watcher回调线程 使用`sem_t *sem = (sem_t *)zoo_get_context(zh);`从共享内存中取出了信号量并激活.
- API调用线程 被唤醒并继续执行.

**watcher的作用** : 就是很单纯的用来监视会话是否成功建立, watcher还有很多可以开发的用法, 这里不再详述.

### Zookeeper在本框架中的应用

在解释了zookeeper相关细节后, 我们将在框架中引用zookeeper的服务.

首先我们要明晰应该在哪里应用zookeeper : 

- 服务提供端, 也就是RpcProvider, 需要将发布的远程服务发布到zk服务器上. (具体到细节就是在zk服务器中添加多个znode节点, 存入自己的ip/port).
- 服务调用端, 也就是RpcChannel, 不再通过配置文件获取目标服务器路径, 而是通过配置文件获取zk服务器路径, 同zk服务器进行服务发现.

```cpp
void RpcProvider::Run()
{
    std::string ip = MprpcApplication::GetInstance().getConfig().Load("rpcserverip");
    uint16_t port = atoi(MprpcApplication::GetInstance().getConfig().Load("rpcserverport").c_str());
    InetAddress address(port, ip);
    TcpServer server(&m_eventLoop, address, "RpcProvider");

    server.setConnectionCallback(std::bind(&RpcProvider::OnConnection, this, std::placeholders::_1));

    server.setMessageCallback(std::bind(&RpcProvider::OnMessage, this,
                                        std::placeholders::_1, std::placeholders::_2, std::placeholders::_3));

    server.setThreadNum(3);

    // 把当前rpc节点要发布的所有服务都注册到zk上, 让客户端通过zk发现服务而不是ip/port
    // 服务节点设置为永久, 方法节点设置为暂时, 只要rpc节点断开连接, 方法节点就会失效
    ZkClient zkCli;
    zkCli.start();
    for (auto &[name, service_info] : m_serviceMap)
    {
        std::string service_path = "/" + name;
        zkCli.create(service_path.c_str(), nullptr, 0);
        for (auto &[method_name, ptr] : service_info.m_methodMap)
        {
            std::string method_path = service_path + "/" + method_name;
            char method_data[129] = {0};
            sprintf(method_data, "%s:%d", ip.c_str(), port);
            zkCli.create(method_path.c_str(), method_data, strlen(method_data), ZOO_EPHEMERAL);
        }
    }

    cout << "RpcProvider start service at ip:" << ip << " port:" << port << endl;

    server.start();
    m_eventLoop.loop();
}
```

聚焦到RpcProvider的Run函数, 在自己启动对于方法远程调用服务的同时, 要将自己发布的所有服务和方法发布到zk中(从`m_serviceMapzh`中获取), 注意我们把服务节点设置为永久节点, 方法都设置为临时节点, 这意味着一旦服务提供端与zk服务器断连, zk服务器便会删除这些方法节点.

```cpp
void MprpcChannel::CallMethod(const google::protobuf::MethodDescriptor *method,
                              google::protobuf::RpcController *controller, const google::protobuf::Message *request,
                              google::protobuf::Message *response, google::protobuf::Closure *done)
{
    const google::protobuf::ServiceDescriptor *sd = method->service();
    std::string service_name(sd->name());
    std::string method_name(method->name());

    // 获取参数的序列化字符串长度
    uint32_t args_size = 0;
    std::string args_str;
    if (request->SerializeToString(&args_str))
    {
        args_size = args_str.size();
    }
    else
    {
        controller->SetFailed("serialize request error!");
        return;
    }

    mprpc::RpcHeader rpcHeader;
    rpcHeader.set_service_name(service_name);
    rpcHeader.set_method_name(method_name);
    rpcHeader.set_args_size(args_size);

    uint32_t header_size = 0;
    std::string rpc_header_str;
    if (rpcHeader.SerializeToString(&rpc_header_str))
    {
        header_size = rpc_header_str.size();
    }
    else
    {
        controller->SetFailed("serialize header error");
        return;
    }

    std::string send_rpc_str;
    send_rpc_str.insert(0, std::string((char *)&header_size, 4));
    send_rpc_str += rpc_header_str;
    send_rpc_str += args_str;

    int clientfd = socket(AF_INET, SOCK_STREAM, 0);
    if (clientfd == -1)
    {
        controller->SetFailed("create socket error!");
        exit(EXIT_FAILURE);
    }

    // 最普通就是直接从配置文件中读取rpcserver的消息
    // std::string ip = MprpcApplication::GetInstance().getConfig().Load("rpcserverip");
    // std::string port = MprpcApplication::GetInstance().getConfig().Load("rpcserverport");

    // 还可以通过服务名和方法名从zookeeper上查询
    ZkClient zkCli;
    zkCli.start();

    std::string path = "/" + service_name + "/" + method_name;
    std::string data = zkCli.getData(path.c_str());
    if (data == "")
    {
        std::string str = "no method found in path: " + path;
        controller->SetFailed(str);
        return;
    }

    int idx = data.find_first_of(":");
    std::string ip = data.substr(0, idx);
    std::string port = data.substr(idx + 1);

    struct sockaddr_in server_addr;
    bzero(&server_addr, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(atoi(port.c_str()));
    server_addr.sin_addr.s_addr = inet_addr(ip.c_str());

    if (-1 == connect(clientfd, (struct sockaddr *)&server_addr, sizeof(server_addr)))
    {
        std::string str = "connection error! errno:" + std::to_string(errno) + " errmsg:" + strerror(errno);
        controller->SetFailed(str);
        close(clientfd);
        exit(EXIT_FAILURE);
    }

    if (-1 == send(clientfd, send_rpc_str.c_str(), send_rpc_str.size(), 0))
    {
        controller->SetFailed("send error");
        close(clientfd);
        return;
    }

    // 接收rpc请求的响应值
    char buf[1024] = {0};
    int n = recv(clientfd, buf, 1024, 0);
    if (-1 == n)
    {
        controller->SetFailed("receive error");
        close(clientfd);
        return;
    }

    if (!response->ParseFromArray(buf, n))
    {
        controller->SetFailed("parse error!");
        close(clientfd);
        return;
    }
    close(clientfd);
}
```

我们知道RpcChannel中的CallMethod方法负责汇聚不同的远程方法请求并发送出去, 那么寻求目标服务提供端的方式就是在zk上查询对应服务名和方法名, 如果服务提供端确实将服务发布在了zk上, 那么调用端就确实可以查询到并且获取到节点中的data, 从data中提取出服务端的ip/port就可以进行正常的发送了.

至此Zookeeper在本框架项目中的应用已分析完毕.



by 天目中云