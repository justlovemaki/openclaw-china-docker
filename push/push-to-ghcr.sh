#!/bin/bash

#2. push-to-ghcr.sh - 推送到 GitHub Container Registry
 #功能：将构建好的 Docker 镜像推送到 GitHub Container Registry (GHCR)（https://ghcr.io）
 #使用场景：
 #与 GitHub 项目深度集成
 #更好的权限控制（私有仓库镜像）
 #免费的私有镜像存储
 #适合企业项目和需要访问控制的场景
# 推送镜像到 GitHub Container Registry (ghcr.io)
# 使用方法: ./push-to-ghcr.sh [版本号]
# 示例: ./push-to-ghcr.sh 1.0.0

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 读取版本号
if [ -f "version.txt" ]; then
    VERSION=$(cat version.txt | tr -d '[:space:]')
else
    echo -e "${RED}错误: version.txt 文件不存在${NC}"
    exit 1
fi

# 如果提供了参数，使用参数作为版本号
if [ ! -z "$1" ]; then
    VERSION=$1
fi

echo -e "${GREEN}=== 推送镜像到 GitHub Container Registry ===${NC}"
echo -e "${YELLOW}版本号: ${VERSION}${NC}"

# 检查是否已登录 ghcr.io
echo -e "${YELLOW}检查 ghcr.io 登录状态...${NC}"
if ! docker info 2>/dev/null | grep -q "ghcr.io"; then
    echo -e "${YELLOW}请先登录 ghcr.io:${NC}"
    echo -e "${YELLOW}docker login ghcr.io -u <GITHUB_USERNAME> -p <GITHUB_TOKEN>${NC}"
    read -p "是否现在登录? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "请输入 GitHub 用户名: " GITHUB_USERNAME
        read -sp "请输入 GitHub Token (PAT): " GITHUB_TOKEN
        echo
        echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
    else
        echo -e "${RED}取消推送${NC}"
        exit 1
    fi
fi

# 获取 GitHub 用户名和仓库名
read -p "请输入 GitHub 用户名 [justlovemaki]: " GITHUB_USERNAME
GITHUB_USERNAME=${GITHUB_USERNAME:-justlovemaki}

read -p "请输入仓库名 [openclaw-docker-cn-im]: " REPO_NAME
REPO_NAME=${REPO_NAME:-openclaw-docker-cn-im}

# 清理输入并转换为小写（ghcr.io 要求小写）
GITHUB_USERNAME_LOWER=$(echo "$GITHUB_USERNAME" | xargs | tr 'A-Z' 'a-z')
REPO_NAME_LOWER=$(echo "$REPO_NAME" | xargs | tr 'A-Z' 'a-z')

# 镜像名称
IMAGE_NAME="ghcr.io/${GITHUB_USERNAME_LOWER}/${REPO_NAME_LOWER}"

echo -e "${YELLOW}镜像名称: ${IMAGE_NAME}${NC}"

# 询问是否需要构建镜像
read -p "是否需要构建镜像? (y/n，默认 n): " BUILD_IMAGE
BUILD_IMAGE=$(echo "$BUILD_IMAGE" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

if [ "$BUILD_IMAGE" = "y" ] || [ "$BUILD_IMAGE" = "yes" ]; then
    # 构建镜像
    echo -e "${GREEN}开始构建镜像...${NC}"
    docker build -t "${IMAGE_NAME}:${VERSION}" -t "${IMAGE_NAME}:latest" .
else
    # 询问本地镜像名称
    read -p "请输入本地镜像名称 [openclaw:local]: " LOCAL_IMAGE
    LOCAL_IMAGE=${LOCAL_IMAGE:-openclaw:local}
    # 使用 xargs 移除首尾空格
    LOCAL_IMAGE=$(echo "$LOCAL_IMAGE" | xargs)
    
    # 检查本地镜像是否存在
    if ! docker image inspect "$LOCAL_IMAGE" > /dev/null 2>&1; then
        echo -e "${RED}错误: 本地镜像 ${LOCAL_IMAGE} 不存在${NC}"
        echo -e "${YELLOW}可用的镜像列表:${NC}"
        docker images
        exit 1
    fi
    
    # 打标签
    echo -e "${GREEN}为本地镜像打标签...${NC}"
    docker tag "$LOCAL_IMAGE" "${IMAGE_NAME}:${VERSION}"
    docker tag "$LOCAL_IMAGE" "${IMAGE_NAME}:latest"
fi

# 推送镜像
echo -e "${GREEN}推送版本标签: ${VERSION}${NC}"
docker push "${IMAGE_NAME}:${VERSION}"

echo -e "${GREEN}推送 latest 标签${NC}"
docker push "${IMAGE_NAME}:latest"

echo -e "${GREEN}=== 推送完成 ===${NC}"
echo -e "${GREEN}镜像地址:${NC}"
echo -e "  ${IMAGE_NAME}:${VERSION}"
echo -e "  ${IMAGE_NAME}:latest"
echo -e "${GREEN}拉取命令:${NC}"
echo -e "  docker pull ${IMAGE_NAME}:${VERSION}"
echo -e "  docker pull ${IMAGE_NAME}:latest"
