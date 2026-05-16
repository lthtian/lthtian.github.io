---
title: Effective C++ 条款3 const
date: 2024-11-29 21:05:44
tags: [Effective C++]
---

## 条款03 : 尽可能使用const

>`const`(不可被改动), 是一种非常有效且多样的语义约束, 有了这项约束, 我们可以借用编译器之手规范我们的代码, 以免带来意想不到的错误, 毕竟任何的改动都会伴随着一定的风险, 如果可以提前规避, 我们何乐而不为呢? 

`const`在实际表现上是多才多艺的, 他可以修饰对象, 对象指针, 甚至成员函数, 接下来逐一介绍 :

### const 修饰变量

```c++
const int N = 200010; // 这样子定义的N又被称为常变量, 其实也就是常量了(因为不可被改动)
```

### const 修饰指针

```c++
char arr[] = "hello"; 			// 众所周知, arr数组名是一个指针
char* a = arr;					// a指针可修改, 指针指向的内容可修改
const char* b = arr;			// b指针不可修改, 指针指向的内容可修改
char* const c = arr;			// c指针可修改, 指针指向的内容不可修改
const char* const d = arr;		// d指针不可修改, 指针指向的内容不可修改
```

谈到指针就不可避免的就会想到` 迭代器`, 毕竟`迭代器`就是指针的封装嘛.

```c++ 
//看看下面两种迭代器的定义, 就可以对应上面指针的情况
const vector<int>::iterator iter = v.begin(); 
// 迭代器本身是const的, 也就是说本身不可修改, 相当于指针在*前加const
// 此时无法进行 ++iter 等操作

vector<int>::const_iterator citer = v.begin();
// 语言自带的const_iterator本身就是为了对迭代器指向的内容设置只读, 本身可以进行运算操作, 相当于在*后加const 
```

### const 修饰成员函数

>先明确`const`成员函数的意义 : 告知编译器这个函数内部的对象不应被改动.
>
>不是说明函数本身不可改动!!!

- 那么对成员函数声明`const`的意义何在?

1. **使这个函数接口更容易被理解**, 一个函数是否可以改变类内变量的具体数值会很大程度上影响我们对这个函数的定位判断.
2. **使操作`const`对象成为可能**, 首先我们要明晰`const`对象是什么, 就是类定义出的`const`对象(例如 const Stu stu(小明, 18);), 当我们声明一个类对象为`const`时, 这个对象对象只能调用`const`成员函数, 调用的任何`non-const`成员函数都无法通过编译的, 因此如果你所设计的类有需求`const`的情景时, 请设计`const`成员函数.

---

- 这里书中给出了一个事实 : **两个成员函数如果只是常量性不同(const / non-const), 也可以被重载.**

​	这其实就告诉我们如果想要适配`const`版本的话, **non-const版本和const版本各写一个就好了**, 编译器会根据对象是否为`const`来选择使用哪个函数, 样例如下:

```c++
class TextBlock {
public:
 ...
 const char& operator[](const std::size_t position) const  // 1
 	{ return text[position]; }							   // 2
 char& operator[](const std::size_t position)
 	{ return text[position]; }
private:
   std::string text;
};

TextBlock tb("hello");
const TextBlock ctb("hello");
cout << tb[0];				// 调用函数2
cout << ctb[0];				// 调用函数1
```



---



- 接下来需要介绍两种对` 成员函数为const`时应有行为的流派概念:

#### bitwise const :

​	这个流派认为如果一个成员函数为`const`, 应当**不改变对象中的任何变量**, 也就是物理上没有1bit被改变.

#### logical const :

​	这个流派认为如果一个成员函数为`const`, **可以改变对象中的某些变量**, **但是不能对对象的主要逻辑产生影响**, 也就是说对象在逻辑上没有被改变, 改变的部分只是起辅助优化作用, 例如修改日志, 对计算结果进行缓存, 记录当前容器大小等, 这些工作对主逻辑并没有任何影响, 却可以大大提高主逻辑的工作效率.



---



- 那么C++实际上是怎么定义`const`成员函数的行为的呢?

​	C++在**一般情况下的定义按照`bitwise const`的规则进行**, 也就是说一个`const`成员函数无法改变对象中任何变量.

​	但是这其中有一个C++本身不好决断的情况需要了解 :

​	还记得上面代码中定义的[]重载函数吗 ? const char& operator[](const std::size_t position) const 

​	假如我把返回值改为char& : char& operator[](const std::size_t position) const

​	那么这样就会产生一个奇怪的情况 :

```c++
class TextBlock {
public:
 ...
char& operator[](const std::size_t position) const  
 	{ return text[position]; }							   
private:
   std::string text;
};

const TextBlock ctb("hello");
char* pc = &cbt(0);					// 返回的指针没有const
*pc = 'j';							// "hello"被变成了"jello"!!!
```

​	通过以上的情况我们可以发现, C++虽然确保在`const`成员函数内部不会改变任何对象, 但是并不会检查返回对象所指向的内容是否是不可改变的, C++可能认为在函数外的行为是程序员的自由吧, 所以我们应当注意这一点.

---



- 那么问题又来了, 既然`logical const`也有其道理所在, C++是如何解决的呢?

​	C++引入了一个与`const`相关的摆动场 : **mutable(可变的).**

​	`	mutable` 的主要用途是在 `const` 成员函数中允许对特定成员变量的修改, 这样`logical const`的诉求就可以满足了。

​	请阅读以下代码 : 

```c++
class text {
	
public:
	//...
        
	size_t updateLength() const
	{
		if (!lengthIsValid)
		{
			// 以下两句就是因为mutable得以通过
			length = pText.size(); // 重新更新text的长度
			lengthIsValid = true;  // 定义当前length可用
		}
		return length;
	}
	    
private:
	string pText;

	// mutable 关键字可以使某个成员变量在const成员函数被修改
	// 作用是在不改变内部变量的基础逻辑的情况下, 可以引入少量变量可以被改变, 丰富逻辑
	// 保证函数的安全, 使用mutable意味着在const成员函数中只能改变mutable变量, 其他变量不会被改变
	mutable size_t length;
	mutable bool lengthIsValid;
};

```

​	以上代码将`lenth`和`lengthIsValid`赋予`mutable`特性, 使其在`const`成员函数中可以改变, 从而可以用非常小的代价更新`text`的长度, 方便其他需要使用text长度的函数, 这两个变量均对`text`存储字符串的主逻辑没有影响.

---

​	最后还有一个比较有价值的观点 : 我们知道要适配`const`版本需要写两个类似的函数, 一个处理`const`对象, 一个处理`non-const`对象, 但是我们也应当发现这两个函数其实非常相似, 那么这就带来了一些问题:

1. **代码重复**, 这会带来阅读性降低, 维护成本提高的负面作用.
2. 我们在以后的条款学习中会知道, 编译器一般会把成员函数替换为`inline`函数, 这在一般情况下肯定是更高效的, 但是`inline`函数中的代码越多, 会带来一系列如代码膨胀之类的问题, 这点我们应当避免.

- 书中提出了这样的解决方案 : **令`non-const`版本调用`const`版本**.

​	这样子做的前提是两个版本的内容一定相等, 或者说`non-const`版本不能修改对象内的变量, 毕竟如果修改了那和`const`版本就一定不一样了, 我们来改写上面[]重载的两个版本.

```c++
const char& operator[](const std::size_t position) const  
{ 
    //我们假定[]重载在返回下标引用之前还要做许多工作, 代码量巨大
    // ...	边界检验
    // ...	将数据访问的行为加入日志
    // ...	检验指向内容数据的完整性
    return text[position]; 
}	

char& operator[](const std::size_t position)
{ 
    // 这段代码实现了两次类型转换, 目的是调用const版本的operator[]函数并返回non-const的char&
	return const_cast<char&>(static_cast<const text&>(*this)[pos]);
    /* 我们把这段代码拆分开来解读
    return const_cast<char&>(   		 // 3. 将[]返回结果由const版本通过const_cast转换为non-const版本
        static_cast<const text&>(*this)  // 1. 先将this指针通过static_cast转换为const text&
        [pos]							 // 2. const text&类型调用[]重载, 自然使用的是const版本的[]重载
    );
    */
}
```

​	经过以上的操作, 无论`const`版本需要多少行代码, `non-const`版本都只需要一行代码即可, 相当实用.

​	另外如果在`non-const`版本虽然和`const`版本十分相似, 但是还是想要修改一部分的数据, 也可以在调用完重载版本后不返回, 再进行一些修改操作再返回.

- 小问题 : 为什么不用`const`版本调用`non-const`版本?  因为`non-const`版本不会限制修改行为, 无法监督`const`实现.

---

## 请记住

- 将某些东西声明为`const`可以帮助编译器检查出错误语法, `const`可被施加于任何对象, 函数参数, 函数返回值, 成员函数
- C++在`const`成员函数定义上默认支持`bitwise const`流派, 但是也通过关键字`mutable`变相支持了`logical const`流派
- 当`non-const`版本和`const`版本等价实质时, 可以用`non-const`版本调用`const`版本



作者 : 天目中云





