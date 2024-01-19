---
title:  'Postman 使用脚本添加 BA 认证'
tags:   [Postman, JavaScript, API]
cover-img: /assets/img/postman.jpg
series: 'Postman 脚本'
---

BA 认证是对 API 请求的一种认证措施。主要是先组合请求的一些参数（例如请求时间、请求方法和请求路径）和双方约定的授权 key，
然后将组合的字符串进行单向加密处理得到一个凭证，然后在头部加上带上该凭证和请求时间访问 API。

之后服务端可以对请求时间做约束（禁止过期请求），并按照同样的算法加密后比对客户端的凭证，一致的话身份认证通过。

这是有别于 token 的另一种 API 认证方式，方便双方不需要用户系统的情况下进行安全的 API 交互。当前有许多服务使用这种方式，例如美团开放平台。

## BA 认证具体实现

这里指定一种 BA 认证的具体逻辑，后面直接在 Postman 中动态实现该逻辑。不同服务商的 BA 认证逻辑有些许不同，稍作调整即可。

首先服务端客户端双方提前约定好授权 key，这里用 partner_id 和 partner_secret 的形式，例如：
```
partnerId     = '10000'
partnerSecret = 'my_secret'
```

然后设定请求时间格式为 GMT 标准格式：
```
requestTime = (new Date()).toGMTString()
```

设定凭证明文组合形式为：
```
signature = requestMethod + ' ' + requestPath + '\n' + requestTime
```

加密算法选用 HMAC-SHA1 + Base64 编码：
```
encryptedSignature = CryptoJS.HmacSHA1(signature, partnerSecret).toString(CryptoJS.enc.Base64);
```

根据 partnerId 和 encryptedSignature 生成证明：
```
var authorization = partner_id + ':' + encrypted_signature;
```

最终我们只要根据以上内容生成两个信息 requestTime 和 authorization 添加到每个请求上就行。

## 使用 Postman 脚本功能的代码完整实现

Postman 有请求预脚本的功能 Pre-request Script，在请求主页 Headers 和 Body 那一栏中
> 如果要给一整个文件夹的请求都加上该脚本功能（大多数情况都是这样），可以在文件夹右边详情里的编辑中处理，那里也有一个预脚本功能

另外 Postman 的预脚本功能使用的 JS 库是标准 JS 库的子集，
有些无法使用的方法和类可以使用 [Postman Collection SDK](https://www.postmanlabs.com/postman-collection/index.html) 代替。

![Postman Pre-request Script Menu]({{ '/assets/img/2018-09-08 14.14.11.png' | relative_url }})

![Postman Pre-request Script]({{ '/assets/img/2018-09-08 14.14.48.png' | relative_url }})

```js
var partnerId     = '10000';
var partnerSecret = 'my_secret';

var requestMethod = request.method;
var sdk           = require('postman-collection');
var url           = new sdk.Url(request.url);
var requestPath   = url.getPath();
var requestTime   = (new Date()).toGMTString();
// "#{requestMethod} #{requestPath}\n#{requestTime}"
var signature = requestMethod + ' ' + requestPath + '\n' + requestTime;
var encryptedSignature = CryptoJS.HmacSHA1(signature, partnerSecret).toString(CryptoJS.enc.Base64);
// "#{partnerId}:#{encryptedSignature}"
var authorization = partnerId + ':' + encryptedSignature;

postman.setEnvironmentVariable('Authorization', authorization);
postman.setEnvironmentVariable('Time', requestTime);
```

最后将上述 Postman 设置的两个变量 `Authorization` 和 `Time` 添入 Postman 的头部中就行。

![Postman Headers Settings](/assets/img/2018-09-08 14.15.46.png)
