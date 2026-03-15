#!/bin/bash

#1. push-to-dockerhub.sh - 推送到 Docker Hub
 #功能：将构建好的 Docker 镜像推送到 Docker Hub（https://hub.docker.com）
 #使用场景：
 #发布公开镜像，让所有人都可以下载
 #最常用的 Docker 镜像仓库
 #适合开源项目和个人开发者
# 推送镜像到 Docker Hub
# 使用方法: ./push-to-dockerhub.sh [版本号]
# 示例: ./push-to-dockerhub.sh 1.0.0

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

echo -e "${GREEN}=== 推送镜像到 Docker Hub ===${NC}"
echo -e "${YELLOW}版本号: ${VERSION}${NC}"

# 检查是否已登录 Docker Hub
echo -e "${YELLOW}检查 Docker Hub 登录状态...${NC}"
if ! docker info 2>/dev/null | grep -q "Username"; then
    echo -e "${YELLOW}请先登录 Docker Hub:${NC}"
    echo -e "${YELLOW}docker login${NC}"
    read -p "是否现在登录? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker login
    else
        echo -e "${RED}取消推送${NC}"
        exit 1
    fi
fi

# 获取 Docker Hub 用户名和仓库名
read -p "请输入 Docker Hub 用户名 [justlovemaki]: " DOCKERHUB_USERNAME
DOCKERHUB_USERNAME=${DOCKERHUB_USERNAME:-justlovemaki}

read -p "请输入仓库名 [openclaw-docker-cn-im]: " REPO_NAME
REPO_NAME=${REPO_NAME:-openclaw-docker-cn-im}

# 清理输入（使用 xargs 移除首尾空格，然后转换为小写）
DOCKERHUB_USERNAME=$(echo "$DOCKERHUB_USERNAME" | xargs | tr 'A-Z' 'a-z')
REPO_NAME=$(echo "$REPO_NAME" | xargs | tr 'A-Z' 'a-z')

# 镜像名称
IMAGE_NAME="${DOCKERHUB_USERNAME}/${REPO_NAME}"

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
echo -e "${GREEN}Docker Hub 地址:${NC}"
echo -e "  https://hub.docker.com/r/${IMAGE_NAME}"
