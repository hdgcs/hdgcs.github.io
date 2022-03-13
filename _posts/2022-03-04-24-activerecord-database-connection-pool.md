---
title:  'ActiveRecord 的数据库连接池'
tags:   [ActiveRecord, Database, Rails, Ruby]
series: 'Rails 源码分析'
---

ActiveRecord 的数据库配置中有一项 `pool` 值，默认是 5。这个值有什么用处呢？以及应该怎么配置？另外你是不是遇到过 `ActiveRecord::ConnectionTimeoutError` 异常？本文会带你彻底搞懂这些问题。

## 配置作用以及如何配置

先说答案，这个值的作用是设置连接池容量（也就是限制应用使用的最大数据库连接数）。配置合理值应该等于你应用最大并发数量，而应用最大的并发数量等于 “进程里配置的最大线程数” 加上 “多线程代码的最大并发数”。

这样描述比较生硬，我举个例子，比如你的应用(例如 puma)配置为：

```
workers 4
threads 1, 16
```

Sidekiq 配置为：

```
concurrency 24
```

应用代码里有并发代码：

```ruby
# 下面 10 只是举例，具体你需要大概估量一下，你应用里多线程代码的最大并发数
10.times do
  Thread.new { xxx }
end
```

那么 `pool` 最终配置应该是：[16, 24].max + 10 = 34。其中应用配置里的 `workers` 属于进程，是独立的连接池，是不用管的。

继续深入，如果我不配置相等，而是配置更大的值可以吗？

这个问题可以这么思考，如果你是为了预留后面应用可能出现更大的并发代码（比如上面又出现了比上面 10 更大的情况），那么你可以先预设个更大的配置，这是没问题的；

如果你是想着我数据库配置强，设个更大的数，性能应该会有提升吧，那就想错了，具体可以看下面的 ActiveRecord 对数据库连接池的源码分析。

## ActiveRecord 对数据库连接池的源码分析

下面是精简的处理过程源码，主要解释都写在代码里面。另外最后参考里会给出源码链接。

```ruby
def connection
  # 如果当前线程没有连接，则请求一个（可能是创建，也可能是在空闲连接里面找一个）
  @thread_cached_conns[connection_cache_key(current_thread)] ||= checkout
end

def checkout(checkout_timeout = @checkout_timeout)
  checkout_and_verify(acquire_connection(checkout_timeout))
end

def acquire_connection(checkout_timeout)
  # 先看可用连接里有没，没有的话就执行创建一个新的，创建新的连接会验证总数量（这个就是本文所讲的 `pool` 配置）
  if conn = @available.poll || try_to_checkout_new_connection
    conn
  # 连接总数量验证失败，即连接池里连接数量已经满了时
  else
    # 尝试回收失活的连接
    reap
    # 这个 `poll` 带了超时参数，比起上面无参数的 `poll` 会多一个超时等待逻辑，
    # 就是这里会抛出开头提到的 `ConnectionTimeoutError` 异常
    @available.poll(checkout_timeout)
  end
end

def try_to_checkout_new_connection
  do_checkout = synchronize do
    if @threads_blocking_new_connections.zero? && (@connections.size + @now_connecting) < @size
      @now_connecting += 1
    end
  end
  # 连接数超了，下面的 if 块不会执行，也就是返回 `nil`
  if do_checkout
    # ...
  end
end

# 我们下面只关注 `timeout` 参数存在的逻辑
def poll(timeout = nil)
  synchronize { internal_poll(timeout) }
end

def internal_poll(timeout)
  no_wait_poll || (timeout && wait_poll(timeout))
end

def wait_poll(timeout)
  @num_waiting += 1

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  elapsed = 0
  loop do
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
      @cond.wait(timeout - elapsed)
    end

    return remove if any?

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    # 这里就是实际抛出异常的代码。超时时间可在应用里配置，配置项为 `checkout_timeout`（代码或文档里可以找到）
    if elapsed >= timeout
      msg = "could not obtain a connection from the pool within %0.3f seconds (waited %0.3f seconds); all pooled connections were in use" %
        [timeout, elapsed]
      raise ConnectionTimeoutError, msg
    end
  end
ensure
  @num_waiting -= 1
end
```

捋清并分析这个核心过程，可以发现连接数配的超过最大并发数，会在连接数已经达到并发数时不会回收而是继续创建新连接。正常来说创建新连接 `do_checkout`性能消耗只会比回收旧连接 `reap` 更高，因此在保证连接数 `pool` 配置够用的情况下，要尽量小，也就是说理论上等于最好了。

## 要注意临时任务

当你要编写一个要操作数据库的 task 大任务时，如果你想利用高并发加快速度，比如你打算起 1000 个线程，那么记得要在任务进程里将 ActiveRecord 的 `pool` 配置成 1000，否则将会产生两种你不希望的情况：

1. 任务执行过程出现 `ActiveRecord::ConnectionTimeoutError` 异常；
2. 任务执行没有异常，但是速度不升反降（出现大量线程等待连接池的消耗）。

实际上这里也是能套用一开始给出的公式的，只是这里 “多线程代码的最大并发数” 是临时的，因此可能会被忽视，忘记同步配置 ActiveRecord 的 `pool`。扩展一下，所有这种临时情况都需要注意这个。

## 参考

- [ActiveRecord ConnectionPool 源码](https://github.com/rails/rails/blob/74ba52ec5c/activerecord/lib/active_record/connection_adapters/abstract/connection_pool.rb)
- [Sidekiq Wiki 的 ConnectionPool 相关](https://github.com/mperham/sidekiq/wiki/Problems-and-Troubleshooting#cannot-get-database-connection-within-500-seconds)
