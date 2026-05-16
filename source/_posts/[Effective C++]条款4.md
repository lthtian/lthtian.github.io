---
title: Effective C++ 条款4 初始化
date: 2024-11-29 22:05:44
tags: [Effective C++]
---

 ## 条款04 确定对象被使用前已先被初始化

> 本条讨论如何安全高效地实现初始化, 当然也有一些条件奇葩的初始化值得我们去讨论

### 普通变量初始化

```cpp
int x = 0;
cont char text[] = "hello";

double d;
cin >> d;    // 这种也叫初始化
```

### 类内变量初始化 

类内变量的初始化一般就是三种, `类内设置初始值`, `缺省值` , `初始值列表`. 

```cpp
class Stu{
public:
    Stu(const string& name = "小红", const int& age = "17", const string& sex = "女") // 设置缺省值 (次之)
    	:_name(name.c_str())
        ,_age(age)
        ,_sex(sex.c_str())		// 初始化列表 (优先)
    {}
    
private : 
	char _name[10] = "小明";
    int _age = 18;
    char _sex[5] = "男";  // 类内设置初始值 (最次)
}

Stu s1;  					// 小红 17 女
Stu s2("张三", 35, "男");    // 张三 35 男 
```

这里虽然看起来三种方式都可以, 但是只推荐全部使用初始值列表, 当有特别想要设置的默认值时设置缺省值.



### 初始值列表

#### 优势描述 : 

为了描述初始值列表的优势, 请先阅读以下另一版本的构造函数:

```cpp
Stu(const string& name, const int& age, const string& sex)	
{
	_name = name.c_str();
    _age = age;
    _sex = sex.c_str();
}
```

可以看出这样子写构造函数其实和我们写初始值列表的最终结果是一样的, 而且相对直观.

**但是**, 该版本在底层每个变量其实是先进行了一次default的构造, 再进行了一次copy操作, 其本质是`初始化 + 赋值`.

而`初始值列表`在底层只进行了一次copy构造, 比前者高效得多, 本质就是`初始化`.

#### 注意事项 : 

- 最好在初始值列表中初始化所有的成员变量, 这样起码不会忘记没有初始化的变量.
- C++中成员变量的初始化顺序是按照类中声明的次序, 而非初始值列表中的顺序! (如果有继承关系, 基类一定早于派生类初始化)

```cpp
class Example {
public:
    Example(int a, int b)
        : _b(b), _a(a) // 尽管在初始化列表中是_b在前, 但是依旧是先初始化_a
    {}
private:
    int _a; // _a 在 _b 之前声明
    int _b; // _b 在 _a 之后声明
};
// ----------------------------------------------------------//
class Red {};
class Blue {};
class Purple{ // 紫色需要类型为红色和蓝色的变量
public:
	Purple(const Red& red, const Blue& blue)
        :r(red) ,b(blue)
    {}
private:
    Red r;
    Blue b;
};

class Color // Color类存储三种颜色, 并且可以用红蓝配出紫
{
public:
    Color(const Red& red, const Blue& blue)
        :r(red)
        :b(blue)
        :purper(r, b)
    {}
private:
    Red r;           //purple p;
    Blue b;			 //Red r;		
    Purple p;		 //Blue b;	 假如是注释中的情况, 将无法编译通过, 因为p需要r,b都初始化完才能初始化
};
```



### [ 不同编译单元内定义non-local static对象 ] 的初始化次序

初看第一眼根本就不知道是什么东西(再看也不知道), 所以先介绍一下定义:

- 编译单元 : 可以简单理解为一个单独的`.cpp`文件或`.h`文件等, 就是有一定的隔离性.

- `local static`(局部静态变量) : 生命周期为整个程序, **在局部第一次调用时初始化**, 之后都是用这个.

- `non-local static`(全局静态变量) : 生命周期也为整个程序, **程序启动时初始化**, 之后都是用这个.(例如全局变量)

`local static`和`non-local static`的区别简单来看就在于初始化的时机.

---

再举一个例子, 如果我在`a.h`中定义了`class A`, 在`b.h`中定义了`class B`, 又在`c.cpp`中要求使用类型为A和类型为B的`non-local static`变量, 那么这两个变量的初始化次序是怎样的?

答案是**无法判断**, 你看上面的定义, `non-local static`对象都是在程序启动时初始化, C++根本没有手段判断应该先初始化哪个,所以这就是没有定义的行为!

---

说了这么多, 那这样会带来什么隐患呢? 

如果两个编译单元中的类有依赖关系的话, 初始化次序的不确定性就会导致问题!

假如说B类static变量中使用到了A类static变量的话, 如果在`c.cpp`中先初始化了B类static变量, 可是A类static变量还没初始化, 那么就只有报错一条路了. 

---

可能看到这里有人不太理解这种情况有什么应用场景, 那么我在这里引入一个定义 :

- 内置型对象 : 这个对象本身并没有太大意义, 目的是为了引出类中的各种功能性函数, 一般是non-local static的.

**进一步解释** : 有些类中会有许多应用实际场景的方法函数, 如果需要使用这些函数, 就需要客户构造一个类对象,再用这个对象使用函数, 那么我们就干脆在类的头文件中声明一个类对象, 要求使用这个头文件的客户必须记得生成一个对应对象, 而这个对象一般是non-local static的. 

假如有一个钟表类, 内部需要用到一个计时器的类, 于是使用了计时器类的内置对象, 当用户创建一个non-local static类型的钟表类对象时, 你无法确定计时器类的内置对象和钟表类对象哪个先初始化.

```cpp
// TimeKeeper.h   这是一个计时器类
class TimeKeeper
{
public:
    ....
    int GetTime();
    ....
};
extern TimeKeeper tk;
```

```cpp
// Clock.h		这是一个钟表类
#include "TimeKeeper"
......
class Clock
{
public: 
    Clock()
        :time(tk.GetTime()) // 这里用tk获取当前时间来初始化time
    {}
    
private:
    int time;
};
```

```cpp
// user.cpp
#include "Clock.h"
...
Clock clock; // 如果用户设置一个全局变量的Clock类对象clock, 此时无法确定clock和tk的初始化次序!
...
```

#### 解决方法 : 以local static对象替换non-local static对象

这个解决方法用到了设计模式中最经典的`单例模式`的设计思想 : 延迟初始化.

思路简单来说就是, 既然给出一个non-local static对象有风险的话, 我就不给这个non-local static对象了, 我直接使用一个函数, 当客户有使用内置型对象相应需求的时候, 当真正客户调用这个函数时, 才会使用函数内部的代码自己生成一个local static对象供自己使用, 这样初始化次序就有了保障.

更通俗易懂地描述一下, 就是虽然不好直接使用内置型对象, 但是可以把函数返回值当成内置型对象来使用,  因为在函数内生成的对象时是local static对象, 没有初始化次序的问题.

看一看接下来的代码吧 : 

```cpp
// TimeKeeper.h   这是一个计时器类
class TimeKeeper
{
public:
    ....
    int GetTime();
    
    TimeKeeper& tk() // 这里用tk函数替代内置型对象tk
    {
        static TimeKeeper timekeeper;  // 当用户真正调用tk()时, 才会在函数内部生成一个局部静态变量(local static)
        return timekeeper;
    }
    ....
};
```

```cpp
// Clock.h		这是一个钟表类
#include "TimeKeeper"
......
class Clock
{
public: 
    Clock()
        :time(tk().GetTime()) // 这里只是简单地将tk换成了tk(), 从调用对象改为调用函数而已
    {}
    
private:
    int time;
};
```

```cpp
// user.cpp
#include "Clock.h"
...
Clock clock; 
// 设置一个全局变量的Clock类对象clock, 此时一定是clock开始初始化, 当初始化时调用到tk()再进行timekeeper的初始化
...
```

#### 多线程情况下的安全性 : 

书中指明, `内涵static对象`在多线程情况下会带有线程安全的问题, 等待某事发生都会有麻烦.

如果同时调用tk(), 没办法保证只有一个timekeeper生成, 除非用锁, 但那样花销太大得不偿失.

所以我们可以在线程的单线程启动阶段`手工调用`所有的初始化函数(例如tk()), 这样在多线程来临前就可以确保初始化完毕.

---

### 请记住 : 

- 对内置型对象进行手工初始化, C++本身并不会保证正确初始化他们.
- 最好使用初始化列表, 并且排序要和类内的声明顺序一致.
- 如果有跨编译单元的初始化次序问题, 请以local static对象替换non-local static对象.



刚开始写博客, 如有错误感谢指正!

by 天目中云
