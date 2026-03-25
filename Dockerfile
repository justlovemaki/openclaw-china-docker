# syntax=docker/dockerfile:1.10
# OpenClaw Docker 镜像
FROM node:22-slim

# 设置工作目录
WORKDIR /app

# 设置环境变量
ENV BUN_INSTALL="/usr/local" \
    PATH="/usr/local/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive

# 1. 合并系统依赖安装与全局工具安装，并清理缓存
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    chromium \
    curl \
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
    python3 \
    socat \
    tini \
    unzip \
    pipx \
    python3-venv \
    websockify && \
    sed -i 's/^# *en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    # update-locale 在部分 slim 基础镜像中会返回 invalid locale settings，这里改为直接写入默认 locale 配置
    printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale && \
    # 配置 git 使用 HTTPS 替代 SSH
    git config --system url."https://github.com/".insteadOf ssh://git@github.com/ && \
    # 设置 npm 镜像并安装全局包
    npm config set registry https://registry.npmmirror.com && \
    npm install -g openclaw@latest opencode-ai@latest clawhub playwright playwright-extra puppeteer-extra-plugin-stealth @steipete/bird && \
    # 安装 bun、uv 和 qmd
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    npm install -g @tobilu/qmd@1.1.6 && \
    # 安装 Playwright 浏览器依赖
    npx playwright install chromium --with-deps && \
    # 清理 apt 缓存
    apt-get purge -y --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.npm /root/.cache

# 2. 插件安装（作为 node 用户以避免后期权限修复带来的镜像膨胀）
RUN mkdir -p /home/node/.openclaw/workspace /home/node/.openclaw/extensions && \
    chown -R node:node /home/node

USER node
ENV HOME=/home/node
WORKDIR /home/node

# 安装linuxbrew（Homebrew 的 Linux 版本），并配置环境变量
RUN mkdir -p /home/node/.linuxbrew/Homebrew && \
    git clone --depth 1 https://github.com/Homebrew/brew /home/node/.linuxbrew/Homebrew && \
    mkdir -p /home/node/.linuxbrew/bin && \
    ln -s /home/node/.linuxbrew/Homebrew/bin/brew /home/node/.linuxbrew/bin/brew && \
    chown -R node:node /home/node/.linuxbrew && \
    chmod -R g+rwX /home/node/.linuxbrew

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
  # 预执行安装命令（容器内需手动交互，此处仅作声明或环境准备）
  #  printf '{\n  "channels": {\n    "feishu": {\n      "enabled": false,\n      "appId": "2222222222222222",\n      "appSecret": "1111111111111111",\n      "accounts": {\n        "default": {\n          "appId": "2222222222222222",\n          "appSecret": "1111111111111111",\n          "botName": "OpenClaw Bot"\n        }\n      }\n    }\n  }\n}\n' > /home/node/.openclaw/openclaw.json && \
  # npx -y @larksuite/openclaw-lark-tools install && \
  find /home/node/.openclaw/extensions -name ".git" -type d -exec rm -rf {} + && \
  mv /home/node/.openclaw/extensions /home/node/.openclaw-seed/ && \
  printf '%s\n' '2026.3.24' > /home/node/.openclaw-seed/extensions/.seed-version && \
  rm -rf /tmp/* /home/node/.npm /home/node/.cache

USER root
# 1. 安装 UV (使用 COPY 也就是多阶段构建，不增加额外下载层)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# 2. 系统层依赖安装 & 清理 (合并指令，减少层数)
# 使用 root 权限进行系统级安装
# --no-install-recommends: 仅安装必要的依赖，不安装推荐包（显著减小体积）
# rm -rf /var/lib/apt/lists/*: 清除 apt 缓存，这是减小体积的关键
RUN sed -i 's@deb.debian.org@mirrors.aliyun.com@g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's@security.debian.org@mirrors.aliyun.com@g' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends python3-pip && \
    rm -rf /var/lib/apt/lists/*



# 3. Node 全局包安装 (合并指令)
# 既然下面要用 mcporter 和 clawhub，直接全局安装，不需要反复 npx (npx 会临时下载)
# npm cache clean: 清除 npm 缓存
RUN npm install -g mcporter clawhub && \
    npm install -g agent-browser && \
    npm cache clean --force

# 4. 切换到 node 用户进行应用配置
# 关键优化：避免在最后使用 chown -R。
# 如果在 root 下生成文件再 chown，Docker 会复制一份文件到新层，导致体积翻倍。
# 直接以 node 用户身份运行配置命令，文件所有权天然就是 node。
USER node
WORKDIR /home/node/.openclaw/workspace/

# Update Feishu
RUN mcporter config  add rednote http://rednote.mcp:18060/mcp && \
    mcporter config add freesearch --command "uvx mcp-server-freesearch --break-system-packages" --env SEARXNG_API_URL="https://searx.bndkt.io" 

WORKDIR /home/node/.openclaw/
# 5. 配置与技能安装 (合并指令)
# 直接使用全局安装的命令，省去 npx 的开销

RUN --mount=type=secret,id=clawhub,env=CLAWHUB_TOKEN,required=true \
    clawhub login --token "$CLAWHUB_TOKEN" --no-browser

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
    clawhub install creativity  && \
    clawhub install --force skill-improvement && \
    clawhub install --force skill-refiner && \
    clawhub install --force skill-creator && \
    clawhub install agent && \
    clawhub install --force agent-evaluation && \
    clawhub install --force cron-mastery && \
    clawhub install --force news-summary && \
    clawhub install --force openclaw-subagents && \
    clawhub install --force create-subagent

RUN git clone https://github.com/ACautomata/model-guidance /home/node/.openclaw/skills/model-guidance && \
    git clone https://github.com/ACautomata/openclaw-optimizer /home/node/.openclaw/skills/openclaw-optimizer && \
    git clone https://github.com/win4r/openclaw-workspace /home/node/.openclaw/skills/openclaw-workspace

    

WORKDIR /home/node
ENV NODE_OPTIONS="--max-old-space-size=1280"
  
# 3. 最终配置
USER root

# 复制初始化脚本并确保换行符为 LF
COPY ./init.sh /usr/local/bin/init.sh
RUN sed -i 's/\r$//' /usr/local/bin/init.sh && \
    chmod +x /usr/local/bin/init.sh&& \
    chown -R node:node /home/node/.openclaw/ /home/node/.npm/

# 设置环境变量
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

# 暴露端口
EXPOSE 18789 18790

# 设置工作目录为 home
WORKDIR /home/node

# 使用初始化脚本作为入口点
ENTRYPOINT ["/bin/bash", "/usr/local/bin/init.sh"]
