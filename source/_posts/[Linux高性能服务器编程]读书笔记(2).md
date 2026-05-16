---
title: Linux高性能服务器编程 读书笔记(2)
date: 2025-2-13 19:31:00
tags: [Linux高性能服务器编程]
---

> **第六章 高级IO函数**

### pipe

```cpp
int pipe(int fd[2]);
```

- fd[0]对应读端, fd[1]对应写端

- 默认阻塞, 可设置为非阻塞
- 双端都存在引用计数功能, 写端引用计数为0读端read返回0, 读端引用计数为0写端write会失败并发出SIGPIPE信号
- 多用于父子进程间通信, 一边关闭读端, 一边关闭写端.

---

### dup / dup2

```cpp
int dup(int fd);
int dup2(int oldfd, int newfd);
```

#### 前置知识

- 文件描述符 : 用来标定已打开文件的整数, 进程中默认打开的三个操作符是stdio(0), stiout(1), stderro(2).
- 文件描述符以进程为单位, 每个进程都有一套独立的文件描述符, 从0开始, 进程开始就会使用0,1,2三个文件描述符, 分别代表输入/输出/报错.
- Linux下一切皆文件, 我们很多的行为都可以被解释为文件操作, 比如fork, socket, 只要有文件描述符, 我们就可以控制其读写.
- 可以创建文件描述符的操作 : open/pipe/socket/accept/fork等.
- 每次创建文件描述符时选择的值都是**从0开始当前进程中最小的未使用值**.

dup/dup2的作用主要就是**重定向文件描述符的输入输出**. 

dup的主要操作为 : 将一个新的文件描述符(和创建逻辑一致)重定向到fd, 返回这个新文件描述符.

dup2就是在dup的基础上, 可以指定这个新的文件描述符, 如果这个新的文件描述符已被占用, 就先关闭该描述符再重定向.

其实在实际使用中"新的文件描述符"一般都是三种标准文件描述符, 即将标准输入输入重定向到fd.

dup的使用比较意识流, 我们先看代码 : 

```cpp
#include <iostream>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <stdio.h>
#include <arpa/inet.h>
#include <string.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
using namespace std;

int main(int arg, char *argv[])
{
    const char *ip = argv[1];
    int port = atoi(argv[2]);

    struct sockaddr_in server;
    bzero(&server, sizeof(server));
    server.sin_family = AF_INET;
    server.sin_port = htons(port);
    inet_pton(AF_INET, ip, &server.sin_addr);

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    int ret = bind(sock, (struct sockaddr *)&server, sizeof(server));
    ret = listen(sock, 5);

    struct sockaddr_in client;
    socklen_t client_addrlength = sizeof(client);

    int connfd = accept(sock, (struct sockaddr *)&client, &client_addrlength);
    if (connfd < 0)
    {
        printf("Error: accept() failed.\n");
    }
    else
    {
        close(STDOUT_FILENO);
        dup(connfd);
        printf("Hello World\n");
        close(connfd);
    }

    close(sock);
    return 0;
}
```

这是一个简易的TCP网络代码, dup在这里的作用是把标准输出重定向到网络套接字, 过程如下 : 

- `close(STDOUT_FILENO);`关闭标准输入
- `dup(connfd);`选取从0开始当前进程中最小的未使用值, 那就是刚刚关闭的标准输出(1), 因此标准输出被重定向到了connfd.
- `printf("Hello World\n");`中的输出将被改为输出到connfd中, 其实就类似于使用了send将"Hello World\n"发送了出去.

加入换用dup2, 可以把close+dup替换为如下代码 : 

```cpp
dup2(connfd, STDOUT_FILENO);
```

dup2的使用一般比dup要方便直观不少, 所以日常中基本都是使用dup2.

#### 应用场景

- 将标准输入输出从重定向到打开的文件.
- 将标准输入输出从重定向到网络套接字. 
- 将标准输入输出从重定向到管道.
- 利用子进程会继承父进程文件描述符的特性, 在fork前使用dup2可以使后续的子进程重定向到相同的位置而无需多余操作, 在fork后使用dup2可以使父子进程输入输出到不同的文件, 这里的可操作空间很大. 如果不使用dup2可能还要创建多余的文件句柄等.

---

### readv / writev

后面的v指代vector, 作用在于输入输出到多个缓冲区(这里的缓冲区可以理解为内存).

```cpp
#include＜sys/uio.h＞
ssize_t readv(int fd,const struct iovec*vector,int count)；
ssize_t writev(int fd,const struct iovec*vector,int count);
```

相比于普通的read : 

```cpp
ssize_t read(int fd, void *buf, size_t count);
```

read只能读入一个缓冲区的内容, count代表buf的size.

readv可以读入多个缓冲区的内容, 多个缓冲区都被存在struct iovec中, count代表缓冲区的个数.

write和writev同理.

```cpp
char header_buf[BUFFER_SIZE];
...
char*file_buf;
...
struct iovec iv[2];
iv[0].iov_base = header_buf;            // 指向缓冲区的指针
iv[0].iov_len = strlen(header_buf);		// 缓冲区的size
iv[1].iov_base = file_buf;
iv[1].iov_len = file_stat.st_size;
ret = writev(connfd,iv,2);
```

在发送http回复时我们就可以将报头部分和文件部分存入iv中, 就可以实现将多个缓冲区中的内存发送, 而不必要将这两个部分合并再用write发送, 我们可以发现这可以避免不必要的拷贝和内存消耗.

---

### 内存的用户空间和内核空间

- 用户空间 : 用户程序运行的内存区域，包含应用程序的代码、数据和堆栈。用户程序在此空间运行，**无法直接访问硬件或内核资源**，必须通过系统调用请求内核协助.
- 内核空间 : 操作系统内核运行的内存区域，负责管理硬件、进程调度、内存分配等核心功能。只有内核代码能直接访问此区域，具有**最高权限**（如操作硬件、修改页表).
- 用户态和内核态的转换 : 
  - 这两种状态是CPU的运行状态, 一般处于用户态, 可以通过一些方式进入内核态.
  - 内核态拥有最高权限.
  - 内核态可以访问所有内存空间, 包括磁盘, 网络设备等, 用户态只可访问内存空间. 
  - 进入内核态的方式 : 系统调用(fork, open, read等), 硬件中断, 异常.

---

### sendfile

一种专用于文件网络传输的send.

```cpp
#include＜sys/sendfile.h＞
ssize_t sendfile(int out_fd, int in_fd, off_t*offset, size_t count);
```

- out_fd : 要输出到的socketfd, 这里必须是socket的fd.
- in_fd : 要输入的文件fd, 这里必须是真正文件的fd.
- offset : 要从in_fd偏移量为多少的位置开始读, 默认为0.
- count : 要读取的大小.

```cpp
sendfile(sockfd, filefd, NULL, stat_buf.st_size);
```

该函数的优势在于传输文件时不需要将其从磁盘搬到用户空间再发送, 而是直接在内核空间中就将磁盘中的数据发送到网络套接字中, 实现了**零拷贝**.

---

### mmap / munmap

一个用于申请一段内存空间将文件映射到该空间中的函数, 这个空间可以作为进程间通信的贡献内存. munmap用于释放该空间.

```cpp
#include＜sys/mman.h＞
void*mmap(void*start,size_t length,int prot,int flags,int fd,off_t offset);
int munmap(void*start,size_t length);
```

- start : 允许用户使用某个特定的地址作为这段内存的起始地址, 设置为NULL自动选择地址.
- length : 内存段的长度.
- port : 设置内存段的访问权限.
- flags : 控制内存段内容被修改后程序的行为.
- fd : 被映射文件对应的文件描述符.
- offset : 设置从文件的何处开始映射.

---

### splice 

用于两个文件描述符之间的数据移动, 所谓移动就是说读取完就没有了.

```cpp
#include <fcntl.h>
#include <unistd.h>
ssize_t splice(int fd_in, off_t *off_in, int fd_out, off_t *off_out, size_t len, unsigned int flags);
```

- fd_in : 执行输入的文件描述符.
- off_in : 对应偏移量的指针, 一般设NULL.
- fd_out : 接收输入的文件描述符.
- off_out : 同上.
- len : 输入数据的长度.
- flags : 控制数据如何移动.

splice可以在内核空间中实现不同文件描述符之间的信息传输, 而和管道结合可以将这种信息传输扩展到进程间通信, 而不只是在一个进程内传输, 由此可以实现**高效的进程间通信**.

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/uio.h>

#define BUFFER_SIZE 1024

int main() {
    int pipe_fds[2]; // 管道文件描述符
    pid_t pid;
    char *message = "Hello from parent process to child process using splice!";
    ssize_t bytes_spliced;

    // 创建管道
    if (pipe(pipe_fds) == -1) {
        perror("pipe failed");
        exit(EXIT_FAILURE);
    }

    pid = fork();
    if (pid < 0) {
        perror("fork failed");
        exit(EXIT_FAILURE);
    }

    if (pid > 0) {
        // 父进程：将数据写入管道
        close(pipe_fds[0]); // 关闭管道的读端

        // 将数据写入管道
        bytes_spliced = splice(STDOUT_FILENO, NULL, pipe_fds[1], NULL, BUFFER_SIZE, 0);
        if (bytes_spliced == -1) {
            perror("splice to pipe failed");
            exit(EXIT_FAILURE);
        }

        printf("Parent process wrote data to pipe: %zd bytes\n", bytes_spliced);
        close(pipe_fds[1]); // 关闭管道的写端

        // 等待子进程结束
        wait(NULL);
    } else {
        // 子进程：从管道中读取数据
        close(pipe_fds[1]); // 关闭管道的写端

        // 通过管道读取数据并将其输出
        char buf[BUFFER_SIZE];
        bytes_spliced = splice(pipe_fds[0], NULL, STDOUT_FILENO, NULL, BUFFER_SIZE, 0);
        if (bytes_spliced == -1) {
            perror("splice from pipe failed");
            exit(EXIT_FAILURE);
        }

        printf("Child process received data from pipe: %zd bytes\n", bytes_spliced);
        close(pipe_fds[0]); // 关闭管道的读端
    }

    return 0;
}
```

这段代码中父进程向子进程发送消息, 子进程可以接收到父进程中的消息, 并且由于splice一切都在内核空间中进行, 非常高效.

---

### tee

用于两个文件描述符之间的数据复制, 和splice用法一致, 但是数据读取后会留下了, 下次读取还在.

---

### struct stat

用于用于描述文件或文件系统对象的结构体. 使得进程可以通过stat, fstat, lstat获得文件的基本信息.

```cpp
struct stat {
    dev_t     st_dev;         /* 文件所在设备的 ID */
    ino_t     st_ino;         /* Inode 号 */
    mode_t    st_mode;        /* 文件类型和权限 */
    nlink_t   st_nlink;       /* 硬链接数 */
    uid_t     st_uid;         /* 所有者的用户 ID */
    gid_t     st_gid;         /* 所有者的组 ID */
    dev_t     st_rdev;        /* 设备 ID（如果是设备文件） */
    off_t     st_size;        /* 文件大小（字节数） */
    blksize_t st_blksize;     /* 文件系统 I/O 的块大小 */
    blkcnt_t  st_blocks;      /* 文件占用的块数 */

    /* 时间戳 */
    struct timespec st_atim;  /* 最后访问时间 */
    struct timespec st_mtim;  /* 最后修改时间 */
    struct timespec st_ctim;  /* 最后状态变更时间 */

    #define st_atime st_atim.tv_sec  /* 向后兼容：最后访问时间（秒） */
    #define st_mtime st_mtim.tv_sec  /* 向后兼容：最后修改时间（秒） */
    #define st_ctime st_ctim.tv_sec  /* 向后兼容：最后状态变更时间（秒） */
};
```

```cpp
int stat(const char *pathname, struct stat *statbuf);   // 用路径寻找文件信息,  statbuf都是输出型参数
int fstat(int fd, struct stat *statbuf);				// 用文件fd寻找文件信息
```

使用方法 : 

```cpp
struct stat stat_buf;
fstat(filefd, &stat_buf);  
...
sendfile(connfd,filefd,NULL,stat_buf.st_size);  // 这里sendfile的就会用到需要传输的文件大小
```

