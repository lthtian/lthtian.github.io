---
title: "Rust 初步学习"
date: 2026-06-14 20:18:48
tags:
  - Rust
---

---

## 1. ownership - 所有权（本质就是默认移动）

### 默认移动语义

Rust 默认使用移动语义，拷贝必须显式调用 `.clone()`。

```rust
let v1 = vec![1, 2, 3];
let v2 = v1;           // 默认移动，v1 失效
// println!("{:?}", v1); // 编译错误！

let v3 = v2.clone();   // 显式拷贝
println!("{:?}, {:?}", v2, v3); // 两者有效
```

**对比 C++**：C++ 默认拷贝，移动需显式 `std::move()`，且移动后对象仍可使用（状态未定义）。Rust 编译期禁止使用已移动的值。

**Copy trait 例外**：基本类型（i32、bool、f64 等）实现了 Copy，自动拷贝：
```rust
let x = 5;
let y = x;  // 拷贝，x 仍有效
```

### Copy vs 非 Copy 的决定因素

**是否实现 Copy trait 决定行为**：

| 类型 | Copy? | 赋值行为 | 原因 |
|------|-------|----------|------|
| i32, f64, bool, char | ✅ | 拷贝 | 栈分配，拷贝成本为零 |
| String, Vec<T>, Box<T> | ❌ | 移动 | 堆分配，有所有权 |
| 自定义 struct | 默认 ❌ | 移动 | 需显式 derive Copy |

**实现 Copy 的条件**：
1. 所有字段都实现 Copy
2. 没有 Drop（不能有自定义析构）

```rust
// 默认不 Copy
struct Point { x: i32, y: i32 }
let p1 = Point { x: 1, y: 2 };
let p2 = p1;  // 移动，p1 失效

// 显式标注 Copy
#[derive(Copy, Clone)]
struct PointCopy { x: i32, y: i32 }
let p3 = PointCopy { x: 1, y: 2 };
let p4 = p3;  // 拷贝，p3 仍有效
```

### #[derive(...)] 编译期代码生成

`derive` 不是注解反射，是编译器自动生成 trait 实现：

```rust
#[derive(Copy, Clone)]
struct Point { x: i32, y: i32 }
// 编译器自动生成 Clone 的 clone() 方法和 Copy 的标记
```

**对比其他语言**：
- Java 注解：运行时反射，有开销
- C++ 宏：预处理器文本替换
- Rust derive：编译期代码生成，零运行时成本

**常见 derive**：`Clone`、`Copy`、`Debug`、`Default`、`PartialEq`、`Eq`、`Hash`

---

## 2. borrow - 借用规则

### mut 可变声明

Rust 默认不可变，`mut` 显式声明可变：

```rust
// 默认不可变
let x = 5;
// x = 10;  // 编译错误！

// 可变变量
let mut y = 5;
y = 10;  // 正确

// 可变引用
let mut s = String::from("hello");
s.push_str(" world");  // 正确

// 不可变引用
let r1 = &s;       // 只读，可以有多个
let r2 = &s;       // 可以有多个

// 可变引用
let r3 = &mut s;   // 可读写，同一时刻只能有一个
r3.push_str("!");
```

**对比 C++**：
- Rust `let x = 5;` ≈ C++ `const int x = 5;`
- Rust `let mut x = 5;` ≈ C++ `int x = 5;`
- Rust 默认不可变，C++ 默认可变

### 切片引用

切片是对序列的部分引用，语法 `[start..end]`，**左闭右开** `[start, end)`：

```rust
let s = String::from("hello world");
let hello = &s[0..5];   // "hello"
let world = &s[6..11];  // "world"
let full = &s[..];      // 完整切片
let start = &s[..5];    // 前5个字符
let end = &s[6..];      // 从第6个到结尾

let arr = [1, 2, 3, 4, 5];
let slice = &arr[1..3]; // [2, 3]
```

**切片类型**：`&str`（字符串切片）、`&[T]`（数组切片）

---

## 3. enum_demo - Option/Result

### 格式化输出

| 标志 | 用途 | 说明 |
|------|------|------|
| `{}` | Display | 用户友好输出 |
| `{:?}` | Debug | 调试输出，需 `#[derive(Debug)]` |
| `{:#?}` | Debug | 美化缩进输出 |

```rust
#[derive(Debug)]
struct User { name: String, age: u32 }

let u = User { name: "Tom".into(), age: 25 };
println!("{:?}", u);   // User { name: "Tom", age: 25 }
println!("{:#?}", u);  // 多行美化输出
```

### match 模式匹配

类似 C++ switch 但更强大，可解构数据：

```rust
match msg {
    Message::Quit => handle_quit(),
    Message::Move { x, y } => move_player(x, y),  // 解构提取 x, y
    Message::Write(text) => save_text(text),
    _ => println!("其他"),  // _ 通配，类似 default
}
```

**对比 C++ switch**：

| 特性 | Rust match | C++ switch |
|------|-----------|-----------|
| 匹配类型 | 任意类型、枚举、结构体 | 仅整数/字符 |
| 提取值 | ✅ 可解构内部数据 | ❌ 不能 |
| 必须完整 | ✅ 必须覆盖所有分支 | ❌ 可能漏 |

**注意**：数组模式匹配只能用于固定大小数组 `[T; N]`，不能用于 `Vec<T>`：

```rust
let arr: [i32; 5] = [1, 2, 3, 4, 5];
match arr {
    [1, second, ..] => println!("首是1，第二个是 {}", second),
    [first, ..] if first > 10 => println!("首大于10"),
    _ => println!("其他"),
}
```

**匹配守卫**：在模式后加 `if` 条件进一步筛选：

```rust
match msg {
    Message::ChangeColor(r, g, b) if r == 0 && g == 0 && b == 0 => {
        println!("黑色");
    }
    Message::ChangeColor(r, g, b) => {
        println!("RGB({}, {}, {})", r, g, b);
    }
    _ => {}
}
```

### Option 和 Some

Rust 没有 null，用 `Option<T>` 表示可能不存在的值：

```rust
enum Option<T> {
    Some(T),  // 有值
    None,     // 无值
}

let some_value: Option<i32> = Some(42);  // 有值
let no_value: Option<i32> = None;        // 无值
```

### if let 和 while let

**if let**：只匹配一种模式，简化 match：

```rust
let some_value = Some(3);

// match 写法
match some_value {
    Some(n) => println!("值是 {}", n),
    _ => (),
}

// if let 写法（更简洁）
if let Some(n) = some_value {
    println!("值是 {}", n);
}
```

**while let**：循环匹配直到不符合：

```rust
let mut stack = vec![1, 2, 3];
while let Some(top) = stack.pop() {  // pop 返回 Some(元素) 或 None
    println!("弹出: {}", top);
}
```

**pop() 方法**：移除并返回顶部元素，返回 `Option<T>`，空时返回 `None`。

---

## 4. error - 错误处理

Rust 没有异常，用 `Result<T, E>` 和 `Option<T>` 处理错误：

```rust
enum Result<T, E> {
    Ok(T),   // 成功
    Err(E),  // 失败
}

fn divide(a: f64, b: f64) -> Result<f64, String> {
    if b == 0.0 {
        Err("除零错误".to_string())
    } else {
        Ok(a / b)
    }
}

// 必须处理两种情况
match divide(10.0, 2.0) {
    Ok(v) => println!("结果: {}", v),
    Err(e) => println!("错误: {}", e),
}

// ? 运算符：自动传播错误
fn read_file(path: &str) -> Result<String, io::Error> {
    let mut file = File::open(path)?;  // 失败自动返回 Err
    let mut content = String::new();
    file.read_to_string(&mut content)?;
    Ok(content)
}
```

**对比 C++**：Rust 强制处理错误，编译期保证；C++ 异常可能被忽略。

---

## 5. struct_demo - 结构体

### 结构体更新语法

`..对象名` 从已有实例复制剩余字段，**必须放最后**：

```rust
let user2 = User {
    email: String::from("new@example.com"),
    ..user1  // 必须在最后
};
```

**注意所有权**：非 Copy 字段会被移动，原对象可能失效。

### impl 实现关键字

用于给类型添加方法或实现 trait：

```rust
impl User {
    // 关联函数（无 self，类似静态方法）
    fn new(name: String) -> User {
        User { name, age: 0 }
    }

    // 方法（有 &self，只读访问）
    fn describe(&self) -> String {
        format!("{}: {}", self.name, self.age)
    }

    // 方法（有 &mut self，可读写）
    fn grow(&mut self) {
        self.age += 1;
    }
}
```

**self 的三种形式**：

| 形式 | 权限 | 说明 |
|------|------|------|
| 无 self | 不能访问实例 | 关联函数，类似静态方法 |
| `&self` | 只读访问 | 只能读取成员 |
| `&mut self` | 可读写访问 | 可修改成员 |

（待补充）

---

## 6. trait_demo - Trait

### Trait 定义与实现

Trait 定义接口规范，类似 C++ 纯虚基类：

```rust
trait Summary {
    fn summarize(&self) -> String;
}

struct Article { title: String }

impl Summary for Article {
    fn summarize(&self) -> String {
        format!("文章: {}", self.title)
    }
}
```

**对比 C++**：

| Rust Trait | C++ 概念 |
|-----------|---------|
| `trait Summary` | 纯虚基类（只有纯虚函数） |
| `impl Trait for Type` | 继承并实现接口 |
| Trait 无数据成员 | 基类可有数据成员 |

### 泛型与 Trait Bound

```rust
// 泛型参数 <T>
fn print<T: Summary>(item: &T) {
    println!("{}", item.summarize());
}

// where 子句（多约束时更清晰）
fn process<T, U>(t: &T, u: &U)
where
    T: Summary,
    U: Summary + std::fmt::Display,
{ ... }
```

**Trait bound**：约束泛型必须实现某些 trait，编译期强制检查。

### impl Trait 返回值

```rust
fn create() -> impl Summary {
    Article { ... }  // 返回具体类型，作为 trait 使用
}
```

类似 C++ 返回基类指针，但编译期单态化，零开销。只能返回一种具体类型。

### dyn Trait 动态分发

```rust
// 运行时多态，可存储多种类型
let items: Vec<Box<dyn Summary>> = vec
![
    Box::new(Article { ... }),
    Box::new(Tweet { ... }),
];

fn factory(kind: &str) -> Box<dyn Summary> {
    match kind {
        "article" => Box::new(Article { ... }),
        "tweet" => Box::new(Tweet { ... }),
        _ => panic!(),
    }
}

// 使用工厂函数
let item = factory("article");
println!("{}", item.summarize());  // 调用 trait 方法

let items: Vec<Box<dyn Summary>> = vec![
    factory("article"),
    factory("tweet"),
];
for item in items {
    println!("{}", item.summarize());
}
```

**对比**：

| `impl Trait` | `dyn Trait` |
|-------------|-------------|
| 编译期单态化 | 运行时多态 |
| 零开销 | 虚函数开销 |
| 固定一种类型 | 可存储多类型 |

### Box 堆分配

`Box<T>` ≈ C++ `std::unique_ptr<T>`，堆分配智能指针：

```rust
let b = Box::new(42);  // 堆上分配
println!("{}", *b);    // 解引用访问

// 主要用途：dyn Trait、递归类型、大数据
let item: Box<dyn Summary> = Box::new(Article { ... });
```

**栈 vs 堆分配规则**：

| 类型 | 内存位置 | 说明 |
|------|---------|------|
| i32, f64, bool, char | 栈 | 大小固定，编译期已知 |
| `[T; N]` 固定数组 | 栈 | 大小固定 |
| struct 字段 | 栈 | 字段在栈则在栈 |
| String, Vec\<T\> | 栈+堆 | 栈存指针/长度，堆存数据 |
| Box\<T\> | 栈存指针，堆存数据 | 显式堆分配 |

```rust
let s = String::from("hello");
// 栈：ptr + len + capacity（管理信息）
// 堆：['h', 'e', 'l', 'l', 'o']（实际数据）
```

**判断方法**：编译期能确定大小 → 栈，否则需要堆（或引用/Box）。

**注意**：`::new()` 只是命名习惯，不代表一定在堆上（如 `String::new()` 是空字符串）。

### 常见标准 Trait

- 重写对应的函数可以改变底层机制相对应的处理方式.

| Trait | 作用 | 绑定功能 |
|-------|------|---------|
| `Clone` | 显式深拷贝 | `.clone()` |
| `Copy` | 隐式按位拷贝 | 赋值自动拷贝 |
| `Drop` | 析构逻辑 | 离开作用域自动调用 |
| `Display` | 用户友好输出 | `{}` 打印 |
| `Debug` | 调试输出 | `{:?}` 打印 |

```rust
impl Drop for Resource {
    fn drop(&mut self) {
        // 清理资源（类似 C++ 析构函数）
    }
}
```

---

## 7. collection - 集合类型

### Vec 动态数组

```rust
let mut v = vec
![1, 2, 3];
v.push(4);
let last = v.pop();        // Some(4)
v.get(2);                  // Some(&3)，安全访问
```

### String 字符串

```rust
let mut s = String::from("hello");
s.push_str(" world");
s.replace("hello", "hi");  // "hi world"
"hello".to_string();       // &str -> String
```

### 闭包语法

`|参数| 表达式`，类似 Lambda：

```rust
|x| x * 2           // 单参数，隐式返回
|x, y| x + y        // 多参数
|x| { x * 2; x }    // 多语句，显式返回
```

### 迭代器与 collect

`collect()` 收集迭代器元素，**必须标注类型**（因为可返回多种集合）：

```rust
// 方式1：标注变量类型
let doubled: Vec<i32> = v.iter().map(|x| x * 2).collect();

// 方式2：turbofish 语法（在方法上标注泛型）
let result = iter.collect::<Vec<i32>>();
let result = iter.collect::<Vec<_>>();  // _ 让编译器推断元素类型

// turbofish 用于无法在变量上标注的场景
println!("{:?}", a.intersection(&b).collect::<Vec<_>>());
```

### 链式调用

```rust
let result: Vec<i32> = v.iter()
    .filter(|x| *x % 2 == 0)  // 过滤
    .map(|x| x * 3)           // 映射
    .take(2)                  // 取前N个
    .collect();

let sum = (1..=10).fold(0, |acc, x| acc + x);  // 归约求和
```

### HashSet 集合操作

```rust
let a: HashSet<i32> = vec
![1, 2, 3].into_iter().collect();
let b: HashSet<i32> = vec
![2, 3, 4].into_iter().collect();
a.intersection(&b);  // 交集
a.union(&b);         // 并集
a.difference(&b);    // 差集
```

### HashMap

```rust
let mut map: HashMap<String, i32> = HashMap::new();
map.insert("a".to_string(), 1);
map.entry("b").or_insert(0);  // 不存在则插入
```