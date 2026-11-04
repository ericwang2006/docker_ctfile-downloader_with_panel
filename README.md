# 使用此 docker 镜像可以搭建自己的城通网盘解析 api 服务器和面板

参见 [ctfile-downloader](https://github.com/Nekohy/ctfile-downloader) 项目。

> **2026-11 更新：城通已停用旧的 `/p2` 客户端接口，开放接口 `/v1` 又仅限 VIP 会员。**
> 本项目现已全面升级支持**官方最新客户端 `/v4` REST 协议（免会员，普通免费账号可用）**，并保留 `/v1` 会员模式。
>
> - **普通免费用户**：启动容器后，访问 `http://<IP>:8787/qr`，使用城通网盘手机 App 扫码一次即可完成授权，系统会自动持久化并在后台静默续期。
> - **VIP 会员用户**：仍可在 `SESSIONS` 环境变量中填入后台开放接口 session 使用。

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
      # 免会员模式（默认）：如不想扫码，也可直接在网页端/桌面端复制 refresh_token（多个账号用逗号分隔）
      # REFRESH_TOKENS: "token1,token2"
      # 会员模式（可选）：后台生成的 openapi session
      # SESSIONS: "session1,session2"
    volumes:
      # 挂载保存扫码登录凭据，重启容器后无需重新扫码
      - ./data:/app/data
    restart: unless-stopped
```

## .env

```dotenv
NEXT_PUBLIC_API_URL=http://localhost:8787
PASSWORD=123456
# REFRESH_TOKENS=token1,token2
```

## 账号配置与登录（免会员）

### 推荐：手机 App 扫码登录（一键完成）
1. 启动服务后，用浏览器打开：<http://localhost:8787/qr>
2. 打开手机上的「城通网盘 App」，使用扫一扫扫描屏幕上的二维码
3. 在手机上点击「确认登录」，页面会显示登录成功并自动加入账号池
4. 支持重复扫码添加多个免费账号，系统自动轮询下载防限速！

### 备选：手动复制 Token
1. 在浏览器登录城通网盘（<https://pan.ctfile.com>）
2. 按 F12 打开开发者工具 -> Application -> Session Storage，找到 `refresh_token`
3. 将其填入环境变量 `REFRESH_TOKENS`（多个用逗号分隔）

---

## VIP 会员模式（可选）

如拥有城通 VIP 会员：
1. 登录城通网盘后台进入「开放接口登录密钥管理」
2. 生成 session 并配置到环境变量 `SESSIONS`，系统将自动使用 v1 开放接口。

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
