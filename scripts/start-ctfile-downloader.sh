#!/bin/sh
set -e

# 兼容配置：
# 1. 如果设置了 SESSIONS 且未设置 TOKENS/REFRESH_TOKENS，启用 v1 开放接口会员模式
# 2. 否则默认启用 v4 官方客户端免会员模式，支持扫码登录与多账号自动轮询刷新
if [ -n "$SESSIONS" ] && [ -z "$TOKENS" ] && [ -z "$REFRESH_TOKENS" ]; then
	export CTFILE_API_MODE="v1"
else
	export CTFILE_API_MODE="${CTFILE_API_MODE:-v4}"
fi

# 启动服务
exec npm run start
