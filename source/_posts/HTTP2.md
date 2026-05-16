---
title: HTTP/2
date: 2025-8-1 17:00:00
tags: [HTTP]
---

> 分为两部分 : 理论知识 和 nghttp2库使用

## 理论知识

可以理解为在HTTP/1.1上做了很多精简优化的工作, 解决了很多冗余的部分, 实现了精细地控制.

提升了加载速度, 减少了连接资源的浪费, 避免的频繁的队头阻塞.

### 整体理解

- 依旧使用TCP进行数据传递, 但是一组请求响应不再会长时间占用整个TCP连接, 并且不同的请求都将始终在一条TCP连接上实现.
- 流机制和帧机制实现了上述的效果.
- HPACK压缩机制实现了对多个相同报头的字段冗余问题.
- 提供优先级机制控制不同流直接的传输优先级.
- 提供流控机制防止单一流占用过多资源.

### 流机制 Stream

- **一个完整的请求响应的流程就是一个完整的流.**

- 所有流都在同一个TCP连接上.
- 每个流都可以被分为多个帧, 帧是最基本的数据单元, 最基础的类型包括HEADERS(报头), DATA(报文), 接收方可以根据帧的类型去对应处理相应的流.

- stream id : 
  - 每条流都会分配一个独立唯一的id,接收方可以根据id实现同一流资源的合并, 使得不同流可以交叉进行.
  - 一般来说正常认知都是客户端发起一个流, 因为都是客户想请求资源, 但是其实服务端也可以发起流, 这种情况被称为Server Push(服务器推送), 后面会解释. 因此协议规定**客户端发起的stream id为奇数, 服务端发起的stream id为偶数**, 这样可以天然避免id冲突.

### 帧机制 Frame

- 整个HTTP/2的最小数据单元.
- 每个帧有固定的 9 字节帧头和一个可变长度的帧体.
- 帧头包含 : 帧体长度, 帧类型, 标志位, stream id. 其中不同的帧类型传递不同类型的信息, 标志位可以根据不同的帧类型设置一些特殊的选项.

- 帧类型如下 : 

  | 帧类型                | 描述                                     | Stream ID 是否为 0 |
  | --------------------- | ---------------------------------------- | ------------------ |
  | `DATA` (0x0)          | 传输请求或响应体内容                     | 否                 |
  | `HEADERS` (0x1)       | 传输 HTTP 头部，标识一个请求或响应的开始 | 否                 |
  | `PRIORITY` (0x2)      | 声明流的优先级信息                       | 否                 |
  | `RST_STREAM` (0x3)    | 强制终止流                               | 否                 |
  | `SETTINGS` (0x4)      | 交换连接参数，初始化连接                 | ✅ 是               |
  | `PUSH_PROMISE` (0x5)  | 服务端推送资源预告                       | 否                 |
  | `PING` (0x6)          | 保活/RTT 检测（8字节数据）               | ✅ 是               |
  | `GOAWAY` (0x7)        | 关闭连接并告知最后处理的 stream          | ✅ 是               |
  | `WINDOW_UPDATE` (0x8) | 控制流量窗口大小                         | 否或是             |

- 最常用的标志位是`END_STREAM`, 该标志代表流结束, 可以在`HEADERS`和`DATA`帧中出现, 表示后续不会有新的帧传来, 流已经结束.

###  服务器推送 Server Push

> 注意该技术很大程度上已过时.

- 由服务器主动向客户端发起请求, 新建一个流进行数据传递.

- 类似场景如请求一个网站, 服务端会将需求的html页面作为响应发送给用户, 相应的服务端也会知道网页需要的css/js/图片等资源, 于是不用等客户端再次请求这些资源, 服务端就可以申请向客户端直接发送.

- `PUSH_PROMISE` : 

  这是一个特殊的帧类型, 用于向客户端预告自己将向其发送一些客户端可能需要的资源.

  其中帧体会包含两种字段 : `Promised Stream ID`(新建流的id) 和 `Header Block Fragment`(模拟的请求头).

  在发生类似上面的场景时, 服务端就会向客户端发送这样的一个承诺帧, 之后再开始传输`DATA`帧.

- 性能分析 : 

  其优化主要在减少了RTT(往返时间). 普通过程中客户端需要解析出需要的资源再向服务端请求, 需要RTT * 2, 但是Server Push只需要一个RTT就可以实现, 谷歌测试这种技术的提速大概在30%.

- 适用场景 : 

  其实就是公共网络下, 可以减缓RTT比较长情况下的延迟. 如果都在一个局域网中RTT非常小就完全没必要了.

### HPACK压缩机制

- 必要性 : 

  在一个TCP连接中, 发送的报头其实有很多都是重复的, 比如很多method都是GET, 很多scheme都是https, 但普通情况下我们还是需要传输一个很长的字段再解析出来, 这其实是相对低效的做法, 而这种报头压缩机制会将字段转化成简短的索引, 就可以有效解决这种问题.

- 方法简述 : 

  其实本质就是维护一些映射, 使得一些非常小的索引可以代指一些比较长的字段. 但是这种映射只有**在双方互通且完全一致**的情况下才有可行性, 而TCP可以帮助我们实现这种要求.

- 存储结构 : 

  - 存储机构包含两种 : 静态表 和 动态表, 前者固定不变, 后者同步更新.

  - 静态表 : 存储**固定的、所有连接共享的、永不变的**索引映射, 这是官方定好的, 具体如下 : 
  
    | Index | Name             | Value         |
    | ----- | ---------------- | ------------- |
    | 1     | `:authority`     | -             |
    | 2     | `:method`        | `GET`         |
    | 3     | `:method`        | `POST`        |
    | 4     | `:path`          | `/`           |
    | 5     | `:path`          | `/index.html` |
    | 6     | `:scheme`        | `http`        |
    | 7     | `:scheme`        | `https`       |
    | 8     | `:status`        | `200`         |
    | 13    | `content-length` | -             |
    | ...   | ...              | ...           |

    默认的静态表索引为**1 - 61**, 注意这静态表中有一部分是对完整[name value]的映射, 而一部分只是对name的映射.

  - 动态表 : **运行时可变的，用于存储最近使用过的 name/value 对**, 举例如下 : 
  
    | Index | Name    | Value         |
    | ----- | ------- | ------------- |
    | 62    | cookie  | `session=xyz` |
    | 63    | referer | `https://xxx` |
    | 64    | accept  | `text/html`   |

    动态表索引从**62**开始, 按序递增, 动态表中的映射一般都是对完整[name value]的映射.
  
    需要注意的是, 动态表的更新**必须同步**, 也就是说双方维护的动态表必须完全相同, 如果不同, 那么交流的正确性是绝对无法保证的, 而这一点可以用TCP的**有序**性质实现保证.
  
  注意上述的两个表, 在实现中大多用vector实现而非map, 因为我们的索引可以和数组下标对应, 用顺序表更为快捷便利.

>针对此压缩机制, 双方的编解码器可以维护这两个表, 从而用索引代指一些常用且冗长的字段. 但索引成立的前提是双方信息互通, 都知道索引代表了什么.
>
>静态表双方在一开始就可以持有, 但是动态表如何实现双方索引互通呢? 解决方法在报头格式中.

**压缩报头格式** :  多字段, 每段组成如下 : 

```cpp
[前导字节 name value]
```

- 前导字节 : 用于表示该段的类型, 是字段还是索引, 是否需要另外的操作, 共四种 : 

  | 编码类型                                          | 说明                                           | 典型前缀（高位）          |
  | ------------------------------------------------- | ---------------------------------------------- | ------------------------- |
  | 1. Indexed Header Field                           | 只发送索引，表示该字段完全命中静态/动态表      | `1xxxxxxx` （首位 1）     |
  | 2. Literal Header Field with Incremental Indexing | 新字段，插入动态表（就是 `0x40` 类型）         | `01xxxxxx` （前两位 01）  |
  | 3. Literal Header Field without Indexing          | 发送字段，但**不插入动态表**                   | `0000xxxx`（前四位 0000） |
  | 4. Literal Header Field Never Indexed             | 明确声明此字段不应被压缩器存储（例如敏感字段） | `0001xxxx`（前四位 0001） |

  - 当我们使用第一种编码类型, 代表我们在动态表或静态表中有对应的[name value]映射, 将使用索引替代, 此时**后面7位x对应值就代表双方约定的索引值**.

    例如我们想发送字段`:method: GET`, 由于在静态表中有其完整对, 我们可以直接发送`0x82(10000010)`这个字节代指该段.

  - 当我们使用第二种编码类型, 代表没有匹配或仅name匹配, 并且我们要让接收端将其插入动态表.

    无匹配插入 : `0x40(01000000) name value` 

    部分匹配插入 : `01xxxxxx value`, 这种情况存在主要因为静态表中会存一些仅匹配name的索引, 这种插入只是帮我们省略了一个name而已.

  - 这里我们可以发现HPACK压缩机制本身是由**发送方主导**的, 发送方可以决定接收方的行为, 因为本身表结构就需要双方一致, 如果接收方还可以拒绝接收方的行为的话, 为了两边一致就要做出很大的性能牺牲了.

- name / value : 

  当我们需要传这两个字段时, 可以直接明文传输, 也可以选择使用哈夫曼编码压缩.

至此, 加入我们想传入这样的报头 : 

```cpp
:method: GET
:path: /
:scheme: https
:authority: www.example.com
user-agent: curl/7.79.1
```

其就会被压缩成这样:

```cpp
82                          -> :method: GET
84                          -> :path: /
87                          -> :scheme: https
41 11 77 77 77 2e 65 78 61 6d 70 6c 65 2e 63 6f 6d  -> :authority: www.example.com
7A 0C 63 75 72 6C 2F 37 2E 37 39 2E 31              -> user-agent: curl/7.79.1
```

其中前三段在静态表中都有对应段, 直接索引替代. 第四,五段都采用了部分匹配插入, 41(01000001)因为`:authority`的索引是1, 7A(01011110)因为`user-agent`的索引是58, 后面的字段都是value明问转化成的哈夫曼编码.

### 优先级机制

优先级机制用来解决HTTP/2使用单一TCP连接带来的阻塞问题, 其通过给流设置优先级来实现高优先级的流资源(如html/css)可以高优先地发出, 避免被一些较大但次优先的资源(如图片)占用TCP连接资源.

HTTP/2设置了一个依赖树来实现优先级的设置, 子流的优先级始终低于父流, 父流可以更多地占用资源.

关键在于三种参数的设置 : 

| 字段              | 作用                     | 默认值 / 推荐用法                |
| ----------------- | ------------------------ | -------------------------------- |
| Exclusive         | 是否独占父流，重塑依赖树 | 默认 0，某些关键资源设为 1       |
| Stream Dependency | 依赖的父流 ID            | 默认 0，表示虚拟根节点           |
| Weight            | 调度比例                 | 默认 16，建议关键资源设置为 >100 |

我们可以在`HEADERS`帧和`PRIORITY`帧中设置这些参数, 具体设置方式不细究.

### 流控机制

- 必要性 :

  HTTP/1中都是每个请求响应都对应一条独立连接, 不同请求响应的流量不影响彼此, 并且TCP自己就有流量控制. 但是HTTP/2中每个请求响应共用一条连接, 一个流的数据传输如果过大且不加限制, 是绝对会拖慢其他流的传输的. 可以理解为TCP的流控是针对一条街道的, 而HTTP/2的流控是针对街道上的每条车道的.

- HTTP/2 流控是**接收方驱动的**. 流控通过接收方控制窗口大小实现, 和TCP的拥塞窗口机制类似.

- 接收方需要向发送方发送`WINDOW_UPDATE`帧告知发送方**还能发送多少**.

  - 0x08, 这是`WINDOW_UPDATE`帧的类型代码.
  - 在`WINDOW_UPDATE`帧的报体中会有`Window Size Increment`字段, 大小4字节, 可以用来设置窗口的大小. 

- 发送方每个时刻发送的数据总量(DATA 帧中的大小总和)**不能超过接收方通告的流控窗口大小**.

- HTTP/2有默认的窗口大小, **64KB**, 因此在发送方前期发送给接收方数据时是按照这默认大小来的.

- 如果接收方长时间不发送`WINDOW_UPDATE`帧给发送方, 发送方应当逐渐减小窗口至0, 直到接收到`WINDOW_UPDATE`帧, 也就是说如果想要发送方长时间持续发送内容, 就需要用户方持续发送`WINDOW_UPDATE`帧.

- 为什么必须要由接收方主导?

  因为发送方的能力一般是较高的, 但是接收方的机器水平参差不齐, 发送方并不能获取接收方的信息, 需要接收方按自己的接收能力控制窗口.

- 当然接收方也有可能把窗口设的很大恶意拖慢发送方服务, 这需要配合限流技术预防.

### SETTINGS帧

这是TCP连接建立后双方发的第一个帧, 用来交换初始参数.

- 建立连接后，客户端和服务端都必须各发送一帧 SETTINGS.
- 初始参数包括但不限于 : 
  - 初始流窗口大小（`SETTINGS_INITIAL_WINDOW_SIZE`）
  - 最大并发 stream 数量（`SETTINGS_MAX_CONCURRENT_STREAMS`）
  - 单帧最大大小（`SETTINGS_MAX_FRAME_SIZE`）
  - 是否启用服务器推送（`SETTINGS_ENABLE_PUSH`）
- 收到SETTINGS帧后, 每一端都需要发送 ACK 帧回应, 只有收到ACK帧, 设置才算是真正成立.

## nghttp2库

### 最基础的http2报文收发客户端

```cpp
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <nghttp2/nghttp2.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <netdb.h>
#include <arpa/inet.h>

#define HOST "nghttp2.org"
#define PORT "443"
#define MAKE_NV(NAME, VALUE)                                                 \
    {(uint8_t *)NAME, (uint8_t *)VALUE, sizeof(NAME) - 1, sizeof(VALUE) - 1, \
     NGHTTP2_NV_FLAG_NONE}

int stream_id = -1;

static ssize_t send_callback(nghttp2_session *session,
                             const uint8_t *data, size_t length,
                             int flags, void *user_data)
{
    SSL *ssl = (SSL *)user_data;
    return SSL_write(ssl, data, (int)length);
}

static ssize_t recv_callback(nghttp2_session *session,
                             uint8_t *buf, size_t length,
                             int flags, void *user_data)
{
    SSL *ssl = (SSL *)user_data;
    return SSL_read(ssl, buf, (int)length);
}

static int on_header_callback(nghttp2_session *session,
                              const nghttp2_frame *frame,
                              const uint8_t *name, size_t namelen,
                              const uint8_t *value, size_t valuelen,
                              uint8_t flags, void *user_data)
{
    printf("[HEADER] %.*s: %.*s\n", (int)namelen, name, (int)valuelen, value);
    return 0;
}

static int on_data_chunk_recv(nghttp2_session *session, uint8_t flags,
                              int32_t stream_id,
                              const uint8_t *data, size_t len,
                              void *user_data)
{
    printf("[DATA] %.*s\n", (int)len, data);
    return 0;
}

static int on_stream_close(nghttp2_session *session,
                           int32_t stream_id, uint32_t error_code,
                           void *user_data)
{
    printf("[INFO] Stream %d closed\n", stream_id);
    return 0;
}

// ALPN 回调
static int select_proto_cb(SSL *ssl, const unsigned char **out, unsigned char *outlen,
                           const unsigned char *in, unsigned int inlen, void *arg)
{
    static const unsigned char h2[] = {'h', '2'};
    *out = h2;
    *outlen = sizeof(h2);
    return SSL_TLSEXT_ERR_OK;
}

SSL *connect_tls(const char *host, const char *port, int *sockfd)
{
    struct addrinfo hints = {0}, *res;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    getaddrinfo(host, port, &hints, &res);
    *sockfd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    connect(*sockfd, res->ai_addr, res->ai_addrlen);

    SSL_library_init();
    SSL_load_error_strings();
    const SSL_METHOD *method = TLS_client_method();
    SSL_CTX *ctx = SSL_CTX_new(method);

    SSL_CTX_set_alpn_protos(ctx, (const unsigned char *)"\x2h2", 3);
    SSL_CTX_set_alpn_select_cb(ctx, select_proto_cb, NULL);

    SSL *ssl = SSL_new(ctx);
    SSL_set_fd(ssl, *sockfd);
    SSL_connect(ssl);
    return ssl;
}

int main()
{
    int sockfd;
    SSL *ssl = connect_tls(HOST, PORT, &sockfd);

    nghttp2_session_callbacks *callbacks;
    nghttp2_session_callbacks_new(&callbacks);
    nghttp2_session_callbacks_set_send_callback(callbacks, send_callback);
    nghttp2_session_callbacks_set_recv_callback(callbacks, recv_callback);
    nghttp2_session_callbacks_set_on_header_callback(callbacks, on_header_callback);
    nghttp2_session_callbacks_set_on_data_chunk_recv_callback(callbacks, on_data_chunk_recv);
    nghttp2_session_callbacks_set_on_stream_close_callback(callbacks, on_stream_close);

    nghttp2_session *session;
    nghttp2_session_client_new(&session, callbacks, ssl);

    // 初始化 SETTINGS 帧
    nghttp2_settings_entry iv = {NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, 100};
    nghttp2_submit_settings(session, NGHTTP2_FLAG_NONE, &iv, 1);

    // 准备请求头部
    const nghttp2_nv hdrs[] = {
        MAKE_NV(":method", "GET"),
        MAKE_NV(":path", "/httpbin/get"),
        MAKE_NV(":scheme", "https"),
        MAKE_NV(":authority", HOST),
        MAKE_NV("user-agent", "nghttp2-c-client")};

    stream_id = nghttp2_submit_request(session, NULL, hdrs, sizeof(hdrs) / sizeof(hdrs[0]), NULL, NULL);

    nghttp2_session_send(session);

    while (1)
    {
        int rv = nghttp2_session_recv(session);
        if (rv < 0)
            break;
        rv = nghttp2_session_send(session);
        if (rv < 0)
            break;
        if (nghttp2_session_want_read(session) == 0 &&
            nghttp2_session_want_write(session) == 0)
            break;
    }

    nghttp2_session_del(session);
    SSL_shutdown(ssl);
    close(sockfd);
    return 0;
}
```

初看确实比较麻烦, 实质上就是向`nghttp2.org`这个网站发送了一个请求, 然后通过设置各种事件的回调实现响应的接收, 回调包括读, 写,报头帧, 数据帧. 其实nghttp2有和boost::asio结合实现的简便版本, 不过目前没有普及, 这里还是拿最初始的版本进行学习.

### 服务器推送部分

在客户端, 首先应该在`SETTINGS`帧中就设置`SETTINGS_ENABLE_PUSH`, 告诉服务端你是否接受服务器推送.

如果接受, 需要设置针对`PUSH_PROMISE`帧的回调函数 : 

```cpp
static int on_begin_headers_callback(nghttp2_session *session,
                                     const nghttp2_frame *frame,
                                     void *user_data)
{
    if (frame->hd.type == NGHTTP2_PUSH_PROMISE)
    {
        printf("[INFO] PUSH_PROMISE for promised stream %d\n", frame->push_promise.promised_stream_id);
        stream_info[frame->push_promise.promised_stream_id] = "[Push Resource]";
    }
    return 0;
}
```

当然这里只是打印了一下帧信息, 实际我们可以采取系列行为, 比如停止后续对于该推送资源的请求, 就用服务器发过来的资源即可.

---

在服务端, 我们在检测到可以提前推送的资源后, 可以触发服务器推送机制, 发送`PUSH_PROMISE`帧 + 报头帧 + 数据帧 : 

```cpp
// ① 提交 PUSH_PROMISE 帧
nghttp2_nv push_hdrs[] = {
    MAKE_NV(":method", "GET"),
    MAKE_NV(":path", "/style.css"),
    MAKE_NV(":scheme", "https"),
    MAKE_NV(":authority", "example.com")
};

int32_t promised_stream_id = nghttp2_submit_push_promise(
    session,
    NGHTTP2_FLAG_NONE,
    parent_stream_id,   // 原请求 stream ID
    push_hdrs,
    sizeof(push_hdrs) / sizeof(push_hdrs[0]),
    NULL  // user_data 可选
);

// ② 为推送资源准备 HEADERS 和 DATA 响应
nghttp2_nv resp_hdrs[] = {
    MAKE_NV(":status", "200"),
    MAKE_NV("content-type", "text/css")
};

// 假设你将推送的内容保存在 memory_data 里
nghttp2_data_provider data_prd;
data_prd.source.ptr = memory_data;
data_prd.read_callback = your_data_read_callback; // 提供数据内容

nghttp2_submit_response(
    session,
    promised_stream_id,
    resp_hdrs,
    sizeof(resp_hdrs) / sizeof(resp_hdrs[0]),
    &data_prd
);
```

- 服务端如何知道要主动推送什么资源?

  最朴素的想法就是扫描请求的资源, 发现其依赖的资源, 就像在html文件中找css/js文件. 但基于效率可以针对文件生成其对应的依赖列表, 这样在客户端请求资源时即可立刻按照其依赖列表迅速进行推送申请了.

### HPACK压缩部分

报头压缩的部分nghttp2库中已经在内部全部实现, 无需外部的使用者关心.

### 优先级部分

nghttp2中有对优先级数值的封装 : 

```cpp
typedef struct {
  int32_t stream_id;    // 依赖的父 stream ID
  int32_t weight;       // 权重值（1~256）
  uint8_t exclusive;    // 是否独占依赖（0 或 1）
} nghttp2_priority_spec;
```

其可用于在`HEADERS`和`PRIORITYS`帧中传递优先级信息 : 

```cpp
nghttp2_priority_spec ps;
nghttp2_priority_spec_init(&ps, parent_id, weight, exclusive);

nghttp2_nv headers[] = {
    MAKE_NV(":method", "GET"),
    MAKE_NV(":path", "/img1.png"),
    ...
};

nghttp2_submit_headers(session, NGHTTP2_FLAG_END_STREAM, stream_id,
                       &ps, headers, header_count, NULL);

// ------------------------------------------------------------------ // 

nghttp2_priority_spec ps;
nghttp2_priority_spec_init(&ps, new_parent_id, new_weight, new_exclusive);

nghttp2_submit_priority(session, stream_id, &ps, NULL);
```

### 流控部分

主要通过以下几个部分实现 : 

- 设置初始窗口大小 : 

  ```cpp
  nghttp2_option_set_initial_window_size(option, 1024 * 1024);  // 1MB
  ```

  其会控制每个流初始的窗口大小.

- 接收方定时发送`WINDOW_UPDATE`帧恢复窗口.

  ```cpp
  nghttp2_submit_window_update(session, 0, 32768);        // 恢复连接窗口
  nghttp2_submit_window_update(session, stream_id, 32768); // 恢复该 stream 窗口
  ```

  - 关于调用时机, 一般是接收方接收完一段消息后就立刻恢复, 如果注重服务器效率, 且接收方流量小实时性要求不高, 也可以设置一些累计机制触发恢复, 可以减少`WINDOW_UPDATE`帧的发送频率.

- 发送方在想要发送内容时通过api获取窗口大小, 按此大小发送内容 : 

  ```cpp
  nghttp2_session_get_remote_window_size(session);						// 连接级窗口
  nghttp2_session_get_stream_remote_window_size(session, stream_id);		// 流级窗口
  ```

  - 确实有`WINDOW_UPDATE`帧的回调函数, 但是一般来说没有必要, 只需要发送时获取窗口大小即可.
  - nghttp2库内部会自动解析`WINDOW_UPDATE`帧并存储对应窗口大小.