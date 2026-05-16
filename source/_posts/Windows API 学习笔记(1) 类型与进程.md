---
title: Windows API 学习笔记(1) 类型和进程
date: 2025-9-4 21:00:00
tags: [WindowsAPI, 进程]
---

> 学习目标 : 主要在于学习怎么用C/C++使用Windows操作系统, 不学界面, 只学底层, 比如内存管理, 线程, 系统信息调用, 网络编程相关.

> 类型和进程

## Windows类型

| Windows类型      | 等效C/C++类型           | 大小    | 用途                               |
| :--------------- | :---------------------- | :------ | :--------------------------------- |
| `BYTE`           | `unsigned char`         | 1字节   | 二进制数据、字节流                 |
| `WORD`           | `unsigned short`        | 2字节   | 16位无符号整数（如端口号）         |
| `DWORD`          | `unsigned long`         | 4字节   | 32位无符号整数（如进程ID、错误码） |
| `DWORD64`        | `unsigned long long`    | 8字节   | 64位无符号整数                     |
| `INT`, `UINT`    | `int`, `unsigned int`   | 4字节   | 通用有/无符号整数                  |
| `LONG`, `ULONG`  | `long`, `unsigned long` | 4字节   | 长整数（Win32 API常用）            |
| `BOOL`           | `int`                   | 4字节   | 布尔值（`TRUE`/`FALSE`）           |
| `HANDLE`         | `void*`                 | 4/8字节 | 内核对象通用句柄（文件、进程等）   |
| `CHAR`/`LPSTR`   | `char*`                 | 1字节   | ANSI字符串（多字节编码）           |
| `WCHAR`/`LPWSTR` | `wchar_t*`              | 2字节   | Unicode字符串（UTF-16）            |
| `LPVOID`         | `void*`                 | 4/8字节 | `void*`（通用指针）                |

### wchar

现代Windows系统的原生字符编码方式就是**Unicode(UTF-16)**, 就是wchar本身的编码方式(两字节宽字符), 因此Windows系统最好使用wchar字符串, 可以减少很多转码的开销.

C++本身也支持宽字符 : 

- `wchar_t` : 宽字符类型.

- `<cwchar>` : 宽字符库, 有`wprintf`, `wcslen`等实现对宽字符串的处理.

- `<locale>`  : 设置本地化, 因为默认按照ASCII编码解释, 通过setlocale可以改变解释规则.

  ```cpp
  #include <locale>
  setlocale(LC_ALL, "");  // 启用本地化支持（如控制台输出中文）
  ```

  这里选择`LC_ALL`代表依据操作系统本身的本地化规则来解释, 比如汉字在不设置之前就无法被读出.

- `std::wstring` : 

  ```cpp
  std::wstring ws = L"你好，世界！";
  ```

## 进程相关

### CreateProcessW

> 用绝对路径或相对路径指定一个可执行文件, 开辟一个进程运行该可执行文件.

CreateProcessW总共有10个参数, 但现在只需要先知道第二个参数传入可执行文件路径.

下面的例子中, 我们开辟了一个进程运行了Windows自带的记事本 : 

```cpp
int main() {
    STARTUPINFOW si{ sizeof(si) };
    PROCESS_INFORMATION pi;

    // 使用可修改的宽字符串缓冲区
    wchar_t commandLine[] = L"notepad.exe";

    if (CreateProcessW(
        NULL,                   // 应用程序名（NULL表示使用命令行）
        commandLine, // 命令行参数
        NULL,                   // 进程安全属性
        NULL,                   // 线程安全属性
        FALSE,                  // 不继承句柄
        0,                      // 创建标志
        NULL,                   // 环境变量
        NULL,                   // 工作目录
        &si,                    // 启动信息
        &pi))                   // 进程信息
    {
        printf("成功启动！PID: %d\n", pi.dwProcessId);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }
    else {
        printf("错误代码: %d\n", GetLastError());
    }
    system("pause");
    return 0;
}
```

- 注意第二个参数必须要传入**可修改的宽字符串缓冲区**, 我们需要在栈上开辟然后传入, 不可以直接在第二个参数处传入路径, 因为普通字符串会被视为常量**只读**, 不可修改, 而CreateProcessW会在内部对第二个参数进行修改, 因此必须栈上构造再传入.
- 倒数第二个参数可以设置一些启动线程的设置.
- 最后一个参数用来存放启动的进程对应的**进程/线程句柄**, 这个两种句柄的作用很大, 可以查询各种进程/线程的信息. 需要这两个句柄最后必须通过`CloseHandle`函数消掉, 不然会内存泄露.

### OpenProcess

> 传入进程PID, 返回对应进程的线程句柄.

```cpp
HANDLE OpenProcess(
    DWORD dwDesiredAccess,  // 访问权限（如 PROCESS_TERMINATE）
    BOOL  bInheritHandle,   // 是否继承句柄
    DWORD dwProcessId       // 目标进程的PID
);
```

### **TerminateProcess**

> 传入句柄, 强制终止对应进程.

```cpp
BOOL TerminateProcess(
    HANDLE hProcess,  // 进程句柄（通过 OpenProcess 或 CreateProcess 获取）
    UINT   uExitCode  // 退出代码（自定义，通常填 0）
);
```

下面一个例子, 我们将再外部打开记事本, 通过任务管理器找到对应的PID, 传入程序, 通过`OpenProcess`获取进程句柄, 再通过`TerminateProcess`强制停止记事本进程 : 

```cpp
#include <windows.h>
#include <stdio.h>

int main() {
    DWORD pid;
    printf("输入要打开的进程PID: ");
    scanf_s("%d", &pid);

    // 打开进程（获取句柄）
    HANDLE hProcess = OpenProcess(
        PROCESS_ALL_ACCESS,  // 所有权限（实际需根据需求调整）
        FALSE,               // 不继承句柄
        pid                  // 目标进程PID
    );

    if (hProcess == NULL) {
        printf("打开进程失败！错误代码: %d\n", GetLastError());
    }
    else {
        printf("进程句柄: 0x%p\n", hProcess);
    }

    if (TerminateProcess(hProcess, 0)) {
        printf("进程已终止！\n");
    }
    else {
        printf("终止失败！错误代码: %d\n", GetLastError());
    }
    CloseHandle(hProcess);
    return 0;
}
```

我们会发现, 我们外部开启的记事本会被我们启动的程序强制关闭.

### 进程句柄的作用

- 终止进程 : 效果同上, 可以强关卡死的进程, 关闭冲突进程.

- 等待进程结束, 实现进程同步.

  ```cpp
  WaitForSingleObject(hProcess, INFINITE); // 阻塞直到进程退出
  ```

- 查询进程信息 : 

  - GetProcessTimes : 输出时间相关的数据, 传入进程句柄和四种时间参数.

    | 参数             | 类型       | 单位    | 说明                                        |
    | :--------------- | :--------- | :------ | :------------------------------------------ |
    | `lpCreationTime` | `FILETIME` | 100纳秒 | 进程创建时间（UTC时间戳）                   |
    | `lpExitTime`     | `FILETIME` | 100纳秒 | 进程退出时间（若未退出则为0）               |
    | `lpKernelTime`   | `FILETIME` | 100纳秒 | 进程在内核模式消耗的CPU时间（所有线程累计） |
    | `lpUserTime`     | `FILETIME` | 100纳秒 | 进程在用户模式消耗的CPU时间（所有线程累计） |

  - GetProcessMemoryInfo : 输入内存相关的数据, 传入进程句柄和`PROCESS_MEMORY_COUNTERS`, 以下是pmc的参数 : 

    | 字段                 | 类型     | 单位 | 说明                             |
    | :------------------- | :------- | :--- | :------------------------------- |
    | `WorkingSetSize`     | `SIZE_T` | 字节 | 当前物理内存占用（工作集）       |
    | `PeakWorkingSetSize` | `SIZE_T` | 字节 | 物理内存占用的历史峰值           |
    | `PagefileUsage`      | `SIZE_T` | 字节 | 虚拟内存使用量（含磁盘分页文件） |
    | `PeakPagefileUsage`  | `SIZE_T` | 字节 | 虚拟内存占用的历史峰值           |
    | `PageFaultCount`     | `DWORD`  | 次   | 页错误次数（硬错误+软错误）      |

### 进程状态检测器

利用Windows API的进程函数, 展示所有进程的名称/路径/内存占用/CPU占用.

```cpp
#include <windows.h>
#include <stdio.h>
#include <psapi.h>
#include <locale.h>
#include <pdh.h>  // 用于CPU性能计数器
#include <pdhmsg.h>

#pragma comment(lib, "pdh.lib")

// 获取系统总物理内存
ULONGLONG GetTotalPhysicalMemory() {
    MEMORYSTATUSEX memInfo;
    memInfo.dwLength = sizeof(MEMORYSTATUSEX);
    GlobalMemoryStatusEx(&memInfo);
    return memInfo.ullTotalPhys;
}

// 获取进程CPU使用率
double GetProcessCpuUsage(HANDLE hProcess, ULONGLONG* lastTime, ULONGLONG* lastSysTime, ULONGLONG* lastUserTime) {
    FILETIME createTime, exitTime, kernelTime, userTime;
    ULONGLONG now, sysTime, userTime64;

    GetSystemTimeAsFileTime(&createTime);
    now = ((ULONGLONG)createTime.dwHighDateTime << 32) | createTime.dwLowDateTime;

    if (!GetProcessTimes(hProcess, &createTime, &exitTime, &kernelTime, &userTime)) {
        return -1.0;
    }

    sysTime = ((ULONGLONG)kernelTime.dwHighDateTime << 32) | kernelTime.dwLowDateTime;
    userTime64 = ((ULONGLONG)userTime.dwHighDateTime << 32) | userTime.dwLowDateTime;

    ULONGLONG sysTimeDiff = sysTime - *lastSysTime;
    ULONGLONG userTimeDiff = userTime64 - *lastUserTime;
    ULONGLONG timeDiff = now - *lastTime;

    *lastTime = now;
    *lastSysTime = sysTime;
    *lastUserTime = userTime64;

    if (timeDiff == 0) {
        return 0.0;
    }

    return (double)(sysTimeDiff + userTimeDiff) * 100.0 / (double)timeDiff;
}

int main() {
    setlocale(LC_ALL, ""); // 允许控制台输出中文

    // 获取系统总内存
    ULONGLONG totalMemory = GetTotalPhysicalMemory();
    wprintf(L"系统总内存: %.2f MB\n", totalMemory / (1024.0 * 1024.0));

    // 初始化CPU计数器
    ULARGE_INTEGER lastCPU, lastSysCPU, lastUserCPU;
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    lastCPU.LowPart = ft.dwLowDateTime;
    lastCPU.HighPart = ft.dwHighDateTime;

    SYSTEM_INFO sysInfo;
    GetSystemInfo(&sysInfo);
    DWORD numProcessors = sysInfo.dwNumberOfProcessors;

    // 获取所有的进程id
    DWORD pids[1024], cbNeeded;
    if (!EnumProcesses(pids, sizeof(pids), &cbNeeded)) {
        wprintf(L"EnumProcesses失败! 错误: %d\n", GetLastError());
        return 1;
    }

    DWORD processCount = cbNeeded / sizeof(DWORD);
    wprintf(L"共发现 %d 个进程\n", processCount);

    for (DWORD i = 0; i < processCount; i++) {
        HANDLE hProcess = OpenProcess(
            PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
            FALSE,
            pids[i]
        );

        if (hProcess == NULL) {
            continue;
        }

        WCHAR processName[MAX_PATH] = L"<未知>";
        if (GetModuleBaseNameW(hProcess, NULL, processName, MAX_PATH) > 0) {
            wprintf(L"[PID: %5d] 名称: %s\n", pids[i], processName);
        }

        // 获取进程路径
        WCHAR exePath[MAX_PATH];
        DWORD size = MAX_PATH;
        if (QueryFullProcessImageNameW(hProcess, 0, exePath, &size)) {
            wprintf(L"  路径: %s\n", exePath);
        }

        // 获取内存信息并计算百分比
        PROCESS_MEMORY_COUNTERS pmc;
        if (GetProcessMemoryInfo(hProcess, &pmc, sizeof(pmc))) {
            double memoryMB = pmc.WorkingSetSize / (1024.0 * 1024.0);
            double memoryPercent = (double)pmc.WorkingSetSize * 100.0 / (double)totalMemory;
            wprintf(L"  内存: %.2f MB (%.2f%%)\n", memoryMB, memoryPercent);
        }

        // 获取CPU使用率
        ULONGLONG lastTime = 0, lastSysTime = 0, lastUserTime = 0;
        double cpuUsage = GetProcessCpuUsage(hProcess, &lastTime, &lastSysTime, &lastUserTime);
        if (cpuUsage >= 0.0) {
            wprintf(L"  CPU使用率: %.2f%%\n", cpuUsage / numProcessors);
        }

        CloseHandle(hProcess);
    }

    return 0;
}
```

