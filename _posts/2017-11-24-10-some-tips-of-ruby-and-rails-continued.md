---
title:  '一些 Ruby/Rails 小技巧续'
tags:   [Ruby, Rails]
cover-img: /assets/img/rails.jpg
---

第一篇地址在这：[一些 Ruby/Rails 小技巧]({{ '/posts/9-some-tips-of-ruby-and-rails' | relative_url }})

我们接着记录开发应用中遇到的一些小问题。

## 在 sql 中拼接字符串形式的时间需要注意时区问题

我们经常会使用这样的查询：

```ruby
Product.where("created_at > %", 2.days.ago)
```

如果你的应用设置了时区，这里 Rails 会帮我们把时间转化为 UTC 时间插入。但如果我们传入的是字符串而不是 Rails 的 Time/Date/DateTime 格式，情况又是怎么样呢？能不能直接 `2.days.ago.to_s` ?

能不能直接尝试后就知道了。经过尝试，一个时间对象转换成字符串的后会在当前时区时间加上 `+0800` 这样的时区后缀。但是问题就在有些数据库并不能解析这个后缀。在我们用的 PostgreSQL 中，这样的后缀可以说是被直接忽略掉的。

因此通过上面的分析，该问题的答案就变成了当 sql 需要传入字符串时间时，需要转换成 UTC 时间字符串。具体可以这么处理：

```ruby
# 原始时间是对象
2.days.ago.utc.to_s

# 原始时间是字符串
"2017/11/24 12:00:00".in_time_zone.utc.to_s
# 或者
"2017/11/24 12:00:00".to_time.utc.to_s # 这里不能使用 to_datetime，因为 to_time 比 to_datetime 多支持一个时区参数，并且该参数默认值为 :local , 符合我们需求
```

如果有其他更直观的方法，请留言告诉我。

## 理解 map/collect/inject/reduce/each_with_object

标题是不合理的，因为他们并不全部相关。但是这些方法经常困扰着一些新人，所以放一起对比解释一下。

### map/collect

他们只是别名，C 源码中用的是 collect 方法统一定义。使用的话记住两点：

1. 最终返回一个数组，每次迭代的值为该数组的元素；
2. 操作单元素枚举对象（Array）时，块中应该指定一个参数；操作双元素枚举对象（Hash）时，块中应该指定 1..2 个参数，当指定 1 个参数时，其实是将 Hash 先转化成 Array 在进行操作。

### inject/reduce

他们也是别名，源码中用的是 inject 方法统一定义。inject 的作用是迭代更新每次结果。需要注意的是当没有初始值参数时，实际上迭代次数为 size-1，操作枚举对象的第一个元素被指定为初始值，没有进行迭代。以下是代码说明：

#### 当指定初始值参数时

```ruby
[1, 2, 3].map(10) { |result, item| result + item } #=>16

# 等价于
result = 10
[1, 2, 3].each { |item| result = result + item } # 这里的 result + item 表达式与 map 中迭代的表达式一致
result #=> 16
```

#### 当没有指定初始值参数时

```ruby
[1, 2, 3].map { |result, item| result + item } #=> 6

# 等价于
data = [1, 2, 3]
result = data.shift
data.each { |item| result = result + item } # 此时只有 2, 3 元素被迭代
result #=> 6
```

### each_with_object

这个方法其实很好理解，就是迭代前，引入一个变量并最终返回那个变量（至于这个变量你有没有用到，方法并不关心）。

```ruby
[1, 2, 3].each_with_object({}) { |item, object| object[item] = 0 } #=> {1=>0, 2=>0, 3=>0}
# 等价于
object = {}
[1, 2, 3].each { |item| object[item] = 0 }
object #=> {1=>0, 2=>0, 3=>0}

[1, 2, 3].each_with_object({}) { |item, object| item += 1 } #=> {}
# 等价于
object = {}
[1, 2, 3].each { |item| item += 1 }
object #=> {}
```

### 总结

这三个方法都是为 ruby 枚举对象迭代多做了一些额外的工作，其中 map/collect 是在枚举对象迭代时，收集元素，最后生成一个数组；each_with_object 是帮助我们为枚举对象的迭代引入一个结果变量（作为参数引入）；最后 inject/reduce 做的事情是引入结果变量后，还修改了迭代体，每次迭代体最后返回的结果存给了该变量。

## 什么时候该用 render/redirect_to .. and return

官方 Guides 中提到了 action 中重复渲染/重定向的问题，并建议了使用 `render/redirect_to .. and return` 解决。但是有些人刚开始可能会不明白具体哪里需要（比如我），这里先将语句展开：

`render/redirect_to .. and return`

=> `(render/redirect_to ..) && return`

=> `if (render/redirect_to ..); return; end`

很好理解，他是希望在一个方法里提前结束，因为 `render/redirect_to` 并不等于 `return`。

Rails 还有 `before_action` 回调，这里需要怎么处理？

```ruby
class HomeController < ApplicationController
  before_action do
    redirect_to root_url if ... # 不需要 and return
  end

  def index
  end
end
```

这里不需要做其他处理的原因是因为 Rails 会判断其他域（方法、块）中是否已经渲染或重定向，这里回调换成方法体也是一样的情况。

总结：一个域（方法、块）中有多个显示的渲染或重定向，除了最后一个都需要 `and return`

## 在 model 层而不是数据库层设置默认值

原因：model 层设置默认值更灵活，且适用场景更多，例如设置动态值等。

如何设置：

```ruby
model User < ApplicationRecord::Base
  after_initialize :set_defaults, if: :new_record? # 仅当初始化的是新纪录的时候设置默认值

  def set_defaults
    self.attribute  ||= 'some value' # bool 以外的字段设置
    self.bool_field = true if self.bool_field.nil? # bool 字段设置
  end
```

## 常量的自动加载

### 开发环境中，Rails 应用的自动加载会与 Ruby 的 require 冲突

原因：Ruby `require` 维护着 `$LOADED_FEATURES` 全局变量，Rails 的 `load` 加载不会更新 `$LOADED_FEATURES`，所以 Rails 自动加载后，`require` 还是会再执行一遍。另外如果 `require` 先运行了，Rails 没有完成该常量的自动加载，也就不会把该常量标记为自动加载的常量，因此开发环境设置的常量重新加载会失效。

做法：Rails 中，应保持默认自动加载的目录文件规则。即使出现需要手动引入常量，也应该使用 Rails 的 `require_dependency` 解决。

### 自动模块

在一些项目的 lib 文件夹中，经常会出现 api.rb, api/product.rb, api/user.rb 之类的结构，其中 api.rb 只有一个空模块定义。但其实 Rails 已经为我们处理了这类需求。假设 Rails 自动加载目录中含有 api 目录，且 Rails 自动加载中为找到 Api 常量定义，则 Rails 会为 Api 常量定义好空模块。即上述出现的结果中，api.rb 文件其实是可省略的，因为 Rails 帮我们这么干了。

## 不要依靠赋值方法的返回值

这个主要是因为 Ruby 中有一个约定：赋值语句/方法总是返回表达式右值。我们看一个案例：

```ruby
class User
  attr_reader :name

  def name=(name)
    if name.present?
      @name = name
      return true
    else
      return false
    end
  end
end

user = User.new
user.name = "" #=> ""
user.name #=> nil
user = User.new
user.name = "Pine" #=> "Pine"
user.name #=> "Pine"
```

这里 User#name=() 的 return 语句会被忽略，不会得到想要的效果。
