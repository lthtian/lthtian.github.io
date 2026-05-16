---
title: Windows API 学习笔记(4) IOCP
date: 2025-9-9 20:37:00
tags: [WindowsAPI, IOCP]
---

> IOCP高性能网络编程

### 初步理解

**IOCP(IO Completion Port), IO完成端口**, 是可以将**网络数据收发异步化**的技术.

如果学过Linux的io_uring, 他们的内核思想很相近, 区别在于IOCP**专注于网络编程和异步**, 而io_uring更加全面, 可以处理并优化各种事务. 

### 内核理解

- 首先想要使用IOCP, 需要通过`CreateIoCompletionPort`构造IOCP句柄.
- 构造句柄的同时, 内部会维护两个队列(任务队列和完成队列)和一个内核区域, 收发任务会将任务投递到任务队列中, 内核从任务队列中取出任务并执行.
- 等实际的接收或发送完毕后, 内核会把其推到完成队列中, 我们会开辟多个线程调用`GetQueuedCompletionStatus`阻塞等待, 从完成队列中取出结果, 并根据结果执行对应的操作.
- 这里做到的是真异步, 并且这种异步十分高效, 可以有效提高并发量. (主要体现在于没有多余的阻塞, 建立连接/收发数据都在内核中, 可以马上收马上做).

> 内核思想比较容易理解, 但是实际还有许多复杂的细节, 下面将会介绍一个重要概念和常用API.

### 重叠I/O

IOCP编程中一定会看到`WSAOVERLAPPED`这个类型, 通常被叫做重叠I/O, 这是一个看起来很唬人的概念, 但简单理解你可以认为这就是一个**标识符**, 用于表示**我要使用异步IO, 所有IO操作都在内核执行**, 因此想要使用IOCP, 就**必须为所有收发函数传入该标识符**.

另外你可以认为其有着一定**存储上下文**的能力, 因此**每次使用都要清空内部**, 便于内核使用.

至此使用方式就非常明朗了, 就是有使用收发函数时传入一个已经清空的`WSAOVERLAPPED`对象.

### CreateIoCompletionPort

创建 IOCP句柄 或将文件/套接字句柄关联到现有 IOCP句柄.

```cpp
HANDLE CreateIoCompletionPort(
    HANDLE FileHandle,           // 文件句柄或 socket
    HANDLE ExistingCompletionPort, // 已存在的 IOCP，如果为 NULL 则创建新端口
    ULONG_PTR CompletionKey,     // 与句柄关联的用户数据
    DWORD NumberOfConcurrentThreads // 线程并发数，0 表示系统决定
);
```

- 第二个参数传入IOPC句柄 : 
  - 如果为nullptr, 那么表示要创建新的端口, 会返回新的IOPC句柄, 并且和第一个参数关联.
  - 如果为IOPC句柄, 表示将对应文件或socket关联到该句柄上.

### GetQueuedCompletionStatus

获取任务结果的线程用于**阻塞等待 IOCP 完成事件**.

```cpp
BOOL GetQueuedCompletionStatus(
    HANDLE CompletionPort,					// IOPC句柄
    LPDWORD lpNumberOfBytesTransferred,		// 完成的 I/O 字节数
    PULONG_PTR lpCompletionKey,				// CreateIoCompletionPort中传入的key
    LPOVERLAPPED *lpOverlapped,				// 重叠 I/O 对象
    DWORD dwMilliseconds					// 超时, INFINITE表示永久阻塞
);
```

### WSASend

Windows的send. (WSA是Windows Socket API的缩写)

```cpp
int WSASend(
    SOCKET s,							// socket
    LPWSABUF lpBuffers,					// 发送缓冲区, 可以存在多个, 类比writev
    DWORD dwBufferCount,				// 缓冲区个数
    LPDWORD lpNumberOfBytesSent,		// 输出实际发送了多少字节
    DWORD dwFlags,					
    LPWSAOVERLAPPED lpOverlapped,		// 重叠 I/O 对象
    LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine
);
```

和send使用类似, 但是想使用IOCP需要注意以下亮点 : 

- socket必须已经通过`CreateIoCompletionPort`和IOCP句柄发生关联.
- 必须传入重叠 I/O 对象.

下面的recv同理.

### WSARecv

```cpp
int WSARecv(
    SOCKET s,
    LPWSABUF lpBuffers,
    DWORD dwBufferCount,
    LPDWORD lpNumberOfBytesRecvd,
    LPDWORD lpFlags,
    LPWSAOVERLAPPED lpOverlapped,
    LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine
);
```

### AcceptEx

accept的异步版本, 可以配合IOPC使用.

```cpp
BOOL AcceptEx(
    SOCKET sListenSocket,      // [in] 监听套接字
    SOCKET sAcceptSocket,      // [in] 接受连接的套接字
    PVOID lpOutputBuffer,      // [out] 接收缓冲区，AcceptEx 会把客户端和本地地址信息写入其中
    DWORD dwReceiveDataLength, // [in] 预接收数据长度，如果客户端发送了初始数据，会被提前读入缓冲区
    DWORD dwLocalAddressLength,// [in] 本地地址结构长度，通常 sizeof(sockaddr_in) + 16
    DWORD dwRemoteAddressLength,// [in] 远程地址结构长度，通常 sizeof(sockaddr_in) + 16
    LPDWORD lpdwBytesReceived, // [out] 实际接收到的字节数（初始数据）
    LPOVERLAPPED lpOverlapped  // [in] OVERLAPPED 结构，用于异步通知 I/O 完成
);

```

### 回显服务器

下面是一个回显服务器, 实现对发送的每个字符进行回显.

其中几乎所有操作都是异步的, 包括读写和接收新连接.

```cpp
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <mswsock.h>
#include <windows.h>
#include <iostream>
#include <thread>

#pragma comment(lib, "ws2_32.lib")

// -------------------- 上下文结构 --------------------
struct PER_IO_CONTEXT {
    WSAOVERLAPPED overlapped;
    WSABUF buf;
    char data[1024];
    char acceptBuffer[(sizeof(sockaddr_in) + 16) * 2]; // AcceptEx buffer
    DWORD bytes;
    int operation; // 0=RECV, 1=SEND, 2=ACCEPT
    SOCKET sock;
};

// -------------------- 全局变量 --------------------
LPFN_ACCEPTEX g_lpfnAcceptEx = nullptr;
SOCKET g_listenSock;
HANDLE g_iocp;

// -------------------- 投递新的 AcceptEx --------------------
void PostAccept(PER_IO_CONTEXT* ctx) {
    ZeroMemory(&ctx->overlapped, sizeof(ctx->overlapped));
    ctx->sock = WSASocket(AF_INET, SOCK_STREAM, 0, NULL, 0, WSA_FLAG_OVERLAPPED);
    ctx->operation = 2; // ACCEPT
    ctx->buf.buf = ctx->acceptBuffer;
    ctx->buf.len = sizeof(ctx->acceptBuffer);

    DWORD bytes = 0;
    BOOL ret = g_lpfnAcceptEx(g_listenSock, ctx->sock, ctx->buf.buf,
        0, sizeof(sockaddr_in) + 16, sizeof(sockaddr_in) + 16,
        &bytes, &ctx->overlapped);
    if (!ret && WSAGetLastError() != ERROR_IO_PENDING) {
        std::cout << "[DEBUG] AcceptEx failed: " << WSAGetLastError() << "\n";
        closesocket(ctx->sock);
        delete ctx;
    }
    else {
        std::cout << "[DEBUG] AcceptEx posted, socket=" << ctx->sock << "\n";
    }
}

// -------------------- IOCP 工作线程 --------------------
void WorkerThread(HANDLE iocp) {
    DWORD bytesTransferred;
    ULONG_PTR key;
    LPOVERLAPPED pol;

    while (true) {
        BOOL ok = GetQueuedCompletionStatus(iocp, &bytesTransferred, &key, &pol, INFINITE);
        if (!ok) {
            if (pol) {
                PER_IO_CONTEXT* ctx = (PER_IO_CONTEXT*)pol;
                std::cout << "[DEBUG] GetQueuedCompletionStatus error, socket=" << ctx->sock
                    << ", error=" << WSAGetLastError() << "\n";
                closesocket(ctx->sock);
                delete ctx;
            }
            continue;
        }

        PER_IO_CONTEXT* ctx = (PER_IO_CONTEXT*)pol;
        // 输出调试信息
        std::cout << "[DEBUG] Completion: operation=" << ctx->operation
            << ", bytes=" << bytesTransferred
            << ", socket=" << ctx->sock << "\n";

        if (ctx->operation == 2) { // ACCEPT 完成
            SOCKET clientSock = ctx->sock;
            // 关联 client 到 IOCP
            CreateIoCompletionPort((HANDLE)clientSock, g_iocp, (ULONG_PTR)clientSock, 0);
            std::cout << "[DEBUG] Client connected, socket=" << clientSock << "\n";

            // 立即投递 RECV
            ctx->operation = 0;
            ctx->buf.buf = ctx->data;
            ctx->buf.len = sizeof(ctx->data);
            DWORD flags = 0;
            ctx->bytes = 0;
            ZeroMemory(&ctx->overlapped, sizeof(ctx->overlapped));
            int ret = WSARecv(clientSock, &ctx->buf, 1, &ctx->bytes, &flags, &ctx->overlapped, NULL);
            if (ret == SOCKET_ERROR && WSAGetLastError() != WSA_IO_PENDING) {
                std::cout << "[DEBUG] WSARecv failed: " << WSAGetLastError() << "\n";
                closesocket(clientSock);
                delete ctx;
            }

            // 投递新的 AcceptEx
            PostAccept(new PER_IO_CONTEXT());
        }
        else if (ctx->operation == 0) { // RECV 完成
            if (bytesTransferred == 0) { // 客户端断开
                std::cout << "[DEBUG] Client disconnected, socket=" << ctx->sock << "\n";
                closesocket(ctx->sock);
                delete ctx;
                continue;
            }

            std::cout << "[DEBUG] Recv: " << std::string(ctx->data, bytesTransferred)
                << ", socket=" << ctx->sock << "\n";

            // 投递发送（回显）
            ctx->operation = 1;
            ctx->buf.len = bytesTransferred;
            DWORD sendBytes = 0;
            ZeroMemory(&ctx->overlapped, sizeof(ctx->overlapped));
            int ret = WSASend(ctx->sock, &ctx->buf, 1, &sendBytes, 0, &ctx->overlapped, NULL);
            if (ret == SOCKET_ERROR && WSAGetLastError() != WSA_IO_PENDING) {
                std::cout << "[DEBUG] WSASend failed: " << WSAGetLastError() << "\n";
                closesocket(ctx->sock);
                delete ctx;
            }
        }
        else if (ctx->operation == 1) { // SEND 完成
            // 再投递接收
            ctx->operation = 0;
            ctx->buf.len = sizeof(ctx->data);
            DWORD flags = 0;
            ctx->bytes = 0;
            ZeroMemory(&ctx->overlapped, sizeof(ctx->overlapped));
            int ret = WSARecv(ctx->sock, &ctx->buf, 1, &ctx->bytes, &flags, &ctx->overlapped, NULL);
            if (ret == SOCKET_ERROR && WSAGetLastError() != WSA_IO_PENDING) {
                std::cout << "[DEBUG] WSARecv failed: " << WSAGetLastError() << "\n";
                closesocket(ctx->sock);
                delete ctx;
            }
        }
    }
}

// -------------------- main --------------------
int main() {
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        std::cout << "[DEBUG] WSAStartup failed\n";
        return -1;
    }

    g_listenSock = WSASocket(AF_INET, SOCK_STREAM, 0, NULL, 0, WSA_FLAG_OVERLAPPED);

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(8888);
    bind(g_listenSock, (sockaddr*)&addr, sizeof(addr));
    listen(g_listenSock, SOMAXCONN);

    // 获取 AcceptEx 函数指针
    DWORD bytes;
    GUID guidAcceptEx = WSAID_ACCEPTEX;
    WSAIoctl(g_listenSock, SIO_GET_EXTENSION_FUNCTION_POINTER,
        &guidAcceptEx, sizeof(guidAcceptEx),
        &g_lpfnAcceptEx, sizeof(g_lpfnAcceptEx),
        &bytes, NULL, NULL);

    // 关联 listenSock 到 IOCP
    g_iocp = CreateIoCompletionPort((HANDLE)g_listenSock, NULL, 0, 0);
    if (!g_iocp) {
        std::cout << "[DEBUG] CreateIoCompletionPort failed: " << GetLastError() << "\n";
        return -1;
    }

    // 启动工作线程（CPU 核数 * 2）
    SYSTEM_INFO sysInfo;
    GetSystemInfo(&sysInfo);
    for (int i = 0; i < (int)sysInfo.dwNumberOfProcessors * 2; ++i) {
        std::thread(WorkerThread, g_iocp).detach();
    }

    std::cout << "[DEBUG] Server running on port 8888...\n";

    // 预投递若干 AcceptEx
    for (int i = 0; i < 5; ++i) {
        PostAccept(new PER_IO_CONTEXT());
    }

    // 主线程阻塞
    while (true) Sleep(1000);

    closesocket(g_listenSock);
    WSACleanup();
    return 0;
}
```

这段代码如果有统一事件源和异步经验的人读起来可能会更加方便.

下面说几点不太好理解的地方 : 

- `WSAIoctl`和`g_lpfnAcceptEx`的出现主要是因为`AcceptEx`并不在标准库里, 属于扩展, 这里是用`WSAIoctl`查找到了扩展库中的函数再匹配对应的`g_lpfnAcceptEx`以达到`AcceptEx`的效果.

  - 其实`AcceptEx`也并非必须, 完全可以使用accept同步阻塞接收新连接, 然后让收发异步就行. 将accept异步化主要是为例提高**初期并发量**, 让系统可以同时接收非常多的新连接(我这里就是开了5个异步accept, 也就是说同一时间有五个accept任务可被触发完成).

- 我们发现每个任务需要的数据都存在`PER_IO_CONTEXT`中了, 而任务间数据的传递是依托其顶部的`overlapped`来的, 具体是通过`PER_IO_CONTEXT* ctx = (PER_IO_CONTEXT*)pol;`**把重叠I/O对象指针强转为该结构体指针**来的. 

  这是IOCP编程常用的一种数据传递手段, 具体是因为`lpOverlapped`作为输出参数每个任务都独立存在, 把其放在首位, 正好可以强转出其他的结构体存放每个任务独立需要的数据或缓冲区.

- `WorkerThread`中执行的代码根据发布任务时存储的任务类型进行选择, 可以有效处理不同类型的事件.
