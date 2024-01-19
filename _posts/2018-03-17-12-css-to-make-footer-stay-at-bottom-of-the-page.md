---
title:  '使用 CSS 让 footer 固定在页面底部'
tags:   [CSS]
---

我们经常会在页面底部加一个 footer（例如版权声明），当页面内容足够高时，这个 footer 放在内容最下面没什么问题。但是如果内容太少，高度小于可视范围，这时候
footer 的位置就会有些尴尬。我们希望 footer 能在此时，能像 fixed 定位一样，固定在可视页面底部。

## 解决

首先，假设我们的页面有如下布局：

```html
<div class="main"></div>
<div class="footer"></div>
```

通过 CSS 让页面主体部分 main 块最小高度为 100%，此时每个页面不管 main 的高度如何，footer 都是需要滚动后才能看到的：

```css
.main {
  min-height: 100%;
}
```

然后给 main 块底部预留好 footer 块的高度的位置，让 footer 块填充进去就好了：

```css
.main {
  min-height: 100%;
  padding-bottom: 3em; /* 这里的 3em 是 footer 块的高度 */
}
.footer {
  margin-top: -3em;
}
```

现在已经实现当 main 块高度低于可视化高度时，footer 块固定在页面底部了。

我们可以再测试一下 main 块高度很大时，footer 块的情况：

```css
.main {
  min-height: 100%;
  padding-bottom: 3em; /* 这里的 3em 是 footer 块的高度 */
  height: 100em; /* 这里只需要一个超过可视高度的值 */
}
.footer {
  margin-top: -3em;
}
```

此时 footer 块仍然正常的位于 main 下面，完全满足需求。
