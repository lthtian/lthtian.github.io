---
title: Effective C++ 条款41 隐式接口和编译期多态
date: 2025-1-3 16:52:00
tags: [Effective C++, 模板]
---

## 条款41 : 了解隐式接口和编译期多态

> 从本条款开始, 我们将开始讨论模板与泛型编程, templates最初知识为了建立类型安全的泛用容器, 但在不断的发展中泛型编程的观念逐渐成型, 使得我们拥有了将写出的代码和其所处理的对象类型彼此独立的技术. 在本条款中我们将了解两个泛型编程中的核心概念--隐式接口和编译期多态.

在面向对象编程中, **显示接口和运行期多态**是我们主要研究的对象 : 

- 显示接口 : 函数的签名式(函数名称, 参数类型, 返回类型).
- 运行期多态 : 在运行期通过对象的动态类型进行动态绑定, 可以使相同的代码展现出多态的效用.

而在templates及泛型编程的世界, 底层逻辑和面向对象有根本的不同, 但也不是毫不相干, 在其中显示接口和运行期多态仍然存在, 但是重要性降低, **隐式接口和编译期多态**是其中的重中之重.

我们先来举一个例子, 帮助我们理解上面两个新概念 : 

```cpp
class Widget {
public:
  Widget();
  virtual ~Widget();

  virtual std::size_t size() const;
  virtual void normalize();
  void swap(Widget& other);
};

void doProcessing(Widget& w)
{
  if (w.size() > 10 && w != someNastyWidget) {
      Widget temp(w);
      temp.normalize();
      temp.swap(w);
  }
}
```

这是一个没有实际意义的`Widget`类, 只是为了促进我们的理解, 接下来我们将会写一个`doProcessing`的模板版本 : 

```cpp
template<typename T>
void doProcessing(T& w)
{
  if (w.size() > 10 && w != someNastyWidget) {
     T temp(w);
     temp.normalize();
     temp.swap(w);
  }
}
```

与原版的实现相似, 但是在实际编译中会有很大的差别, 我们比较直观的一个感受就是**类型T至少应该有operator>重载, operator!=重载, 拷贝构造函数, normalize成员函数, swap成员函数(由上至下)**, 不然编译肯定会报错, 这便是**隐式接口**最简单的一个理解.

- 隐式接口在定义上是模板函数中的部分**有效表达式**.

简单来说就是**类型T必须可以做到表达式中的行为**, **如果做不到那便是隐式接口不匹配**, 编译便无法通过, 在本例中的有效表达式便是`w.size() > 10 && w != someNastyWidget`, `T temp(w)`等. 

并且由于其是隐式接口, 也可以通过**隐式转换**来进行匹配, 这么说比较晦涩, 举个例子就是`w.size() > 10`这个表达式是应当返回一个bool类型的参数的, 但如果你的operator>重载返回的是int类型, 并且以1作为true, 0作为false, 那么在编译中完全可以将int隐式转换为bool类型, 进而继续接下来的判断.

- 编译期多态 : "以不同的template参数(T)具现化出来的function templates"会导致调用不同的函数.

用术语来讲, 编译期多态基于**模板具现化和函数重载解析**, 但其实很容易理解, 白话讲就是**在编译期根据不同的类型可以调用不同且对应的成员函数**, 其效果与运行时多态在运行期动态绑定的行为相似, 因此被称为编译期多态.

---

### 请记住 : 

- classes 和 templates 都支持接口和多态, templates不只有classes拥有的显示接口和运行时多态, 也有自己独有的隐式接口和编译期多态.
- 隐式接口基于有效表达式, 编译器多态基于模板具现化和函数重载解析.



by 天目中云







