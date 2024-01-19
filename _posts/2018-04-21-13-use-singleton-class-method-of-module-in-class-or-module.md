---
title:  '在类或模块中引入模块的单例类方法'
tags:   [Ruby]
---

在 Ruby 中，我们都知道 include 能引入一个模块的方法作为当前类/模块的实例方法，以及 extend 可以引入模块的方法作为当前类/模块的类方法（单例方法）。那么模块中本身的类方法（单例方法）呢？该怎么引入他呢？

首先两种直接引入的方式都是不行的：

```ruby
module M
  def instance_m; end
  def self.class_m; end # 模块中的类方法无法被引入
end

class C
  include M
  extend M
end

C.instance_m #=> nil
C.class_m #=> NoMethodError
```

## 理解

先抛结论：在模块中直接定义的类方法（self.m）是无法被其他类/模块引入使用的。

原因的话，引入（include）做的事是只会操作当前模块的方法（实例方法），而模块的类方法实际上是属于模块的单例类（singleton class）的方法，关于单例类的解释，这个链接里解释的很好：
[What exactly is the singleton class in ruby?](https://stackoverflow.com/questions/212407/what-exactly-is-the-singleton-class-in-ruby)

## 解决

上述结论里特意指出“直接定义”，所以这个问题是可以通过其他方式解决的，而且解决方案被广大库（Rails等）推崇。因此我们以后设计模块的时候也应该考虑该设计。

```ruby
module M
  # 将单例方法换一种方式定义，定义在子模块中，模块名有时也被写作（SingletonMethods）
  module ClassMethods
    def class_m; end
  end

  # 自身用引入该模块的方法为类方法，实现直接定义单例方法相同的效果（self.class_m）
  extend ClassMethods

  # 通过钩子，在其他类/模块引入该模块时，同时引入该模块的类方法（作为操作类/模块的类方法引入）
  def self.included(base)
    base.extend ClassMethods
  end
end
```

之后，只要把原来直接定义的类方法（self.m）都定义到 ClassMethods 子模块中，就行了。

Rails 的 [ActiveSupport::Concern](http://devdocs.io/rails~5.1/activesupport/concern) 对上述的操作进行了一些简单封装，使得操作更加方便。
