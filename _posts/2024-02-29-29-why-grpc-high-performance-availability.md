---
title:     'gRPC 的高性能和高可用'
tags:      [Why, RPC, performance, availability]
---

RPC 是一种远程过程调用协议，目标是让远程服务调用更加简便、直观。RPC 在微服务架构中得到广泛应用，特别适用于内部服务之间的调用。gRPC 是 Google 在 2015 开源的 RPC 框架，因其高性能和高可用性而受到广泛欢迎，我们来具体看下它是如何做到高性能和高可用的。

## 高性能

### 基于 HTTP/2 通信协议

首先 gRPC 使用基于 HTTP/2 的通信协议，HTTP/2 支持多路复用、头部压缩、服务器推送等特性，这些特性使得 gRPC 在传输效率上比传统的 HTTP/1.x 有了很大的提升。

HTTP/2 的多路复用功能允许在单个连接上并行处理多个请求。这可以减少 TCP 连接数量，降低内存和 CPU 等的压力。

![HTTP/2 Multiplexing](/assets/img/http-1-2.png)

### 基于 Protocol Buffers 序列化协议

其次 gRPC 使用 Protocol Buffers 序列化协议。Protocol Buffers 是一种高效的二进制序列化格式，相比于 XML 或者 JSON 格式的数据传输，Protocol Buffers 更加轻量级，传输效率更高。它能够快速地将结构化数据序列化为二进制格式，并且快速地进行反序列化，因此能够提高数据传输的效率，降低系统的网络开销。

### 异步非阻塞编程模型

gRPC 在设计上采用了异步非阻塞的编程模型，客户端和服务器可以并行处理多个请求，不会因为某个请求的阻塞而导致整个系统的性能下降。这种设计可以更有效地利用系统资源，提高系统的性能和可用性。

### 支持流式处理

gRPC 支持基于流的数据传输，包括单向流、双向流等，这种流式处理机制使得 gRPC 在处理大量数据时更加高效，同时也提高了系统的可用性。通过流式处理，可以更灵活地处理数据，降低系统的延迟和资源消耗。

## 高可靠

### 连接管理

gRPC 的连接管理中，有两个非常重要的组件：名称解析器和负载均衡器。名称解析器负责将名称转化成 IP 地址，就像域名 DNS 解析，IP 地址可能有多个。名称解析器最后将这些解析出来的 IP 地址交给负载均衡器，负载均衡器负责从这些地址创建连接并在连接之间对 RPC 进行负载均衡。

连接创建后，gRPC 将保持连接池稳定。比如 DNS 条目可能会随着时间的推移而改变或者出现新的 IP 地址，此时负载均衡器会删除/新建他们。

### 识别失败连接

gRPC 还能灵活处理失败连接。对于端点主动终止连接时，关闭逻辑会产生 TCP 的 FIN 握手，进而关闭 HTTP/2 连接，最后结束 gRPC 连接。这个过程不需要 gRPC 做额外的工作。

对于异常情况下的连接失败，gRPC 通过 HTTP/2 KeepAlive 来解决。gRPC 会定期发送 HTTP/2 PING 帧用于确定连接是否处于活跃状态。如果 PING 未及时响应，gRPC 会认为连接失败，关闭并打开新的连接。

### 保持连接活跃

上面的 KeepAlive 功能除了能用来识别失败连接，还能用来保持连接活跃。对于一些代理服务器，由于资源非常有限，会终止空闲连接以节省资源。此时为了保持连接的活跃状态，gRPC 会定期向连接发送 HTTP/2 PING 帧，以防止连接被服务器或代理终止。

## 总结和建议

总结一下，gRPC 的高性能主要通过 HTTP/2 通信协议、Protocol Buffers 序列化协议、异步非阻塞编程模型、支持流式处理等。而 gRPC 的保证高可靠主要有：连接管理、识别失败连接和保持连接活跃：
![gRPC Summary](/assets/img/grpc-summary.png)

在我们的项目中，建议尽可能充分利用 gRPC 的以上特性来提升我们的程序。例如在客户端和服务端上都应该采用并发编程来提高 gRPC 的利用率，充分利用 HTTP/2 多路复用以及异步非阻塞编程模型等特性。

## 扩展阅读

- [gRPC on HTTP/2 Engineering a Robust, High-performance Protocol](https://grpc.io/blog/grpc-on-http2/)
- [So You Want to Optimize gRPC - Part 1](https://grpc.io/blog/optimizing-grpc-part-1/)
- [So You Want to Optimize gRPC - Part 2](https://grpc.io/blog/optimizing-grpc-part-2/)
