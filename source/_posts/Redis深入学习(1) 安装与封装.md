---
title: Redis深入学习(1) 安装与封装
date: 2025-10-25 20:00:00
tags: [Redis]
---

### vcpkg 

一个安装管理器, 你可以认为类似于ubuntu的apt, 这个安装器跨平台, windows和linux都可以用, 可以一键部署下载很多C/C++的核心第三方库.

其对CMake配置的项目有天然助益, 有清单配置之类的功能, 之后可以了解一下在vs上使用CMake + vcpkg的方式写几个demo.

### 安装/配置

一般选用hiredis库作为Redis第三方库使用.

- Linux : 其实直接下载就可以, 不用配置直接就能用.
- Windows : 这里我是用的vcpkg安装的hiredis, 确实很方便, 应该避了很多坑, 但是貌似使用CMake会更加方便, 使用vs自己的配置系统需要设置头目录和库目录.

### Redis封装(连接池 + 管理类)

```cpp
// RedisMgr.h
#pragma once
// 在文件顶部添加hiredis头文件
#include <memory>
#include <string>
#include <queue>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <string>
#include <cstring>
#include <iostream>
#include <cstdlib>

// 添加hiredis头文件
#include <hiredis/hiredis.h>

// Redis连接池的前置声明
class RedisConPool {
public:
	RedisConPool(size_t poolSize, const char* host, int port, const char* pwd);
	~RedisConPool();

	void ClearConnections();
	redisContext* getConnection();
	redisContext* getConNonBlock();
	void returnConnection(redisContext* context);
	void Close();

private:
	bool reconnect();
	void checkThreadPro();
	void checkThread();

	std::atomic<bool> b_stop_;
	size_t poolSize_;
	const char* host_;
	const char* pwd_;
	int port_;
	std::queue<redisContext*> connections_;
	std::atomic<int> fail_count_;
	std::mutex mutex_;
	std::condition_variable cond_;
	std::thread  check_thread_;
	int counter_;
};

// 简单的单例模板类
namespace {
	template<typename T>
	class Singleton {
	public:
		static T& Inst() {
			static T instance;
			return instance;
		}

	protected:
		Singleton() = default;
		~Singleton() = default;
		Singleton(const Singleton&) = delete;
		Singleton& operator=(const Singleton&) = delete;
	};
}

class RedisMgr: public Singleton<RedisMgr>, 
	public std::enable_shared_from_this<RedisMgr>
{
	friend class Singleton<RedisMgr>;
public:
	~RedisMgr();
	bool Get(const std::string &key, std::string& value);
	bool Set(const std::string &key, const std::string &value);
	bool LPush(const std::string &key, const std::string &value);
	bool LPop(const std::string &key, std::string& value);
	bool RPush(const std::string& key, const std::string& value);
	bool RPop(const std::string& key, std::string& value);
	bool HSet(const std::string &key, const std::string  &hkey, const std::string &value);
	bool HSet(const char* key, const char* hkey, const char* hvalue, size_t hvaluelen);
	std::string HGet(const std::string &key, const std::string &hkey);
	bool HDel(const std::string& key, const std::string& field);
	bool Del(const std::string &key);
	bool ExistsKey(const std::string &key);
	void Close() {
		con_pool_->Close();
		con_pool_->ClearConnections();
	}

	std::string acquireLock(const std::string& lockName,
		int lockTimeout, int acquireTimeout);

	bool releaseLock(const std::string& lockName,
		const std::string& identifier);

	void IncreaseCount(std::string server_name);
	void DecreaseCount(std::string server_name);
	void InitCount(std::string server_name);
	void DelCount(std::string server_name);
private:
	RedisMgr();
	std::unique_ptr<RedisConPool>  con_pool_;
};
```

```cpp
// RedisMgr.cc
#include "RedisMgr.h"
#include <iostream>
#include <hiredis/hiredis.h>
#include <memory>

/**
 * RedisConPool类：Redis连接池实现
 * 负责管理与Redis服务器的连接池，提供连接获取、归还、健康检查等功能
 * 设计目的：避免频繁创建和销毁Redis连接带来的性能开销
 */
// =========================RedisConPool类===========================================================//
/**
 * RedisConPool构造函数
 * @param poolSize 连接池大小
 * @param host Redis服务器主机地址
 * @param port Redis服务器端口号
 * @param pwd Redis服务器密码
 */
RedisConPool::RedisConPool(size_t poolSize, const char* host, int port, const char* pwd)
	: poolSize_(poolSize), host_(host), port_(port), b_stop_(false), pwd_(pwd), counter_(0), fail_count_(0){
	// 初始化连接池，创建指定数量的连接
	for (size_t i = 0; i < poolSize_; ++i) {
		// 创建Redis连接
		auto* context = redisConnect(host, port);
		if (context == nullptr || context->err != 0) {
			if (context != nullptr) {
				redisFree(context);
			}
			continue;
		}

		// 只有当密码不为空时才进行认证
		if (pwd != nullptr && strlen(pwd) > 0) {
			// 认证连接
			auto reply = (redisReply*)redisCommand(context, "AUTH %s", pwd);
			if (reply == nullptr) {
				std::cout << "认证命令执行失败" << std::endl;
				redisFree(context);
				continue;
			}
			if (reply->type == REDIS_REPLY_ERROR) {
				std::cout << "认证失败: " << reply->str << std::endl;
				//执行成功 释放redisCommand执行后返回的redisReply所占用的内存
				freeReplyObject(reply);
				redisFree(context);
				continue;
			}

			//执行成功 释放redisCommand执行后返回的redisReply所占用的内存
			freeReplyObject(reply);
			std::cout << "认证成功" << std::endl;
		} else {
			std::cout << "密码为空，跳过认证" << std::endl;
		}
		connections_.push(context);
	}

	// 启动连接健康检查线程
	check_thread_ = std::thread([this]() {
		while (!b_stop_) {
			counter_++;
			// 每60秒执行一次连接健康检查
			if (counter_ >= 60) {
				checkThreadPro();
				counter_ = 0;
			}

			std::this_thread::sleep_for(std::chrono::seconds(1)); // 每隔1秒检查一次计数器
		}
	});
}

/**
 * RedisConPool析构函数
 * 关闭连接池并清理所有连接
 */
RedisConPool::~RedisConPool() {
	Close();
	ClearConnections();
}

/**
 * 清理连接池中的所有连接
 */
void RedisConPool::ClearConnections() {
	std::lock_guard<std::mutex> lock(mutex_);
	while (!connections_.empty()) {
		auto* context = connections_.front();
		redisFree(context);
		connections_.pop();
	}
}

/**
 * 获取一个Redis连接（阻塞模式）
 * 如果连接池为空，则等待直到有可用连接或连接池被关闭
 * @return Redis连接上下文指针
 */
redisContext* RedisConPool::getConnection() {
	std::unique_lock<std::mutex> lock(mutex_);
	cond_.wait(lock, [this] { 
		if (b_stop_) {
			return true;
		}
		return !connections_.empty(); 
	});
	//如果停止则直接返回空指针
	if (b_stop_) {
		return nullptr;
	}
	auto* context = connections_.front();
	connections_.pop();
	return context;
}

/**
 * 获取一个Redis连接（非阻塞模式）
 * 如果连接池为空，直接返回nullptr
 * @return Redis连接上下文指针
 */
redisContext* RedisConPool::getConNonBlock() {
	std::unique_lock<std::mutex> lock(mutex_);
	if (b_stop_) {
		return nullptr;
	}

	if (connections_.empty()) {
		return nullptr;
	}

	auto* context = connections_.front();
	connections_.pop();
	return context;
}

/**
 * 归还Redis连接到连接池
 * @param context Redis连接上下文指针
 */
void RedisConPool::returnConnection(redisContext* context) {
	std::lock_guard<std::mutex> lock(mutex_);
	if (b_stop_) {
		return;
	}
	connections_.push(context);
	cond_.notify_one(); // 通知等待中的线程有新的连接可用
}

/**
 * 关闭连接池
 * 设置停止标志，通知所有等待线程，并等待健康检查线程结束
 */
void RedisConPool::Close() {
	b_stop_ = true;
	cond_.notify_all(); // 通知所有等待的线程
	if (check_thread_.joinable()) {
		check_thread_.join(); // 等待健康检查线程结束
	}
}

/**
 * 重连Redis服务器
 * @return 重连是否成功
 */
bool RedisConPool::reconnect() {
	auto context = redisConnect(host_, port_);
	if (context == nullptr || context->err != 0) {
		if (context != nullptr) {
			redisFree(context);
		}
		return false;
	}

	auto reply = (redisReply*)redisCommand(context, "AUTH %s", pwd_);
	if (reply->type == REDIS_REPLY_ERROR) {
		std::cout << "认证失败" << std::endl;
		//执行成功 释放redisCommand执行后返回的redisReply所占用的内存
		freeReplyObject(reply);
		redisFree(context);
		return false;
	}

	//执行成功 释放redisCommand执行后返回的redisReply所占用的内存
	freeReplyObject(reply);
	std::cout << "认证成功" << std::endl;
	returnConnection(context);
	return true;
}

/**
 * 连接池健康检查处理函数
 * 检查所有连接的健康状态，对异常连接进行重连
 */
void RedisConPool::checkThreadPro() {
	size_t pool_size;
	{
		// 先拿到当前连接数（使用局部作用域减少锁持有时间）
		std::lock_guard<std::mutex> lock(mutex_);
		pool_size = connections_.size();
	}

	// 检查每个连接的健康状态
	for (int i = 0; i < pool_size && !b_stop_; ++i) {
		// 1) 取出一个连接(持有锁)
		auto * context = getConNonBlock();
		if (context == nullptr) {
			break;
		}

		redisReply* reply = nullptr;
		try {
			// 发送PING命令检查连接健康状态
			reply = (redisReply*)redisCommand(context, "PING");
			// 2. 先看底层 I/O／协议层有没有错
			if (context->err) {
				std::cout << "Connection error: " << context->err << std::endl;
				if (reply) {
					freeReplyObject(reply);
				}
				redisFree(context);
				fail_count_++;
				continue;
			}

			// 3. 再看 Redis 自身返回的是不是 ERROR
			if (!reply || reply->type == REDIS_REPLY_ERROR) {
				std::cout << "reply is null, redis ping failed: " << std::endl;
				if (reply) {
					freeReplyObject(reply);
				}
				redisFree(context);
				fail_count_++;
				continue;
			}
			// 4. 如果都没问题，则还回去
			freeReplyObject(reply);
			returnConnection(context);
		} catch (std::exception& exp) {
			if (reply) {
				freeReplyObject(reply);
			}

			redisFree(context);
			fail_count_++;
		}
	}

	//执行重连操作，尝试恢复失败的连接
	while (fail_count_ > 0) {
		auto res = reconnect();
		if(res){
			fail_count_--;
		} else {
			//留给下次再重试
			break;
		}
	}
}

/**
 * 另一个版本的连接检查函数
 * 与checkThreadPro类似，但实现方式略有不同
 * 注：该函数当前未被使用，可以考虑移除
 */
void RedisConPool::checkThread() {
	std::lock_guard<std::mutex> lock(mutex_);
	if (b_stop_) {
		return;
	}
	auto pool_size = connections_.size();
	for (int i = 0; i < pool_size && !b_stop_; i++) {
		auto* context = connections_.front();
		connections_.pop();
		try {
			auto reply = (redisReply*)redisCommand(context, "PING");
			if (!reply) {
				std::cout << "reply is null, redis ping failed: " << std::endl;
				connections_.push(context);
				continue;
			}
			freeReplyObject(reply);
			connections_.push(context);
		} catch(std::exception& exp) {
			std::cout << "Error keeping connection alive: " << exp.what() << std::endl;
			redisFree(context);
			context = redisConnect(host_, port_);
			if (context == nullptr || context->err != 0) {
				if (context != nullptr) {
					redisFree(context);
				}
				continue;
			}

			auto reply = (redisReply*)redisCommand(context, "AUTH %s", pwd_);
			if (reply->type == REDIS_REPLY_ERROR) {
				std::cout << "认证失败" << std::endl;
				//执行成功 释放redisCommand执行后返回的redisReply所占用的内存
				freeReplyObject(reply);
				continue;
			}

			//执行成功 释放redisCommand执行后返回的redisReply所占用的内存
			freeReplyObject(reply);
			std::cout << "认证成功" << std::endl;
			connections_.push(context);
		}
	}
}

/**
 * RedisMgr类：Redis管理器实现
 * 基于单例模式，封装Redis操作，提供各种Redis命令的便捷接口
 * 设计目的：统一管理Redis连接和操作，简化Redis的使用
 */
// =============================RedisMgr类的实现====================================//
/**
 * RedisMgr构造函数
 * 初始化Redis连接池
 */
RedisMgr::RedisMgr() {
	// 初始化连接池，这里需要根据实际情况设置参数
	con_pool_ = std::make_unique<RedisConPool>(10, "127.0.0.1", 6379, "");
}

/**
 * RedisMgr析构函数
 * 关闭Redis连接池
 */
RedisMgr::~RedisMgr() {
	Close();
}

/**
 * 获取Redis中的字符串值
 * @param key 键名
 * @param value 用于存储返回值的引用
 * @return 操作是否成功
 */
bool RedisMgr::Get(const std::string &key, std::string& value) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "GET %s", key.c_str());
	if (!reply) {
		con_pool_->returnConnection(context);
		return false;
	}

	// 在释放reply之前保存返回值类型
	bool success = (reply->type == REDIS_REPLY_STRING);
	if (success) {
		value = reply->str;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return success;
}

/**
 * 从列表头部弹出元素
 * @param key 键名
 * @param value 用于存储弹出元素的引用
 * @return 操作是否成功
 */
bool RedisMgr::LPop(const std::string &key, std::string& value) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "LPOP %s", key.c_str());
	if (!reply) {
		con_pool_->returnConnection(context);
		return false;
	}

	// 在释放reply之前保存返回值类型
	bool success = (reply->type == REDIS_REPLY_STRING);
	if (success) {
		value = reply->str;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return success;
}

/**
 * 从列表尾部弹出元素
 * @param key 键名
 * @param value 用于存储弹出元素的引用
 * @return 操作是否成功
 */
bool RedisMgr::RPop(const std::string& key, std::string& value) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "RPOP %s", key.c_str());
	if (!reply) {
		con_pool_->returnConnection(context);
		return false;
	}

	// 在释放reply之前保存返回值类型
	bool success = (reply->type == REDIS_REPLY_STRING);
	if (success) {
		value = reply->str;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return success;
}

/**
 * 设置Redis中的字符串值
 * @param key 键名
 * @param value 要设置的值
 * @return 操作是否成功
 */
bool RedisMgr::Set(const std::string &key, const std::string &value) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "SET %s %s", key.c_str(), value.c_str());
	if (!reply || reply->type != REDIS_REPLY_STATUS || strcmp(reply->str, "OK") != 0) {
		freeReplyObject(reply);
		con_pool_->returnConnection(context);
		return false;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return true;
}

/**
 * 在列表头部添加元素
 * @param key 键名
 * @param value 要添加的元素
 * @return 操作是否成功
 */
bool RedisMgr::LPush(const std::string &key, const std::string &value) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "LPUSH %s %s", key.c_str(), value.c_str());
	if (!reply || reply->type != REDIS_REPLY_INTEGER) {
		freeReplyObject(reply);
		con_pool_->returnConnection(context);
		return false;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return true;
}

/**
 * 在列表尾部添加元素
 * @param key 键名
 * @param value 要添加的元素
 * @return 操作是否成功
 */
bool RedisMgr::RPush(const std::string& key, const std::string& value) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "RPUSH %s %s", key.c_str(), value.c_str());
	if (!reply || reply->type != REDIS_REPLY_INTEGER) {
		freeReplyObject(reply);
		con_pool_->returnConnection(context);
		return false;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return true;
}

/**
 * 设置哈希表字段值
 * @param key 键名
 * @param hkey 哈希表字段名
 * @param value 要设置的值
 * @return 操作是否成功
 */
bool RedisMgr::HSet(const std::string &key, const std::string  &hkey, const std::string &value) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "HSET %s %s %s", key.c_str(), hkey.c_str(), value.c_str());
	if (!reply || reply->type != REDIS_REPLY_INTEGER) {
		freeReplyObject(reply);
		con_pool_->returnConnection(context);
		return false;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return true;
}

/**
 * 设置哈希表字段值（二进制安全版本）
 * @param key 键名
 * @param hkey 哈希表字段名
 * @param hvalue 要设置的二进制值
 * @param hvaluelen 二进制值长度
 * @return 操作是否成功
 */
bool RedisMgr::HSet(const char* key, const char* hkey, const char* hvalue, size_t hvaluelen) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	// 使用二进制安全的命令格式
	redisReply* reply = (redisReply*)redisCommand(context, "HSET %b %b %b", key, strlen(key), hkey, strlen(hkey), hvalue, hvaluelen);
	if (!reply || reply->type != REDIS_REPLY_INTEGER) {
		freeReplyObject(reply);
		con_pool_->returnConnection(context);
		return false;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return true;
}

/**
 * 获取哈希表字段值
 * @param key 键名
 * @param hkey 哈希表字段名
 * @return 字段值，如果不存在返回空字符串
 */
std::string RedisMgr::HGet(const std::string &key, const std::string &hkey) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return "";
	}

	redisReply* reply = (redisReply*)redisCommand(context, "HGET %s %s", key.c_str(), hkey.c_str());
	std::string result = "";
	if (reply && reply->type == REDIS_REPLY_STRING) {
		result = reply->str;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return result;
}

/**
 * 删除哈希表字段
 * @param key 键名
 * @param field 要删除的字段名
 * @return 操作是否成功
 */
bool RedisMgr::HDel(const std::string& key, const std::string& field) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "HDEL %s %s", key.c_str(), field.c_str());
	if (!reply || reply->type != REDIS_REPLY_INTEGER) {
		freeReplyObject(reply);
		con_pool_->returnConnection(context);
		return false;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return reply->integer > 0;
}

/**
 * 删除键
 * @param key 要删除的键名
 * @return 操作是否成功
 */
bool RedisMgr::Del(const std::string &key) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "DEL %s", key.c_str());
	if (!reply || reply->type != REDIS_REPLY_INTEGER) {
		freeReplyObject(reply);
		con_pool_->returnConnection(context);
		return false;
	}

	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return reply->integer > 0;
}

/**
 * 检查键是否存在
 * @param key 要检查的键名
 * @return 键是否存在
 */
bool RedisMgr::ExistsKey(const std::string &key) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return false;
	}

	redisReply* reply = (redisReply*)redisCommand(context, "EXISTS %s", key.c_str());
	if (!reply || reply->type != REDIS_REPLY_INTEGER) {
		freeReplyObject(reply);
		con_pool_->returnConnection(context);
		return false;
	}

	bool exists = reply->integer > 0;
	freeReplyObject(reply);
	con_pool_->returnConnection(context);
	return exists;
}

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

/**
 * 增加计数器值
 * @param server_name 计数器名称
 */
void RedisMgr::IncreaseCount(std::string server_name) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return;
	}

	redisCommand(context, "INCR %s", server_name.c_str());
	con_pool_->returnConnection(context);
}

/**
 * 减少计数器值
 * @param server_name 计数器名称
 */
void RedisMgr::DecreaseCount(std::string server_name) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return;
	}

	redisCommand(context, "DECR %s", server_name.c_str());
	con_pool_->returnConnection(context);
}

/**
 * 初始化计数器
 * @param server_name 计数器名称
 */
void RedisMgr::InitCount(std::string server_name) {
	redisContext* context = con_pool_->getConnection();
	if (!context) {
		return;
	}

	redisCommand(context, "SET %s 0", server_name.c_str());
	con_pool_->returnConnection(context);
}

/**
 * 删除计数器
 * @param server_name 计数器名称
 */
void RedisMgr::DelCount(std::string server_name) {
	Del(server_name);
}
```

- 连接池的意义显而易见, 就是减少建立销毁连接的开销.
- 管理类就是封装了大部分的Redis操作, 本质还是一个**超大型独立Map管理器**.
- 有关分布式锁的以后详说.
- 剩下要说的可能就是在连接器建立同时会开辟线程执行连接的健康检查, 会取出每个连接发PING, 如果失败就再建立一个健康的连接放进去.

### 测试代码

```cpp
#include <iostream>
#include <string>
#include <thread>
#include <chrono>
#include "RedisMgr.h"

/**
 * RedisMgr和RedisConPool功能测试程序
 * 测试内容包括：
 * 1. 基本连接和字符串操作（Get/Set）
 * 2. 列表操作（LPush/LPop/RPush/RPop）
 * 3. 哈希操作（HSet/HGet/HDel）
 * 4. 键操作（ExistsKey/Del）
 * 5. 计数器操作（InitCount/IncreaseCount/DecreaseCount）
 * 6. 分布式锁操作（acquireLock/releaseLock）
 */

// 测试基本的字符串操作
void testStringOperations() {
    std::cout << "===== 测试字符串操作 ======" << std::endl;
    
    // 设置键值对
    bool setResult = RedisMgr::Inst().Set("test_key", "Hello Redis!");
    std::cout << "Set操作结果: " << (setResult ? "成功" : "失败") << std::endl;
    
    // 获取键值
    std::string value;
    bool getResult = RedisMgr::Inst().Get("test_key", value);
    std::cout << "Get操作结果: " << (getResult ? "成功" : "失败") << std::endl;
    if (getResult) {
        std::cout << "获取的值: " << value << std::endl;
    }
    
    // 检查键是否存在
    bool existsResult = RedisMgr::Inst().ExistsKey("test_key");
    std::cout << "ExistsKey操作结果: " << (existsResult ? "存在" : "不存在") << std::endl;
    
    // 删除键
    bool delResult = RedisMgr::Inst().Del("test_key");
    std::cout << "Del操作结果: " << (delResult ? "成功" : "失败") << std::endl;
    
    // 再次检查键是否存在
    existsResult = RedisMgr::Inst().ExistsKey("test_key");
    std::cout << "删除后检查键是否存在: " << (existsResult ? "存在" : "不存在") << std::endl;
    std::cout << "" << std::endl;
}

// 测试列表操作
void testListOperations() {
    std::cout << "===== 测试列表操作 ======" << std::endl;
    std::string listKey = "test_list";
    
    // 清空列表（如果存在）
    RedisMgr::Inst().Del(listKey);
    
    // 从左侧插入元素
    bool lpResult1 = RedisMgr::Inst().LPush(listKey, "item1");
    bool lpResult2 = RedisMgr::Inst().LPush(listKey, "item2");
    std::cout << "LPush操作结果: " << (lpResult1 && lpResult2 ? "成功" : "失败") << std::endl;
    
    // 从右侧插入元素
    bool rpResult = RedisMgr::Inst().RPush(listKey, "item3");
    std::cout << "RPush操作结果: " << (rpResult ? "成功" : "失败") << std::endl;
    
    // 从左侧弹出元素
    std::string lpopValue;
    bool lpopResult = RedisMgr::Inst().LPop(listKey, lpopValue);
    std::cout << "LPop操作结果: " << (lpopResult ? "成功" : "失败") << std::endl;
    if (lpopResult) {
        std::cout << "LPop弹出的值: " << lpopValue << std::endl;
    }
    
    // 从右侧弹出元素
    std::string rpopValue;
    bool rpopResult = RedisMgr::Inst().RPop(listKey, rpopValue);
    std::cout << "RPop操作结果: " << (rpopResult ? "成功" : "失败") << std::endl;
    if (rpopResult) {
        std::cout << "RPop弹出的值: " << rpopValue << std::endl;
    }
    
    // 清理测试数据
    RedisMgr::Inst().Del(listKey);
    std::cout << "" << std::endl;
}

// 测试哈希操作
void testHashOperations() {
    std::cout << "===== 测试哈希操作 ======" << std::endl;
    std::string hashKey = "test_hash";
    
    // 清空哈希表（如果存在）
    RedisMgr::Inst().Del(hashKey);
    
    // 设置哈希字段
    bool hsetResult1 = RedisMgr::Inst().HSet(hashKey, "field1", "value1");
    bool hsetResult2 = RedisMgr::Inst().HSet(hashKey, "field2", "value2");
    std::cout << "HSet操作结果: " << (hsetResult1 && hsetResult2 ? "成功" : "失败") << std::endl;
    
    // 获取哈希字段值
    std::string hgetResult1 = RedisMgr::Inst().HGet(hashKey, "field1");
    std::string hgetResult2 = RedisMgr::Inst().HGet(hashKey, "field3"); // 不存在的字段
    std::cout << "HGet field1结果: " << hgetResult1 << std::endl;
    std::cout << "HGet field3结果: " << (hgetResult2.empty() ? "(空，字段不存在)" : hgetResult2) << std::endl;
    
    // 删除哈希字段
    bool hdelResult = RedisMgr::Inst().HDel(hashKey, "field1");
    std::cout << "HDel操作结果: " << (hdelResult ? "成功" : "失败") << std::endl;
    
    // 再次获取已删除的字段
    std::string hgetAfterDel = RedisMgr::Inst().HGet(hashKey, "field1");
    std::cout << "删除后HGet field1结果: " << (hgetAfterDel.empty() ? "(空，字段已被删除)" : hgetAfterDel) << std::endl;
    
    // 清理测试数据
    RedisMgr::Inst().Del(hashKey);
    std::cout << "" << std::endl;
}

// 测试计数器操作
void testCounterOperations() {
    std::cout << "===== 测试计数器操作 ======" << std::endl;
    std::string counterKey = "test_counter";
    
    // 初始化计数器
    RedisMgr::Inst().InitCount(counterKey);
    std::cout << "InitCount操作完成" << std::endl;
    
    // 增加计数
    for (int i = 0; i < 5; ++i) {
        RedisMgr::Inst().IncreaseCount(counterKey);
    }
    std::cout << "IncreaseCount操作完成（+5）" << std::endl;
    
    // 获取当前计数值
    std::string countValue;
    RedisMgr::Inst().Get(counterKey, countValue);
    std::cout << "当前计数值: " << countValue << std::endl;
    
    // 减少计数
    RedisMgr::Inst().DecreaseCount(counterKey);
    RedisMgr::Inst().DecreaseCount(counterKey);
    std::cout << "DecreaseCount操作完成（-2）" << std::endl;
    
    // 再次获取计数值
    RedisMgr::Inst().Get(counterKey, countValue);
    std::cout << "减少后计数值: " << countValue << std::endl;
    
    // 删除计数器
    RedisMgr::Inst().DelCount(counterKey);
    std::cout << "DelCount操作完成" << std::endl;
    
    // 检查计数器是否存在
    bool exists = RedisMgr::Inst().ExistsKey(counterKey);
    std::cout << "删除后计数器是否存在: " << (exists ? "存在" : "不存在") << std::endl;
    std::cout << "" << std::endl;
}

// 测试分布式锁操作
void testLockOperations() {
    std::cout << "===== 测试分布式锁操作 ======" << std::endl;
    std::string lockName = "test_lock";
    
    // 获取锁（超时时间5000ms，获取超时时间1000ms）
    std::string lockId = RedisMgr::Inst().acquireLock(lockName, 5000, 1000);
    std::cout << "acquireLock操作结果: " << (lockId.empty() ? "失败" : "成功") << std::endl;
    if (!lockId.empty()) {
        std::cout << "获取的锁ID: " << lockId << std::endl;
        
        // 模拟业务操作
        std::cout << "模拟业务操作..." << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(1));
        
        // 释放锁
        bool releaseResult = RedisMgr::Inst().releaseLock(lockName, lockId);
        std::cout << "releaseLock操作结果: " << (releaseResult ? "成功" : "失败") << std::endl;
    }
    
    // 测试错误的锁ID释放
    if (!lockId.empty()) {
        std::string wrongLockId = lockId + "_wrong";
        bool wrongReleaseResult = RedisMgr::Inst().releaseLock(lockName, wrongLockId);
        std::cout << "使用错误的锁ID释放结果: " << (wrongReleaseResult ? "成功（不安全）" : "失败（安全）") << std::endl;
    }
    std::cout << "" << std::endl;
}

// 测试多线程并发访问
void testMultiThreadAccess() {
    std::cout << "===== 测试多线程并发访问 ======" << std::endl;
    const int THREAD_COUNT = 5;
    const std::string threadKey = "thread_counter";
    
    // 初始化计数器
    RedisMgr::Inst().InitCount(threadKey);
    
    // 创建多个线程同时增加计数
    std::thread threads[THREAD_COUNT];
    for (int i = 0; i < THREAD_COUNT; ++i) {
        threads[i] = std::thread([threadKey, i]() {
            for (int j = 0; j < 10; ++j) {
                RedisMgr::Inst().IncreaseCount(threadKey);
                std::this_thread::sleep_for(std::chrono::milliseconds(10)); // 小延迟模拟实际操作
            }
            std::cout << "线程" << i << "完成操作" << std::endl;
        });
    }
    
    // 等待所有线程完成
    for (int i = 0; i < THREAD_COUNT; ++i) {
        threads[i].join();
    }
    
    // 检查最终计数值
    std::string finalCount;
    RedisMgr::Inst().Get(threadKey, finalCount);
    std::cout << "多线程操作后最终计数值: " << finalCount 
              << " (期望: " << THREAD_COUNT * 10 << ")" << std::endl;
    
    // 清理测试数据
    RedisMgr::Inst().DelCount(threadKey);
    std::cout << "" << std::endl;
}

int main() {
    std::cout << "===== RedisMgr 功能测试程序开始 ======" << std::endl;
    
    try {
        // 测试各种功能
        testStringOperations();
        testListOperations();
        testHashOperations();
        testCounterOperations();
        testLockOperations();
        testMultiThreadAccess();
        
        std::cout << "===== RedisMgr 功能测试程序完成 ======" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "测试过程中发生异常: " << e.what() << std::endl;
        std::cout << "===== RedisMgr 功能测试程序异常结束 ======" << std::endl;
    }
    
    // 关闭Redis连接池
    RedisMgr::Inst().Close();
    
    return 0;
}
```

样例输出 : 

```bash
➜  RedisLearn ./redistest
===== RedisMgr 功能测试程序开始 ======
===== 测试字符串操作 ======
密码为空，跳过认证
密码为空，跳过认证
密码为空，跳过认证
密码为空，跳过认证
密码为空，跳过认证
密码为空，跳过认证
密码为空，跳过认证
密码为空，跳过认证
密码为空，跳过认证
密码为空，跳过认证
Set操作结果: 成功
Get操作结果: 成功
获取的值: Hello Redis!
ExistsKey操作结果: 存在
Del操作结果: 成功
删除后检查键是否存在: 不存在

===== 测试列表操作 ======
LPush操作结果: 成功
RPush操作结果: 成功
LPop操作结果: 成功
LPop弹出的值: item2
RPop操作结果: 成功
RPop弹出的值: item3

===== 测试哈希操作 ======
HSet操作结果: 成功
HGet field1结果: value1
HGet field3结果: (空，字段不存在)
HDel操作结果: 成功
删除后HGet field1结果: (空，字段已被删除)

===== 测试计数器操作 ======
InitCount操作完成
IncreaseCount操作完成（+5）
当前计数值: 5
DecreaseCount操作完成（-2）
减少后计数值: 3
DelCount操作完成
删除后计数器是否存在: 不存在

===== 测试分布式锁操作 ======
acquireLock操作结果: 成功
获取的锁ID: lock_1804289383
模拟业务操作...
releaseLock操作结果: 成功
使用错误的锁ID释放结果: 失败（安全）

===== 测试多线程并发访问 ======
线程1完成操作
线程0完成操作
线程2完成操作
线程4完成操作
线程3完成操作
多线程操作后最终计数值: 50 (期望: 50)

===== RedisMgr 功能测试程序完成 ======
```



