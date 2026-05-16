---
title: Effective C++ 条款42 typename
date: 2025-1-5 19:57:00
tags: [Effective C++]
---

## 条款42 : 了解typename的双重意义

> 本条款中我们将了解typename的两种使用场景, 对typename的内涵及使用加深认知.

### template声明式

在template的声明中, `template<class T>`和`template<typename T>`都是被允许的, 这两种写法并没有任何差别, C++对这两种写法一视同仁, 但是在真正使用中, 作者还是建议在传入自定义类时用class, 在传入任意类型(包括int等)时用typename, 这样会增加代码的可读性.

---

### 针对嵌套从属类型名称的应用

先让我们认识**嵌套从属类型名称**的定义 : 

- 从属 : 依赖于某个template参数.
- 嵌套 : 在class内呈嵌套状.
- 从属嵌套类型名称 : 在class内呈嵌套状且依赖于某个template参数的类型名称.

我们通过下面的代码来理解 : 

```cpp
template<typename C>                           
void print2nd(const C& container)              
{                                               
  if (container.size() >= 2) {
     C::const_iterator iter(container.begin());  // 这里的C::const_iterator便是从属嵌套类型名称
     ++iter;                                    
     int value = *iter;                        
     std::cout << value;                        
  }
}
```

这段代码是无法通过编译的, 我们只有在前头加上typename才可以通过编译, 这是因为编译器起初并不确定`C::const_iterator`是一个类型名称, 所以当你明确指明其是一个类型名称之后, 编译器就可以正常运作了.

```cpp
typename C::const_iterator iter(container.begin()); // 这样就可以了
```

- 所以为什么编译器无法确定这是一个类型名称呢? 

  其实是为了代码的严谨性, 我们举一个极端一点的例子 : 

  ```cpp
   C::const_iterator* x;
  ```

  当我们写下这样的代码时, 编译器并不知道`const_iterator`是C中的类型还是成员变量, 如果它是成员变量的话, 那么这其实是一个乘法运算式, *是乘号; 如果他是类型, 那么这其实就是一个定义式, *代表着指针. 这两种情况都完全合法, 因此需要程序员明确指出其究竟是什么才行.

---

### 两个例外

在一般情况下, typename必须作为嵌套从属类型名称的前缀词, 这一规则的例外是, typename不可出现在**继承语句和初始值列表**中, 这是C++中定死的, 没有必要去了解为什么, 记住就行.

```cpp
template<typename T>
class Derived: public Base<T>::Nested { // 继承语句不可加typename 
public:                                 
  explicit Derived(int x)
  : Base<T>::Nested(x)                  // 初始值列表不可加typename
  {                                    

    typename Base<T>::Nested temp;      // 这里可以加
    ...                               
  }                                    
};
```

---

### typename和typedef的组合使用

我们知道了typename会与嵌套从属类型名称绑定, 并且其实在一些情况下嵌套从属类型名称是很长的, 我们会习惯把typedef与typename组合, 将一个类型的书写长度缩短, 我们通过下面的例子了解 : 

```cpp
template<typename IterT>
void workWithIterator(IterT iter)
{
  typedef typename std::iterator_traits<IterT>::value_type value_type;
  value_type temp(*iter);
  ...
}
```

这是这个组合的经典用法, 在STL标准库中就有大量的使用.

这里通过typedef将`typename std::iterator_traits<IterT>::value_type`这个如此长的类型缩短到`value_type`, 不用想也一定会减少大量的代码量. 至于为什么会有这么长的类型, 这与`iterator_traits`的萃取功能有关, 简单来说就是`IterT`是一个迭代器类型,而`iterator_traits`可以根据`iterT`通过`value_type`萃取出迭代器所指向资源的真实类型T. 我们将在条款47中再作讨论这部分内容, 如果想深入学习的话也可以去`STL源码剖析`中研读.

---

### 请记住 : 

- typename作为template参数时, 和class意义完全相同.
- typename必须作为嵌套从属类型名称的前缀词, 除非在继承语句和初始值列表中.
- 将typedef和typename组合可以减小代码复杂度.



by 天目中云
