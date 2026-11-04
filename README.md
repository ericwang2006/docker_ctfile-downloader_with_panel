# 使用此 docker 镜像可以搭建自己的城通网盘解析 api 服务器和面板

参见 [ctfile-downloader](https://github.com/Nekohy/ctfile-downloader) 项目。

> **2026-11 更新：城通已经停用旧的 `/p2` 客户端接口。**
> 旧接口现在统一返回 `{"code":410,"message":"请使用新客户端"}`，旧的 p2 token 全部失效。
> 本仓库已改为调用新的 REST API v1（`https://rest.ctfile.com/v1`），并使用 `session` 认证。

# 使用方法

## docker-compose.yml

```yaml
services:
  ctfile:
    image: ctfile-services:latest
    container_name: ctfile
    ports:
      - "3000:3000"
      - "8787:8787"
    environment:
      NEXT_PUBLIC_API_URL: http://192.168.2.27:8787
      PASSWORD: "123456"
      # 新接口使用 session，多个账号用逗号分隔
      SESSIONS: "session1,session2,session3"
    restart: unless-stopped
```

## .env

```dotenv
NEXT_PUBLIC_API_URL=http://localhost:8787
PASSWORD=123456
SESSIONS=session1,session2,session3
```

旧变量名 `TOKENS` 仍然兼容，但里面必须填新的 session，不能再填旧的 p2 token。

## session 获取方法

旧的 `/p2/user/auth/login` 接口已经失效，无法再用邮箱密码自动换 token。现在需要：

1. 用浏览器登录城通网盘：<https://www.ctfile.com/>
2. 进入后台的「开放接口登录密钥管理」页面
3. 生成或复制你的 session token
4. 把 session 填入 `SESSIONS` / `TOKENS` 环境变量，多个账号用逗号分隔

每个 session 对应一个下载线程/账号，配置多个可以继续绕过单账号的下载限制。

## 构建与运行

```bash
docker build -t ctfile-services .
bash run.sh
```

`Dockerfile` 会从 GitHub clone `ericwang2006/ctfile-downloader-node` 和 `ericwang2006/ctfile-downloader-panel`。请先把修复后的 Node 源码 push 到 GitHub，否则构建出来的镜像仍然会包含旧的 `/p2` 代码。

## 解析面板地址

<http://localhost:3000>

# 本次修复内容

- `ctfile-downloader-node/src/index.ts`
  - `/p2/browser/file/list` → `/v1/browser/file/list`
  - `/p2/browser/file/fetch_url` → `/v1/browser/file/fetch_url`
  - `token` → `session`
  - 正确处理 v1 的错误码（v1 出错时 HTTP 状态仍为 200，错误在 `code` 字段）
  - 支持 v1 列表接口的 `start` 分页
  - 上游返回 401/403/410 时，API 返回明确的 JSON 错误，而不是只抛 `Upstream error: 410`
  - 修复 `.state.json` 中下标超出 session 数量时取到 `undefined` 的问题
- `Dockerfile`
  - 恢复从 GitHub clone `ctfile-downloader-node`，并使用 `npm ci` 构建（仓库使用 `package-lock.json`）
  - Go 构建镜像升级到 `golang:1.27.3-alpine`，并固定 `supervisord v0.7.6`（上游 `go.work` 已要求 Go >= 1.27.3）
  - 固定 `pnpm@9`（pnpm 10 默认禁止依赖构建脚本，会导致面板安装 `sharp` 时失败）
- 新增 `.dockerignore`
- `scripts/start-ctfile-downloader.sh`
  - 兼容旧变量 `TOKENS`（自动当作 `SESSIONS`）
- `supervisor/*.conf`
  - 移除 `environment=...%(ENV_...)s` 引用，子进程改为直接继承容器环境变量，避免 go-supervisord 因变量未设置而跳过 program
