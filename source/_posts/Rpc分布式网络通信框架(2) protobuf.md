---
title: Rpc分布式网络通信框架(2) protobuf
date: 2025-5-11 17:00:00
tag: [RPC]
---

> protobuf部分

protobuf的功效和json相似, 都是便利数据的序列化和反序列化用于网络传输, 在rpc分布式网络通信中可以使用protobuf, 让我们先了解其优势 : 

- 传输数据由二进制存储, 节省空间且效率更高.
- 有专门对于服务/方法的封装, 可以更方便地传输一个方法的信息.

当然其劣势在于需要编写.proto文件, 安装和使用都麻烦些, 不过这并不妨碍我们学习.

### .proto文件

首先我们要知道, 写一个.proto文件实际就是类似c++中写几个类, 每个类都是对你要传输数据的封装, 下面是一个对于登录所需数据的.proto文件 : 

```protobuf
syntax = "proto3";  // 声明proto版本

package fixbug;  	// 类似namespace

option cc_generic_services = true;  // 这个是在你想要使用service类型时添加

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

我们可以看出, 普通数据封装都是message类型, 里面可以存, int, bool等类型, 注意这里bytes实际就是string类型, 当然直接写string也可以, 但是使用bytes效率更佳.

最后sevice类型用来描述一个服务, 其中可以有多个方法(函数), 其中每个方法的写法是 : 

```protobuf
rpc 函数名(参数类型) returns(返回类型);
```

为什么要封装方法? 假设我们要调用一个远程服务, 作为客户端, 我们就要告诉服务端我们要调用什么服务的什么方法. 假设我们要发布服务, 那么为了让我们的服务可以被更多的客户端找到, 我们所封装的服务格式就应当符合一些广为人知的标准, 而这个标准一般就是proto所封装的服务.

### 生成头文件和源文件

在写完.proto文件后, 我们就可以执行终端命令来自动生成头文件和源文件了.

```cpp
protoc xxx.proto --cpp_out=./
```

调用该命令便可以在当前目录下生成 xxx.pb.h 和 xxx.pb.cpp 文件了, 这两个文件才是我们真正使用的文件.

### 使用proto进行序列化和反序列化

```cpp
// 在客户端, 我们可以这样构建请求类型
#include "user.pb.h"

fixbug::LoginRequest request;
request.set_name("zhang san");
request.set_pwd("123456");

// 在服务端, 可以这样取出请求类型
std::string name = request->name();
std::string pwd = request->pwd();
```

