---
title: Effective C++ 条款43 模板基类的继承
date: 2025-1-7 11:37:00
tags: [Effective C++, 模板, 继承]
---

## 条款43 : 学习处理模板化基类内的名称

> 在本条款中我们将探讨继承与模板共同使用时的注意事项, 有些我们通过学习继承得来的直觉在这里可能不再适用, 当我们从Object Oriented C++ 跨进 Template C++, 继承就不像以前那样畅行无阻了.

### 发现问题

我们先引入一个例子, 假设我们要写一个程序, 他能够传送信息到若干不同公司去, 大部分公司传输的信息不需要加密, 少部分公司传输的信息需要加密. 那么在实际编写中就是写一个`MsgSender`模板类, 模板参数是公司类型, 针对需要加密信息的公司进行全特化. 我们通过代码来理解.

```cpp
// 两个公司类, 传递信息都不需要加密
class CompanyA {
public:
  ...
  void sendCleartext(const std::string& msg);
  void sendEncrypted(const std::string& msg);
  ...
};

class CompanyB {
public:
  ...
  void sendCleartext(const std::string& msg);
  void sendEncrypted(const std::string& msg);
  ...
};

class MsgInfo { ... };                  // 用来保存信息的类

template<typename Company> 
class MsgSender {
public:

  void sendClear(const MsgInfo& info)  // 发送不加密的信息
  {
    std::string msg;
    create msg from info;

    Company c;
    c.sendCleartext(msg);
  }
};
```

假设我们想要在`MsgSender`的前提下再加入日志志记的功能, 继承它可能是一个最高效的方式 : 

```cpp
template<typename Company>
class LoggingMsgSender: public MsgSender<Company> {
public:
  ...                                    
  void sendClearMsg(const MsgInfo& info)
  {
    // 信息发送前进行记录日志

    sendClear(info);           // 错误! 这里根本无法通过编译 
      
    // 信息发送后进行记录日志
  }
};
```

这种继承方式在`Object Oriented C++`领域中是没有任何问题的, 但是一旦加上了模板, 在事实上你会发现这个代码根本无法通过编译, 这就是我们本条款需要解决的问题.

----

### 问题核心

开门见山地指出问题核心 : **模板类存在特化这种操作**, 因此普通模板类有的函数, 特化版本却不一定有. 

我们假设还有一个公司Z, 它要求自己传送的信息必须加密, 我们看看代码 : 

```cpp
class CompanyZ {                             // 要求发送加密信息
public:                                    
  ...
  void sendEncrypted(const std::string& msg);
  ...
};

template<>                          
class MsgSender<CompanyZ> {                
public:                                  
  ...                                     
  void sendSecret(const MsgInfo& info)
  { ... }
};
```

我们发现, 当我们对MsgSender进行全特化后, 这个特化版本中并没有`sendClear`! 然而LoggingMsgSender中使用到了sendClear这个函数, 那么当LoggingMsgSender继承到的是这个特化版本时, 报错也就在所难免了.

---

### 深入探讨

这种现象出现的本质在于, 在派生类中使用到的基类的功能, 因为特化的存在, 在一些版本有这种功能, 另外一些版本就可能没有, 所以C++可以选择的方式解决方案有两种 : 

- 假定继承而来的基类**没有**这些功能, 除非程序员明确指出有, 会在编译期报错.
- 假定继承而来的基类**有**这些功能, 程序员自行承担继承错误基类的风险, 会在运行期报错.

在事实上C++选择了前者, 因为这样更加规范, 起码不会在运行中产生错误.

而其对应做出的行为就是 : **C++不进入templatized base classes(模板基类)观察**, 也就是C++不会去模板基类中找用到的成员, 除非程序员指定, 我们接下来将会介绍指定方法.

---

### 解决方法

其实就是在程序员通过自己的分析后, 明确告诉它有对应的功能, 总共有三种方式 : 

- 在基类函数前加上`this->`.

  ```cpp
  void sendClearMsg(const MsgInfo& info)
    {
      ...
      this->sendClear(info);                // 编译通过
      ...
    }
  ```

- 使用using声明式.

  ```cpp
  template<typename Company>
  class LoggingMsgSender: public MsgSender<Company> {
  public:
    using MsgSender<Company>::sendClear;   // 提前告诉编译器基类中存在sendClear
    void sendClearMsg(const MsgInfo& info)
    {
      ...
      sendClear(info);    // 编译通过               
      ...
    }
  };
  ```

- 明确指出函数位于基类内.

  ```cpp
  void sendClearMsg(const MsgInfo& info)
  {
      ...
      MsgSender<Company>::sendClear(info);      // 编译通过
      ...                                       
  }   
  ```

  这种方式并不推荐, 因为其会关闭虚函数的绑定行为, 如果sendClear是虚函数的话, 将会强制使用当前基类的版本.

---

### 请记住 : 

- 继承模板基类后, 想要使用继承而来的成员, 必须通过`this->`或`using声明式`指定.



by 天目中云