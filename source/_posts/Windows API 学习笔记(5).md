---
title: Windows API 学习笔记(5) 注册表
date: 2025-9-10 15:00:00
tags: [WindowsAPI]
---

> 注册表

### 初步理解

注册表你可以理解为是一个**缓存和配置的存储中心**, 你可以在这里查到庞杂的信息, **系统信息, 硬件信息, 软件信息**都可以查到.

本身是**树形结构**, 非叶节点都可视为**键**, 最顶端并列的几个键被视为**根键**, 叶节点则可视为**值**, 我们一般都是通过传入一连串键的路径来获取值.

当然注册表只是记录一些偏固定的键值, 一些常变动的数据还要老实用系统API去查.

### RegOpenKeyEx

打开一个根键下子键路径的句柄, 你可以查该路径下的所有值.

```cpp
LSTATUS RegOpenKeyEx(
  HKEY    hKey,          // 根键句柄
  LPCSTR  lpSubKey,      // 子键路径
  DWORD   ulOptions,     // 选项, 默认0
  REGSAM  samDesired,    // 访问权限, 常用KEY_READ
  PHKEY   phkResult      // 接收打开的键句柄[输出]
);
```

### RegQueryValueEx

查询句柄对应路径下的任意值.

```cpp
LSTATUS RegQueryValueEx(
  HKEY    hKey,          // 已打开的键句柄
  LPCSTR  lpValueName,   // 值名称
  LPDWORD lpReserved,    // 保留参数, 默认nullptr
  LPDWORD lpType,        // 接收值类型
  LPBYTE  lpData,        // 接收数据的缓冲区
  LPDWORD lpcbData       // 缓冲区大小/接收数据大小
);
```

### 使用注册表获取各项数据

```cpp
#include <windows.h>
#include <stdio.h>

void ReadCPUInfo() {
    HKEY hKey;
    DWORD dwType, dwSize;
    CHAR processorName[256] = { 0 };
    DWORD processorSpeed = 0;

    // 打开CPU注册表键
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
        "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
        0, KEY_READ, &hKey) == ERROR_SUCCESS) {

        // 读取处理器名称
        dwSize = sizeof(processorName);
        if (RegQueryValueExA(hKey, "ProcessorNameString", NULL, &dwType,
            (LPBYTE)processorName, &dwSize) == ERROR_SUCCESS) {
            printf("CPU 型号: %s\n", processorName);
        }

        // 读取处理器速度(MHz)
        dwSize = sizeof(DWORD);
        if (RegQueryValueExA(hKey, "~MHz", NULL, &dwType,
            (LPBYTE)&processorSpeed, &dwSize) == ERROR_SUCCESS) {
            printf("CPU 频率: %u MHz\n", processorSpeed);
        }

        RegCloseKey(hKey);
    }
    else {
        printf("无法读取CPU信息\n");
    }
}

void ReadGPUInfo() {
    HKEY hKey;
    DWORD dwType, dwSize;
    CHAR gpuName[256] = { 0 };
    CHAR driverVersion[256] = { 0 };

    // 打开显卡注册表键
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
        "SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}\\0000",
        0, KEY_READ, &hKey) == ERROR_SUCCESS) {

        // 读取显卡名称
        dwSize = sizeof(gpuName);
        if (RegQueryValueExA(hKey, "DriverDesc", NULL, &dwType,
            (LPBYTE)gpuName, &dwSize) == ERROR_SUCCESS) {
            printf("显卡型号: %s\n", gpuName);
        }

        // 读取驱动版本
        dwSize = sizeof(driverVersion);
        if (RegQueryValueExA(hKey, "DriverVersion", NULL, &dwType,
            (LPBYTE)driverVersion, &dwSize) == ERROR_SUCCESS) {
            printf("驱动版本: %s\n", driverVersion);
        }

        RegCloseKey(hKey);
    }
    else {
        printf("无法读取显卡信息\n");
    }
}

void ReadOSVersion() {
    HKEY hKey;
    DWORD dwType, dwSize;
    CHAR productName[256] = { 0 };
    CHAR currentBuild[256] = { 0 };
    DWORD ubr = 0;

    // 打开Windows版本注册表键
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
        "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
        0, KEY_READ, &hKey) == ERROR_SUCCESS) {

        // 读取产品名称
        dwSize = sizeof(productName);
        if (RegQueryValueExA(hKey, "ProductName", NULL, &dwType,
            (LPBYTE)productName, &dwSize) == ERROR_SUCCESS) {
            printf("操作系统: %s\n", productName);
        }

        // 读取内部版本号
        dwSize = sizeof(currentBuild);
        if (RegQueryValueExA(hKey, "CurrentBuild", NULL, &dwType,
            (LPBYTE)currentBuild, &dwSize) == ERROR_SUCCESS) {
            printf("内部版本: %s\n", currentBuild);
        }

        // 读取UBR(Update Build Revision)
        dwSize = sizeof(DWORD);
        if (RegQueryValueExA(hKey, "UBR", NULL, &dwType,
            (LPBYTE)&ubr, &dwSize) == ERROR_SUCCESS) {
            printf("更新版本: %u\n", ubr);
        }

        RegCloseKey(hKey);
    }
    else {
        printf("无法读取操作系统信息\n");
    }
}

void ReadInstalledPrograms() {
    HKEY hKey;
    CHAR subKeyName[256];
    DWORD dwIndex = 0;
    DWORD dwSize = sizeof(subKeyName);

    printf("\n已安装程序列表:\n");

    // 打开32位程序注册表键
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
        "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
        0, KEY_READ, &hKey) == ERROR_SUCCESS) {

        // 枚举所有子键
        while (RegEnumKeyExA(hKey, dwIndex, subKeyName, &dwSize, NULL, NULL, NULL, NULL) == ERROR_SUCCESS) {
            HKEY hSubKey;
            CHAR displayName[256] = { 0 };
            CHAR displayVersion[256] = { 0 };

            // 打开每个程序的子键
            if (RegOpenKeyExA(hKey, subKeyName, 0, KEY_READ, &hSubKey) == ERROR_SUCCESS) {
                DWORD dwSubSize = sizeof(displayName);

                // 读取显示名称
                if (RegQueryValueExA(hSubKey, "DisplayName", NULL, NULL,
                    (LPBYTE)displayName, &dwSubSize) == ERROR_SUCCESS) {

                    // 读取版本号
                    dwSubSize = sizeof(displayVersion);
                    RegQueryValueExA(hSubKey, "DisplayVersion", NULL, NULL,
                        (LPBYTE)displayVersion, &dwSubSize);

                    printf("- %s (版本: %s)\n", displayName, displayVersion[0] ? displayVersion : "未知");
                }

                RegCloseKey(hSubKey);
            }

            dwIndex++;
            dwSize = sizeof(subKeyName);
        }

        RegCloseKey(hKey);
    }
    else {
        printf("无法读取已安装程序列表\n");
    }
}

void ReadNetworkAdapters() {
    HKEY hKey;
    CHAR subKeyName[256];
    DWORD dwIndex = 0;
    DWORD dwSize = sizeof(subKeyName);

    printf("\n网络适配器信息:\n");

    // 打开网络适配器注册表键
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
        "SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e972-e325-11ce-bfc1-08002be10318}",
        0, KEY_READ, &hKey) == ERROR_SUCCESS) {

        // 枚举所有子键
        while (RegEnumKeyExA(hKey, dwIndex, subKeyName, &dwSize, NULL, NULL, NULL, NULL) == ERROR_SUCCESS) {
            // 跳过0000-0005以外的键(它们是实际适配器)
            if (strlen(subKeyName) == 4 && isdigit(subKeyName[0])) {
                HKEY hSubKey;
                CHAR driverDesc[256] = { 0 };

                // 打开适配器子键
                if (RegOpenKeyExA(hKey, subKeyName, 0, KEY_READ, &hSubKey) == ERROR_SUCCESS) {
                    DWORD dwSubSize = sizeof(driverDesc);

                    // 读取适配器描述
                    if (RegQueryValueExA(hSubKey, "DriverDesc", NULL, NULL,
                        (LPBYTE)driverDesc, &dwSubSize) == ERROR_SUCCESS) {
                        printf("- %s\n", driverDesc);
                    }

                    RegCloseKey(hSubKey);
                }
            }

            dwIndex++;
            dwSize = sizeof(subKeyName);
        }

        RegCloseKey(hKey);
    }
    else {
        printf("无法读取网络适配器信息\n");
    }
}

int main() {
    printf("===== 计算机硬件和软件配置信息 =====\n");
    // 读取硬件信息
    printf("\n[硬件信息]\n");
    ReadCPUInfo();
    ReadGPUInfo();
    // 读取操作系统信息
    printf("\n[操作系统信息]\n");
    ReadOSVersion();
    // 读取网络信息
    ReadNetworkAdapters();
    // 读取软件信息
    ReadInstalledPrograms();
    return 0;
}
```

运行结果 : 

```cpp
===== 计算机硬件和软件配置信息 =====

[硬件信息]
CPU 型号: 13th Gen Intel(R) Core(TM) i7-13700H
CPU 频率: 2918 MHz
显卡型号: NVIDIA GeForce RTX 4060 Laptop GPU
驱动版本: 32.0.15.6607

[操作系统信息]
操作系统: Windows 10 Home China
内部版本: 22631
更新版本: 5768

网络适配器信息:
- Microsoft Kernel Debug Network Adapter
- Realtek PCIe GbE Family Controller
- Intel(R) Wi-Fi 6 AX201 160MHz
- Microsoft Wi-Fi Direct Virtual Adapter
- Bluetooth Device (Personal Area Network)
- Microsoft Wi-Fi Direct Virtual Adapter
- WAN Miniport (SSTP)
- WAN Miniport (IKEv2)
- WAN Miniport (L2TP)
- WAN Miniport (PPTP)
- WAN Miniport (PPPOE)
- WAN Miniport (IP)
- WAN Miniport (IPv6)
- WAN Miniport (Network Monitor)

已安装程序列表:
- 7-Zip 24.09 (x64) (版本: 24.09)
- Git (版本: 2.47.1.2)
- 微软OfficePLUS (版本: 3.8.0.13669)
- PremiumSoft Navicat Premium 17.0 (版本: 17.0.8)
- Notepad++ (64-bit x64) (版本: 8.6.7)
- Microsoft 365 - zh-cn (版本: 16.0.19127.20192)
- Microsoft OneNote - zh-cn (版本: 16.0.19127.20192)
- pot (版本: 3.0.6)
- Limbus Company (版本: 未知)
- 星引擎 Party (版本: 未知)
- 苏丹的游戏 (版本: 未知)
- 雨世界 (版本: 未知)
- Stardew Valley (版本: 未知)
- VcXsrv (版本: 1.20.14.0)
- Wacom 数位板 (版本: 6.4.6-2)
- 腾讯会议 (版本: 3.37.1.426)
- WinRAR 5.91 (64 位) (版本: 5.91.0)
- ARMOURY CRATE Service (版本: 5.9.14)
- ASUS Aac_NBDT HAL (版本: 2.5.23.0)
- Microsoft Visual C++ 2005 Redistributable (x64) (版本: 8.0.56336)
- ASUS Monitor Control (版本: 1.0.5)
- ASUS Keyboard HAL (版本: 1.2.21.0)
- ASUS Hotplug Controller (版本: 2.0.0)
- Microsoft Visual C++ 2010  x64 Redistributable - 10.0.40219 (版本: 10.0.40219)
- vs_communityx64msi (版本: 17.7.33906)
- MySQL Server 8.0 (版本: 8.0.26)
- ROG Live Service (版本: 2.4.26.0)
- vs_minshellinteropx64msi (版本: 17.7.33905)
- Typora (版本: 1.10.8)
- Microsoft Visual C++ 2012 x64 Additional Runtime - 11.0.61030 (版本: 11.0.61030)
- Java(TM) SE Development Kit 23.0.1 (64-bit) (版本: 23.0.1.0)
- Microsoft .NET Host - 8.0.8 (x64) (版本: 64.32.18380)
- Windows App Certification Kit Native Components (版本: 10.1.22621.1778)
- 天选姬 (版本: 3.7.0)
- Microsoft System CLR Types for SQL Server 2019 (版本: 15.0.2000.5)
- icecap_collection_x64 (版本: 16.11.34930)
- Microsoft Visual C++ 2022 X64 Debug Runtime - 14.36.32532 (版本: 14.36.32532)
- vs_Graphics_Singletonx64 (版本: 17.7.33906)
- Microsoft Visual C++ 2022 X64 Minimum Runtime - 14.40.33816 (版本: 14.40.33816)
- Universal CRT Tools x64 (版本: 10.1.22621.1778)
- Microsoft Visual C++ 2022 X64 Additional Runtime - 14.40.33816 (版本: 14.40.33816)
- MySQL Router 8.0 (版本: 8.0.26)
- Microsoft Windows Desktop Runtime - 8.0.8 (x64) (版本: 64.32.18376)
- Application Verifier x64 External Package (版本: 10.1.22000.194)
- TortoiseGit 2.12.0.0 (64 bit) (版本: 2.12.0.0)
- Microsoft Visual Studio Installer (版本: 3.14.2084.208)
- UE Prerequisites (x64) (版本: 1.0.22.0)
- MySQL Shell 8.0.26 (版本: 8.0.26)
- MySQL Workbench 8.0 CE (版本: 8.0.26)
- Microsoft .NET Host FX Resolver - 8.0.8 (x64) (版本: 64.32.18380)
- Microsoft Visual C++ 2008 Redistributable - x64 9.0.30729.17 (版本: 9.0.30729)
- Application Verifier x64 External Package (版本: 10.1.19041.685)
- Office 16 Click-to-Run Licensing Component (版本: 16.0.19029.20184)
- Office 16 Click-to-Run Extensibility Component (版本: 16.0.19127.20154)
- Office 16 Click-to-Run Localization Component (版本: 16.0.19127.20154)
- Microsoft Visual C++ 2013 x64 Additional Runtime - 12.0.21005 (版本: 12.0.21005)
- 认证客户端 V6.84 (版本: 6.84)
- ASUS Aac_GmAcc HAL (版本: 1.0.11.0)
- Microsoft .NET Runtime - 8.0.8 (x64) (版本: 64.32.18380)
- ASUS AURA Headset Component (版本: 1.3.47.0)
- Node.js (版本: 22.11.0)
- Microsoft Visual C++ 2013 x64 Minimum Runtime - 12.0.21005 (版本: 12.0.21005)
- ASUS AURA Display Component (版本: 1.2.29.0)
- NVIDIA 图形驱动程序 566.07 (版本: 566.07)
- NVIDIA GeForce Experience 3.28.0.417 (版本: 3.28.0.417)
- NVIDIA Optimus Update 39.5.0.0 (版本: 39.5.0.0)
- NVIDIA PhysX 系统软件 9.23.1019 (版本: 9.23.1019)
- NVIDIA 更新 39.5.0.0 (版本: 39.5.0.0)
- NVIDIA FrameView SDK 1.3.8513.32290073 (版本: 1.3.8513.32290073)
- NVIDIA SHIELD Streaming (版本: 7.1.33903191)
- NVIDIA GPX Common OSS binaries (POCO, OpenSSL, libprotobuf) (版本: 7.1)
- NVIDIA Install Application (版本: 2.1002.422.0)
- NVIDIA Backend (版本: 39.5.0.0)
- NVIDIA Container (版本: 1.40)
- NVIDIA TelemetryApi helper for NvContainer (版本: 1.40)
- NVIDIA LocalSystem Container (版本: 1.40)
- NVIDIA Message Bus for NvContainer (版本: 1.34)
- NVIDIA NVAPI Monitor plugin for NvContainer (版本: 1.0)
- NVIDIA NetworkService Container (版本: 1.40)
- NVIDIA Session Container (版本: 1.40)
- NVIDIA User Container (版本: 1.40)
- NVIDIA NvModuleTracker (版本: 6.14.26040.64835)
- NVIDIA NodeJS (版本: 3.28.0.417)
- NVIDIA Platform Controllers and Framework (版本: 560.46)
- NVIDIA Watchdog Plugin for NvContainer (版本: 1.40)
- NVIDIA Telemetry Client (版本: 18.1.13.0)
- NVIDIA Virtual Host Controller (版本: 3.05.0.1)
- Nvidia Share (版本: 3.28.0.417)
- NVIDIA ShadowPlay 3.28.0.417 (版本: 3.28.0.417)
- NVIDIA SHIELD Wireless Controller Driver (版本: 3.27.0.94)
- NVIDIA Update Core (版本: 39.5.0.0)
- NVIDIA Virtual Audio 4.65.0.3 (版本: 4.65.0.3)
- ASUS Mouse HAL (版本: 1.2.0.53)
- Application Verifier x64 External Package (DesktopEditions) (版本: 10.1.22621.1778)
- ASUS Mouse Extern HAL (版本: 1.2.0.6)
- ASUS MB Peripheral Products (版本: 1.0.40)
- VS JIT Debugger (版本: 17.0.125.0)
- icecap_collection_x64 (版本: 17.7.33905)
- AURA lighting effect add-on x64 (版本: 0.0.44)
- Application Verifier x64 External Package (OnecoreUAP) (版本: 10.1.22621.1778)
- Microsoft Update Health Tools (版本: 5.72.0.0)
- vs_minshellx64msi (版本: 17.7.33905)
- Microsoft Visual C++ 2012 x64 Minimum Runtime - 11.0.61030 (版本: 11.0.61030)
- ASUS Aura SDK (版本: 3.04.46)
- VS Script Debugging Common (版本: 17.0.125.0)
- Windows SDK DirectX x64 Remote (版本: 10.1.22621.1778)
- vs_devenx64vmsi (版本: 17.7.33905)
- DiagnosticsHub_CollectionService (版本: 17.3.32601)
```

我们可以发现, 当我们对某些数据有需求时, 可以先去查询可能存储这些数据的根键和子键路径, 如果查的到, 那么我们就可以用注册表获取这些数据.

在写代码时, 查询数据可以先通过注册表去查询, 查询不到再通过系统API获取目标信息.