---
title: "Rust 初步学习 (2) - 进阶特性"
date: 2026-06-27 15:53:56
tags:
  - Rust
---

---

## 1. attribute - 属性系统

### #[derive(...)] 编译期代码生成

让编译器自动生成 trait 实现，避免手写重复代码。

```rust
#[derive(Debug, Clone, PartialEq)]
struct Point { x: i32, y: i32 }

let p1 = Point { x: 1, y: 2 };
let p2 = p1.clone();      // Clone
println!("{:?}", p1);     // Debug
assert_eq!(p1, p2);       // PartialEq
```

### 标准库 derive 选项

| derive | 功能 | 示例用途 |
|--------|------|----------|
| `Clone` | `.clone()` 深拷贝 | 复制对象 |
| `Copy` | 赋值自动拷贝 | 小型值类型 |
| `Debug` | `{:?}` 调试输出 | 打印调试信息 |
| `Default` | `.default()` 默认值 | 创建默认实例 |
| `PartialEq` | `==` `!=` 比较 | 值相等判断 |
| `Eq` | 完全相等（需 PartialEq） | HashMap key |
| `PartialOrd` | `<` `>` `<=` `>=` | 排序比较 |
| `Ord` | 完全排序（需 Eq） | 排序、BTreeMap key |
| `Hash` | `.hash()` 哈希值 | HashMap/HashSet key |

**依赖关系**：`Copy → Clone`，`Eq → PartialEq`，`Ord → Eq`

### 无法自动生成的情况

- 有非 Clone 字段 → 无法 derive Clone
- 实现了 Drop → 无法 derive Copy
- 需要自定义逻辑（如隐藏敏感信息）→ 必须手写

### 其他常用属性

```rust
#[must_use]           // 强制使用返回值
#[allow(dead_code)]   // 允许警告
#[inline]             // 内联建议
#[inline(always)]     // 强制内联
#[inline(never)]      // 禁止内联
```

### #[cfg] 条件编译

编译期配置选项，由 Cargo 自动设置。

| 类别 | 选项 | 示例值 |
|------|------|--------|
| 目标系统 | `target_os` | `"windows"`, `"linux"`, `"macos"` |
| 目标架构 | `target_arch` | `"x86_64"`, `"arm"`, `"aarch64"` |
| 编译模式 | `debug_assertions` | `true` / `false` |
| 特性开关 | `feature` | 自定义 feature |
| 测试模式 | `test` | `true` |

```rust
#[cfg(target_os = "windows")]
fn platform_func() { println!("Windows"); }

#[cfg(debug_assertions)]
fn debug_only() { println!("仅debug模式"); }

// 组合条件
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn linux_x64() {}

#[cfg(any(target_os = "windows", target_os = "macos"))]
fn desktop() {}
```

---

## 2. module_demo - 模块系统

模块 = 命名空间 + 访问控制。

### 可见性规则

| 可见性 | 范围 | 类比 C++ |
|--------|------|----------|
| `pub` | 公开，任意模块可访问 | `public` |
| `pub(crate)` | 当前 crate 内可见 | `internal` linkage |
| `pub(super)` | 父模块及其子模块可见 | 无对应 |
| 无修饰 | 私有，仅当前模块 | `private` |

```rust
mod outer {
    pub fn outer_fn() {}           // 公开
    pub(crate) fn crate_fn() {}    // crate 内可见

    mod inner {
        pub(super) fn inner_fn() {}  // 仅 outer 模块可访问

        pub struct Data {
            pub field: i32,       // 公开
            pub(crate) id: i32,   // crate 内可见
            private: i32,         // 私有
        }
    }

    fn test() {
        inner::inner_fn();  // ✅ super 可见
    }
}
```

### use 导入

```rust
use math::advanced::*;     // 导入所有公开项
use math::advanced;        // 只导入模块名，需用 advanced::xxx 访问
```

**对比 C++**：`use` ≈ `using namespace`，但 Rust 模块有可见性控制。

---

## 3. test_demo - 测试框架

Rust 内置测试框架，无需第三方库。

### 基本用法

```rust
#[cfg(test)]        // 仅测试时编译
mod tests {
    use super::*;

    #[test]         // 标记测试函数
    fn test_add() {
        assert_eq!(1 + 1, 2);
    }

    #[test]
    #[should_panic] // 期望 panic
    fn test_panic() { panic!(); }

    #[test]
    #[ignore]       // 跳过测试
    fn test_slow() {}
}
```

### 断言宏

| 宏 | 用途 |
|---|------|
| `assert!(expr)` | 表达式为真 |
| `assert_eq!(a, b)` | 相等 |
| `assert_ne!(a, b)` | 不相等 |

### 测试组织

| 位置 | 用途 | 可见性 |
|------|------|--------|
| 同文件 `#[cfg(test)] mod tests` | 单元测试 | 可测私有 |
| `tests/` 目录 | 集成测试 | 仅公开 API |

**习惯**：单元测试放同文件底部，就近维护；集成测试放 `tests/` 测试跨模块交互。

```bash
cargo test              # 运行所有测试
cargo test test_add     # 过滤测试名
cargo test -- --ignored # 运行被忽略的测试
```

### 第三方测试库

| 库 | 用途 |
|---|------|
| `proptest` | 属性测试（随机生成用例） |
| `criterion` | 性能基准测试 |
| `mockall` | Mock 框架 |

---

## 4. lifetime - 生命周期

编译期标记，确保引用有效。

### 为什么需要标注？

编译器不分析函数体，只看签名。多个引用参数时，不知道返回值绑谁。

```rust
// ❌ 编译器不知道返回值属于 x 还是 y
fn longest(x: &str, y: &str) -> &str { ... }

// ✅ 显式标注：返回值生命周期 = 参数交集
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str { ... }
```

### 省略规则

| 情况 | 能否省略 |
|------|----------|
| 1 个参数 + 返回引用 | ✅ 自动绑定 |
| 有 `&self` + 返回引用 | ✅ 自动绑定 self |
| 多个参数 + 返回引用 | ❌ 必须标注 |

### struct 存引用

```rust
struct Text<'a> {
    content: &'a str,  // 必须标注
}
```

### 实际使用

大多数代码不需要手动标注，编译器会报错提醒。

---

## 5. async_demo - 异步编程

Rust 异步底层是**编译器生成的状态机**（协程）。

### 基本语法

```rust
async fn fetch() -> i32 {
    let data = read_file().await;  // 暂停等待
    process(data)
}
```

### 核心概念

| 概念 | 作用 |
|------|------|
| `async` | 定义异步函数/块，返回 Future |
| `.await` | 暂停等待结果 |
| `Future` | 状态机，`poll()` 检查是否完成 |
| 运行时 | tokio/async-std，负责调度 |

### 实际项目使用

```rust
// Cargo.toml
// tokio = { version = "1", features = ["full"] }

#[tokio::main]
async fn main() {
    let result = async_op().await;
}
```

### tokio 运行时

Rust 的 async 语法只定义 Future，需要运行时执行。tokio 是最流行的异步运行时库。

| tokio 提供 | 说明 |
|------------|------|
| 执行器 | 多线程执行 Future |
| 网络 | 异步 TCP/UDP |
| 文件 I/O | 异步文件操作 |
| 定时器 | sleep、interval |

```rust
use tokio::time::{sleep, Duration};

#[tokio::main]
async fn main() {
    sleep(Duration::from_secs(1)).await;  // 异步等待

    tokio::spawn(async { /* 并发任务 */ });  // 创建任务

    let (a, b) = tokio::join!(task1(), task2());  // 并发执行
}
```

**关系**：Rust async = 语法层面；tokio = 运行时库。

### 对比其他语言

| 语言 | 实现方式 | 运行时 |
|------|----------|--------|
| Rust | 编译期状态机 | 需 tokio |
| Go | goroutine | 内置 |
| C++20 | 协程 | 需自行实现 |
| Python | async/await | 事件循环 |

**特点**：零成本抽象，无内置运行时，显式 .await。

---

## 6. concurrency - 并发原语

### 智能指针

数据分配 + 资源管理功能，包装一个值，提供额外能力。

| 智能指针 | 提供的能力 | 类比 C++ |
|----------|-----------|----------|
| `Box<T>` | 堆分配 | `unique_ptr<T>` |
| `Arc<T>` | 共享所有权（线程安全） | `shared_ptr<T>` |
| `Rc<T>` | 共享所有权（单线程） | - |
| `Mutex<T>` | 互斥访问 | `mutex` + 数据 |

```rust
let a = Box::new(42);           // 堆分配
let b = Arc::new(vec
![1, 2, 3]);   // 可跨线程共享
let c = Mutex::new(0);          // 互斥保护

// 用法一致
println!("{}", *a);
println!("{}", *Arc::clone(&b));
println!("{}", *c.lock().unwrap());
```

### Arc + Mutex 组合

```rust
use std::sync::{Arc, Mutex};

let counter = Arc::new(Mutex::new(0));  // 共享 + 互斥

let handles: Vec<_> = (0..10).map(|_| {
    let counter = Arc::clone(&counter);
    thread::spawn(move || {
        let mut num = counter.lock().unwrap();
        *num += 1;
    })
}).collect();
```

### Channel 通道

线程安全的消息管道，用于线程间通信。

```
发送端 ──► [ channel ] ──► 接收端

```

```rust
use std::sync::mpsc;

let (tx, rx) = mpsc::channel();  // (发送端, 接收端)

// 发送
tx.send(42).unwrap();

// 接收（阻塞等待）
let val = rx.recv().unwrap();

// 或迭代接收
for val in rx {
    println!("{}", val);
}
```

| 类型 | 说明 |
|------|------|
| `mpsc` | 多生产者，单消费者（标准库） |
| `mpmc` | 多生产者，多消费者（需 `crossbeam` 库） |

**对比 Go**：`tx.send(val)` ≈ `ch <- val`，`rx.recv()` ≈ `val := <- ch`

### 闭包

Rust 闭包 ≈ C++ lambda。

| Rust | C++ lambda | 说明 |
|------|-----------|------|
| `|| expr` | `[]() { expr }` | 无参数 |
| `|x| x + 1` | `(x) { return x + 1; }` | 单参数 |
| `|x, y| x + y` | `(x, y) { return x + y; }` | 多参数 |
| `move ||` | `[=]() { }` | 拷贝/移动捕获 |
| 默认 `||` | `[&]() { }` | 引用捕获 |

```rust
let add = |x| x + 1;              // 单参数
let sum = |a, b| a + b;           // 多参数
let calc = |x| { let y = x * 2; y + 1 };  // 多语句

// move 闭包：用于线程
thread::spawn(move || { /* 变量移入 */ });

// 作为参数
vec.iter().map(|x| x * 2).collect();
```

**类比**：Arc ≈ 共享钥匙，Mutex ≈ 保险箱，Channel ≈ 管道。

---

## 7. macro_demo - 宏系统

编译期代码生成，类似 C 预处理器但更安全。

### 声明宏 macro_rules!

```rust
macro_rules! create_function {
    ($name:ident) => {
        fn $name() {
            println!("Function {:?}", stringify!($name));
        }
    };
}

create_function!(foo);  // 生成 fn foo() { ... }
create_function!(bar);
```

### 片段分类符

| 分类符 | 匹配内容 | 示例 |
|--------|----------|------|
| `ident` | 标识符 | `foo`, `my_func` |
| `expr` | 表达式 | `1 + 2`, `x * 3` |
| `ty` | 类型 | `i32`, `String` |
| `stmt` | 语句 | `let x = 1;` |
| `literal` | 字面量 | `42`, `"hello"` |
| `tt` | 任意 token | 任何 |

### 重复匹配

```rust
// * : 0次或多次
($($x:expr),*) => { ... }

// + : 1次或多次
($($x:expr),+) => { ... }

// 示例：求和宏
macro_rules! add_all {
    ($first:expr, $($rest:expr),+) => {
        $first $(+ $rest)+
    };
}
add_all!(1, 2, 3);  // 展开为 1 + 2 + 3
```

### 条件编译宏

```rust
macro_rules! if_debug {
    ($($code:tt)*) => {
        #[cfg(debug_assertions)]
        { $($code)* }
    };
}

if_debug! {
    println!("仅debug模式");
}
```

### 常用内置宏

| 宏 | 作用 |
|---|------|
| `vec![]` | 创建 Vec |
| `println!()` | 格式化输出 |
| `format!()` | 格式化字符串 |
| `panic!()` | 抛出 panic |
| `assert!()` | 断言 |

**对比 C**：Rust 宏是编译期代码生成，有类型检查；C 宏是预处理期文本替换，无检查。

---

## 8. unsafe_demo - Unsafe 与 FFI

绕过编译器安全检查，用于底层操作和 FFI。

### unsafe 块

```rust
let mut num = 5;
let ptr = &mut num as *mut i32;  // 创建裸指针（安全）

unsafe {
    *ptr = 10;  // 解引用裸指针（需要 unsafe）
}
```

### 可做的事情

| 操作 | 说明 |
|------|------|
| 解引用裸指针 | `*ptr` |
| 调用 unsafe 函数 | `dangerous()` |
| 访问可变静态变量 | `static mut X: i32` |
| 实现 unsafe trait | `unsafe impl Send for T` |

### FFI - 调用 C

```rust
// 声明外部 C 函数
extern "C" {
    fn abs(input: i32) -> i32;
}

unsafe {
    let result = abs(-10);  // Rust 调用 C
}
```

### FFI - 导出 C 接口

```rust
// 导出给 C 调用
#[no_mangle]  // 保持函数名不变
extern "C" fn add(a: i32, b: i32) -> i32 {
    a + b
}

// 导出结构体
#[repr(C)]  // C 内存布局
pub struct Point {
    x: f64,
    y: f64,
}
```

### 导出规则

| 类型 | 能否导出 |
|------|----------|
| 基本类型 (`i32`, `f64`) | ✅ |
| `#[repr(C)]` 结构体 | ✅ |
| 裸指针 | ✅ |
| Rust 特有类型 (`String`, `Vec`) | ❌ |

**对比 C++**：`extern "C" fn` ≈ `extern "C"` 函数声明。

### 安全抽象

```rust
// 将 unsafe 封装成安全 API
fn safe_split_at(slice: &[i32], mid: usize) -> (&[i32], &[i32]) {
    assert!(mid <= slice.len());
    unsafe {
        (
            std::slice::from_raw_parts(slice.as_ptr(), mid),
            std::slice::from_raw_parts(slice.as_ptr().add(mid), slice.len() - mid),
        )
    }
}
```

**原则**：unsafe 代码要尽量少，封装成安全 API。