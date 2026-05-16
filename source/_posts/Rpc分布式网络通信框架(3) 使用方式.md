---
title: Rpc分布式网络通信框架(3) 使用方式
date: 2025-5-15 17:00:00
tag: [RPC]
---

> 在构建通信框架前,  一定要先了解我们的框架该怎么使用, 大体有哪几个部件, 在本章将会先写出一个简易的客户端和服务端, 让我们了解该设计出什么样的网络通信框架.

### 统一通信标准

首先双方如果需要通信, 那么**统一通信标准**必不可少, 这也是为什么讲解proto的原因, 所以我们的第一步是编写proto文件并且生成.h和.cpp文件, 这里还是已先前的登录服务为例 : 

```protobuf
syntax = "proto3";

package fixbug;

option cc_generic_services = true;

message ResultCode
{
    int32 errcode = 1;
    bytes errmsg = 2;
}

message LoginRequest 
{
    bytes name = 1;
    bytes pwd = 2;
}

message LoginResponse
{
    ResultCode result = 1;
    bool success = 2;
}

service UserServiceRpc
{
    rpc Login(LoginRequest) returns(LoginResponse);
}
```

当我们通过终端命令获得.h和.cpp文件后, 这个文件会共享给客户端和服务端, 你也许会觉得这增加了远程调用的难度, 因为这意味着客户端还要获取这些文件, 但是这是必须前提.

### 服务端发布服务

当我们想给一个方法或一类方法提供远程调用服务时, 我们要把其包装进一个Service(服务类)中, 这个类提供远程调用版本的方法, 并且这个类还要继承自我们先前用proto生成的服务类封装, 我们具体看代码理解 : 

```cpp
// UserServic原本是一个本地服务
// 只要继承UserServiceRpc再重写一个虚函数就可以实现rpc服务
class UserService : public fixbug::UserServiceRpc
{
public:
    bool Login(std::string name, std::string pwd)
    {
        std::cout << "doing local servie : Login" << std::endl;
        std::cout << "name:" << name << " pwd:" << pwd << std::endl;
        return true;
    }

    void Login(::google::protobuf::RpcController *controller,
               const ::fixbug::LoginRequest *request,
               ::fixbug::LoginResponse *response,
               ::google::protobuf::Closure *done)
    {
        std::string name = request->name();
        std::string pwd = request->pwd();

        bool login_result = Login(name, pwd);

        // 把结果response
        ResultCode *code = response->mutable_result();
        code->set_errcode(0);
        code->set_errmsg("");
        response->set_success(login_result);

        // 执行回调操作 直接执行响应对象数据的序列化和网络发送
        done->Run();
    }
};
```

- fixbug : 这个就是我们先前在proto中设置的命名空间, 在这个命名空间中就会有我们设置的`UserServiceRpc服务类`.

- 继承后我们就要写一个Login函数重写版本, 相当于一个远程调用版本, 其参数是固定的 : 

  RpcController + 先前设定的请求参数类型 + 响应参数类型 + Closure.

  中间两个我们很熟悉, 第一个我们先不用关心, 最后一个你可以理解为执行类型, 帮我们执行最后发送操作.

在写完我们要发布的服务类后我们来看具体如何发布 : 

```cpp
#include <iostream>
#include <string>
#include "../user.pb.h"
#include "mprpcapplication.h"
#include "rpcprovider.h"
#include "logger.h"
using namespace fixbug;
using namespace mprpc;

// UserServic原本是一个本地服务
// 只要继承UserServiceRpc再重写一个虚函数就可以实现rpc服务
class UserService : public fixbug::UserServiceRpc
{
public:
    bool Login(std::string name, std::string pwd)
    {
        std::cout << "doing local servie : Login" << std::endl;
        std::cout << "name:" << name << " pwd:" << pwd << std::endl;
        return true;
    }

    void Login(::google::protobuf::RpcController *controller,
               const ::fixbug::LoginRequest *request,
               ::fixbug::LoginResponse *response,
               ::google::protobuf::Closure *done)
    {
        std::string name = request->name();
        std::string pwd = request->pwd();

        bool login_result = Login(name, pwd);

        // 把结果response
        ResultCode *code = response->mutable_result();
        code->set_errcode(0);
        code->set_errmsg("");
        response->set_success(login_result);

        // 执行回调操作 直接执行响应对象数据的序列化和网络发送
        done->Run();
    }
};

int main(int argc, char *argv[])
{
    // 调用框架初始化操作
    MprpcApplication::Init(argc, argv);

    log_info("first log message.");

    // 把UserService发布到rpc节点上
    RpcProvider provider;
    provider.NotifyService(new UserService());
    // 启动一个rpc服务发布节点
    provider.Run();
}
```

这里引出两个关键类 :  `MprpcApplication` 和 `RpcProvider` .

- MprpcApplication : 负责框架的初始化, 其更多的功能在于加载配置文件, 后面会详细介绍.
- RpcProvider : 核心类, 其作用在于将服务发布到rpc节点上, 发布成功后就可以持续监听对于该服务的请求并做出响应.
  - NotifyService : 将服务中的信息的记录下来, 在运行后以供查询.
  - Run : 调用网络库的网络服务, 开始接收外部调用请求.

### 客户端调用远程服务

客户端的调用就相对方便了, 设置好请求对象就行了 : 

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

- `fixbug::UserServiceRpc_Stub stub(new MprpcChannel());`

  stub其目的在于帮助我们调用到我们需求函数的远程版本, 其构造必须传入一个MprpcChannel类型的参数, 这个也是框架的核心类, 在之后会详细讲解.

- 之后就是正常的设置请求对象, 将响应对象一并放入远程调用函数, 如果框架帮我们调用成功, 这里便可以从响应对象中取出我们想要的响应.