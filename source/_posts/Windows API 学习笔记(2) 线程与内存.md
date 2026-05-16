---
title: Windows API 学习笔记(2) 线程与内存管理
date: 2025-9-7 10:00:00
tags: [WindowsAPI, 线程, 内存管理]
---

>线程与内存管理

## 线程相关

### CreateThread / OpenThread

通过这两个函数获取线程句柄.

- 前者可以用C++11的 thread 库代替.
- 后者传入对应的线程tid, 返回对应的线程句柄.

### 线程句柄的作用

- 使用`TerminateThread`直接终止线程.
- 使用`WaitForSingleObject`等待线程结束.
- 使用 `SuspendThread/ResumeThread`随时挂起和唤醒线程, 一般用来配合分析检测.
- 使用`GetThreadTimes`获取时间, 例如创建时间, CPU占用时间.

### SetThreadAffinityMask

**将某个线程任务绑定到某些CPU核上**, 使得这些CPU优先运行这个任务. 

其作用在于 : 

- **避免频繁的线程切换**.
- 可以有效**缓解缓存失效**, 每个CPU核都有自己的缓存, 会缓存过去运行线程的变量/指令, 随意改变线程执行的核会让这些缓存失效. 

使用方法就是传入线程句柄, 传入掩码, 掩码中每有一个1, 任务就会被绑定到其对应的核上.

```cpp
DWORD_PTR mask = 0x01; // 绑定到核心0
SetThreadAffinityMask(hThread, mask);
```

适用于**计算密集型/低延迟要求**的任务, 比如音视频解码, 金融交易.

### SwitchToThread

调用该函数, 会使当前线程**主动让出时间片**, 供其他线程使用.

- 一些任务如果认为优先级低(就是可以延后执行), 那么可以设置一些节点触发`SwitchToThread`, 让一些高优先级任务(比如UI界面更新)更有可能拿到时间片.

自旋锁是让线程自旋一会等待解锁, 可以有效减少线程切换带来的消耗, 用`SwitchToThread`可以优化其逻辑 : 

```cpp
volatile bool g_Lock = false;

void SpinLockWithYield() {
    int spinCount = 0;
    while (InterlockedCompareExchange(&g_Lock, true, false) != false) {
        // 自旋100次后让出CPU
        if (++spinCount > 100) {
            SwitchToThread(); // 减少空转
            spinCount = 0;
        }
        _mm_pause(); // CPU指令级优化（降低功耗）
    }
}
```

原本自选锁会一直在这里自旋, 将持续占用一个CPU核, 我们预计会很快解锁, 但是假如有特殊情况一直拿不到锁, 累计到一定自选次数后, 就可以调用`SwitchToThread`让出时间片来减少空转.

## 内存管理相关

Windows内存管理也和Linux的那一套非常相似, 进程地址空间 + 分页.

### VirtualAlloc

这是Windows操作系统底层的内存申请函数, malloc在windows平台底层就会间接调用到该函数. 可以认为是Windows版的mmap.

```cpp
LPVOID VirtualAlloc(
  LPVOID lpAddress,       // 指定希望分配的虚拟地址（可选）
  SIZE_T dwSize,          // 分配大小（按页对齐）
  DWORD flAllocationType, // 分配类型（提交/保留）
  DWORD flProtect         // 内存保护属性
);
```

- `lpAddress` : 你可以指定分配的地址, 但是该指针必须页对齐, 不然会失败.
- `dwSize` : 指定分配大小, 最终结果会按页对齐.
  - 对齐 : 默认页大小为4KB(4096), 因此在每个页开始处进行访问只需要一次指令, 但是其他地方就要多条指令, 因此**我们希望分配地址是4KB的整数倍**, 也就是所谓的页对齐.
- `flAllocationType` : 指定分配的类型.
  - `MEM_RESERVE` : 保留一段虚拟地址空间, 但先不申请内存, 需要时再COMMIT.
  - `MEM_COMMIT` : 提交对于物理地址空间的申请, 会做虚拟到物理的映射.
  - RESERVE出来的空间不可被使用, **只是占用使用权**, 要使用时必须COMMIT.
  - 最常见的做法是填入`MEM_RESERVE | MEM_COMMIT`, 本质就是申请一块物理空间可以随时使用.
- `flProtect` : 设置内存保护属性, 防止自己对某些重要内存进行修改.

- 平常大多数情况使用malloc申请内存即可, 只是在**申请大块内存, 有延迟映射需求, 有内存对齐需求, 需要控制内存保护权限**的情况下可以选择使用`VirtualAlloc`.

- VirtualFree : 需要配套使用.

  ```cpp
  BOOL VirtualFree(
    LPVOID lpAddress,
    SIZE_T dwSize,   // 如果 MEM_RELEASE，必须为 0
    DWORD dwFreeType // MEM_RELEASE / MEM_DECOMMIT
  );
  ```

### VirtualProtect

修改已分配内存的保护属性.

```cpp
BOOL VirtualProtect(
  LPVOID lpAddress,
  SIZE_T dwSize,
  DWORD flNewProtect,
  PDWORD lpflOldProtect
);
```

- 建议只使用`VirtureAlloc`出来的句柄设置, 因为其是按页修改保护属性的, `malloc`出来的并非页对齐.
- 默认是`PAGE_READWRITE`可读写, 可改为`PAGE_READONLY`只读和`PAGE_NOACCESS`禁止访问.
- 保护熟悉设置一视同仁, 对本进程和其他进程同样有效, 一般是先读写完, 如果想保护数据在后期通过该函数设置只读或禁读.

### VirtualQuery / VirtualQueryEx

**查询进程虚拟内存状态/属性/归属的重要函数(可跨进程).**

```cpp
// 当前进程
SIZE_T VirtualQuery(
    LPCVOID lpAddress,
    PMEMORY_BASIC_INFORMATION lpBuffer, // 输出内存信息的缓存区
    SIZE_T dwLength // 缓存区结构体的大小
);

// 指定进程
SIZE_T VirtualQueryEx(
    HANDLE hProcess, 	// 想要查询内存的进程句柄
    LPCVOID lpAddress,
    PMEMORY_BASIC_INFORMATION lpBuffer,
    SIZE_T dwLength
);
```

主要用来查询指定内存的状态, 在读写自己或其他内存前使用, 可以有效避免崩溃.

以下是缓存区的结构 : 

```cpp
typedef struct _MEMORY_BASIC_INFORMATION {
  PVOID  BaseAddress;       // 内存块的起始地址
  PVOID  AllocationBase;    // 内存块保留时的基地址
  DWORD  AllocationProtect; // 分配时的保护属性
  SIZE_T RegionSize;        // 从 BaseAddress 开始的连续区域大小
  DWORD  State;             // MEM_COMMIT / MEM_RESERVE / MEM_FREE
  DWORD  Protect;           // 当前页的保护属性
  DWORD  Type;              // MEM_PRIVATE / MEM_MAPPED / MEM_IMAGE
} MEMORY_BASIC_INFORMATION, *PMEMORY_BASIC_INFORMATION;
```

- 一般是读取`State`和`Protect`, 地址可以用来读取内存, 但是仅限本进程, 跨进程需要`ReadProcessMemory`.

### ReadProcessMemory / WriteProcessMemory

**跨进程读写内存**的核心函数.

```cpp
BOOL ReadProcessMemory(
    HANDLE  hProcess,       // 目标进程句柄
    LPCVOID lpBaseAddress,  // 要读取的起始虚拟地址
    LPVOID  lpBuffer,       // 存放数据的本地缓冲区
    SIZE_T  nSize,          // 要读取的字节数
    SIZE_T* lpNumberOfBytesRead // 实际读取字节数（可选）
);

BOOL WriteProcessMemory(
    HANDLE  hProcess,        // 目标进程句柄
    LPVOID  lpBaseAddress,   // 要写入的起始虚拟地址
    LPCVOID lpBuffer,        // 要写入数据的本地缓冲区
    SIZE_T  nSize,           // 要写入的字节数
    SIZE_T* lpNumberOfBytesWritten // 实际写入字节数（可选）
);
```

关键就是目标进程句柄+虚拟地址+缓冲区, 但前提是**读写的内存必须已提交, 读必须有可读权限, 写必须有可写权限**, 这点靠`VirtualQueryEx`查询状态保证.

### 跨进程内存读写实操

这里打算做一个测试 : 

- ProcessA构造一个类对象, 内部有一个val, 显示自己的pid和对象地址后进入循环等待.
- ProcessB用进程pid和对象地址访问该对象并进行修改.

```cpp
// ProcessA.cpp
#include <windows.h>
#include <iostream>
using namespace std;

class MyClass {
public:
    int val;
    MyClass(int v) : val(v) {}
};

int main() {
    MyClass obj(12345);  // 创建对象
    cout << "Process ID: " << GetCurrentProcessId() << endl;
    cout << "Object address: " << &obj << endl;

    while (true) {
        Sleep(1000);
    }
    return 0;
}
```

```cpp
// ProcessB.cpp
#include <windows.h>
#include <iostream>
using namespace std;

int main() {
    DWORD pid;
    uintptr_t objAddr;

    cout << "Enter target PID: ";
    cin >> pid;
    cout << "Enter target object address (hex, e.g., 0x12345678): ";
    cin >> std::hex >> objAddr;

    // 增加读写查询权限
    HANDLE hProcess = OpenProcess(PROCESS_VM_READ | PROCESS_VM_WRITE | PROCESS_VM_OPERATION | PROCESS_QUERY_INFORMATION, FALSE, pid);
    if (!hProcess) {
        cout << "Failed to open process, error: " << GetLastError() << endl;
        return -1;
    }

    // 使用 VirtualQueryEx 确认地址可读写
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQueryEx(hProcess, (LPCVOID)objAddr, &mbi, sizeof(mbi)) == 0) {
        cout << "VirtualQueryEx failed, error: " << GetLastError() << endl;
        CloseHandle(hProcess);
        return -1;
    }

    if (mbi.State != MEM_COMMIT || (mbi.Protect & PAGE_NOACCESS)) {
        cout << "Memory not accessible" << endl;
        CloseHandle(hProcess);
        return -1;
    }

    // 先读 val
    int val = 0;
    SIZE_T bytesRead;
    if (ReadProcessMemory(hProcess, (LPCVOID)objAddr, &val, sizeof(val), &bytesRead) && bytesRead == sizeof(val)) {
        cout << "Before write, val = " << val << endl;
    }
    else {
        cout << "ReadProcessMemory failed, error: " << GetLastError() << endl;
        CloseHandle(hProcess);
        return -1;
    }

    // 写 val = 999
    int newVal = 999;
    SIZE_T bytesWritten;
    if (WriteProcessMemory(hProcess, (LPVOID)objAddr, &newVal, sizeof(newVal), &bytesWritten) && bytesWritten == sizeof(newVal)) {
        cout << "Successfully wrote val = " << newVal << endl;
    }
    else {
        cout << "WriteProcessMemory failed, error: " << GetLastError() << endl;
        CloseHandle(hProcess);
        return -1;
    }

    // 再读 val
    if (ReadProcessMemory(hProcess, (LPCVOID)objAddr, &val, sizeof(val), &bytesRead) && bytesRead == sizeof(val)) {
        cout << "After write, val = " << val << endl;
    }
    else {
        cout << "ReadProcessMemory failed after write, error: " << GetLastError() << endl;
    }

    CloseHandle(hProcess);
    return 0;
}
```

实际效果如下 : 

![aabfeb69ffa2c26861ee99602b054ae5](D:\xwechat_files\wxid_0c8qtb27aeen22_9747\temp\RWTemp\2025-09\9e20f478899dc29eb19741386f9343c8\aabfeb69ffa2c26861ee99602b054ae5.png)

需要注意的是, 打开进程句柄时需要传入对应的权限标识, 不然无法使用对应的函数, 我这里就加入了读写和查询的权限.

### 跨进程内存读写可行性分析

实际上在进程运行时**所有用户区堆内存/数据段几乎都是可读写**的, 本质是因为**页保护属性对所有进程一视同仁**, 如果设置为不可读写, 那么设置方也无法读写, 这是操作系统内存设计的底层逻辑, 无法改变. 因此跨进程读写还是有可行性的. 

不过许多应用也会有很多反制措施, 比如禁止未授权的进程获取本进程的句柄等等, 但似乎依旧有漏洞可钻, 这点貌似很深就不深入学习了.

