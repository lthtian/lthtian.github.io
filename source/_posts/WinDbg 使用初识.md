---
title: "WinDbg 使用初识"
date: 2026-05-16 22:14:38
tags:
  - WinDbg
---

记录使用 WinDBG 分析 Dump 文件、定位崩溃根因的核心方法。聚焦两件事：

- 把 **符号路径** 和 **源码路径** 配对，让调试器能从十六进制地址翻译成源码行
- 用 `!analyze -v` 和 `k` 看堆栈，点击蓝色路径直接跳到源码现场

---

## Symbol Path（符号路径）

### 是什么

符号路径告诉 WinDBG 去哪里找 PDB 文件。PDB 是「地址 ↔ 函数名 / 文件 / 行号」的词典，没有它，你看到的只会是一堆十六进制地址。

### 实际配置值

多个符号源之间用分号分隔：

```
srv*E:\LDSSymbols*http://msdl.microsoft.com/download/symbols;
srv*E:\LDSSymbols*\\<内网符号服务器>\symbol\ldssymbol;
srv*E:\LDSSymbols*http://<内网符号服务器>/symbols
```

### 语法解释

`srv*<本地缓存>*<远程符号源>` 是给 WinDBG 下达的「先查本地缓存，本地没有就去远程下载并缓存到本地」指令。

- `E:\LDSSymbols` —— 本地缓存目录，下载过的 PDB 会留在这里，下次秒开
- `http://msdl.microsoft.com/download/symbols` —— 微软公共符号服务器，解析 `ntdll` / `kernel32` / `user32` 等系统模块
- `\\<内网符号服务器>\symbol\ldssymbol` 和 `http://<内网符号服务器>/symbols` —— 公司私有符号服务器，解析自家模块（如 `c_expand` / `computercenter`）

### 内部运作原理

以堆栈帧 `c_expand!HasBitLockerOnSystemDisk+0x51c` 为例：

1. **提取模块特征码**：WinDBG 从 Dump 中读出 `c_expand.tpi` 模块的 GUID + Age + 时间戳。
2. **查本地缓存**：到 `E:\LDSSymbols` 里找 GUID + Age 完全一致的 `c_expand.tpi.pdb`。
3. **查远程服务器**：本地没有就依次向后面配置的符号服务器请求同一个 GUID 的 PDB。
4. **下载并缓存**：找到后下载到 `E:\LDSSymbols`，下次直接命中。
5. **微软公共源兜底**：系统模块走到 `msdl.microsoft.com`。

> **关键点**：PDB 校验靠 **GUID + Age** 两个字段同时一致。同一份代码改一行重新编译，老 PDB 立刻作废。这是"我明明有 PDB 但加载不上"最常见的原因——版本对不上。

### 产生的效果

没有 Symbol Path 时：

```
0044ebb0 069ec883     07d9ea12 03903e38 0394f690
```

—— 只能看到一堆冷冰冰的十六进制地址。

配好 Symbol Path 之后：

```
0044ebb0 069ec883     07d9ea12 03903e38 0394f690 c_expand!common::utils::HasBitLockerOnSystemDisk+0x51c
```

—— 地址被翻译成了人能看懂的「函数名 + 偏移」。

---

## Source Path（源码路径）

### 是什么

源码路径告诉 WinDBG 去哪里找 `.cc` / `.h` 源文件。配上它，点击堆栈里的蓝色路径就能直接跳到对应源码现场。

### 实际配置值

```
D:\c_expand\client
```

（指向本地 c_expand 仓库的 `client` 子目录）

### 内部运作原理

点击堆栈里 `c_expand!HasBitLockerOnSystemDisk+0x51c` 这一行时：

1. **问 PDB 要源码信息**：WinDBG 去刚加载的 `c_expand.tpi.pdb` 词典里查这个偏移对应哪个文件、哪一行。
2. **拿到编译时的绝对路径**：PDB 里记录的是编译机上的原始绝对路径，比如：

   ```
   e:\jenkins\.jenkins\workspace\pay_group\c_expand\client\client\common\common_utils.cc @ 864
   ```

3. **路径后缀匹配**：本地根本没有 `e:\jenkins\...` 这个目录。WinDBG 用源码路径 `D:\c_expand\client` 从路径**尾部反向匹配**，发现本地的：

   ```
   D:\c_expand\client\client\common\common_utils.cc
   ```

   刚好和编译路径的后缀对得上。

4. **打开并高亮**：调用内置编辑器打开本地文件，跳到第 864 行高亮显示。

> **关键点**：是 **路径后缀匹配**，不是完整匹配。只要本地目录的尾部结构跟编译路径的尾部一致就行，前面多深无所谓。

### 产生的效果

`!analyze -v` 输出的 `STACK_TEXT` 段，仅靠符号路径只翻译出函数名：

```
0044ebb0 069ec883     ... c_expand!common::utils::HasBitLockerOnSystemDisk+0x51c
```

而 `k` 命令在配上 Source Path 后，会在每一帧后面追加源码位置，并把它做成**可点击的蓝色链接**：

```
0f 0044ebb0 069ec883     c_expand!common::utils::HasBitLockerOnSystemDisk+0x51c
   [e:\jenkins\.jenkins\workspace\pay_group\c_expand\client\client\common\common_utils.cc @ 864]
```

点击 `[...]` 里的路径，WinDBG 通过后缀匹配自动打开 `D:\c_expand\client\client\common\common_utils.cc` 并跳到第 864 行。

---

## 保存配置（Save Workspace）

每次配完路径要手动保存，否则下次打开 WinDBG 又得重配。

**操作步骤**：

1. 顶部菜单栏 → **File** → **Settings**
2. 在 **Symbol Path** 输入框填入完整的 `srv*...;srv*...;...` 字符串
3. 在 **Source Path** 输入框填入 `D:\c_expand\client`
4. **File** → **Save Workspace**（关键步骤，否则不持久化）

保存后这些路径就跟着 Workspace 持久保存了，下次打开 WinDBG 自动加载，可以从启动日志的 `Path validation summary` 里确认：

```
************* Path validation summary **************
Response                         Time (ms)     Location
OK                                             D:\c_expand\client

************* Path validation summary **************
Response                         Time (ms)     Location
Deferred                                       srv*E:\LDSSymbols*http://msdl.microsoft.com/download/symbols
Deferred                                       srv*E:\LDSSymbols*\\<内网符号服务器>\symbol\ldssymbol
Deferred                                       srv*E:\LDSSymbols*http://<内网符号服务器>/symbols
```

`OK` 表示源码目录已识别；`Deferred` 表示符号服务器已登记，等真正用到时才发起下载请求（懒加载）。

---

## 核心命令

只需要两个命令就能定位 90% 的崩溃根因。

### `!analyze -v` —— 自动分析

打开 Dump 后第一个执行的命令。WinDBG 会自动：

- 解析异常代码（如 `c0000417` = INVALID_CRUNTIME_PARAMETER）
- 找出 Faulting Module（崩溃所在模块）
- 推算 Failure Bucket（崩溃分类签名，用于聚合相同崩溃）
- 打印一份精简版调用栈 `STACK_TEXT`

典型输出片段：

```
Key  : Failure.Bucket
Value: INVALID_CRUNTIME_PARAMETER_c0000417_c_expand.tpi!_invoke_watson

Key  : Failure.Exception.Code
Value: 0xc0000417

Key  : Failure.Exception.IP.Module
Value: c_expand

PROCESS_NAME:  computercenter.exe

EXCEPTION_RECORD:  (.exr -1)
ExceptionAddress: 06a55db6 (c_expand!_invoke_watson+0x00000020)
   ExceptionCode: c0000417
```

光看这段就能得出第一层结论：`computercenter.exe` 进程，在 `c_expand` 模块里触发了一个 CRT 非法参数异常。

### `k` —— 看完整调用栈

`!analyze -v` 给的 `STACK_TEXT` 是精简版，`k` 是更完整的栈回溯，**每一帧后面带源码位置**（前提是 Source Path 配好了）。

典型输出片段：

```
 # ChildEBP RetAddr
00 0044e1cc 75c215ce     ntdll!NtWaitForSingleObject+0x15
01 0044e238 77241194     KERNELBASE!WaitForSingleObjectEx+0x98
...
04 0044e4e8 772803cb     computercenter!CrashHandler::_MiniDumpHanlder+0x45f
                         [e:\build\lib_common\pc_public\include\commonhelper\crashhandler.cpp @ 400]
05 0044e570 06a55cb4     kernel32!UnhandledExceptionFilter+0x127
06 0044e8a8 06a55db6     c_expand!__acrt_call_reportfault+0x115
                         [d:\th\...\invalid_parameter.cpp @ 182]
07 0044e8bc 06a55d68     c_expand!_invoke_watson+0x20
                         [d:\th\...\invalid_parameter.cpp @ 211]
08 0044e8e0 06a55d75     c_expand!_invalid_parameter+0x7a
09 0044e8f8 06a57cc1     c_expand!_invalid_parameter_noinfo+0xc
0a 0044e904 06a59d2e     c_expand!common_vsprintf_s<wchar_t>+0x74
0b 0044e928 069d48a1     c_expand!__stdio_common_vswprintf_s+0x1f
0e 0044e94c 069d9c4c     c_expand!swprintf_s<32>+0x21
0f 0044ebb0 069ec883     c_expand!common::utils::HasBitLockerOnSystemDisk+0x51c
                         [e:\jenkins\.jenkins\workspace\pay_group\c_expand\client\client\common\common_utils.cc @ 864]
10 0044ed88 0081dc25     c_expand!CExpandClient::Start+0x4f3
                         [...\client.cc @ 109]
11 0044f1dc 0081dc9b     computercenter!CPluginMgr::Start+0x215
                         [...\pluginmgr.cc @ 363]
...
```

---

## 定位根因的工作流

固定打法，三步：

### 跑 `!analyze -v`

主要看三个字段：

- **ExceptionCode**：异常类型
  - `c0000005` = 访问违例（最常见的野指针/空指针）
  - `c0000417` = CRT 非法参数（如 `swprintf_s` 缓冲区不够、格式串错）
  - `c00000fd` = 栈溢出
- **Failure.Exception.IP.Module**：崩溃所在模块
- **PROCESS_NAME**：进程名

### 跑 `k`，找第一个自家代码的栈帧

从栈顶往下看，**跳过 CRT / 系统模块的帧**（`ntdll` / `kernel32` / `KERNELBASE` / `user32` / `_invoke_watson` / `_invalid_parameter` / `swprintf_s` 这些都是事故链的下游，是 CRT 检测到错误后内部往上抛错的调用链），找到第一个**自家业务代码模块**的栈帧——那才是真正的崩溃现场。

以上面输出为例，从栈顶 `00` 往下扫：

```
00-03  ntdll / KERNELBASE / kernel32         ← 系统等待 / 异常处理框架，跳过
04     computercenter!CrashHandler::_MiniDump ← 自家崩溃处理器，是事故的"消费者"，跳过
05     kernel32!UnhandledExceptionFilter      ← 系统的未处理异常分发，跳过
06-0e  c_expand!_invoke_watson / _invalid_parameter / swprintf_s / __stdio_common_vswprintf_s
                                              ← CRT 检测到非法参数后的内部抛错链，跳过
0f     c_expand!HasBitLockerOnSystemDisk      ← ★ 第一个自家业务帧，肇事者就在这
```

`0f` 这一帧才是真正的崩溃现场——是它调了 `swprintf_s<32>` 并传了非法参数，导致 CRT 抛了 `c0000417`。

### 点击蓝色路径跳到源码

点 `k` 输出里 `0f` 帧那段 `[...\common_utils.cc @ 864]`（在 WinDBG 里显示为蓝色），WinDBG 通过 Source Path 后缀匹配，自动打开本地的：

```
D:\c_expand\client\client\common\common_utils.cc
```

并跳到第 864 行。

至此就能在源码现场分析根因——比如这个例子里第 864 行是个 `swprintf_s<32>` 调用，结合 CRT 非法参数异常，基本可以判定是缓冲区不够、或格式串与参数对不上。

---

## 扩展补充

`!analyze -v` + `k` 能覆盖大多数崩溃 dump。下面两个命令是这套基础工作流的天然延伸，遇到对应场景时很实用。

### `~*k` —— 看所有线程的调用栈

`k` 只看当前线程，`~*k` 一次性打印 **进程内全部线程** 的调用栈。

**使用场景**：dump 是「程序卡死、界面无响应」类型时，进程并没有抛异常，没有"当前出错线程"可看，必须扫所有线程才能找到谁在等谁。比如主线程卡在 `WaitForSingleObject`，再去其他线程里找谁应该 set 这个 event 却没 set。

### `dv` —— 看当前栈帧的局部变量

定位到肇事栈帧后（比如用 `.frame 0f` 切到 `HasBitLockerOnSystemDisk` 那一帧），跑 `dv` 可以看这一帧里所有局部变量的当前值——往往直接就能看到「哦原来这个 size 变量是 0」「这个指针是 0xdddddddd（已释放）」之类的根因。

**注意**：Release 优化版本里很多局部变量会被寄存器化或合并掉，`dv` 输出可能是 `<value unavailable>` 或干脆缺失。看不到是常态，不是配置出错。

- **TTD（Time Travel Debugging，时空穿梭调试）**：能录制运行过程并回放、反向单步。听起来很强，但**前提是事先用 WinDbg Preview 录制**（生成 `.run` 文件）。**对已经拿到的 `.dmp` 文件无效**。只有当你能在本地稳定复现、愿意花时间录制时才用得上。
- **`!heap`**：堆分析、找内存泄漏源头。需要进程启动前用 `gflags` 开启 Page Heap，普通 minidump 里几乎拿不到有效信息。
- **`!locks`**：列出所有被持有的临界区（CRITICAL_SECTION），快速定位死锁。怀疑死锁时配合 `~*k` 用。
- **`dx` + 数据模型**：用类 LINQ 语法查询调试器对象（模块、线程、堆等）。例如 `dx @$curprocess.Modules.Where(m => m.Name.Contains("c_expand"))`。处理超大对象树/链表时很高效，对日常崩溃定位是杀鸡用牛刀。
