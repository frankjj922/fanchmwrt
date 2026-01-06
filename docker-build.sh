#!/bin/bash
# OpenWrt Docker 本地编译脚本 (容器内复制模式)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== OpenWrt Docker 编译 ===${NC}"

if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}错误: Docker 未运行${NC}"
    exit 1
fi

IMAGE="ghcr.io/openwrt/buildbot/buildworker-v3.8.0:v9"
CONTAINER_NAME="openwrt-build"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 清理旧容器
docker rm -f ${CONTAINER_NAME} 2>/dev/null || true

echo -e "${GREEN}[1/5] 拉取镜像...${NC}"
docker pull --platform linux/amd64 ${IMAGE}

echo -e "${GREEN}[2/5] 启动容器...${NC}"
docker run -d --platform linux/amd64 --name ${CONTAINER_NAME} ${IMAGE} tail -f /dev/null

echo -e "${GREEN}[3/5] 复制代码到容器 (排除 .git)...${NC}"
# 使用 tar 排除 .git 目录，避免大文件问题
cd "${PROJECT_DIR}"
tar --exclude='.git' --exclude='feeds' --exclude='bin' --exclude='build_dir' --exclude='staging_dir' --exclude='tmp' -cf - . | \
    docker exec -i ${CONTAINER_NAME} tar -xf - -C /home/buildbot/openwrt/

# 修复权限
docker exec ${CONTAINER_NAME} chown -R buildbot:buildbot /home/buildbot/openwrt

echo -e "${GREEN}[4/5] 更新 feeds 并安装...${NC}"
docker exec -u buildbot ${CONTAINER_NAME} bash -c "
    cd /home/buildbot/openwrt && \
    ./scripts/feeds update -a && \
    ./scripts/feeds install -a
"

echo -e "${GREEN}[5/5] 配置编译...${NC}"
docker exec -u buildbot ${CONTAINER_NAME} bash -c "
    cd /home/buildbot/openwrt && \
    echo 'CONFIG_TARGET_armsr=y' > .config && \
    echo 'CONFIG_TARGET_armsr_armv8=y' >> .config && \
    echo 'CONFIG_TARGET_armsr_armv8_DEVICE_generic=y' >> .config && \
    echo 'CONFIG_TARGET_IMAGES_GZIP=y' >> .config && \
    echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=512' >> .config && \
    make defconfig && \
    echo '=== 配置验证 ===' && \
    grep -E 'CONFIG_TARGET_armsr|CONFIG_TARGET_DEVICE.*DEVICE_generic' .config | head -5
"

echo ""
echo -e "${GREEN}=== 环境准备完成! ===${NC}"
echo ""
echo -e "开始编译（预计 1-3 小时）:"
echo -e "  ${YELLOW}docker exec -u buildbot ${CONTAINER_NAME} bash -c 'cd /home/buildbot/openwrt && make -j\$(nproc) V=s'${NC}"
echo ""
echo -e "进入容器:"
echo -e "  ${YELLOW}docker exec -it -u buildbot ${CONTAINER_NAME} bash${NC}"
echo ""
echo -e "编译完成后复制产物:"
echo -e "  ${YELLOW}docker cp ${CONTAINER_NAME}:/home/buildbot/openwrt/bin ./bin${NC}"
