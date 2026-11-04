#!/bin/sh
set -e

# 城通已经停用旧的 p2 token，现在需要 REST API v1 的 session。
# 兼容旧配置名：如果只设置了 TOKENS，就把它当作 SESSIONS 使用。
if [ -z "$SESSIONS" ] && [ -n "$TOKENS" ]; then
	export SESSIONS="$TOKENS"
fi

# 启动服务
exec npm run start
