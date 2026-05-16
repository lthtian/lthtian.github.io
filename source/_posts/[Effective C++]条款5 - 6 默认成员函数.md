---
title: Effective C++ 条款5-6 默认成员函数
date: 2024-11-30 22:05:44
tags: [Effective C++]
---

## 条款05 了解C++默默编写并调用哪些函数

> 编译器会默认为class创建default构造函数, 析构函数, copy构造函数, 赋值操作符重载, 这算是我们C++语言基础学习中的重中之重, 这里就不再过多阐释.

书中提出一点 : 如果我们在实际使用中确实没有使用到某些默认成员函数, 编译器很大可能也不会自动创建对应的默认函数(例如copy构造函数, 赋值操作符重载).

---

书中还提出了三种编译器拒绝自动生成赋值操作符重载的情景 : 

1.  内含`reference(引用)`成员变量的类.
2. 内含`const`成员变量的类
3. 基类将赋值操作符重载声明为private的派生类

原因都是显而易见的, `reference`不可改指不同对象, `const`不可被更改, 派生类基于基类.

---

这里额外提一个小点, 就是默认生成的拷贝函数和辅助操作符重载默认都是浅拷贝, 就是只把类类对象的所有值进行复制, 如果有指针, 不会深入拷贝指针指向的内容, 只是单纯把指针本身拷贝.



## 条款6 : 若不想使用编译器自动生成的函数, 就该明确拒绝

>虽然大多情况下一个类对象应当有外置的构造/析构/拷贝接口, 但是总会有一些独一无二的东西应当是不可复制的, 就想天下没有第二个你一样, 如果为你自己设计一个类, 你肯定也不希望有一个自动生成的拷贝函数可以拷贝出无数个你吧.

因此, 若不想使用编译器自动生成的函数, 就该明确拒绝.

所以怎么拒绝呢?

1. 将该函数写入private中, 并且故意不实现它.
2. 将该函数后加上`= delete`.

假定我们要写一个房产买卖的类`HomeForSale`, 众所周知每一套房产都是独一无二的.

我们来看看怎么实现 :

```cpp
// 方法一
class HomeForSale
{
public:
    ...
private:
    // private成员函数
    HomeForSale(const HomeForSale&); 
    HomeForSale& operator=(const HomeForSale&); // 这样拷贝函数无法在外部使用就相当于禁用
private:
    // private成员变量
};
```

```cpp
// 方法二
class HomeForSale
{
public:
    HomeForSale(const HomeForSale&) = delete; // 直接声明禁用, 其实在哪声明都可以
    HomeForSale& operator=(const HomeForSale&) = delete;
private:
   	...
};
```

---

#### 设计一个专门为了阻止copying动作的base class

针对某些对象独一无二的情况, 我们可以设计一个专门为了阻止copying动作的base class, 让所有有此需求的类继承自该类, 就可以完全不用在专门处理阻止copying动作了.

```cpp
class Uncopyable {
protected:              // 允许构造和析构
  Uncopyable() {}                            
  ~Uncopyable() {}                           

private:
  Uncopyable(const Uncopyable&);   // 阻止copying
  Uncopyable& operator=(const Uncopyable&);
};

class HomeForSale: private Uncopyable {     
  ...    // 自此HomeForSale不需要再进行任何动作就可以实现阻止copying
};  
```

ed : 也许有人觉得这样子反而多写的, 但在日常情况下`Uncopyable`完全可以是我们提前备好的, ctrl + v当然方便很多. 再说到为什么是`private继承`, 在后面的条款中我们会明白, `private继承`意味着`has-a(有一个)`的关系, 就是说, 派生类有着基类的部分性质, 而不等于基类, 符合此处`HomeForSale`和`Uncopyable`的关系.

----

### 请记住:

- 编译器会默认为class创建`default构造函数`, `析构函数`, `copy构造函数`, `赋值操作符重载`.
- 拒绝编译器自动生成的函数, 可以将其写在将该函数写入private中, 并且故意不实现它, 或者直接加上`= delete`
- 可以写一些通用类如`Uncopyable`, 将功能和实现解耦.

