---
title: libuv事件库
date: 2025-7-11 18:00:00
tags: [libuv]
---

### 回显服务器

先实现一个最简的Tcp回显服务器 : 

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#define PORT 7000
#define BUFFER_SIZE 1024

// 分配缓冲区
void alloc_buffer(uv_handle_t *handle, size_t suggested_size, uv_buf_t *buf)
{
    buf->base = (char *)malloc(suggested_size);
    buf->len = suggested_size;
}

// 关闭连接
void on_close(uv_handle_t *handle)
{
    free(handle);
}

// 写回数据后的回调
void echo_write(uv_write_t *req, int status)
{
    if (status < 0)
    {
        fprintf(stderr, "Write error %s\n", uv_strerror(status));
    }
    free(req->data);
    free(req);
}

// 读数据后的回调
void on_read(uv_stream_t *client, ssize_t nread, const uv_buf_t *buf)
{
    if (nread > 0)
    {
        uv_write_t *req = (uv_write_t *)malloc(sizeof(uv_write_t));
        uv_buf_t wrbuf = uv_buf_init(buf->base, nread);
        req->data = buf->base; // 保存写回用的数据

        uv_write(req, client, &wrbuf, 1, echo_write);
        return;
    }
    else if (nread < 0)
    {
        if (nread != UV_EOF)
            fprintf(stderr, "Read error %s\n", uv_err_name(nread));
        uv_close((uv_handle_t *)client, on_close);
    }

    free(buf->base);
}

// 有新连接时触发
void on_new_connection(uv_stream_t *server, int status)
{
    if (status < 0)
    {
        fprintf(stderr, "New connection error %s\n", uv_strerror(status));
        return;
    }

    uv_tcp_t *client = (uv_tcp_t *)malloc(sizeof(uv_tcp_t));
    uv_tcp_init(server->loop, client);

    if (uv_accept(server, (uv_stream_t *)client) == 0)
    {
        uv_read_start((uv_stream_t *)client, alloc_buffer, on_read);
    }
    else
    {
        uv_close((uv_handle_t *)client, on_close);
    }
}

int main()
{
    uv_loop_t *loop = uv_default_loop();

    uv_tcp_t server;
    uv_tcp_init(loop, &server);

    struct sockaddr_in addr;
    uv_ip4_addr("0.0.0.0", PORT, &addr);

    uv_tcp_bind(&server, (const struct sockaddr *)&addr, 0);
    int r = uv_listen((uv_stream_t *)&server, 128, on_new_connection);

    if (r)
    {
        fprintf(stderr, "Listen error %s\n", uv_strerror(r));
        return 1;
    }

    printf("Echo server listening on port %d...\n", PORT);
    return uv_run(loop, UV_RUN_DEFAULT);
}
```

可以看到都是和其他网络库非常相似的事件循环, 但也有非常强的异步风格, 处理事件都是需要传入相应回调的.

比较有意思的是`uv_read_start`的使用, 这个函数需要传入申请缓冲区的回调和读事件发生后的回调, 这里并不需要我们在外部提前申请缓冲区, 而是由库内部自己决定申请缓冲区的时机, 于是就可以在读事件发生时再及时申请内存然后读入, 非常好地利用了异步的特性, 避免了长期占有部分内存. 关于如何获取内部读到的数据, 读事件完毕后的回调中必须要有`uv_buf_t`这个类型, 我们可以从该类型参数中取出读到的内容.

### libuv特性及优势

- libuv是一般使用单线程模型, 支持线程池但很少使用. 本身还是Reactor模型, 通过事件循环多路复用分发事件.
- 非常标准的纯异步网络库, 都是通过回调进行处理.

- 专门匹配Node.js, 可以比较完美地匹配windows环境, 虽然本身跨平台, 但是相比于其他网络库在windows平台有天然优势, 可以实现很多windows下的异步操作.
- 原生支持异步文件 / DNS / 子进程.

### 异步文件操作

利用libuv实现异步文件读取.

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <uv.h>

uv_loop_t *loop;
uv_fs_t open_req, read_req, close_req;
uv_buf_t iov;
char buffer[1024];

void on_close(uv_fs_t* req) {
    uv_fs_req_cleanup(req);
}

void on_read(uv_fs_t* req) {
    if (req->result > 0) {
        printf("Read: %.*s\n", (int)req->result, buffer);
    }
    uv_fs_req_cleanup(req);
    uv_fs_close(loop, &close_req, open_req.result, on_close);
}

void on_open(uv_fs_t* req) {
    if (req->result >= 0) {
        iov = uv_buf_init(buffer, sizeof(buffer));
        uv_fs_read(loop, &read_req, req->result, &iov, 1, -1, on_read);
    } else {
        fprintf(stderr, "Error opening file: %s\n", uv_strerror((int)req->result));
    }
    uv_fs_req_cleanup(req);
}

int main() {
    loop = uv_default_loop();
    uv_fs_open(loop, &open_req, "test.txt", O_RDONLY, 0, on_open);
    uv_run(loop, UV_RUN_DEFAULT);
    return 0;
}
```

主要就是围绕`uv_fs_t`这个类实现异步文件读取, 读到内容都会先存在这个类中.

### 异步 DNS 解析

这个主要是为了配合Nodejs实现网页前端的异步域名解析 : 

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <uv.h>

void on_resolved(uv_getaddrinfo_t* req, int status, struct addrinfo* res) {
    if (status < 0) {
        fprintf(stderr, "getaddrinfo callback error %s\n", uv_strerror(status));
        return;
    }

    char addr[17] = {'\0'};
    uv_ip4_name((struct sockaddr_in*) res->ai_addr, addr, 16);
    printf("Resolved IP: %s\n", addr);

    uv_freeaddrinfo(res);
}

int main() {
    uv_loop_t* loop = uv_default_loop();
    uv_getaddrinfo_t resolver;

    struct addrinfo hints = {0};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    uv_getaddrinfo(loop, &resolver, on_resolved, "www.baidu.com", "80", &hints);
    uv_run(loop, UV_RUN_DEFAULT);
    return 0;
}
```



