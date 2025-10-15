# 使用此docker镜像可以搭建自己的城通网盘解析api服务器和面板

参见[ctfile-downloader](https://github.com/Nekohy/ctfile-downloader)项目

# 使用方法

## docker-compose.yml

```
services:
  ctfile:
    image: ericwang2006/ctfile-services
    container_name: ctfile
    ports:
      - "3000:3000"
      - "8787:8787"
    env_file:
      - .env
    restart: unless-stopped

```

## .env

```
NEXT_PUBLIC_API_URL=http://localhost:8787
PASSWORD=123456
TOKENS=406eed8862e147ddab186609907999606f030d979edc4205b04dc7c3990474a4
```

## token获取方法

```
curl -X POST 'https://rest.ctfile.com/p2/user/auth/login' -H 'User-Agent: okhttp/4.9.2' -H 'Content-Type: application/json' -d '{
  "token": null,
  "username": "邮箱",
  "password": "密码",
  "app_version": "3.7.6"
}' -k
```

多个token在环境变量中用逗号隔开

## 解析面板地址 http://localhost:3000
