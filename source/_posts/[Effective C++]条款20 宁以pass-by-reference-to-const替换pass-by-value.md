---
title: Effective C++ 条款20 宁以pass-by-reference-to-const替换pass-by-value
date: 2024-11-30 22:06:54
tag: Effective C++
---

## 条款20 : 宁以pass-by-reference-to-const替换pass-by-value

>本条款将告诉我们函数传参时的最佳策略.

我们都知道, `pass-by-value`(传值传参)是一个费时费力的过程, 它会直接复制一个原件的拷贝, 如果是自定义类就会调用一次拷贝构造来实现复制, 函数结束时还要额外调用一次析构函数, 我们会很有意愿去削减这方面的花销.

相信我们在别处的很多函数中都看见过`pass-by-reference-to-const`的存在, 在本书中也极力推荐这种写法, 足矣见得这种写法的高效与广泛, 就像下面这行函数定义 : 

```cpp
bool validateStudent(const Student& s);
```

reference的底层一般是个指针, 也就是说我们只是用了一个传递指针的花销就实现了参数的传递, 再加上const, 这对我们传入引用的安全性给予了保证,  使得这个写法**兼具了效率与安全**, 是不可多得的好事.

另外书中还给出了一个好处 : **避免对象切割问题**.

我们都知道多态中的动态类型是依靠指针和引用来触发的, 简单来说就是也许某个指针或引用的静态类型是基类, 但是动态类型可以通过实际的赋值来改变, 实现动态类型的绑定, 这点可是一个普通的类对象做不到的. 当我们使用`pass-by-reference-to-const`, 其实也就符合了这种性质, 我们来看代码理解 : 

```cpp
class Window {						// 普通窗口
public:
  ...
  std::string name() const;           // 返回窗口名
  virtual void display() const;       // 窗口显示函数
};

class WindowWithScrollBars: public Window {		// 高级窗口! 它带滚动条!
public:
  ...
  virtual void display() const;		// 对窗口重写
};
```

上面是一对父子类, 下面是分别用两种传值方法的函数 : 

```cpp
void printNameAndDisplay(Window w)         // pass-by-value
{                             
  std::cout << w.name();
  w.display();
}

void printNameAndDisplay(const Window& w)   // pass-by-reference-to-const
{                                           
  std::cout << w.name();
  w.display();
}
```

当我们使用以下的代码 : 

```cpp
WindowWithScrollBars wwsb;
printNameAndDisplay(wwsb);
```

如果我们调用前者, 答案是只能调用基类的`display()`, 因为**对象被切割了**, `wwsb`被强行从派生类被切割成了基类, 这很正常, 传一个对象可没有什么多态的机制.

如果我们调用后者, 结果很成功, 调用的就是派生类的`display()`, 因为`w`虽然静态类型是`Window`, 但由于引用的对象`wwsb`类型是`WindowWithScrollBars`, 所以动态类型绑定为了派生类, 调用就正确了. 说的有些复杂了, 可以宏观理解为`pass-by-reference-to-const`是虚函数机制实现的必要手段.

---

吹了那么久`pass-by-reference-to-const`, 那么就没有什么情况要用`pass-by-value`的吗?

答案是有的, 先看书中给出的最终结论 : **内置类型, STL迭代器, 函数对象推荐用pass-by-value**.

原因很简单, `pass-by-reference-to-const`说到底也就是一个指针的花销, **一些内置类型的花销甚至比指针花销还小**, 而**STL迭代器和函数对象内部也就是一个或几个指针**而已, 差不了多少, 当然也有一部分原因是习惯所致.

有人可能认为只包含小型对象的自定义类型也可以用`pass-by-value`, 这样的想法是有漏洞的.

书中给出了三个原因 : 

1. 对象小不代表**构造和析构函数的花销**就不小, 如果你直接`pass-by-value`一个STL的`set`, 其内部对象也就是几个指针, 是所谓的"小对象", 但是构造和析构的开销就不知道大多少倍了.
2. **某些编译器对待内置类型和自定义类型的态度截然不同**, 编译器很乐意把内置类型对象放进缓存器, 但一个自定义类对象就不会有此般关怀.
3. **一个类创建完后是需要维护的**, 你现在对象小, 不代表以后就不会根据客户需求加入额外的变量, 除非你在一开始就把框架定死了.

因此书中才给出了我们上面的最终结论.

---

### 请记住 : 

- 尽量以pass-by-reference-to-const替换pass-by-value, 前者高效, 安全, 并且有效解决了切割问题.
- 以上规则不适用于内置类型, STL迭代器, 函数对象, 它们适合pass-by-value.



by 天目中云



