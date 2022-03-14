---
title:  '如何用 Ruby 高效处理区间'
tags:   [LeetCode, Red–black tree, Skip list, Ruby]
cover-img: /assets/img/ruby-range.png
---

有个需求，需要使用 Ruby 处理区间，实现以下操作：

```ruby
range_list = RangeList.new # []
range_list.add([1, 5]) # [[1, 5)], all elements: 1, 2, 3, 4
range_list.add([7, 9]) # [[1, 5), [7, 9)]
range_list.remove([4, 8]) # [[1, 4), [8, 9)]
range_list.contains_any?([3, 6]) # true，include any of 3, 4, 5
range_list.contains_all?([3, 6]) # false, include all of 3, 4, 5
range_list.contains?(3) # true
range_list.contains?(6) # false
```

## 数据结构和算法

我们先来确定用哪种数据结构处理，常用的数据结构与相关操作复杂度有：

- 哈希表：查找、插入、删除：O(1)，不支持顺序遍历
- 有序数组：查找：O(logn)，插入、删除：O(n)，支持顺序遍历
- 红黑树：查找、插入、删除：O(logn)，支持顺序遍历
- 跳表：查找、插入、删除：O(logn)，支持顺序遍历

我们的需求需要支持查找、插入、删除和顺序遍历，因此红黑树和跳表综合来说更符合我们的要求。

其中跳表原理和实现都更简单，Redis 的有序集合实现就是用的跳表。而工程里常用的红黑树，应用很广泛，已经有很多现成的库供使用。
对我们需求来说跳表和红黑树两种数据结构都行。

接下来要确定算法逻辑，这个可以直接参考 LeetCode 这题：[729. 我的日程安排表 I](https://leetcode-cn.com/problems/my-calendar-i/)，在核心思路上扩展一下就行。
官方答案里使用了 Java 的 TreeMap 数据类型，TreeMap 就是用红黑树实现的。

## Ruby 实现 - treemap 库

数据结构和算法逻辑都确定了，现在就是要找到 Ruby 的相关库，然后根据算法逻辑具体实现。

首先找到了 [algorithms](https://rubygems.org/gems/algorithms)，这个库实现了常用的数据结构和算法，里面的 `Containers::RBTreeMap` 就是红黑树的实现。不过进一步发现，实现里没有类似 Java 的 `TreeMap#lowerEntry` 方法，这个是找到第一个小于输入节点的方法，我们的算法逻辑中需要。最后放弃了这个库。

然后找到了 [treemap](https://rubygems.org/gems/treemap)，这个库就是仿照 Java 的 TreeMap 实现的，方法上完全符合我们需求，因此使用该库实现了一版，核心代码如下：

```ruby
def add(range)
  # Get real range start.
  start_floor_entry = @treemap.floor_entry(range[0])
  range_start = if !start_floor_entry.nil? && start_floor_entry.value >= range[0]
    start_floor_entry.key
  else
    range[0]
  end

  # Get real range end.
  end_floor_entry = @treemap.floor_entry(range[1])
  range_end = if !end_floor_entry.nil? && end_floor_entry.value >= range[1]
    end_floor_entry.value
  else
    range[1]
  end

  # Insert or replace new range.
  @treemap.put(range_start, range_end)

  # Remove keys between range, exclude start, include end.
  between_maps = @treemap.sub_map(range[0], false, range[1], true)
  between_maps.keys.each { |key| @treemap.remove(key) }
end

def remove(range)
  # Insert end lower entry
  end_lower_entry = @treemap.lower_entry(range[1])
  if !end_lower_entry.nil? && end_lower_entry.value > range[1]
    @treemap.put(range[1], end_lower_entry.value)
  end

  # Relace start lower entry
  start_lower_entry = @treemap.lower_entry(range[0])
  if !start_lower_entry.nil? && start_lower_entry.value > range[0]
    @treemap.put(start_lower_entry.key, range[0])
  end

  # Remove keys between range, include start, exclude end
  between_maps = @treemap.sub_map(range[0], true, range[1], false)
  between_maps.keys.each { |key| @treemap.remove(key) }
end
```

## Ruby 实现 - rbtree 库

通过 treemap 库实现的版本经过性能测试，速度很不理想，还不够符合我们的“高效处理”要求。然后继续找到了这个库：[rbtree](https://rubygems.org/gems/rbtree)。rbtree 使用 C 扩展方式实现的，效率相比 treemap 有很大的提升。且 rbtree 库也有类似的 `upper_bound` 方法实现我们“找到第一个小于输入节点”的需求。

具体实现的话跟上面 treemap 的代码一样，仅仅是库方法用法需要做一些适配更改，例如：

```
TreeMap#floor_entry -> RBTree#upper_bound
TreeMap#put -> RBTree#[]=
TreeMap#sub_map -> RBTree#bound
TreeMap#remove -> RBTree#delete
```

其中 `RBTree` 没有 `TreeMap#lower_entry` 对应的方法，不过只需要修改 `RBTree#upper_bound` 参数就能简单实现：

```
TreeMap#lower_entry(key) -> RBTree#upper_bound(key - 1)
```

## 分离第三方库的适配

通过上面从 treemap 更换到 rbtree 的过程，我们可以发现库的适配实际上应该从我们算法逻辑中分离出去，分成两个模块：算法逻辑和库的适配。
这么操作可以使得抽象接口与逻辑实现分离，后期更换第三方库也不会像之前那样要耦合到算法逻辑里处理。

具体实现的话，可以先构建一个库的适配接口：

```ruby
class AbstractAdapter
  def put(key, value)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def lower_entry(key)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def sub_map(from_key, to_key)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def remove(key)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end
end
```

之后将我们上面的算法逻辑里的方法改成上面抽象出来的方法，之后对于接入一个数据结构库，只需要完成该库对我们接口的适配即可。完整代码可以参考项目的源码。

这方面知识可以参考：

- 设计模式里的适配器模式：[https://refactoringguru.cn/](https://refactoringguru.cn/)
- Rails 源码中对于数据库适配的部分：[https://github.com/rails/rails](https://github.com/rails/rails)

## 最终版本链接

[https://rubygems.org/gems/range_list](https://rubygems.org/gems/range_list)
