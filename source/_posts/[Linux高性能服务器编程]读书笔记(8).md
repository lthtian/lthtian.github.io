---
title: Linux高性能服务器编程 读书笔记(8)
date: 2025-2-23 15:07:00
tags: [Linux高性能服务器编程, 多线程]
---

> 第14章 多线程编程

## 线程与进程

线程是轻量级的进程, 想要理解线程的关键, 首先要理解线程和进程之间的区别.

一个进程在创建之初其实就可以看作是一个主线程, 其创建出的线程其实和其本质无很大差别, 其实就多了一个线程共享资源罢了, 我们要明晰的是一个进程创建的不同线程之间, 什么是共享的, 什么是独立的.

线程间共享的 : 

- 进程地址空间中的代码段, 数据段, 堆
- 文件描述符
- 信号处理
- 环境变量
- 进程id

线程间独立的 : 

- 线程id
- 进程地址空间中的栈
- 寄存器状态
- 信号掩码(会继承但独立)
- 线程局部存储(TLS)
- errno

只有理解了这些, 我们才可以分析出线程相比于进程, 我们还需要关心什么, 例如 : 

- 数据段 + 文件描述符共享 -> 需要锁来限制共享内存的访问
- 信号处理共享 + 信号掩码独立 -> 可以创建一个线程单独管理信号.

---

## 线程创建及使用

```cpp
#include＜pthread.h＞
typedef unsigned long int pthread_t;
int pthread_create(pthread_t*thread,const pthread_attr_t*attr,void*(*start_routine)(void*),void*arg);
void pthread_exit(void*retval);
int pthread_join(pthread_t thread,void**retval);
```

----

## 线程同步(线程间通信)

和线程同步相关的要点也有三种 : 

### POSIX信号量

进程间通信中已经将了System V信号量l, POSIX信号量的理念和使用方法也相似, 还是可以理解为一种可计数的高级互斥锁.

POSIX信号量的使用会更加方便一些 : 

```cpp
#include＜semaphore.h＞
int sem_init(sem_t*sem,int pshared,unsigned int value);
int sem_destroy(sem_t*sem);
int sem_wait(sem_t*sem);
int sem_trywait(sem_t*sem);
int sem_post(sem_t*sem);
```

- sem : 就是标定唯一的信号量的一个标准, 直接创建即可`sem_t sem;`;
- pshared : 用于指定信号量类型, 如果为0代表是进程局部的信号量, 不为0可以实现进程间共享, 不过这个信号量一般用于线程间通信, 所以用0即可.
- value : 设置信号量的值, 和System V中semctl的作用一致. 

### 互斥锁

这个就是常用的普通锁, 只能被一个线程持有.

```cpp
#include＜pthread.h＞
int pthread_mutex_init(pthread_mutex_t*mutex,const pthread_mutexattr_t*mutexattr);
int pthread_mutex_destroy(pthread_mutex_t*mutex);
int pthread_mutex_lock(pthread_mutex_t*mutex);
int pthread_mutex_trylock(pthread_mutex_t*mutex);
int pthread_mutex_unlock(pthread_mutex_t*mutex);
```

可以用宏的方式替代init : 

```cpp
pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER; 
```

init的第二个参数用于设置互斥锁属性, 一般是NULL.

### 条件变量

```cpp
#include＜pthread.h＞
int pthread_cond_init(pthread_cond_t*cond,const pthread_condattr_t*cond_attr);
int pthread_cond_destroy(pthread_cond_t*cond);
int pthread_cond_broadcast(pthread_cond_t*cond);    
int pthread_cond_signal(pthread_cond_t*cond);
int pthread_cond_wait(pthread_cond_t*cond,pthread_mutex_t*mutex);
```

这个名称起的比较晦涩, 但是确实是和"条件"有关, 这个东西是和互斥锁绑定使用的, 你可以理解为互斥锁只负责确保当前只有一个线程可以持有锁, 也就是只用一个线程可以访问共享资源. 而条件变量是在**确保这个共享资源属于可用状态**, **可用状态的判断是靠条件实现的**, 更具体的说就是通过if判断是否触发`pthread_cond_wait`函数.

以生产者消费者模型为例, 生产者将产物存入共享内存中, 消费者从共享内存中取出产物, 那么互斥锁可以保证同时只能由一个生产者或消费者访问共享内存, 

- 但是如果共享内存满了, 生产者再去生产就是浪费, 
- 如果内存为空, 消费者去取也是徒劳. 

这时条件变量就可以发挥作用 : 

- 当共享内存满了, 可以将生产者挂起, 直到共享内存有产物被取走为止,
- 当共享内存为空, 可以将消费者挂起, 直到共享内存不为空为止.

#### 函数使用

函数使用和互斥锁相似, init的第二个参数还是设置为NULL就行, 并且也可以用下面的代码替代 : 

```cpp
pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
```

- 我们通过条件判断触发pthread_cond_wait, 这个函数会将线程挂起, 并且释放当前持有的锁.
- 在我们认为可以满足条件的地方触发pthread_cond_signal, 这个函数会选择一个挂起的线程并唤醒他, 被唤醒的线程会重新持有互斥锁并且继续执行pthread_cond_wait后面的代码.

#### CS模型代码案例

```cpp
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t cond_var = PTHREAD_COND_INITIALIZER;
int shared_data = 0;

// 生产者线程函数
void* producer(void* arg) {
    pthread_mutex_lock(&mutex);  // 获取互斥锁
    while (shared_data != 0) {   // 条件判断
        pthread_cond_wait(&cond_var, &mutex);  // 等待条件变量
    }
    
    shared_data = 1;  // 生产数据
    printf("生产者生产数据: %d\n", shared_data);
    
    pthread_cond_signal(&cond_var);  // 唤醒消费者, 这时条件一定满足
    pthread_mutex_unlock(&mutex);  // 释放互斥锁
    return NULL;
}

// 消费者线程函数
void* consumer(void* arg) {
    pthread_mutex_lock(&mutex);  // 获取互斥锁
    while (shared_data == 0) {
        pthread_cond_wait(&cond_var, &mutex);  // 等待条件变量
    }
    
    shared_data = 0;  // 消费数据
    printf("消费者消费数据: %d\n", shared_data);
    
    pthread_cond_signal(&cond_var);  // 唤醒生产者, 这时条件一定满足
    pthread_mutex_unlock(&mutex);  // 释放互斥锁
    return NULL;
}

int main() {
    pthread_t producer_thread, consumer_thread;

    pthread_create(&producer_thread, NULL, producer, NULL);
    pthread_create(&consumer_thread, NULL, consumer, NULL);

    pthread_join(producer_thread, NULL);
    pthread_join(consumer_thread, NULL);

    pthread_mutex_destroy(&mutex);
    pthread_cond_destroy(&cond_var);
    return 0;
}
```

### 线程同步机制包装类

```cpp
#ifndef LOCKER_H
#define LOCKER_H
#include＜exception＞
#include＜pthread.h＞
#include＜semaphore.h＞

/*封装信号量的类*/
class sem
{
public:
    /*创建并初始化信号量*/
    sem()
    {
        if(sem_init(＆m_sem,0,0)!=0)
        {
            /*构造函数没有返回值，可以通过抛出异常来报告错误*/
            throw std::exception();
        }
    }

    /*销毁信号量*/
    ～sem()
    {
        sem_destroy(＆m_sem);
    }

    /*等待信号量*/
    bool wait()
    {
        return sem_wait(＆m_sem)==0;
    }

    /*增加信号量*/
    bool post()
    {
        return sem_post(＆m_sem)==0;
    }

private:
    sem_t m_sem;
};

/*封装互斥锁的类*/
class locker
{
public:
    /*创建并初始化互斥锁*/
    locker()
    {
        if(pthread_mutex_init(＆m_mutex,NULL)!=0)
        {
            throw std::exception();
        }
    }

    /*销毁互斥锁*/
    ～locker()
    {
        pthread_mutex_destroy(＆m_mutex);
    }

    /*获取互斥锁*/
    bool lock()
    {
        return pthread_mutex_lock(＆m_mutex)==0;
    }

    /*释放互斥锁*/
    bool unlock()
    {
        return pthread_mutex_unlock(＆m_mutex)==0;
    }

private:
    pthread_mutex_t m_mutex;
};

/*封装条件变量的类*/
class cond
{
public:
    /*创建并初始化条件变量*/
    cond()
    {
        if(pthread_mutex_init(＆m_mutex,NULL)!=0)
        {
            throw std::exception();
        }
        if(pthread_cond_init(＆m_cond,NULL)!=0)
        {
            /*构造函数中一旦出现问题，就应该立即释放已经成功分配了的资源*/
            pthread_mutex_destroy(＆m_mutex);
            throw std::exception();
        }
    }

    /*销毁条件变量*/
    ～cond()
    {
        pthread_mutex_destroy(＆m_mutex);
        pthread_cond_destroy(＆m_cond);
    }

    /*等待条件变量*/
    bool wait()
    {
        int ret=0;
        pthread_mutex_lock(＆m_mutex);
        ret=pthread_cond_wait(＆m_cond,＆m_mutex);
        pthread_mutex_unlock(＆m_mutex);
        return ret==0;
    }

    /*唤醒等待条件变量的线程*/
    bool signal()
    {
        return pthread_cond_signal(＆m_cond)==0;
    }

private:
    pthread_mutex_t m_mutex;
    pthread_cond_t m_cond;
};

#endif
```

## 不可重入函数

不可重入函数不能在多线程环境下使用, 因为其一般会使用到静态变量, 比如inet_ntoa等.

## 线程和信号

我们在上文已经知道线程之间信号处理共享并且信号掩码会继承但独立, 那么我们就可以设置一个单独的信号处理线程.

相关函数如下 : 

```cpp
#include＜pthread.h＞
#include＜signal.h＞
int pthread_sigmask(int how,const sigset_t*newmask,sigset_t*oldmask);
int sigwait(const sigset_t*set,int*sig);
```

构建流程如下 : 

- 在主线程构建出其他子线程之前就调用pthread_sigmask来设置好信号掩码，所有新创建的子线程都将自动继承这个信号掩码.
- 在信号处理线程中调用sigwait来等待信号并处理之.

```cpp
#include＜pthread.h＞
#include＜stdio.h＞
#include＜stdlib.h＞
#include＜unistd.h＞
#include＜signal.h＞
#include＜errno.h＞

#define handle_error_en(en,msg) do{errno=en;perror(msg);exit(EXIT_FAILURE);}while(0)

static void* sig_thread(void* arg)
{
    sigset_t* set = (sigset_t*)arg;
    int s, sig;
    for(;;)
    {
        /*第二个步骤，调用sigwait等待信号*/
        s = sigwait(set, &sig);
        if(s != 0)
            handle_error_en(s, "sigwait");
        printf("Signal handling thread got signal%d\n", sig);
    }
}

int main(int argc, char* argv[])
{
    pthread_t thread;
    sigset_t set;
    int s;
    /*第一个步骤，在主线程中设置信号掩码*/
    sigemptyset(&set);
    sigaddset(&set, SIGQUIT);
    sigaddset(&set, SIGUSR1);
    s = pthread_sigmask(SIG_BLOCK, &set, NULL);
    if(s != 0)
        handle_error_en(s, "pthread_sigmask");
    s = pthread_create(&thread, NULL, &sig_thread, (void*)&set);
    if(s != 0)
        handle_error_en(s, "pthread_create");
    pause();
}
```

## 线程局部存储(TLS)

线程局部存储（TLS）是一种允许线程拥有独立数据的技术。这意味着每个线程都可以访问同名变量的不同实例，而这些变量在不同线程中不会互相干扰。TLS 在多线程环境中提供了一种为每个线程分配私有存储空间的机制。

简单来说可以理解为 : 

- **TLS中的数据像线程的私有全局变量, 避免在各种函数间频繁传入常用的数据降低效率**.

在 POSIX 系统中，如果你使用 `pthread_key_create()` 来创建线程局部存储（TLS）键并且关联某些数据，那么你还需要提供一个销毁函数，这个销毁函数会在线程退出时自动调用，用来释放线程局部存储的数据。

销毁过程：

- 在 `pthread_key_create()` 时，你可以指定一个销毁函数（destructor），这个函数会在线程退出时被调用。
- `pthread_key_delete()` 用于显式地删除一个 TLS 键，销毁相关的资源。

```cpp
#include <pthread.h>
pthread_key_t t_key;  // 定义 TLS 键
// 初始化（通常在程序启动时调用）
void init_tls() {
    pthread_key_create(&t_key, [](void* ptr) {
        free(ptr);  // 线程退出时自动释放资源
    });
}
// 设置线程局部值
void set_tls_value(int value) {
    int* ptr = (int*)malloc(sizeof(int));
    *ptr = value;
    pthread_setspecific(t_key, ptr);
}
// 获取线程局部值
int get_tls_value() {
    int* ptr = (int*)pthread_getspecific(t_key);
    return ptr ? *ptr : 0;
}
```

当然以上是操作系统提供的TLS使用, 在实际使用中, GCC和C++11都有提供对应的TLS使用方式

- GCC : **``__thread``** 将该关键字置于变量前方, 就可以将该变量作为线程局部资源使用.
- C++11 : **`thread_local`** 将该关键字置于变量前方, 也可以实现相同的效果.

需要注意的一点是``__thread``只作用于POD类型变量, 而``thread_local``都可以, 因此更推荐使用``thread_local``.

在性能方面 : ``__thread`` > ``thread_local`` > ``pthread_key_t``.

---

## 浅谈线程设计的初衷

线程设计的初衷就是在于和多核CPU搭配实现同时并行处理多个任务, 我们可以简单理解线程的合理数量应当和CUP核数相当, 数量太少显示不出线程的优势, 数量太多其额外开销其实会非常多并且还吃力不讨好.



























