---
title: Effective C++ 条款9 绝不在构造和析构函数过程中调用
date: 2024-11-30 22:06:45
tag: Effective C++
---

## 条款09 : 绝不在构造和析构函数过程中调用virtual函数

开门见山阐释本条款的重点 : **你不该在构造函数和析构函数中调用virtual函数**.

书中给出了一个例子 : 假如我们要塑膜股市交易订单模型, 订单可以分成买入, 卖出等不同类型的订单, 当我们产生不同类型的订单, 也就是构造不同类型订单对象时, 我们也许会有记录订单日志的需求, 并我们希望订单根据不同的订单类型产生不同的订单日志.

于是我们可以抽象出以上需求的类构建过程, 一个订单基类, 派生出不同的订单派生类(如买入类, 卖出类), 基类的构造函数调用一个虚函数`logTransaction()`, 派生类重写出不同的`logTransaction()`, 就可以实现我们以上的需求.

代码如下:

```cpp
class Transaction {                               // 基类
public:                                           
  	Transaction()
  	{                                                 
  		...
  		logTransaction();                        // 订单构建时依据订单动态类型构建对应日志       
	}     

  	virtual void logTransaction() const = 0;     // 要求派生类重写
  	...
};                       
                                            
class BuyTransaction: public Transaction {       // 买入类
public:
  virtual void logTransaction() const;           // 提供重写版本日志
  ...
};
class SellTransaction: public Transaction {      // 卖出类
public:
    virtual void logTransaction() const;          
  	...
};
```

这段代码看似很完美, 但是真正运行起来是无法实现的!

当我们创建一个`BuyTransaction`类对象`b`时, 并不会调用`BuyTransaction`重写的`logTransaction()`, 而是会调用基类`Transaction`的`logTransaction()`, 然而我们基类的`logTransaction()`设置为纯虚函数甚至都没有写, 就更别谈运行了. 

为什么? 书中告诉我们, **在base class构造期间, virtual函数不是virtual函数**, 更细致的说就是**base class构造期间virtual函数绝不会下降到derived class阶层**. 原因很直观, **base class 构造函数执行期间derived class的成员变量一定还未初始化**, 如果此刻就可以通过virtual下降到派生类, 我们怎么确保这个虚函数不会调用派生类的成员变量呢? 太危险了, 所以C++不会让你走这条路.

而且不止是不能在构造析构函数内调用虚函数, 当然也不能调用包含了虚函数的普通函数, 这是显而易见的, 这就又回到了我们开头说的那句话 : **绝不在构造和析构函数过程中调用virtual函数**, 只要还在过程中, 就不要调用.

---

那么我们最开始的需求还有其他实现的方式吗?

书中提出一种解决办法 : 将`logTransaction()`改为普通函数, 要求派生类构造函数传递必要的日志信息给基类的构造函数, 基类的构造函数再把接收到的日志信息传入`logTransaction()`, 这样就可以了!

我们可以宏观地理解一下, 有助于我们的思维进步. 其实派生类的构造函数是一个`自底向上`的过程, 一直递归调用到最顶层的基类, 当调用到最顶层后, 我们不好奢求基类再自顶向下调用派生类的重写函数, 不如在一开始自底向上时就把必要的信息传递至基类构造函数, 这样想就非常通顺了.

代码如下 : 

```cpp 
class Transaction {
public:
  	explicit Transaction(const std::string& logInfo)  // 接收下层的日志信息
  	{
  		...
  		logTransaction(logInfo);
	}

  	void logTransaction(const std::string& logInfo) const;   // 此时是普通函数
  	...
};

class BuyTransaction: public Transaction {
public:
	BuyTransaction(const std::string& parameters)
		: Transaction(createLogString(parameters))             // 将log信息传递给上层
  	{ ... }                                                 
   	...                                                  

private:
  // 这里利用一个辅助函数创建一个值传给base class构造函数往往比较方便美观可读
  static std::string createLogString(const std::string& parameterss);
};
```

---

### 请记住 :

- 绝不在构造和析构函数过程中调用`virtual`函数.
- 对象在`derived class构造函数`开始执行前不会成为一个`derived class对象`.



by 天目中云