---
title: Effective C++ 条款24 类型转换与non-member函数
date: 2024-12-3 16:09:11
tag: Effective C++
---

## 条款24: 若所有参数皆需类型转换, 请为此采用non-member函数

> 虽然令classes支持隐式类型转换是一个坏主意, 但常常有许多意外出现, 有些类型之间的关联实在太强, 我们经常想把它们放在一起用,       例如支持int类型隐式转换为Rational(有理数), 当对便利性的需求非常强烈之后, 也许支持隐式类型转换也未必是坏事.

书中给出了一个`Rational`类, 它可以由`int`类型隐式转化而来 : 

```cpp
class Rational {
public:
  Rational(int numerator = 0,        // 这里没有加explicit
           int denominator = 1);     // 传入int类型可隐式转换为分母是1的Rational类型

  int numerator() const;             // 获取分子
  int denominator() const;           // 获取分母  // 见条款22

private:
  ...
};
```

我们一定希望`Rational`类型可以和int类型相乘, 所以我们来写一个成员函数 : 

```cpp
class Rational {
public:
	...
	const Rational operator*(const Rational& rhs) const
	{
	    return Rational(this->numerator() * rhs.numerator(),
                       this->denominator() * rhs.denominator());
	}
    ...
};
```

有了以上的函数, 我们看看能通过哪些代码 : 

```cpp
Rational oneEighth(1, 8);
Rational oneHalf(1, 2);
Rational result = oneHalf * oneEighth;            // fine
result = result * oneEighth;                      // fine

result = oneHalf * 2;                         	  // fine
result = 2 * oneHalf;                             // error!
```

我们发现最后一个例子无法通过编译, 原因很容易理解, 让我们重写一下上述两个式子 : 

```cpp
result = oneHalf.operator*(2);                    // fine
result = 2.operator*(oneHalf);                    // 2还没隐式转换, 怎么可能使用operator*
```

因此我们有了这样的推论 : **只有当参数被列于参数列内, 这个参数才是隐式转换的合格参与者**.

至于"被调用之成员函数所隶属的哪个对象", 即**this对象**, 绝不是隐式转换的合格参与者.

为了支持这样的混合算术运算, 可行之道拨云见日 : 

**让operator*成为一个non-member成员函数**, 即可让编译器在每一个实参上执行隐式类型转换. 

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
//-----------------------//
Rational oneFourth(1, 4);
Rational result;
result = oneFourth * 2;                           // fine
result = 2 * oneFourth;                           // fine
```

问题解决, 皆大欢喜. 有了以上的经验, 我们在看别人代码时, 就不会奇怪于为什么总是要把双目运算符的重载都放在类外作为`non-member`定义了, 说明他们也深谙上述的道理, 也许有时并没有隐式转换的需求大家还是这样写, 可能是因为习惯了.

---

有人可能认为`operator*`可以作为友元与`Rational`类加强联系, 但完全没必要, 除非它要调用`Rational`的`private`数据, 不然这样只会降低其封装性(见条款23), 我们**不应当只因函数不该成为member, 就自动让它成为friend**.

---

### 请记住 : 

- 如果你需要为某个函数的所有参数进行类型转换, 那么这个函数必须是个`non-member`. 



by 天目中云