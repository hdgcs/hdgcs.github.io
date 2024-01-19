---
title:  '使用 Docker 简化部署'
tags:   [Docker, Deploy]
cover-img: /assets/img/docker.png
---

一个产品出现, 从线下开发到线上 internal 服务器最后到 release 服务器, 需要维护许多处的环境. 现在, 我们需要将环境同样抽象出来, 做到本地开发环境变了, 所有线上服务器部署前可以一并自动得到同步.

## Summary

- 构建镜像(在项目中添加Dockerfile)
- 增加部署项目, 例如: app-deploy
- 新建 Docker Hub 账户, 并绑定你的项目地址(GitHub, Bitbucket)

## Quickly realize

### 1. 构建基础镜像

在 [Docker Docs](https://docs.docker.com/) 里学习镜像相关操作, 最后将现有的环境封装到镜像里, 作为你应用的基础镜像, 并最后上传 [Docker Hub](https://hub.docker.com/).

基础镜像的构建可以参照官方 Library. 例如: [Rails 基础镜像](https://github.com/docker-library/rails)

假设我们最后得到基础镜像名为: `pinewong/app-base:latest`.

### 2. 构建部署镜像(将基础镜像与项目源码组合)

在项目主目录添加 Dockerfile 文件, 内容不需要太多, 对于 Rails 应用, 类似这样:

```
FROM pinewong/app-base:latest
MAINTAINER PineWong <pinewong@163.com>

# Bundle
WORKDIR /app
ADD ./Gemfile Gemfile
ADD ./Gemfile.lock Gemfile.lock
RUN bundle install

# Assets
ADD ./app
RUN bundle exec rake assets:precompile RAILS_ENV=production
```

最后在 [Docker Hub](https://hub.docker.com/) 上建立该项目的自动构建关联, 并 Trigger 第一个镜像, 得到部署镜像: `pinewong/app:latest`

![Docker Hub与GitHub项目关联](https://ruby-china-files.b0.upaiyun.com/photo/2016/e036ea82d252b9ad3f06ebcb332d0acd.png!large)

### 3. 新建 app-deploy 项目

目录大概如下:
```shell
|app-deploy/
|__config/               # 配置文件目录
|__|__nginx_site.conf    # nginx site 设置
|__|__...             
|__docker-compose.yml    # 主配置文件
|__app.default.env       # 默认环境变量
|__...
```

docker-compose.yml:

```
version: '2'

services:
  app:
    image: pinewong/app:latest
    command: puma -C config/puma.rb
    depends_on:
      - postgres
    volumes:
      - ./config/nginx_site.conf:/etc/nginx/conf.d/default.conf
  nginx:
    image: nginx:1.11.5
    ports:
      - "80:80"
    depends_on:
      - app
  postgres:
    image: postgres:9.6.1
  # ...
```

该步骤具体配置可以参照社区 [homeland-docker](http://gethomeland.com/install/) 项目.

![homeland-docker install](https://ruby-china-files.b0.upaiyun.com/photo/2016/954e101261c9420664c6fc01ab93f911.png!large)

最后将该项目分发到各服务器和开发人员, 在目录下, 直接: `docker-compose up` 即可运行这个完全封装的应用.

## Advance

### 开发调试

上述步骤简单封装了一个生产环境, 开发环境只需要做一下小修改, 添加一个 docker-compose-dev.yml 文件, 内容大致是去掉 Nginx 这类生产中用的组件, 和替换一些轻量级开发组件: postgres 替换成 sqlite 等, 并在环境变量配置中修改 RAILS_ENV 值, 最后启动应用时添加文件参数 `--file docker-compose-dev.yml`

另外开发需要实时变化源码, 我们直接使用容器的 Volume 功能, 将本地源码目录映射替换容器源码目录:

docker-compose.yml:

```
app:
  volumes:
    - ./app-dir:/app    # app-dir代表本地当前目录下的源码目录，app是上述部署容器所添加源码的目录
```

最后, 当启动容器运行程序后, 你还可以进到容器内部调试:

```shell
docker-compose exec app bash
```

于是, 你就进到了一个应用环境的命令窗口, 这里可以得到虚拟机的体验.

### 对于项目的基础镜像管理

为了更好管理各项目的基础镜像, 这里可以学习官方操作, 在自己的 GitHub 中建立一个 Library 源, 这里有我一些环境的例子: [pinewong/docker-library](https://github.com/pinewong/docker-library)

这样还有一个好处, 可以让基础镜像也使用自动构建服务.

### 简化安装和命令输入

第一次部署项目时具体需要的操作有许多, 例如初始化本地环境变量文件, 数据库初始化, 生成秘钥等等, 这些都可以自动化, 你可以写一个 shell 脚本来做这些, 但更优雅的是学习 [homeland-docker](https://github.com/ruby-china/homeland-docker) 项目, 使用 Makefile 清晰实现封装.

另外如果使用了 Makefile 实现一些封装, 你还可以将开发中的命令简短不少, 例如这样设置 Makefile:

```shell
status:
  @docker-compose ps
stop:
  @docker-compose stop
restart:
  @docker-compose restart $(name)
start:
  @docker-compose up -d
console:
  @docker-compose run app rails console
update:
  @make pull
  @make reload
pull:
  @docker pull pinewong/app:latest
  @docker pull nginx:1.11.5
  @docker pull postgres:9.6.1
reload:
  @docker-compose up -d --force-recreate
# ...
```

之后当你想要进入 Rails 控制台, 可以使用命令`make console` 代替 `docker-compose run app rails console`； 当发布新容器, 需要升级时可以使用`make update`代替
```shell
docker pull pinewong/app:latest
docker pull nginx:1.11.5
docker pull postgres:9.6.1
# ...
docker-compose up -d --force-recreate
```

当然, 你也可以自己在 Makefile 中定义需要的命令.

### 持续部署

上面虽然解决了环境一致的问题, 但部署由于脱离了 Mina 等工具变得麻烦起来, 这时我们可以使用一些 CI 工具来自动完成, 且上述用到的基本都是标准组件, 持续部署将很容易实现.

需要实现持续部署, 首先你要明确整个流程, 如果我们从项目源码提交开始, 大致是这样:

Commit -> Docker Hub 构建部署镜像 -> 各服务器升级程序(pull 新镜像, 重启容器)

如果是基础环境变了, 例如应用从 MySQL 迁移到 Postgres , 环境依赖需要安装 libmysqlclient-dev, 大致流程变成这样:

docker-library更新 -> Docker Hub 重新构建基础镜像 -> Docker Hub 检测到基础镜像改变 -> Docker Hub 重新构建部署镜像 -> 各服务器升级程序(pull 新镜像, 重启容器)

综上, 不管什么触发, 当我们理解了流程, 我们就可以在 CI 工具中新建一个任务. 开心的是, Docker Hub 和 GitHub 已经结合的相当紧密, 一般的触发可以直接在项目设置 webholk 来实现.最后对于 CI 工具, 我使用的是 [Jenkins](https://jenkins.io/)

## Extend

- [Ruby China 社区部署的好例子](https://github.com/ruby-china/homeland-docker)
- [通过容器进行持续部署](http://www.infoq.com/cn/articles/continuous-deployment-containers)
- [生产环境使用 Docker 部署 Rails 应用 Puma 和 Sidekiq](https://ruby-china.org/topics/30098)
- [使用docker快速构建rails开发环境](https://www.embbnux.com/2016/02/21/docker_for_rails_development_with_postgresql_and_redis/)
