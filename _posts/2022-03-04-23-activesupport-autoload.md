---
title:  'ActiveSupport 的 Autoload 扩展'
tags:   [ActiveSupport, Rails, Ruby]
series: 'Rails 源码分析'
---

Ruby 有个内核方法 `autoload`，可以很方便的完成复杂的依赖加载，但是这个方法需要指定目录。遵守约定大于配置的 Rails，早已经定义好了
目录规范，此时就显得目录参数有点多余，于是 Rails 就在 `ActiveSupport::Autoload` 里对它进行了扩展。另外 eager_load 则是 `ActiveSupport::Autoload` 里进一步通过预加载提升性能的功能。

## 减少文件路径参数

Ruby 原生的 `autoload` 方法定义为：

```
autoload(module, filename) → nil
```

Rails 的扩展直接将第二个参数 `filename` 改成了可选参数，如果你没有传入，会通过当前环境和加载 `module` 的名称生成 `filename`，逻辑如下：

```ruby
[name, @_under_path, const_name.to_s].compact.join("::").underscore
```

大部分都好理解，其中的 `@_under_path` 是对约定的增强，下面来解释。

## 特殊情况处理

### 子模块处理

class/module 的组织会用到文件夹，此时如果文件夹里的类多了，定义也会比较麻烦：

```ruby
autoload :'Adapters::MySQL'
autoload :'Adapters::PostgreSQL'
autoload :'Adapters::SQLite'
```

这时候可以利用 `autoload_under` 进行改进，这个方法会在块作用域下配置上面提到的 `@_under_path` 值：

```ruby
autoload_under :adapters do
  autoload :MySQL
  autoload :PostgreSQL
  autoload :SQLite
end
```

### 单文件处理

有些类，比如异常类虽然有多个，但是都很简单，不想分太多文件，比如都定义在一个 `errors.rb` 文件里面：

```ruby
# errors.rb
class Error < StandardError; end
class ArgumentError < Error; end
class BadRequestError < Error; end
```

此时需要：

```ruby
autoload :Error, 'errors'
autoload :ArgumentError, 'errors'
autoload :BadRequestError, 'errors'
```

这里可以通过 `autoload_at` 改进：

```ruby
autoload_at :errors do
  autoload :Error
  autoload :ArgumentError
  autoload :BadRequestError
end
```

虽然节省不大，但是利用块将同类资源放到了一起，直观很多。

## 及时加载 eager_load

接下来是重点的 eager_load 功能。我们先思考一下，自动加载方便了我们编码，但有些常量是一定需要的，如果在线上可以提前加载出来这些常量，对性能肯定能提升。那有什么方法可以做到这个呢？答案就是 eager_load 功能。

### 基本使用

eager_load 功能用起来很简单，把你的库里肯定需要及时加载的模块放到 `eager_autoload` 块下即可：

```ruby
# active_lib.rb
module ActiveLib
  autoload :Model

  eager_autoload do
    autoload :Cache
  end
end
```

上面就会特殊处理这个 `Cache` 的加载。原理的话，`eager_autoload` 方法实际上是在块执行期间，设置了 `@_eager_autoload` 变量，然后 `autoload` 会对这个变量做特殊处理，将这个变量下加载的常量存储到 `@_eagerloaded_constants` 数组中。

上面只是存储起来，所有记得要在你的库的最后执行加载，这个 `eager_load!` 方法就是加载 `@_eagerloaded_constants` 数组里所有的常量：

```ruby
ActiveLib.eager_load!
```

如果你的库不止一个模块使用了 `ActiveSupport::Autoload`，记得要保证全部加载，通常这么做：

```ruby
# active_lib/module_a.rb
module ActiveLib
  module ModuleA
    extend ActiveSupport::Autoload
    # ...
  end
end

# active_lib/module_b.rb
module ActiveLib
  module ModuleB
    extend ActiveSupport::Autoload
    # ...
  end
end

# active_lib.rb
module ActiveLib
  extend ActiveSupport::Autoload
  include ActiveLib::ModuleA
  include ActiveLib::ModuleB

  def self.eager_load!
    ActiveLib::ModuleA.eager_load!
    ActiveLib::ModuleB.eager_load!
  end
end

ActiveLib.eager_load!
```

### 配合 Rails 使用

如果你的库是为 Rails 应用服务的，例如一个 Rails Engine，那么你还可以“什么时机执行加载”交给 Rails，Rails 有个配置项 `eager_load_namespaces` 就是处理这个的，这个还能配合 `config.eager_load` 配置项，能在合适的时机帮你加载：

```ruby
# active_lib.rb
module ActiveLib
  # ...
end

# 取消主动加载
# ActiveLib.eager_load!
```

使用 Railtie 让库支持 Rails 环境

```ruby
# active_lib/railtie.rb
module ActiveLib
  class Railtie < Rails::Railtie
    config.eager_load_namespaces << ActiveLib
  end
end
```

## 参考

以上代码基于 Rails 7：

- [ActiveSupport::Autoload 源码](https://github.com/rails/rails/blob/74ba52ec5c/activesupport/lib/active_support/dependencies/autoload.rb)
- [Rails 初始化 eager_load 处理](https://github.com/rails/rails/blob/74ba52ec5c/railties/lib/rails/application/finisher.rb#L75)
- [ActiveRecord 配置 eager_load_namespaces 示例](https://github.com/rails/rails/blob/74ba52ec5c/activerecord/lib/active_record/railtie.rb#L41)
