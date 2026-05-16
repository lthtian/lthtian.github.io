---
title: Effective C++ 条款28 避免返回handles指向对象内部成分
date: 2024-12-7 16:52:00
tag: Effective C++
---

## 条款28 : 避免返回handles指向对象内部成分

让我们先来明确本条款中的两个概念 : 

- handle : 即句柄, 号码牌, 可以理解为各种**指针, 引用, 迭代器**.
- 内部成分 : **private成员变量和成员函数**.

有了上面两个概念, 就可以比较直观地理解本条款了, 不过在通读完本条款后, 本条款虽说是**避免返回handles指向对象内部成分**, 但是其实内容着重在解释**在必须返回handles指向对象内部成分的情况下, 会带来什么样的风险**, 以此告诫我们注意. 

---

### 降低对象封装性

书中指出, **返回handles指向对象内部成分**, 随之而来的便是**"降低对象封装性"的风险**, 如果不是有意设计, 我们**不应令public成员函数返回一个handle指向private的成员变量**, 这会使后者的**实际访问级别变为public**, 这是完全可以理解的.

书中描述了GUI中常有的矩形, 它一般会用左上点和右下点表示 : 

```cpp
class Point {                      // 坐标点
public:
  Point(int x, int y);
  ...

  void setX(int newVal);
  void setY(int newVal);
  ...
};

struct RectData {                    // 矩形资源类
  Point ulhc;                        // 左上点
  Point lrhc;                        // 右下点
};

class Rectangle {					// 资源管理类 见条款13
  ...
private:
  std::shared_ptr<RectData> pData;    // 存入智能指针进行管理    
};
```

客户一般会要求使用矩形的位置信息 : 

```cpp
class Rectangle {
public:
  ...
  Point& upperLeft() const { return pData->ulhc; }
  Point& lowerRight() const { return pData->lrhc; }
  ...
};
```

我们用两个函数分别返回左上点和右下点, 这个操作很正常, 但是这给了客户捣乱的方式 : 

```cpp
Point coord1(0, 0);
Point coord2(100, 100);
const Rectangle rec(coord1, coord2);    

rec.upperLeft().setX(50);  // rec的左上点实际被修改为了(50, 0)!
```

这种情况在条款3中也实际发生过, 就是**通过const成员函数的返回值修改了类的内部数据**, 原因条款3中已经解释过了, 解决方式也很简单, 给返回值也加一个`const`就好了 : 

```cpp
class Rectangle {
public:
  ...
  const Point& upperLeft() const { return pData->ulhc; }
  const Point& lowerRight() const { return pData->lrhc; }
  ...
};
```

重新整理思路, 封装性在于**数据隐藏**, 在于**限制外部对内部的访问与修改**. 以上函数做到了**访问权的让渡与修改权的禁止**, 访问权让渡是因为有必要的客户需求, 修改权禁止是应为客户没有权限修改内部, 以此在提供必要功能的前提下使对象达到了最好的封装性.

---

### 空悬句柄(dangling handles)

空悬句柄和C中的野指针很相似, 书中给出了某个函数返回GUI对象的外框(矩形)的例子 :

```cpp
class GUIObject { ... }; 
const Rectangle boundingBox(const GUIObject& obj);  // 返回一个矩形    

GUIObject *pgo;   
...                                  
const Point *pUpperLeft = &(boundingBox(*pgo).upperLeft());  // 这里pUpperLeft是一个空悬句柄                   
```

我们来解释最后一句代码 : 

1. `boundingBox(*pgo)` 利用`pgo`调用`boundingBox`函数
2. `boundingBox`函数返回一个临时矩形对象(这是一个匿名对象, 以下简称`temp`)
3. `temp`调用`upperLeft()`得到该临时对象的左上点
4. 取出右上点的地址赋值给`pUpperLeft`

最后的结果就是`pUpperLeft`获得了一个来自临时对象的指针, 当控制域离开该行, 这个指针将成为一个野指针, 则称`pUpperLeft`是一个空悬句柄, 它指向了一个不存在的对象.

因此书中告诉我们, **返回handles指向对象内部成分总是危险的**, 不管这个`handle`是否为`const` 唯一造成危险的事实就是, **有个handle被传出去了**, 因此就有可能出现**handle比其所指对象更长寿**的风险, 这才是问题的核心.

然而指出这个风险不是说就不应该返回`handles`, 我们总会有许多需求需要访问内部成分, 这种风险避无可避, 而是在告诫我们时常注意空悬句柄问题, **不要让我们的指针/引用/迭代器因为比其所指对象更长寿而失效**.

我们可以再通过一个例子来加深理解 : 

```cpp
vector<int> v = { 1, 2, 3, 3, 5 };
vector<int>::iterator it = v.begin();
while (it != v.end())
{
	if (*it == 3) v.erase(it);
    ++it;
}
```

这个就是非常经典**迭代器失效**问题, 这个例子在遍历`v`, 将`v`中等于3的元素删除, 这段代码看似合理, 但是结合我们上面的理解, 在触发`erase`后, `it`迭代器指向的对象其实已经被销毁了, 这时`++it`就变为了未定义的操作, 在`vs`中甚至会直接报错, 如果我们可以提前发现这个问题, 就可以做出以下改进 : 

```cpp
vector<int> v = { 1, 2, 3, 3, 5 };
vector<int>::iterator it = v.begin();
while (it != v.end())
{
	if (*it == 3) it = v.erase(it);
    else ++it;
}
```

我们利用`erase`的返回值对`it`重新赋值, 使其免于失效.

---

### 请记住 : 

- 尽可能避免返回`handles`指向对象内部成分, 这可以提升对象封装性, 避免`dangling handles`出现.
- 避无可避时谨慎释出内部成分的访问权与修改权, 修改权可用`const`禁止, 注意`dangling handles`问题.



by 天目中云