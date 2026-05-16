---
title: Effective C++ 条款29 异常安全性
date: 2024-12-8 20:10:00
tags: [Effective C++, 异常安全]
---

## 条款29 : 为"异常安全"而努力是值得的

> 异常安全性是我们每个程序员都要考量的内容, 我们有必要知道我们写出的每个函数保证了怎样的异常安全, 因为一个函数是否会抛出异常不仅会影响我们是否使用该函数的决策, 也会影响部分的编译器优化策略, 让我们通过本条款来充分认识异常安全性.

先了解本条款的例子, 假设有个`class`用来表现夹带背景图案的GUI界面, 这个`class`用于多线程环境, 所以它有个互斥器作为并发控制之用 : 

```cpp
class PrettyMenu {
public:
  ...
  void changeBackground(std::istream& imgSrc);           // 用来改变背景图片的成员函数

private:

  Mutex mutex;                    // 互斥器

  Image *bgImage;                 // 当前的背景图像
  int imageChanges;               // 背景图像被改变的次数
};

void PrettyMenu::changeBackground(std::istream& imgSrc)
{
  lock(&mutex);                      // 上锁

  delete bgImage;                    // 释放原背景
  ++imageChanges;                    // 更新计数
  bgImage = new Image(imgSrc);       // 修改新背景

  unlock(&mutex);                    // 解锁
}
```

从异常安全性的角度来看, `changeBackground`非常糟糕, 它并没有满足"异常安全"的两个必要条件 : 

- **不泄漏任何资源**. 

  资源泄漏包括内存/文件句柄/`socket`连接/锁等泄漏, 这里我们知道`new Image(imgSrc)`是一定可能有`bad_alloc`的异常的, 当异常发生, `unlock(&mutex)`语句将不会执行, 锁并没有得到释放, 也就是说发生了泄漏.

- **不允许数据败坏**.

  数据败坏即数据与预期的有效状态不符, 比如野指针. 这里当`new Image(imgSrc)`处发生异常, `bgImage`的原资源已经释放却没有获得新资源, 它的行为是未定义的, 并且`imageChanges`也增加了一次本不存在的计数, 这都是数据败坏.

---

### 利用资源管理类解决资源泄漏

当我们深谙条款13"**以对象管理资源**"的道理后, 资源泄漏将不再是问题! 资源管理类可以确保资源及时且自动地释放, 并且还减少了我们的代码量, 于是我们就可以用条款14中`RAII`风格的`Lock`类来解决本条款的锁泄漏 : 

```cpp
class Lock {
public:
  explicit Lock(Mutex *pm)
  : mutexPtr(pm)
  { lock(mutexPtr); }                          // 获得资源
  ~Lock() { unlock(mutexPtr); }                // 释放资源
private:
  Mutex *mutexPtr;
};

void PrettyMenu::changeBackground(std::istream& imgSrc)
{
  Lock ml(&mutex);                // 自动管理锁的释放
  delete bgImage;
  ++imageChanges;
  bgImage = new Image(imgSrc);    // 一旦触发异常离开函数作用域就会自动触发Lock的析构函数释放锁
}
```

绝大多数异常引发的资源泄漏都可以用资源管理类来解决.

---

### 三种异常安全保证

这将是本条款的重点, 一个异常安全的函数在避免资源泄漏之后, 为了防止数据败坏, 我们还必须拥有下面三个保证之一, 越往后保证强度越大.

- **基本承诺** : 异常抛出后, 没有数据泄漏, 没有数据败坏, 所有事物仍然保持有效, 但是不支持完全回滚, 我们不确定数据在该函数中修改成什么样了, 即使这种状态合法, 其实就是符合**两个必要条件但是不做任何处理**. 我们看以下的例子理解 : 

  ```cpp
  void addElement(vector<int>& data) {
      for(int i = 1; i = 10; i ++ )
          data.push_back(i); // 如果此处抛出异常，vector 自动管理内存，无泄漏
  }
  ```

  该例子符合基本承诺, 这个函数向`data`中插入1到10, 插入动作会抛出异常, 但是`vector`会自动管理内存, 不会有泄漏与数据败坏, 但是加入我们在插入`i = 5`时出现异常, 那么异常抛出将不会执行之后的语句, 也就是说这次插入的结果是`data`尾插了1,2,3,4, 然而出现异常后客户并不会知道内部到底插入了多少, 虽然该状态合法.

- **强烈保证** : 如果异常被抛出, 对象状态不会改变, 与调用该函数前状态一致. 就是说, 没有异常就是完全成功, 抛出异常对象状态会发生**回滚**, 回滚至调用前状态. 

- **不抛掷保证** : 承诺绝不抛出异常. 这种函数不可能涉及任何动态内存的分配, 一般只是对**内置类型**进行操作, 如算术类型, 指针, 引用等.并且这种函数我们一般会在其函数定义后添加`noexcept`关键字, 这代表你向编译器声明这个函数绝不会抛出异常, 编译器就会删去对这个函数的异常处理工作, 实现效率的提升.

---

### 实现强烈保证

我们一般都是由下至上选择安全保证, 不抛掷保证只适用于对内置类型的操作, 比较典型的就是移动构造和移动赋值.

所以大多数情况下我们更愿意实现强烈保证, 我们来看看将`changeBackground`修改为强烈保证的步骤 : 

1. 将`bgImage`这个成员变量用智能指针代替, 这个只是为了实现两个条件中的避免资源泄漏.
2. 重新改变语句顺序, **不要为了表示某事件的发生而改变对象状态, 除非那件事真的发生了**.

```cpp
class PrettyMenu {
  ...
  std::shared_ptr<Image> bgImage; // 改用智能指针
  ...
};

void PrettyMenu::changeBackground(std::istream& imgSrc)
{
  Lock ml(&mutex);
  bgImage.reset(new Image(imgSrc));  // 以 new Image(imgSrc) 的结果设定为bfImage的内部指针
    								 // 无需delete原资源, reset内部会帮我们自动调用delete	
  ++imageChanges;
}
```

分析上述代码, 我们可以很惊喜地发现, 如果`new Image(imgSrc)`失败, 对象状态将不发生任何改变, `reset`和`++imageChanges`都不会触发,  也就是说失败即回滚, 成功即完全, 再加上不会资源泄漏与数据败坏, 其符合强烈保证!

---

### copy and swap

上文我们通过**调整语序**来实现了强烈保证, 这确实是最基础的一种解决方法, 其内核在于"**在所有可能抛出异常的动作成功结束前不要改变对象状态**", 但是这种做法比较费脑, 并且不一定适合某些场景. 然而有一个**一般化的设计**很典型地会导致强烈保证, 这个策略被称为`copy and swap`.

使用方法很简单, **为你打算修改的对象做出一个副本, 在那个副本上做任何的修改, 待所有改变成功后再交换原对象和副本**(注意这个做法的前提建立在`swap`是`noexcept`的, 这也是为什么条款25一直强调`swap`不抛异常的重要性). 其内核在于"**修改对象数据的副本, 然后在一个不抛异常的函数中将数据和原件置换**".

在看代码之前, 有一个手法很适合实现上述操作, 叫做**pimpl idiom**(pointer to implementation idiom)(指针指向实现), 这个手法在于将所有需要隐藏的成员变量和成员函数包入一个**实现类**, 外部构造一个**接口类**, 该接口类存放该实现类的指针(一般是智能指针)与外放接口. 条款31将详细描述该手法的优势, 在本条款就是将**所有"隶属对象的数据"从原对象放进另一个对象内, 然后赋值原对象一个指针, 指向该对象**, **这样我们copy and swap的对象就仅限于存放数据的对象, 而一切操作都在原对象中进行**.

```cpp
struct PMImpl {                               // 实现类
  std::shared_ptr<Image> bgImage;        
  int imageChanges;                           
};

class PrettyMenu {							  // 接口类
  ...
private:
  Mutex mutex;
  std::shared_ptr<PMImpl> pImpl;			  // 一个智能指针指向实现类
};

void PrettyMenu::changeBackground(std::istream& imgSrc)
{
  using std::swap;                            // 见条款25
  Lock ml(&mutex);                      	  // 锁的copy and swap是没有意义的
  std::shared_ptr<PMImpl> pNew(new PMImpl(*pImpl)); // 复制副本

  pNew->bgImage.reset(new Image(imgSrc));     // 对副本进行所有修改
  ++pNew->imageChanges;

  swap(pImpl, pNew);    // 只有前面不抛异常才会到这里, 直接进行交换, 内置类型的交换一定不会有异常
}                                     
```

以上便通过`copy and swap`实现了强烈保证.

---

### 实现强烈保证的最终策略

`copy and swap`策略是**对对象状态做出"全有或全无"改变**的一个很好办法, 但是它**不等于一个函数有强烈保证**.

分析起来比较麻烦, 简单说就是`copy and swap`**只确定了内存相关操作的强烈保证, 使对象的局部状态有了一致性**, 即"全有或全无", 然而有时候对象其实是会对"**非局部性数据**"产生影响的, 例如数据库连接, 网络连接, 锁等, 这些东西不会只因为内存数据的有无而生效或失效, 连接还和连接的对象有关, 锁还和线程分配有关, 它们更偏向于全局状态, 这也是上面代码我没有将`Lock ml`存入`PMImpl`的原因.

再讲一个例子, 假设我在函数中创建的副本上对**数据库**进行了修改, 如果之后发生了异常, 如果我不做任何其他的操作, 那么这个数据库的修改是一直成立的, 并没有因为`copy and swap`而回滚, 这是完全可以理解的, 代码如下 : 

```cpp
void modifyDataAndDatabase(std::vector<int>& localData, Database& db) { // 修改局部数据与数据库
    
    std::vector<int> localDataCopy = localData; // copy 创建局部状态的副本

    // 修改数据库（非局部数据）
    db.updateRecord("key", "value");
    
    for (int i = 0; i < 10; ++i) {
        localDataCopy.push_back(i);   // 如果此处发生异常, 前面的数据库修改无法恢复!
    }
    swap(localData, localDataCopy);
}
```

因此, 我们可以总结出可以实现强烈保证的大体策略 :

- **如果函数有关内存数据的修改, 使用`copy and swap`策略.**
- **如果函数有关非局部数据的修改, 自己根据非局部数据的性质进行对应的异常回滚操作.**

例如上文的数据库, 我们就可以利用其**事务**的特性实现异常回滚 : 

```cpp
void modifyDataAndDatabase(std::vector<int>& localData, Database& db) {
    std::vector<int> localDataCopy = localData;
    db.beginTransaction(); // 开启数据库事务

    try {
        db.updateRecord("key", "value"); // 修改数据库数据
		
        for (int i = 0; i < 10; ++i) {
            localDataCopy.push_back(i);  // 此刻发生任何异常都会被捕获, 在catch语句中触发回滚
        }

        db.commitTransaction(); // 所有修改成功后，提交事务
        std::swap(localData, localDataCopy);
    } catch (...) {
        db.rollbackTransaction();  // 发生异常时，回滚事务
        throw;
    }
}
```

于是`modifyDataAndDatabase`函数也就拥有了强烈保证, 这部分的最终策略是我求证后自创的, 书中没有详细指出如有问题或补充欢迎指出.

---

### 关于嵌套函数的问题

书中指出, 嵌套函数会确实影响函数本身的异常安全性, 道理也很容易理解, 一个没有强烈保证的函数被嵌入一个函数, 那么这个函数也一定没有强烈保证. 然而**所有嵌套函数都是强烈保证的就能使本函数有强烈保证了吗, 未必!** 让我们看下面的函数 : 

```cpp
void someFunc() {
    ...                // 创建副本
    f1();              // 调用 f1 当成调用 modifyDataAndDatabase(localData);
    f2();              // 调用 f2
    ...                // 将修改后的副本交换到原状态
}
```

现在我们把`f1`当成上文的`modifyDataAndDatabase`, 仔细想想有什么问题.

大佬可能一眼就看出来了, 虽然`f1`的本身有强烈保证, 但是如果`f2`抛出了异常, `f1`中对`localData`的修改固然可以因为`copy and swap`回滚, 但是数据库的修改不能呀, 我们在`f1`中的数据库回滚操作无法延申到`f2`中! 所以无法实现完全的回滚, 这个函数是没有强烈保证的!

这种问题书中叫做"**连带影响**", 即当一个函数对"非局部性数据"有影响时, 其被嵌套在其他函数内部时, 就算本身有强烈保证, 也会因为外部可能的异常连带产生错误. 

这个问题提醒我们一个函数如果想有强烈保证, 不要嵌套影响"非局部数据"的函数, 非要嵌套也要确定其后没有任何异常产生的可能性.

---

### 异常安全性就像怀孕 . . .

作者提出, 一位女士若非怀孕, 就是没怀孕, 不可能说她"部分怀孕"; 同理, 一个系统内如果有一个函数不具备异常安全性, 整个系统就不具备异常安全性, 很不幸, C++由于对C的继承, 其很多传统代码其实是不具备异常安全性的, 不过我们应当尽力让我们的代码具备异常安全性, 同时也**应当将自己对函数的安全性定义写成文档, 为我们的客户和后期维护者使用**.

---

### 书中作者难得发出感叹, 由此摘录: 

四十年前, 满载goto的代码被视为一种美好实践, 而今我们却致力于写出结构化控制流.

二十年前, 全局数据被视为一种美好实践, 而今我们却致力于数据的封装.

十年前, 撰写"未将异常考虑在内"的函数被视为一种美好实践, 而今我们却致力于写出"异常安全码".

---

### 请记住 : 

- "以对象管理资源"可以阻止资源泄漏, 调整语序和三种异常保证可能可以阻止数据败坏.
- "基本承诺"诚可贵, "强烈保证"价更高, 若为"不抛掷", 二者皆可抛.



by 天目中云