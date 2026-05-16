---
title: libevent事件库
date: 2025-7-4 20:16:00
tags: [libevent]
---

### 使用

libevent的主要核心就是一套统一事件源的事件处理, 下面是一个echo服务器 : 

```cpp
#include <event2/event.h>
#include <event2/util.h>
#include <netinet/in.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>

#define PORT 8888

// 设置非阻塞
int setnonblock(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

// 客户端 socket 有数据可读时调用
void on_read(evutil_socket_t fd, short what, void *arg)
{
    char buf[1024] = {0};
    int n = read(fd, buf, sizeof(buf));
    if (n > 0)
    {
        write(fd, buf, n); // 回显数据
    }
    else if (n == 0)
    {
        printf("客户端关闭连接: fd = %d\n", fd);
        struct event *ev = (struct event *)arg;
        event_free(ev);
        close(fd);
    }
    else
    {
        perror("read error");
    }
}

// 有客户端连接时调用
void on_accept(evutil_socket_t listener, short event, void *arg)
{
    struct event_base *base = (struct event_base *)arg;
    struct sockaddr_in client;
    socklen_t len = sizeof(client);
    int client_fd = accept(listener, (struct sockaddr *)&client, &len);
    if (client_fd < 0)
    {
        perror("accept");
        return;
    }

    printf("新连接: fd = %d\n", client_fd);
    setnonblock(client_fd);

    // 为这个 client_fd 创建一个读事件
    struct event *read_event = event_new(base, client_fd, EV_READ | EV_PERSIST, on_read, NULL);
    event_add(read_event, NULL);
}

int main()
{
    // 创建监听 socket
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    evutil_make_socket_nonblocking(listener);

    int reuse = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in sin;
    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_ANY);
    sin.sin_port = htons(PORT);

    if (bind(listener, (struct sockaddr *)&sin, sizeof(sin)) < 0)
    {
        perror("bind");
        return 1;
    }

    if (listen(listener, 16) < 0)
    {
        perror("listen");
        return 1;
    }

    // 创建 base 和监听事件
    struct event_base *base = event_base_new();
    struct event *listen_event = event_new(base, listener, EV_READ | EV_PERSIST, on_accept, base);
    event_add(listen_event, NULL);

    printf("Echo服务器启动，监听端口 %d...\n", PORT);
    event_base_dispatch(base);

    // 清理资源
    event_free(listen_event);
    event_base_free(base);
    close(listener);
    return 0;
}
```

- event_base_new : 创建底层句柄, 调用epoll_create.
- event_new : 创建一个事件对象, 对于某些fd上的事件进行关心.
- event_add : 将事件对象加入epoll内核事件表, 调用epoll_ctl.
- event_base_dispatch : 调用epoll_wait进行事件监视.

这里echo服务器的整体思路就是把先监视listenfd上的连接请求, 传入连接回调, 在连接回调中用accept, 在监视读请求, 读回调中实现信息的回显.

### 部分源码剖析

- epoll_new : 

  ```cpp
  struct event *
  event_new(struct event_base *base, evutil_socket_t fd, short events, void (*cb)(evutil_socket_t, short, void *), void *arg)
  {
  	struct event *ev;
  	ev = mm_malloc(sizeof(struct event));
  	if (ev == NULL)
  		return (NULL);
  	if (event_assign(ev, base, fd, events, cb, arg) < 0) {
  		mm_free(ev);
  		return (NULL);
  	}
  
  	return (ev);
  }
  ```

  先构建出要返回的事件结构题, 然后放到event_assign中统一处理.

  ```cpp
  #if defined(__GNUC__) && (__GNUC__ == 11 || __GNUC__ == 12)
  __attribute__((noinline))
  #endif
  event_assign(struct event *ev, struct event_base *base, evutil_socket_t fd, short events, void (*callback)(evutil_socket_t, short, void *), void *arg)
  {
  	if (!base)
  		base = current_base;
  	if (arg == &event_self_cbarg_ptr_)
  		arg = ev;
  
  	if (!(events & EV_SIGNAL))
  		event_debug_assert_socket_nonblocking_(fd);
  	event_debug_assert_not_added_(ev);
  
  	ev->ev_base = base;
  
  	ev->ev_callback = callback;
  	ev->ev_arg = arg;
  	ev->ev_fd = fd;
  	ev->ev_events = events;
  	ev->ev_res = 0;
  	ev->ev_flags = EVLIST_INIT;
  	ev->ev_ncalls = 0;
  	ev->ev_pncalls = NULL;
  
  	if (events & EV_SIGNAL) {
  		if ((events & (EV_READ|EV_WRITE|EV_CLOSED)) != 0) {
  			event_warnx("%s: EV_SIGNAL is not compatible with "
  			    "EV_READ, EV_WRITE or EV_CLOSED", __func__);
  			return -1;
  		}
  		ev->ev_closure = EV_CLOSURE_EVENT_SIGNAL;
  	} else {
  		if (events & EV_PERSIST) {
  			evutil_timerclear(&ev->ev_io_timeout);
  			ev->ev_closure = EV_CLOSURE_EVENT_PERSIST;
  		} else {
  			ev->ev_closure = EV_CLOSURE_EVENT;
  		}
  	}
  
  	min_heap_elem_init_(ev);
  
  	if (base != NULL) {
  		/* by default, we put new events into the middle priority */
  		ev->ev_pri = base->nactivequeues / 2;
  	}
  
  	event_debug_note_setup_(ev);
  
  	return 0;
  }
  ```

  用传入的内容填入ev中.

- epoll_add

  ```cpp
  event_add(struct event *ev, const struct timeval *tv)
  {
  	int res;
  
  	if (EVUTIL_FAILURE_CHECK(!ev->ev_base)) {
  		event_warnx("%s: event has no event_base set.", __func__);
  		return -1;
  	}
  
  	EVBASE_ACQUIRE_LOCK(ev->ev_base, th_base_lock);
  
  	res = event_add_nolock_(ev, tv, 0);
  
  	EVBASE_RELEASE_LOCK(ev->ev_base, th_base_lock);
  
  	return (res);
  }
  
  int
  event_add_nolock_(struct event *ev, const struct timeval *tv,
      int tv_is_absolute)
  {
  	struct event_base *base = ev->ev_base;
  	int res = 0;
  	int notify = 0;
  
  	// .......
      
      // 核心主要是从此处将事件交付给专门处理IO/信号/定时器的专用函数
  	if ((ev->ev_events & (EV_READ|EV_WRITE|EV_CLOSED|EV_SIGNAL)) &&
  	    !(ev->ev_flags & (EVLIST_INSERTED|EVLIST_ACTIVE|EVLIST_ACTIVE_LATER))) {
  		if (ev->ev_events & (EV_READ|EV_WRITE|EV_CLOSED))
  			res = evmap_io_add_(base, ev->ev_fd, ev);
  		else if (ev->ev_events & EV_SIGNAL)
  			res = evmap_signal_add_(base, (int)ev->ev_fd, ev);
  		if (res != -1)
  			event_queue_insert_inserted(base, ev);
  		if (res == 1) {
  			/* evmap says we need to notify the main thread. */
  			notify = 1;
  			res = 0;
  		}
  	}
  
  	
      // ........
  }
  ```

  这里就是通过event_add通过函数层层调用, 针对不同的事件进行不同的处理, 最终调用到epoll_ctl.

  ```cpp
  // io事件调用线路如下 : 
  event_add_nolock_()
  └── evmap_io_add_()
      └── epoll_nochangelist_add()
          └── epoll_apply_one_change()
              └── epoll_ctl()  
  ```

- epoll_init

  ```cpp
  #include <sys/epoll.h>
  #include <stdlib.h>
  #include <string.h>
  #include <unistd.h>
  #include <stdio.h>
  
  #define INITIAL_NEVENT 64
  
  struct epollop {
      int epfd;                            // epoll 实例的文件描述符
      struct epoll_event *events;         // epoll_wait 用的事件数组
      int nevents;                        // 当前分配的事件个数
  };
  
  struct epollop *epoll_init(void) {
      int epfd;
      struct epollop *epollop;
  
      // 创建 epoll 实例，使用 epoll_create（内核 > 2.6.8 其参数已无意义）
      epfd = epoll_create(32000);
      if (epfd == -1) {
          perror("epoll_create failed");
          return NULL;
      }
  
      // 分配 epollop 结构体
      epollop = (struct epollop *)calloc(1, sizeof(struct epollop));
      if (!epollop) {
          close(epfd);
          return NULL;
      }
      epollop->epfd = epfd;
  
      // 分配事件数组，用于 epoll_wait 存放就绪事件
      epollop->events = (struct epoll_event *)calloc(INITIAL_NEVENT, sizeof(struct epoll_event));
      if (!epollop->events) {
          close(epfd);
          free(epollop);
          return NULL;
      }
      epollop->nevents = INITIAL_NEVENT;
  
      return epollop;
  }
  ```

- epoll_dispatch : 

  ```cpp
  int simple_epoll_dispatch(struct event_base *base, int timeout_ms)
  {
      struct epollop *epollop = base->evbase;
      struct epoll_event *events = epollop->events;
      int res;
  
      // ---- 调用 epoll_wait 等待事件就绪
      res = epoll_wait(epollop->epfd, events, epollop->nevents, timeout_ms);
      if (res < 0) {
          perror("epoll_wait failed");
          return -1;
      }
  
      // ---- 依次处理返回的所有事件
      for (int i = 0; i < res; ++i) {
          int what = events[i].events;
          short ev_flags = 0;
  
          // ---- 错误或者断开连接也作为读/写事件处理
          if (what & EPOLLERR || what & EPOLLHUP) {
              ev_flags = EV_READ | EV_WRITE;
          } else {
              if (what & EPOLLIN)  ev_flags |= EV_READ;
              if (what & EPOLLOUT) ev_flags |= EV_WRITE;
          }
  
          // ---- 将事件激活（调用回调或放入激活队列）
          int fd = events[i].data.fd;
          evmap_io_active_(base, fd, ev_flags);
      }
  
      // ---- 如果满了，扩大事件数组容量
      if (res == epollop->nevents && epollop->nevents < 4096) {
          int new_nevents = epollop->nevents * 2;
          struct epoll_event *new_events = realloc(epollop->events, new_nevents * sizeof(struct epoll_event));
          if (new_events) {
              epollop->events = new_events;
              epollop->nevents = new_nevents;
          }
      }
  
      return 0;
  }
  ```

- evmap_io_active_ : 

  ```cpp
  // 这个函数负责激活所有目标事件
  evmap_io_active_(struct event_base *base, evutil_socket_t fd, short events)
  {
  	struct event_io_map *io = &base->io;
  	struct evmap_io *ctx;
  	struct event *ev;
  
  #ifndef EVMAP_USE_HT
  	if (fd < 0 || fd >= io->nentries)
  		return;
  #endif
  	GET_IO_SLOT(ctx, io, fd, evmap_io);
  
  	if (NULL == ctx)
  		return;
  	LIST_FOREACH(ev, &ctx->events, ev_io_next) {
  		if (ev->ev_events & (events & ~EV_ET))
  			event_active_nolock_(ev, ev->ev_events & events, 1);
  	}
  }
  ```

### Buffer

libevent中有专门的buffer类帮助我们进行更简洁高效安全的读写 : 

```cpp
#include <event2/event.h>
#include <event2/bufferevent.h>
#include <event2/util.h>
#include <netinet/in.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>

#define PORT 8888

// 当有数据可读时触发
void on_read(struct bufferevent *bev, void *ctx)
{
    char buf[1024];
    int n = bufferevent_read(bev, buf, sizeof(buf));
    if (n > 0)
    {
        // 回显给客户端
        bufferevent_write(bev, buf, n);
    }
}

// 当连接断开或发生错误时触发
void on_event(struct bufferevent *bev, short events, void *ctx)
{
    if (events & BEV_EVENT_EOF)
    {
        printf("客户端关闭连接\n");
    }
    else if (events & BEV_EVENT_ERROR)
    {
        perror("发生错误");
    }
    // 释放 bufferevent（自动关闭 fd）
    bufferevent_free(bev);
}

// 当有新连接进入时触发
void on_accept(evutil_socket_t listener, short event, void *arg)
{
    struct event_base *base = (struct event_base *)arg;
    struct sockaddr_in client;
    socklen_t len = sizeof(client);

    int fd = accept(listener, (struct sockaddr *)&client, &len);
    if (fd < 0)
    {
        perror("accept");
        return;
    }

    printf("新连接: fd = %d\n", fd);
    evutil_make_socket_nonblocking(fd);

    // 创建 bufferevent，自动释放 fd
    struct bufferevent *bev = bufferevent_socket_new(base, fd, BEV_OPT_CLOSE_ON_FREE);
    // 设置回调函数：读、写（可选）、事件
    bufferevent_setcb(bev, on_read, NULL, on_event, NULL);
    // 启用读写事件
    bufferevent_enable(bev, EV_READ | EV_WRITE);
}

int main()
{
    // 创建 socket
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    evutil_make_socket_nonblocking(listener);

    int reuse = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in sin;
    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_ANY);
    sin.sin_port = htons(PORT);

    if (bind(listener, (struct sockaddr *)&sin, sizeof(sin)) < 0)
    {
        perror("bind");
        return 1;
    }

    if (listen(listener, 16) < 0)
    {
        perror("listen");
        return 1;
    }

    // 创建事件循环 base
    struct event_base *base = event_base_new();

    // 创建监听事件，监听 listener fd 的可读事件
    struct event *listen_event = event_new(base, listener, EV_READ | EV_PERSIST, on_accept, base);
    event_add(listen_event, NULL);

    printf("Echo服务器启动，监听端口 %d...\n", PORT);

    // 进入事件循环
    event_base_dispatch(base);

    // 清理资源
    event_free(listen_event);
    event_base_free(base);
    close(listener);

    return 0;
}
```

相比于上一个回显服务器, 这个版本的主要变动在于on_accept中从新建一个event变为了新建一个bufferevent, 然后在bufferevent中注册回调并开启监视. 读写操作都被改为bufferevent_read和bufferevent_write, 由系统内部处理数据的读入和写出, 处理粘包等问题, 并且必要的资源释放操作也在内部自动完成, 无需使用者关心.

### evdns --- 异步 DNS 解析模块

libevent提供原生异步域名解析服务 : 

```cpp
#include <event2/event.h>
#include <event2/dns.h>
#include <event2/util.h>
#include <stdio.h>
#include <cstring>

// 回调函数：解析成功或失败时被调用
void dns_callback(int errcode, struct evutil_addrinfo *res, void *ptr)
{
    if (errcode)
    {
        printf("DNS lookup failed: %s\n", gai_strerror(errcode));
    }
    else
    {
        char buf[128];
        evutil_inet_ntop(res->ai_family,
                         &((struct sockaddr_in *)res->ai_addr)->sin_addr,
                         buf, sizeof(buf));
        printf("Resolved IP: %s\n", buf);
        evutil_freeaddrinfo(res);
    }
}

int main()
{
    struct event_base *base = event_base_new();

    // 初始化 DNS 支持
    evdns_base *dns_base = evdns_base_new(base, 1); // 1 = 初始化默认 DNS 服务器

    // 启动 DNS 查询（类似 getaddrinfo，但是异步的）
    struct evutil_addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    evdns_getaddrinfo(dns_base, "www.baidu.com", NULL, &hints, dns_callback, NULL);

    event_base_dispatch(base);

    evdns_base_free(dns_base, 0);
    event_base_free(base);
    return 0;
}
```

可以直接在内部进行域名解析, 得到结果后通过传入的回调函数告知结果.

### evhttp --- 内置 HTTP Server / Client

libevent提供了内置的HTTP服务, 可以帮助我们快速解析请求与发送响应 : 

```cpp
#include <event2/event.h>
#include <event2/http.h>
#include <event2/buffer.h>
#include <stdio.h>

void hello_handler(struct evhttp_request *req, void *arg)
{
    struct evbuffer *buf = evbuffer_new();
    evbuffer_add_printf(buf, "Hello, evhttp!\n");
    evhttp_send_reply(req, 200, "OK", buf);
    evbuffer_free(buf);
}

int main()
{
    struct event_base *base = event_base_new();
    struct evhttp *http = evhttp_new(base);

    // 监听 0.0.0.0:8888
    evhttp_bind_socket(http, "0.0.0.0", 8888);

    // 设置 URI 回调
    evhttp_set_cb(http, "/hello", hello_handler, NULL);

    printf("HTTP Server running on http://localhost:8888/hello\n");

    event_base_dispatch(base);

    evhttp_free(http);
    event_base_free(base);
    return 0;
}
```

### 核心思路

- 事件回调模型 : 单线程 + 非阻塞epoll + 事件驱动回调.
- 采用统一事件源的核心思想, 可跨平台, 单线程一定线程安全.
- 劣势 : 以单线程为主, windows上只能用select不合适.
