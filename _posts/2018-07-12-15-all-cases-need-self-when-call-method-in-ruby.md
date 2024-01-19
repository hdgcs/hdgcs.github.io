---
title:  'Ruby 中调用方法需要 self 的所有情况'
tags:   [Ruby]
---

Ruby 中的对象没有属性的概念，比起一些静态语言（如 Java）少了很多 self 前缀的调用情况。在 Ruby 项目中，为了代码简洁和符合大家习惯，我们应该了解一下
需要 self 的情况有哪些。

总结来说，只有两个情况需要：

* setter 方法
* 与 ruby 关键字同名的方法

## setter 方法

```ruby
class Cat
  attr_accessor :color
  
  def initialize
    self.color = :red
  end
end
```

上面的 self 是不能省略的，因为该语句其实是

```ruby
self.color=(:red)
```

的语法糖，在 Ruby 中被称为 setter 方法。如果你使用完整方法（带括号）调用形式，是可以不用 self 的，但是一旦你使用了上述的语法糖形式，你就必须加上了。
因为没有指定对象的 setter 方法和局部变量的声明与赋值语法一样，Ruby 会优先理解成此处需要声明并赋值一个局部变量。

## 与 ruby 关键字同名的方法

```ruby
class Dog
  def class_name
    self.class.name
  end
end
```

上述的 self 也不能省略，因为此处的方法名 class 跟关键字同名，为了语法解析好过一点（现在的情况是根本跑不过），我们还是乖乖显示加上对象吧。

该类情况除了上述的 class，还会有其他情况，这些情况会跟着 Ruby 语言的迭代和或者自定义方法的添加而不同，因此需要时刻注意，我们能做的就是尽量避免自己添加
和关键字同名的方法。
