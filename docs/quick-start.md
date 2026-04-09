# 快速开始

本文适合第一次部署 [`OpenClaw-CN-Docker`](../README.md) 的用户，覆盖预构建镜像部署、自行构建镜像、升级、日志查看与进入容器等常用操作。

## 部署方式概览

### 方式一：使用预构建镜像

适合绝大多数用户，直接使用 [`docker-compose.yml`](../docker-compose.yml) 与 [`.env.example`](../.env.example) 即可启动。

### 方式二：自行构建镜像

适合需要自定义镜像、调试 Docker 构建过程或验证本地修改的用户，构建定义见 [`Dockerfile`](../Dockerfile)。

---

## 方式一：使用预构建镜像

### 1. 获取配置文件

可以直接下载：

```bash
wget https://raw.githubusercontent.com/justlovemaki/OpenClaw-CN-Docker/main/docker-compose.yml
wget https://raw.githubusercontent.com/justlovemaki/OpenClaw-CN-Docker/main/.env.example
```

也可以直接克隆仓库，便于后续升级维护：

```bash
git clone https://github.com/justlovemaki/OpenClaw-CN-Docker.git
cd OpenClaw-CN-Docker
```

### 2. 初始化环境变量

你可以根据需求选择完整版或精简版配置：

- **完整版 (推荐)**: 包含所有可选配置及详细注释
  ```bash
  cp .env.example .env
  ```
- **精简版 (极简起步)**: 仅包含运行必需的核心参数
  ```bash
  cp .env.minimal .env
  ```

至少配置以下三个变量：

| 环境变量 | 说明 | 示例 |
| --- | --- | --- |
| `MODEL_ID` | 默认模型 ID | `gpt-4` |
| `BASE_URL` | 模型服务地址 | `https://api.openai.com/v1` |
| `API_KEY` | 模型服务密钥 | `sk-xxx` |

一个最小示例：

```bash
MODEL_ID=gemini-3-flash-preview
BASE_URL=http://localhost:3000/v1
API_KEY=your-api-key
API_PROTOCOL=openai-completions
CONTEXT_WINDOW=1000000
MAX_TOKENS=8192
```

> IM 平台配置可以暂时留空，后续再按需启用。

### 3. 启动服务

```bash
docker compose up -d
```

### 4. 查看日志

```bash
docker compose logs -f
```

### 5. 停止服务

```bash
docker compose down
```

---

## 方式二：自行构建镜像

### 1. 克隆仓库

```bash
git clone https://github.com/justlovemaki/OpenClaw-CN-Docker.git
cd OpenClaw-CN-Docker
```

### 2. 构建镜像

```bash
docker build -t justlikemaki/openclaw-docker-cn-im:latest .
```

### 3. 复制并修改环境变量

```bash
cp .env.example .env
```

### 4. 启动服务

```bash
docker compose up -d
```

---

## 启用沙箱支持 (可选)

沙箱功能用于隔离 AI 执行 Python 代码与 Shell 脚本的环境，防止对主容器造成潜在安全威胁。

1. 修改 `.env` 文件，启用沙箱模式：
   ```bash
   OPENCLAW_SANDBOX_MODE=all
   ```
2. 修改 `docker-compose.yml`，取消第 200 行左右关于 `/var/run/docker.sock` 挂载的注释：
   ```yaml
   volumes:
     - ${OPENCLAW_DATA_DIR}:/home/node/.openclaw
     - openclaw-extensions:/home/node/.openclaw/extensions
     # 取消下面这一行的注释
     - /var/run/docker.sock:/var/run/docker.sock
   ```
3. 重新启动服务：
   ```bash
   docker compose up -d --force-recreate
   ```

详细配置说明请参考 [配置指南](configuration.md#沙箱配置-sandbox)。

---

## 升级建议

推荐直接克隆仓库进行维护。升级时，先同步项目文件，再拉取镜像并重建容器，避免遗漏新增的环境变量、Compose 编排或文档变更。

```bash
# 首次使用（如果还没有克隆仓库）
git clone https://github.com/justlovemaki/OpenClaw-CN-Docker.git
cd OpenClaw-CN-Docker

# 后续升级时同步仓库
git pull

# 根据最新模板检查本地 .env
# 必要时对照 .env.example 补充新增配置

# 拉取镜像并重建
docker compose pull
docker compose up -d --force-recreate
```

如果你不是通过克隆仓库，而是只下载了 [`docker-compose.yml`](../docker-compose.yml) 和 [`.env.example`](../.env.example)，升级时也建议先同步这两个文件，再执行上面的拉取与重建命令。

---

## 进入容器

### 进入主服务容器

```bash
docker compose exec openclaw-gateway /bin/bash
```

或：

```bash
docker exec -it openclaw-gateway /bin/bash
```

### 进入后先切换到 `node` 用户

```bash
su node
```

这是推荐操作。否则在容器内执行某些命令时，可能因为权限上下文不一致而失败。

### 容器内常用命令

```bash
# 查看 OpenClaw 版本
openclaw --version

# 查看配置文件
cat ~/.openclaw/openclaw.json

# 查看工作空间
ls -la ~/.openclaw/workspace

# 手动执行配对审批（以 Telegram 为例）
openclaw pairing approve telegram {token}

# 手动安装飞书官方插件
npx -y @larksuite/openclaw-lark-tools install
```

---

## 独立工具容器的用途

项目在 [`docker-compose.yml`](../docker-compose.yml) 中提供了 [`openclaw-installer`](../docker-compose.yml) 工具容器，用于执行一次性的交互式安装或维护任务，例如飞书官方团队插件安装。

### 启动主服务

```bash
docker compose up -d openclaw-gateway
```

### 启动工具容器

```bash
docker compose --profile tools up -d openclaw-installer
```

如已有异常退出的旧工具容器，可先删除：

```bash
docker compose --profile tools rm -sf openclaw-installer
```

### 进入工具容器

```bash
docker exec -it openclaw-installer bash
su node
```

---

## 部署后的建议检查项

- 确认端口 `18789` 被占用
- 确认 [`.env`](../.env.example) 中至少完成模型相关配置
- 确认宿主机数据目录对容器可写
- 如需接入 IM 平台，优先根据 [`.env.example`](../.env.example) 与 [`docs/configuration.md`](configuration.md) 补充对应环境变量

## 下一步

- 模型与 Gateway 配置：[`docs/configuration.md`](configuration.md)
- AIClient-2-API 对接：[`docs/aiclient-2-api.md`](aiclient-2-api.md)
- 高级运行方式：[`docs/advanced.md`](advanced.md)
- 故障排查：[`docs/faq.md`](faq.md)
