---
title: Redis深入学习(4) redis_plus_plus库
date: 2025-11-8 17:00:00
tags: [Redis]
---

> 本章使用了redis_plus_plus库, 确实使用要比hiredis要方便的多, 实际使用还是直接用这个最好.
>
> 另外还加入了 Pipeline / 事务 / 发布订阅 的应用, 补全一些前面没有深入的概念.

### Redis Pub/Sub (消息订阅)

这应该算是简化版的消息队列, 其可以通过订阅评到来实时获取频道上实时发来的消息, 和卡夫卡之类不同, Redis做的更简化, 更轻便, 在实时接收消息上的效率是极高的. 但相应的高载荷/持久化/数据堆积之类的功能就没有了, 适合一些简单的需求.

测试代码 : 

```cpp
void RedisExamples::pubsubOperations() {
    std::cout << "\n=== 发布订阅操作 ===" << std::endl;
    
    try {
        // 创建连接配置
        sw::redis::ConnectionOptions conn_opts;
        conn_opts.host = "127.0.0.1";
        conn_opts.port = 6382;
        conn_opts.socket_timeout = std::chrono::seconds(1);
        
        sw::redis::ConnectionPoolOptions pool_opts;
        pool_opts.size = 1;
        
        // 使用shared_ptr管理Redis实例
        auto redis_ptr = std::make_shared<sw::redis::Redis>(conn_opts, pool_opts);
        
        // 在单独的线程中运行订阅者
        std::thread subscriber_thread([redis_ptr]() {  // 值捕获，安全！
            try {
                auto sub = redis_ptr->subscriber();
                sub.on_message([](std::string channel, std::string msg) {
                    std::cout << "[订阅者] 收到消息 - 频道: " << channel 
                              << ", 消息: " << msg << std::endl;
                });
                sub.subscribe("test_channel");
                // 运行一段时间后自动退出, 如果是生产环境就不必退出了
                auto end_time = std::chrono::steady_clock::now() + std::chrono::seconds(30);
                while (std::chrono::steady_clock::now() < end_time) {
                    try {
                        sub.consume();
                    } catch (const sw::redis::TimeoutError& e) {
                        continue;
                    }
                }
            } catch (const Error& e) {
                std::cerr << "订阅错误: " << e.what() << std::endl;
            }
        });
        
        // 给订阅者一些时间准备
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        // 发布消息
        redis_ptr->publish("test_channel", "Hello from publisher!");
        redis_ptr->publish("test_channel", "Second message");
        // 现在可以安全detach
        subscriber_thread.detach();
        std::cout << "主线程继续执行，订阅线程在后台运行30秒后自动退出" << std::endl;
    } catch (const Error& e) {
        std::cerr << "发布订阅错误: " << e.what() << std::endl;
    }
}
```

- `on_message` : 当订阅的频道有消息传来, 会将频道与消息作为参数传入该回调, 然后进行自定义反馈.
- `subscribe` : 订阅频道名, 类似于关注一个key, 可以同时订阅多个.
- `consume` : 阻塞等待订阅频道的消息.
- `publish` : 向指定频道发送消息.
- 这里我们可以看到一般会在一个单独的线程中实现频道的订阅和消息接收, 并且和主线程detach, 当消息发来时便可以通过回调函数进行持续的反馈.
- 在聊天室项目就用到过这个技术, 主要解决的是不同服务器上消息的广播问题, 就可以让客户端订阅同一个Redis服务, 当不同服务器的客户端发送消息, 就会向指定的频道发送消息, 让其他服务器上的客户端收到消息.

### 内嵌Lua脚本(Redis 事务)

Redis确实有自己的事务, 其理由和MYSQL的事务也差不多, 就是为了实现多条命令的原子性, 但是由于Redis已经可以支持内嵌Lua脚本, 这种机制**天然原子性, 并且还可以自定义回滚机制**, 就导致其几乎成了Redis事务的上位替代, 之前在分布式锁解锁的时候也是用的Lua脚本保证原子性.

下面的这个测试函数中, 其中的Lua脚本就具备原子性与失败回滚.

```cpp
void RedisExamples::LuaTransaction() {
    std::cout << "\n=== Lua 事务回滚测试 ===" << std::endl;
    
    try {
        redis.set("acc:X", "100");
        redis.set("acc:Y", "50");
        
        std::cout << "初始 - X: " << *redis.get("acc:X") 
                  << ", Y: " << *redis.get("acc:Y") << std::endl;
        
        // 事务脚本：要么全部成功，要么全部回滚
        std::string tx_script = R"(
            local from = KEYS[1]
            local to = KEYS[2] 
            local amount = tonumber(ARGV[1])
            
            -- 先读取，不修改
            local from_balance = tonumber(redis.call('GET', from))
            local to_balance = tonumber(redis.call('GET', to))
            
            -- 验证
            if from_balance < amount then
                return "错误：余额不足"
            end
            
            -- 验证通过，执行转账
            redis.call('DECRBY', from, amount)
            redis.call('INCRBY', to, amount)
            
            -- 最终验证（模拟业务规则）
            if amount > 80 then
                -- 违反规则，回滚操作
                redis.call('INCRBY', from, amount)  -- 退款
                redis.call('DECRBY', to, amount)    -- 扣回
                return "错误：金额超过限制，已回滚"
            end
            
            return "成功"
        )";
        
        // 测试
        auto result = redis.eval<std::string>(tx_script, {"acc:X", "acc:Y"}, {"90"});
        std::cout << "转账结果: " << result << std::endl;
        std::cout << "最终 - X: " << *redis.get("acc:X") 
                  << ", Y: " << *redis.get("acc:Y") << std::endl;
        
        redis.del({"acc:X", "acc:Y"});
        
    } catch (const sw::redis::Error& e) {
        std::cerr << "错误: " << e.what() << std::endl;
    }
}
```

### Redis PipiLine

也是一个相对简单的机制, 目的是**降低网络传输的次数与消耗**, 方法是**将一批操作打包在一块发送, 并一次性接收所有返回**.

实际到操作中其实就是在打包前调用`pipeline`, 打包完调用`exec`.

```cpp
void RedisExamples::pipelineBasic()
{
    std::cout << "\n=== Pipeline 基本使用 ===" << std::endl;

    try
    {
        auto pipe = redis.pipeline();

        // 添加命令到 pipeline
        pipe.set("pipeline_key", "pipeline_value");
        pipe.get("pipeline_key");
        pipe.incr("pipeline_counter");
        pipe.hset("pipeline_hash", "field", "value");

        // 执行所有命令
        auto replies = pipe.exec();

        // 获取结果
        std::cout << "SET 结果: " << replies.get<bool>(0) << std::endl;

        auto value = replies.get<sw::redis::OptionalString>(1);
        if (value)
        {
            std::cout << "GET 结果: " << *value << std::endl;
        }

        std::cout << "INCR 结果: " << replies.get<long long>(2) << std::endl;
        std::cout << "HSET 结果: " << replies.get<bool>(3) << std::endl;
    }
    catch (const Error &e)
    {
        std::cerr << "Pipeline 错误: " << e.what() << std::endl;
    }
}
```

### Redis功能全面测试

```c++
// redis_examples.h
#ifndef REDIS_EXAMPLES_H
#define REDIS_EXAMPLES_H

#include <sw/redis++/redis++.h>
#include <iostream>
#include <vector>
#include <unordered_map>

using namespace sw::redis;

class RedisExamples {
public:
    RedisExamples(const std::string& connection_string = "tcp://127.0.0.1:6382");
    
    // 基本连接测试
    bool testConnection();
    // 字符串操作示例
    void stringOperations();
    // 列表操作示例
    void listOperations();
    // 哈希操作示例
    void hashOperations();
    // 集合操作示例
    void setOperations();
    // // 有序集合操作示例
    // void sortedSetOperations();
    // 事务操作示例
    void transactionOperations();
    void LuaTransaction();
    // 发布订阅示例
    void pubsubOperations();
    // PipeLine示例
    void pipelineBasic();
private:
    Redis redis;
};

#endif
```

```cpp
// redis_examples.cpp
#include "redis_examples.h"
#include <chrono>
#include <thread>
#include <atomic>

RedisExamples::RedisExamples(const std::string &connection_string)
    : redis(connection_string)
{
}

bool RedisExamples::testConnection()
{
    try
    {
        // 测试 ping 命令
        auto pong = redis.ping();
        std::cout << "连接测试: " << pong << std::endl;

        // 测试设置和获取
        redis.set("test_key", "Hello, Redis!");
        auto value = redis.get("test_key");
        if (value)
        {
            std::cout << "获取测试值: " << *value << std::endl;
        }

        redis.del("test_key");
        return true;
    }
    catch (const Error &e)
    {
        std::cerr << "Redis 错误: " << e.what() << std::endl;
        return false;
    }
}

void RedisExamples::stringOperations()
{
    std::cout << "\n=== 字符串操作 ===" << std::endl;

    try
    {
        // 基本设置和获取
        redis.set("name", "Alice");
        auto name = redis.get("name");
        std::cout << "姓名: " << *name << std::endl;

        // 数字操作
        redis.set("counter", "10");
        redis.incr("counter");
        auto counter = redis.get("counter");
        std::cout << "计数器: " << *counter << std::endl;

        // 设置过期时间
        redis.setex("temp_data", std::chrono::seconds(10), "临时数据");

        // 批量操作
        std::unordered_map<std::string, std::string> data = {
            {"key1", "value1"},
            {"key2", "value2"},
            {"key3", "value3"}};
        redis.mset(data.begin(), data.end());

        std::vector<std::string> keys = {"key1", "key2", "key3"};
        std::vector<OptionalString> values;
        redis.mget(keys.begin(), keys.end(), std::back_inserter(values));

        for (size_t i = 0; i < values.size(); ++i)
        {
            if (values[i])
            {
                std::cout << keys[i] << ": " << *values[i] << std::endl;
            }
        }

        // 清理
        redis.del(keys.begin(), keys.end());
        redis.del({"name", "counter"});
    }
    catch (const Error &e)
    {
        std::cerr << "字符串操作错误: " << e.what() << std::endl;
    }
}

void RedisExamples::listOperations()
{
    std::cout << "\n=== 列表操作 ===" << std::endl;

    try
    {
        std::string list_key = "my_list";

        // 推入元素
        redis.rpush(list_key, "first");
        redis.rpush(list_key, "second");
        redis.lpush(list_key, "zero");

        // 获取列表长度
        auto length = redis.llen(list_key);
        std::cout << "列表长度: " << length << std::endl;

        // 获取范围元素
        std::vector<std::string> elements;
        redis.lrange(list_key, 0, -1, std::back_inserter(elements));

        std::cout << "列表元素: ";
        for (const auto &elem : elements)
        {
            std::cout << elem << " ";
        }
        std::cout << std::endl;

        // 弹出元素
        auto popped = redis.lpop(list_key);
        if (popped)
        {
            std::cout << "弹出的元素: " << *popped << std::endl;
        }

        redis.del(list_key);
    }
    catch (const Error &e)
    {
        std::cerr << "列表操作错误: " << e.what() << std::endl;
    }
}

void RedisExamples::hashOperations()
{
    std::cout << "\n=== 哈希操作 ===" << std::endl;

    try
    {
        std::string hash_key = "user:1001";

        // 设置哈希字段
        redis.hset(hash_key, "name", "John Doe");
        redis.hset(hash_key, "age", "30");
        redis.hset(hash_key, "email", "john@example.com");

        // 获取单个字段
        auto name = redis.hget(hash_key, "name");
        if (name)
        {
            std::cout << "姓名: " << *name << std::endl;
        }

        // 获取所有字段
        std::unordered_map<std::string, std::string> all_fields;
        redis.hgetall(hash_key, std::inserter(all_fields, all_fields.begin()));

        std::cout << "所有字段:" << std::endl;
        for (const auto &field : all_fields)
        {
            std::cout << "  " << field.first << ": " << field.second << std::endl;
        }

        // 数字操作
        redis.hincrby(hash_key, "age", 1);
        auto new_age = redis.hget(hash_key, "age");
        if (new_age)
        {
            std::cout << "新年龄: " << *new_age << std::endl;
        }

        redis.del(hash_key);
    }
    catch (const Error &e)
    {
        std::cerr << "哈希操作错误: " << e.what() << std::endl;
    }
}

void RedisExamples::setOperations()
{
    std::cout << "\n=== 集合操作 ===" << std::endl;

    try
    {
        std::string set_key = "my_set";

        // 添加元素
        redis.sadd(set_key, "apple");
        redis.sadd(set_key, "banana");
        redis.sadd(set_key, "orange");
        redis.sadd(set_key, "apple"); // 重复元素不会被添加

        // 获取集合大小
        auto size = redis.scard(set_key);
        std::cout << "集合大小: " << size << std::endl;

        // 获取所有成员
        std::vector<std::string> members;
        redis.smembers(set_key, std::back_inserter(members));

        std::cout << "集合成员: ";
        for (const auto &member : members)
        {
            std::cout << member << " ";
        }
        std::cout << std::endl;

        // 检查成员是否存在
        bool exists = redis.sismember(set_key, "apple");
        std::cout << "apple 是否存在: " << (exists ? "是" : "否") << std::endl;

        redis.del(set_key);
    }
    catch (const Error &e)
    {
        std::cerr << "集合操作错误: " << e.what() << std::endl;
    }
}

void RedisExamples::transactionOperations()
{
    std::cout << "\n=== 事务操作 ===" << std::endl;

    try
    {
        // 只执行设置操作，不获取结果
        auto tx = redis.transaction();

        tx.set("tx_key1", "value1");
        tx.set("tx_key2", "value2");
        tx.incr("tx_counter");

        // 提交事务
        tx.exec();

        std::cout << "事务执行成功" << std::endl;

        // 验证结果（在事务外查询）
        auto value1 = redis.get("tx_key1");
        auto value2 = redis.get("tx_key2");
        auto counter = redis.get("tx_counter");

        if (value1)
            std::cout << "tx_key1: " << *value1 << std::endl;
        if (value2)
            std::cout << "tx_key2: " << *value2 << std::endl;
        if (counter)
            std::cout << "tx_counter: " << *counter << std::endl;

        // 清理
        redis.del({"tx_key1", "tx_key2", "tx_counter"});
    }
    catch (const Error &e)
    {
        std::cerr << "事务操作错误: " << e.what() << std::endl;
    }
}

void RedisExamples::LuaTransaction()
{
    std::cout << "\n=== Lua 事务回滚测试 ===" << std::endl;

    try
    {
        redis.set("acc:X", "100");
        redis.set("acc:Y", "50");

        std::cout << "初始 - X: " << *redis.get("acc:X")
                  << ", Y: " << *redis.get("acc:Y") << std::endl;

        // 事务脚本：要么全部成功，要么全部回滚
        std::string tx_script = R"(
            local from = KEYS[1]
            local to = KEYS[2] 
            local amount = tonumber(ARGV[1])
            
            -- 先读取，不修改
            local from_balance = tonumber(redis.call('GET', from))
            local to_balance = tonumber(redis.call('GET', to))
            
            -- 验证
            if from_balance < amount then
                return "错误：余额不足"
            end
            
            -- 验证通过，执行转账
            redis.call('DECRBY', from, amount)
            redis.call('INCRBY', to, amount)
            
            -- 最终验证（模拟业务规则）
            if amount > 80 then
                -- 违反规则，回滚操作
                redis.call('INCRBY', from, amount)  -- 退款
                redis.call('DECRBY', to, amount)    -- 扣回
                return "错误：金额超过限制，已回滚"
            end
            
            return "成功"
        )";

        // 测试
        auto result = redis.eval<std::string>(tx_script, {"acc:X", "acc:Y"}, {"90"});
        std::cout << "转账结果: " << result << std::endl;
        std::cout << "最终 - X: " << *redis.get("acc:X")
                  << ", Y: " << *redis.get("acc:Y") << std::endl;

        redis.del({"acc:X", "acc:Y"});
    }
    catch (const sw::redis::Error &e)
    {
        std::cerr << "错误: " << e.what() << std::endl;
    }
}

void RedisExamples::pubsubOperations()
{
    std::cout << "\n=== 发布订阅操作 ===" << std::endl;

    try
    {
        // 创建连接配置
        sw::redis::ConnectionOptions conn_opts;
        conn_opts.host = "127.0.0.1";
        conn_opts.port = 6382;
        conn_opts.socket_timeout = std::chrono::seconds(1);

        sw::redis::ConnectionPoolOptions pool_opts;
        pool_opts.size = 1;

        // 使用shared_ptr管理Redis实例
        auto redis_ptr = std::make_shared<sw::redis::Redis>(conn_opts, pool_opts);

        // 在单独的线程中运行订阅者
        std::thread subscriber_thread([redis_ptr]() { // 值捕获，安全！
            try
            {
                auto sub = redis_ptr->subscriber();

                sub.on_message([](std::string channel, std::string msg)
                               { std::cout << "[订阅者] 收到消息 - 频道: " << channel
                                           << ", 消息: " << msg << std::endl; });

                sub.subscribe("test_channel");

                // 运行一段时间后自动退出, 如果是生产环境就不必退出了
                auto end_time = std::chrono::steady_clock::now() + std::chrono::seconds(30);
                while (std::chrono::steady_clock::now() < end_time)
                {
                    try
                    {
                        sub.consume();
                    }
                    catch (const sw::redis::TimeoutError &e)
                    {
                        continue;
                    }
                }

                std::cout << "[订阅者] 监听时间到，正常退出" << std::endl;
            }
            catch (const Error &e)
            {
                std::cerr << "订阅错误: " << e.what() << std::endl;
            }
        });

        // 给订阅者一些时间准备
        std::this_thread::sleep_for(std::chrono::milliseconds(100));

        // 发布消息
        redis_ptr->publish("test_channel", "Hello from publisher!");
        redis_ptr->publish("test_channel", "Second message");

        // 现在可以安全detach
        subscriber_thread.detach();

        std::cout << "主线程继续执行，订阅线程在后台运行30秒后自动退出" << std::endl;
    }
    catch (const Error &e)
    {
        std::cerr << "发布订阅错误: " << e.what() << std::endl;
    }
}

void RedisExamples::pipelineBasic()
{
    std::cout << "\n=== Pipeline 基本使用 ===" << std::endl;

    try
    {
        auto pipe = redis.pipeline();

        // 添加命令到 pipeline
        pipe.set("pipeline_key", "pipeline_value");
        pipe.get("pipeline_key");
        pipe.incr("pipeline_counter");
        pipe.hset("pipeline_hash", "field", "value");

        // 执行所有命令
        auto replies = pipe.exec();

        // 获取结果
        std::cout << "SET 结果: " << replies.get<bool>(0) << std::endl;

        auto value = replies.get<sw::redis::OptionalString>(1);
        if (value)
        {
            std::cout << "GET 结果: " << *value << std::endl;
        }

        std::cout << "INCR 结果: " << replies.get<long long>(2) << std::endl;
        std::cout << "HSET 结果: " << replies.get<bool>(3) << std::endl;
    }
    catch (const Error &e)
    {
        std::cerr << "Pipeline 错误: " << e.what() << std::endl;
    }
}
```

- `incr` : 数字操作, 对指定键的值递增1.
- `setex` : 中间多填一个std::chrono::seconds()来设置TTL, 应该实际中用的都是这个.
- 批量操作中`mget`用到的`std::back_inserter`, 这个是输出迭代器, 之前在c++primer中有看过, 简单理解就是可以从容器中获取其, 对其进行**赋值动作就等于进行push_back操作**, 其专门**针对序列容器**. 在这里的应用就是把输出填入values. 而后面的`std::inserter`可以应用于关联容器和序列容器.
- 事务与集群在下面专门讲解, 不再赘述.

测试代码 : 

```cpp
void testStandaloneRedis() {
    std::cout << "=== 测试单机Redis (6382端口) ===" << std::endl;
    
    RedisExamples examples("tcp://127.0.0.1:6382");
    
    if (!examples.testConnection()) {
        std::cerr << "单机Redis连接测试失败!" << std::endl;
        return;
    }
    
    examples.stringOperations();
    examples.listOperations();
    examples.hashOperations();
    examples.setOperations();
    examples.transactionOperations();
    examples.LuaTransaction();
    examples.pubsubOperations();
    examples.pipelineBasic();
    
    std::cout << "单机Redis测试完成!" << std::endl << std::endl;
}
```

测试结果:

```cpp
➜  build ./redis_test
Redis-plus-plus 集群测试程序
=== 测试单机Redis (6382端口) ===
连接测试: PONG
获取测试值: Hello, Redis!

=== 字符串操作 ===
姓名: Alice
计数器: 11
key1: value1
key2: value2
key3: value3

=== 列表操作 ===
列表长度: 3
列表元素: zero first second 
弹出的元素: zero

=== 哈希操作 ===
姓名: John Doe
所有字段:
  email: john@example.com
  age: 30
  name: John Doe
新年龄: 31

=== 集合操作 ===
集合大小: 3
集合成员: orange banana apple 
apple 是否存在: 是

=== 事务操作 ===
事务执行成功
tx_key1: value1
tx_key2: value2
tx_counter: 1

=== Lua 事务回滚测试 ===
初始 - X: 100, Y: 50
转账结果: 错误：金额超过限制，已回滚
最终 - X: 100, Y: 50

=== 发布订阅操作 ===
[订阅者] 收到消息 - 频道: test_channel, 消息: Hello from publisher!
[订阅者] 收到消息 - 频道: test_channel, 消息: Second message
主线程继续执行，订阅线程在后台运行30秒后自动退出

=== Pipeline 基本使用 ===
SET 结果: 1
GET 结果: pipeline_value
INCR 结果: 2
HSET 结果: 0
单机Redis测试完成!
```

### 集群代码测试

集群上一章已经讲了很多了, 实际使用却非常简单, 和普通Redis操作基本一样, 只要传入正确的集群ip就行.

下面是测试代码 : 

```cpp
// redis_cluster_examples.h
#include <sw/redis++/redis_cluster.h>
#include <iostream>
#include <vector>
#include <unordered_map>

using namespace sw::redis;

class RedisClusterExamples {
public:
    RedisClusterExamples(const std::string& connection_string = "tcp://127.0.0.1:7000");
    // 基本连接测试
    bool testConnection();  
    // 集群信息查询
    void clusterInfo(); 
    // 键操作（自动路由到正确的节点）
    void keyOperations();  
    // 字符串操作
    void stringOperations();
    // 哈希操作
    void hashOperations();
    // 列表操作
    void listOperations();
    // 集群特定操作
    void clusterSpecificOperations();
    // 哈希标签
    void hashTagOperations();
private:
    RedisCluster cluster;
};
```

```cpp
// redis_cluster_examples.cpp
#include "redis_cluster_examples.h"
#include <chrono>

RedisClusterExamples::RedisClusterExamples(const std::string& connection_string) 
    : cluster(connection_string) {
}

bool RedisClusterExamples::testConnection() {
    try {
        // 修正：使用 set/get 测试连接，而不是 ping
        cluster.set("cluster_test_key", "Hello, Redis Cluster!");
        auto value = cluster.get("cluster_test_key");
        
        if (value) {
            std::cout << "集群连接测试: 成功" << std::endl;
            std::cout << "获取集群测试值: " << *value << std::endl;
        }
        
        cluster.del("cluster_test_key");
        return true;
        
    } catch (const Error& e) {
        std::cerr << "Redis集群错误: " << e.what() << std::endl;
        return false;
    }
}

void RedisClusterExamples::clusterInfo() {
    std::cout << "\n=== 集群信息查询 ===" << std::endl;
    
    try {
        // 修正：使用 command 方法执行 CLUSTER NODES 和 CLUSTER SLOTS 命令
        auto nodes_reply = cluster.command("CLUSTER", "NODES");
        std::cout << "集群节点信息:" << std::endl;
        if (nodes_reply) {
            // std::cout << nodes_reply->str() << std::endl;
        }
        
        auto slots_reply = cluster.command("CLUSTER", "SLOTS");
        std::cout << "集群槽信息获取成功" << std::endl;
        
    } catch (const Error& e) {
        std::cerr << "集群信息查询错误: " << e.what() << std::endl;
    }
}

void RedisClusterExamples::keyOperations() {
    std::cout << "\n=== 键操作（自动路由） ===" << std::endl;
    
    try {
        // 测试不同slot的键
        std::vector<std::string> keys = {
            "user:1001",    // 可能在一个slot
            "product:2001", // 可能在另一个slot
            "order:3001"    // 可能在第三个slot
        };
        
        // 设置多个键（会自动路由到不同节点）
        for (const auto& key : keys) {
            cluster.set(key, "value_for_" + key);
            std::cout << "设置键: " << key << std::endl;
        }
        
        // 获取键值
        for (const auto& key : keys) {
            auto value = cluster.get(key);
            if (value) {
                std::cout << "获取键 " << key << ": " << *value << std::endl;
            }
        }
        
        // 测试键是否存在
        for (const auto& key : keys) {
            bool exists = cluster.exists(key);
            std::cout << "键 " << key << " 是否存在: " << (exists ? "是" : "否") << std::endl;
        }
        
        // 清理
        for (const auto& key : keys) {
            cluster.del(key);
        }
        
    } catch (const Error& e) {
        std::cerr << "键操作错误: " << e.what() << std::endl;
    }
}

void RedisClusterExamples::stringOperations() {
    std::cout << "\n=== 字符串操作 ===" << std::endl;
    
    try {
        // 基本操作
        cluster.set("cluster_counter", "100");
        cluster.incr("cluster_counter");
        auto counter = cluster.get("cluster_counter");
        if (counter) {
            std::cout << "计数器值: " << *counter << std::endl;
        }
        
        // 带过期时间
        cluster.setex("cluster_temp", std::chrono::seconds(10), "临时数据");
        
        // 批量操作
        std::unordered_map<std::string, std::string> data = {
            {"cluster_key1", "value1"},
            {"cluster_key2", "value2"},
            {"cluster_key3", "value3"}
        };
        
        for (const auto& item : data) {
            cluster.set(item.first, item.second);
        }
        
        // 批量获取
        for (const auto& item : data) {
            auto val = cluster.get(item.first);
            if (val) {
                std::cout << item.first << ": " << *val << std::endl;
            }
        }
        
        // 清理
        for (const auto& item : data) {
            cluster.del(item.first);
        }
        cluster.del("cluster_counter");
        cluster.del("cluster_temp");
        
    } catch (const Error& e) {
        std::cerr << "字符串操作错误: " << e.what() << std::endl;
    }
}

void RedisClusterExamples::hashOperations() {
    std::cout << "\n=== 哈希操作 ===" << std::endl;
    
    try {
        std::string hash_key = "cluster_user:1001";
        
        // 设置哈希字段
        cluster.hset(hash_key, "name", "Cluster User");
        cluster.hset(hash_key, "age", "30");
        cluster.hset(hash_key, "city", "Beijing");
        
        // 获取单个字段
        auto name = cluster.hget(hash_key, "name");
        if (name) {
            std::cout << "用户名: " << *name << std::endl;
        }
        
        // 获取所有字段
        std::unordered_map<std::string, std::string> all_fields;
        cluster.hgetall(hash_key, std::inserter(all_fields, all_fields.begin()));
        
        std::cout << "用户信息:" << std::endl;
        for (const auto& field : all_fields) {
            std::cout << "  " << field.first << ": " << field.second << std::endl;
        }
        
        // 数字操作
        cluster.hincrby(hash_key, "age", 1);
        auto new_age = cluster.hget(hash_key, "age");
        if (new_age) {
            std::cout << "新年龄: " << *new_age << std::endl;
        }
        
        cluster.del(hash_key);
        
    } catch (const Error& e) {
        std::cerr << "哈希操作错误: " << e.what() << std::endl;
    }
}

void RedisClusterExamples::listOperations() {
    std::cout << "\n=== 列表操作 ===" << std::endl;
    
    try {
        std::string list_key = "cluster_queue";
        
        // 推入元素
        cluster.rpush(list_key, "item1");
        cluster.rpush(list_key, "item2");
        cluster.lpush(list_key, "item0");
        
        // 获取列表长度
        auto length = cluster.llen(list_key);
        std::cout << "队列长度: " << length << std::endl;
        
        // 获取范围元素
        std::vector<std::string> elements;
        cluster.lrange(list_key, 0, -1, std::back_inserter(elements));
        
        std::cout << "队列内容: ";
        for (const auto& elem : elements) {
            std::cout << elem << " ";
        }
        std::cout << std::endl;
        
        // 弹出元素
        auto popped = cluster.lpop(list_key);
        if (popped) {
            std::cout << "弹出的元素: " << *popped << std::endl;
        }
        
        cluster.del(list_key);
        
    } catch (const Error& e) {
        std::cerr << "列表操作错误: " << e.what() << std::endl;
    }
}

void RedisClusterExamples::clusterSpecificOperations() {
    std::cout << "\n=== 集群特定操作 ===" << std::endl;
    
    try {
        // 修正：使用 command 方法执行 CLUSTER INFO 命令
        auto info_reply = cluster.command("CLUSTER", "INFO");
        std::cout << "集群信息:" << std::endl;
        if (info_reply) {
            // std::cout << info_reply->str() << std::endl;
        }
        
        std::cout << "集群状态: 正常" << std::endl;
        
    } catch (const Error& e) {
        std::cerr << "集群特定操作错误: " << e.what() << std::endl;
    }
}

void RedisClusterExamples::hashTagOperations() {
    std::cout << "\n=== 哈希标签测试 ===" << std::endl;
    
    try {
        std::string user_id = "1001";
        std::string order_id = "20240115001";
        
        // 1. 测试哈希标签的基本功能
        std::cout << "哈希标签基本功能测试:" << std::endl;
        
        // 使用相同哈希标签的键（会在同一个节点）
        cluster.set("user:{" + user_id + "}:name", "张三");
        cluster.set("user:{" + user_id + "}:age", "25");
        cluster.set("user:{" + user_id + "}:email", "zhang@example.com");
        
        // 验证数据设置成功
        auto name = cluster.get("user:{" + user_id + "}:name");
        auto age = cluster.get("user:{" + user_id + "}:age");
        auto email = cluster.get("user:{" + user_id + "}:email");
        
        if (name) std::cout << "  用户名: " << *name << std::endl;
        if (age) std::cout << "  年龄: " << *age << std::endl;
        if (email) std::cout << "  邮箱: " << *email << std::endl;
        
        // 测试不同哈希标签的数据分布
        std::cout << "\n不同哈希标签的数据分布测试:" << std::endl;
        
        cluster.set("order:{" + order_id + "}:amount", "199.99");
        cluster.set("order:{" + order_id + "}:status", "paid");
        
        auto amount = cluster.get("order:{" + order_id + "}:amount");
        auto status = cluster.get("order:{" + order_id + "}:status");
        
        if (amount) std::cout << "  订单金额: " << *amount << std::endl;
        if (status) std::cout << "  订单状态: " << *status << std::endl;
        
        std::vector<std::string> keys_to_delete = {
            "user:{" + user_id + "}:name",
            "user:{" + user_id + "}:age", 
            "user:{" + user_id + "}:email",
            "user:{" + user_id + "}:last_login",
            "user:{" + user_id + "}:login_count",
            "user:{" + user_id + "}:profile",
            "user:{" + user_id + "}:counter1",
            "user:{" + user_id + "}:counter2",
            "order:{" + order_id + "}:amount",
            "order:{" + order_id + "}:status"
        };
        
        for (const auto& key : keys_to_delete) {
            cluster.del(key);
        }
        
        std::cout << "哈希标签测试完成!" << std::endl;
        
    } catch (const Error& e) {
        std::cerr << "哈希标签测试错误: " << e.what() << std::endl;
    }
}
```

- 哈希标签:

  这是这里唯一要额外解释的一种使用方式, 你可以理解**哈希标签是一种键的性质**.

  **只要一个键中带有花括号`{}`, 那么计算哈希时就只会用花括号内的, 如果没有则用整个键算**.

  因此**只要花括号内值一致, 就算键不同, 也一定会被分到同一个节点中**.

  这种机制的目的在于 : **将一些关联度较高的数据设置相同的哈希标签, 使其存放到同一个节点中, 使得同时读取它们不需要到多个节点中去找, 从而提升性能.**

测试代码:

```cpp
void testClusterRedis() {
    std::cout << "=== 测试Redis集群 (7000端口) ===" << std::endl;
    
    RedisClusterExamples cluster_examples("tcp://127.0.0.1:7000");
    
    if (!cluster_examples.testConnection()) {
        std::cerr << "Redis集群连接测试失败!" << std::endl;
        return;
    }
    
    cluster_examples.clusterInfo();
    cluster_examples.keyOperations();
    cluster_examples.stringOperations();
    cluster_examples.hashOperations();
    cluster_examples.listOperations();
    cluster_examples.clusterSpecificOperations();
    cluster_examples.hashTagOperations();
    
    std::cout << "Redis集群测试完成!" << std::endl;
}
```

测试结果 : 

```cpp
=== 测试Redis集群 (7000端口) ===
集群连接测试: 成功
获取集群测试值: Hello, Redis Cluster!

=== 集群信息查询 ===
集群节点信息:
集群槽信息获取成功

=== 键操作（自动路由） ===
设置键: user:1001
设置键: product:2001
设置键: order:3001
获取键 user:1001: value_for_user:1001
获取键 product:2001: value_for_product:2001
获取键 order:3001: value_for_order:3001
键 user:1001 是否存在: 是
键 product:2001 是否存在: 是
键 order:3001 是否存在: 是

=== 字符串操作 ===
计数器值: 101
cluster_key3: value3
cluster_key2: value2
cluster_key1: value1

=== 哈希操作 ===
用户名: Cluster User
用户信息:
  age: 30
  city: Beijing
  name: Cluster User
新年龄: 31

=== 列表操作 ===
队列长度: 3
队列内容: item0 item1 item2 
弹出的元素: item0

=== 集群特定操作 ===
集群信息:
集群状态: 正常

=== 哈希标签测试 ===
哈希标签基本功能测试:
  用户名: 张三
  年龄: 25
  邮箱: zhang@example.com

不同哈希标签的数据分布测试:
  订单金额: 199.99
  订单状态: paid

哈希标签测试完成!
Redis集群测试完成!
```



by 天目中云



