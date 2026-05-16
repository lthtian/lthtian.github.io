---
title: Linux高性能服务器编程 读书笔记(3)
date: 2025-2-13 20:31:00
tags: [Linux高性能服务器编程]
---

> **第七章 Linux服务器程序规范**

## 日志

### rsyslog

一个非常强大的日志管理工具，它是现代 Linux 和 Unix 系统中默认的日志守护进程之一.

它负责收集、存储和转发来自操作系统和应用程序的日志消息.

### syslog

一个用于向rsyslog系统发送日志进行存储的函数.

```cpp
#include＜syslog.h＞
void syslog(int priority, const char*message,...);
```

- priority用来描述这个日志消息的类别级别等信息.

  ```cpp
  // 消息类别
  LOG_USER（值 1）: 用户应用程序消息
  LOG_DAEMON（值 3）: 守护进程消息
  LOG_SYSLOG（值 4）: 系统日志相关消息
  LOG_LOCAL0 到 LOG_LOCAL7（值 16 到 23）: 用户定义的本地类别
  // 消息级别
  LOG_EMERG（0）：紧急情况，系统无法使用
  LOG_ALERT（1）：需要立即采取行动
  LOG_CRIT（2）：临界情况
  LOG_ERR（3）：错误
  LOG_WARNING（4）：警告
  LOG_NOTICE（5）：普通但需要注意的消息
  LOG_INFO（6）：一般信息
  LOG_DEBUG（7）：调试信息
  ```

  这些信息用"|"运算符连接.

  类别可以不填, 默认为LOG_USER, 也可以在openlog中设置.

- 后面用来填写要保存的日志信息, 是一个模板和可变参数, 可以这样使用 : 

  ```cpp
  syslog(LOG_INFO, "This is a simple log message.");
  const char *username = "Alice";
  syslog(LOG_INFO, "User %s has logged in.", username);
  ```

### openlog / closelog

其实就是使用syslog要用到的构造和析构函数. 

openlog不写使用syslog会隐式调用该函数, closelog必须显式调用.

```cpp
#include＜syslog.h＞
void openlog(const char*ident,int logopt,int facility);
void closelog();
```

ident参数指定的字符串将被添加到日志消息的日期和时间之后，它通常被设置为程序的名字。logopt参数对后续syslog调用的行为进行配置，它可取下列值的按位或：

```cpp
#define LOG_PID 0x01/*在日志消息中包含程序PID*/
#define LOG_CONS 0x02/*如果消息不能记录到日志文件，则打印至终端*/
#define LOG_ODELAY 0x04/*延迟打开日志功能直到第一次调用syslog*/
#define LOG_NDELAY 0x08/*不延迟打开日志功能*/
```

facility参数可用来修改syslog函数中的默认设施值, 可以提前设置日志类别 : 

```cpp
openlog("MyApp", LOG_PID | LOG_CONS, LOG_USER);
syslog(LOG_INFO, "This is an info message.");
closelog();
```

---

## 用户信息

### uid / euid 

- **`uid`** 是进程的真实用户 ID，标识启动进程的用户。

- **`euid`** 是进程的有效用户 ID，决定进程的权限级别。

  euid存在的目的是方便资源访问：它使得运行程序的用户拥有该程序的有效用户的权限。

- **`getuid`** 和 **`geteuid`** 用于获取 `uid` 和 `euid`，常用于权限检查、权限切换和调试。

```cpp
#include＜unistd.h＞
#include＜stdio.h＞
int main()
{
	uid_t uid=getuid();
	uid_t euid=geteuid();
	printf("userid is%d,effective userid is:%d\n",uid,euid);
	return 0;
}
```

作用 : 根据当前用户的权限执行不同的操作 / 用于调试和日志记录.

### 切换用户

将以root身份启动的进程切换为以一个普通用户身份运行:

```cpp
static bool switch_to_user(uid_t user_id,gid_t gp_id)
{
	/*先确保目标用户不是root*/
	if((user_id==0)＆＆(gp_id==0)) return false;
    
	/*确保当前用户是合法用户：root或者目标用户*/
	gid_t gid=getgid();
	uid_t uid=getuid();
	if(((gid!=0)||(uid!=0))＆＆((gid!=gp_id)||(uid!=user_id))) return false;
    
	/*如果不是root，则已经是目标用户*/
	if(uid!=0) return true;
    
	/*切换到目标用户*/
	if((setgid(gp_id)＜0)||(setuid(user_id)＜0)) return false;
    
	return true;
}
```

---

## 进程间关系

### 进程组

每个进程都有自己的pid, 也会有自己的pgid, pgid是自己所在的进程组id.

每个进程组都有一个首领进程, 首领进程的pid将会被用作进程组的id, 作用仅限于此.

一个进程组中的进程有共同作用, 如果一个接收了SIGINT信号, 其他几个也会一并退出.

父子进程就默认属于同一个进程组, 但也可以通过setsid来改变.

### 会话

一些有关联的进程组将形成一个会话（session）.

通过会话，操作系统可以更高效地管理进程组和终端交互，并为用户提供强大的作业控制功能。

#### **会话的作用**

（1）**终端管理**

- 会话与终端关联，决定了哪些进程组可以访问终端。
- 每个会话有一个前台进程组（Foreground Process Group），只有前台进程组中的进程可以从终端读取输入、向终端输出，并接收终端的控制信号（如 `Ctrl+C` 发送的 `SIGINT`）。

（2）**作业控制**

- 会话支持作业控制（Job Control），允许用户在前台和后台之间切换任务。
- 例如，Shell 可以将一个作业（如管道命令）放到前台或后台运行。

（3）**信号管理**

- 会话可以统一管理信号。
- 例如，当终端断开连接时，会话首进程会收到 `SIGHUP` 信号，通常会导致会话中的所有进程终止。

（4）**资源管理**

- 会话可以统一管理资源。
- 例如，当会话首进程终止时，操作系统会向会话中的所有进程发送 `SIGHUP` 信号，终止整个会话。

### 改变工作目录和根目录

```cpp
#include＜unistd.h＞
char*getcwd(char*buf,size_t size);  // 获取当前的工作目录
int chdir(const char*path);			// 改变当前工作目录
int chroot(const char*path);		// 改变根目录
```

### 服务器程序后台化(守护进程)

```cpp
bool daemonize()
{
    /*创建子进程，关闭父进程，这样可以使程序在后台运行*/
    pid_t pid = fork();
    if (pid＜0)
    {
        return false;
    }
    else if (pid＞0)
    {
        exit(0);
    }
    /*设置文件权限掩码。当进程创建新文件（使用open(const char*pathname,int flags,mode_t mode)系统调用）时，文件的权限将是mode＆0777*/
    umask(0);
    /*创建新的会话，设置本进程为进程组的首领*/
    pid_t sid = setsid();
    if (sid＜0) return false;

    /*切换工作目录*/
    if ((chdir("/"))＜0)
    {
        return false;
    }

    /*关闭标准输入设备、标准输出设备和标准错误输出设备*/
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    /*关闭其他已经打开的文件描述符，代码省略*/
    
    /*将标准输入、标准输出和标准错误输出都定向到/dev/null文件*/
    open("/dev/null", O_RDONLY);
    open("/dev/null", O_RDWR);
    open("/dev/null", O_RDWR);
    return true;
}
```

也可以使用daemon函数, 将该函数所在的进程变为守护进程 : 

```cpp
#include＜unistd.h＞
int daemon(int nochdir,int noclose);
```

- nochdir用于指定是否改变当前目录, 0则设置"/"为根目录.
- noclose设置为0时, 三个标准都会被默认重定向到/dev/null文件.

