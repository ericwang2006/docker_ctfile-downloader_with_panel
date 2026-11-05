[![ctfile-services Docker Stars](https://img.shields.io/docker/stars/ericwang2006/ctfile-services.svg)](https://hub.docker.com/r/ericwang2006/ctfile-services/)
[![ctfile-services Docker Pulls](https://img.shields.io/docker/pulls/ericwang2006/ctfile-services.svg)](https://hub.docker.com/r/ericwang2006/ctfile-services/)

# 城通网盘解析 API 服务器 + 面板（Docker）

[Dockerfile](https://github.com/ericwang2006/docker_ctfile-downloader_with_panel)

> **2026-11 更新**
> 城通已停用旧的 `/p2` 客户端接口（返回 `410 请使用新客户端`），开放接口 `/v1` 又仅限 VIP 会员。
> 本镜像已升级为**官方最新客户端 `/v4` REST 协议**，**普通免费账号可用**，同时保留 `/v1` 会员模式。
>
> - **免费账号**：启动后打开 `http://<IP>:8787/qr`，用手机 App 扫码一次，凭据会自动落盘并在后台静默续期。
> - **VIP 会员**：仍可在 `SESSIONS` 环境变量中填写开放接口 session，走 `/v1`。

---

## docker-compose.yml

```yaml
services:
  ctfile:
    image: ericwang2006/ctfile-services
    container_name: ctfile
    ports:
      - "3000:3000"   # 解析面板
      - "8787:8787"   # 解析 API
    environment:
      NEXT_PUBLIC_API_URL: http://localhost:8787
      PASSWORD: "123456"
      # 可选：启动时直接注入 refresh_token，多个用逗号分隔
      # REFRESH_TOKENS: "token1,token2"
      # 可选：VIP 会员的 v1 开放接口 session
      # SESSIONS: "session1,session2"
    volumes:
      # 【必须】持久化登录凭据，否则容器重启后需要重新扫码
      - ./data:/app/data
    restart: unless-stopped
```

> **重要**：数据目录固定为 `/app/data`（`DATA_DIR`）。
> **不要**把卷挂载到 `/app/ctfile-downloader-node`，否则会覆盖程序代码。

## .env

```
NEXT_PUBLIC_API_URL=http://localhost:8787
PASSWORD=123456
# REFRESH_TOKENS=token1,token2
```

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PASSWORD` | 空 | 访问密码。留空表示不校验。自动去除首尾空格与引号 |
| `PORT` | `8787` | 解析 API 端口 |
| `DATA_DIR` | `/app/data` | 数据目录，保存 `.tokens.json` 等凭据 |
| `NEXT_PUBLIC_API_URL` | 自动推断 | 面板调用的 API 地址；留空时按当前访问地址推断 `<host>:8787` |
| `REFRESH_TOKENS` | 空 | 启动时注入的 refresh_token，逗号分隔（别名：`TOKENS`、`WEB_TOKENS`） |
| `SESSIONS` | 空 | VIP 会员的 v1 开放接口 session，逗号分隔 |
| `CTFILE_API_MODE` | `v4` | `v4` = 免费账号（默认）；`v1` = VIP 会员 |
| `CTFILE_CARRIER` | `0` | 下载请求携带的运营商参数 |

---

## 添加账号（免会员，4 种方式任选）

### 方式一：手机 App 扫码（推荐，最简单）

1. 启动服务后，浏览器打开 `http://<IP>:8787/qr`
2. 打开手机「城通网盘 App」，用扫一扫扫描页面上的二维码
3. 在手机上点击「确认登录」，页面提示成功后账号自动加入账号池
4. 可重复扫码添加多个免费账号，系统自动轮询下载以规避单账号限速

### 方式二：扫码页手动粘贴 Token

打开 `http://<IP>:8787/qr`，展开「没有 App？点这里粘贴 refresh_token」，
粘贴 token 后点击「添加账号」。系统会自动校验并加入账号池，**无需重启容器**。

### 方式三：HTTP 接口动态添加（适合脚本 / 自动化）

```bash
# token 字段会自动识别是 refresh_token 还是 access_token
curl -X POST http://localhost:8787/auth/token \
  -H 'Content-Type: application/json' \
  -d '{"token":"你的_refresh_token","username":"备注名"}'

# 也可以显式指定类型
curl -X POST http://localhost:8787/auth/token -d 'refresh_token=xxx'
curl -X POST http://localhost:8787/auth/token -d 'access_token=xxx'

# 查看当前账号列表
curl http://localhost:8787/auth/accounts

# 删除账号（按索引或 id）
curl -X POST http://localhost:8787/auth/accounts/delete -d 'index=0'
```

### 方式四：环境变量注入

1. 浏览器登录城通网盘 <https://pan.ctfile.com>
2. 按 `F12` → Application → Session Storage，复制 `refresh_token` 的值
3. 填入环境变量 `REFRESH_TOKENS`（多个用逗号分隔）后重启容器

> `refresh_token` 在刷新时会被轮换。使用环境变量注入时，轮换后的新 token 会写入
> `/app/data/.tokens.json`，且**优先于**环境变量。因此务必挂载 `/app/data`，
> 否则容器重启后旧 token 已失效，需要重新扫码。

---

## API 使用

### 换取下载直链（302 跳转）

```bash
curl -i "http://<IP>:8787/download?xtlink=<xturl...>&file_id=f1420878136&password=123456"
```

- `xtlink`：分享链接中的 `xturl...` 串（也支持传入完整分享链接，服务端会自动提取）
- `file_id`：文件 ID，**必须带 `f` 前缀**
- `password`：`PASSWORD` 环境变量配置的访问密码
- 成功时返回 `302`，`Location` 即真实直链，可直接交给 aria2 下载：

```bash
aria2c "$(curl -s -o /dev/null -w '%{redirect_url}' \
  'http://<IP>:8787/download?xtlink=<xturl...>&file_id=f1420878136&password=123456')"
```

### 获取文件列表 / 下载信息

```bash
curl "http://<IP>:8787/download_info?xtlink=<xturl...>&password=123456"
curl "http://<IP>:8787/download_info?xtlink=<xturl...>&file_id=f1420878136&download=true&password=123456"
```

### 校验访问密码

```bash
curl "http://<IP>:8787/login?password=123456"   # 返回 true / false
```

### 其他页面

| 路径 | 用途 |
| --- | --- |
| `/meow` | 存活探针（返回 `Meow!`） |
| `/config` | 查看当前运行配置（不含敏感信息） |
| `/qr`、`/login/qr` | 扫码登录 / 手动添加 Token 页面 |
| `/auth/accounts` | 账号池列表（JSON） |

---

## VIP 会员模式（可选）

如拥有城通 VIP 会员：

1. 登录城通网盘后台，进入「开放接口登录密钥管理」
2. 生成 session，配置到环境变量 `SESSIONS`（多个逗号分隔）
3. 设置 `CTFILE_API_MODE=v1` 后重启容器

---

## 构建与运行

```bash
docker build -t ctfile-services .
bash run.sh
```

`Dockerfile` 会从 GitHub clone 以下两个仓库，因此修改代码后需先 push：

- `ericwang2006/ctfile-downloader-node`
- `ericwang2006/ctfile-downloader-panel`

### 快速启动

```bash
docker run -d --name ctfile \
  -p 8787:8787 -p 3000:3000 \
  -e PASSWORD=123456 \
  -v ./data:/app/data \
  --restart unless-stopped \
  ctfile-services:latest
```

## 解析面板

<http://localhost:3000>

面板会自动根据当前访问地址推断 API 地址（`<当前 host>:8787`），
因此通过局域网 IP 或反向代理访问时无需手工修改 `NEXT_PUBLIC_API_URL`。

---

## v4 解析调用链（实测可用）

1. `POST https://api.ctfile.com/v4/public/browser/list` — 浏览分享列表
2. `POST https://api.ctfile.com/v4/public/browser/create-download-auth`
   - 请求：`{ "xtlink": "<xturl...>", "ids": "f1420878136" }`
   - 返回：`data.download_signature`
3. （可选）`POST https://api.ctfile.com/v4/file/browse/download-audit` — 上报审计
4. `POST https://api.ctfile.com/v4/public/browser/fetch-url`
   - 请求：`{ "file_id": "1420878136", "download_sign": "<sig>", "xtlink": "<xturl...>", "carrier": 0 }`
   - 返回：`data.download_url`（真实直链，302 后交给 aria2）

> 换取直链必须用 **`/v4/public/browser/fetch-url`**，
> 用 `/v4/file/browse/fetch-url-direct` 会对分享链接返回 `403 签名验证失败`。

## 常见问题

**Q：登录时提示 `该账号需要使用二维码登录` / `LOGIN_REQUIRE_QRSCAN`？**

这是城通账号级的「登录保护」，与 UA、IP、客户端版本无关。即使密码正确，服务端
也会要求扫码。手机 App 之所以能直接密码登录，是因为它持有本机已登记的设备凭据。

处理方式：

- 用 `/qr` 扫码一次，之后靠 refresh_token 自动续期（推荐）
- 或从已登录设备导出 `refresh_token`，通过 `/auth/token` 导入
- 或在网页端账号安全设置中关闭登录保护（如账号提供该开关）

**Q：重启容器后又要重新扫码？**

没有挂载 `/app/data`。`refresh_token` 轮换后的新值保存在那里，
请务必加上 `-v ./data:/app/data`。

**Q：`/download` 返回 `403 Wrong Password`？**

`PASSWORD` 未正确传入，或请求参数中的密码与容器内配置不一致。
注意 `PASSWORD` 会自动 trim 空格与引号。

**Q：`/download` 返回 `502 No download_url returned`？**

账号 token 已失效。访问 `/auth/accounts` 查看状态，必要时重新扫码或重新导入 token。
