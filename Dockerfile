# 运行阶段使用的 Node 基础镜像，由 CI 按目标架构传入：
#   amd64 / arm64 / s390x : node:24.22.2-alpine (Node 24 LTS)
#   arm/v6 / arm/v7       : node:22.23.4-alpine (Node 22 LTS，Node 24 已不提供 32 位 ARM)
#   ppc64le               : node:24.22.2-bookworm-slim (Node 24 LTS，官方无 Alpine ppc64le)
ARG NODE_IMAGE=node:24.22.2-alpine

# ========== 第一阶段：构建阶段 ==========
# 前端/Node 构建产物与 CPU 架构无关，统一在构建机架构上执行，
# 避免在 QEMU 下运行 Next.js SWC（ppc64le/s390x 会崩溃）并大幅提速。
FROM --platform=$BUILDPLATFORM node:24.22.2-alpine AS builder
# 安装编译依赖
RUN apk add --no-cache git ca-certificates build-base python3 make

# 创建工作目录
WORKDIR /app

# 安装 pnpm（固定 9.x，pnpm 10 默认禁止依赖构建脚本，会导致面板安装 sharp 时失败）
RUN npm install -g pnpm@9

# 复制脚本
COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh

# 克隆并构建服务1 - ctfile-downloader-node
# 注意：修复后的源码（REST API v1 + session）需要先 push 到 GitHub。
RUN git clone --depth=1 https://github.com/ericwang2006/ctfile-downloader-node.git /app/ctfile-downloader-node && \
    cd /app/ctfile-downloader-node && \
    npm ci && \
    npm run build && \
    npm prune --production && \
    rm -rf src tsconfig.json README.md .git

# 克隆并构建服务2 - ctfile-downloader-panel
RUN git clone --depth=1 https://github.com/ericwang2006/ctfile-downloader-panel.git /app/ctfile-downloader-panel && \
    cd /app/ctfile-downloader-panel && \
    pnpm install && \
    NEXT_PUBLIC_API_URL=__API_URL_PLACEHOLDER__ npm run build

RUN mv /app/ctfile-downloader-panel/out /app/ && \
    rm -rf /app/ctfile-downloader-panel/ && \
	mv /app/out /app/ctfile-downloader-panel

# ========== go-supervisor 构建阶段 ==========
FROM --platform=$BUILDPLATFORM golang:1.27.3-alpine AS go-builder
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
RUN apk add --no-cache git
WORKDIR /src
# 固定版本，避免 master 分支的 Go 版本要求变化导致构建失败。
RUN git clone --depth=1 --branch v0.7.6 https://github.com/ochinchina/supervisord.git .

RUN GOARM_VAL=""; \
    if [ "$TARGETARCH" = "arm" ]; then \
      GOARM_VAL="${TARGETVARIANT#v}"; \
      [ -z "$GOARM_VAL" ] && GOARM_VAL="7"; \
    fi; \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${GOARM_VAL} \
    go build -tags release -a \
    -ldflags "-s -w -extldflags '-static'" \
    -trimpath \
    -o /out/supervisord .

# ========== http-server 构建阶段 ==========
FROM alpine:3.9 AS http-builder

RUN apk add build-base

# https://sourceforge.net/projects/shttpd/files/shttpd/1.42/
# 静态链接，确保 Alpine(musl) 构建出的二进制也能放进 ppc64le 的 Debian(glibc) 运行阶段。
RUN wget -O ./shttpd-1.42.tar.gz https://github.com/ericwang2006/shttpd/archive/refs/tags/v1.42.tar.gz && \
   tar -zxvf ./shttpd-1.42.tar.gz && \
   cd shttpd-1.42/src && \
   CFLAGS="-O2 -static" LIBS="-lpthread -ldl " make unix

# ========== 第三阶段：运行阶段 ==========
FROM ${NODE_IMAGE}

# 安装依赖（Alpine 用 apk，ppc64le 的 Debian 用 apt）
RUN if command -v apk >/dev/null 2>&1; then \
      apk add --no-cache ca-certificates; \
    elif command -v apt-get >/dev/null 2>&1; then \
      apt-get update && \
      apt-get install -y --no-install-recommends ca-certificates && \
      rm -rf /var/lib/apt/lists/*; \
    fi

# 从 go-builder 阶段复制 go-supervisor 二进制文件
COPY --from=go-builder /out/supervisord /usr/bin/supervisord

# 从 http-builder 阶段复制 shttpd 二进制文件
COPY --from=http-builder /shttpd-1.42/src/shttpd /usr/bin/shttpd

# 创建工作目录
WORKDIR /app

# 设置环境变量
ENV NEXT_PUBLIC_API_URL=http://localhost:8787

# RUN npm install -g http-server

# 从构建阶段复制构建好的文件
COPY --from=builder /app/ /app/

# 复制配置文件
COPY supervisord.conf /etc/supervisord.conf
COPY supervisor/ /etc/supervisor/conf.d/

# 给脚本执行权限与创建数据持久化目录
RUN chmod +x /app/scripts/*.sh && mkdir -p /app/data
ENV DATA_DIR=/app/data

# 暴露端口
EXPOSE 8787 3000

# 启动supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
