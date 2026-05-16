---
title: Effective C++ 条款34 接口继承和实现继承
date: 2024-12-17 17:13:00
tags: [Effective C++, 继承]
---

## 条款34 : 区分接口继承和实现继承

> 作为class的设计者, 我们有时希望派生类只继承成员函数的接口, 有时又希望同时继承接口和实现, 有时又希望能够重写所继承的实现,  因此我们的选择是多样的, 这里大有可以探讨的地方, 本条款将带我们区分不同的继承方法, 并对其做出建议

### 三种继承方式

首先让我们明晰各种继承方式的区别, 大体有三种继承方式 : 

- 接口继承 : **pure virtual函数**实现, 强制派生类**继承接口**.

  这种方式的通过强制继承接口确保必需功能的实现.

- 接口 + 缺省实现继承 : **virtual函数**实现, 派生类可以选择重写, **继承基类提供的接口和缺省实现**.

  这种方式可以灵活选择是继承缺省版本还是重写.

- 接口 + 强制实现继承 : **non-virtual函数**实现, 派生类**继承接口和唯一实现**.

  这种方式就是给整个继承体系增加了一个固定的工具函数, 该函数不可重写.

简单来说就是继承会继承接口, 但是否继承一份实现是看具体情况而定的.

---

### 纯虚函数也可以被定义

在前面的条款中应该有提过纯虚函数定义的问题, 这里再着重研究一下 : 

- **纯虚函数可以被定义**, 但调用它的唯一途径是调用时**明确指出其class名称**.

就像如下代码 : 

```cpp
class Shape
{
  public:  
    virtual void draw() const = 0;
  ...
};
class Rectangle : public Shape {...};

void Shape::draw()
{
    cout << "draw" << endl;
}

Shape* ps = new Rectangle;
ps->Shape::draw(); 				// 这样便可以调用纯虚函数
```

有了该定义, 便可以为上述的第二种继承方式提供**更平常更安全的缺省实现**.

---

### "使用纯虚函数并定义"来替换普通虚函数的使用

先来引入前提, **普通虚函数的重写并没有强制性, 并且在没有重写的情况下会自动继承缺省版本**, 这点在实际应用中被认为是有风险的. 因为自动使用某些功能总是有可能超出使用者的预期的, 有些时候往往可能只是我们忘记重写, 本身并不希望使用缺省, 但实际却还是调用到了缺省, 这很有可能**和我们想要实现的目的不一致, 但是在语法上是正确的, 我们不一定会意识到我们的错误**. 书中举出了一个飞机公司的例子, 一开始有两种型号的飞机A和B, 新加入一个型号的飞机C,  其默认的飞行方式和AB都不同, 如果我们忘记重写fly函数, 自动调用的缺省函数可能不会符合我们的预期 : 

```cpp
class Airport { ... };                     // represents airports

class Airplane {
public:
  virtual void fly(const Airport& destination);
  ...
};

void Airplane::fly(const Airport& destination)
{
   // fly的缺省行为
}

class ModelA: public Airplane { ... };

class ModelB: public Airplane { ... };

class ModelC: public Airplane {
  ...                                   // 忘记重写C的fly, 调用的缺省行为也可能不符合我们的预期
};
```

理解起来并没有那么麻烦, 就是使用`virtual`函数并没有强制性检查, 程序员的疏忽可能导致错误.

于是我们提出了一个新的方式替代`virtual`函数(第二种继承方案) : 

- **使用pure virtual函数并定义,  在想要使用缺省版本时显示指定缺省版本**.

代码如下 : 

```cpp
class Airplane {
public:
  virtual void fly(const Airport& destination) = 0; // 纯虚函数声明fly
  ...
};


void Airplane::fly(const Airport& destination)     
{                                                  
  // 用纯虚函数的定义当作缺省版本
}

class ModelA: public Airplane {
public:
  virtual void fly(const Airport& destination)
  { Airplane::fly(destination); }   // 在想要调用缺省版本时显示调用
  ...
};

class ModelB: public Airplane {
public:
  virtual void fly(const Airport& destination)
  { Airplane::fly(destination); }
  ...
};

class ModelC: public Airplane {
public:
  virtual void fly(const Airport& destination);
  ...
};

void ModelC::fly(const Airport& destination)
{
  	// 这里强制我们重写fly, 不想调用缺省版本就只能老实重写
}
```

这样我们可以用更安全地方式实现普通`virtual`函数的作用, **利用纯虚函数必须重写的机制来让我必须在缺省和重写中做出选择, 而没有"忘了"这种选项**.

---

### 继承方式的选择

具体选择还是依靠我们的需求来决定, 每种继承方式应用的场景我们都应明晰, 最后做出明智的判断, 最后作者还给出了几点提醒: 

- 除非你的`class`没有多态用途, 不要将所有函数声明为`non-virtual`.
- 除非你要写接口类, 不要将所有函数声明为`virtual`, 这是不想思考的体现.
- `virtual`函数是有成本的, 但是考虑到80-20法则(程序有80%的时间花费在20%的代码身上), 有80%的`virtual`函数不会对效率产生冲击, 这需要我们合理考量.

---

### 请记住 : 

- `pure virtual`函数只确保接口继承, 但是也可以进行定义.

- `virtual`函数在接口继承的同时可以选择是否继承实现, 可以用"使用纯虚函数并定义"的方式来替换以提高安全性.
- `non-virtual`函数在接口继承的同时继承一份强制性实现.



by 天目中云









