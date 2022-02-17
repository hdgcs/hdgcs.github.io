---
title:  '一些 Ruby/Rails 小技巧'
tags:   [Ruby, Rails]
cover-img: /assets/img/rails.jpg
---

最近做项目的一些小记录，有些地方可能考虑的不对，发出来一起讨论，希望大家可以一起提高

现在假设我们在开发一个小商店应用（以下用 Store），并且领导说可以用 Rails 5。

## 初始化应用

那第一步就是初始化依赖，做一些应用配置之类的，在这里记的小问题有：

### PostgreSQL 中，添加 host 设置的同时，也需要设置用户名和密码

这里有 pg 登录途径的相关知识，因为有了 Unix Socket 方式，于是在保持默认安装的 pg(9.6) 配置时，应用的数据库配置文件只需要设置非常简单的几项就能正确连接数据库，但这里要注意的是，一旦在 `database.yml` 中设置了 host（即使是 localhost），这时候你还要设置用户名和密码才能连接，原因是 pg 此时改用用户名密码的登录方式了。

### 使用 dotenv 配置项目能方便项目的协作开发

对比 figaro 的 `.sample` 方案，dotenv 多了个 `.env` 文件可以设置变量默认值，可以方便不常变化的变量设置。但有很多项目在使用 `.sample` 方式配置项目，这里有点不太理解（我搜到的有安全问题，但我总觉的可以绕过这个问题啊）。

## 应用模型

初始化完后，就来到对应用模型的设计环节了。

### persisted? 才是判断是否创建成功最有效的方式

首先，我们要知道 `Model.create` 方法无论成功与否都返回了一个对象，一般情况下，我们会想到用 `valid?` 来判断:

```ruby
user = User.create(name: "pine")
if user.valid?
  # 设想的成功情况
else
  # 失败情况
end
```

什么情况下不一定成功？

```ruby
class One < ActiveRecord::Base
  has_many :twos
  after_create :create_twos_after_create
  def create_twos_after_create
    # Use bang method in callbacks, than it will rollback while create  two failed
    twos.create!({})    # This will fail because lack of the column `number`
  end
end

class Two < ActiveRecord::Base
  validates :number, presence: true
end
```

此时 `One.create` 失败，但 `One.create.valid?` 返回 `true`，所以正确操作应该是(经二楼朋友提示，改用更精简的 `persisted?`)：

```ruby
# if User.exists?(user.id)
if user.persisted?
  # Success
else
  # Failed
end
```

这有详细解释：[Ruby on Rails Active Record return value when create fails?](https://stackoverflow.com/a/46091806/7840077)

### 正确的终止回调

官方 Guides 中提到使用 `throw :abort` 手动终止回调一个回调链，并且给出了下面的提示：

> 当回调链停止后，Rails 会重新抛出除了 ActiveRecord::Rollback 和 ActiveRecord::RecordInvalid 之外的其他异常。这可能导致那些预期 save 和 update_attributes 等方法（通常返回 true 或 false ）不会引发异常的代码出错。

但是经过测试，`throw :abort ` 只在 `before_` 类型的回调中能其作用，`after_` 回调里，使用 `throw :abort` 会得到一个 `UncaughtThrowError` 的异常，因此，`raise ActiveRecord::Rollback` 应该是现在手动终止回调最佳的办法了。

### 回调里的异常正确处理并不是那么简单

同样使用上面 `One`，`Two` 模型创建的例子，完整的异常的处理是怎么样的呢？大概应该是这样的：

```ruby
# models
class One < ActiveRecord::Base
  has_many :twos
  after_create :create_twos_after_create
  def create_twos_after_create
    # Use bang method in callbacks, than it will rollback while create  two failed
    twos.create!({})    # This will fail because lack of the column `number`
  rescue ActiveRecord::RecordInvalid => e  # This is exception of Two, but not One
    errors.add(:base, e)
    raise ActiveRecord::Rollback
  end
end

class Two < ActiveRecord::Base
  validates :number, presence: true
end
```

```ruby
# controllers
class OneController < ActionController::Base
  def create
    one ＝ One.create
    if One.exists?(one.id)
      redirect_to one
    else
      render :new
    end
  end
end
```

```erb
<!-- views -->
<ul>
  one.errors.full_messages.each do |message|
    <li><%= message %></li>
  end
</ul>
```
这样就基本完成了，上述主动捕获的 `ActiveRecord::RecordInvalid` 是其他模型的，上述 Guides 中提到的：

> Rails 会重新抛出除了 ActiveRecord::Rollback 和 ActiveRecord::RecordInvalid 之外的其他异常

里，虽然 `ActiveRecord::RecordInvalid` 会被处理成回滚操作，但是 Rails 自身的处理会丢失了错误信息，因此，我们这里要捕获异常，并作记录错误信息操作，最后手动终止回调。

另外，因为这是不属于本模型的错误，我们把它加到 `:base` 键里。同理，如果回调中有其他可能需要终止执行的操作，也可以这样操作：

```ruby
def create_twos_after_create
  # Use bang method in callbacks, than it will rollback while create  two failed
  twos.create!({})    # This will fail because lack of the column `number`
  api_get!(...)
rescue ActiveRecord::RecordInvalid, ApiError => e  # When get exception after call API
  errors.add(:base, e)
  raise ActiveRecord::Rollback
end
```

## 开发应用

对于开发应用的过程，就有更多的小问题了:

### 字符串间的操作，请使用插入代替拼接

```ruby
# Good
logger.info "#{object.name} - #{object.number}"
# Bad
logger.info object.name + ' - ' + object.number
```

上述两种方案里，后者当 object.name, object.number 出现 nil, 或其他非字符串类型值，你就会得到一个 `TypeError` 的异常，而第一种会帮我们尝试转化字符串，对于写 JS 多，第二种会更常用，可能需要注意一下。

### 正确的理解方法和变量

这个属于 Ruby 语言问题，Ruby 方法省略括号，给了我们很大方便，似乎是促使我们将方法和变量一同看待。这样使得语法精炼很多，但理解不深时也会容易造成一些误解。

列举一个案例，我现在需要通过一个传参，清空所有参数，并且由于对 params 对象了解不够，用了最简单的赋值清空：

```ruby
# controllers
def  index
  params = {} if "true" == params[:deny_all]
  ...
end
```

这里也是不正确的，当 `"true" == params[:deny_all]` 条件不成立时，params（此时是变量） 的值会被设成 nil。这里其实是 Ruby 的基础（不同于其他语言的几点地方），但有时业务一上来，可能就会没注意到这些了。具体问题是啥？我们继续进一步补全 Ruby 的语法：

```ruby
def  index
  if "true" == self.params()[:deny_all]
    params = {}
  else
    params = nil
  end
  ...
end
```

这样问题就暴露的很明显了，这是 params 由方法变成变量引起的，这里正确的解决办法就不贴了，大概就是应该是去查看 `params` 文档，使用方法清空而非引入变量。

### 利用 document DOM 对动态节点绑定事件

当一个元素是用户 JS 触发插入的，我们该如何为该元素事先添加事件？

现在 Store 中有一个订单页，用户可以通过手动添加商品，这里，我们要为每一个商品项添加监听数量变动的事件，商品项中数量节点的类为 `.product-count`，我们应该如下操作：

```js
// Right
$(document).on("change", ".product-count", function(e) {
  ...
});

// Wrong
$(".product-count").change(function(e) {
  ...
});
```

由于商品项元素是 JS 添加的，商品项中的 `.product-count` 元素也即属于动态节点，而 jQuery 提供了事例的方案为动态节点绑定时间，具体请参照文档：[jQuery-On](http://devdocs.io/jquery/on)

### 为静态资源添加范围限制

Rails 默认会将所有的 css 和 js 分别打包成一个一个文件引入，为了提升程序健壮性和性能，我们要自己为专属资源添加范围限制，这里，最简单快捷的可以使用资源名化作范围。现在我要为管理模块的订单流水记录(admin/flow_records)的样式和脚本添加限制：

```erb
<!-- layouts/application.html.erb -->
<html>
<head></head>
<body class="<%= controller_path.gsub(/[\/\_]/, '-') %>"></body>
</html>
```

```js
// javascripts/admin_flow_records.js
$(function() {
  if (!document.body.classList.contains('admin-flow-records')) { return }
  ...
});
```

```css
/* stylesheets/admin_flow_records.scss */
body.admin-flow-records {
  ...
}
```

如此，资源限制就完成了，其他资源也可以快速实现限制。
