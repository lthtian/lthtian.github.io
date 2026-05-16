---
title: Effective C++ 条款26 尽可能延后变量定义式的出现时间
date: 2024-12-5 16:17:23
tag: Effective C++
---

## 条款26 : 尽可能延后变量定义式的出现时间

只要你定义了一个变量, 并且其类型带有构造函数或析构函数, 那么当程序控制流到达变量定义式时, 你便得承担构造成本; 当变量离开作用域时, 你便得承担析构成本. 本条款希望我们避免**定义变量但最终并未使用**的情况, 不要白白浪费构造和析构的成本.

先来看看什么情况下会出现定义变量但最终并未使用 : 

这是一个密码加密的函数, 由于密码本身不能修改, 所以要定义并返回一个`encryted`来表示**加密后的密码**.

```cpp
string encryptPassword(const string& password)
{
  string encrypted;
  if (password.length() < MinimumPasswordLength) {
      throw logic_error("Password is too short");
  }
  ...                        
  return encrypted;
}
```

我们可以看到, 当密码的长度小于最小值时, 我们的函数无法提供对应的服务, 所以要抛出一个`logic_error`异常, 然后就离开该函数了, 也就是说先前构造的`encrypted`确实没有发挥任何作用.

没错, `encrypted`并非完全未被使用, 但是仍然会有未被使用的情况存在, 为了不无端付出构造和析构的成本, 我们应将其**定义式往后移**, 代码如下 : 

```cpp
string encryptPassword(const string& password)
{
  if (password.length() < MinimumPasswordLength) {
     throw logic_error("Password is too short");
  }
  string encrypted;
  ...                     
  return encrypted;
}
```

我们假设还有一个`encrypt`函数, 里面通过复杂的算法将`password`加密, 那么我们应当把`password`赋值给`encrypted`, 再把`encrypted`传进去, 进而使函数修改`encrypted`实现加密 : 

```cpp
string encryptPassword(const string& password)
{
  ...
  string encrypted;         
  encrypted = password;  // 赋值             

  encrypt(encrypted);	// 传入
  return encrypted;
}
```

到这里就又有可以提升效率的地方了, 这里的行为是`defalut`构造 + 赋值, 但是我们在条款4就讨论过 : "**通过default构造函数构造出一个对象然后对它赋值比直接在构造是指定初值效率差**", 就和`vector`中`emplace_back`比`push_back`效率高一个道理, 于是我们可以有以下的改良操作 : 

```cpp
string encryptPassword(const string& password)
{
  ...                                   
  string encrypted(password);     
  encrypt(encrypted);
  return encrypted;
}
```

由此我们再回顾本条款的内容 : **尽可能延后变量定义式的出现时间**.

我们可以理解到"尽可能延后"的真正意义, 在于**我们不应当只延后变量的定义, 直到非得使用该变量的前一刻为止, 甚至应该尝试延后这份定义直到能够给它初值实参为止**. 这样不只能**避免构造非必要对象**, 还能**避免无意义的defalut构造行为**. 更深一层说, 以"具明显意义值初值"将变量初始化, 还可以附带说明变量的目的, **提高代码的可读性**.

---

还有一个小问题, 循环怎么办? 我们在循环外定义只需要定义一次, 在循环内需要定义n次, 延后不是代价更大吗?

```cpp
Widget w;
for (int i = 0; i < n; ++i){         for (int i = 0; i < n; ++i) {
  	w = 取决于某个i的值;       			Widget w(取决于某个i的值);
  	...                                  ...
}                                    }
```

我们分析两种写法的成本 : 

- 循环外 : 1构造 + 1析构 + n赋值
- 循环内 : n构造 + n析构

确实就实际而言, 循环外的做法大体比较高效, 但这建立在: 

1. 你知道赋值比"构造 + 析构"的成本低的情况下.
2. 你的这部分代码对效率高度敏感.

否则你应该使用循环内的做法.

---

### 请记住 : 

- 尽可能延后变量定义式的出现. 这样有助于**避免浪费, 提升效率, 提高代码可读性**.



by 天目中云