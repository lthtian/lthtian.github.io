---
title: Effective C++ 条款31 编译依存性
date: 2024-12-11 15:32:00
tags: [Effective C++, 编译依存性]
---

## 条款31 : 将文件间的编译依存关系降至最低

> 本条款将带我们认识文件编译依存的问题, 以及解决问题的两个有效手段.

### 问题引入

问题的根源来自C++并没有把**"将接口从实现中分离"**这事做得很好, 简单来说, 由于C++本身机制与定位的原因, 为了达到更大的效率和可扩展性, C++引入`inline`和`template`等特性, 这些特性无不需要在头文件中发挥作用, 也就代表原本只应该存放声明的头文件会加入太多的实现细目, 也就是所谓的"没有把将接口从实现中分离这事做得很好".

这带来的问题是既然**很多定义在头文件里**, 一旦我们要修改这些定义, 那么所有使用了这个头文件的所有客户(头文件)就都需要重新编译, 一环嵌一环, 最后需要的**编译成本就非常高**了, 这在书中被称作**"连串编译依存关系"**.

---

### 进一步解析

`inline`和`template`无可厚非, 这是为了效率我们必须要让步的地方, 但是许多**成员变量**也会定义在类的定义式中, 这就有我们处理的余地了, 看看以下代码 : 

```cpp
#include <string>
#include "date.h"
#include "address.h" // 必须包含下方相关类的头文件

class Person {
public:
  Person(const std::string& name, const Date& birthday,
         const Address& addr);
  std::string name() const;
  std::string birthDate() const;
  std::string address() const;
  ...

private:
      std::string theName;        // 名称定义
      Date theBirthDate;          // 生日定义
      Address theAddress;         // 地址定义
};
```

这是一个人的抽象类型, 里面有三种不同类型的成员变量, 我们可以设想到的是, 只要`Date`和`Address`的内部定义发生变化, 就一定会连串导致`Person`重新编译, 然后使用`Person`的客户也需要重新编译.

部分语言的解决方式是直接在底层处理成指针, 这样到哪里都是原生指针的大小, 就无需通过引入头文件知道其大小, 于是可能处理成如下定义 : 

```cpp
std::string* theName;        
Date* theBirthDate;   
Address* theAddress;
```

这样就不需要引入头文件了,  只需要声明有这么一个类就行了, 当然string还是声明头文件吧, 因为标准库的编译一般不会成为编译瓶颈.

```cpp
#include <string>             
class Date;                          
class Address;      
```

但我们的C++并没有在底层实现这种机制, 也是因为效率和一些设计理念的问题, 但没关系, 我们可以自己仿照这种做法来实现, 这就请我们回忆起条款29中提到的**pimpl idiom**手法(指针指向实现), 我们将在本条款继续深入其使用, **设置接口类和实现类, 做到接口和实现分离**, 以下是接口类的代码, 实现类将在后文补充 : 

```cpp
#include <string>                      
#include <memory>                      // shared_ptr所在
class PersonImpl;                      // 同时也声明实现类
class Date;                        
class Address;                         
class Person {
public:
	Person(const std::string& name, const Date& birthday,
	        const Address& addr);
	std::string name() const;
	std::string birthDate() const;
	std::string address() const;
	...

private:                                   
  	std::shared_ptr<PersonImpl> pImpl;  // shared_ptr使用见条款13
}; 
```

我们会实现一个`PersonImpl`封装上文的三个定义, 并且实现对`Person`中成员函数的定义,  因此`Person`中就只有这三个类型的声明而无定义了, 就算这三个类发生修改, 也无需重新编译Person, 于此通过接口与实现分离, 降低了编译依存关系.

额外说一下, `shared_ptr`并不需要被管理类的头文件, 也是声明即可, 就像正常的指针一样.

---

### 思想内核

**编译依存性最小化**的本质在于**以"声明的依存性"替换"定义的依存性"**, 现实中让头文件**尽可能自我满足**, 万一做不到, 则让它与其它文件内**声明式**相依.

于是我们可以衍生出三个设计策略 : 

- 如果可以用**指针或引用**就不要直接用类定义. **类定义需要引入头文件, 但是指针或引用不需要, 只要声明类型即可**.
- 如果能够, 尽量**以class声明式替换class定义式**. **当你声明一个函数而用到某个class时, 你并不需要改class的定义**, 纵使函数以`by value`的方式传递该类型的参数, 就像上面的`Person`构造一样.
- **为接口类和实现类(也就是声明和定义)提供不同的头文件**, 原因很容易理解, 本来分开的目的就是为了在实现类修改时无需接口类再次编译进而扩散影响,  放在一个头文件中到最后还不是一块编译吗?

这里还需要解释为什么上面的策略都是无需定义, 只要声明就可以了?

我们可以想开一点, 就是在接口类中真的有没有无所谓, 只要通过声明认为它有就行, 真正用它的是实现类, **一旦任何人调用那些函数, 调用之前定义式一旦得先曝光才行**(就是你调用函数前肯定会传入对应的参数嘛), 所以我们是**将"提供定义式"的义务从接口类头文件转到了"内含该函数调用"的客户文件中**, 这样就可以**将"非必要类型定义"与客户端之间的编译依存性去掉**.

接下来将会根据思想内核提供两种实现编译依存性最小化的最终方案 : 

---

### Handle classes

本方案以上文的**pimpl idiom**手法为核心, `Handle classes`意为使用句柄的类, 这个句柄就是**pimpl idiom**手法的指针, `Person`类还是和上文一致, `PersonImpl`类**应当和Person有着完全相同的成员函数, 并且有原本Person预想拥有的成员变量**,  可以理解为`PersonImpl`才是真正的`Person`类, 以后所有的修改将在`PersonImpl`中进行.

一般来说我们要实现三个文件, 一个`Person.h`存放供客户使用的接口类, 一个`PersonImpl.h`存放对应接口类的实现类, 一个`Person.cpp`实现`Person`中函数声明的对应定义.  有点麻烦, 可以看代码理解, 接下来将给出两个分别封装接口类和实现类的头文件 : 

```cpp
// Person.h  存放接口类, 和上文一致
#pragma once
#include <string>                      
#include <memory>                      // shared_ptr所在
class PersonImpl;                      // 同时也声明实现类
class Date;                        
class Address;                         
class Person {
public:
	Person(const std::string& name, const Date& birthday,
	        const Address& addr);
	std::string name() const;
	std::string birthDate() const;
	std::string address() const;
	...

private:                                   
  	std::shared_ptr<PersonImpl> pImpl;  // shared_ptr使用见条款13
}; 
```

```cpp
// PersonImpl.h  存放实现类
#pragma once
#include "Date.h"   // 对实现所需的其他类进行包含
#include "Address.h"

// 定义实现类
class PersonImpl {
public:
    PersonImpl(const std::string& n, const Date& b, const Address& a)
        :_name(n) ,_birthDate(b) ,_address(a)
    {}
    std::string name() const { return _name; }
    std::string birthDate() const { return _birthDate.toString(); }
    std::string address() const { return _address.toString(); }
private:
    std::string _name;
    Date _birthDate;
    Address _address;
};
```

```cpp
// Person.cpp  在该文件实现接口类和实现类的真正关联
#include "Person.h"
#include "PersonImpl.h"

// 完成对接口类中声明函数的定义
Person::Person(const std::string& name, const Date& birthday, const Address& addr)
    : pImpl(std::make_shared<PersonImpl>(name, birthday, addr)) {}

std::string Person::name() const { return pImpl->name(); }
std::string Person::birthDate() const { return pImpl->birthDate(); }
std::string Person::address() const { return pImpl->address(); }
```

宏观来说`Person`更像是一个外壳, 和`PersonImpl`有藕断丝连的关系, 而`PersonImpl`才拥有我们的核心代码, 不过对`PersonImpl`的修改并不需要`Person`所在头文件重新编译, 因为它和`PersonImpl`的关系都是声明来的, 在定义上没有任何关联.

于是客户就可以这样调用`Person`类 : 

```cpp
#include <iostream>
#include "Person.h"  // 只需包含接口类即可
#include "Date.h"
#include "Address.h"
using std::cout;
using std::endl;

int main()
{
	Date date(2024, 12, 10);
	Address addr("NUC");
	Person p("张三", date, addr);
	cout << p.name() << endl;
	cout << p.birthDate() << endl;
	cout << p.address() << endl;
	return 0;
}
```

---

### Interface classes

本方案核心在于**继承**, 像是`java`有专属的接口类, `C++`也可以模拟类似的**抽象基类作为接口类, 而派生类作为实现类**, 也可以达到和上个方案相似的效果, 但是唯一的问题是**客户怎么使用接口类**? 接口类既然是抽象基类, 就绝不可能生成对象, 但是**抽象基类可以有指针和引用**, 由此可以**利用多态机制通过基类指针调用到派生的实现类**, 所以我们虽然写不了构造函数, 但是可以写一个**factory**(工厂)函数来调用派生类的构造函数进而返回派生类的指针, 代码还是三个部分, 我们来逐一阅读 : 

```cpp
// Person.h
#pragma once
#include <string>                      
#include <memory>                      // shared_ptr所在
class Date;
class Address;

class Person {
public:
	virtual ~Person() = default;    // virtual析构函数见条款7
	virtual std::string name() const = 0;
	virtual std::string birthDate() const = 0;
	virtual std::string address() const = 0;
	
    // 工厂函数为create, 通过提供的参数构造不同的派生类
	static std::shared_ptr<Person>    
		create(const std::string& name, const Date& birthday, const Address& addr);
};
```

```cpp
// RealPerson.h  存放实现类
#pragma once
#include "Person.h"
#include "Date.h"   // 对实现所需的其他类进行包含
#include "Address.h"

// 定义实现类
class RealPerson : public Person {
public:
    RealPerson(const std::string& n, const Date& b, const Address& a)
        :_name(n), _birthDate(b), _address(a)
    {}
    
    virtual ~RealPerson() {}
    std::string name() const { return _name; }
    std::string birthDate() const { return _birthDate.toString(); }
    std::string address() const { return _address.toString(); }
private:
    std::string _name;
    Date _birthDate;
    Address _address;
};
```

```cpp
// Person.cpp
#include "Person.h"
#include "RealPerson.h"
// ...

std::shared_ptr<Person>
Person2::create(const std::string& name, const Date& birthday, const Address& addr)
{
	return std::shared_ptr<RealPerson>(std::make_shared<RealPerson>(name, birthday, addr));
}
```

我们这里重点理解`create`工厂函数, 它的最终目的一定是传出一个派生类的智能指针, 尽管传出指针的静态类型是`std::shared_ptr<Person>`, 但也会依靠多态机制绑定到正确的派生类类型. 至于是什么派生类可以通过参数值, 读取数据库数据, 环境变量等各种因素影响, 这里是因为只写了`RealPerson`一个派生类所以就直接返回了, 实际情况可以写更多的判断类型返回不同的派生类指针, 比如男人女人伪人之类的.

于是客户就可以这样调用`Person`类 : 

```cpp
#include <iostream>
#include "Person.h"
#include "Date.h"
#include "Address.h"
using std::cout;
using std::endl;

int main()
{
	Date date(2024, 12, 10);
	Address addr("NUC");
	std::shared_ptr<Person> pp(Person::create("李四", date, addr));

	cout << pp->name() << endl;
	cout << pp->birthDate() << endl;
	cout << pp->address() << endl;

	return 0;
}
```

---

### 两种方案的异同

`Handle classes`利用**pimpl idiom**手法, 构造出来的是一个实打实的对象, 因此可以通过各种方式调用内部功能, 使用较为简单.

`Interface classes`利用**继承和多态**, 构造出来的只能说一个指向派生类对象的指针, 因此只可通过指针调用内部功能, 需要额外调用工厂函数, 但是吃到了多态的便利性, 可以有更大的可扩展性.

二者都实现了声明与定义的分离, 使头文件相依于声明式而非定义式, 解除了接口和实现之间的耦合关系, 从而降低了文件间的编译依存性.

---

### 尾声

C++由于专注于运行时效率的提升, 引入`inline`等各种方式来促成该目的, 再加上`template`, 这其实给编译带来了过大的负担, 也就是说其实是牺牲了编译时而成全了运行时, 放在现实中其实就是牺牲了程序员的时间成本而成全了客户, 这无可厚非, 但若是因此影响了开发效率就顾此失彼了, 因此我们才要优化编译时间, 才要降低编译依存性, 尽管这可能增加些微的运行时成本, 但这仍是必要的.

另外我们也应权衡`inline`, `template`和以上两种方案的使用, 就让它们出现在最应该出现的地方吧.

----

### 请记住 : 

- 支持"编译依存性最小化"的一般构想是 : 相依于声明式, 不要相依于定义式. 基于此构想的两个手段是`Handle classes`和`Interface classes`.
- 头文件应该以"完全且仅有声明式"的形式存在, 除非要使用`inline`或`template`, 而且就算使用`template`, 也可以在头文件中实现`template`的声明, 将定义置入非头文件中, 



by 天目中云







