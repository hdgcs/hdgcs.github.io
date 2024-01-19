---
title:  '在 El Capitan 中使用 Dnsmasq'
tags:   [macOS, DNS]
---

毕设有个需求，是解析某个域名的所有子域名到本地。这个需求按理来说不难，实质上是需要一个增强版的 hosts 文件，进一步分析，可以找一个 dns 代理工具来解决，通过搜索找到了 Dnsmasq。但这篇文章的出现是因为大多数教程操作都没有提到一点，使得原本简单的工具使用却占用了我挺多时间！

## 具体实现和注意点

### 1. 下载安装工具

下载安装步骤因为有了 [Homebrew](https://brew.sh/) 神器，变得轻而易举：

```shell
brew install dnsmasq
```

最后安装完后，会得到类似工具提示：

```shell
Installed successful.

To configure dnsmasq, copy the example configuration to /usr/local/etc/dnsmasq.conf
and edit to taste.

  cp /usr/local/opt/dnsmasq/dnsmasq.conf.example /usr/local/etc/dnsmasq.conf

To have launchd start dnsmasq now and restart at startup:
  sudo brew services start dnsmasq
```

### 2. 配置使用

该软件配置以及使用根据安装完后的提示，即能简单完成：

先拷贝事例文件：

```shell
cp /usr/local/opt/dnsmasq/dnsmasq.conf.example /usr/local/etc/dnsmasq.conf
```

然后在 dnsmasq.conf
根据提示添加解析后就能完事了，但是这里有个需要注意的地方：

打开 /usr/local/etc/dnsmasq.conf，参照事例，添加类似解析行:

```shell
echo 'address=/dev/127.0.0.1' >> /usr/local/etc/dnsmasq.conf
```

这里解释一下，该行命令的作用是后缀域名解析到 127.0.0.1 ip，即类似 a.dev,
demo.domain.dev 都会被解析到了 127.0.0.1 这个 ip
下，这里即可以实现所有子域名解析本地这个需求。

但是需要注意的地方是本地的网络环境中 dns
设置一般不会有本地服务器，而是一般的 114.114.114.114 或着其他运营商的
dns 服务器，因此我们需要在正常的 dns
服务器前加上一会儿我们即将启动的本地 dns 服务器（这里用 127.0.0.1 即可, 这个可以理解为你 dnsmasq 工具跑的地址）

这步具体操作为：

打开系统设置->网络设置->高级设置->DNS设置，在第一项设置或补充一个本地服务器
127.0.0.1

最后根据安装软件时给出的提示启动工具即可：

```shell
sudo brew services start dnsmasq

# 该命令还会设置开机启动该工具,
如果你只是临时用一下，可以更换执行一下命令
# sudo brew services run dnsmasq
```

### 3. 检测使用

最后如果启动成功且配置没有问题，即可通过 `dig 'a.dev'` 看到 dns
服务器被该工具修改成 127.0.0.1 了。

如果出现问题，首先可以使用命令 `sudo brew services list`
看看工具是否正常启动（绿色正常）,
如果不正常，最大的可能是软件配置文件有问题，可以打开手动编辑对后再试。
