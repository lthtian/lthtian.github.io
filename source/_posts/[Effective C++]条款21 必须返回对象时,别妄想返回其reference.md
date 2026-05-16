---
title: Effective C++ 条款21 必须返回对象时, 别妄想返回其reference
date: 2024-12-1 20:09:12
tag: Effective C++
---

## 条款21 : 必须返回对象时, 别妄想返回其reference

>当程序员领悟了条款20所讲的pass-by-value的种种效率问题之后, 往往会变成十字军战士, 一心一意根除pass-by-value的存在, 然而这却会让他们犯下一些致命的错误, 通过本条款让我们来了解.

阅读完本文章, 我更倾向于把本条款解释为 :

- 必须返回**新**对象时, 别妄想返回其reference.

这样子会更便于理解.

书中给出了一个有理数类, 用于计算一个有乘积的有理数 : 

```cpp
class Rational {
public:
  Rational(int numerator = 0,int denominator = 1);
  ...
private:
  int n, d;  // 有理数的分子和分母

friend const Rational operator*(const Rational& lhs, const Rational& rhs);
};
```

这是我们最初的设想, `operator*`是传值返回的, 这不由得引发我们顾虑, 我们确实是希望其返回一个新的代表`lhs`和`rhs`乘积的`Rational`对象, 但是传值返回的拷贝构造成本也许会很高, 因此有不同的程序员想出了三种不同返回策略, 但无一例外都是错误的, 让我们看书中逐一反驳.

---

#### 返回一个pointer/reference指向一个 local stack 对象

```cpp
const Rational& operator*(const Rational& lhs,   // 错误的代码!
                          const Rational& rhs)
{
  	Rational result(lhs.n * rhs.n, lhs.d * rhs.d);
  	return result;
}
```

首先我们的目的是避免调用构造函数, 这样不仅没有避免, 而且`result`还是一个`local`对象, 出了作用域就会被销毁, 返回的引用是一个悬挂引用! 我们首先应当知道的, 就是不要让函数返回一个函数内局部变量的`reference`, 也就是返回引用的生命周期一定要大.

---

#### 返回一个reference指向一个heap-allocated对象

```cpp
const Rational& operator*(const Rational& lhs,   // 错误的代码!
                          const Rational& rhs)
{
  Rational *result = new Rational(lhs.n * rhs.n, lhs.d * rhs.d);
  return *result;
}
```

其一还是会进行构造, 其二这会带来严重的内存泄露, 首先你必须记得在外部要执行delete, 其次当你进行连乘时, 例如`a * b * c` , 你永远无法获得`b*c`是new出来的指针, 也就是说必然内存泄露.

---

#### 返回一个pointer/reference指向一个local static对象而有可能同时需要多个这样的对象

```cpp
const Rational& operator*(const Rational& lhs,    // 有风险的代码!
                          const Rational& rhs)    
{
  static Rational result; 
  result = ...;            
  return result;
}
```

这个原理上看来没有问题, 但是只要使用`static`对象就一定会伴随着多线程情况下的风险, 这样就显得有弊端了, 除非你可以保证这个代码不会在多线程情况下出问题或是通过锁保证了线程安全, 就像我们条款4中提到的初始化策略一样 : 

```cpp
TimeKeeper& tk() // 这里用tk函数替代内置型对象tk
{
    static TimeKeeper timekeeper;  // 当用户真正调用tk()时, 才会在函数内部生成一个局部静态变量(local static)
    return timekeeper;
}
```

我们会确保这个函数在多线程之前的单线程阶段就都调用过一次来实现初始化.

---

看过以上的三种情况后, 最后还是直接返回对象吧!

```cpp
inline const Rational operator*(const Rational& lhs, const Rational& rhs)
{
  	return Rational(lhs.n * rhs.n, lhs.d * rhs.d);
}
```

书中说即使要承担构造和析构的成本, 也还是推荐直接传值返回, 但是要知道Effective C++已经是十几年前的老书了, 现在伴随着C++11的引入, 带来了**移动语义**的新机制, 这种机制对传值返回带来了极大的优化, 简单来说就是不会有多余的构造和析构了, **编译器会直接在原本要析构的临时对象上直接构建要传出的新对象**, 也就是说传值返回的效率得到了极大的提升, 而这也与本条款的要求不谋而合, 可见Effective C++的条款还是禁得住时间历练的.

---

### 请记住 : 

- 绝对不要返回一个`pointer/reference`指向一个`local stack`对象, 返回一个`reference`指向一个`heap-allocated`对象, 返回一个`pointer/reference`指向一个`local static`对象而有可能同时需要多个这样的对象. 

- 请优先考虑传值返回吧, 在C++11引入移动语义后它如有神助!



by 天目中云