---
title:     'Gin 框架源码概览'
tags:      [What, How, Gin, Golang]
series:    'Gin 源码分析'
---

[Gin](https://gin-gonic.com/) 是一个 Golang Web 框架，优势是拥有极高的性能和简易的 API，类似 Ruby 的 [sinatra](https://github.com/sinatra/sinatra) 框架。本文会从一个简单示例入手，对 Gin 的源码做一个简单导读，代码版本为最新的 [v1.9.1](https://github.com/gin-gonic/gin/tree/v1.9.1)。

## 简单示例

我们先从一个简单示例入手，看看 Gin 究竟做了什么：
```golang
package main

import "github.com/gin-gonic/gin"

func main() {
    // 一、创建 Engine 对象
    gin := gin.New()
    // 二、注册中间件
    gin.Use(Logger(), Recovery())
    // 三、注册路由
    gin.GET("/ping", func(c *gin.Context) {
        c.JSON(200, gin.H{
            "message": "pong",
        })
    })
    // 四、运行服务
    gin.Run() // 监听并在 0.0.0.0:8080 上启动服务
    // 五、处理请求
}
```

运行程序，并打开浏览器访问 http://localhost:8080/ping, 网页上会展示出 JSON 响应：`{ "message": "pong" }`。

上述代码不难理解，我们下面会按照注释的五个步骤进行分开讲解。

## 一、创建 Engine 对象

我们先来看一下创建 Engine 的源码：
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/gin.go#L183
func New() *Engine {
    // ...
    engine := &Engine{
        // 路由组功能都是由 RouterGroup 实现
        RouterGroup: RouterGroup{
            // 存储中间件
            Handlers: nil,
            basePath: "/",
            root:     true,
        },
        // trees 用来存储路由树，后面 “注册路由” 中会使用到
        trees:                  make(methodTrees, 0, 9),
        // ...
    }
    engine.RouterGroup.engine = engine
    // 配置上下文对象池的构造函数，后面 “处理请求” 中会使用到
    engine.pool.New = func() any {
        return engine.allocateContext(engine.maxParams)
    }
    return engine
}
```

创建 Engine 对象的过程其实就是一些列初始化的过程，源码里截取了一些比较关键的内容并加上了注释。

关键的信息主要包括：
- 初始化路由组结构体
- 初始化路由树属性
- 绑定路由组与 Engine
- 配置上下文对象池的构造函数

## 二、注册中间件

Gin 中间件是支持全局、路由组两种级别，其中：
- 全局中间件存储在 `Engine.RouterGroup.Handlers` 属性中
- 路由组中间件存储在 `RouterGroup.Handlers` 属性中，创建新的 RouterGroup 时会继承全局或父级路由组中的中间件

### 注册全局中间件

我们先来看下全局中间件的注册源码：
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/gin.go#L307
func (engine *Engine) Use(middleware ...HandlerFunc) IRoutes {
    engine.RouterGroup.Use(middleware...)
    engine.rebuild404Handlers()
    engine.rebuild405Handlers()
    return engine
}
```
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/routergroup.go#L65
func (group *RouterGroup) Use(middleware ...HandlerFunc) IRoutes {
    group.Handlers = append(group.Handlers, middleware...)
    return group.returnObj()
}
```

可以看到核心逻辑其实是在 `RouterGroup.Use` 方法中完成的，逻辑就是在 `RouterGroup.Handlers` 变量中附加新的中间件。

### 注册路由组中间件

路由组中间件的注册示例代码为：
```golang
group := engine.Group("/v1", Logger(), Recovery())
group.GET(...)
```

具体实现源码：
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/routergroup.go#L72
func (group *RouterGroup) Group(relativePath string, handlers ...HandlerFunc) *RouterGroup {
    return &RouterGroup{
        Handlers: group.combineHandlers(handlers),
        basePath: group.calculateAbsolutePath(relativePath),
        engine:   group.engine,
    }
}
```
`Group` 方法会创建一个新 `RouterGroup` 对象，跟父级 `Group/Engine` 的中间件和基础路径两个属性进行合并。

## 三、注册路由

我们一般通过 `GET`, `POST`, `PUT`, `PATCH`, `DELETE` 等方法来注册路由，查看源码会发现它们都是通过统一的 `RouterGroup.handle` 方法来处理：
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/routergroup.go#L116
func (group *RouterGroup) GET(relativePath string, handlers ...HandlerFunc) IRoutes {
    return group.handle(http.MethodGet, relativePath, handlers)
}
```
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/routergroup.go#L86
func (group *RouterGroup) handle(httpMethod, relativePath string, handlers HandlersChain) IRoutes {
    // 合并继承的基础路径和当前相对路径，得到完整的路由路径
    absolutePath := group.calculateAbsolutePath(relativePath)
    // 合并所有继承的中间件与处理程序
    handlers = group.combineHandlers(handlers)
    group.engine.addRoute(httpMethod, absolutePath, handlers)
    return group.returnObj()
}
```
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/routergroup.go#L241
func (group *RouterGroup) combineHandlers(handlers HandlersChain) HandlersChain {
    finalSize := len(group.Handlers) + len(handlers)
    assert1(finalSize < int(abortIndex), "too many handlers")
    mergedHandlers := make(HandlersChain, finalSize)
    copy(mergedHandlers, group.Handlers)
    copy(mergedHandlers[len(group.Handlers):], handlers)
    return mergedHandlers
}
```
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/gin.go
func (engine *Engine) addRoute(method, path string, handlers HandlersChain) {
    // ...
    // 获取 HTTP 方法对应的路由树链表
    root := engine.trees.get(method)
    // 如果链表不存在则新建
    if root == nil {
        root = new(node)
        root.fullPath = "/"
        engine.trees = append(engine.trees, methodTree{method: method, root: root})
    }
    // 在 HTTP 方法对应的路由树链表中添加路由节点，节点中记录路由路径和所有处理程序
    root.addRoute(path, handlers)
    // ...
}
```

Gin 的路由使用的是[基数树](https://zh.wikipedia.org/zh-cn/%E5%9F%BA%E6%95%B0%E6%A0%91)，是一种优化后的前缀树，他是提升 Gin 性能的主要原因，具体路由树的实现不在本文范畴。

Gin 为每个 HTTP 方法单独创建一个路由树，且是动态创建，即当应用没有用到 DELETE 路由时就不会创建 DELETE 路由树。

最终路由配置信息记录在路由树节点里，主要配置包括完整路由路径和所有处理程序。

Gin 路由的处理程序其实就是最后一个中间件，Gin 中把他们统一抽象为了 Handler。

## 四、运行服务

Gin 运行服务逻辑其实很简单，是通过 net/http 库接口 `ServeHTTP` 来实现的：
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/gin.go#L376
func (engine *Engine) Run(addr ...string) (err error) {
    // ...
    address := resolveAddress(addr)
    debugPrint("Listening and serving HTTP on %s\n", address)
    err = http.ListenAndServe(address, engine.Handler())
    return
}
```
```golang
// 这个是 net/http 库中的源码，不属于 gin
// https://github.com/golang/go/blob/go1.22.0/src/net/http/server.go#L3436
func ListenAndServe(addr string, handler Handler) error {
    server := &Server{Addr: addr, Handler: handler}
    return server.ListenAndServe()
}

// Gin 中需要实现 ServeHTTP 接口方法
// https://github.com/golang/go/blob/go1.22.0/src/net/http/server.go#L86
type Handler interface {
    ServeHTTP(ResponseWriter, *Request)
}
```
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/gin.go#L570
func (engine *Engine) ServeHTTP(w http.ResponseWriter, req *http.Request) {
    // 在上下文对象池中获取上下文对象
    c := engine.pool.Get().(*Context)
    c.writermem.reset(w)
    c.Request = req
    c.reset()

    // 具体处理请求逻辑，后面讲解
    engine.handleHTTPRequest(c)

    // 将上下文对象放回对象池中
    engine.pool.Put(c)
}
```

Gin 运行服务是通过 net/http 库的 `ListenAndServe` 函数完成的，其中建立连接和将请求发送给 Handler 处理的详细逻辑不在本文范畴，可以进一步查看 net/http 源码了解。Gin 框架需要做的就是构建一个 Handler 传入给 `ListenAndServe` 函数，在 Handler 中实现 `ServeHTTP` 接口方法。

运行服务第一步是从 Engine 池中取出 Context 对象。这里通过使用标准库 `sync.Pool` 来减少频繁实例 Context 对象带来的资源消耗。如果对象池中不存在实例，则会通过 `Engine.pool` 对象的 `New` 方法创建，这个方法的定义在 “创建 Engine 对象” 章节有提到过。

取出 Context 对象后，会绑定 response 和 request 对象，之后的处理请求逻辑就是通过 `handleHTTPRequest` 方法和参数 Context 对象来实现。

Gin 的 Context 对象是 Gin 框架最重要的部分，后续的大部分 Web 功能都可以通过 Context 来完成，这个对象的源码值得单独一篇文章来讲解。

## 五、处理请求

上面运行服务成功后，后续的 HTTP 请求处理主要是在 `handleHTTPRequest` 方法中完成，我们来看一下相关源码：
```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/gin.go#L592
func (engine *Engine) handleHTTPRequest(c *Context) {
    // ...
    t := engine.trees
    for i, tl := 0, len(t); i < tl; i++ {
        // 找到对应 HTTP 方法的路由树
        if t[i].method != httpMethod {
            continue
        }
        root := t[i].root
        // 在路由树中搜索匹配的路由节点
        value := root.getValue(rPath, c.params, c.skippedNodes, unescape)
        if value.params != nil {
            c.Params = *value.params
        }
        if value.handlers != nil {
            c.handlers = value.handlers
            c.fullPath = value.fullPath
            // 遍历并运行所有处理程序(中间件+处理程序)
            c.Next()
            c.writermem.WriteHeaderNow()
            return
        }
        // ...
    }
    // ...
    c.handlers = engine.allNoRoute
    serveError(c, http.StatusNotFound, default404Body)
}
```

```golang
// https://github.com/gin-gonic/gin/blob/v1.9.1/context.go#L171
func (c *Context) Next() {
    c.index++
    for c.index < int8(len(c.handlers)) {
        c.handlers[c.index](c)
        c.index++
    }
}
```

首先遍历路由树找到对应 HTTP 方法的路由树，我们上面提到过 Gin 会为每个 HTTP 方法创建一个路由树。

在路由树中搜索匹配的路由节点，如果没匹配则最后会响应 404。

匹配到路由节点后，遍历并运行节点里的所有处理程序。所有处理程序包括全局和路由组中间件，以及路由注册时传入的 Handler 函数。

遍历处理程序的进度存储在共享的 Context 层，这样设计是方便异常处理，当某个处理程序出现 panic 时，可以恢复进度并继续执行。默认启用的 Recovery 中间件就是一个异常恢复的实现。

## 总结和建议

以上是 Gin 框架源码的一个简单导读，如果想继续深入，以下是一些推荐的方向：
- Gin 的路由树实现，了解 Radix 树是什么，为什么说他很快
- Gin 的重要对象的实现，例如 `Gin.Engine`、`Gin.Context`，方便了解到常见功能的实现
- Gin 异常恢复逻辑，了解 Recover 中间件的实现
- Gin 的优雅关停实现

最后附上本文的导图供大家回顾：
![Gin Source Overview](/assets/img/gin-source-overview.png)
