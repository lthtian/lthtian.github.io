---
title: Effective C++ 条款1-2
date: 2024-11-29 20:05:44
tags: Effective C++
---

### 条款01 : 视C++为一个语言联邦

> 不像Java对各种资源都进行了整合内聚, C++更像是由四种次语言组合而成的语言联邦, 每种次语言都有自己的规约, 也都有不同的用武之地, 每个都可以给C++这门语言带来独特的优势.
> - #### C  :  C++的基础, 包含指针/内置数据类型等基础思想.

- #### Object-Oriented C++  :  面向对象编程的核心, 实现封装/继承/多态.

- #### Template C++  :  泛型编程.

- #### STL  :  一套template的程序库, 包含各种数据结构与算法.

	这四个方向我们都应熟识掌握, 但是可以给自己这样一个印象 : C++并不是一个一体的语言, 编程时的思想规范应当随你使用C++的对应部分而改变.

---

### 条款02 : 尽量以cnost, enum, inline 替换 #define

>由 '#' 引出的语句一般与C的预处理机制相关, 我们很需要预处理机制中的 #include 和 #ifdef, 前者保证库的引入, 后者可以针对不同的环境进行条件编译, 而 #define 却在语言的发展下显得有些与时代脱节了, 现在我们应当有心减少 #define 的使用.

以下列举 #define 所带来的一些问题:

1. 书写代码时很难自动显示错误
2. 编译错误时显示的信息并不直观
3. #define并不重视作用域, 面向全局生效, 这与我们应当坚持的封装思想相悖

简而言之, 就是#define可能带来一些不可预料的行为并且无法保证类型安全, 而如今我们由足够多的方法可以安全有效地替代#define的功能, 比如const和enum可以替代#define在常量定义上功能, inline又可以替代#define在宏函数上的功能.

#### const 
~~~cpp
#define N 100 			// 这个步骤在预处理阶段实现
const int N = 100;		// 这个步骤在编译阶段实现
~~~
#### enum

```cpp
// 这里我们想定义三元色的对应数值
#define RED = 1
#define GREEN = 2
#define BLUE = 3

enum Color{
    RED = 1, 
    GREEN = 2,
    BLUE = 3
}	// 使用enum枚举类型在增强代码的可读性的同时也提升了可维护性

//-----------------------------------------------------//
enum Action{
    RUN = 0x0001,    // 第一位
    JUMP = 0x0002,	 // 第二位
    SAY = 0x0004,	 // 第三位
    SLEEP = 0x0008	 // 第四位
}	// 使用enum还可以实现比特级别的状态判断

void CheckAction(int action);   // 假设我们有这样一个检查运动状态的函数, 那么我们就可以只接受一个int就可以判断复数的状态
CheckAction(RUN | JUMP | SAY);	// 这里的状态就 跑 + 跳 + 说话
```

#### inline

```cpp
// 加入我们想实现的MAX(a, b), 我们可以通过以下实现
#define MAX(a, b)  (a) > (b) ? (a) : (b)

template<typename T>
inline void MAX(const T& a, const T& b)
{
    return a > b ? a : b;
}
```

我们用模板 + inline就可以完全代替宏函数的作用, 首先inline的书写模式更加自然, 另外还保证了类型安全, 规避了#define的危险性.
