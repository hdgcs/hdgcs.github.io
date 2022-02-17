---
title:  '内部系统的 API 响应和异常实践'
tags:   [API, API 响应, API 异常, 前后端分离]
cover-img: /assets/img/api.png
---

Web 开发中前后端分离的一大阻碍是交互的数据结构复杂难用，离服务端直接渲染那样简单和灵活相差甚远。另外很多项目没考虑自身场景的滥用了 API 规范，比如内部的后台系统，经常被“规范”束缚强制统一响应结构，将 4xx 甚至 5xx 异常全部改成 2xx 响应，然后自己定义一套复杂的异常规范。

对于内部后台系统，这种简单场景下的 API 响应和异常处理，其实设计可以考虑这些：

- 完全用 HTTP Status 规范，不另起 code。
- 2xx, 4xx, 5xx 分开处理，基本所有 HTTP Client 都能很好的区分他们，不需要强制统一起来（后面会讲分开的优点）。
- 正常响应情况，只要统一用一个规范的响应体即可，这里不难。对于任何异常情况，后端统一用异常处理，这样可以统一到基类一起处理响应，业务代码中也可以快速 return（少写很多 else）。另外可以在基类声明一个 ClientError 异常，出错时不清楚该用什么异常就都用这个。

后面我们基于这些，详细设计出一种方案，并给出实践例子。

## 四种响应和异常

首先，我们需要为响应和异常分类，这里根据场景频率对异常和响应分类，对于内部系统，大部分情况是正确响应和只需要一个错误信息的异常响应，这里将他们分别归类到“2xx响应”和“4xx响应”。剩下情况是服务器异常和复杂业务异常响应，这里将它们分别归类到“5xx响应”和“6xx+响应”。

根据二八原则，常用的前两者应该尽可能做到使用简单，因此使用方式要区别开后面两者。不常见的“6xx+响应”为了保证功能强大允许使用起来复杂一点（反正用的少）。

### 2xx 响应 - 正常情况

这个比较简单，也很多规范，只要约束住 HTTP Status 为 2xx 和结构体就行

```
- status: 2xx
- message: 附带消息，比如成功提示
- data：功能主数据
- meta：功能附带数据，比如分页筛选等信息
```

### 4xx 响应 - 只需要一个错误信息的异常情况

```
- status: 4xx，常用错误，后台系统一般直接抛除一个 ClientError 并传入一个错误信息即可。
- message: 附带消息，前端统一处理所有这类异常，消息提示参考：`API Client Error: ${message}`
```

### 5xx 响应 - 服务器异常情况

完全不处理，这样能最大限度保留后端堆栈等异常。前端也统一处理所有这类异常，消息提示参考：

```
`API Server Error: ${statusText}`
```

### 6xx+ 响应 - 复杂业务异常情况

```
- status: 6xx+，这是不常用的错误，因此用法允许复杂一点，可以配合配置文件中使用，方便汇总所有业务错误，+的意思是还可以用 7xx, 8xx（HTTP Status 标准中，大于 600 都属于 Custom Status）。
- message：附带信息，一般是一个总结性的错误描述，也可以放到配置文件里。
- detail：指引前端如何进一步处理的主数据，要有这个，才需要用这类响应，否则应该使用简单的 4xx 响应。
```

## 实践例子

下面代码以后端 Rails 5，前端 Vue.js 2 举例：

1、后端路由定义和功能处理，功能为了简单，放到一个 controller 中，根据不同参数处理四种响应。这里为了简单，放到一起了，实际上这四种场景会遍布在你的项目的每个功能里：

```rb
# config/routes.rb

get '/test_api/:status', to: 'test_api#index'
```

```rb
# app/controller/api/test_api_controller.rb

class Api::TestApiController < Api::ApplicationController
  def index
    case params[:status]
    when '2xx'
      render_data '我是正常响应数据'
    when '4xx'
      raise ClientError.new('我是一个 4xx 错误') # 这里常用异常处理很简单，使用起来跟后端渲染中的设置 flash 错误差不多简单了
    when '5xx'
      undefined_method # 这是一个没有定义的方法或变量，这里目的是手动制造一个 5xx 异常
    when '6xx'
      raise CustomError.new(:order_create_failed, '我是业务错误 detail 信息')
    else
      raise ActionController::BadRequest, '没找到该 status 处理方式'
    end
  end
end
```

2、后端基类定义，这个是后端最重要的地方，包括三种响应的统一处理（5xx 应用不处理）：

```rb
# app/controller/api/application_controller.rb

class Api::ApplicationController < ActionController::API
  class ClientError < StandardError
    attr_accessor :status, :message

    def initialize(message, status = 400)
      @status, @message = status, message
    end
  end

  class CustomError < StandardError
    attr_accessor :status, :message, :detail

    def initialize(name, detail = {})
      error = Rails.configuration.custom_errors.find { |error| error['name'] == name.to_s }
      @status, @message, @detail = error['status'], error['message'], detail
    end
  end

  # 4xx 响应
  rescue_from ClientError do |exception|
    render status: exception.status, json: { message: exception.message }
  end

  # 6xx+ 响应
  rescue_from CustomError do |exception|
    render status: exception.status, json: { message: exception.message, detail: exception.detail }
  end

  # 2xx 响应
  def render_data(data, status: 200, message: "", meta: {})
    render status: status, json: { message: message, data: data, meta: meta }
  end
end
```

3、后端 CustomError 配置，汇总在一起使得错误信息更清晰：

```rb
# config/initializers/config_custom_errors.rb

file_dir = Rails.root.join('config', 'custom_errors.yml')
Rails.configuration.custom_errors = YAML.load_file(file_dir)
```

```yml
# config/custom_errors.yml

- status: 600
  name: order_create_failed
  message: 订单创建失败
- status: 601
  name: order_cancel_failed
  message: 订单取消失败
```

4、前端路由定义和功能处理：

```js
// config/routes/index.js

{
  path: '/test_api/:status',
  component: () => import('@/pages/test_api'),
}
```

{% raw %}
```vue
// pages/test_api/index.vue

<template>
  <div>
    <div>{{ result }}</div>
    <div v-if="$flash">{{ $flash }}</div>
  </div>
</template>

<script>
  import request from '@/utils/request'

  export default {
    data () {
      return {
        result: '',
      }
    },
    beforeMount () {
      $flash = ''
    },
    mounted () {
      request
        .get(`/test_api/${this.$route.params.status}`)
        .then(data => {
          this.result = data
        })
        .catch(error => {
          // 只有功能有 6xx+ 响应时才需要 catch，普通功能不必写这个
          this.result = `我是一个业务错误，${JSON.stringify(error.response.data)}，${error.response.status}`
          const detail = error.response.data.detail
          if (error.response.status === 600) {
            // 做一些 600 异常处理的事情，可以使用后端传过来的 detail
          } else if (error.response.status === 601) {
            // 做一些 601 异常处理的事情，可以使用后端传过来的 detail
          }
        })
    },
  }
</script>
```
{% endraw %}

5、前端请求统一处理处，这个是前端最重要的地方：

```js
// utils/request.js

import axios from 'axios'

const request = axios.create()
request.interceptors.request.use(
  config => config,
  // 请求发出失败处理，比如无网络
  error => {
    $flash = error.message
    // 这个是一个永远 pending 的 Promise，可以阻止 Promise 持续传播到 then 中
    // https://juejin.cn/post/6935404767778701325
    return Promise(() => {}) 
  },
)
request.interceptors.response.use(
  response => response.data,
  error => {
    // 无响应处理，比如 timeout
    if (!error.response) {
      $flash = `API Noresponse Error: ${error.message}`
      return Promise(() => {}) // 返回一个 pending 的 Promise，防止执行功能的 then 方法
    // 4xx 响应处理
    } else if (error.response.status >= 400 && error.response.status <= 499) {
      $flash = `API Client Error: ${error.response.data.message || error.response.status}`  // 当 4xx 错误是由 Web 服务器或者应用服务器触发的，此时没有 message 值，这里要特殊处理一下
      return Promise(() => {})
    // 5xx 响应处理
    } else if (error.response.status >= 500 && error.response.status <= 599) {
      $flash = `API Server Error: ${error.response.status}`
      return Promise(() => {})
    // 6xx+ 响应处理
    } else {
      return Promise.reject(error) // 不处理，直接抛异常给业务层处理
    }
  },
)

export default request
```

这里 `$flash` 只是一个简略的全局变量（这个处理不是重点，因此没有扩展），实际应用中可以实现具体的响应处理。

这样就大功告成了。

## 其他

以上是一个思路，具体应用到项目中，可以在添加很多规范约束上的东西，比如考虑同伴如果不使用规范怎么拒绝（这个其实可以参照 Rails 对重复设置 response 或者没有设置 response 的处理）。

API 响应和异常处理属于很常见的技术问题了，以上是我的一些浅显看法，欢迎大家发表任何想法，一起讨论进步。
