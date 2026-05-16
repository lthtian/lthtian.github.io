---
title: Rpc分布式网络通信框架(4) RpcApplication
date: 2025-5-20 17:00:00
tags: [RPC]
---

> RpcApplication

本章讲解第一个核心类`RpcApplication`, 该类的主要任务是解析传入的配置文件, 并可以取出解析到的内容, 简单来说就是执行初始化任务.

- 为什么要传入并解析配置文件?

  网络通信是点到点的, 你必须要知道对端的ip和port才能真正实现通信. 在本框架中, 配置文件主要存储的就是我们的目标服务器的ip与port, 当然如果我们使用zookeeper, 也会存储对应zk的ip与port, 关于zk我们之后再讲.

那么在认识了what和why后, 对于配置文件的解析其实就是很普通的字符串处理了, 让我们通过代码来了解 :

```cpp
// mprpcapplication.h
#pragma once
#include "mprpcconfig.h"
#include "mprpcchannel.h"
#include "mprpccontroller.h"

// mprpc框架的初始类, 用来加载配置文件
class MprpcApplication
{
public:
    static void Init(int argc, char *argv[]);
    static MprpcApplication &GetInstance();
    static MprpcConfig &getConfig();

private:
    MprpcApplication() {}
    MprpcApplication(const MprpcApplication &) = delete;
    MprpcApplication(MprpcApplication &&) = delete;

    static MprpcConfig _config;
};
```

- init : 不管是客户端还是服务端, 在最初构造完MprpcApplication对象后都要调用此函数, 用来加载配置文件.

  - 其参数就是上级main函数传入的命令参数, 这里默认选项为`-i`, 需要传入配置文件信息,例如 :

    ```bash
    ./consumer -i ./test.conf
    ```

    test.conf配置约定如下 : 

    ```conf
    rpcserverip=82.156.254.74
    rpcserverport=8888
    zookeeperip=82.156.254.74
    zookeeperport=2181
    ```

- GetInstance : 本类采取单例模式, 因为获取配置始终只需要一个对象即可, 唯一对象都通过该函数获取.

- getConfig : 获取解析完成的配置对象.

- _config : 配置对象, 之后会分析.

```cpp
#include "mprpcapplication.h"
#include <iostream>
using std::cout;
using std::endl;
#include <unistd.h>

MprpcConfig MprpcApplication::_config;

MprpcApplication &MprpcApplication::GetInstance()
{
    static MprpcApplication app;
    return app;
}

void MprpcApplication::Init(int argc, char *argv[])
{
    if (argc < 2)
    {
        cout << "format: command -i <configfile>" << endl;
        exit(EXIT_FAILURE);
    }

    int c = 0;
    std::string config_file;
    while ((c = getopt(argc, argv, "i:")) != -1)
    {
        switch (c)
        {
        case 'i':
            config_file = optarg;
            break;
        case '?':
            exit(EXIT_FAILURE);
        case ':':
            exit(EXIT_FAILURE);
        default:
            break;
        }
    }

    // 开始加载配置文件 rpcserver_ip= rpcserver_port= zookeeper_ip= zookeeper_port=
    _config.LoadConfigFile(config_file.c_str());
    std::cout << "rpcserverip:" << _config.Load("rpcserverip") << std::endl;
    std::cout << "rpcserverport:" << _config.Load("rpcserverport") << std::endl;
    std::cout << "zookeeperip:" << _config.Load("zookeeperip") << std::endl;
    std::cout << "zookeeperport:" << _config.Load("zookeeperport") << std::endl;
}

MprpcConfig &MprpcApplication::getConfig()
{
    return _config;
}
```

`MprpcApplication`只负责对传入的参数进行合法性检验并执行生成配置对象, 真正的细节在MprpcConfig中.

````cpp
// mprpcconfig.h
#pragma once
#include <iostream>
#include <unordered_map>

// rpcserver_ip= rpcserver_port= zookeeper_ip= zookeeper_port=

class MprpcConfig
{
public:
    // 解析加载配置文件
    void LoadConfigFile(const char *config_file);
    // 查询配置项信息
    std::string Load(const std::string &key);

private:
    std::unordered_map<std::string, std::string> _configMap;
};
````

```cpp
// mprpcconfig.cpp
#include "mprpcconfig.h"
#include <string>

// 解析加载配置文件
void MprpcConfig::LoadConfigFile(const char *config_file)
{
    FILE *pf = fopen(config_file, "r");
    if (nullptr == pf)
    {
        exit(EXIT_FAILURE);
    }
    while (!feof(pf))
    {
        char buf[512] = {0};
        fgets(buf, 512, pf);
        std::string sbuf(buf);
        for (int i = 0; i < sbuf.size(); i++)
        {
            if (sbuf[i] == ' ' || sbuf[i] == '\r' || sbuf[i] == '\n')
                sbuf.erase(i, 1), i--;
        }
        if (sbuf[0] == '#')
            continue;

        int idx = sbuf.find('=');
        std::string key = sbuf.substr(0, idx);
        std::string value = sbuf.substr(idx + 1);
        _configMap[key] = value;
    }
}
// 查询配置项信息
std::string MprpcConfig::Load(const std::string &key)
{
    if (_configMap.count(key) == 0)
        return "";
    return _configMap[key];
}
```

- LoadConfigFile : 

  在该函数中, 通过传入的配置文件路径打开文件并进行字符串处理, 将每个键值对存入`_configMap`.

- Load : 

  该函数用于查询, 传入代表键的string, 就会返回解析出来的值string.

经过这样子解析配置文件, 我们就可以通过类似下面的操作取出配置文件中的参数 : 

```cpp
std::string ip = MprpcApplication::GetInstance().getConfig().Load("rpcserverip");
std::string port = MprpcApplication::GetInstance().getConfig().Load("rpcserverport");
```



by 天目中云