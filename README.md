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

## 2026-11：接入官方 v4 客户端协议（免会员）
调用链（实测可用）：
1. `POST https://api.ctfile.com/v4/public/browser/list` — 浏览分享列表
2. `POST https://api.ctfile.com/v4/public/browser/create-download-auth`
   - 请求：`{ "xtlink": "<xturl...>", "ids": "f1420878136" }`（`ids` 必须带 `f` 前缀）
   - 返回：`data.download_signature`
3. （可选）`POST https://api.ctfile.com/v4/file/browse/download-audit` — 上报审计
4. `POST https://api.ctfile.com/v4/public/browser/fetch-url`
   - 请求：`{ "file_id": "1420878136", "download_sign": "<sig>", "xtlink": "<xturl...>", "carrier": 0 }`
   - 返回：`data.download_url`（真实直链，302 跳转给 aria2 即可）

> 注意：换取直链的接口是 **`/v4/public/browser/fetch-url`**，
> 而不是 `/v4/file/browse/fetch-url-direct`（后者会对分享链接返回 `403 签名验证失败`）。

### ⚠️ 重要：务必持久化 `/app/data`
`refresh_token` 在刷新时会轮换（服务端 rotate_token），新的 token 会保存到
`/app/data/.tokens.json`。**如果没有把 `/app/data` 挂载出来，容器重启后轮换后的
token 会丢失，而环境变量里的初始 token 已失效，导致需要重新扫码。**
所以请务必加上：`-v ./data:/app/data`。

## 基础修复
- `ctfile-downloader-node/src/index.ts`
  - 支持 v4（免会员）与 v1（会员）双模式
  - 内置 `/qr` 扫码登录页，扫码后自动加入账号池并轮换使用
  - 自动刷新 access_token，并持久化轮换后的 refresh_token
  - `PASSWORD` 自动去除首尾空格与引号
  - 数据目录独立为 `DATA_DIR`（默认 `/app/data`），避免误挂载覆盖代码目录
- `Dockerfile`
  - 使用 `--platform=$BUILDPLATFORM` 交叉编译，修复 `linux/arm/v7` 下 QEMU 导致的
    `futexwakeup returned -38 SIGSEGV` 崩溃
  - 移除在 ARM 上不稳定的 UPX 压缩
  - 固定 `supervisord v0.7.6`、`pnpm@9`
- `ctfile-downloader-panel`
  - 前端自动根据当前访问地址推断 API 地址（`<当前host>:8787`），并给出明确的连接错误提示
