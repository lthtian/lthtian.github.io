---
title: Redis深入学习(2) 分布式锁
date: 2025-10-26 22:00:00
tags: [Redis]
---

> Redis分布式锁

### 分布式锁

看起来很高端, 但是非常易懂, 类似于线程中的互斥锁, 用来保证不同线程间的资源共享, 把这里的**线程提升到服务器**, 对应的就是分布式锁了. 

其实本质就是在做**不同服务器上的进程/线程对于共享资源的管理**.

解决的思路也比较统一, 以我目前的学习程度看来就是单独**在一个服务器上开一个分布式锁服务, 统一到这个服务上申请使用权**.

实现这种分布式锁功能的中间件有很多, Redis就是其中之一.

### 本质理解

在Redis中分布式锁的实现非常简单甚至原始, 你可以简单理解为就是**SET一对键值, 键存在表示有占用, 键不存在表示无占用并持有锁**.

下面是SET命令格式 : 

```cpp
SET key value [NX|XX] [GET] [EX seconds|PX milliseconds|EXAT timestamp|PXAT milliseconds-timestamp|KEEPTTL]
```

这时我们要用的就是NX表示**键不存在时才能设置**, PX表示**过期时间**. 用hiredis表示如下 :

```cpp
redisReply* reply = (redisReply*)redisCommand(context, "SET %s %s NX PX %d", key, value, lockTimeout);
```

- 超过过期时间后键值自动删除, 其实就等同于**锁释放**, 当然也可以用完提前删除释放.
- 注意Redis实现如此简单的前提在于, Redis本身就是一个**单线程**程序, 就算多个服务器同时申请锁, 也不会有任何线程问题.

### 进一步封装

先看锁申请 : 

```cpp
/**
 * 获取分布式锁
 * @param lockName 锁名称
 * @param lockTimeout 锁超时时间（毫秒）
 * @param acquireTimeout 获取锁的超时时间（毫秒）
 * @return 锁标识符，如果获取失败返回空字符串
 */
std::string RedisMgr::acquireLock(const std::string& lockName, int lockTimeout, int acquireTimeout) {
	// 实现分布式锁获取逻辑
	std::string identifier = "lock_" + std::to_string(rand());
	const char* key = lockName.c_str();
	const char* value = identifier.c_str();
	int retryCount = 0;
	int maxRetries = acquireTimeout / 100; // 每100ms重试一次

	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return "";
	}

	while (retryCount < maxRetries) {
		// 使用SET命令的NX和PX选项实现分布式锁
		redisReply* reply = (redisReply*)redisCommand(context, "SET %s %s NX PX %d", key, value, lockTimeout);
		if (reply && reply->type == REDIS_REPLY_STATUS && strcmp(reply->str, "OK") == 0) {
			freeReplyObject(reply);
			con_pool_->returnConnection(context);
			return identifier;
		}
		freeReplyObject(reply);
		retryCount++;
		std::this_thread::sleep_for(std::chrono::milliseconds(100));
	}

	con_pool_->returnConnection(context);
	return "";
}
```

- 这里对于键对应的值只是放了个rand(), 但是实际应该放很多信息, 比如订单ID, 用户, pid, tid, timestamp等等, 这样在一个锁被异常持有时就可以**准确追根溯源, 或是统计锁的竞争使用情况**, 不同公司对锁值有不同的规定, 比如阿里就是`hostname_ip:pid:threadid:timestamp`, 可以类似如下函数生成 :

  ```cpp
  std::string generate_lock_id() {
      char hostname[256];
      gethostname(hostname, sizeof(hostname));
          
      auto now = std::chrono::system_clock::now();
      auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
          now.time_since_epoch()).count();
          
      char buffer[512];
      snprintf(buffer, sizeof(buffer), "%s|pid%d|tid%ld|ts%ld",
               hostname,
               getpid(),
               syscall(SYS_gettid), // 获取线程ID
               now_ms);
          
      return std::string(buffer);
  }
  ```

- 另外还做了重复尝试申请, 超过一定次数后才退出.

再看锁释放 : 

```cpp
/**
 * 释放分布式锁
 * @param lockName 锁名称
 * @param identifier 锁标识符
 * @return 释放是否成功
 */
bool RedisMgr::releaseLock(const std::string& lockName, const std::string& identifier) {
	// 实现分布式锁释放逻辑
	const char* key = lockName.c_str();
	const char* value = identifier.c_str();

	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	// 使用Lua脚本确保原子性，防止误删其他客户端的锁
	const char* script = 
		"if redis.call('get', KEYS[1]) == ARGV[1] then "
		"return redis.call('del', KEYS[1]) "
		"else "
		"return 0 "
		"end";

	redisReply* reply = (redisReply*)redisCommand(context, "EVAL %s 1 %s %s", script, key, value);
	if (!reply || reply->type != REDIS_REPLY_INTEGER || reply->integer == 0) {
		freeReplyObject(reply);
		con_pool_->returnConnection(context);
		return false;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return true;
}
```

- 这里做的其实就是如果键对应的值还是自己的, 就进行删除操作, 相当于释放锁.
- 不过这里实际需要完成两个操作, **为了保证原子性就必须把两个操作封装在一个Lua语句中**, 交给Redis执行, Redis天然支持解读Lua脚本语言, 再加上自己的单线程特性, 很容易实现多个操作的原子化.

### 锁续期(看门狗)

这里依旧是看了一大堆, 但是本质依旧很简单, 这里分为前提和做法.

- 前提 : 
  - Redis在针对锁设置键值时**必须设置TTL**, 不能依赖于手动删除, 因为一旦使用Redis的客户端宕机, 就**必定会发生锁的无限占有**, 这是灾难性的.
  - 我们一般会将自动删除的TTL设置的比较久, 比如3-5秒, 但是有些任务执行的时间确实会因为需求与现况不同有长有短, 在高峰期有时就是会超过TTL. 这里的隐患是, 一旦超TTL自动删除, 客户端并不知情, 因为其没有调用过`releaseLock`, **自认为锁还被自己持有, 但很有可能已被其他线程持有, 于是就会发生资源竞争**.
- 做法 : 
  - 其实我们想实现的效果就是, **只要客户端还没有调用`releaseLock`, 并且客户端还健在, 就不自动释放锁**, 这种效果便可以由锁续期(看门狗)来实现. 
  - 实现也容易理解, 调用`acquireLock`就将锁存入map, 调用`releaseLock`就将锁移出map, 在map中的锁会有一个线程持续进行重置超时时间.

这样只要客户端任务没结束并且不崩溃, 所有就会一直被独占, 不会发生资源竞争, 我们来看看代码 : 

```cpp
// LockRenewer.h
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>
#include <hiredis/hiredis.h>
#include "RedisMgr.h"

// 锁续期任务管理器
class LockRenewer {
public:
    LockRenewer(RedisConPool* pool)
        : pool_(pool), running_(true), manager_thread_(&LockRenewer::run_manager, this) {}
    
    ~LockRenewer() {
        stop();
        if (manager_thread_.joinable()) {
            manager_thread_.join();
        }
    }
    
    void start(const std::string& lock_name, 
               const std::string& identifier, 
               int lock_timeout_ms) {
        std::lock_guard<std::mutex> lock(mutex_);
        
        // 如果已有续期任务，先停止
        if (tasks_.find(lock_name) != tasks_.end()) {
            stop(lock_name);
        }
        
        auto task = std::make_shared<RenewTask>();
        task->lock_name = lock_name;
        task->identifier = identifier;
        task->lock_timeout_ms = lock_timeout_ms;
        task->renew_interval = lock_timeout_ms / 3;
        task->next_renew_time = std::chrono::steady_clock::now() + 
                               std::chrono::milliseconds(task->renew_interval);
        task->running = true;
        
        tasks_[lock_name] = task;
        cv_.notify_one(); // 唤醒管理器线程
    }
    
    void stop(const std::string& lock_name) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = tasks_.find(lock_name);
        if (it != tasks_.end()) {
            it->second->running = false;
            tasks_.erase(it);
        }
    }
    
    void stop() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            running_ = false;
            for (auto& [_, task] : tasks_) {
                task->running = false;
            }
            tasks_.clear();
        }
        cv_.notify_one();
    }

private:
    struct RenewTask {
        std::string lock_name;
        std::string identifier;
        int lock_timeout_ms;
        int renew_interval;
        std::chrono::steady_clock::time_point next_renew_time;
        std::atomic<bool> running;
    };
    
    void run_manager() {
        while (running_) {
            std::vector<std::shared_ptr<RenewTask>> tasks_to_renew;
            
            // 获取需要续期的任务
            {
                std::unique_lock<std::mutex> lock(mutex_);
                
                // 计算最近需要续期的时间
                auto next_wake_time = std::chrono::steady_clock::now() + std::chrono::seconds(10);
                for (const auto& [_, task] : tasks_) {
                    if (task->next_renew_time < next_wake_time) {
                        next_wake_time = task->next_renew_time;
                    }
                }
                
                // 等待到下一个续期时间或新任务
                cv_.wait_until(lock, next_wake_time, [&] {
                    return !running_ || !tasks_.empty();
                });
                
                if (!running_) break;
                
                // 收集需要续期的任务
                auto now = std::chrono::steady_clock::now();
                for (const auto& [_, task] : tasks_) {
                    if (task->running && task->next_renew_time <= now) {
                        tasks_to_renew.push_back(task);
                    }
                }
            }
            
            // 执行续期操作
            for (auto& task : tasks_to_renew) {
                if (!task->running) continue;
                bool success = renew_lock(task);
                
                // 更新下次续期时间
                if (task->running) {
                    task->next_renew_time = std::chrono::steady_clock::now() + 
                                          std::chrono::milliseconds(task->renew_interval);
                }
            }
        }
    }
    
    bool renew_lock(const std::shared_ptr<RenewTask>& task) {
        redisContext* conn = pool_->getConnection();
        if (!conn) return false;
        
        const char* script = 
            "if redis.call('GET', KEYS[1]) == ARGV[1] then "
            "   return redis.call('PEXPIRE', KEYS[1], ARGV[2]) "
            "else "
            "   return 0 "
            "end";
        
        redisReply* reply = nullptr;
        bool success = false;
        
        try {
            reply = (redisReply*)redisCommand(conn, 
                "EVAL %s 1 %s %s %d", 
                script, 
                task->lock_name.c_str(), 
                task->identifier.c_str(),
                task->lock_timeout_ms);
            
            success = (reply && 
                      reply->type == REDIS_REPLY_INTEGER && 
                      reply->integer == 1);
        } catch (...) {
            // 异常处理
            success = false;
        }
        
        if (reply) freeReplyObject(reply);
        pool_->returnConnection(conn);
        return success;
    }
    
    RedisConPool* pool_;
    std::atomic<bool> running_;
    std::thread manager_thread_;
    std::mutex mutex_;
    std::condition_variable cv_;
    std::unordered_map<std::string, std::shared_ptr<RenewTask>> tasks_;
};
```

这里便会实现在map中的锁在超时之前就进行重置, 除非由极端情况网络问题, 不然是非常健全的. 我们将其加入RedisMgr : 

```cpp
RedisMgr::RedisMgr() {
	con_pool_ = std::make_unique<RedisConPool>(10, "127.0.0.1", 6379, "");
	lock_renewer_ = std::make_unique<LockRenewer>(con_pool_.get());
}

RedisMgr::~RedisMgr() {
	Close();
	// 确保锁续期管理器正确关闭
    if (lock_renewer_) {
        lock_renewer_->stop();
    }
}

// .....

std::string RedisMgr::acquireLock(const std::string& lockName, int lockTimeout, int acquireTimeout) {
    std::string identifier = generate_lock_id();
    
    const char* key = lockName.c_str();
    const char* value = identifier.c_str();
    int retryCount = 0;
    int maxRetries = acquireTimeout / 100;

    redisContext* context = con_pool_->getConnection();
    if (!context) {
        return "";
    }

    while (retryCount < maxRetries) {
        redisReply* reply = (redisReply*)redisCommand(context, "SET %s %s NX PX %d", key, value, lockTimeout);
        if (reply && reply->type == REDIS_REPLY_STATUS && strcmp(reply->str, "OK") == 0) {
            freeReplyObject(reply);
            con_pool_->returnConnection(context);
            
            // 针对当前锁启动锁续期
            lock_renewer_->start(lockName, identifier, lockTimeout);
            
            return identifier;
        }
        
        if (reply) freeReplyObject(reply);
        retryCount++;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    con_pool_->returnConnection(context);
    return "";
}

bool RedisMgr::releaseLock(const std::string& lockName, const std::string& identifier) {
    // 先停止续期
    lock_renewer_->stop(lockName);
    
    const char* key = lockName.c_str();
    const char* value = identifier.c_str();

    redisContext* context = con_pool_->getConnection();
    if (!context) {
        return false;
    }

    const char* script = 
        "if redis.call('get', KEYS[1]) == ARGV[1] then "
        "return redis.call('del', KEYS[1]) "
        "else "
        "return 0 "
        "end";

    redisReply* reply = (redisReply*)redisCommand(context, "EVAL %s 1 %s %s", script, key, value);
    if (!reply || reply->type != REDIS_REPLY_INTEGER || reply->integer == 0) {
        if (reply) freeReplyObject(reply);
        con_pool_->returnConnection(context);
        return false;
    }

    freeReplyObject(reply);
    con_pool_->returnConnection(context);
    return true;
}
```

- 监视机制 : 这里其实可以写一些监视机制来分析锁的使用情况, 锁冲突情况等等, 会很便于后台分析监控, 但会使代码更加负责, 这里就不加赘述.

### RedLock

这是应对Redis分布式锁另外一个问题的技术, 是Redis官方推荐的解决方式.

- 问题所在 : 如果锁都只在一个服务器的Redis服务上申请, 那么只要这台服务器挂了, 那么锁服务就瘫痪了.

- 解决方式 : 大道至简, 多开几个服务器, 申请分布式锁要向所有的服务器发出请求, 只要大多数请求成功, 便会认为锁获取成功.
- 具体实现 : 其实可以基于我这里的代码在上层进一步封装RedLock, 但鉴于我只是学习, 实际使用还是直接用现成库就好, 就不继续封装了.



by 天目中云