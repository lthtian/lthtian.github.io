---
title: Effective C++ 条款10-12 拷贝与赋值
date: 2024-11-30 22:06:46
tag: Effective C++
---

## 条款10 : 令 operator= 返回一个 reference to * this

> 很多类都有重写operator=函数的要求,  本质是 = 左侧调用 operator= 函数, 右侧作为参数传入, 将右侧参数赋值给左侧成员变量, 并且为了实现连锁赋值, 我们还应当使 operator= 返回当前赋完值的对象.

本条款的目的是**实现连锁赋值**, 接下来看看如何 令 operator= 返回一个 reference to * this : 

```cpp
Widget& operator=(const Widget& rhs)     // 返回一个引用, 符合右侧参数的类型
{          
    // 条款11, 12会告诉我们怎样实现中间的拷贝过程
    ...
    
  	return *this;                        // 返回=左侧的当前对象, 使其可以充当下一次operator=的右侧参数
}
```

同时这个协议不只适用于 = , 也同样适用于 +=, -=, *= 等运算符.

### 请记住 : 

- 令赋值操作符重载返回一个 reference to * this

---

## 条款11 : 在 operator= 中处理"自我赋值"

> 我们设置一个变量w, 令 w = w , 这种自我赋值的做法虽然看上去很愚蠢, 但是合法, 这种程度的自由还是应该有的, 可是这在我们手动重载operator= 时也会带来相应的麻烦, 有一些我们需要注意的点.

正常来说, 如果我们的类中只有一些普通的本地变量, 其实不必考虑自我赋值的问题, 因为只要把正常情况下的 operator= 函数写好(或者你也可以让编译器自动生成), 是没有什么问题的, 问题发生在**需要动态管理内存**时.

假如我们一个类中有一个成员变量是指针, 该指针指向一块动态分配的内存, 我们创建两个类对象 a 和 b , 其中的指针都指向不同的内存, 当使 a = b, 从正常考量来说, b 赋值给 a 应当代表着 a 的指针将指向原先 b 所指向内存, 那么**原先 a 所指向的内存就应当delete掉**, 以完成最后的赋值操作. 书中举了一个指针指向bitmap的例子 : 

```cpp
class Bitmap { ... };
class Widget {
  ...
private:
  Bitmap *pb; 
};

Widget& Widget::operator=(const Widget& rhs)              // 这是一个有隐患的赋值重载
{
  	delete pb;                                      // delete掉原来指向的动态内存
  	pb = new Bitmap(*rhs.pb);                       // 再new一块用来拷贝rhs副本的空间, pb重新接手这块空间 

  	return *this;                                   // 见条款10
}
```

这段代码看起来很合理, 但是带入自我赋值的情况, 你就会惊奇地发现, new Bitmap(*rhs.pb)用来拷贝的副本 rhs.pb 已经因为 delete pb 被释放了! 我们掉进了"**在停止使用资源之前就意外释放了它**"的陷阱! 虽然自我赋值是愚蠢的操作, 但我们程序员也不能让愚蠢的操作产生愚蠢的错误, 所以我们应当提前判断是否是自我赋值 : 

```cpp
Widget& Widget::operator=(const Widget& rhs)
{
  if (this == &rhs) return *this;   // 判断是否是自我赋值, 是就直接返回
  delete pb;
  pb = new Bitmap(*rhs.pb);

  return *this;
}
```

这样就可以对自我赋值的问题完全规避了! 

---

但是其实由于动态内存的存在, 还催生出了另一个问题, 就是其实new一个对象也会有产生异常的情况出现, 如果申请内存失败, pb就是折了孩子又赔兵, 原先的内存释放了, 新申请的还失败了, 这个问题就是**异常安全性**的问题了, 从原理上来说这和本条款重点针对的自我赋值毫无关联, 但是书中很高兴地告诉我们 : 

- **让 operator= 具备"异常安全性"往往会自动获得"自我赋值安全"的回报.**

因此作者告诉我们可以把焦点放在实现异常安全性上, 对自我赋值问题倾向于不管理. 就是说虽然两个问题毫不相干, 但你解决一个问题却可以顺带解决另一个问题, 何乐而不为呢?

那么如何实现异常安全性呢? 异常安全性会在条款29着重讲解, 但不妨我们提前了解 : 

简而言之就是 : **不泄露任何资源, 不允许数据败坏, 强烈保证如果函数没有成功就回滚到函数被调用前的状态**.

放在本例中, 就是**如何确保new失败后pb可以依旧指向原先的内存, 而不是原先的内存被释放**.

简单思考一下就可以写出如下的代码 : 

```cpp
Widget& Widget::operator=(const Widget& rhs)
{
  Bitmap *pOrig = pb;               // 用一个备份指针记住原先的pb指向的空间先不释放
  pb = new Bitmap(*rhs.pb);         // 令左边pb指向右边pb所指向内存的副本
  delete pOrig;                     // 如果new成功了再释放原先指向的空间

  return *this;
}
```

于是异常安全性的问题就解决啦, 我们还可以发现, 确实自我复制安全的问题也被解决了, 因为pb不会被提前释放, 就算是对着自己再复制一遍也完全没有问题, 唯一的变化就是换了块内存而已.

书中还提出了一种理念相同, 但更推荐的编写方法 : **copy and swap技术**;

简而言之就是 : **如果对某对象的操作有异常风险, 就直接先copy该对象的副本, 在该对象的副本上做出所有操作, 随后swap原件和副本**.

代码如下 : 

```cpp
class Widget {
  ...
  void swap(Widget& rhs); 
  Widget(const Widget& W);
  ...                       
};

Widget& Widget::operator=(const Widget& rhs) // 大多数赋值重载最后用的都是这种方法
{
  	Widget temp(rhs);             // 使用重写的拷贝构造函数直接拷贝副本
  	swap(temp);                   // 交换原件和副本
  	return *this;
}
```

看到这里可能有些人似懂非懂, 前一个函数很明确要在拷贝目标内存成功后就释放原内存, 这个是怎么实现的呢?

这里的拷贝构造函数我们需要重写, 实现对 bitmap 的深拷贝, 拷贝完的对象就是 temp , 由于 temp 是一个临时对象, 离开这个函数的作用域就会析构掉, 此时我们交换原对象和目标对象, 那么最后析构掉的就是存在 temp 中的原对象, 而目标对象留在了我们的当前对象中.

---

### 请记住 :

- 通过实现异常安全性顺便解决自我赋值的问题.
- 确保操作多个对象时, 其中多个对象实质上是同一个对象时, 其行为仍然正确.

---

## 条款12 : 复制对象时勿忘其每一个成分

> copying函数 : 拷贝构造 和 赋值重载(operator=) .
>
> 条款10/11告诉了我们 operator= 如何返回值 和 注意 operator= 自我赋值, 本条款会告诉我们 copying函数 在赋值过程中应当注意些什么.

书中提出, 如果我们决定自己实现 copying函数, 编译器会仿佛被冒犯似的, 以一种奇怪的方式回敬 : 当你的代码必然出错时也不会告诉你. 

这也在警告我们, 复制对象时勿忘其每一个成分.

首先提出的观点是 : 

- **如果你为class添加一个成员变量, 你必须同时修改copying函数**.

这点很好理解, 每个成员变量都必须和拷贝构造和赋值拷贝关联.

接下的观点就涉及继承层面了 : 

- **只要为 derived class 撰写 copying函数, 必须很小心地复制其 base class 成分.**

- **你应当让 derived class 的 copying函数 调用相应的 base class函数.**

我们来看书中的代码来进一步了解这两句话 : 

书中设定了一个`Customer顾客类`, 其派生类是`PriorityCustomer贵宾类`, 贵宾类中local int 变量 `priority`, 用来确定贵宾的优先度.

```cpp
void logCall(const std::string& funcName);  // 用来产生一个日志通告

// Customer 类

class Customer {		// 普通客户
public:
  	...
  	Customer(const Customer& rhs);
  	Customer& operator=(const Customer& rhs);
  	...

private:
  	std::string name;
};

Customer::Customer(const Customer& rhs)
	: name(rhs.name)                                 
{
  	logCall("Customer 拷贝构造被触发");
}

Customer& Customer::operator=(const Customer& rhs)
{
  	logCall("Customer 赋值重载被触发");
  	name = rhs.name;                             
  	return *this;                                  // 见条款10
}

// PriorityCustomer 类

class PriorityCustomer: public Customer {                  // 贵宾客户
public:
   	...
   	PriorityCustomer(const PriorityCustomer& rhs);
   	PriorityCustomer& operator=(const PriorityCustomer& rhs);
  	...

private:
   	int priority;
};

// 重点看这个两个函数
PriorityCustomer::PriorityCustomer(const PriorityCustomer& rhs)
	: priority(rhs.priority)
{
  	logCall("PriorityCustomer 拷贝构造被触发");
}

PriorityCustomer&
PriorityCustomer::operator=(const PriorityCustomer& rhs)
{
  	logCall("PriorityCustomer 赋值重载被触发");
  	priority = rhs.priority;
  	return *this;
}
```

看似`PriorityCustomer`的构造函数好像复制了每一样东西, 但是其实它所**继承的Customer部分并未进行复制**, Customer部分中的name变量仍旧是未定义的, 当我们再仔细看看operator=, 里面的问题是一样的.

接下来是改进后的代码 : 

```cpp 
PriorityCustomer::PriorityCustomer(const PriorityCustomer& rhs)
	: Customer(rhs)                   // 调用 base class 的 copy构造函数
  	, priority(rhs.priority)
{
  	logCall("PriorityCustomer 拷贝构造被触发");
}

PriorityCustomer&
PriorityCustomer::operator=(const PriorityCustomer& rhs)
{
    logCall("PriorityCustomer 赋值重载被触发");

  	Customer::operator=(rhs);           // 对 base class 成分进行赋值动作
  	priority = rhs.priority;

  	return *this;
}
```

这样代码就完美了! 再去回味前面提出的两句话, 其实就是在告诉我们**显式且正确处理基类部分的拷贝和赋值**的重要性.

我们要确保 : 

1. 复制所有的 local 变量.
2. 调用所有 `base classes` 内适当的 `copying函数`.

---

很多时候这两个`copying函数`往往有着近似的实现本体, 这可能会诱使我们用其中一个调用另外一个以实现代码复用的效果, 但是书中告诉我们这样做风险很大, 因为拷贝构造用来初始化新对象, 而赋值重载只能施行于已初始化的对象上, 二者的应用场景就不同, 不然也就不会分成两个默认成员函数了, 所以书中告诉我们 : 

- **你不该令 copy assignment 操作符调用 copy构造函数 .**
- **令 copy构造函数 调用 copy assignment 操作符同样无意义.**

- **真正明智的做法是将相近代码封装进 init() 函数, 给二者调用.**

---

### 请记住 : 

- `copying函数`应当确保复制 "对象内的所有成员变量" 及 "所有`base class`成分".
- 不要尝试`copying函数`相互调用, 应当封装一个共用函数实现代码复用.



by 天目中云