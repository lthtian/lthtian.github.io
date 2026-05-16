---
title: Rpc分布式网络通信框架(6) RpcChannel
date: 2025-6-25 21:00:00
tags: [RPC]
---

> RpcChannel

RpcChannel是客户调用端的核心类, 其控制了客户端该如何向服务端发出远程方法调用.

让我们先回顾一下客户端是如何调用我们的框架的 : 

```cpp
#include <iostream>
#include "mprpcapplication.h"
#include "user.pb.h"

using std::cout;
using std::endl;

int main(int argc, char **argv)
{
    // 想要使用rpc服务, 就要调用框架的初始化服务
    MprpcApplication::Init(argc, argv);

    // 演示调用远程发布的rpc方法的Login
    fixbug::UserServiceRpc_Stub stub(new MprpcChannel());

    fixbug::LoginRequest request;
    request.set_name("zhang san");
    request.set_pwd("123456");
    fixbug::LoginResponse response;

    MprpcController controller;

    stub.Login(&controller, &request, &response, nullptr);

    // 如果rpc服务确实成功再继续接下来的内容
    if (controller.Failed())
    {
        std::cout << controller.ErrorText() << endl;
        return 0;
    }
    // rpc方法调用完成, 读响应
    if (response.result().errcode() == 0)
    {
        cout << "rpc login response:" << response.success() << endl;
    }
    else
    {
        cout << "rpc login response error : " << response.result().errmsg() << endl;
    }

    return 0;
}
```

这里最核心的就是要构建一个桩对象stub, 并且必须要用框架提供的RpcChannel类对象进行构造, 你可以把其简单理解为一个帮助我们实现远程调用的类.

`UserServiceRpc_Stub`类中会有我们先前封装的函数, 但是其只是一个包装, 我们可以看其生成的内容 : 

```cpp
void UserServiceRpc_Stub::Login(
    ::google::protobuf::RpcController* PROTOBUF_NULLABLE controller,
    const ::fixbug::LoginRequest* PROTOBUF_NONNULL request, ::fixbug::LoginResponse* PROTOBUF_NONNULL response,
    ::google::protobuf::Closure* PROTOBUF_NULLABLE done) {
  channel_->CallMethod(descriptor()->method(0), controller,
                       request, response, done);
}
```

这里其实都是统一调用channel_中的CallMethod函数, 不同函数只是在某些参数上有所不同, 注意这里的CallMethod方法和上一章RpcProvider的CallMethod不是一个东西, 前者代表调用端, 后者代表服务提供端.

如此处理可以让不同远程方法的调用应用到同一段请求发送的代码, 也就是channel_ 的CallMethod, 这里 channel_ 就是我们先前在构造时传入的RpcChannel类对象, 让我们来了解这个类 : 

```cpp
// mprpcchannel.cpp
#pragma once
#include <google/protobuf/service.h>
#include <google/protobuf/descriptor.h>
#include <google/protobuf/message.h>

class MprpcChannel : public google::protobuf::RpcChannel
{
public:
    void CallMethod(const google::protobuf::MethodDescriptor *method,
                    google::protobuf::RpcController *controller, const google::protobuf::Message *request,
                    google::protobuf::Message *response, google::protobuf::Closure *done);
};
```

整个类只有一个函数且继承于`google::protobuf::RpcChannel`, 我们先要了解CallMethod这个函数的职责, 就是**将要请求的服务, 方法和对应参数封装并序列化, 再通过网络将这个请求发送给提供该服务的服务器(也就是使用了RpcProvider), 最后接收服务器返回的结果存入响应对象**, 下面是具体代码 : 

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
    std::string ip = MprpcApplication::GetInstance().getConfig().Load("rpcserverip");
    std::string port = MprpcApplication::GetInstance().getConfig().Load("rpcserverport");

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

让我们再盘点一下这个函数干了些什么 : 

- 取出服务名, 方法名, 参数长度, 以此构成报头类对象, 再转换成二进制字符串(对于双端信息交互的格式在上一章已经说明, 这里不再详述).
- 组合要发送的字符串, 包含 : 报头长度 + 报头二进制字符串 + 参数二进制字符串.
- 获取提供目标远程调用服务器的ip和端口(这里默认配置文件中有提供, 在引入zookeeper后会有改动).
- 构建网络结构体, 进行正常的Tcp客户端发送.
- 接收对端返回的字符串, 并将其存入响应对象.

至此客户端进行远程方法调用的逻辑链路已经完善, 整体思路就是**将发送服务调用请求的任务通过stub汇聚到RpcChannel类上**.

另外在前面没有对`Controller`这个类型进行讲解, 因为其并非核心, 其作用在于检测rpc服务是否正常进行, 如果不正常就不会继续后面的代码并且发出错误信息, 这里给出其内部实现 : 

```cpp
// mprpccontroller.h
#pragma once
#include <google/protobuf/service.h>
#include <string>

class MprpcController : public google::protobuf::RpcController
{
public:
    MprpcController();
    void Reset();
    bool Failed() const;
    std::string ErrorText() const;
    void SetFailed(const std::string &reason);

    void StartCancel();
    bool IsCanceled() const;
    void NotifyOnCancel(google::protobuf::Closure *);

private:
    bool _failed;
    std::string _errText;
};

// // mprpccontroller.cpp
#include "mprpccontroller.h"

MprpcController::MprpcController()
{
    _failed = false;
    _errText = "";
}

void MprpcController::Reset()
{
    _failed = false;
    _errText = "";
}

bool MprpcController::Failed() const
{
    return _failed;
}

std::string MprpcController::ErrorText() const
{
    return _errText;
}

void MprpcController::SetFailed(const std::string &reason)
{
    _failed = true;
    _errText = reason;
}

void MprpcController::StartCancel() {}
bool MprpcController::IsCanceled() const { return false; }
void MprpcController::NotifyOnCancel(google::protobuf::Closure *) {}
```



by 天目中云