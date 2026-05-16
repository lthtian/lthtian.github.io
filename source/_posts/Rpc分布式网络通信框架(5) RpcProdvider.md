---
title: Rpc分布式网络通信框架(5) RpcProdvider
date: 2025-6-23 21:00:00
tags: [RPC]
---

> RpcProdvider

`RpcProdvider`是提供给服务发布端的核心类. 

既然想把方法发布为远程方法被外部调用, 那么发布端需要做的无非就是作为一个服务器持续接收外部的方法调用请求, 根据请求在本地调用对应的方法, 最后再将响应发送回去, 可以当作一个简易的webServer, 但是需要配合我们先前protobuf的Service类, 使其对于方法调用更加便捷与通用.

```cpp
// rpcprodvider.h
#pragma once
#include "google/protobuf/service.h"
#include <memory>

#include <muduo/net/TcpServer.h>
#include <muduo/net/EventLoop.h>
#include <muduo/net/InetAddress.h>
using namespace muduo;
using namespace muduo::net;

#include <functional>
#include <google/protobuf/descriptor.h>
#include <unordered_map>

class RpcProvider
{
public:
    // 所有rpc服务都会继承于goole::protobuf::Service
    // 选其为类型可以接收任意服务
    void NotifyService(google::protobuf::Service *service);

    // 启动Rpc节点, 开始启动远程网络调用服务
    void Run();

private:
    void OnConnection(const TcpConnectionPtr &);
    void OnMessage(const TcpConnectionPtr &, Buffer *, Timestamp);
    void SendRpcResponse(const TcpConnectionPtr &, google::protobuf::Message *);

    std::unique_ptr<TcpServer> m_tcpserverPtr;
    EventLoop m_eventLoop;

    // service服务类型信息
    struct ServiceInfo
    {
        google::protobuf::Service *m_service;
        std::unordered_map<std::string, const google::protobuf::MethodDescriptor *> m_methodMap;
    };
    std::unordered_map<std::string, ServiceInfo> m_serviceMap;
};
```

- NotifyService : 

  这个函数用于在远程调用服务启动前记录需要发布出去的服务及对应方法.

- Run : 

  这个函数用于启动远程调用服务, 实际上就是监听指定的读端口, 接收外部的请求, 我们这里直接使用Muduo网络库执行网络层的行动.

- OnConnection / OnMessage : 分别对应Muduo网络库在连接建立和读事件触发时的回调.

- SendRpcResponse : 在函数调用完成后会调用此回调函数将响应发送回去.

再看成员变量 : 

- m_tcpserverPtr / m_eventLoop : 使用Muduo网络库的必要变量.

- m_serviceMap : 

  每个服务名对应一个服务结构体`ServiceInfo`, 每一个服务结构体中又包含了以**方法名与方法结构体指针**为键值对的结构体. 通过`NotifyService`向其中存储, 在收到请求后, 根据解析出来的服务名和方法进行查询和取出指针的操作.

接下来展示每个函数的细节 : 

```cpp
void RpcProvider::NotifyService(google::protobuf::Service *service)
{
    ServiceInfo service_info;
    // 获取服务对象的描述信息
    const google::protobuf::ServiceDescriptor *serviceDesc = service->GetDescriptor();
    std::string service_name(serviceDesc->name());
    int methodCnt = serviceDesc->method_count();
    cout << "service name : " << service_name << endl;

    for (int i = 0; i < methodCnt; i++)
    {
        // 获取指定下标的服务方法的描述
        const google::protobuf::MethodDescriptor *methodDesc = serviceDesc->method(i);
        std::string method_name(methodDesc->name());
        service_info.m_methodMap.insert({method_name, methodDesc});
        cout << "method name : " << method_name << endl;
    }
    service_info.m_service = service;
    m_serviceMap.insert({service_name, service_info});
}
```

这里通过protobuf中内置的方法, 可以直接从Service对象中通过GetDescriptor()获取服务指针, 进而获取服务名, 方法数目及其下的每个方法指针. 本函数要做的就是将这些信息存储到我们上面提到的m_serviceMap中, 步骤比较麻烦, 但是不难懂.

```cpp
// 启动Rpc节点, 开始启动远程网络调用服务
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

    cout << "RpcProvider start service at ip:" << ip << " port:" << port << endl;

    server.start();
    m_eventLoop.loop();
}
```

这里就是一个比较常规的开启网络服务的步骤了, 先通过`MprpcApplication`取出配置文件中的ip与port, 然后构造Muduo网络库的TcpServer对象, 设置连接建立回调和读事件回调, 最后开启服务器并启动循环, 这里需要对Muduo网络库有使用经验才容易理解.

```cpp
// 已建立连接用户的读事件回调, 如果远程有一个rpc服务的调用请求, 会响应该方法
// 执行请求的反序列化 和 响应的序列化
void RpcProvider::OnMessage(const TcpConnectionPtr &conn, Buffer *buf, Timestamp timestamp)
{
    std::string recv_buf = buf->retrieveAllAsString();

    // 约定请求rpc服务需要 service_name / method_name / args_size / args_str
    // args_size是为了解决粘包问题
    uint32_t header_size = 0;
    recv_buf.copy((char *)&header_size, 4, 0);
    string rpc_header_str = recv_buf.substr(4, header_size);
    mprpc::RpcHeader rpcHeader;
    string service_name, method_name;
    uint32_t args_size;
    if (rpcHeader.ParseFromString(rpc_header_str))
    {
        service_name = rpcHeader.service_name();
        method_name = rpcHeader.method_name();
        args_size = rpcHeader.args_size();
    }
    else
    {
        cout << "rpc_header_str:" << rpc_header_str << "parse error!" << endl;
        return;
    }

    string args_str = recv_buf.substr(4 + header_size, args_size);

    cout << "=============================================" << endl;
    cout << "header_size" << header_size << endl;
    cout << "service_name" << service_name << endl;
    cout << "method_name" << method_name << endl;
    cout << "args_str" << args_str << endl;
    cout << "=============================================" << endl;

    // 获取service对象和method对象
    auto it = m_serviceMap.find(service_name);
    if (it == m_serviceMap.end())
    {
        cout << service_name << "is not exist!" << endl;
        return;
    }

    auto mit = it->second.m_methodMap.find(method_name);
    if (mit == it->second.m_methodMap.end())
    {
        std::cout << service_name << ":" << method_name << "is not exist" << endl;
        return;
    }

    google::protobuf::Service *service = it->second.m_service;
    const google::protobuf::MethodDescriptor *method = mit->second;

    // 生成rpc方法调用的请求request和response
    // 生成一个message对象, 设定其内部对应目标method的参数
    google::protobuf::Message *request = service->GetRequestPrototype(method).New();
    if (!request->ParseFromString(args_str)) // 反序列化存储到request中
    {
        cout << "request prase error" << endl;
        return;
    }
    google::protobuf::Message *response = service->GetResponsePrototype(method).New();

    // 给下面的method方法调用绑定一个Closure的回调函数
    google::protobuf::Closure *done = google::protobuf::NewCallback<RpcProvider, const TcpConnectionPtr &, google::protobuf::Message *>(this, &RpcProvider::SendRpcResponse, conn, response);

    // 在框架上根据远端rpc的请求, 调用当前rpc节点上发布的方法
    service->CallMethod(method, nullptr, request, response, done);
}
```

这个是读事件的回调, 我们来整理一下当读事件回调触发时我们的行为 : 

- **正确读入字段, 取出需求的信息.**

  为了达到此目的, 我们必须和客户端达成对于请求格式的一致,  具体规定为分为报头部分和参数部分.

  - 报头部分包含 *service_name / method_name / args_size* (服务名, 方法名, 参数部分大小), 这些被包含在*RpcHeader* 这个对象中, 该对象也由protobuf生成, 具体细节不表.
  - 参数部分就是客户端的请求对象序列化成的二进制字符串.

  我们先读出报头部分的三个参数, 在利用args_size取出参数部分, 这样可以防止tcp的粘包问题.

- 在我们事先准备好存储服务信息的map中**找寻请求的服务**, 再**将对应服务和对应方法的操作指针取出**.

-  **利用指针构造请求对象和响应对象**.

  注意需要将参数部分的字符串放到请求对象中反序列化, 就是这段代码 : 

  ```cpp
  request->ParseFromString(args_str)
  ```

- **构造Closure(控制器)并存入回调函数**.

  构造出来的done参数主要用来在合适的时机调用先前设置的回调函数. 其作用是确保在响应对象填充完毕后才执行发送. 我们先来看看回调函数我们具体是怎么写的 : 

  ```cpp
  void RpcProvider::SendRpcResponse(const TcpConnectionPtr &conn, google::protobuf::Message *response)
  {
      std::string response_str;
      if (response->SerializeToString(&response_str))
      {
          conn->send(response_str);
      }
      else
      {
          cout << "serialize response_str error!" << endl;
      }
      conn->shutdown(); // rpc服务的提供方主动断开连接
  }
  ```

  其实很简单, 就是把响应对象序列化成二进制字符串发送出去罢了.

- **调用目标服务专门的`CallMethod`方法**.

  这里其实就是在调用我们发布方法的远程版, 其依赖于protobuf对每个服务方法的封装, 通过多态, CallMethod又会调用到对应服务的版本, 然后再根据我们传入的method通过switch语句选择调用正确的远程方法. 假如我们请求的是UserService的Login方法, 那么最后就会调用到我们先前用protobuf自动生成的源文件中的这个函数.
  
  ```cpp
  void UserServiceRpc::CallMethod(
      const ::google::protobuf::MethodDescriptor* PROTOBUF_NONNULL method,
      ::google::protobuf::RpcController* PROTOBUF_NULLABLE controller,
      const ::google::protobuf::Message* PROTOBUF_NONNULL request,
      ::google::protobuf::Message* PROTOBUF_NONNULL response, ::google::protobuf::Closure* PROTOBUF_NULLABLE done) {
    ABSL_DCHECK_EQ(method->service(), file_level_service_descriptors_user_2eproto[0]);
    switch (method->index()) {
      case 0:
        this->Login(controller, ::google::protobuf::DownCastMessage<::fixbug::LoginRequest>(request),
                     ::google::protobuf::DownCastMessage<::fixbug::LoginResponse>(response), done);
        break;
  
      default:
        ABSL_LOG(FATAL) << "Bad method index; this should never happen.";
        break;
    }
  }
  ```

至此对于整个`RpcProvider`的构建思路基本完善, 主要就是配合protobuf构建的服务封装体系, 先把要发布的服务方法记录下来, 然后设置epoll服务器接收请求, 分析请求并查找是否有对应的远程方法, 有就利用多态直接通过CallMethod函数调用对应远程方法.



by 天目中云