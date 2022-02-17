---
title:  'Ruby 中的抽象与接口'
tags:   [Ruby]
---

静态语言中，通过抽象类或接口约束对象的行为经常被使用，并且很容易实现。例如下面是一个 Java 的事例：

```java
Vehical vehicle = new Car();
vehicle.run();
vehicle.charge(distance, hours);

Vehical vehicle = new Bus();
vehicle.run();
vehicle.charge(distance, hours);
```

上面类 `Car` 继承自抽象类 `Vehical`，其中 `#run` 和 `#charge(Float distance, Integer hours)` 都是在 `Vehicle` 类中声明，`Car` 类中实现的方法。

上述操作依赖于 Java 的多态特性（polymorphism）。总结来说，多态性是使用父类数据类型的引用指向子类对象，从而得到一个特殊的对象，该对象遵守父类的方法声明，但用的是子类的方法实现。

那么能不能在没有抽象类和接口概念的动态语言 Ruby 中实现上面的需求呢？是否也能做到统一方法声明、参数约束呢？

## 实现

下面直接上实现，首先定义一个抽象类，再定义一个该抽象类的具体实现

```ruby
# ./vehicles/abstract.rb

module Vehicles
  class Abstract
    def self.impl(mod)
      include mod
    end

    def self.run(**opts); super; end

    def charge(distance, hours); super; end
  end
end
```

```ruby
# ./vehicles/car.rb

module Vehicles
  module Car
    def self.included(mod)
      mod.extend ClassMethods
    end

    module ClassMethods
      def run(**opts)
        puts "Car runing with options: #{opts}."
      end
    end

    def charge(distance, hours)
      charge = distance * hours + 20
      puts "Need pay $#{charge} for car vehicle."
    end
  end
end
```

下面我们对上述操作进行测试一下

```ruby
# ./test.rb

require_relative "vehicles/abstract"
require_relative "vehicles/car"

# Use `Vehicles::Abstract` for all adapeters of vehicles.
vehicle = Vehicles::Abstract.impl(Vehicles::Car)
vehicle.run(color: "red") # => Car runing with options: {:color=>"red"}.
vehicle.new.charge(1.2, 3) # => Need pay $23.6 for car vehicle.
```

## 分析

以上，通过规范统一的抽象类(`Vehicles::Abstract`)入口和使用 `super` 关键字完成了对所有交通工具适配器类的约束，由于入口在抽象类上，
因此会进行参数检查。

在抽象类的实现上，没有使用传统的继承而是模块引入来实现，原因是动态类型的 Ruby 无法做到 Java 上述的多态操作，因此父类对子类难以做到约束，
但模块的动态查找特性，可以实现统一约束。

另外 Ruby 的类方法属于单例类（singleton_class），如果需要也做到被约束，需要像例子一样，使用模块的 `included` 钩子方法。具体原理可以参照我的上一篇文章：
[在类或模块中引入模块的单例类方法](/posts/13-use-singleton-class-method-of-module-in-class-or-module)
