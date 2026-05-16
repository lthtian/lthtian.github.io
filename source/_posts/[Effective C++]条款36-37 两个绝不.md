---
title: Effective C++ 条款36-37 两个绝不
date: 2024-12-20
tags: [Effective C++, 继承]
---

## 条款36 : 绝不重新定义继承而来的non-virtual函数 

本条款很容易理解, 援引以前的条款就可以说明为什么 : 

- 条款34中就提到过 : non-virtual函数意味着**接口 + 强制性实现继承**, 它不应当被改变. 
- 重新定义继承而来的non-virtual函数会触发条款33中所说的**遮掩**机制.

- 触发遮掩机制其实是对条款32中"**public意味着is-a**"这个定理的破坏.

如果你这么做了, 还可能会出现以下奇怪的效果 : 

```cpp
class B {
public:
  	void mf();
  	...
};
class D: public B {  // D派生自B
public:
    void mf();   // 这个定义遮掩了B中的mf()
};  

//--------------------------------------------//

D x;                              // 创建一个D对象

B *pB = &x;                       
pB->mf();                         // 调用B::mf()

D *pD = &x;                       
pD->mf();  						  // 调用D::mf()
```

我们可以看到通过同一个对象D调用的`mf()`居然效果不同, 这也很容易理解, 毕竟non-virtual并没动态绑定, 只是依据当前对象的静态类型来调用的.

---

### 请记住 : 

- 任何情况下都不应重新定义一个继承来的non-virtual函数.

---

## 条款37 : 绝不重新定义继承而来的缺省参数值

> 先缩小本条款的范围, 通过条款36我们首先应该知道不应该修改继承来的non-virtual函数, 所以本条款的讨论范围将局限在"继承一个带有缺省参数的virtual函数".

首先明确本条款的核心知识 : 

- **virtual函数本身是动态绑定的, 但是缺省参数值是静态绑定的.**

简单理解就是virtual函数会根据对象的当前类型进行动态绑定, 而缺省值无法改变, 只和一开始定义的静态类型相关.

我们来看代码来理解 :

```cpp
class Shape {
public:
  enum ShapeColor { Red, Green, Blue }; 
  virtual void draw(ShapeColor color = Red) const = 0; // Shape默认缺省值为Red
  ...
};

class Rectangle: public Shape {
public:
  // 这是一个糟糕的写法!
  virtual void draw(ShapeColor color = Green) const;  // Shape默认缺省值为Green, 但是有用吗?
  ...
};

class Circle: public Shape {
public:
  virtual void draw(ShapeColor color) const;  // 无缺省值
  ...
};
```

这里设计了一个Shape基类, 派生出三角和圆, 我们来看调用时会发生什么 :

```cpp
// 以下的静态类型都是基类
Shape* ps;                       
Shape* pc = new Circle;         
Shape* pr = new Rectangle;      

pc->draw();
pr->draw();
```

这样子调用看上去没有任何问题, 实际上也确实依靠动态绑定调用到了派生类对应的draw(), 但根据测试`pc->draw()`中color缺省值是Red而非Green, 这便是因为我们上述的理由, 缺省值看的是静态类型, 也就是Shape.

- 为什么C++会设计成会这样?

  其实是因为动态绑定缺省值的花销实在过大, C++为了效率做了这般取舍.

---

### 由此引发出的另一个问题

- **当静态类型是派生类时, 将无法获取基类的缺省值!** 

```cpp
// 这样可以使用基类的缺省值
Shape* pc = new Circle;            
pc->draw();

// 这样不行!
Circle* cc = new Circle;
cc.draw();    // 错误, 自己没有缺省值, 并且也调不到基类的缺省值
```

于是这样的机制似乎在逼迫我们要把所有含缺省值的virtual函数都手动填上和基类一样的缺省值, 就像下面的代码一样 : 

```cpp
class Shape {
public:
  enum ShapeColor { Red, Green, Blue }; 
  virtual void draw(ShapeColor color = Red) const = 0;
  ...
};

class Rectangle: public Shape {
public:

  virtual void draw(ShapeColor color = Red) const;  // 都加上和基类相同的缺省值
  ...
};

class Circle: public Shape {
public:
  virtual void draw(ShapeColor color = Red) const;  // 都加上和基类相同的缺省值
  ...
};
```

只有这样你才可以确保在任何使用场景下你的缺省值都可以正常生效.

但是这样值得吗? 显然是不值得的, 这里包含了**代码重复和代码相依性**两大弊病, 只要你想修改基类中的缺省值, 那么其他所有的派生类就都要修改, 这是我们非常不希望看到的, 还好我们有一个现成的解决方法.

---

### 藉由NVI手法解决上述问题

没错, 就是我们条款35详细介绍的NVI手法(没看过的可以看我往期博客的对应部分, 这将很影响下文的理解), 我们**让非虚函数接口有缺省值, 如果有缺省情况, 把这个缺省值传入具体实现的虚函数**就可以了! 代码如下 : 

```cpp
class Shape {
public:
  enum ShapeColor { Red, Green, Blue };

  void draw(ShapeColor color = Red) const           // 非虚函数接口(包含缺省值), 见条款35
  {
    doDraw(color);                                  // 具体实现的虚函数接受color
  }
  ...
private:
  virtual void doDraw(ShapeColor color) const = 0;  // 见条款35
};                                                  

class Circle: public Shape {
public:
  ...
private:
  virtual void doDraw(ShapeColor color) const;     // 这样就不必再加缺省值了!  
  ...                                                
};

//-----------------------//

Circle* cc = new Circle;
cc.draw();                 // 这样的调用也被允许了!
```

---

### 请记住 :

- 绝对不要重新定义一个继承而来的缺省参数值, 因为它是静态绑定的.
- 再想让virtual函数携带缺省值是, 不妨使用NVI手法, **让非虚接口替虚函数携带缺省值**.



by 天目中云







