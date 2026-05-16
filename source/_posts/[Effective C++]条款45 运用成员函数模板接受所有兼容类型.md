---
title: Effective C++ 条款45 运用成员函数模板接受所有兼容类型
date: 2025-1-13 17:38:00
tags: [Effective C++, 模板]
---

## 条款45 : 运用成员函数模板接受所有兼容类型

> 本条款中我们将会以智能指针为例, 介绍如何通过成员函数模板使一个模板类可以接受所有兼容类型.

我们先来构建一个简单的继承体系 : 

```cpp
class Top { ... };
class Middle: public Top { ... };
class Bottom: public Middle { ... };
Top *pt1 = new Middle;                   // Middle*隐式转换为Top*
Top *pt2 = new Bottom;                   // Bottom*隐式转换为Top*
const Top *pct2 = pt1; 					 // Top*隐式转换为const Top*
```

在本例中, `Top`是最初始的基类, 依次派生出`Middle`和`Bottom`, 通过隐式转换, 各种指针类型是可以合理地进行隐式转换的. 但当我们想用智能指针代行管理事务时, 再想这样的转换就比较麻烦了, 当然标准库中的智能指针已经解决了这种问题, 我们现在要讨论的就是标准库是如何实现智能指针之间的隐式转换的, 我们期待的效果如下 : 

```cpp
template<typename T>
class SmartPtr {
public:                             
  explicit SmartPtr(T *realPtr);    // 通过资源指针进行初始化
  ...
};

SmartPtr<Top> pt1 = SmartPtr<Middle>(new Middle);   
SmartPtr<Top> pt2 = SmartPtr<Bottom>(new Bottom); 
SmartPtr<const Top> pct2 = pt1; 
```

这段代码是无法通过编译的, 因为就算是`Top`和`Middle`有联系, `SmartPtr<Top>`和`SmartPtr<Middle>`也没有任何联系, 它们是无法隐式转换的, 但是我们可以通过成员函数模板, 具体说是写一个泛化copy构造函数来创造这种联系.

---

### 泛化copy构造函数

我们先来写一个成员函数模板中的**泛化copy构造函数** : 

```cpp
template<typename T>
class SmartPtr {
public:
  template<typename U>                       // 泛化copy构造函数
  SmartPtr(const SmartPtr<U>& other);       
  ...                 
};
```

这个模板函数接受用一个`SmartPtr<U>`类型的参数去构造一个`SmartPtr<T>`类型的对象, 现在还只是声明, 我们应该考虑如何定义内部逻辑, 正常逻辑应该是先看`U*`是否可以隐式转换为`T*`, 如果可以转换也就可以进行智能指针之间的转换, 我们来看代码 : 

```cpp
template<typename T>
class SmartPtr {
public:
  template<typename U>
  SmartPtr(const SmartPtr<U>& other)         
  : heldPtr(other.get()) {...}            // 关键代码
    
  T* get() const { return heldPtr; }
  ...
private:                                     
  T *heldPtr;                                
};
```

这里直接将参数other中的`heldPtr`取出, 赋值给当前对象的`heldPtr`. 其实在这里就进行了检查 : 

- `other.get()`取出的指针类型为`U*`, 如果`U*`可以隐式转换为`T*`, 那么可以进行智能指针之间的转换.
- 如果不可以隐式转换, 编译错误, 会被系统拦截.

至此, 通过泛化copy构造函数这个成员函数模板, 只要`U*`可以隐式转换为`T*`, 那么`SmartPtr<U>`也可以隐式转换为`SmartPtr<T>`.

---

### 成员函数模板

成员函数模板的效用不只局限于构造函数, 也可以支持赋值操作, 其不改变语言规则, 但是可以帮助你让class在构造和赋值操作上可以兼容更多类型, 让我们在使用模板类型时可以像使用非模板类型时一样自然流畅. 我们可以了解一下标准库中`shared_ptr`的简略版本, 看看其对成员函数模板的使用 : 

```cpp
template<class T> 
class shared_ptr {
public:
  // 构造
  template<class Y>                                     
    explicit shared_ptr(Y * p);                         // 泛化构造函数
  template<class Y>                                     
    shared_ptr(shared_ptr<Y> const& r);                 // 泛化copy构造函数
  template<class Y>                                     
    explicit shared_ptr(weak_ptr<Y> const& r);          // 通过weak_ptr构造
  template<class Y>
    explicit shared_ptr(unique_ptr<Y>& r);				// 通过unique_ptr构造
  // 赋值
  template<class Y>                                    
    shared_ptr& operator=(shared_ptr<Y> const& r);      // 泛化赋值重载
  template<class Y>                                     
    shared_ptr& operator=(unique_ptr<Y>& r);            // 用unique_ptr赋值
  ...
};
```

在本例中,  构造函数中只有泛化copy构造函数没有explicit, 说明其他构造函数都不应当支持隐式类型转换, 也就是说T和Y的类型应当一致. 另外成员模板函数并**不改变语言规则**, 就算我们写了泛化的拷贝构造函数和赋值重载, 依旧不影响普通的拷贝构造和赋值重载, 如果我们没有写, 编译器还是会自动生成, 所以如果想要控制构造的方方面面, 我们应当**同时声明普通版本和泛化版本**.

```cpp
template<class T> 
class shared_ptr {
public:
  shared_ptr(shared_ptr const& r);                 // 普通拷贝构造
  template<class Y>                                
    shared_ptr(shared_ptr<Y> const& r);            // 泛化拷贝构造

  shared_ptr& operator=(shared_ptr const& r);      // 普通赋值重载
  template<class Y>                               
    shared_ptr& operator=(shared_ptr<Y> const& r); // 泛化赋值重载
  ...
};
```

---

### 请记住 : 

- 使用成员函数模板可以生成"可接受所有兼容类型"的函数.
- 当我们声明泛化拷贝构造和赋值重载时, 也应该声明其普通版本.