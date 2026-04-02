# syntax=docker/dockerfile:1.10
# OpenClaw Docker 镜像 - 面向中国 IM 场景
# 构建命令: docker build -t openclaw-cn-im . --secret id=clawhub,src=.clawhub_token

FROM node:22-slim

# 从 Python 官方镜像拷贝 Python 3.12 (确保使用与 node 镜像一致的 Debian Bookworm 版本)
COPY --from=python:3.12-slim-bookworm /usr/local /usr/local

# 设置工作目录
WORKDIR /app

# 设置环境变量
ENV BUN_INSTALL="/usr/local" \
    PATH="/usr/local/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive

# =============================================================================
# Phase 1: 系统层 - 基础依赖（缓存优先级最高，变更最少）
# =============================================================================

# 1.1 配置国内镜像源 + 安装系统依赖
# 合并为单层避免 apt 缓存问题，clean 减小镜像体积
RUN sed -i 's@deb.debian.org@mirrors.aliyun.com@g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's@security.debian.org@mirrors.aliyun.com@g' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        chromium \
        curl \
        docker.io \
        build-essential \
        ffmpeg \
        fonts-liberation \
        fonts-noto-cjk \
        fonts-noto-color-emoji \
        git \
        gosu \
        jq \
        locales \
        openssh-client \
        procps \
        socat \
        tini \
        unzip && \
    sed -i 's/^# *en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale && \
    # 配置 git 使用 HTTPS 替代 SSH
    git config --system url."https://github.com/".insteadOf ssh://git@github.com/ && \
    # 设置 npm 镜像并安装全局包
    npm config set registry https://registry.npmmirror.com && \
    npm install -g openclaw@2026.3.31 opencode-ai@latest clawhub playwright playwright-extra puppeteer-extra-plugin-stealth @steipete/bird && \
    # 安装 bun、uv 和 qmd
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    # 建立 python3 -> python 链接并安装 websockify
    ln -sf /usr/local/bin/python3 /usr/local/bin/python && \
    /usr/local/bin/python3 -m pip install --no-cache-dir websockify && \
    npm install -g @tobilu/qmd@1.1.6 && \
    # 安装 Playwright 浏览器依赖
    npx playwright install chromium --with-deps && \
    # 清理 apt 缓存
    apt-get purge -y --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# =============================================================================
# Phase 2: 运行时层 - 其他语言工具（变更较少）
# =============================================================================

# 2.1 UV (Python 包管理器) - 使用多阶段构建，更小更快
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# =============================================================================
# Phase 3: 应用层 - OpenClaw 插件与配置（变更较频繁）
# =============================================================================

# 3.1 创建 OpenClaw 目录结构
RUN mkdir -p /home/node/.openclaw/workspace /home/node/.openclaw/extensions && \
    chown -R node:node /home/node

# 切换到 node 用户（避免后续 chown 导致镜像膨胀）
USER node
ENV HOME=/home/node
WORKDIR /home/node

# 3.2 安装 Linuxbrew（Homebrew Linux 版本）
RUN mkdir -p /home/node/.linuxbrew/Homebrew && \
    git clone --depth 1 https://github.com/Homebrew/brew /home/node/.linuxbrew/Homebrew && \
    mkdir -p /home/node/.linuxbrew/bin && \
    ln -s /home/node/.linuxbrew/Homebrew/bin/brew /home/node/.linuxbrew/bin/brew && \
    chown -R node:node /home/node/.linuxbrew && \
    chmod -R g+rwX /home/node/.linuxbrew

# 3.3.1 克隆 napcat 插件
RUN cd /home/node/.openclaw/extensions && \
    git clone --depth 1 -b v4.17.25 https://github.com/Daiyimo/openclaw-napcat.git napcat

# 3.3.2 安装 napcat npm 依赖
RUN cd /home/node/.openclaw/extensions/napcat && \
    npm install --production

# 3.3.3 安装 napcat openclaw 插件
RUN cd /home/node/.openclaw/extensions/napcat && \
    timeout 300 openclaw plugins install -l . || true

# 3.3.4 安装 ClawHub 插件（napcat 之外的 IM 通道）
RUN timeout 300 openclaw plugins install clawhub:humanizeai || true && \
    timeout 300 openclaw plugins install clawhub:@openclaw/ralph-loop || true

# 3.3.5 安装第三方 IM 插件（钉钉/QQ/企微/内存插件）
RUN timeout 300 openclaw plugins install @soimy/dingtalk || true && \
    timeout 300 openclaw plugins install @tencent-connect/openclaw-qqbot@latest || true && \
    timeout 300 openclaw plugins install @sunnoy/wecom || true && \
    timeout 300 openclaw plugins install memory-lancedb-pro@beta || true

# 3.3.6 清理 .git 目录并打包为 seed
RUN mkdir -p /home/node/.openclaw /home/node/.openclaw-seed && \
    find /home/node/.openclaw/extensions -name ".git" -type d -exec rm -rf {} + && \
    mv /home/node/.openclaw/extensions /home/node/.openclaw-seed/ && \
    printf '%s\n' '2026.3.31' > /home/node/.openclaw-seed/extensions/.seed-version && \
    rm -rf /tmp/* /home/node/.npm /home/node/.cache
USER root

# 4.1 全局 Node 工具（mcporter, clawhub, agent-browser）
RUN npm install -g mcporter clawhub agent-browser && \
    npm cache clean --force

# 切换回 node 用户
USER node
WORKDIR /home/node/.openclaw/workspace/

# 4.2 配置 mcporter MCP 服务
RUN mcporter config add rednote http://rednote.mcp:18060/mcp && \
    mcporter config add freesearch --command "uvx mcp-server-freesearch --break-system-packages" --env SEARXNG_API_URL="https://searx.bndkt.io"

WORKDIR /home/node/.openclaw/

# =============================================================================
# Phase 5: ClawHub 技能安装（需要认证）
# =============================================================================

# 5.1 ClawHub 登录（使用 BuildKit secrets）
RUN --mount=type=secret,id=clawhub,env=CLAWHUB_TOKEN,required=true \
    clawhub login --token "$CLAWHUB_TOKEN" --no-browser

# 5.2 安装 ClawHub 技能包
RUN clawhub install --force proactive-agent && \
    clawhub install mcporter && \
    clawhub install self-improving && \
    clawhub install agent-browser-clawdbot && \
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
    clawhub install --force skill-refiner && \
    clawhub install --force skill-creator && \
    clawhub install agent && \
    clawhub install --force agent-evaluation && \
    clawhub install --force cron-mastery && \
    clawhub install --force news-summary && \
    clawhub install --force openclaw-subagents && \
    clawhub install --force create-subagent && \
    clawhub install ontology && \
    clawhub install multi-search-engine

# 5.3 克隆外部技能仓库
RUN git clone https://github.com/ACautomata/model-guidance /home/node/.openclaw/skills/model-guidance && \
    git clone https://github.com/ACautomata/openclaw-optimizer /home/node/.openclaw/skills/openclaw-optimizer && \
    git clone https://github.com/win4r/openclaw-workspace /home/node/.openclaw/skills/openclaw-workspace

# =============================================================================
# Phase 6: 最终配置
# =============================================================================

WORKDIR /home/node
ENV NODE_OPTIONS="--max-old-space-size=1280"

USER root

# 6.1 复制并配置初始化脚本
COPY ./init.sh /usr/local/bin/init.sh
RUN sed -i 's/\r$//' /usr/local/bin/init.sh && \
    chmod +x /usr/local/bin/init.sh && \
    chown -R node:node /home/node/.openclaw/ /home/node/.npm/

# 6.2 最终环境变量
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

# 6.3 暴露端口
EXPOSE 18789 18790

# 6.4 健康检查 - 检测 Gateway 端口是否可达
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD bash -c 'cat < /dev/tcp/localhost/${OPENCLAW_GATEWAY_PORT:-18789}' > /dev/null 2>&1 || exit 1

WORKDIR /home/node

# 入口点 - 使用 tini 作为 PID 1 以正确传播信号
ENTRYPOINT ["tini", "--", "/bin/bash", "/usr/local/bin/init.sh"]
