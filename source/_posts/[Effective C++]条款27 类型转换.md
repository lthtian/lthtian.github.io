---
title: Effective C++ 条款27 类型转换
date: 2024-12-6 19:57:12
tag: Effective C++
---

## 条款27 : 尽量少做转型动作

> 优良的C++代码很少使用转型, 但是要完全摆脱它们又太过不切实际, 我们应当保证"类型错误"绝无可能发生. 本条款在了解各种转型动作的前提下, 指出了一些有风险的转型操作及其解决方法.

我们先来回顾一下类型转换 : 

#### 旧式C风格转型

```cpp
(T)expression;
T(experssion);
```

#### 新式转型

```cpp
static_cast<T>(expression)
const_cast<T>(expression)
dynamic_cast<T>(expression)
reinterpret_cast<T>(expression)
```

- static_cast : 强制隐式转换, 适合除常量性移除之外的大部分转换场景.
- const_cast : 唯一可以常量性移除的转换, 而且能且仅能移除常量性.
- dynamic_cast : "安全向下转型", 可以理解为一个有安全类型检查的可以将基类转为派生类的`static_cast`.
- reinterpret_cast : 低级转型, 现在很少用了.

---

书中提出第一个观点 : 除非你确定转型没有任何风险, 并且旧式转型很方便, 应当**始终理智使用新式转型**, 以下为原因 : 

1. 新式转型**很容易在代码中被识别出来**, 有助于编译器或其他工具识别.
2. 新式转型**细化了转型动作的目标**, 使得编译器更容易诊断出错误的运用.

---

#### 避免做出"对象在C++中如何布局"的假设

书中提醒我们, **类型转换并不仅仅是“告诉编译器类型的变化”**, 它是会实际产生额外代码的, 而且有可能对当前对象布局做出调整, 例如将基类指针从原本的指向的基类, 改为指向派生类, 我们也许会认为前者和后者的指针地址是一样的, 实际也确实大多数情况都是一样的(包括我测试的), 但是书中说对象布局方式会依照编译器的不同而不同, 确实会发生前后者指针不一样的情况出现, 而且在出现多重继承是这种情况会更多. 所以作者告诫我们, **"由于知道对象如何布局"而设计的转型, 在某些平台行得通, 在其他平台并不一定**.

---

#### 避免用类型转换写出似是而非的代码

在写GUI时会有定义很多的窗口类, 这种应用框架一般会坚持派生类的重写会先调用父类版本, 于是就有了以下代码 : 

```cpp
class Window {                                // base class
public:
  virtual void onResize() { ... }             // 基类窗口重置尺寸
  ...
};

class SpecialWindow: public Window {          // derived class
public:
  virtual void onResize() {                   // 派生类重写
    static_cast<Window>(*this).onResize();    // 先调用父类版本的onResize()
    ...                                    
  }                                          
  ...
};
```

我们起初看可能还像一回事, 但是实际漏洞百出,  `static_cast<Window>(*this)`这个表达式返回的其实是一个**"*this对象值base class成分"的临时拷贝**! `static_cast`在底层转换类型后进行切分, 然后把切分出来的部分拷贝返回. 也就是说真正调用基类`onResize()`的是这个临时对象, 而不是当前对象的基类部分, 想要真正使当前对象调用基类`onResize()`, 应以如下写法 : 

```cpp
class SpecialWindow: public Window {
public:
  virtual void onResize() {
    Window::onResize();                    // 这样调用
    ...                                   
  }
  ...
};
```

---

#### 谨慎使用dynamic_cast

我们之所以需要`dynamic_cast`, 通常是因为我们手持一个**静态类型是base而动态类型是derived的指针或引用**时, **想要使用只有derived中有的一个普通函数**, 因为其不是虚函数, 所以我们现在无权使用它, 只能依靠`dynamic_cast`来进行较为安全的转换.

假设我们的`SpecialWindow`有一个单独的闪烁功能, 有一个`vector`中存放了大量的`Window`, 我们希望遍历该`vector`, 如果其动态类型是`SpecialWindow`就调用其闪烁功能, 代码如下 : 

```cpp
class Window { ... };
class SpecialWindow: public Window {
public:
  void blink();  // 特有的blink功能
  ...
};

typedef std::vector<std::shared_ptr<Window> > VPW;  // 存放Window智能指针的数组
VPW winPtrs;
...
for (VPW::iterator iter = winPtrs.begin(); iter != winPtrs.end();  ++iter) {
  // dynamic_cast转换成功说明是SpecialWindow类型, psw不为空, 判true, 调用blink
  // 转换失败说明不是, psw为nullptr, 判false
  if (SpecialWindow *psw = dynamic_cast<SpecialWindow*>(iter->get()))
     psw->blink();
}
```

上面算是对`dynamic_cast`的日常用法做了一个介绍, 但是作者告诉你使用`dynamic_cast`在很多情况并不必要, **能不使用dynamic_cast就尽量不使用**, 原因在于`dynamic_cast`为了实现安全性检测和其他一些目的, 效率十分低下, 相比于它的其他几个兄弟效率不只低了一点半点, 除非有**必须是多态情况下用基类使用派生类普通函数的场景**, 我们可以**做出一些让步**来提升我们的效率, 书中给出了两种方法 : 

1. **放弃多态需求**, 确保容器内只有需求派生类的指针.具体来说就是`VPW`内只存`shared_ptr<SpecialWindow>`, 让`blink`的调用普遍化.

   ```cpp
   typedef std::vector<std::tr1::shared_ptr<SpecialWindow> > VPSW; // 只存派生类智能指针
   VPSW winPtrs;
   ...
   for (VPSW::iterator iter = winPtrs.begin(); iter != winPtrs.end(); ++iter)
     (*iter)->blink(); // 直接调用
   ```

2. **将普通函数转为virtual函数**, **略微增加写代码的成本**.

   ```cpp
   class Window {
   public:
     virtual void blink() {}  // 这里什么都不做, 其目的只是为了让SpecialWindow通过多态调用有效果的blink()
     ...
   };                                            
   
   class SpecialWindow: public Window {
   public:
     virtual void blink() { ... };                 
     ...                                          
   };
   
   typedef std::vector<std::tr1::shared_ptr<Window> > VPW;
   VPW winPtrs;                                    
   ...
   for (VPW::iterator iter = winPtrs.begin();
        iter != winPtrs.end();
        ++iter)                                  
     (*iter)->blink();  // 正常的多态用法
   ```

最后总结下来就是, **在出现dynamic_cast需求场景时, 如果代码对效率没有太多需求, 直接使用dynamic_cast, 反之则思考是否能做出上面所说的两种让步, 如果前两种让步的代价实在太高再使用dynamic_cast**.

书中还指出了一种应当杜绝的写法 : 

```cpp
class Window { ... };
class SpecialWindow1 { ... };
class SpecialWindow2 { ... };
class SpecialWindow3 { ... };
...                    
typedef std::vector<std::tr1::shared_ptr<Window> > VPW;
VPW winPtrs;
...

for (VPW::iterator iter = winPtrs.begin(); iter != winPtrs.end(); ++iter)
{
  if (SpecialWindow1 *psw1 =
       dynamic_cast<SpecialWindow1*>(iter->get())) { ... }
  else if (SpecialWindow2 *psw2 =
            dynamic_cast<SpecialWindow2*>(iter->get())) { ... }
  else if (SpecialWindow3 *psw3 =
            dynamic_cast<SpecialWindow3*>(iter->get())) { ... }
  ...
}
```

这样子的代码, 不仅效率低, 而且可维护性差, 最好将这种需求**改写成某种virtual函数**来实现, 不要去依赖`dynamic_cast`.

---

### 请记住 : 

- **尽量避免转型**, 尤其在注重效率的程序中避免`dynamic_cast`.
- 转型并非什么都没做, 会产生实际的花销.
- 如果转型是必要的, **可以把转型过程放在一个函数中**, 让客户调用该函数以实现转型, 而不需要将转型写入他们的代码.
- 最好使用`C++`风格的新式转型.



by 天目中云





