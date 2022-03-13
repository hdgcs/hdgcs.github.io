---
title:  '后台系统重构 - 菜单同步'
tags:   [Refactor, Menu, Rails, Vue.js]
series: '前后端分离实战'
---

公司决定要使用前后端分离方式，重构一个维护了十余年的后台系统（原来是后端渲染方式）。由于持续过程较长，需要新旧系统并存一段时间。这个并存希望对使用者透明，因此我们把新系统界面结构弄的跟旧系统很相似，且我们要实现两个系统菜单完全一致。

要做到完全一致，首先需要将旧系统菜单抽离出来，改成可配置形式。其次因为新系统是前端渲染形式，所以新系统菜单需要通过 API 获取。接下来详细介绍具体实现的要点，实现代码以框架 Rails 5 和 Vue.js 2 举例，实际上其他框架大同小异。

## 请求路由定义

首先是路由定义。路由定义每个系统单独定义自己的功能，假如现在总共有三个功能，其中一个功能已经重构到了新系统内。

1、旧系统（Rails）还剩下两个路由：

```ruby
# config/routes.rb

Rails.application.routes.draw do
  get "function-A1" => "function_a1#index"
  get "function-A2" => "function_a2#index"
end
```

2、新系统（Vue.js）增加一个路由：

```js
// src/configs/routes.js

const routes = [  
  {
    path: '/function-B1',
    component: () => import('@/pages/function_b1'),
  },
]
```

## 菜单改成可配置化

然后是菜单配置问题。配置形式采用 yaml 格式，使用最简单的树形结构，配置内容尽可能的少。

1、配置菜单：

```yaml
# config/menus.yml

- name: 菜单A
  icon_old: icon-a
  icon_new: mdi-a
  children:
    - name: 菜单A1
      link: /function-A1
    - name: 菜单A2
      link: /function-A2
- name: 菜单B
  icon_old: icon-b
  icon_new: mdi-b
  children:
    - name: 菜单B1
    - link: /frontend/function-B1
# ...
```

这里假定 /frontend 开头的连接，会使用新系统（Vue.js）进行服务（这里需要配置代理和 Nginx，此文先不展开），其他情况使用旧系统（Rails）进行服务。

2、加载菜单配置文件：

```ruby
# config/initializers/config_menus.rb

file_dir = Rails.root.join('config', 'menus.yml')
Rails.configuration.menus = YAML.load_file(file_dir)
# 之后可在程序中这样获取：Rails.configuration.menus
```

（进阶一）其中我们可能要经常要在菜单配置中使用 Rails Routes Helper 方法，可以改用如下加载方式：

```ruby
# config/initializers/config_menus.rb

Rails.configuration.after_initialize do |application|
  # 开发环境此时路由数据依然为空，需要主动 reload
  # https://stackoverflow.com/a/8707687
  application.reload_routes!

  file = File.read(Rails.root.join('config', 'menus.yml'))
  # yaml 配置中，可以用 <%= xxx_path %> 方法
  bind = application.routes.url_helpers.instance_eval { binding }
  application.config.menus = YAML.load(ERB.new(file).result(bind))
end
```

（进阶二）树形结构不好通过子节点取父节点，这里通过程序给菜单自动添加一个 tree_nodes 属性，使得后续用起来更方便：

```ruby
# config/initializers/config_menus.rb

file_dir = Rails.root.join('config', 'menus.yml')
Rails.configuration.menus = YAML.load_file(file_dir)
# 菜单A的 tree_nodes 为: [1], 菜单A1: [1, 1], 菜单A2: [1, 2], 菜单B: [2]
add_tree_nodes = lambda { |menus, parent_tree_nodes = []|
  menus.each_with_index do |menu, index|
    tree_nodes = parent_tree_nodes + [index + 1]
    menu.merge!("tree_nodes" => tree_nodes)
    add_tree_nodes.call(menu['children'], tree_nodes) if menu['children'].present?
  end
}
add_tree_nodes.call(Rails.configuration.menus)
```

## 旧系统菜单渲染

旧系统是后端渲染方式，可以直接取到配置并渲染。渲染采用递归形式渲染，下面是一些核心方法。

1、在布局里渲染菜单：

```ruby
# app/views/layouts/application.html.erb

# 菜单栏
<%= render_menus(Rails.configuration.menus) %>
```

2、菜单渲染核心方法（UI 框架为 Bootstrap 2）：

```ruby
# app/helpers/menus_helper.rb

module MenuHelper
  def render_menus(menus, depth = 1)
    doms = menus.map do |menu|
      if menu['children']
        <<~HTML
          # 这里假设 open 样式会让父菜单打开折叠
          <li class="#{'open' if menu_active?(menu, depth)}">
            <a href="#" class="dropdown-toggle">
              <i class="#{menu['icon_old'] || 'icon-double-angle-right'}"></i>
              <span class="menu-text">#{menu['name']}</span>
              <b class="arrow icon-angle-down"></b>
            </a>
            <ul class="submenu">
              #{render_menus(menu['children'], depth + 1)}
            </ul>
          </li>
        HTML
      else
        <<~HTML
          # 这里假设 active 样式会让子菜单高亮
          <li class="#{'active' if menu_active?(menu, depth)}">
            <a href="#{menu['link']}">
              <i class="#{menu['icon_old'] || 'icon-double-angle-right'}"></i>
              <span class="menu-text">#{menu['name']}</span>
            </a>
          </li>
        HTML
      end
    end
    doms.join.html_safe
  end

  private

  # 这里用到了上面菜单配置进阶二中的 tree_nodes 属性，如果不用，也可以用其他方式解决
  def menu_active?(menu, depth)
    current_active_menu&.dig('tree_nodes')&.first(depth) == menu['tree_nodes']
  end

  # 深度遍历，获取第一个命中的菜单（命中算法这里简单使用当前 url 的 path，实际情况可能更复杂，这里不展开讨论）
  def current_active_menu(menus = nil)
    @current_active_menu ||= begin
      menus ||= Rails.configuration.menus
      menus.each do |menu|
        if menu['children']
          active_menu = current_active_menu(menu['children'])
          return active_menu if active_menu
        elsif request.path == menu['link']
          return menu
        end
      end
      nil
    end
  end
end
```

## 新系统菜单渲染

新系统是前端渲染形式，除了获取菜单数据方式需要通过 API 形式，其他跟上面逻辑大同小异，大部分就是 Ruby 代码改 JS 代码。

1、首先定义后端菜单获取的 API：

```ruby
# app/controllers/api/menus_controller.rb

module Api
  class MenusController < ApplicationController
    def index
      render json: { menus: Rails.configuration.menus }
    end
  end
end
```

2、然后是前端布局中渲染菜单：

```vue
<!-- src/layouts/index.vue -->

<template>
  <Menus :menus="menus" :currentActiveMenu="currentActiveMenu" />
</template>
<script>
import Menus from '@/components/Menus'
export default {
  components: {
    Menus,
  },
  data: function () {
    return {
      menus: [],
      currentActiveMenu: null,
    }
  },
  mounted () {
    axios
      .get('/api/menus.json')
      .then(res => {
        this.menus = res.data.menus
        // 根据当前访问 url，设置匹配到的菜单，后续高亮这个菜单要用
        this.setCurrentActiveMenu(this.menus)
      })
  },
  method: {
    setCurrentActiveMenu (menus) {
      menus.forEach(menu => {
        if (menu.children) {
          const activeMenu = this.setCurrentActiveMenu(menu.children)
          if (activeMenu) { this.currentActiveMenu = activeMenu }
        } else if (location.pathname === menu.link) {
          this.currentActiveMenu = menu
        }
      })
    },
  },
</script>
```

3、最后是完成核心菜单组件（UI 框架为 Vuetify 2）：

```vue
<!-- src/components/Menus.vue -->

<template>
  <v-list>
    <template v-for="menu in menus">
      <v-list-group
        v-if="menu.children"
        :key="menu.name"
        :sub-group="isSubmenu"
        :value="isMenuActive(menu)"
      >
        <template v-slot:activator>
          <v-list-item-icon v-if="!isSubmenu">
            <v-icon v-text="menu.icon_new || 'mdi-notification-clear-all'" />
          </v-list-item-icon>
          <v-list-item-content>
            <v-list-item-title v-text="menu.name" />
          </v-list-item-content>
        </template>
        <Menus :menus="menu.children" :currentActiveMenu="currentActiveMenu" :depth="depth + 1" />
      </v-list-group>
      <v-list-item
        v-else
        :key="menu.name"
        :href="menu.link"
        :class="{ 'v-list-item--active': isMenuActive(menu) }"
      >
        <v-list-item-icon v-if="!isSubmenu">
          <v-icon v-text="menu.icon_new || 'mdi-notification-clear-all'" />
        </v-list-item-icon>
        <v-list-item-content>
          <v-list-item-title v-text="menu.name" />
        </v-list-item-content>
      </v-list-item>
    </template>
  </v-list>
</template>

<script>
  export default {
    name: 'Menus', // 采用递归组件形式，需要配置组件名称
    props: {
      menus: { type: Array, required: true },
      currentActiveMenu: { type: Object },
      depth: { type: Number, default: 1 },
    },
    methods: {
      isMenuActive(menu) {
        if (this.currentActiveMenu) {
          return this.currentActiveMenu.tree_nodes.slice(0, this.depth).join(',') === menu.tree_nodes.join(',')
        } else {
          return false
        }
      },
    },
    computed: {
      isSubmenu () {
        return this.depth !== 1
      },
    },
  }
</script>
```

## 其他

以上是最小核心解决方式，后面要在实际项目中用起来，还要处理菜单是否可见、菜单是否新窗口打开、菜单是否有权限等一系列问题，大部分可以在配置文件中增加配置项解决。

其实将系统菜单配置到 menus.yml 中才是最花时间的，手动整理了 1000 多行 -_-
