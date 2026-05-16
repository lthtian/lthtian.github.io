---
title: Effective C++ 条款44 防止代码膨胀
date: 2025-1-12 17:50:00
tags: [Effective C++, 模板]
---

## 条款44 : 将与参数无关的代码抽离templates

> 我们知道代码重复和过度的inline都可能导致代码膨胀, 而在模板中会发生比较隐晦的代码重复, 我们应当尽力去避免代码重复的情况发生, 而最核心的方法就是将与参数无关的代码抽离templates, 让我们通过本条款进行了解.

在本条款中我们将会了解 : 

- 在模板中什么情况下会发生代码膨胀?
- 如何缓解这种代码膨胀?
- 在缓解代码膨胀后如何知道该操作什么数据?

---

### 代码膨胀

举个例子, 假设你想为固定尺寸的正方矩形编写一个template, 该矩形指出逆矩阵运算 : 

```cpp
template<typename T,           // 矩阵的元素类型是T
         std::size_t n>        // 矩阵的固定尺寸为n, 这是非类型模板参数
class SquareMatrix {         
public:
  ...
  void invert();              // 求逆功能
};
```

当我们在使用这个类型时 : 

```cpp
SquareMatrix<double, 5> sm1;      // SquareMatrix<double, 5>类型
...
sm1.invert();                 

SquareMatrix<double, 10> sm2;     // SquareMatrix<double, 10>类型
...
sm2.invert(); 
```

我们应该已经注意到, 只要T和n有不同, 在实际上编译器就会重新编译出一份代码. 在本例中, 仅仅只是在尺寸上有差别, 但还是在底层编译出了两份除了尺寸不一样但是其他都相近的代码, 这就造成了实际意义上的代码膨胀.

你也许会觉得这样无可厚非, 这就是模板机制导致的, 但是细想`invert()`这个函数, 对矩阵求逆的过程基本都是相同的, 只是矩阵的尺寸有差别罢了, 我们可以通过某些手法将`invert()`抽离出来, 使其不必频繁编译, 这便是我们接下来要介绍的解决方法.

---

### 将实现类和功能类分离

我们可以把一个类拆分, 把功能函数拆分出来作为基类, 实现类作为子类.

让我们直接给出例子, 根据例子来介绍 : 

```cpp
template<typename T>                   // 基类 - 功能类
class SquareMatrixBase {               
protected:							   // 这里是protected, 不对外公开, 只给派生类调用
  ...
  void invert(std::size_t matrixSize); // 这里实际是用函数参数替代掉了SquareMatrixBase的模板参数
  ...
};

template<typename T, std::size_t n>    // 派生类 - 实现类
class SquareMatrix: private SquareMatrixBase<T> {
private:
  using SquareMatrixBase<T>::invert;   // 见条款33, 避免遮掩
public:
  ...
  void invert() { this->invert(n); }   // 调用模板基类的成员函数, 见条款43
};
```

这里`SquareMatrix`是实现类, 也就是我们正常使用的类型, 它的情况还是和上面一致, 只要T和n有不同, 还是会生成一份额外的代码, 但是不同的是**它把大量的实际代码移到了功能类中(这里只显示了invert, 实际可以有很多功能函数), 使本身的代码量骤减, 大大减少了额外代码的生成**.

这里`SquareMatrixBase`是功能类, 他负责给派生类提供相应的功能, 我们从派生类**private继承**自它便可看出. 它只有一个T模板参数, 也就是说它**只对"矩阵元素对象的类型"参数化, 不对"矩阵的尺寸"参数化**, 也就是说只要T相同, 就算派生类的n是任何数字, 都将使用同一份代码 , 不会再编译出多份代码, 我们也可以认为**实际上是用函数参数替代掉了SquareMatrixBase的模板参数**. 

---

### 数据操作问题 

在解释这个问题之前, 我们应该再引入一个前提, 就是**SquareMatrix应该是有一个存储数据的成员变量的**, 这应当很容易理解, 在最初版`SquareMatrix`中就可以是这样 : 

```cpp
template<typename T,         
         std::size_t n>       
class SquareMatrix {         
public:
  	...
  	void invert();            
    
private:
  	T data[n * n];              // 存储矩阵数据的成员变量
};
```

在最初版中, `invert()`可以直接对data进行操作, 但是当我们把实现类和功能类分离后, **data肯定还是在实现类中**, 因为控制数据应当是实现类的职责, 并且这样子便于动态内存的分配; **但是invert()到了功能类, 无法直接对data进行修改**, 功能类函数该如何实际修改data中的数据, 这便是我们要解决的问题.

其实解决方式也很简单, **在SquareMatrixBase中存储一个指向data的指针**就好了 : 

```cpp
template<typename T>
class SquareMatrixBase {
protected:
  SquareMatrixBase(T *pMem)     
  :pData(pMem) {}                    // 在构造函数中接受传入的资源指针

  void setDataPtr(T *ptr) { pData = ptr; }     // 重新设置资源指针
  ...
  void invert(std::size_t matrixSize);	       // 内部直接用pData这个指针对资源进行调整

private:
  T *pData;                                    // 指向资源
};


template<typename T, std::size_t n>
class SquareMatrix: private SquareMatrixBase<T> {
public:
  SquareMatrix()                             
  : SquareMatrixBase<T>(data) {}          // 向基类构造传入资源指针
  ...
  void invert() { this->invert(n); }
private:
  T data[n*n];
};
```

我们可以自行决定实现类中数据内存的分配方式, 在上文中`T data[n*n];`是将数据存储在了对象内部, 也就是栈上. 我们也可以通过动态分配内存的方式将数据存入堆上(通过new来分配内存) : 

```cpp
template<typename T, std::size_t n>
class SquareMatrix: private SquareMatrixBase<T> {
public:
  SquareMatrix()                          
  : SquareMatrixBase<T>(n, 0),            
    pData(new T[n*n])                    // 向基类构造传入new出来的指针
  { this->setDataPtr(pData.get()); }      
  ...                                     

private:
  std::unique_ptr<T> pData;           // 使用智能指针管理内存
}; 
```

---

### 类型参数导致的代码膨胀

我们可以发现上文都对非类型参数(n)导致的代码膨胀提供的解决方案, 但是类型参数(T)也同样会导致代码膨胀, 不同的T也会产生不同的编译版本, 有些类型在底层其实是非常相近甚至相同的, 例如int和long, 各种指针类型之间. 

假设T是一个指针类型, 所有指针类型都有着相同的二进制表述, 其实编译出来的代码基本一致, 只是指针类型不一样而已. 那么我们就可以在模板函数中将这些指针转换为`void*`, 然后调用操作`void*`指针类型的函数, 由后者完成实际函数, 也可以达到类似防止代码膨胀的效果, 标准库中的vector, list等都用过这种方式, 以下是list在底层的类似实现 : 

```cpp
class ListBase {
protected:
    ...
    void push_back_impl(void* value) {
        // 使用 `void*` 实现通用逻辑
        *(pdata + size) = value;
        size++;
    }

private:
    void* pData;
    int size = 0;
};

template <typename T>
class List : private ListBase {
public:
    ...
    void push_back(T* value) {
        // 转换为 `void*`，调用底层通用逻辑
        push_back_impl(static_cast<void*>(value));
    }
    
private:
    void* data[100]; // 用 `void*` 存储所有指针类型
};

// `list<int*>` 和 `list<const int*>` 都调用相同的底层代码
List<int*> list1;
List<const int*> list2;
```

---

### 请记住 : 

- 使用模板会有隐含的代码膨胀产生, 我们可以通过将一些功能函数抽离出来作为基类, private继承给派生类来避免代码膨胀.
- 因非类型模板参数(n)造成的代码膨胀, 往往可消除, 可以用**函数参数或class成员变量**替换掉非类型模板参数.

- 因类型模板参数(T)造成的代码膨胀, 往往可降低, 可以让**底层二进制表述完全相同的类型(如指针)共享功能函数**.



by 天目中云













