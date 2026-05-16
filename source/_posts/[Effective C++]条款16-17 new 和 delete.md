---
title: Effective C++ 条款16-17 new 和 delete
date: 2024-11-30 22:06:51
tag: Effective C++
---

## 条款16 : 成对使用new和delete时要采用相同形式

直接看代码 : 

```cpp
std::string *stringPtr1 = new std::string;
std::string *stringPtr2 = new std::string[100];
...
delete stringPtr1;                     
delete [] stringPtr2;
```

这个其实没什么好说的, 其实就是相对应就行.

---

## 条款17 : 以独立语句将newed对象置入智能指针

在条款15我们知道C风格API喜欢直接调用原始资源, 那么我们来看一个不用直接调用原始资源的API : 

```cpp
void processWidget(std::tr1::shared_ptr<Widget> pw, int priority);
```

这个函数用来在某动态分配的Widget上进行某些带有优先权的操作, 所以需要传入一个智能指针和一个优先度, 那么现在**假定去求优先度其实是一个很复杂的过程**, 我们需要额外封装一个函数来返回求得的优先度 : 

```cpp
int priority();
```

那么我们设想的调用`processWidget`的方法可能是这样的 : 

```cpp
processWidget(new Widget, priority());
```

这里的`priority()`函数嵌套是没有问题的, 我们日常中也推荐多用这种手法, 但是前面的new就有问题了, 因为`shared_ptr`不支持隐式转换, 也就是无法通过`new`出一个`Widget*`再转换成`shared_ptr<Widget>`, 那么下面的修改是否合理 : 

```cpp
processWidget(std::tr1::shared_ptr<Widget>(new Widget), priority());
```

一眼看上去非常合理, 但是还是有一些隐患在其中, 我们知道`priority()`是一个很复杂的过程, 既然复杂就有可能会抛出异常, 抛出异常本身并不可怕, 我们可以设置对应的处理逻辑, 但是在这样的调用发生异常就有额外的问题了.

问题核心在于**C++在函数参数的调用上弹性很大, 并不确定实际的调用步骤** , 真正的调用步骤由编译器选择效率最高的步骤.

我们先来看看按顺序会发生什么 : 

- 执行 `"new Widget"` 表达式
- 调用`shared_ptr`构造函数
- 调用`priority()`

虽然我们确定执行 `"new Widget"` 表达式一定在调用`shared_ptr`构造函数之前, 但是我们确实不确定`priority()`的调用时机 : 

- 执行 `"new Widget"` 表达式
- 调用`priority()`
- 调用`shared_ptr`构造函数

如果是这样的话, 在priority()调用过程中发生了异常, 就算之后异常得到了处理,` "new Widget"`得到的资源也很大可能是被泄露了.

这一切的问题来源于**在"资源被创建"和"资源被转换为资源管理对象"两个时间点之间有可能发生异常干扰**.

解决方法很简单, 那就是标题 : **坚持以独立语句将newed对象置入智能指针**, 这样就可以杜绝一切异常干扰了.

```cpp
std::shared_ptr<Widget> pw(new Widget);  
processWidget(pw, priority()); 
```

于是以上操作就没有任何问题了!

---

### 请记住 : 

- 成对使用`new`和`delete`时要采用相同形式.
- 以独立语句将`newed`对象置入智能指针.

by 天目中云