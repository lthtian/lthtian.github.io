---
title: Effective C++ 条款18 设计正确易用的接口
date: 2024-11-30 22:06:52
tag: Effective C++
---

## 条款18 : 让接口容易被正确使用, 不易被误用.

> C++在接口之海漂浮, 一个好的接口很容易被正确使用, 不容易被误用.

条款18其实是一个很宏观的条款, 让接口变得正确易用, 简单来说就是"**促进正确使用**"和"**阻止误用**".

我们先从**阻止误用**的角度考虑, 对接口来说, 是否误用无非就是参数传递的类型对不对, 参数是否合法, 是否符合设计者的设想.

书中给出了一个日期类, 分别由年月日的成员变量, 我们先来看第一个给出的构造函数 : 

```cpp
class Date {
public:
  Date(int month, int day, int year);
  ...
};
```

这样设计在设计者看来很合理, 但是没有任何合法性检查只会带来无穷的隐患, 我们可以从中看出以下问题 : 

- 客户不一定知道是按月日年的顺序来输入, 如果是我们的日常习惯, 可能会输入年月日.

如何使用户在编写过程中就知道自己写错了呢? 

书中告诉我们的方法是 : **导入新类型**, 因为问题的根源是年月日的变量类型都是相同的`int`, 如果设定为不同的类型, 就可以确保输入的正确性了, 代码如下 : 

```cpp
struct Day {            struct Month {                struct Year {
  explicit Day(int d)     explicit Month(int m)         explicit Year(int y)
  :val(d) {}              :val(m) {}                    :val(y){}

  int val;                int val;                      int val;
};                      };                            };
class Date {
public:
Date(const Month& m, const Day& d, const Year& y);
...
};
Date d(30, 3, 1995);                      // 错误, 不是int!
Date d(Day(30), Month(3), Year(1995));    // 错误, 顺序错了!
Date d(Month(3), Day(30), Year(1995));    // 正确, 类型和顺序相对应
```

当然还有一些数值我们可以提前限制, 比如一年肯定只有12个月, 我们就可以让用户不用直接通过构造传参, 而是用函数返回需求的`Month`对象, 代码如下 : 

```cpp
class Month {
public:
  static Month Jan() { return Month(1); } 
  static Month Feb() { return Month(2); }  
  ...                                       
  static Month Dec() { return Month(12); } 
  ...                                      
private:
  explicit Month(int m);  // 不让用户显式使用构造, 只能通过成员函数内部调用
};

Date d(Month::Mar(), Day(30), Year(1995));  // 这样我们就可以这样调用了
```

 书中提出**以函数替换对象**也是一种预防客户输入错误的方式.

当然通过**const限制类型操作**也是一种方式, 这里就不再举例.

---

讲完了阻止误用, 那么如何**促进正确使用**呢? 

正确使用, 简单来说就是**符合使用者的习惯**, 使用者的习惯是什么呢? 当然是**使用内置类型**呀, 使用者当然希望可以像使用`int`一样使用其他自定义的类型.

因此书中提出: **除非有好理由, 否则应该尽量令你的自定义类型的行为与内置类型一致.**

实际来说就是**用好运算符重载, 有必要时考虑迭代器的设计模式**.

---

书中还提出了一个重要观点 : 

- **任何接口如果要求用户必须记得做某些事情, 就是有者"不正确使用"的倾向.**

> 接下来的内容有关条款13和14, 没有看过的可以看我往期的博客.

让我们回到条款13中提出的`createInvestment()`工厂函数, 他会返回一个资源的原始指针, 而我们应当用`shared_ptr`去封装该指针, 这就成了用户必须记得做的事情, 那么为了让该函数返回的内容更易用, 我们可以在直接返回一个智能指针, 函数声明如下 : 

```cpp
// Investment* createInvestment();
std::shared_ptr<Investment> createInvestment();
```

---

函数内部实现并非本条款的重点, 但是书中也花了部分篇幅去讲解, 我也会跟着解释清楚, 先看内部的代码 : 

```cpp
std::tr1::shared_ptr<Investment> createInvestment()
{
  std::shared_ptr<Investment> retVal(static_cast<Investment*>(nullptr), getRidOfInvestment);
    
  ...                                // 中间部分实现工厂函数的内存分配步骤
      
  return retVal;
}
```

看到`shared_ptr`构造的两个参数我们可能会有点懵, 我们来一个个分析 : 

首先我们明确`stl`中`shared_ptr`构造的第一个参数是**原始资源类型的指针**, 第二个参数是**删除器函数**.

先讲第二个参数, 看过条款14的都知道, `getRidOfInvestmen`t应当是我们提供给`shared_ptr`在析构时使用的函数, 它存在的意义在于某些类型没有传统的析构, 而是一些特殊的释放函数, 需要我们手动调用, 我们把这些函数放在删除器中, 就可以化手动为自动, 我们这里是假定`Investment`是有这种需求的类型, 如果不是当然可以不写. 这种由设计者自己定制删除器的行为其实也是在减少客户不必要的释放步骤, 与本条款的理念相符合.

接下来是第一个参数, 我们应当传入一个原始资源类型的指针, 按道理来说应该是通过`new Investment()` 返回一个指针直接存进去, 但这里选择先不进行动态分配, 直接存入一个`nullptr`, 而且由于`shared_ptr`构造不允许隐式类型转换, 所以要把`nullptr`强转成`Investment*`类型, 也就是`static_cast<Investment*>(nullptr)`了, 因此`retVal`刚生成时并没有分配到资源, 是在接下来中间部分实现内存分配.

这里深入一下, 为什么工厂函数中要先构造指针再分配内存, 而不是先分配内存再给指针构造? 这里有两点原因 : 

1. 可能需要**通过不同的条件以不同的方式分配内存**, 这是也是工厂函数存在的意义所在.

   ```cpp
   std::shared_ptr<Investment> createInvestment(bool isPremium)
   {
       std::shared_ptr<Investment> retVal(static_cast<Investment*>(nullptr), getRidOfInvestment);
   
       // 根据条件选择不同的分配方式
       if (isPremium) {
           retVal = std::make_shared<PremiumInvestment>();
       } else {
           retVal = std::make_shared<RegularInvestment>();
       }
   
       return retVal;
   }
   ```

   分析以上代码, 我们可以知道`Investment*`的静态类型是一个基类指针, 但是通过`isPremium`和多态机制, 我们可以根据传入的`isPremium`来选择其动态类型是派生类的`PremiumInvestment`还是`RegularInvestment`进而产生不同的内存分配策略, 而这起码要我们先有一个指针对象才行.

2. **分配内存是有可能出现异常的**, 如果出现异常先前分配的内存就泄露了, 但如果提前构造指针, 再用`make_shared`函数获取内存, 就算发生异常也一定是安全的, 因为**指针会调用析构把先前的内存释放**.

也许略微有些跑题, 但是我觉得能看透问题的本质才是最重要的, 因此多下了一些功夫.

---

### 请记住 : 

- **阻止误用的方法包括 : 导入新类型, 以函数替换对象, 利用const限制, 消除客户的资源管理责任, 不要让客户必须记得某些事情.**
- **促进正确使用的方法包括 : 保证接口的一致性, 与内置类型行为兼容.**
- 可以通过设定定制的删除器减少客户手动调用释放函数的负担.



by 天目中云