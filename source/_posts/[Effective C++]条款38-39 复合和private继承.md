---
title: Effective C++ 条款38-39 复合和private继承
date: 2024-12-29 20:12:12
tags: [Effective C++, 继承]
---

## 条款38 : 通过复合塑膜出has-a或"根据某物实现出"

> 在条款32中我们认识了public继承意味着is-a, 本条款将会认识两个新的关系, 均可通过"复合"这一操作实现出来.

---

### 复合

所谓**复合**, 就是**某种类型的对象内含其他类型的对象,** 其实非常容易理解, 我们通过代码理解 : 

```cpp
class Address { ... };           
class PhoneNumber { ... };

class Person {
public:
  ...
private:
  std::string name;              // 复合std::string
  Address address;               // 复合Address
  PhoneNumber voiceNumber;       // 复合PhoneNumber
  PhoneNumber faxNumber;          
};
```

`Person`类便是复合了`Address`和`PhoneNumber`两个类.

---

### 两种意义

使用复合手法在不同领域的对象上, 有不同的意义, 我们先来定义两个领域 : 

- 应用域 : 当一个内置对象的目的是"**这个类能做到什么(what)**", 它属于应用域, 上面的地址和电话便是如此.
- 实现域 : 当一个内置对象的目的是"**这个类如何做到(how)**", 它属于实现类.

在设置不同域的对象其代表的意义也不同, 让我们看下面两种意义 : 

- **has-a(有一个)** 

  当对象属于应用域, 如果A复合了B, 则代表A有一个B, A可以做出B的所有行为, 但不强制, 例如人有一个家.

- **is-implemented-in-terms-of(根据某物实现出)** 

  当对象属于实现域, 如果A复合了B, 则代表A根据B实现出来, A想要实现自己的功能要借助B的功能, 例如标准库中的unordered_set根据HashTable实现出来.

  我如果不想用HashTable实现set, 也可以用list来实现, 书中给出的例子是这样的 : 

  ```cpp
  template<class T>                 
  class Set {
  public:
    bool member(const T& item) const;
    void insert(const T& item);
    void remove(const T& item);
    std::size_t size() const;
  
  private:
    std::list<T> rep;                 // 复用list实现另一个版本的set.
  };
  ```

  于是Set就可以依靠list提供的机能来实现自己的功能 : 

  ```cpp
  template<typename T>
  bool Set<T>::member(const T& item) const
  {
    return std::find(rep.begin(), rep.end(), item) != rep.end();
  }
  
  template<typename T>
  void Set<T>::insert(const T& item)
  {
    if (!member(item)) rep.push_back(item);
  }
  
  template<typename T>
  void Set<T>::remove(const T& item)
  {
    typename std::list<T>::iterator it =               
      std::find(rep.begin(), rep.end(), item);        
    if (it != rep.end()) rep.erase(it);
  }
  
  template<typename T>
  std::size_t Set<T>::size() const
  {
    return rep.size();
  }
  ```

---

### 请记住 : 

- public继承的意义完全不同.
- 在应用域中, 复合意味着`has-a`. 在实现域, 复合意味着`is-implemented-in-terms-of`

---

## 条款39 : 明智而审慎地使用private继承

> 通过本条款, 你将明晰private继承在继承体系中充当了什么样的角色, 其与public继承和复合又有怎样的区别.

没错, private继承也有其所意味的东西, 但是这个意义我们已经了解过了, 那就是**is-implemented-in-terms-of**.

没错, private继承和复合除开在底层的实现细节不同, 它们可以实现相同的目的, 虽然有着不同的限制.

我们还是先回忆一下private继承会发生什么 : 

- 编译器**不会自动将该派生类对象隐式转换为基类对象**, 也就是说基类参数接口将无法接受该对象.
- 所有从基类继承而来的属性在派生类中**都是private的**, 纵使它们原来是public/protect.

```cpp
class Person { 
	...
public:
    void speak();    
    ...
};
class Student: private Person { ... };     // 如果是private继承Person

void eat(const Person& p);				   // 按常理所有人都可以吃

Person p;                                  // p is a Person
Student s;                                 // s is a Student

eat(p);                                    // 正确
eat(s);									   // 错误! 无法隐式转换为基类
cout << s.speak() << endl;				   // 错误! public已经转为private
```

我们可以看出private继承和`is-a`的关系完全不沾边, 最终的实际效果其实就是`is-implemented-in-terms-of`(根据某物实现出).

若B private继承 自A, 说明A需要采用B中备妥的某些特性, A不需要传递B的什么接口, 而是希望使用B的一部分功能实现, 可以是直接使用, 也可以是有目的的重写, 我们可以肯定的是这样至少要比我们单独实现一份需求的功能来得方便.

---

### 什么时候使用private继承

既然我们知道private继承和复合都可以实现`is-implemented-in-terms-of`的效果, 那么应该选哪个呢? 

答案是如果可以选复合, 最好优先选择复合, 毕竟private继承有时十分晦涩, 会大大降低代码的可读性, 我们对private继承的使用应当是**明智而审慎**的.

接下我们将说明什么情况下可以选用private继承 : 

- **涉及protected成员/virtual函数时**. 当我们希望继承并重写一些virtual函数或是使用一些protected成员时, 如果我们**不希望它们将基类接口或成员暴露出去**, 就可以采用private继承, 因为其有天然转换为private的属性.

  以下是书中的一个例子, `Widget`想利用`Timer`中的计时机制来实现一些定时触发的机制, 它希望重写其中的`onTick()` : 

  ```cpp
  class Timer {
  public:
    explicit Timer(int tickFrequency);
     virtual void onTick() const;     // Timer每过一段时间就会触发一次onTick()
    ...
  };
  
  class Widget: private Timer {		// private继承
  private:
    virtual void onTick() const;      // 重写Timer中的onTick(), 使其可以定时查看Widget的数据...
    ...
  };
  ```

  这样用户就不可能在外部调用到任何的`onTick`函数(包括基类和派生类的), 毕竟这只是为了实现内部的功能.

- **有极大的空间要求时**. 我们有时会面对一些空间十分有限的情况, 我们会非常希望去节省空间, 那么有一项技术值得我们研究 : 

  先引入一些前提, 我们有些时候会有创建并使用一些**空类**的需求, 目的在于用作类型标识, 占位符, 空对象之类的需求, 这样的需求始终存在并且在现代C++的重要性逐步提升, 比如通过类型表示进行类型推导, 实现在编译期即可进行判断的技术.

  ```cpp
  // 类型标识空类
  class TypeA {};
  class TypeB {};
  
  //通过 if constexpr 在编译时确定类型并执行不同的行为, 提高了运行期效率
  template <typename T>
  void identifyType(T obj) {
      if constexpr (std::is_same_v<T, TypeA>) {   // is_same_v是C++17引入的判断类型是否相同的类型特征
          std::cout << "TypeA\n";
      } else if constexpr (std::is_same_v<T, TypeB>) {
          std::cout << "TypeB\n";
      } else {
          std::cout << "Unknown type\n";
      }
  }
  
  int main() {
      identifyType(TypeA{});  // 输出 "TypeA"
      identifyType(TypeB{});  // 输出 "TypeB"
  }
  ```

  而使用这些空类符合"is-implemented-in-terms-of"的意味, 假设我们就是为了做类型标识, 那么如果我们想赋予一个类对应的类型标识来达到分类的效果, 我们可以让这个类复合或private继承空类来实现, 在这种情况下我们建议优先选择private继承, 这样可以通过继承的类型在编译器做出更多的操作, 并且也减小了对象大小, 这就是所谓的**EBO(空白基类最优化)**.

  简单来说就是复合会增加对象大小(就算是空类也会), 而private继承**完全不会增加大小, 而且还给了我们在编译期的可操作空间**, 我们可以做到以下编译期类型识别的效果 : 

  ```cpp
  // 空类型标识基类
  class TypeA {};
  class TypeB {};
  
  // 派生类，通过private继承不同的空基类来在编译期区分类型
  class MyClass : private TypeA {};
  class AnotherClass : private TypeB {};
  
  //通过 if constexpr 在编译时确定类型并执行不同的行为
  template <typename T>
  void identifyType(T obj) {
      if constexpr (std::is_base_of_v<TypeA, T>) {   // is_base_of_v是C++17引入的判断基类类型的类型特征
          std::cout << "Object is of TypeA\n";
      } else if constexpr (std::is_base_of_v<TypeB, T>) {
          std::cout << "Object is of TypeB\n";
      } else {
          std::cout << "Unknown type\n";
      }
  }
  
  int main() {
      MyClass a;
      AnotherClass b;
  
      identifyType(a);  // 输出: Object is of TypeA
      identifyType(b);  // 输出: Object is of TypeB
  }
  ```

---

### 复合的优势

在上文我们讲了两种建议使用private继承的情况, 那么除此之外我们还是推荐能使用复合就使用复合, 其优势在于 : 

- 可读性高.
- 使用复合对象可以**防止派生类重写其virtual函数**. (private继承不可, 因为就算是private继承也可以重写private的virtual函数, 然后通过基类指针调用, 见条款35)
- 使用复合就可以**使编译依存性降至最低**, 如果继承必须可见定义, 而复合只需声明即可. (详见条款31)

----

### "public继承 + 复合"替代private继承

我们还可以通过"public继承 + 复合"替代一些场景下private继承的作用, 虽然这样会麻烦一些, 但值得我们考量, 我们将上文的Timer案例重写一下 : 

```cpp
class Widget {
private:
  class WidgetTimer: public Timer {
  public:
    virtual void onTick() const;
    ...
  };
   WidgetTimer timer;
  ...
};
```

这个例子中我们创建一个WidgetTimer的内部类, 其public继承自Timer, 其重写了onTick(), 并且我们立马在下面创建一个对应的复用对象, 我们可以发现这个private继承的效果类似, 并且也可以体现上述复合的优势.

当然这只适用于部分情况, private继承肯定还是有用武之地的.

---

### 请记住 : 

- private继承意味着`is-implemented-in-terms-of`. 
- 任何时候都优先选择复合, 除非一些特殊情况下.
- private继承可以支持`EBO`, 并且在C++17中可以继承类型标识空类来实现编译期逻辑判断.



by 天目中云