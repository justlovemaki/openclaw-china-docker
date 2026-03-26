# syntax=docker/dockerfile:1.10
# OpenClaw Docker 镜像 - 面向中国 IM 场景
# 构建命令: docker build -t openclaw-cn-im . --secret id=clawhub,src=.clawhub_token

FROM node:22-slim

# =============================================================================
# 环境变量配置
# =============================================================================
ENV BUN_INSTALL="/usr/local" \
    PATH="/usr/local/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# =============================================================================
# Phase 1: 系统层 - 基础依赖（缓存优先级最高，变更最少）
# =============================================================================

# 1.1 配置国内镜像源 + 安装系统依赖
# 合并为单层避免 apt 缓存问题，clean 减小镜像体积
RUN sed -i 's@deb.debian.org@mirrors.aliyun.com@g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's@security.debian.org@mirrors.aliyun.com@g' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        bash ca-certificates chromium curl build-essential ffmpeg \
        fonts-liberation fonts-noto-cjk fonts-noto-color-emoji \
        git gosu jq locales openssh-client procps python3 socat \
        tini unzip pipx python3-venv python3-pip websockify && \
    sed -i 's/^# *en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 1.2 Git 配置（HTTPS 替代 SSH，避免密钥问题）
RUN git config --system url."https://github.com/".insteadOf ssh://git@github.com/

# =============================================================================
# Phase 2: Node 层 - npm 核心工具（变更较少）
# =============================================================================

# 2.1 设置 npm 镜像（中国镜像源）
RUN npm config set registry https://registry.npmmirror.com

# 2.2 全局 npm 工具（OpenClaw 核心依赖）
RUN npm install -g \
        openclaw@latest \
        opencode-ai@latest \
        clawhub \
        playwright \
        playwright-extra \
        puppeteer-extra-plugin-stealth \
        @steipete/bird \
        @tobilu/qmd@1.1.6 && \
    npm cache clean --force

# 2.3 Playwright 浏览器（体积大，独立层便于缓存）
RUN npx playwright install chromium --with-deps && \
    rm -rf /root/.npm /root/.cache /tmp/*

# =============================================================================
# Phase 3: 运行时层 - 其他语言工具（变更较少）
# =============================================================================

# 3.1 Bun 运行时
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash

# 3.2 UV (Python 包管理器) - 使用多阶段构建，更小更快
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# =============================================================================
# Phase 4: 应用层 - OpenClaw 插件与配置（变更较频繁）
# =============================================================================

# 4.1 创建 OpenClaw 目录结构
RUN mkdir -p /home/node/.openclaw/workspace /home/node/.openclaw/extensions && \
    chown -R node:node /home/node

# 切换到 node 用户（避免后续 chown 导致镜像膨胀）
USER node
ENV HOME=/home/node
WORKDIR /home/node

# 4.2 安装 Linuxbrew（Homebrew Linux 版本）
RUN mkdir -p /home/node/.linuxbrew/Homebrew && \
    git clone --depth 1 https://github.com/Homebrew/brew /home/node/.linuxbrew/Homebrew && \
    mkdir -p /home/node/.linuxbrew/bin && \
    ln -s /home/node/.linuxbrew/Homebrew/bin/brew /home/node/.linuxbrew/bin/brew && \
    chown -R node:node /home/node/.linuxbrew && \
    chmod -R g+rwX /home/node/.linuxbrew

# 4.3 安装 OpenClaw 插件（IM 通道 + 扩展）
RUN cd /home/node/.openclaw/extensions && \
    git clone --depth 1 -b v4.17.25 https://github.com/Daiyimo/openclaw-napcat.git napcat && \
    cd napcat && \
    npm install --production && \
    timeout 300 openclaw plugins install -l . || true && \
    cd /home/node/.openclaw/extensions && \
    timeout 300 openclaw plugins install @soimy/dingtalk || true && \
    timeout 300 openclaw plugins install @tencent-connect/openclaw-qqbot@latest || true && \
    timeout 300 openclaw plugins install @sunnoy/wecom || true && \
    mkdir -p /home/node/.openclaw /home/node/.openclaw-seed && \
    find /home/node/.openclaw/extensions -name ".git" -type d -exec rm -rf {} + && \
    mv /home/node/.openclaw/extensions /home/node/.openclaw-seed/ && \
    printf '%s\n' '2026.3.24' > /home/node/.openclaw-seed/extensions/.seed-version && \
    rm -rf /tmp/* /home/node/.npm /home/node/.cache

# =============================================================================
# Phase 5: 工具层 - 全局命令行工具
# =============================================================================

USER root

# 5.1 全局 Node 工具（mcporter, clawhub, agent-browser）
RUN npm install -g mcporter clawhub agent-browser && \
    npm cache clean --force

# 切换回 node 用户
USER node
WORKDIR /home/node/.openclaw/workspace/

# 5.2 配置 mcporter MCP 服务
RUN mcporter config add rednote http://rednote.mcp:18060/mcp && \
    mcporter config add freesearch --command "uvx mcp-server-freesearch --break-system-packages" --env SEARXNG_API_URL="https://searx.bndkt.io"

WORKDIR /home/node/.openclaw/

# =============================================================================
# Phase 6: ClawHub 技能安装（需要认证）
# =============================================================================

# 6.1 ClawHub 登录（使用 BuildKit secrets）
RUN --mount=type=secret,id=clawhub,env=CLAWHUB_TOKEN,required=true \
    clawhub login --token "$CLAWHUB_TOKEN" --no-browser

# 6.2 安装 ClawHub 技能包
RUN clawhub install --force proactive-agent && \
    clawhub install mcporter && \
    clawhub install self-improving && \
    clawhub install --force agent-browser && \
    clawhub install --force browser-use && \
    clawhub install --force evolver && \
    clawhub install --force capability-evolver && \
    clawhub install --force summarize && \
    clawhub install --force humanizer && \
    clawhub install skill-vetter && \
    clawhub install --force clawddocs && \
    clawhub install --force parallel-deep-research && \
    clawhub install --force deep-research-pro && \
    clawhub install agent-builder && \
    clawhub install creativity && \
    clawhub install --force skill-improvement && \
    clawhub install --force skill-refiner && \
    clawhub install --force skill-creator && \
    clawhub install agent && \
    clawhub install --force agent-evaluation && \
    clawhub install --force cron-mastery && \
    clawhub install --force news-summary && \
    clawhub install --force openclaw-subagents && \
    clawhub install --force create-subagent

# 6.3 克隆外部技能仓库
RUN git clone https://github.com/ACautomata/model-guidance /home/node/.openclaw/skills/model-guidance && \
    git clone https://github.com/ACautomata/openclaw-optimizer /home/node/.openclaw/skills/openclaw-optimizer && \
    git clone https://github.com/win4r/openclaw-workspace /home/node/.openclaw/skills/openclaw-workspace

# =============================================================================
# Phase 7: 最终配置
# =============================================================================

WORKDIR /home/node
ENV NODE_OPTIONS="--max-old-space-size=1280"

USER root

# 7.1 复制并配置初始化脚本
COPY ./init.sh /usr/local/bin/init.sh
RUN sed -i 's/\r$//' /usr/local/bin/init.sh && \
    chmod +x /usr/local/bin/init.sh && \
    chown -R node:node /home/node/.openclaw/ /home/node/.npm/

# 7.2 最终环境变量
ENV HOME=/home/node \
    TERM=xterm-256color \
    NODE_PATH=/usr/local/lib/node_modules \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    NODE_ENV=production \
    PATH="/home/node/.linuxbrew/bin:/home/node/.linuxbrew/sbin:/usr/local/lib/node_modules/.bin:${PATH}" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1

# 7.3 暴露端口
EXPOSE 18789 18790

WORKDIR /home/node

# 入口点
ENTRYPOINT ["/bin/bash", "/usr/local/bin/init.sh"]
