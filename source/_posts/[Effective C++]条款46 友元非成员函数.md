---
title: Effective C++ 条款46 友元非成员函数
date: 2025-1-14 19:06:00
tags: [Effective C++, 模板]
---

## 条款46 : 需要类型转换时请为模板定义友元非成员函数

> 本条款是条款24的延申讨论, 在引入模板的前提下, 如果我们想实现某些隐式类型转换的操作, 会需要比以往多一些额外的操作, 让我们通过本条款来理解.

### 前提引入

还记得条款24中的`Rational`吗, 这是一个有理数类, 内部包含分子和分母, 可以由int隐式转换而来, 当时条款24中讨论的核心是如何让`Rational`支持混合运算, 就像下面这样 : 

```cpp
Rational oneHalf(1, 2);
Rational result;          
result = oneHalf * 2;                 
result = 2 * oneHalf;   // 混合类型的乘法运算                          
```

没有了解的可以看我往期的博客, 总之讨论最后的结果就是`operator*重载`不可以是成员函数(因为有this指针干扰), 要使用非成员函数 : 

```cpp
class Rational {
  ... 
};

const Rational operator*(const Rational& lhs,     // non-member
                         const Rational& rhs) 
{
  return Rational(lhs.numerator() * rhs.numerator(),
                  lhs.denominator() * rhs.denominator());
}
```

那么如果我们想写一个泛型的`Rational`, 我们会很自然地写出下面的版本 : 

```cpp
template<typename T>
class Rational {
public:
  Rational(const T& numerator = 0,     
           const T& denominator = 1);  // 这个构造函数允许隐式类型转换

  const T numerator() const;           
  const T denominator() const;         
};

template<typename T>
const Rational<T> operator*(const Rational<T>& lhs,
                            const Rational<T>& rhs)
{ ... }
```

但很可惜, 当我们写出`result = oneHalf * 2;`这样的语句时根本无法通过编译, 其本质问题在于**template的实参推导出了问题**, 因为**template实参推导过程中不将隐式类型转换纳入考虑**, 2不能再像条款24中一样从int隐式转换为`Rationa`, 编译器只能试图从int中提取出T, 但这显然是不行的, 所以只能编译失败.

---

### 类内定义友元函数

书中指出了解决方法 : 

- **将这个非成员函数声明为友元.**

我们在这里声明友元不是为了访问`Rational`中的`non-public`成分, 仅仅只是为了**在类内部声明一个非成员函数**, 这样在编译时**这个非成员函数就会提前知道T是什么类型**, 而不需要再通过template实参推导出, 前面的问题就迎刃而解了, 下面是新一版代码 : 

```cpp
template<typename T>
class Rational {
public:
    // 声明友元模板函数
    typename<typename T>
	friend const Rational<T> operator*(const Rational<T>& lhs, const Rational<T>& rhs); 
    ...
};

template<typename T>                                
const Rational<T> operator*(const Rational<T>& lhs, const Rational<T>& rhs){ 
	return Rational<T>(lhs.numerator() * rhs.numerator(),
                  lhs.denominator() * rhs.denominator());
}
```

这个代码在部分情况下是可以运行的, 也就是参数类型都是`Rational<T>`的情况下, 形如 `result = oneHalf * 2;`这样的语句依旧无法通过编译, 因为**还是无法进行隐式转换**! 我们知道Rational的隐式转换是通过其构造函数实现的, 但是当前情况是`operator*重载`被定义在类外, 由于template的存在, `Rational`和该函数没有任何联系, 该函数自然不能知道`Rational`的构造函数, 因此无法进行隐式转换.

解决方法也很简单 : 

- **在类内定义友元函数**.

这种做法的本质是**通过友元把一个非成员函数搬到了类内, 在类内接触到构造函数使之可以隐式类型转换**. 代码如下 : 

```cpp
template<typename T>
class Rational {
public:
	friend const Rational<T> operator*(const Rational<T>& lhs, const Rational<T>& rhs)
	{
  		return Rational<T>(lhs.numerator() * rhs.numerator(),      
                  lhs.denominator() * rhs.denominator());  
	}    
    ...
};
```

这样代码就可以正常运行了, 混合类型的运算也可以应对!

另外, 书中提出 : 

- **在一个class template内, template名称可被用来作为"template和其参数"的简写**.

简单来说就是`Rational<T>`可以之间被替换为`Rational`, 仅限模板类内 : 

```cpp
template<typename T>
class Rational {
public:
	friend const Rational operator*(const Rational& lhs, const Rational& rhs)
	{
  		return Rational(lhs.numerator() * rhs.numerator(),      
                  lhs.denominator() * rhs.denominator());  
	}   
    ...
};
```

这便是最简单可以达到目的的版本了!

---

### 令friend函数调用辅助函数

在此基础上, 作者还提出了一点优化, 因为我们在条款30中说过, friend函数也会被在底层化为inline函数, 这在对于本例确实是优化, 因为这个函数只有一行, 但是假如这个函数很长就会带来代码膨胀的问题, 于是我们可以"**令friend函数调用辅助函数**"来避免这一问题.

在本例中确实没什么必要, 这里只是举个例子 : 

```cpp
template<typename T> class Rational;                                                                         
template<typename T>                                      
const Rational<T> doMultiply(const Rational<T>& lhs,      // 辅助函数, 代码可以非常长
                             const Rational<T>& rhs)     
{                                                         
  return Rational<T>(lhs.numerator() * rhs.numerator(),   
                     lhs.denominator() * rhs.denominator());
}

template<typename T>
class Rational {
public:
friend
  const Rational<T> operator*(const Rational<T>& lhs,
                              const Rational<T>& rhs)   
  { return doMultiply(lhs, rhs); }                      // 这里直接在友元函数中调用辅助函数
  ...
};
```

这里的代码非常巧妙, 我们可以知道辅助函数也是一个模板函数, 在这个函数里是无法进行隐式转换的, 但是实际效果依然可以隐式转换, 它支持各种混合运算! 因为所有的隐式转换都在`友元operator*重载`中进行, 在传给辅助函数时类型已经转换完毕!

---

### 逻辑梳理

我们可以再理一遍逻辑, 在引入模板的前提下 : 

- 为了支持混合运算, 运算符重载必须是非成员模板函数(成员模板函数有this干扰).
- 非成员模板函数实参推导过程中不将隐式类型转换纳入考虑.
- 因此要将其声明定义在类内, 本质是非成员函数, 不使用模板但达到模板类似的效果.
- 声明友元可以实现上述的需求.

---

### 请记住 : 

- 当我们希望一个模板类的运算可以支持"**所有参数之隐式类型转换**"时, 将那些函数定义为"**class template内部的friend函数**".



by 天目中云







