---
title:  'Proxy in CentOS 7'
tags:   [CentOS, Linux, Shadowsocks]
---

As we know, in China, we maybe need to use some tools to acquire better knowledge. In
this acticle, I will introduct the use of two tools, the one tool Shadowsocks
is for the world network permission and the another tool Proxychains is
for proxy in shells, enjoy it please!

## Shadowsocks

### Install

```shell
sudo yum install -y libsodium python-pip
sudo pip install shadowsocks
```

### Configure

```
sudo vi /etc/shadowsocks.json

# Something like this
{
    "server":"服务器地址",
    "server_port":服务器端口号,
    "local_address": "127.0.0.1",
    "local_port":1080,
    "password":"密码",
    "timeout":300,
    "method":"加密方式",
    "fast_open": true,
    "workers": 1
}
```

### Usage

```
sudo sslocal -c /etc/shadowsocks.json -d start
sudo sslocal -c /etc/shadowsocks.json -d stop
```

## Proxychains

### Install

```
cd ~
git clone https://github.com/rofl0r/proxychains-ng.git 
cd proxychains-ng 
./configure && make && sudo make install  
```
### Configure

```
make install-config
vi /usr/local/etc/proxychains.conf
# Notice the line 
# socks5 127.0.0.1 xxxx
```

### Usage

```
sudo mv ./proxychains4 /usr/bin/
proxychains4 git pull
```


