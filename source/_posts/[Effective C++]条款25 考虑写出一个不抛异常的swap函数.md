---
title: Effective C++ 条款25 考虑写出一个不抛异常的swap函数
date: 2024-12-4 19:57:12
tag: Effective C++
---

## 条款25 : 考虑写出一个不抛异常的swap函数

> swap 是一个有趣的函数, 原本它只是STL的一部分, 而后成为了异常安全性编程中的脊柱, 有关异常安全性我在条款11中介绍过, 在之后的条款29中也将着重着墨. 由于swap相当有用, 适当的实现非常重要, 好的swap设计可以带来非凡的效率提升.

swap顾名思义, 意为将两对象的值彼此赋予对方, 在现代标准库中的实现是这样 : 

```cpp
namespace std {
    template <typename T>
    void swap(T& a, T& b) noexcept {
        T temp = std::move(a);  // 使用移动拷贝会大大提高效率且不抛出异常
        a = std::move(b);
        b = std::move(temp);
    }
}
```

我们可以看出这只是简单的移动拷贝而已, 而我们经常会使用一个手法叫做`pimpl idiom`, 其"**以指针指向一个对象, 内涵真正的数据**", 这种手法意在将数据管理和操作管理解耦, 可以进行更有效的设计, 而这种类调用标准库的`std::swap`往往是效率低下的, 书中给出的代码如下:

```cpp
class WidgetImpl {                          // 保存Widget的数据
public:                                    
  ...
private:
  int a, b, c;                            
  std::vector<double> v;                  
  ...
};

class Widget {                              // 日常使用的Widget
public:
  Widget(const Widget& rhs);
  ...
private:
  WidgetImpl *pImpl;                         // 一个指针指向数据
};           
```

如果我们调用标准库中的`std::swap`, 其消耗是**三次移动拷贝并且还有可能多余地拷贝双方的底层资源**, 有可能产生更大的花销, 所以我们希望自定义的`swap`可以只交换`pImpl`的指针即可.

现在我们现在需要重新拟定一下我们的目标, 其一**确保我们的swap函数不抛异常**, 这是为了其在异常安全性上的功能得以实现; 其二**让其他人调用swap时都能取得我们提供的高效的版本**.

---

前者只需我们记得不做有异常风险的举动就行了, 但是在`C++11`已经推行的当下, 我们还应**必须**给我们的函数贴心地加上`noexpect`标识符, 用来对编译器保证该函数绝不会抛出异常, **编译器也会回应你的保证, 删去针对该函数的异常处理, 使效率提高**. 

---

现在开始分析后者, 这里我们要知道一个前提, 大多数用户调用`swap`其实都是以标准库中的形式来调用的, 也就是说不会通过对象调用`swap`成员函数, 而是都是`swap(lhs, rhs)`这样的形式, 现在先研究在`C++98`版本下如何解决 :

书中给出的步骤如下:

1. 像我们先前一样写一个完美的不抛异常的`swap`成员函数.
2. 在该`class`的命名空间下写一个`non-member swap`函数, 并使它调用该`class`的成员函数.
3. 最后如果你的`class`不是`class template`(模板类), 为你的`class`全特化`std::swap`. 

我们来解释为什么要写三个函数, 即**member + non-member + std全特化** :

简单来说就是使在客户调用`swap(a, b)`时, 如果这个函数在`WidgetStuff`命名空间中, 就会直接匹配`non-member`版本, 进而调用相同命名空间下的`member`版本, 不会因为参数不匹配而没有调用到`member`版本. 而当客户调用标准库`swap`时, 由于模板全特化, 也会自动调用`member`版本.这样就极大程度上使得调用到的版本都是我们的特化版本.

由上面上述构成的最终方案如下 : 

```cpp
namespace WidgetStuff {  // Widget所在的命名空间
  ...                                   
  template<typename T>      
  class Widget { 
  	public:
    	...
    	void swap(Widget& other)  { 
            using std::swap;   			// 下面解释原因
        	swap(pImpl, other.pImpl); 
    	}
    	...
  };  
  ...
  template<typename T>    
  void swap(Widget<T>& a, Widget<T>& b)   // non-member                                      
  {
    	a.swap(b);
  }
}

namespace std {
  template<>                       // 对于swap针对Widget类型的全特化
  void swap<Widget>(Widget& a, Widget& b)
  {
    a.swap(b);                 
  }                                
}
```

这里要解释一下为什么`member`版本中要加`using std::swap;`而不是直接用`std::swap(pImpl, other.pImpl)`, 因为不必写死只用标准库, `pImpl`也有可能是有自定义`swap`函数的类对象, 这样子可以**让编译器优先选择类的自定义swap**, 并且通过`using std::swap;`暴露了标准库接口, **在没有自定义的情况下最后也会选择标准库版本**.

---

以上是`C++98`版本的解决方法, 但在`C++11`已经引入的当下, 推出了一个新的机制**参数依赖查找 (ADL, Argument-Dependent Lookup)**, 这个机制简单来说就是在`C++98`时的函数查找机制都**只是在当前作用域或using声明中查找**,  **而ADL可以通过参数的类型将该类型所在的命名空间纳入查找范围**. 这对我们上述的解决办法有何助益? 答案是我们不需要执行第三步了, 也就是说可以放弃对`std::swap`的全特化了.

在C++98的情况下, 如果当前作用域中没有`non-member`版本, 就一定会回到使用标准库的情况, 所以对`std::swap`进行全特化是有必要的. 而`ADL`可以通过参数类型引入作用域, 只要`non-member`版本和`member`版本在同一命名空间下, 就一定可以调用成功, 就是说**只要你认真实现了前两步, 就一定不会在发生调用标准库`swap`的情况**, 我们对标准库swap的需求就已经降低到了只需要默认版本的程度, 不需要任何的特化, 所谓的特化已经成为"98往事"了, 代码如下 : 

```cpp
namespace WidgetStuff {  // Widget所在的命名空间
  ...                                   
  template<typename T>      
  class Widget { 
  	public:
    	...
    	void swap(Widget& other) noexcept { 
            using std::swap;   			// 上面已经解释原因
        	swap(pImpl, other.pImpl); 
    	}
    	...
  };  
  ...
  template<typename T>    
  void swap(Widget<T>& a, Widget<T>& b) noexcept   // non-member                                      
  {
    	a.swap(b);
  }
}
```

注意为了符合`C+11`版本, 我们新加了`noexcept`关键字, 添加的原因上文已经说明.

---

这次我基于`C++11`的新增机制对书中条款的解读做出了比较大的变化, 让其更适应2024年的现在, 写了很多原本书中没有的内容, 可能会有自己考虑不周的地方, 欢迎评论指正!

---

### 请记住 : 

- **当std::swap对你的类型效率不高时, 提供swap的member版本和non-member版本, 确定这两个函数不抛出异常, 并且标明noexpect**.
- 如果你的版本还在`C++98`, 可能还要考虑多提供对`std::swap`的全特化.



by 天目中云