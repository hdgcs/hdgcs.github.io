---
title:  '为 Rails 所有的异步请求添加加载动画'
tags:   [Ruby, Rails]
cover-img: /assets/img/loading.png
---

有一个需求，需要为 Rails 上所有的异步请求添加加载动画（其中 Rails: 5.1.4，jQuery: 3.3.1 ）。具体设计是发出请求后在页面展示正在请求的提示动画，请求结束时隐藏或清除该动画。下面是分情况的实现：

## 禁用 rails-ujs 的情况

如果没有使用 rails-ujs

```js
// application.js
// 确定项目中下面这行已经被移除
//= require rails-ujs
```

那么实现只要添加 JS 事件就行了

```js
$(document).on("ajaxSend", function(){
  // 加载异步请求动画
  $("#loading").show();
})
.on("ajaxComplete", function(){
  // 移除异步请求动画
  $("#loading").hide();
})
```

其中 `#loading` 是布局层面的 html 加载动画模板，每个页面都需要加载，初始化时先隐藏起来。

## 使用 rails-ujs 的情况（仅使用于非动态元素）

如果是按默认的 Rails 配置，项目中需要使用 rails-ujs 时，ujs 提供的异步请求（a 或 button 添加 remote: true 这种）绑定的事件不是原生事件，这时候需要绑定另外一种事件实现

```js
$(document).on("ajax:send", function(){
  // 加载异步请求动画
  $("#loading").show();
})
.on("ajax:complete", function(){
  // 移除异步请求动画
  $("#loading").hide();
})
```

这么处理在一般的情况下没有问题。但是当绑定 send 事件的元素在后端处理中被移除了的时候，后续的事件就无效了。举个例子：

* tests/index.html.erb

```erb
<%= link_to "我会异步删除自己", tests_path, remote: true, method: "delete", id: "test" %>
```

* tests/destroy.js.erb

```js
$("#test").remove();
```

然后点击测试中的链接之后，加载异步请求动画成功，但是请求结束后，动画不会移除。查询资料，说这种[异步请求未完成就改变元素的操作不是好实践](https://github.com/rails/jquery-ujs/issues/223)。但是这种需求在 Rails 还是很普遍啊，例如大家用的 kaminari 分页库的异步加载，就会重新渲染整个列表，也就是触发换页操作的按钮也被移除过了，所以也会出现上述的问题。于是这个问题还是要解决的。

## 使用 rails-ujs 的情况（完整）

具体要解决 Rails 异步请求加载动画的问题，需要使用到 ajaxSend 事件的 [jqXHR](http://devdocs.io/jquery/jquery.ajax#jqXHR) 参数，用这个参数值来绑定后续事件，而不再使用 ajaxComplete 事件。

首先，因为当前的 Rails 版本自带的 rails-ujs 不再依赖 jQuery，因此 ajax:send 事件的参数中，不是 jqXHR，所以首先需要替换回原来的 jquery_ujs 库

* Gemfile

```ruby
gem 'jquery-rails'
```
* application.js

```js
//= require rails-ujs 替换为
//= require jquery_ujs
```

然后用以下的方式绑定事件

```js
$(function() {
  $(document).on("ajax:send", function(event, jqXHR) {
    // 加载异步请求动画
    $("#loading").show();
    jqXHR.always(function() {
      // 移除异步请求动画
      $("#loading").hide();
    });
  });
});
```
还有一个多请求干扰的问题，如：异步删除两个资源，A 的删除动作触发了动画显示，随后 A 的任务完成后动画消失，但 B 如果还在进行中的话，动画实际上已经消失了。 

因此还要添加一个全局计数器

```js
$(function() {
  var ajaxSendCount = 0;
  $(document).on('ajax:send', function(event, jqXHR) {
    if (!$("#loading").is(":visible")) {
      ajaxSendCount = 0;
      // 加载异步请求动画
      $("#loading").show();
    }
    ajaxSendCount++;
    jqXHR.always(function() {
      ajaxSendCount--;
      if (count <= 0) {
        // 清除异步请求动画
        $("#loading").hide();
      }
    });
  });
});
```

现在可以正常的加载异步请求的动画了。
