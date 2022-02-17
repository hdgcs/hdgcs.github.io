---
title:  'Postman 使用脚本加密请求参数'
tags:   [Postman, JavaScript, API]
cover-img: /assets/img/postman.jpg
---

上一篇讲到了 [Postman 使用脚本添加 BA 认证](17-add-ba-authentication-by-script-in-postman)，
这里同样使用 Postman 预脚本功能，完成对请求体加密的功能。

HTTP请求参数一般是明文传输，并指定与内容对应的 Content-Type，加密的事应该由 SSL/TLS 协议完成的，
但是国内许多服务商因为没有普及 HTTPS 协议，因此对于敏感参数的传递会做加密处理，
比如美团开放平台对于敏感数据，就要求供应商使用密钥进行对称加解密处理。

## 实现

因为最终请求体是密文，且有可能出现换行符，因此这里我们用 Raw Body 的参数格式，使用 Postman 的变量占位，
后面再预脚本中设置值

![Postman Raw Body](/assets/img/2018-09-10 10.22.57.png)

现在我们的参数定义移到了 Pre-request script 中定义（json 变量），然后用与服务端约定好的密钥对参数做加密处理，
这里我们加密算法使用的是 AES-ECB 对称加密：

![Postman Encrypt Script](/assets/img/2018-09-10 10.25.11.png)

```js
var json = {
	"data": [
		{
			"secret_data1": "data1_value",
			"secret_data2": "data2_value"
		}
	]
};
var jsonStr = JSON.stringify(json);
var secret = 'my_secret';
var encryptedBody = CryptoJS.AES.encrypt(jsonStr, CryptoJS.enc.Utf8.parse(secret), { mode: CryptoJS.mode.ECB });
postman.setEnvironmentVariable('encryptedBody', encryptedBody);

```

最后在服务端使用同样的密钥对参数进行解密即可。

需要注意的是，因为密文无法传递有效的 Content-Type，此参数类型需要提前双方协商好，
比如上面我们用的就是 JSON，后端解密后按照 JSON 格式使用即可
