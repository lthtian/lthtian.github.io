---
title: Linux高性能服务编程 读书笔记(7)
date: 2025-2-22
tags: [Linux高性能服务编程]
---

> 第13章 多进程编程

本章主要是讨论创建进程, 进程替换, 进程等待, 进程间通信, 最后一个占大头.

### 创建进程

```cpp
#include＜sys/types.h＞
#include＜unistd.h＞
pid_t fork(void); 
```

这个只需要记住返回值的判断 : 

- `< 0` : fork失败.
- `== 0 `: 属于子进程.

- `> 0` : 属于父进程.

子进程继承父进程的文件描述符表, 但是父进程设置的信号回调都回取消.

---

### 进程替换

```cpp
#include＜unistd.h＞
extern char**environ;
int execl(const char*path,const char*arg,...);
int execlp(const char*file,const char*arg,...);
int execle(const char*path,const char*arg,...,char*const envp[]);
int execv(const char*path,char*const argv[]);
int execvp(const char*file,char*const argv[]);
int execve(const char*path,char*const argv[],char*const envp[]);
```

---

### 进程等待

- 子进程退出之后, 父进程读取其退出状态之前, 子进程都处于僵尸态, 这会占据内核资源, 需要调用wait释放子进程.

```cpp
#include＜sys/types.h＞
#include＜sys/wait.h＞
pid_t wait(int*stat_loc);  // 等待任一进程
pid_t waitpid(pid_t pid,int*stat_loc,int options);  // 等待指定进程
```

默认都是阻塞的, 但是waitpid如果options设置了WHOHANG, 就会变成非阻塞.

当一个进程结束时, 会向父进程发送SIGCHLD信号, 我们可以捕获这个信号, 在信号回调函数中使用非阻塞waitpid.

```cpp
static void handle_child(int sig)
{
	pid_t pid;
	int stat;
	while((pid=waitpid(-1,＆stat,WNOHANG))＞0)
	{
		/*对结束的子进程进行善后处理*/
	}
}
```

---

### 进程间通信

一种最经典的进程间通信就是管道, 这里不再详述.

接下来详述三种无关联进程间的通信方式, 这里需要注意虽然是无关进程, 但都是同一主机下的进程, 是依靠主机单独在内核中开辟出一些内容物实现的.

### 信号量

我们首先要理解信号量是干什么的 : 

它主要用来**控制对共享资源的访问**,  与其说它是进程间的一种通信方式, 不如说它**可以管控进程间对共享内存的访问**, 其有一个信号量资源, 进程可以调用函数将信号量进行加减操作, 当信号量归0时, 会限制之后需要访问共享内存的进程(挂起), 可以理解为这是**一个有计数功能的专门针对共享资源的高级锁**.

信号量的核心理念是对信号量进行处理, **在设计共享资源的代码前后, 分别设置P操作和V操作**,  P代表passeren(进入), 会减少信号量; V代表vrijgeven(退出), 会增加信号量. PV操作都有对应的函数可以触发. 你可以类比为P操作就是加锁, V操作就解锁.

关于信号量的系统函数有两套 : 

- System V 信号量 : 早期信号量, 设置复杂, 但是老牌系统都在使用, 只适合多线程环境.
- POSIX 信号量 : 比较简单易用, 适合多线程环境.

我们先来学习System V信号量 : 

#### semget

```cpp
#include＜sys/sem.h＞
int semget(key_t key,int num_sems,int sem_flags);
```

这个函数用来创建一个新的信号量集. 

- key用来标识一个全局唯一的信号量集, 就是一个唯一关键字, 一般用ftok生成.

  ```cpp
  key_t ftok(const char *pathname, int proj_id);
  ```

- num_sems是要设置的信号量的数目, 一般就一个. 

- 最后一个一般0666, 设置访问权限.

#### semctl

```cpp
#include＜sys/sem.h＞
int semctl(int sem_id,int sem_num,int command,...);
```

这个函数是用来对建立的信号量集进行设置的函数, 

- sem_id : semget的返回值
- sem_num : 信号量集中的索引, 设置为0代表选择信号集中的第一个.
- command : 用来设置进行什么操作, SETVAL代表设置信号集, 后面加要设置的值.

由于刚建立默认的信号量为0, 无法使用, 必须通过这个函数设置信号量 : 

```cpp 
#define MAX_CONCURRENT 1   // 同一时刻只允许一个进程访问共享内存
semctl(sem_id, 0, SETVAL, MAX_CONCURRENT);
```

假如我们要共享的不是内存而是线程池, 那么这里就大有可为了, 可以根据当前线程池中线程的数量设置信号量, 可以对访问线程数进行限制.

#### semop

```cpp
int semop(int sem_id,struct sembuf*sem_ops,size_t num_sem_ops);
```

这函数用来进行实际的pv操作, sembuf的结构需要细致了解一下 : 

```cpp
struct sembuf{
	unsigned short int sem_num;  // 信号量的索引
    short int sem_op;			 // 操作的数量
	short int sem_flg;		     // 额外的属性
}
```

- 第一个参数还是如果为0默认选第一个.
- sem_op : p操作就是-1, v操作就是1.
- sem_flg : 一般推荐加上SEM_UNDO, 这个参数的作用是设置回滚操作, 也就是说p操作完, 如果在触发v操作前进程崩溃了, 也会将p操作改变的值恢复回去.

一般这样配置 : 

```cpp
// 定义信号量操作结构
struct sembuf p = {0, -1, SEM_UNDO};  // wait 操作
struct sembuf v = {0, 1, SEM_UNDO};   // post 操作
```

#### 示例：System V 信号量控制并发数量

假设我们有一个资源池，最多允许 3 个进程并发访问，我们会将信号量的初始值设置为 3。

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <unistd.h>

#define MAX_CONCURRENT 3

// 定义信号量操作结构
struct sembuf p = {0, -1, SEM_UNDO};  // wait 操作
struct sembuf v = {0, 1, SEM_UNDO};   // post 操作

int main() {
    key_t key = ftok("semfile", 65);   // 创建 IPC 键
    int sem_id = semget(key, 1, IPC_CREAT | 0666);  // 获取信号量

    // 设置初始信号量值为 3，表示允许 3 个进程并发访问
    semctl(sem_id, 0, SETVAL, MAX_CONCURRENT);

    // 模拟进程访问资源
    if (semop(sem_id, &p, 1) == -1) {  // 尝试获取信号量
        perror("semop p");
        exit(1);
    }

    // 访问共享资源
    printf("Process %d is accessing shared resource.\n", getpid());
    sleep(2);  // 模拟工作

    // 释放信号量
    if (semop(sem_id, &v, 1) == -1) {  
        perror("semop v");
        exit(1);
    }

    printf("Process %d finished accessing shared resource.\n", getpid());
    return 0;
}
```

---

### 共享内存

共享内存也是SystemV和POSIX各有一套函数, 这里使用POSIX的. 

简单来说就是向内核申请一块共享内存, 然后通过映射函数(mmap)将这块内存映射到进程的虚拟地址空间上, 使得进程操作这块内存可以像平常一样.

```cpp
#include＜sys/mman.h＞
#include＜sys/stat.h＞
#include＜fcntl.h＞
int shm_open(const char*name, int oflag, mode_t mode);
int shm_unlink(const char* name);
```

这个是用于申请创建共享内存的函数 : 

- name : 名字自己起, 最好是"/name"这种格式.
- oflag : 用于指定创建方式, O_RDONLY / O_RDWR / O_CREAT 
- mode : 一般是0666

```cpp
int ftruncate(int fd, off_t length);
```

这个函数通常要搭配shm_open使用, 它用于设定文件大小为length.

```cpp
#include＜sys/mman.h＞
void*mmap(void*start,size_t length,int prot,int flags,int fd,off_t offset);
int munmap(void*start,size_t length);
```

- start : 允许用户使用某个特定的地址作为这段内存的起始地址, 设置为NULL自动选择地址.
- length : 内存段的长度.
- port : 设置内存段的访问权限.
- flags : 控制内存段内容被修改后程序的行为.
- fd : 被映射文件对应的文件描述符, 这个通过shm_open生成.
- offset : 设置从文件的何处开始映射.

