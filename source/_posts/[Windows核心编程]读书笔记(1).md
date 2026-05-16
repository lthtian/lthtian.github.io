---
title: Windows核心编程 读书笔记(1)
date: 2025-9-15 21:54:00
tags: [WindowsAPI, Windows核心编程]
---

> 进程 线程 优先级 亲和性

### GetCurrentDirectory

获取当前进程所在目录路径.

```cpp
DWORD GetCurrentDirectory(
  DWORD  nBufferLength,  // 缓冲区大小（字符数）[输出]
  LPTSTR lpBuffer        // 接收路径的缓冲区
);
```

返回值 : 

- **成功**：返回写入缓冲区的字符数（不包括终止空字符 `\0`）。
- **失败**：
  - 如果缓冲区太小，返回**所需的缓冲区大小（包括 `\0`）**。
  - 其他错误返回 `0`，可调用 `GetLastError()`获取错误代码。

### GetModuleHandle

**获取已加载到进程地址空间中的模块的基址句柄**.

这里的模块主要是**DLL(动态库)和EXE(可执行文件)**.

许多通过扫描获取资源的函数需要传入模块句柄来指定开始扫描的地址.

**实际使用** : 

- **运行中获取函数地址**(`GetProcAddress`) :

  动态加载动态库函数, 相当于功能检测, 实际有此函数才会调用.

  ```cpp
  HMODULE hModule = GetModuleHandle(L"user32.dll");
  if (hModule) {
      typedef BOOL (*MessageBoxPtr)(HWND, LPCWSTR, LPCWSTR, UINT);
      MessageBoxPtr pMsgBox = (MessageBoxPtr)GetProcAddress(hModule, "MessageBoxW");
      if (pMsgBox) {
          pMsgBox(NULL, L"Hello", L"Dynamic Call", MB_OK);
      }
  }
  ```

  本质就是先看有没有`user32`这个库, 再去看有没有`MessageBoxW`这个函数.

- 获取模块的完整路径或信息(`GetModuleFileName`) : 

  ```cpp
  TCHAR path[MAX_PATH];
  GetModuleFileName(hModule, path, MAX_PATH);
  ```

- 动态加载嵌入在 DLL/EXE 中的资源, 如图标(`LoadResource`)

  ```cpp
  HRSRC hRes = FindResource(hModule, MAKEINTRESOURCE(IDR_ICON1), RT_ICON);
  if (hRes) {
      HGLOBAL hData = LoadResource(hModule, hRes);
      // 使用资源数据...
  }
  ```

### 版本检测

不同的版本会出现各种函数增删改的情况, 因此程序应当确定本身的适配版本和做好版本检测.

- Version Helpers (版本帮助函数) : 

  利用函数返回纯粹的布尔值进行判断, 效率高且简单易用.

  ```cpp
  #include <Windows.h>
  #include <VersionHelpers.h>
  #include <stdio.h>
  #include <locale>
  
  int main() {
      setlocale(LC_ALL, "");
      // 检测Windows版本
      if (IsWindows10OrGreater()) {
          wprintf(L"这是 Windows 10\n");
      }
      else if (IsWindows8Point1OrGreater()) {
          wprintf(L"这是 Windows 8.1\n");
      }
      else if (IsWindows8OrGreater()) {
          wprintf(L"这是 Windows 8\n");
      }
      else if (IsWindows7OrGreater()) {
          wprintf(L"这是 Windows 7\n");
      }
      else {
          wprintf(L"这是旧版 Windows\n");
      }
  
      // 检测是否为服务器版
      if (IsWindowsServer()) {
          wprintf(L"这是服务器版本\n");
      }
      else {
          wprintf(L"这是客户端版本(如家庭版、专业版等)\n");
      }
  
      // 防止控制台窗口立即关闭
      wprintf(L"\n按任意键退出...");
  
      return 0;
  }
  ```

- RtlGetVersion : 

  现代系统调用返回系统真实细致版本.

  ```cpp
  #include <windows.h>
  #include <winternl.h>
  #include <stdio.h>
  
  #pragma comment(lib, "ntdll.lib")
  
  typedef NTSTATUS(WINAPI* PRTLGETVERSION)(PRTL_OSVERSIONINFOW lpVersionInformation);
  
  int main()
  {
      RTL_OSVERSIONINFOW osVersionInfo = { 0 };
      osVersionInfo.dwOSVersionInfoSize = sizeof(osVersionInfo);
  
      HMODULE hNtDll = GetModuleHandleW(L"ntdll.dll");
      if (hNtDll)
      {
          PRTLGETVERSION pRtlGetVersion = (PRTLGETVERSION)GetProcAddress(hNtDll, "RtlGetVersion");
          if (pRtlGetVersion)
          {
              NTSTATUS status = pRtlGetVersion(&osVersionInfo);
              if (status == 0) // STATUS_SUCCESS
              {
                  wprintf(L"Windows Version: %d.%d.%d\n",
                      osVersionInfo.dwMajorVersion,
                      osVersionInfo.dwMinorVersion,
                      osVersionInfo.dwBuildNumber);
              }
              else
              {
                  wprintf(L"Failed to get version information. Status: 0x%X\n", status);
              }
          }
          else
          {
              wprintf(L"Failed to get RtlGetVersion function address.\n");
          }
      }
      else
      {
          wprintf(L"Failed to load ntdll.dll.\n");
      }
  
      return 0;
  }
  ```

  运行结果 : 

  ```cpp
  Windows Version: 10.0.22631
  ```

### 功能检测

比起版本检测, 功能检测愈来愈变为主流, 更加注重使用.

专门针对某些库(尤其是动态库), 某些库下的某些函数进行查询, 往往比做普通的版本检测更加精确.

```cpp
#include <Windows.h>
#include <stdio.h>
#include <locale>

// 检测特定DLL是否存在
BOOL IsFeatureAvailable(const wchar_t* featureName) {
    HMODULE hModule = LoadLibrary(featureName);
    if (hModule) {
        FreeLibrary(hModule);
        return TRUE;
    }
    return FALSE;
}

// 检测特定API是否存在
BOOL IsApiAvailable(const char* moduleName, const char* procName) {
    HMODULE hModule = GetModuleHandleA(moduleName);
    if (!hModule) {
        hModule = LoadLibraryA(moduleName);
        if (!hModule) return FALSE;
    }

    FARPROC proc = GetProcAddress(hModule, procName);
    return (proc != NULL);
}

int main() {
    setlocale(LC_ALL, "");

    // 检测特定DLL是否存在（表示功能可用）
    if (IsFeatureAvailable(L"api-ms-win-core-winrt-l1-1-0.dll")) {
        wprintf(L"Windows Runtime (WinRT) 可用\n");
    }

    if (IsFeatureAvailable(L"d3d12.dll")) {
        wprintf(L"DirectX 12 可用\n");
    }

    // 检测特定API是否存在
    if (IsApiAvailable("kernel32.dll", "GetTickCount64")) {
        wprintf(L"GetTickCount64 API 可用\n");
    }

    if (IsApiAvailable("user32.dll", "EnableNonClientDpiScaling")) {
        wprintf(L"DPI 缩放功能可用\n");
    }

    return 0;
}
```

运行结果 : 

```cpp
Windows Runtime (WinRT) 可用
DirectX 12 可用
GetTickCount64 API 可用
DPI 缩放功能可用
```

### 权限管理

普通应用进程都是以标准用户权限执行, 只能对自己用户空间的内容进行增删改. 

但是可以通过一些手段, 提升为管理员权限, 可对windows的几乎任何内容进行操作, 比如修改受保护的目录, 其他用户的文件, 修改系统时间等等.

- **用户账户控制机制 (UAC)**

  简单来讲, 如果有应用想要提升到管理员权限, 就一定会触发这个机制用于申请管理员权限, 通过显示一个弹窗告知其风险.

- 何时提升权限? 

  在我的认知中有三种提升方式 : 安装时提升, 运行前提升, 运行时提升.

- 运行时提升 : 

  在运行时调用`ShellExecuteEx`来启用一个高权限进程, 调用时会触发UAC.

- 运行前提升 : 

  在清单文件中设置 `requireAdministrator`, 那么程序启动便会触发UAC, 通过即是高权限.

- **安装时提升**(常用) : 

  在安装程序中触发UAC, 使得该应用以后获得管理员权限无需触发UAC. 

  并且引用可以采用**双进程设计**, 一个标准权限执行所有日常任务, 一条管理员权限在真正需要时使用. 可以采用**懒汉思想**, 在第一次需要使用管理员权限时再开辟这个进程.

### EnumProcesses(枚举进程)

Windows提供的用于枚举所有进程的函数, 会输出系统中当前运行的所有进程pid.

```cpp
DWORD pids[1024], cbNeeded;
EnumProcesses(pids, sizeof(pids), &cbNeeded);
```

使用pid便可获取进程句柄, 查询详细信息.

### 作业(Job Object)

有些应用需要同时开辟多个进程, 将其加入作业对象, 可以对多个进程进行统一快速的处理, 比如进行资源限制, 访问限制, 统一终止等等. 虽然这些操作单个进程通过其他操作也可以做到, 但是`Job Object`可以有**更快捷的API, 所做的限制都是硬性限制, 并且还是统一执行的**. (有需要的时候可以深入学习)

### GetCurrentProcess/Thread

调用此函数用于获取当前所在进程/线程句柄, 一般用于快捷获取进线程信息与设置.

- 需要注意的是, 该函数返回的是**伪句柄**, 也就是说并非再开辟一块空间存入当前进线程信息, 而是直接复用, 因此**不可用于跨线程用途**.

下面是获取当前进程时间信息的例子 : 

```cpp
FILETIME createTime, exitTime, kernelTime, userTime;
GetProcessTimes(GetCurrectProcess(), &createTime, &exitTime, &kernelTime, &userTime);
```

下面是设置进线程优先级的例子 : 

```cpp
SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS);
SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
```

### 进程挂起

其实挂起进程并不明确, 因为实际运行的只有进程中的线程, 因此并没有实际的进程挂起函数, 但我们可以通过遍历线程然后挂起每个线程达到实质上的进程挂起.

```cpp
#include <windows.h>
#include <tlhelp32.h>

void SuspendProcessByThreads(DWORD pid) {
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return;

    THREADENTRY32 te;
    te.dwSize = sizeof(te);

    if (Thread32First(hSnap, &te)) {
        do {
            if (te.th32OwnerProcessID == pid) {
                HANDLE hThread = OpenThread(THREAD_SUSPEND_RESUME, FALSE, te.th32ThreadID);
                if (hThread) {
                    SuspendThread(hThread);
                    CloseHandle(hThread);
                }
            }
        } while (Thread32Next(hSnap, &te));
    }
    CloseHandle(hSnap);
}
```

需要明确的是, 如果在遍历过程中有新线程的建立或旧线程的销毁的话, 这里其实是非常不安全的.

### 线程执行时间

通常在线程中在其实和结尾调用`GetThreadTimes`即可, 精确到毫秒.

如果需要更精确的时间, 可以使用`QueryThreadCycleTime`, 其返回的是本线程占用CPU的周期数, 用周期数换算出的时间将会是绝对精确的.

### 线程上下文

存在`CONTEXT`结构来保存线程的上下文数据(**执行位置/参数/局部变量**等), 我们可以通过`GetThreadContext`和`SetThreadContext`实现对上下文的读和写. 一般用于实现调试器等冷门要求. 

- 注意在调用前后要分别挂起和修复线程.

### 进/线程优先级

不同于Linux的公平调度, Windows则是**基于优先级的抢占式调度**, 因此设置进线程的优先级存在一定的必要性.

- **SetPriorityClass**

  设置进程优先级.

  ```cpp
  BOOL SetPriorityClass(HANDLE hProcess, DWORD dwPriorityClass);
  // SetPriorityClass(GetCurrentProcess(), IDLE_PRIORITY_CLASS)
  ```

  常见取值：

  - `IDLE_PRIORITY_CLASS`（空闲）
  - `BELOW_NORMAL_PRIORITY_CLASS`
  - `NORMAL_PRIORITY_CLASS`（默认）
  - `ABOVE_NORMAL_PRIORITY_CLASS`
  - `HIGH_PRIORITY_CLASS`
  - `REALTIME_PRIORITY_CLASS`（慎用！可能卡死系统）

- **SetThreadPriority** 

  设置线程优先级.

  ```cpp
  BOOL SetThreadPriority(HANDLE hThread, int nPriority);
  ```

  常见取值：

  - `THREAD_PRIORITY_LOWEST`
  - `THREAD_PRIORITY_BELOW_NORMAL`
  - `THREAD_PRIORITY_NORMAL`（默认）
  - `THREAD_PRIORITY_ABOVE_NORMAL`
  - `THREAD_PRIORITY_HIGHEST`
  - `THREAD_PRIORITY_TIME_CRITICAL`（危险，接近实时）

- 需要注意的是, 线程创建默认优先级就是normal, 因此如果想让线程在最开始保持低优先级, 不和其他线程竞争, 可以通过 起始挂起 + 修改优先级 + 恢复线程 这一套操作解决.

  ```cpp
  HANDLE hThread = CreateThread(nullptr, 0, ThreadFunc, nullptr, CREATE_SUSPENDED, nullptr);
  SetThreadPriority(hThread, THREAD_PRIORITY_BELOW_NORMAL);
  ResumeThread(hThread);
  ```

- 存在系统为某些线程自主提升优先级的行为, 目的是为了更速响应一些临时的事件(比如键盘敲击), 系统只提升优先级在1 - 15内的线程, 并且增加后会逐步回落到原值.

  可以通过调用`SetProcessPriorityBoost`禁止这种动态提升.

### 进/线程亲和性

人话说就是让某个进/线程更多在某些指定的CPU上运行, 以更好的利用缓存.

- SetProcessAffinityMask : 

  为进程设置亲和CPU.

  ```cpp
  BOOL SetProcessAffinityMask(
    HANDLE hProcess,
    DWORD_PTR dwProcessAffinityMask
  );
  ```

- SetThreadAffinityMask : 

  为线程设置亲和CPU.

  ```cpp
  DWORD_PTR SetThreadAffinityMask(
    HANDLE hThread,
    DWORD_PTR dwThreadAffinityMask
  );
  ```

  注意Mask是位置掩码, 通过比特位是否为1判断是否亲和对应的CPU.

- SetThreadIdealProcessor : 

  为线程设置一个推荐的CPU核, 系统会采纳意见.

  ```cpp
  DWORD SetThreadIdealProcessor(
    HANDLE hThread,
    DWORD  dwIdealProcessor  // 这里直接填数字就行
  );
  ```

- 实际使用还是`SetThreadAffinityMask`, 通常被用在**计算密集型**的线程任务上(比如音视频, 游戏引擎渲染), 这种任务对于缓存的使用会更加频繁.