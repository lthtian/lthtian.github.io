---
title: Effective C++ 条款33 继承, 重载与作用域
date: 2024-12-16 15:40:00
tags: [Effective C++]
---

## 条款33 : 避免遮掩继承而来的名称

> 本条款并非和继承有关, 而是在讨论由继承引发的作用域问题, 其有可能破坏条款32所确定的法则, 因此我们在其之后介绍本条款。

我们知道在不同作用域下如果有相同名称的事物, 无论其功能或类型, 都是局部优先的. 继承的父子类也是类似, 不管是不是虚函数, 亦或是纯虚函数都完全没有关系, 都遵守相同名称局部优先的原则, 我们来看看一下的代码 :  

```cpp
class Base {
private:
  int x;
public:
  virtual void mf1() = 0;
  virtual void mf2();
  void mf3();
  ...
};

class Derived: public Base {
public:
  virtual void mf1() override;
  virtual void mf2() override;
  ...
};
```

分析代码我们可以发现, 派生类的函数都将覆盖基类相同名称的函数, 但没有什么原则上的问题.

但是如果加入重载, 事情就变得有些复杂了, 我们来看看接下来的代码 : 

```cpp
class Base {
private:
  int x;

public:
  virtual void mf1() = 0;
  virtual void mf1(int);  // mf1的重载

  virtual void mf2();

  void mf3();
  void mf3(double);  // mf3的重载
  ...
};

class Derived: public Base {
public:
  virtual void mf1();
  void mf3();
  ...
};
```

我们经过测试发现, 派生类调用`mf1`将只能调用到`Derived`中的`mf1()`, `mf3`也是如此, 而基类中的重载版本将无法再获取(除非用`Base::`). 以下我们将会介绍两种应用于不同情况下的解决办法.

---

### using声明式

让我们回顾条款32 : "**public意味is-a**" , 也就是说派生类可以干出所有`Base`可以干的事, 但是在这种情况下, 基类可以使用`mf1(int)`, 而派生类却不可, 这便是打破了这个规则. 因此我们可以再在派生类重写对应的重载, 亦或是直接接受父类的重载版本, 就像如下代码 : 

```cpp 
class Derived: public Base {
public:
  using Base::mf1;       
  using Base::mf3;      // 所有Base中的mf1和mf2在Derived中都可见
  virtual void mf1();
  void mf3();
  void mf4();
  ...
};
```

如此便可**避免遮掩继承而来的名称**.

---

### 转交函数

`public`继承可以通过`using`暴露所有基类的名称及其对应的重载版本, 但当然也会有`private`继承(具体细节在条款39中讲解)有类似的需求, 但`private`继承不一定需要继承所有基类的重载版本, 可能只是某个被遮掩的版本, 于是我们可以通过**转交函数**, 来缩小获取的范围, 让我们看以下代码 : 

```cpp
class Base {
public:
  virtual void mf1() = 0;
  virtual void mf1(int);
  ...                                   
};

class Derived: private Base {
public:
  virtual void mf1()
  { Base::mf1(); }                     // 转交给基类, 选取其中的无参数版本
  ...
};
```

这样`mf1`就只会有基类无参数版本的`mf1`对应的功能, 而使用不到带`int`的重载版本.

---

### 请记住 : 

- 派生类中的名称会遮掩基类中的名称.
- `public`继承必须接受所有基类中所有被遮掩的名称, 故用`using`声明式.
- `private`继承中可能有需要基类中被遮掩物的需求, 可以用转交函数声明调用基类函数.



by 天目中云