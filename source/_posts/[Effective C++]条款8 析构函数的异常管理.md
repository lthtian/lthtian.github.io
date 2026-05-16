---
title: Effective C++ 条款8 析构函数的异常管理
date: 2024-11-30 22:06:44
tag: Effective C++
---

## 条款08 : 别让异常逃离析构函数

> 日常编程中，常见异常通常由以下原因引发：
>
> 1. **资源管理不当**（如内存泄漏, 文件操作, 连接或断开连接失败）。
> 2. **边界和合法性检查不足**（如数组越界、除以零）。
> 3. **并发编程问题**（如死锁、数据竞争）。
> 4. **类型不匹配或错误的操作**。

本条款主要讨论的是析构函数的异常管理, 为什么会不希望异常逃离析构函数, 因为**析构函数是一个必须执行且有可能失败的函数**, 因为内存泄漏, 文件操作, 连接或断开连接失败等资源管理行为的错误都是很难避免的, 而且由于**析构函数是递归式调用并且可能一次性销毁大量结构**, 同时产生大量异常的概率就提高了, 书中指出, **如果同时存在多个异常, 程序不是结束执行就是导致不明确行为**, 因此对于析构函数的异常管理在所难免.

---

书中举出了一个数据库连接的例子 : 

```cpp
class DBConnection {  // 数据库连接类
public:
  ...
  static DBConnection create(); // 这个函数返回创建出来的静态数据库连接.                                     
  ...                                      
  void close();   // 调用此函数关闭与数据库的连接, 这里有抛出异常的隐患         
};         
```

我们经常会设计一个资源管理类来控制数据库的连接 : 

```cpp
class DBConn {                          // 数据库连接管理类
public:
  ...
  ~DBConn()
  {
   	db.close();	  // 调用析构函数时断开数据库连接
  }
private:
  DBConnection db;   // RAII风格, 由DBConn管理DBConnection, 离开作用域自动触发DBConn的析构函数断开连接
};
```

于是我们就可以写出以下代码 : 

```cpp
{
    ...
	DBConn dbc(DBConnection::create()); // 直接建立DBConnection对象并交由DBConn对象dbc管理
    ... // 进行数据库的CURD, 离开作用域自动断开连接
}
```

---

有了上面例子的基础, 我们来思考一下如何避免异常抛出吧.

站在`DBConn析构函数`的角度, 书中给出了两个一般的方法 : 

1. 如果close()抛出异常就利用abort()结束程序.

   ```cpp 
   DBConn::~DBConn()
   {
   	try { db.close(); }
   	catch (...) {
           // 记录日志, 记录对close的调用失败
      		std::abort(); // 直接结束程序
   	}
   }
   ```

2. 直接吞下该异常.

   ```cpp
   DBConn::~DBConn()
   {
   	try { db.close(); }
   	catch (...) {
         	// 记录日志, 记录对close的调用失败
         	// 不做处理, 直接吞下
   	}
   }
   ```

这两个方法其实都是保底方法, 一个是草率结束进程, 一个是吞掉异常防止扩散, 但其实`DBConn析构函数`也就能做这么多了.

---

现在的问题是**没有办法对"导致close抛出异常"的情况做出反应**, 问题核心在`close()`函数被`DBConn析构函数`掌握, 只能其自己管理, 上一层无法干预. 那么由此我们可以将close()函数的使用权上交, 也就是让上一层用户有权决定处理`close()`报错的方式. 

较佳策略是**重新设计DBConn接口, 使客户有机会对可能出现的问题作出反应**. 

具体做法如下 : 

1. `DBConn`自己也提供一个close接口, 内部封装上`DBConnection`的`close()`.
2. `DBConn`自己对`DBConnection`的`close()`是否已经触发进行追踪管理, 如果到最后客户都没有自行close成功, 由`DBConn析构函数`自行完成close的任务.

我们来看书中给出的代码 : 

```cpp
class DBConn {
public:
  ...
  void close()                                     // 提供给上层用户的close函数
  {                                       
    db.close();
    closed = true;
  }

  ~DBConn()
  {
      // 如果到最后都没有触发close, 就会回到析构函数调用close的老路
      if (!closed) {
   		try {                                           
     		db.close();                           
   		}
   		catch (...) {                                    
     		// 记录日志, 记录对close的调用失败  
     		...                                   // 直接结束 或 吞下异常
   		}
      }
  }

private:
  DBConnection db;
  bool closed;					// 用布尔变量closed来对close()进行追踪管理
};
```

于是客户便可做出如下操作 : 

```cpp
void UsingDB() {
    DBConn dbConn;  // 创建 DBConn 对象
    
    ...
    
    // 客户自己在认为合适的地方调用close()结束连接, 并用try-catch语句尝试捕获异常
    try {
        dbConn.close();  // 这可能会抛出异常，如果关闭失败
    } catch (const std::exception& e) {
        // 客户端捕获从 close() 抛出的异常
        // ... 出现异常时的操作
    }

    return;
}
```

如果只考虑数据库断开连接的场景, 我们可行的具体操作可以是重试关闭或执行数据库回滚, 代码如下 : 

```cpp
void UsingDB() {
    DBConn dbConn;  // 创建 DBConn 对象
    
    ...
    
    bool success = false;
	int attempts = 0;
	while (!success && attempts < 3) {
    	try {
    	    dbConn.close();
    	    success = true;
    	} catch (...) {
    	    std::cerr << "正在尝试断开数据库连接, 次数 :  " << ++attempts << std::endl;
    	}
	}
	if (!success) {
	    std::cerr << "已经尝试三次断开数据库连接, 但都出现异常, 断开失败" << std::endl;
        std::cerr << "进行补偿操作, 回滚数据库" << std::endl;
        dbConn.rollback(); // 内部调用数据库的回滚函数
	}
    return;
}
```

我们再来捋一下流程, 先是客户需要考虑何时调用`close()`并写出应对异常的代码, 实际运行时如果没有异常就万事大吉, 有异常就触发客户的处理逻辑, 最后析构函数检查客户是否真的成功调用了`close()`, 如果还是没有调用, 就自己调用, 自己调用如果还出错, 就直接结束程序或吞掉异常.

至此我们将调用`close()`的责任从`DBConn析构函数`的手上移交到了使用`DBConn对象`的客户手上, 可以更好地避免异常逃离析构函数. 有人可能这样会加大客户的操作负担, 但是根据我们先前的分析, 只有客户才能有办法对"导致close抛出异常"的情况做出反应, 这样做是给客户提供一个根据实际情况回避异常的机会, 至于是否需要就看客户自己了.

---

### 请记住 : 

- 析构函数绝对不要吐出异常. 如果分析出一个析构函数有抛出异常的风险, 应当先把异常捕捉下来, 看是否结束程序或吞下异常.
- 给客户提供自己处理异常的机会, 让客户可以根据实际情况对异常做出反应.



by 天目中云