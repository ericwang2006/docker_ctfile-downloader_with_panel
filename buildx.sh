#!/bin/sh
# 按架构构建并推送多架构镜像，最后只创建 latest 标签。
# 使用前先执行 docker login，并确保 buildx 已安装 QEMU binfmt。
set -eu

IMAGE=ericwang2006/ctfile-services
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
DIGESTS=""

build() {
	platform=$1
	node_image=$2
	name=$3
	meta="$TMPDIR/$name.json"

	echo "==> Building $platform ($node_image)"
	docker buildx build \
		--platform "$platform" \
		--build-arg "NODE_IMAGE=$node_image" \
		--no-cache \
		--provenance=false \
		--metadata-file "$meta" \
		--output "type=image,name=$IMAGE,push-by-digest=true,name-canonical=true,push=true" \
		.

	digest=$(sed -n 's/.*"containerimage.digest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$meta")
	if [ -z "$digest" ]; then
		echo "failed to read digest for $platform" >&2
		exit 1
	fi
	DIGESTS="$DIGESTS $IMAGE@$digest"
}

build linux/amd64 node:24.22.2-alpine amd64
build linux/arm64/v8 node:24.22.2-alpine arm64
build linux/arm/v7 node:22.23.4-alpine armv7
build linux/arm/v6 node:22.23.4-alpine armv6
build linux/ppc64le node:24.22.2-bookworm-slim ppc64le
build linux/s390x node:24.22.2-alpine s390x

echo "==> Creating multi-arch latest tag"
# shellcheck disable=SC2086
docker buildx imagetools create --tag "$IMAGE:latest" $DIGESTS
