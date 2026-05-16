---
title: FFmpeg音视频学习(2) QtAPI
date: 2025-6-28 19::00:00
tags: [ffmpeg]
---

> 本章介绍部分Qt中用于音视频解码的api

本章我们将会在qtcreator中写一段代码实现对一个mp4文件的解码, 所谓解码就是把其中存储的每个视频帧和音频帧取出, 本章先不做展示界面, 只是先读取这些帧的数据.

### 环境准备

- qtcreator
- 安装ffmpeg

在.pro文件中加入相关依赖 : 

```cpp
INCLUDEPATH += /usr/include
LIBS += -lavformat -lavcodec -lavutil -lswresample -lswscale
```

接下来添加相应头文件就可以进行ffmpeg的使用了.

### 基础API学习

先放出整段代码, 我们一句一句分析 : 

```cpp
// main.cpp
#include "mainwindow.h"
#include <iostream>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
#include <libavutil/avutil.h>
}

int main() {
    const char* filename = "/home/lth/learn/ffmpegLearning/fflearn/9.mp4"; // 替换为你的视频路径
    AVFormatContext* fmt_ctx = nullptr;

    // 打开文件
    if (avformat_open_input(&fmt_ctx, filename, nullptr, nullptr) < 0) {
        std::cerr << "无法打开文件" << std::endl;
        return -1;
    }

    // 读取流信息
    if (avformat_find_stream_info(fmt_ctx, nullptr) < 0) {
        std::cerr << "无法找到流信息" << std::endl;
        return -1;
    }

    // 查找视频流和音频流
    int video_stream_index = av_find_best_stream(fmt_ctx, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    int audio_stream_index = av_find_best_stream(fmt_ctx, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);

    AVCodecParameters* video_codecpar = fmt_ctx->streams[video_stream_index]->codecpar;
    const AVCodec* video_codec = avcodec_find_decoder(video_codecpar->codec_id);
    AVCodecContext* video_ctx = avcodec_alloc_context3(video_codec);
    avcodec_parameters_to_context(video_ctx, video_codecpar);
    avcodec_open2(video_ctx, video_codec, nullptr);

    AVCodecParameters* audio_codecpar = fmt_ctx->streams[audio_stream_index]->codecpar;
    const AVCodec* audio_codec = avcodec_find_decoder(audio_codecpar->codec_id);
    AVCodecContext* audio_ctx = avcodec_alloc_context3(audio_codec);
    avcodec_parameters_to_context(audio_ctx, audio_codecpar);
    avcodec_open2(audio_ctx, audio_codec, nullptr);

    AVPacket* pkt = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();

    while (av_read_frame(fmt_ctx, pkt) >= 0) {
        AVCodecContext* ctx = nullptr;
        if (pkt->stream_index == video_stream_index) {
            ctx = video_ctx;
        } else if (pkt->stream_index == audio_stream_index) {
            ctx = audio_ctx;
        } else {
            av_packet_unref(pkt);
            continue;
        }

        avcodec_send_packet(ctx, pkt);
        while (avcodec_receive_frame(ctx, frame) == 0) {
            if (ctx == video_ctx) {
                std::cout << "[Video] PTS=" << frame->pts
                          << " size=" << frame->width << "x" << frame->height << std::endl;
            } else {
                std::cout << "[Audio] PTS=" << frame->pts
                          << " nb_samples=" << frame->nb_samples
                          << " channels=" << frame->channels << std::endl;
            }
            av_frame_unref(frame);
        }

        av_packet_unref(pkt);
    }

    av_frame_free(&frame);
    av_packet_free(&pkt);
    avcodec_free_context(&video_ctx);
    avcodec_free_context(&audio_ctx);
    avformat_close_input(&fmt_ctx);

    return 0;
}
```

**[打开文件和流查找]**

- 首先明确你要解码的文件路径, 我这里直接用的绝对路径, 用相对路径需要看一下起始路径怎么设置.

- `AVFormatContext* fmt_ctx = nullptr;`

  这个是我们进行音视频处理的核心句柄, 其会链接本次解码相关的所有资源, 我们接下来就会用其打开我们要解码的文件.

- ```cpp
  avformat_open_input(&fmt_ctx, filename, nullptr, nullptr)
  ```

  第一个核心函数, 传入句柄与路径, 就可以打开对应文件. 打开失败会返回<0.

- ```cpp
  avformat_find_stream_info(fmt_ctx, nullptr)
  ```

  第二个核心函数, 从文件中找到各种流, 并把所有流信息存入核心句柄, 也是失败返回<0;

- ```c++
  int video_stream_index = av_find_best_stream(fmt_ctx, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
  int audio_stream_index = av_find_best_stream(fmt_ctx, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
  ```

  一个文件中可以有很多流, 这里的函数就是帮我们找到最合适的视频流和音频流, 并给出对应流的下标.

  - 在fmt_ctx中会有一个数组指针数组streams, 每个元素都会指向一个流, 这里的下标就是数组指针的下标.

**[解码前准备]**

- ```cpp
  AVCodecParameters* video_codecpar = fmt_ctx->streams[video_stream_index]->codecpar;
  ```

  根据上文我们可以知道`fmt_ctx->streams[video_stream_index]`就是最佳视频流, 这个一步就是从这个最佳视频流中取出其**编码器参数**, 并存入video_codecpar对象中.

- ```cpp
  const AVCodec* video_codec = avcodec_find_decoder(video_codecpar->codec_id);
  ```

  有了编码器参数, 我们就可以**从库中找到对应的解码器**了.

- ```cpp
  AVCodecContext* video_ctx = avcodec_alloc_context3(video_codec);
  ```

  这里`video_ctx`官方叫做解码器上下文, 说人话就是一个对应我们目标解码器的句柄, 其代表了最佳视频流的解码器.

- ```cpp
  avcodec_parameters_to_context(video_ctx, video_codecpar);
  ```

  把我们先前的编码器参数存入video_ctx中, 便于之后开启正式的解码.

- `avcodec_open2(audio_ctx, audio_codec, nullptr);`

​	传入我们的解码器句柄和解码器, 这个函数会开始准备对于对应包的解码, 如果有多线程就会开辟线程池准备多线程解码.

**[解码过程]**

- 在解释下面的过程前, 我们要先认识些概念 : 
  - 包 : 是从流中压缩出来的数据块, 可以从其中解码出帧. 也就是`流 -> 包 -> 帧`.
  - 存在**一包多帧**(比如音频帧), 也存在**一帧多包**(比如高质量视频帧). 

- ```cpp
  AVPacket* pkt = av_packet_alloc();
  AVFrame* frame = av_frame_alloc();
  ```

  提前准备出包对象和帧对象.

- ```cpp
  while (av_read_frame(fmt_ctx, pkt) >= 0)
  ```

  这里会循环向pkt中存入按顺序读出的包, 这些包可以属于不同流, 并且相邻包的时间相近.

- ```cpp
  AVCodecContext* ctx = nullptr;
  if (pkt->stream_index == video_stream_index) {
      ctx = video_ctx;
  } else if (pkt->stream_index == audio_stream_index) {
      ctx = audio_ctx;
  } else {
      av_packet_unref(pkt);
      continue;
  }
  ```

  这里是对包的筛选,  每个包都可以读出其归属的流, 如果属于我们需求的两条最佳流, 就分配其对应最佳流的解码器句柄, 如果不属于就弃掉继续读.

- ```cpp
  avcodec_send_packet(ctx, pkt);
  ```

  这个函数就是将包根据解码器句柄传入其对应的解码器中.

- ```cpp
  while (avcodec_receive_frame(ctx, frame) == 0)
  ```

  会在这里循环接收我们对于上一句传入包的结果, 也就是帧, 其会将解码出的内容填入我们传入的frame.

  需要注意的是, 只要这里是0, 就代表填充了一个完整帧, 可以对帧进行处理, 在一包多帧的情况下就可以循环到所有帧都处理完毕. 而在一帧多包的情况下, 不会返回0, 也就是说不会进行帧处理, 直到接收到的包可以合成一个完整帧.

- 关于帧frame, 我们只在这里打印其基础参数, 实际我们可以进行更深入的处理使其作为图像和音频表示出来, 这些之后再详解.

至此我们实现了用ffmpeg解码视频文件, 实现了"文件 -> 流 -> 包 -> 帧"的过程.



by 天目中云