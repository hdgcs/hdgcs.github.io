---
title:  'Nginx 保留端口重定向'
tags:   [Nginx, Deploy]
cover-img: /assets/img/nginx.png
---

Web 应用中，需要重定向时，服务端返回一个 301 或者 302 的响应即可，例如在一个 Rails 应用中重定向到登录页面：

```ruby
unless user_signed_up?
  redirect_to login_path
end
```

此时能根据当前主机和端口，自动返回正确的重定向地址给前端，前端再向服务器发送请求。

但是当部署到服务器，应用通过 socket 方式启动，然后配置 Nginx 绑定端口和域名对外开放访问时，所有的跳转都会丢失端口号，使用默认的80端口跳转。
如果此时你主机配置的不是 80 端口，就会产生问题。

下面是节选的 nginx 和 puma 配置：

```
# Nginx
upstream puma_sample.conf {
  server unix:/opt/rails_app/sample/shared/tmp/sockets/puma.sock fail_timeout=0;
}

server {
  listen 9999;
  root /opt/rails_app/sample/current/public;
  try_files $uri/index.html $uri @puma_sample.conf;

  location @puma_sample.conf {
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $host;
    proxy_redirect off;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header X-Forwarded-Proto http;
    proxy_pass http://puma_sample.conf;
    # limit_req zone=one;
    access_log /opt/rails_app/sample/shared/log/nginx.access.log;
    error_log /opt/rails_app/sample/shared/log/nginx.error.log;
  }
  ...
```

```
# Puma 配置
#!/usr/bin/env puma

directory '/opt/rails_app/sample/current'
rackup "/opt/rails_app/sample/current/config.ru"
stdout_redirect '/opt/rails_app/sample/shared/log/puma_access.log', '/opt/rails_app/sample/shared/log/puma_error.log', true
bind 'unix:///opt/rails_app/sample/shared/tmp/sockets/puma.sock'
```

此时发送重定向请求时，会丢失 9999 端口设置，而使用 80 端口跳转。

## 解决

解决的话，需要修改 Nginx 的主机 header 设置，给主机 header 信息添加当前端口：

```
proxy_set_header Host $host:$server_port; # 保留端口跳转
```

这样修改 Nginx 后，就能响应正常了。
