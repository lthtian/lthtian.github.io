---
title: Windows API 学习笔记(3) 文件, 设备IO, 系统信息
date: 2025-9-8 20:30:00
tags: [WindowsAPI]
---

>文件, 设备IO, 系统信息

> 运行环境为vs2022

## 文件相关

### CreateFile

打开/创建文件, 返回文件句柄, 可设置访问权限, 是否共享, 覆盖还是追加.

```cpp
HANDLE CreateFile(
  LPCSTR                lpFileName,      // 文件名/设备名
  DWORD                 dwDesiredAccess, // 访问权限（读/写）
  DWORD                 dwShareMode,     // 共享模式
  LPSECURITY_ATTRIBUTES lpSecurityAttributes, // 安全属性（通常为NULL）
  DWORD                 dwCreationDisposition, // 创建方式（新建/打开等）
  DWORD                 dwFlagsAndAttributes,  // 文件属性（如缓存策略）
  HANDLE                hTemplateFile           // 模板文件（通常为NULL）
);
```

- **`dwDesiredAccess`**

  访问权限：

  - `GENERIC_READ`：只读
  - `GENERIC_WRITE`：只写
  - `GENERIC_READ | GENERIC_WRITE`：读写

- **`dwCreationDisposition`**

  文件存在/不存在时的行为：

  - `CREATE_NEW`：新建（若存在则失败）
  - `CREATE_ALWAYS`：覆盖已有文件
  - `OPEN_EXISTING`：打开已有文件（不存在则失败）
  - `OPEN_ALWAYS`：打开或创建
  - `TRUNCATE_EXISTING`：清空已有文件

### ReadFile / WriteFile

读写文件, 都会移动文件指针.

```cpp
BOOL ReadFile(
  HANDLE       hFile,          // CreateFile返回的句柄
  LPVOID       lpBuffer,       // 接收数据的缓冲区
  DWORD        nNumberOfBytesToRead, // 要读取的字节数
  LPDWORD      lpNumberOfBytesRead,  // 实际读取的字节数
  LPOVERLAPPED lpOverlapped          // 异步I/O结构（同步时为NULL）
);

BOOL WriteFile(
  HANDLE       hFile,          // 文件句柄
  LPCVOID      lpBuffer,       // 待写入的数据缓冲区
  DWORD        nNumberOfBytesToWrite, // 要写入的字节数
  LPDWORD      lpNumberOfBytesWritten, // 实际写入的字节数
  LPOVERLAPPED lpOverlapped           // 异步I/O结构
);
```

### 文件读写实操

向文件追加"hello world!", 并读出.

```cpp
#include<Windows.h>
#include<iostream>
#include<locale>

int main()
{
	setlocale(LC_ALL, "");

	HANDLE ret = CreateFile(
		L"test.txt",
		GENERIC_READ | GENERIC_WRITE, // 读写
		FILE_SHARE_READ,	// 可共享读
		nullptr,
		OPEN_ALWAYS,		// 优先打开, 没有再创建
		FILE_ATTRIBUTE_NORMAL, 
		nullptr
	);
	SetFilePointer(ret, 0, NULL, FILE_END); // 移动文件指针到末尾
	wchar_t buf[] = L"hello world!";
	DWORD realsize;
	WriteFile(ret, buf, sizeof(buf), &realsize, nullptr);

	SetFilePointer(ret, 0, NULL, FILE_BEGIN); // 移动文件指针到开头

	wchar_t rec[40] = {0};
	ReadFile(ret, rec, 26, &realsize, nullptr);
	
	std::wcout << rec << std::endl;
}
```



## 存储设备相关

### Windows文件系统

- 物理磁盘 : 最基础的物理结构, 存在分区用来管理.
- 卷 : 逻辑概念, 操作系统和用户直接交互的“存储容器”.
  - 就是常见的C盘, D盘, E盘.
  - 一个卷可以由一个或多个物理磁盘构成.
- 文件系统 : 软件概念, 对卷的上层构造, 用文件系统去描述卷, 进而去操作其底层的物理磁盘.

- 在Windows操作系统中, 物理磁盘和卷都是可以做为文件被打开的, 进而用来查询一些具体参数.

### DeviceIoControl

**可以用来访问打开的各种硬件, 获取各种参数与实际状态, 及用来和驱动（设备对象）通信.** (物理磁盘和卷便可访问)

```cpp
BOOL DeviceIoControl(
  HANDLE       hDevice,           // 设备句柄
  DWORD        dwIoControlCode,   // 控制代码
  LPVOID       lpInBuffer,        // 输入缓冲区
  DWORD        nInBufferSize,     // 输入缓冲区大小
  LPVOID       lpOutBuffer,       // 输出缓冲区
  DWORD        nOutBufferSize,    // 输出缓冲区大小
  LPDWORD      lpBytesReturned,   // 返回的字节数
  LPOVERLAPPED lpOverlapped       // 用于异步操作
);
```

看起来很复杂, 但核心都在**控制代码**处, 你在这里传入的参数用于表明你**想获取什么样的设备数据**, 在后面填入接收的缓冲区即可.

- `IOCTL_DISK_GET_DRIVE_GEOMETRY_EX` 获取磁盘的几何信息

  下面是向`DeviceIoControl`传入`IOCTL_DISK_GET_DRIVE_GEOMETRY_EX`来获取对应磁盘的几何信息的代码 : 

  ```cpp
  #include <windows.h>
  #include <winioctl.h>
  #include <stdio.h>
  #include <iostream>
  #include<locale>
  
  // 打印磁盘几何结构信息
  void PrintDiskGeometry(DISK_GEOMETRY_EX* diskGeometry) {
      printf("=== 磁盘物理几何结构 ===\n");
      printf("柱面数(Cylinders): %I64d\n", diskGeometry->Geometry.Cylinders.QuadPart);
      printf("磁头数(TracksPerCylinder): %lu\n", diskGeometry->Geometry.TracksPerCylinder);
      printf("每磁道扇区数(SectorsPerTrack): %lu\n", diskGeometry->Geometry.SectorsPerTrack);
      printf("每扇区字节数(BytesPerSector): %lu\n", diskGeometry->Geometry.BytesPerSector);
  
      // 计算并显示磁盘总大小
      ULONGLONG totalSize = diskGeometry->Geometry.Cylinders.QuadPart *
          diskGeometry->Geometry.TracksPerCylinder *
          diskGeometry->Geometry.SectorsPerTrack *
          diskGeometry->Geometry.BytesPerSector;
  
      printf("\n=== 磁盘容量计算 ===\n");
      printf("计算总容量: %I64u 字节\n", totalSize);
      printf("计算总容量: %.2f GB\n", (double)totalSize / (1024 * 1024 * 1024));
  
      // 显示DISK_GEOMETRY_EX中提供的磁盘大小
      printf("\n=== 实际磁盘大小 ===\n");
      printf("实际磁盘大小: %I64u 字节\n", diskGeometry->DiskSize.QuadPart);
      printf("实际磁盘大小: %.2f GB\n", (double)diskGeometry->DiskSize.QuadPart / (1024 * 1024 * 1024));
  }
  
  int main(int argc, char* argv[]) {
      setlocale(LC_ALL, "");
      // 默认查询PhysicalDrive0，或使用命令行参数
      wchar_t devicePath[32] = L"\\\\.\\PhysicalDrive0";
      if (argc > 1) {
          return 0;
      }
  
      wprintf(L"正在查询磁盘: %ls\n", devicePath);
  
      // 打开物理磁盘
      HANDLE hDevice = CreateFile(
          devicePath,
          GENERIC_READ,
          FILE_SHARE_READ | FILE_SHARE_WRITE,
          NULL,
          OPEN_EXISTING,
          0,
          NULL
      );
  
      if (hDevice == INVALID_HANDLE_VALUE) {
          DWORD err = GetLastError();
          printf("无法打开磁盘设备，错误代码: %lu\n", err);
  
          // 获取错误描述
          LPVOID errMsg;
          FormatMessage(
              FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM,
              NULL,
              err,
              0,
              (LPTSTR)&errMsg,
              0,
              NULL
          );
  
          std::wcout << L"错误描述: " << (wchar_t*)errMsg << std::endl;
          LocalFree(errMsg);
          return 1;
      }
  
      // 准备获取磁盘几何结构
      DISK_GEOMETRY_EX diskGeometry = { 0 };
      DWORD bytesReturned = 0;
  
      // 发送IOCTL请求
      BOOL result = DeviceIoControl(
          hDevice,
          IOCTL_DISK_GET_DRIVE_GEOMETRY_EX,
          NULL,
          0,
          &diskGeometry,
          sizeof(diskGeometry),
          &bytesReturned,
          NULL
      );
  
      if (!result) {
          DWORD err = GetLastError();
          printf("获取磁盘几何信息失败，错误代码: %lu\n", err);
  
          LPVOID errMsg;
          FormatMessage(
              FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM,
              NULL,
              err,
              0,
              (LPTSTR)&errMsg,
              0,
              NULL
          );
  
          printf("错误描述: %s\n", (char*)errMsg);
          LocalFree(errMsg);
          CloseHandle(hDevice);
          return 1;
      }
  
      // 打印获取到的信息
      PrintDiskGeometry(&diskGeometry);
  
      // 关闭设备句柄
      CloseHandle(hDevice);
      return 0;
  }
  ```

  运行结果 : 

  ```cpp
  正在查询磁盘: \\.\PhysicalDrive0
  === 磁盘物理几何结构 ===
  柱面数(Cylinders): 62260
  磁头数(TracksPerCylinder): 255
  每磁道扇区数(SectorsPerTrack): 63
  每扇区字节数(BytesPerSector): 512
  
  === 磁盘容量计算 ===
  计算总容量: 512105932800 字节
  计算总容量: 476.94 GB
  
  === 实际磁盘大小 ===
  实际磁盘大小: 512110190592 字节
  实际磁盘大小: 476.94 GB
  ```

- `IOCTL_STORAGE_QUERY_PROPERTY`  查询物理磁盘的属性

  ```cpp
  #include <windows.h>
  #include <winioctl.h>
  #include <iostream>
  #include <iomanip>
  #include <setupapi.h>
  #include <initguid.h>
  #include <devguid.h>
  #include <locale>
  #include <vector>
  
  using namespace std;
  
  void PrintStorageProperty(HANDLE hDevice) {
      STORAGE_PROPERTY_QUERY query{};
      query.PropertyId = StorageDeviceProperty;
      query.QueryType = PropertyStandardQuery;
  
      // 第一次调用获取所需缓冲区大小
      STORAGE_DESCRIPTOR_HEADER header{};
      DWORD bytesReturned = 0;
  
      if (!DeviceIoControl(
          hDevice,
          IOCTL_STORAGE_QUERY_PROPERTY,
          &query,
          sizeof(query),
          &header,
          sizeof(header),
          &bytesReturned,
          nullptr)) {
          wcerr << L"获取存储属性头信息失败，错误码: " << GetLastError() << endl;
          return;
      }
  
      // 分配缓冲区
      vector<BYTE> buffer(header.Size);
      auto descriptor = reinterpret_cast<STORAGE_DEVICE_DESCRIPTOR*>(buffer.data());
  
      if (!DeviceIoControl(hDevice, IOCTL_STORAGE_QUERY_PROPERTY,
          &query, sizeof(query), buffer.data(), header.Size, &bytesReturned, nullptr)) {
          wcerr << L"错误: " << GetLastError() << endl;
          return;
      }
  
      // 安全地获取字符串信息
      auto GetStringFromOffset = [&](DWORD offset) -> const char* {
          return (offset > 0 && offset < header.Size) ?
              reinterpret_cast<const char*>(buffer.data() + offset) : "N/A";
          };
  
      wcout << L"=== 磁盘设备信息 ===" << endl;
      wcout << L"制造商: " << GetStringFromOffset(descriptor->VendorIdOffset) << endl;
      wcout << L"型号: " << GetStringFromOffset(descriptor->ProductIdOffset) << endl;
      wcout << L"固件版本: " << GetStringFromOffset(descriptor->ProductRevisionOffset) << endl;
      wcout << L"序列号: " << GetStringFromOffset(descriptor->SerialNumberOffset) << endl;
  
      wcout << L"总线类型: ";
      switch (descriptor->BusType) {
      case BusTypeUnknown: wcout << L"未知"; break;
      case BusTypeScsi: wcout << L"SCSI"; break;
      case BusTypeAtapi: wcout << L"ATAPI"; break;
      case BusTypeAta: wcout << L"ATA"; break;
      case BusType1394: wcout << L"IEEE 1394"; break;
      case BusTypeSsa: wcout << L"SSA"; break;
      case BusTypeFibre: wcout << L"光纤通道"; break;
      case BusTypeUsb: wcout << L"USB"; break;
      case BusTypeRAID: wcout << L"RAID"; break;
      case BusTypeiScsi: wcout << L"iSCSI"; break;
      case BusTypeSas: wcout << L"SAS"; break;
      case BusTypeSata: wcout << L"SATA"; break;
      case BusTypeSd: wcout << L"SD"; break;
      case BusTypeMmc: wcout << L"MMC"; break;
      case BusTypeVirtual: wcout << L"虚拟"; break;
      case BusTypeFileBackedVirtual: wcout << L"文件虚拟"; break;
      case BusTypeSpaces: wcout << L"存储空间"; break;
      case BusTypeNvme: wcout << L"NVMe"; break;
      case BusTypeSCM: wcout << L"SCM"; break;
      case BusTypeUfs: wcout << L"UFS"; break;
      case BusTypeMax: wcout << L"最大"; break;
      default: wcout << L"未知 (" << descriptor->BusType << L")";
      }
      wcout << endl;
  
      wcout << L"命令队列支持: " << (descriptor->CommandQueueing ? L"是" : L"否") << endl;
  }
  
  int main() {
      setlocale(LC_ALL, "");
      // 打开磁盘0
      HANDLE hDevice = CreateFileW(
          L"\\\\.\\PhysicalDrive0",
          GENERIC_READ,
          FILE_SHARE_READ | FILE_SHARE_WRITE,
          nullptr,
          OPEN_EXISTING,
          0,
          nullptr);
  
      if (hDevice == INVALID_HANDLE_VALUE) {
          wcerr << L"无法打开磁盘设备，错误码: " << GetLastError() << endl;
          return 1;
      }
  
      // 查询并打印磁盘信息
      PrintStorageProperty(hDevice);
  
      CloseHandle(hDevice);
      return 0;
  }
  ```

  运行结果 : 

  ```cpp
  === 磁盘设备信息 ===
  制造商: NVMe
  型号: WD PC SN740 SDDPNQD-512G-1002
  固件版本: 73101000
  序列号: E823_8FA6_BF53_0001_001B_448B_4A8D_25AA.
  总线类型: NVMe
  命令队列支持: 是
  ```

这里只是介绍了获取设备信息的用途, 但实际其可以与各种设备进行交互, 设置与输出.

### GetDiskFreeSpace / GetDiskFreeSpaceEx

获取**卷(盘)的空间信息**, 包括总容量, 可用空间等. 前者为旧版, 后者为新版常用.

一般用来在备份或云空间存储时根据空间信息进行灵活判断.

```cpp
BOOL GetDiskFreeSpace(
  LPCTSTR lpRootPathName,
  LPDWORD lpSectorsPerCluster,
  LPDWORD lpBytesPerSector,
  LPDWORD lpNumberOfFreeClusters,
  LPDWORD lpTotalNumberOfClusters
);

BOOL GetDiskFreeSpaceEx(
  LPCTSTR lpDirectoryName,               // [输入] 要查询的路径
  PULARGE_INTEGER lpFreeBytesAvailable,  // [输出] 当前用户可用空间（考虑配额）
  PULARGE_INTEGER lpTotalNumberOfBytes,  // [输出] 卷总容量
  PULARGE_INTEGER lpTotalNumberOfFreeBytes // [输出] 物理剩余空间（忽略配额）
);
```

下面是获取C盘信息的代码 : 

```cpp
#include <windows.h>
#include <iostream>
#include <iomanip>
#include <string>
#include <string>
#include <locale>

// 将字节数转换为易读格式 (GB/MB/KB)
std::wstring FormatBytes(ULONGLONG bytes) {
    const double KB = 1024.0;
    const double MB = KB * 1024;
    const double GB = MB * 1024;

    if (bytes >= GB) {
        return std::to_wstring(bytes / GB) + L" GB";
    }
    else if (bytes >= MB) {
        return std::to_wstring(bytes / MB) + L" MB";
    }
    else if (bytes >= KB) {
        return std::to_wstring(bytes / KB) + L" KB";
    }
    return std::to_wstring(bytes) + L" Bytes";
}

void PrintDiskSpaceInfo(const wchar_t* drivePath) {
    ULARGE_INTEGER freeBytesAvailable;
    ULARGE_INTEGER totalBytes;
    ULARGE_INTEGER totalFreeBytes;

    if (GetDiskFreeSpaceEx(drivePath, &freeBytesAvailable, &totalBytes, &totalFreeBytes)) {

        std::wcout << L"=== 磁盘空间信息 (" << drivePath << L") ===" << std::endl;
        std::wcout << L"总容量: " << FormatBytes(totalBytes.QuadPart) << std::endl;
        std::wcout << L"可用空间: " << FormatBytes(freeBytesAvailable.QuadPart) << std::endl;
        std::wcout << L"实际空闲: " << FormatBytes(totalFreeBytes.QuadPart) << std::endl;

        // 计算已用空间百分比
        if (totalBytes.QuadPart > 0) {
            double usedPercent = 100.0 - (100.0 * freeBytesAvailable.QuadPart / totalBytes.QuadPart);
            std::wcout << L"已用空间: " << std::fixed << std::setprecision(2) << usedPercent << L"%" << std::endl;
        }
    }
    else {
        std::wcerr << L"获取磁盘信息失败! 错误代码: " << GetLastError() << std::endl;
    }
}

int main() {
    setlocale(LC_ALL, "");
    // 查询C盘信息
    const wchar_t* cDrive = L"C:\\";
    PrintDiskSpaceInfo(cDrive);

    return 0;
}
```

运行结果 : 

```cpp
=== 磁盘空间信息 (C:\) ===
总容量: 148.380192 GB
可用空间: 2.701382 GB
实际空闲: 2.701382 GB
已用空间: 98.18%
```

肉眼可见的已经爆红了qwq.

### GetVolumeInformation

获取**卷的基础信息**, 比如卷名称, 序列号, 最大文件名长, 文件系统等.

```cpp
BOOL GetVolumeInformation(
  LPCTSTR lpRootPathName,          // 根路径（如 "C:\\"）
  LPTSTR lpVolumeNameBuffer,        // 接收卷标名称的缓冲区
  DWORD nVolumeNameSize,           // 卷标缓冲区大小
  LPDWORD lpVolumeSerialNumber,     // 接收卷序列号
  LPDWORD lpMaximumComponentLength, // 最大文件名长度
  LPDWORD lpFileSystemFlags,       // 文件系统特性标志
  LPTSTR lpFileSystemNameBuffer,   // 接收文件系统名称的缓冲区
  DWORD nFileSystemNameSize        // 文件系统名称缓冲区大小
);
```

下面检查各种可能的卷, 然后输出对应卷的基础属性 :

```cpp
#include <windows.h>
#include <iostream>
#include <vector>
#include <locale>

using namespace std;

void CheckVolumeType(const wstring& path) {
    wcout << L"检查卷: " << path;

    // 1. 先检查是否是有效卷
    UINT driveType = GetDriveType(path.c_str());
    const wchar_t* typeName;
    switch (driveType) {
    case DRIVE_FIXED:      typeName = L"本地硬盘"; break;
    case DRIVE_REMOVABLE: typeName = L"可移动设备(U盘等)"; break;
    case DRIVE_CDROM:      typeName = L"光盘驱动器"; break;
    case DRIVE_REMOTE:    typeName = L"网络驱动器"; break;
    case DRIVE_RAMDISK:   typeName = L"RAM磁盘"; break;
    default:              typeName = L"未知/无效"; break;
    }
    wcout << L" ← " << typeName << endl;

    // 2. 获取卷详细信息
    WCHAR volName[MAX_PATH] = { 0 };
    WCHAR fsName[MAX_PATH] = { 0 };
    DWORD serial, maxLen, flags;

    if (GetVolumeInformation(path.c_str(), volName, MAX_PATH, &serial,
        &maxLen, &flags, fsName, MAX_PATH)) {
        wcout << L"  卷标: " << volName << endl;
        wcout << L"  文件系统: " << fsName << endl;
        wcout << L"  序列号: " << hex << serial << dec << endl;
    }
    else {
        wcout << L"  无法获取信息 (错误: " << GetLastError() << L")" << endl;
    }
    wcout << endl;
}

int main() {
    setlocale(LC_ALL, "");
    // 测试各种可能的Volume
    vector<wstring> testPaths = {
        L"C:\\",    // 系统盘
        L"D:\\",    // 其他硬盘分区
        L"E:\\",    // U盘/移动硬盘
        L"F:\\",    // 光盘驱动器
        L"Z:\\",    // 网络映射驱动器
        L"X:\\"     // 可能不存在的驱动器
    };

    for (const auto& path : testPaths) {
        CheckVolumeType(path);
    }

    return 0;
}
```

运行结果 : 

```cpp
检查卷: C:\ ← 本地硬盘
  卷标: OS
  文件系统: NTFS
  序列号: c22b1551

检查卷: D:\ ← 本地硬盘
  卷标:
  文件系统: NTFS
  序列号: 3a7e1748

检查卷: E:\ ← 本地硬盘
  卷标:
  文件系统: NTFS
  序列号: 60a00693

检查卷: F:\ ← 未知/无效
  无法获取信息 (错误: 3)

检查卷: Z:\ ← 未知/无效
  无法获取信息 (错误: 3)

检查卷: X:\ ← 未知/无效
  无法获取信息 (错误: 3)
```



## 系统信息相关

### GetSystemInfo 

获取操作系统硬件相关的信息. 如CPU数, 处理器类型, 内存页大小.

```cpp
void GetSystemInfo(LPSYSTEM_INFO lpSystemInfo);
```

### GlobalMemoryStatusEx

获取当前内存使用情况, 包括物理内存, 虚拟内存的总量和可用量.

```cpp
BOOL GlobalMemoryStatusEx(LPMEMORYSTATUSEX lpBuffer);
```

### GetSystemTime

获取系统当前的UTC(协调世界时, 北京时区需要 + 8时).

```cpp
void GetSystemTime(LPSYSTEMTIME lpSystemTime);
```

### GetTickCount

获取自系统启动以来的毫秒数(32 位整数).

```cpp
DWORD GetTickCount(void);
```

### 测试代码

```cpp
#include <windows.h>
#include <iostream>

using namespace std;

void PrintSystemInfo() {
    SYSTEM_INFO si;
    GetSystemInfo(&si);

    cout << "=== 系统信息 ===" << endl;
    cout << "CPU 核心数: " << si.dwNumberOfProcessors << endl;
    cout << "页面大小: " << si.dwPageSize << " 字节" << endl;
    cout << "处理器架构: ";
    switch (si.wProcessorArchitecture) {
    case PROCESSOR_ARCHITECTURE_AMD64: cout << "x64 (AMD or Intel)" << endl; break;
    case PROCESSOR_ARCHITECTURE_INTEL: cout << "x86" << endl; break;
    case PROCESSOR_ARCHITECTURE_ARM:   cout << "ARM" << endl; break;
    default: cout << "未知" << endl; break;
    }
    cout << endl;
}

void PrintMemoryStatus() {
    MEMORYSTATUSEX ms;
    ms.dwLength = sizeof(ms);

    if (GlobalMemoryStatusEx(&ms)) {
        cout << "=== 内存信息 ===" << endl;
        cout << "物理内存总量: " << (ms.ullTotalPhys / (1024 * 1024)) << " MB" << endl;
        cout << "可用物理内存: " << (ms.ullAvailPhys / (1024 * 1024)) << " MB" << endl;
        cout << "内存使用率: " << ms.dwMemoryLoad << " %" << endl;
        cout << endl;
    }
}

void PrintSystemTime() {
    SYSTEMTIME st;
    GetSystemTime(&st);

    cout << "=== 系统时间 (UTC) ===" << endl;
    cout << st.wYear << "-" << st.wMonth << "-" << st.wDay << " "
        << st.wHour << ":" << st.wMinute << ":" << st.wSecond
        << "." << st.wMilliseconds << endl;
    cout << endl;
}

void PrintUptime() {
    ULONGLONG ms = GetTickCount64();
    ULONGLONG sec = ms / 1000;
    ULONGLONG min = sec / 60;
    ULONGLONG hr = min / 60;
    ULONGLONG day = hr / 24;

    cout << "=== 系统运行时长 ===" << endl;
    cout << "已运行: " << day << " 天 "
        << (hr % 24) << " 小时 "
        << (min % 60) << " 分钟 "
        << (sec % 60) << " 秒" << endl;
    cout << endl;
}

int main() {
    PrintSystemInfo();
    PrintMemoryStatus();
    PrintSystemTime();
    PrintUptime();

    system("pause");
    return 0;
}
```

运行结果 : 

```cpp
=== 系统信息 ===
CPU 核心数: 20
页面大小: 4096 字节
处理器架构: x64 (AMD or Intel)

=== 内存信息 ===
物理内存总量: 16010 MB
可用物理内存: 3569 MB
内存使用率: 77 %

=== 系统时间 (UTC) ===
2025-9-8 11:42:5.720

=== 系统运行时长 ===
已运行: 4 天 5 小时 16 分钟 53 秒
```

