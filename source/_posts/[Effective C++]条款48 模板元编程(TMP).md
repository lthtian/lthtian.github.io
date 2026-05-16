---
title: Effective C++ 条款48 模板元编程(TMP)
date: 2025-1-22 21:07:00
tags: [Effective C++, 模板]
---

## 条款48 : 认识template元编程

> 在条款47我们主要了解了萃取器这种模板元编程, 也初步进入了模板元编程的世界. 在本条款中, 我们将继续认识模板元编程, 认识其必要性和应用场景, 相比于条款47讲的还算比较深入,本条款真的就只是简介, 因为其体量确实非常庞大, 甚至可以单独作为一个学科研究.

`Template metaprogramming`, 模板元编程, 简称TMP, 是**编写template-based C++程序并执行于编译期的过程**.

---

### 模板元编程的效用

我们目前可以用在条款47中学到的萃取器的知识来理解模板元的效用 : 

- 它让某些事情更容易, 这些事情原本比较困难甚至不可能.(例如针对迭代器类型进行可靠的条件编译)
- 它将工作期从运行期移至编译期, 大大提高了运行效率, 有更小的可执行文件, 更短的运行期, 更少的内存消耗.

假设我们使用萃取器时不采用重载或`if constexpr`这种模板元编程, 而是就是在运行期通过判断迭代器类型来条件判断, 我们看看最后的效果怎样 : 

```cpp
template<typename IterT, typename DistT>
void advance(IterT& iter, DistT d)
{
  if (typeid(typename std::iterator_traits<IterT>::iterator_category) ==
      typeid(std::random_access_iterator_tag)) {
     iter += d;                                     
  }                                                 
  else {
    if (d >= 0) { while (d--) ++iter; }             
    else { while (d++) --iter; }                    
  }                                                 
}
```

这里还是用萃取器提取出类型, 利用`typeid`在运行期进行条件判断, 但是这种方法不仅不高效(对应效用2), 而且不可行(对应效用1).

- 不高效 : 这个很容易理解, 利用模板元编程在编译期即可实现的效果, 这样却要在运行期花时间判断.

- 不可行 : 这段代码在一些情况下甚至都无法通过编译, 如果我们像下面这样使用 : 

  ```cpp
  std::list<int>::iterator iter;
  advance(iter, 10);
  ```

  这样使用非常合理, 但是会运行崩溃, 因为list的迭代器是双向迭代器, 而非随机访问迭代器, 所以`iter += d;`这段代码根本无法通过编译! 也许你会认为因为条件判断, 如果是list的迭代器, 这句代码永远不会触发, 但是我们应当知道 : 

  - **编译器必须确保所有源码都有效, 纵使是不会执行起来的代码.**

至此我们应该已经可以理解到部分模板元编程可以达到的效用了.

---

### 模板元编程中的"hello world!"

我们可以了解模板元编程中的一个入门编程, 它相当于初入编程的"hello world", 即**在编译期计算阶乘**.

```cpp
template<unsigned n>                 
struct Factorial {                   
  enum { value = n * Factorial<n-1>::value };
};

template<>                          
struct Factorial<0> {            // 全特化
  enum { value = 1 };
};
```

我们通过代码应该可以推导出一个递归的过程, 并且这个过程是通过模板在编译期来实现的! 于是我们就可以这样使用 : 

```cpp
int main()
{
  std::cout << Factorial<5>::value << std::endl;   // 直接打印出120
  std::cout << Factorial<10>::value;               // 直接打印出3628800
}
```

我们可以和普通递归求阶乘进行对比 : 

- 普通递归 : 运行期实现, 可以通过用户输入动态计算任意数的阶乘.
- 模板元递归 : 编译期实现, 只可以得到预先设置的数的阶乘.

简单来说就是前者耗费运行期时间但是灵活, 后者不费运行期时间但是不可变.

当然使用enum是一个比较原始且可读性较差的做法, 在C++11已经引入constexpr : 

```cpp
template<unsigned n>
struct Factorial {
  static constexpr unsigned value = n * Factorial<n - 1>::value;  // constexpr代替enum
};

template<>
struct Factorial<0> {
  static constexpr unsigned value = 1;
};
```

---

### 三个应用场景案例

- 确保度量单位正确.

  在科学工程中, 我们可以提前确定度量单位的结合正确, 可以进行早期的错误侦测.

  ```cpp
  #include <iostream>
  #include <type_traits>
  
  // 定义不同的单位类型
  struct Time { static constexpr const char* name = "Time"; };		// 时间
  struct Length { static constexpr const char* name = "Length"; };	// 长度
  
  // 计算单位的乘法
  template <typename Unit1, typename Unit2>
  struct MultiplyUnits;
  
  // 两个长度相乘得到面积
  template <>
  struct MultiplyUnits<Length, Length> {   // 全特化
      using type = struct Area { static constexpr const char* name = "Area"; }; // 定义面积类型
  };
  
  // 时间与长度相除，得到速度
  template <>
  struct MultiplyUnits<Length, Time> {
      using type = struct Velocity { static constexpr const char* name = "Velocity"; }; // 定义速度类型
  };
  
  // 打印单位名称
  template <typename Unit>
  void printType() {
      std::cout << "TypeName: " << Unit::name << std::endl;
  }
  
  int main() {
      // 计算长度与时间的组合，得到速度
  	typedef typename MultiplyUnits<Length, Time>::type unit1;
  	printType<unit1>();  // 输出: Unit: Velocity
  
  	// 计算长度与长度的组合，得到面积
  	typedef typename MultiplyUnits<Length, Length>::type unit2;
  	printType<unit2>();  // 输出: Unit: Area
      
      return 0;
  }
  ```

  本例中就可以根据向`MultiplyUnits`中传入的类型在编译期进行判断其结果的类型.

- 优化矩阵运算.

  在条款44中我们编写过矩阵, 假如我们进行下面的运算 : 

  ```cpp
  typedef SquareMatrix<double, 10000> BigMatrix;
  BigMatrix m1, m2, m3, m4, m5;              
  BigMatrix result = m1 * m2 * m3 * m4 * m5; 
  ```

  如果这些在运行期完成, 将会产生内存巨大的临时对象和不低的时间成本, 但假如用模板元编程就可能消除临时对象并合并循环, 大大降低成本, 具体细节书中没有给出, 这里就不再细讲.

- 可以生成客户定制之设计模式实现品.

  这里的命题就更加广阔了, 简单理解就是许多设计模式都和类与模板有关, 可以利用模板元编程根据需求将一些设计模式的行为从运行期搬到编译期中, 不仅实现了定制, 还提高了运行效率.

---

### 现代模板元编程

随C++11, C++14, C++17的引入, 模板元编程的语法日渐丰富, 这一领域虽然有些晦涩难懂, 但是其确实有其价值所在, 并且越来越被重视. 我们虽然不一定要完全掌握, 但是可以逐步了解一下模板元编程的语法, 例如constexpr, if constexpr, SFINAE技术, 模板元函数等等.

---

### 请记住 : 

- 模板元编程可将工作由运行期移往编译期, 因而得以实现早期错误侦测和更高的执行效率.



by 天目中云