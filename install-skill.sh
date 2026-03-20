#!/bin/bash
# install-skill.sh - 通用技能安装脚本

set -e

SKILL_NAME=${1:-skill00}
SKILL_SOURCE_DIR=${2:-./skill00}

if [ ! -d "$SKILL_SOURCE_DIR" ]; then
    echo "❌ 错误：找不到技能目录 $SKILL_SOURCE_DIR"
    echo "用法：./install-skill.sh <技能名称> <技能源目录>"
    echo "示例：./install-skill.sh jira-diagnosis ./conversation-diagnosis-jira"
    exit 1
fi

echo "🔧 开始安装技能：$SKILL_NAME"
echo "📂 源目录：$SKILL_SOURCE_DIR"

# 检测 docker compose 命令的可用形式
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "❌ 错误：找不到 docker-compose 或 docker compose 命令"
    echo "请确保已安装 Docker Compose"
    exit 1
fi

# 确保 installer 容器运行中
if ! docker ps | grep -q openclaw-installer; then
    echo "📦 启动 installer 容器..."
    $DOCKER_COMPOSE_CMD --profile tools up -d openclaw-installer
    sleep 2
fi

# 清理容器内的临时目录
echo "🧹 清理临时文件..."
docker exec openclaw-installer bash -c "rm -rf /tmp/$SKILL_NAME /tmp/$(basename "$SKILL_SOURCE_DIR")"

# 使用 tar 打包并传输（排除不需要的文件）
echo "📦 打包并上传技能文件..."
tar --exclude='node_modules' \
    --exclude='.git' \
    --exclude='*.tar.gz' \
    --exclude='tmp' \
    --exclude='*.log' \
    -czf - -C "$(dirname "$SKILL_SOURCE_DIR")" "$(basename "$SKILL_SOURCE_DIR")" | \
docker exec -i openclaw-installer tar -xzf - -C /tmp/

# 在容器内安装依赖并部署
echo "🚀 安装 npm 依赖并部署..."

# 创建容器内执行的脚本内容
INNER_SCRIPT_CONTENT=$(cat << 'INNER_SCRIPT'
#!/bin/bash
set -e

SKILL_NAME="$1"
SKILL_TMP="$2"
SKILL_DEST="/home/node/.openclaw/workspace/skills/${SKILL_NAME}"

# 创建目标目录
mkdir -p /home/node/.openclaw/workspace/skills

# 删除旧的技能目录
rm -rf "${SKILL_DEST}"

# 复制新技能
cp -r "${SKILL_TMP}" "${SKILL_DEST}"

# 进入技能目录
cd "${SKILL_DEST}"

# 验证 package.json 存在
if [ ! -f "package.json" ]; then
    echo "❌ 错误：技能目录中缺少 package.json"
    ls -la
    exit 1
fi

echo "当前目录：$(pwd)"
echo "文件列表:"
ls -la

# 清理可能存在的损坏 node_modules
if [ -d "node_modules" ]; then
    echo "🧹 清理旧的 node_modules..."
    rm -rf node_modules
fi

# 安装依赖
echo "正在安装依赖..."
npm install --omit=dev

# 设置权限
chown -R node:node /home/node/.openclaw/workspace/skills

echo "✅ 技能安装成功"
INNER_SCRIPT
)

# 将脚本上传到容器并执行
echo "$INNER_SCRIPT_CONTENT" | docker exec -i openclaw-installer bash -s "$SKILL_NAME" "/tmp/$(basename "$SKILL_SOURCE_DIR")"

echo ""
echo "✅ 技能 $SKILL_NAME 安装完成！"
echo ""
echo "💡 配置说明："
echo "   技能将通过 process.env 读取配置"
echo "   请在 .env 文件中设置 SKILLS_CONFIG_JSON 或在容器中设置环境变量"
echo ""
echo "下一步："
echo "1. 编辑 .env 文件，在 SKILLS_CONFIG_JSON 中添加技能配置"
echo "2. 重启 gateway 容器以加载技能："
echo "   $DOCKER_COMPOSE_CMD restart openclaw-gateway"
echo ""
echo "3. 查看日志验证："
echo "   docker logs -f openclaw-gateway | grep -i $SKILL_NAME"
