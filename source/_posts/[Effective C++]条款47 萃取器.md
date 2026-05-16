---
title: Effective C++ 条款47 萃取器
date: 2025-1-16 17:19:00
tags: [Effective C++, 模板, 萃取]
---

## 条款47 : 请使用traits classes表现类型信息

> traits classes(萃取器类), 如你所见萃取器其实是一个模板类, 在C++中萃取器是一个神奇且有趣的存在, 它被广泛引用于标准库STL的编写中, 我们将在本条款中了解萃取器的功能及实现, 初步踏入模板元编程的世界.

### 模板元编程的初步认知

很多人在第一次听到"模板元编程"时一定觉得非常高大上, 但是实际上我们可以简单认知其为**针对模板类型在编译期执行的代码**, 目前我们写的代码大都是在运行期执行的, 但是由于模板的引入, 我们便可以针对模板类型(T)进行各种操作, 譬如根据不同的类型选择不同的执行代码和计算逻辑, 这些行为都会在编译期执行. 而我们本条款要学习的萃取器便属于模板元编程的一部分.

---

### 在 *STL源码剖析* 中学习

本条款其实只是对萃取器的简介, 让你认识萃取器这个存在, 想要真正掌握它, 还是建议阅读*STL源码剖析*, 其中第二章用了整整一章的内容来详述萃取器相关的内容, 我也是因为提前阅读过*STL源码剖析*, 才对本条款的阅读没有什么障碍的.

---

### 萃取器

顾名思义, 萃取器是用来萃取的, 其作用是**从模板类型中萃取出类型信息**, 另外萃取器是一种**技术**, 是一个可以实现萃取功能的类, 并且同时也需要被萃取类的帮助才行. 

我们先来介绍书中的典例 - 迭代器 :

迭代器大家都熟知, 并且迭代器有五种迭代器类别 : **只读迭代器, 只写迭代器, 单向读写迭代器, 双向读写迭代器, 随机读写迭代器**, 这五种迭代器类型有明确的继承关系, 代码如下 : 

```cpp
struct input_iterator_tag {};
struct output_iterator_tag {};
struct forward_iterator_tag: public input_iterator_tag {};
struct bidirectional_iterator_tag: public forward_iterator_tag {};
struct random_access_iterator_tag: public bidirectional_iterator_tag {};
```

另外STL库中还有许多模板函数, advance函数便是其中之一, 其声明如下 : 

```cpp
template<typename IterT, typename DistT>  
void advance(IterT& iter, DistT d);
```

其接收一个迭代器类型参数和一个距离类型参数, 意在实现`iter += d`这种操作, 也就是让iter按d发生变化, 这是迭代器的基本功能. 但是不同的迭代器所能实现的操作有所差别 : 

- 只读只写迭代器和单向读写迭代器只能正向且一次一步读写(++). 
- 双向读写迭代器可以双向一次一步读写(++, --).
- 随机读写迭代器可以跳跃读写(+= x, -= x).

这就导致advance希望根据迭代器类别去实现不同的操作, 就像下面一样 : 

```cpp
template<typename IterT, typename DistT>
void advance(IterT& iter, DistT d)
{
  	if(判断iter是否是随机读写迭代器) {
        iter += d;
    } 
    else if(判断iter是否是双向读写迭代器) {
        if (d >= 0) {
            while (d--) ++iter;
        } else {
            while (d++) --iter;
        }
    } 
    else if(判断iter是否是迭代器) {
        if (d < 0) {  // 反向是违规的
            throw std::out_of_range("Negative distance not supported for input iterators.");
        }
        while (d--) ++iter;
    } 
}
```

当然这只是我们的幻想, 直接判断迭代器类型这种技术在C++17才出现, 我们在后面也会讲解, 但是我们先看看前人是如何解决这个问题的.

解决方法自然就是用**萃取器**了, 我们先要知道萃取器要做到什么, 在本例中就是**从迭代器类型IterT中得到迭代器的类别**, 这里不要混淆了, 迭代器类型是专属于某些大类的迭代器(如vector, deque的iterator), 迭代器类别就是我们上面说的五种类别, 也就是我们要从迭代器类型中提取出的东西. 

重点在于如何提取出来, 实际过程非常复杂, 但又缺一不可, 我在这里经过总结将其分为两个部分 : 准备阶段和使用阶段.

----

### 准备阶段

在这一阶段, 我们需要做的工作有 : 

- **为需要提取出相关信息的迭代器配置对应的标签**.

  ```cpp
  template < ... >                  
  class deque {
  public:
    class iterator {
    public:
      typedef random_access_iterator_tag iterator_category;  // 这里便配置了需要的标签
      ...
    }:
  };
  ```

  本例中我们对deque(双端队列)的迭代器进行操作, 使用typedef对其`iterator_category(迭代器类别)`进行了声明, 这其实就是在说明deque的迭代器是可以随机读写的.

  ```cpp
  template < ... >
  class list {
  public:
    class iterator {
    public:
      typedef bidirectional_iterator_tag iterator_category;
      ...
    }:
    ...
  };
  ```

  在list中也是如此, list不支持随机读写, 只能双向读写, 因此它声明的是`bidirectional_iterator_tag`.

- **准备一个萃取器类, 使其可以提取出迭代器中的对应标签.**

  ```cpp
  template<typename IterT>
  struct iterator_traits {
    typedef typename IterT::iterator_category iterator_category;
    ...
  };
  ```

  提取的原理其实很简单, 这里需要萃取器类和被萃取类有一个**共识**, **代表迭代器类别的标签名为`iterator_category`**, 这样只要向萃取器类中传入一个迭代器类型, 就可以通过`typedef typename IterT::iterator_category iterator_category;`这段代码将原本迭代器类型中的`iterator_category`, 赋给自己的`iterator_category`, 这样就实现了迭代器类别的提取.

  当然我们可以发现这种萃取器只对typedef了`iterator_category`的自定义类型生效, 但在实际使用中普通指针也是类似迭代器的形式, 例如普通数组`int* arr`, 这里int*就可以当作是一种指针迭代器类, 它也可以做到随机读写访问. 因此我们可以使用模板的偏特化, 使其兼容指针迭代器 : 

  ```cpp
  template<typename IterT>  
  struct iterator_traits<IterT*>   // 模板偏特化
  {
    typedef random_access_iterator_tag iterator_category; // 直接设置普通指针的迭代器类型为随机读写迭代器
    ...
  };
  ```

---

### 使用阶段

在准备阶段做出了萃取器后, 我们将要通过在advance函数中使用萃取器来达到我们原先希望的效果, 使用方法如下 : 

- 建立一个控制函数, 依旧是接受迭代器和距离.
- 建立一组特化函数, 除了接收迭代器, 距离, 还有迭代器类型.
- 在控制函数中利用萃取器萃取出迭代器类别, 将迭代器类别传入特化函数.
- 依靠**重载解析**机制, 将调用对应迭代器类型的特化函数.

光看比较难以理解, 我们通过代码来分析 : 

```cpp
//-------------特化函数-------------//
template<typename IterT, typename DistT>              
void doAdvance(IterT& iter, DistT d,                  
               std::random_access_iterator_tag)    // 针对:random_access_iterator的特化版本
{
  	iter += d;									   // 直接+=
}

template<typename IterT, typename DistT>              
void doAdvance(IterT& iter, DistT d,                  
               std::bidirectional_iterator_tag)    // 针对bidirectional_iterator的特化版本
{
  	if (d >= 0) { while (d--) ++iter; }     
  	else { while (d++) --iter;}				       // 可逐次++/--
}

template<typename IterT, typename DistT>              
void doAdvance(IterT& iter, DistT d,                  
               std::input_iterator_tag)			   // 针对input_iterator的特化版本
{
  	if (d < 0 ) {
     	throw std::out_of_range("Negative distance");    
  	}
  	while (d--) ++iter;							   // 只可逐次++
}

//-------------控制函数-------------//
template<typename IterT, typename DistT>
void advance(IterT& iter, DistT d)           // 控制函数
{
	// 调用特化函数  
  	doAdvance(iter, d,                                              
    	typename std::iterator_traits<IterT>::iterator_category()); // 这里是最重点的地方                       
}   
```

我们先聚焦于控制函数, 调用特化函数应该都能理解, 重点在于 : 

- **typename std::iterator_traits<IterT>::iterator_category()**

这是**特化函数的第三个参数**, 这段代码如何理解?

- 其中`typename`是为了防止编译器混淆, 确定后面的是一个类型(见条款42).
- `typename std::iterator_traits<IterT>::iterator_category`是一个类型, **代表`iterator_traits`从`IterT`中取出的迭代器类别的类型**.

- 后面加上**()**, 代表这是一个匿名变量, 这个参数本身没有任何用处, 所以使用匿名变量完全可行, **其作用只在于传递一个类型, 触发内部的重载机制, 选择到正确的特化版本**.

再去分析特化函数, 上面给出了三个版本, **第三个参数的类型分别是对应的迭代器类别**, 这里连参数都没写在语法上是可行的, 因为确实不会用到, 没有写的必要. 这里要强调的一点是虽然没有`forward_iterator`的版本, 但是因为其和`input_iterator`的操作实质上是一样的, 这里会直接通过**继承**调用到其基类`input_iterator`的代码, 因此不需要多写.

---

### 现代C++中萃取器的使用方式 

先前我们介绍的使用方式是**基于重载机制**, 实现在编译期即可通过不同的迭代器类别选取不同的特化版advance.

一切的根本目的就是为了**在编译期实现条件选择**, 现在C++17中引入了`if constexpr`语法, 使得我们可以用类似if的语句实现编译器的条件选择, 就不需要再使用重载了 : 

```cpp
void advance(IterT& iter, DistT d) {
    using category = typename std::iterator_traits<IterT>::iterator_category; // 还是要先萃取出迭代器类别

    if constexpr (std::is_same_v<category, std::random_access_iterator_tag>) {
        iter += d;
    } else if constexpr (std::is_same_v<category, std::bidirectional_iterator_tag>) {
        if (d >= 0) {
            while (d--) ++iter;
        } else {
            while (d++) --iter;
        }
    } else if constexpr (std::is_same_v<category, std::input_iterator_tag>) {
        if (d < 0) {
            throw std::out_of_range("Negative distance not supported for input iterators.");
        }
        while (d--) ++iter;
    }
}
```

这里通过标准库内置的`is_same_v`来判断两个类别是否相等, 其他均和普通if语句的操作一致.

---

### 更多类型信息可供提取

在本条款中只针对`iterator_category`进行了提取, 但是事实上萃取器可以提取出更多的类型信息, 在*STL源码剖析*中主要提出了五种信息, 分别是 : value_type(迭代器所指对象的类型), difference_type(两个迭代器之间的距离类型), reference_type(迭代器所指对象的类型的引用), pointer_type(迭代器所指对象的类型的指针), iterator_category(迭代器类别).

这里`value_type`尤为常用, 像上文一样既然可以通过`iterator_category`来选取不同版本的代码, 那么也可以根据`value_type`(对象类型)来选取不同版本的代码, 所以说萃取器提供了非常灵活多样的编译期条件选取方式.

---

### 请记住 : 

- 可以使用萃取器技术提取出模板类型中的类型信息, 利用重载或C++17中的`if constexpr`实现编译期的条件选择.
- 实现萃取需要双方约定相同的类型信息名称. 



by 天目中云

