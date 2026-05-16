---
title: Effective C++ 条款15 在资源管理类中提供对原始资源的访问
date: 2024-11-30 22:06:50
tag: Effective C++
---

## 条款15 : 在资源管理类中提供对原始资源的访问

> 我们将资源存入资源管理类, 为的是可以免去资源管理的麻烦, 但同时我们也希望**可以正常合理地通过资源管理类来使用资源, 就像直接使用资源一样**, 为此我们一定需要在资源管理类中提供对原始资源的访问;

我们先来解答一些疑问 : 

- #### 为什么要对原始资源进行访问(为什么要获取原始资源的指针)?

  有时候需要我们传递原始资源的指针, 因为很多`C API`都是要求传递原始指针才能运作.

- #### 如何进行资源访问呢?  

  **显式转换** 或 **隐式转换** . 

---

**显示转换** : 资源管理类直接提供一个返回原始资源的`get()`函数, `C++`提供的智能指针也提供相应的功能.

书中举了一个有关字体资源管理的例子, 代码如下 : 

```cpp
class Font {                           // 对于FontHandle的资源管理类
public:
  	explicit Font(FontHandle fh) :f(fh) {}                                   
  	~Font() { releaseFont(f); }         
    
    FontHandle get() const { return f; } // 直接显示调用该函数即可获得该资源

private:
  	FontHandle f;                        // 原始的字体资源指针
};
```

假设有一个`C API`可以通过接受字体资源和字体大小来改变字体 :

```cpp
// 这是函数
void changeFont(FontHandle f, int newSize);     // C风格的API函数
// 以下是用户具体使用例子
Font f(getFont());
int newFontSize;
...
changeFont(f.get(), newFontSize);	// 使用f.get()
```

---

**隐式转换** : **提供operator->和operator*的重载** 或 **直接提供隐式转换函数**

前者支持将资源管理类指针隐式转换为底部原始指针, 以此可以直接调用资源函数或取出资源成员变量 : 

```cpp
class Font {                           // 对于FontHandle的资源管理类
public:
  	explicit Font(FontHandle fh) :f(fh) {}                                   
  	~Font() { releaseFont(f); }         
    
    FontHandle get() const { return f; } // 直接显示调用该函数即可获得该资源
    
    // 重载 operator->，返回原始的 FontHandle 指针
    FontHandle* operator->() {
        return &f;  // 返回 FontHandle 的指针，允许访问 FontHandle 的成员
    }

    // 重载 operator*，返回对 FontHandle 的引用
    FontHandle& operator*() {
        return f;  // 返回 FontHandle 的引用，允许访问 FontHandle 的成员
    }

private:
  	FontHandle f;                        // 原始的字体资源指针
};
```

这样我们就可以完全将资源管理类当做一个指针看待, **通过*取出原始资源, 通过->调用原始资源的成员**.

```cpp
changeFont(*f, newFontSize);  // 假装f是一个指针, 通过解引用调出资源
```

---

后者在使用资源管理类时就会默认转换到底部原始指针 : 

```cpp
class Font {                           // 对于FontHandle的资源管理类
public:
  	explicit Font(FontHandle fh) :f(fh) {}                                   
  	~Font() { releaseFont(f); }         
    
    operator FontHandle() const { return f; }        // 隐式转换函数

private:
  	FontHandle f;                        // 原始的字体资源指针
};
```

这样直接写f就行了 : 

```cpp
changeFont(f, newFontSize);
```

但是书中并不推荐这样使用, 因为这是一种**完全把资源管理类作为原始资源**的做法, 也就是说**无法再使用有关任何资源管理类自己的操作**, 当我们想进行资源管理类的拷贝赋值等操作时, 由于已经隐式转换为了资源, 这样做几乎不会有好下场, 当然你也可以保证完全不使用也不设计这类操作, 让它单独做好资源管理的本职工作, 也是完全可以使用这种方法的.

---

### 请记住 : 

- `API` 往往要求访问原始资源, 所以**每个资源管理类都应提供一个取得其原始资源的方法**.
- 对于原始资源的访问, 显示转换一般比较**安全**, 但隐式转换对客户比较**方便**, 自己斟酌利弊.

