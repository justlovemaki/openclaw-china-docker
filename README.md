# OpenClaw-Docker-CN-IM

> 🚀 **推荐搭配**：OpenClaw 功能强大但 Token 消耗较大，推荐配合 [AIClient-2-API](https://github.com/justlovemaki/AIClient-2-API) 项目使用，将各大 AI 客户端转换为标准 API 接口，实现无限 Token 调用，彻底解决 Token 焦虑！本项目已支持 OpenAI 和 Claude 两种协议，可直接对接 AIClient-2-API 服务。

## 项目简介

OpenClaw 中国 IM 插件整合版 Docker 镜像，预装并配置了飞书、钉钉、QQ机器人、企业微信等主流中国 IM 平台插件，让您可以快速部署一个支持多个中国 IM 平台的 AI 机器人网关。

**项目地址**: https://github.com/justlovemaki/OpenClaw-Docker-CN-IM

### 核心特性

- 🚀 **开箱即用**：预装所有中国主流 IM 平台插件
- 🔧 **灵活配置**：通过环境变量轻松配置各平台凭证
- 🐳 **Docker 部署**：一键启动，无需复杂配置
- 📦 **数据持久化**：支持配置和工作空间数据持久化
- 💻 **OpenCode AI**：内置 AI 代码助手，支持智能代码生成和分析
- 🎭 **Playwright**：预装浏览器自动化工具，支持网页操作和截图
- 🗣️ **中文 TTS**：支持中文语音合成（Text-to-Speech）

### 历史更新

<details>
<summary><b>点击展开查看历史更新记录</b></summary>

#### 2026 年 3 月

| 日期 | 版本 | 更新内容 |
|------|------|----------|
| 2026-03-11 | `2026.3.8` | <ul><li>升级 OpenClaw 到 `2026.3.8`，并调整镜像环境与飞书官方插件预更新流程</li><li>新增 `PRIMARY_MODEL`，增强图片模型与多 Provider 配置能力</li><li>QQ 机器人新增 `QQBOT_BOTS_JSON` 多 Bot 配置支持</li><li>企业微信重构为账号中心配置，补充默认账号、命令、动态 Agent 等能力，并兼容旧版环境变量</li><li>重构配置同步逻辑，完善 QQ / WeCom 多账号处理与插件启停联动</li><li>补充飞书官方插件安装说明及异常处理指引</li></ul> |
| 2026-03-08 | `2026.3.2-f3` | <ul><li>修复企业微信插件在显式禁用时被错误启用的问题</li><li>修复模型名称中包含多个斜杠时的前缀判断逻辑（合并 PR #87）</li><li>更新 Dockerfile 中企业微信插件的安装方式，移除非必要版本锁</li><li>增加 README 历史更新记录模块</li><li>集成飞书官方团队插件 CLI 工具（`feishu-plugin-onboard`），支持日历、任务、多维表格等 OAPI 能力</li><li>新增独立安装容器配置，可通过 `docker compose --profile tools` 执行飞书官方插件安装向导</li></ul> |
| 2026-03-04 | `2026.3.2-f2` | <ul><li>支持企业微信多账号配置并标准化配置结构</li><li>优化飞书配置兼容性，增加 `accounts.main` 到 `default` 的自动迁移逻辑</li><li>修复配置同步脚本中环境变量传递问题</li></ul> |
| 2026-03-02 | `2026.3.1` | <ul><li>更新依赖版本</li><li>改进模型同步配置检查</li></ul> |

</details>

### 支持的平台

**IM 平台**
- ✅ 飞书官方团队插件（推荐，支持完整 OAPI 工具）
- ✅ 飞书（Feishu/Lark 旧版内置插件）
- ✅ 钉钉（DingTalk）
- ✅ QQ 机器人（QQ Bot）
- ✅ 企业微信（WeCom）

**集成工具**
- ✅ OpenCode AI - AI 代码助手
- ✅ Playwright - 浏览器自动化
- ✅ 中文 TTS - 语音合成
- ✅ FFmpeg - 语音/视频格式转换
- ✅ 飞书官方 OAPI 工具集（日历、任务、多维表格等）

### Docker 镜像地址

**Docker Hub**: https://hub.docker.com/r/justlikemaki/openclaw-docker-cn-im

```bash
docker pull justlikemaki/openclaw-docker-cn-im:latest
```

---

## 快速开始

### 方式一：使用预构建镜像（推荐）

#### 1. 下载配置文件

```bash
wget https://raw.githubusercontent.com/justlovemaki/OpenClaw-Docker-CN-IM/main/docker-compose.yml
wget https://raw.githubusercontent.com/justlovemaki/OpenClaw-Docker-CN-IM/main/.env.example
```

#### 2. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置文件（至少配置 AI 模型相关参数）
nano .env
```

**最小配置示例**：

| 环境变量 | 说明 | 示例值 |
|---------|------|--------|
| `MODEL_ID` | AI 模型名称 | `gpt-4` |
| `BASE_URL` | AI 服务 API 地址 | `https://api.openai.com/v1` |
| `API_KEY` | AI 服务 API 密钥 | `sk-xxx...` |

> 💡 **提示**：IM 平台配置为可选项，可以先启动服务，后续再配置需要的平台。

#### 3. 启动服务

```bash
docker-compose up -d
```

#### 4. 查看日志

```bash
docker-compose logs -f
```

#### 5. 停止服务

```bash
docker-compose down
```

#### 6. 进入容器

如需进入容器进行调试或执行命令：

```bash
# 使用 docker-compose 进入容器
docker-compose exec openclaw-gateway /bin/bash

# 或使用 docker 命令进入容器
docker exec -it openclaw-gateway /bin/bash
```

进入容器后，**请先执行 `su node` 切换到 node 用户**，然后再执行相关命令（否则可能会由于权限问题导致命令执行失败）：

```bash
# 切换到 node 用户（必需）
su node

# 查看 OpenClaw 版本
openclaw --version

# 查看配置文件
cat ~/.openclaw/openclaw.json

# 查看工作空间
ls -la ~/.openclaw/workspace

# 手动执行配对命令（如 Telegram）
openclaw pairing approve telegram {token}

# 手动安装官方飞书插件
feishu-plugin-onboard install
```

### 方式二：自行构建镜像

如果您需要自定义镜像或进行开发调试，可以选择自行构建：

#### 1. 克隆项目

```bash
git clone https://github.com/justlovemaki/OpenClaw-Docker-CN-IM.git
cd OpenClaw-Docker-CN-IM
```

#### 2. 构建镜像

```bash
docker build -t justlikemaki/openclaw-docker-cn-im:latest .
```

#### 3. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置文件（至少配置 AI 模型相关参数）
nano .env
```

#### 4. 启动服务

```bash
docker-compose up -d
```

---

## 配置指南

### AI 模型配置

本项目支持 **OpenAI 协议**和 **Claude 协议**两种 API 格式。

> 💡 **推荐模型**：推荐使用 `gemini-3-flash-preview` 模型，该模型具有超大上下文窗口（1M tokens）、快速响应速度和优秀的性价比，非常适合作为 OpenClaw 的后端模型。

#### 基础配置参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `MODEL_ID` | 模型名称 | `model id` |
| `PRIMARY_MODEL` | 显式指定 `agents.defaults.model.primary`，使用完整 `provider/model` 引用 | 留空 |
| `IMAGE_MODEL_ID` | 图片模型名称，可单独指定；支持直接填写完整 `provider/model` 引用 | 留空 |
| `BASE_URL` | Provider Base URL | `http://xxxxx/v1` |
| `API_KEY` | Provider API Key | `123456` |
| `API_PROTOCOL` | API 协议类型 | `openai-completions` |
| `CONTEXT_WINDOW` | 模型上下文窗口大小 | `200000` |
| `MAX_TOKENS` | 模型最大输出 tokens | `8192` |

#### 协议类型说明

| 协议类型 | 适用模型 | Base URL 格式 | 特殊特性 |
|---------|---------|--------------|---------|
| `openai-completions` | OpenAI、Gemini 等 | 需要 `/v1` 后缀 | - |
| `anthropic-messages` | Claude | 不需要 `/v1` 后缀 | Prompt Caching、Extended Thinking |

#### 配置示例

**OpenAI 协议（Gemini 模型）**

```bash
MODEL_ID=gemini-3-flash-preview
BASE_URL=http://localhost:3000/v1
API_KEY=your-api-key
API_PROTOCOL=openai-completions
CONTEXT_WINDOW=1000000
MAX_TOKENS=8192
```

**Claude 协议（Claude 模型）**

```bash
MODEL_ID=claude-sonnet-4-5
BASE_URL=http://localhost:3000
API_KEY=your-api-key
API_PROTOCOL=anthropic-messages
CONTEXT_WINDOW=200000
MAX_TOKENS=8192
```

**MiniMax（OpenAI 兼容协议）**

[MiniMax](https://platform.minimax.io) 提供 OpenAI 兼容接口，支持 `MiniMax-M2.5` 和 `MiniMax-M2.5-highspeed` 两款模型，均支持 204,800 tokens 上下文窗口。

作为默认提供商：

```bash
MODEL_ID=MiniMax-M2.5,MiniMax-M2.5-highspeed
BASE_URL=https://api.minimax.io/v1
API_KEY=your-minimax-api-key
API_PROTOCOL=openai-completions
CONTEXT_WINDOW=204800
MAX_TOKENS=8192
```

作为额外提供商（同时保留默认提供商）：

```bash
MODEL3_NAME=minimax
MODEL3_MODEL_ID=MiniMax-M2.5,MiniMax-M2.5-highspeed
MODEL3_BASE_URL=https://api.minimax.io/v1
MODEL3_API_KEY=your-minimax-api-key
MODEL3_PROTOCOL=openai-completions
MODEL3_CONTEXT_WINDOW=204800
MODEL3_MAX_TOKENS=8192
```

> 💡 MiniMax 也支持 Anthropic 协议，将 `BASE_URL` 设为 `https://api.minimax.io/anthropic`、`API_PROTOCOL` 设为 `anthropic-messages` 即可。国内用户可将域名替换为 `api.minimaxi.com`（注意多一个 `i`）。API Key 可在 [MiniMax 开放平台](https://platform.minimax.io) 获取。
>
> 📖 API 文档：[OpenAI 兼容接口](https://platform.minimax.io/docs/api-reference/text-openai-api) | [Anthropic 兼容接口](https://platform.minimax.io/docs/api-reference/text-anthropic-api)

#### 指定其它 Provider 作为默认主模型

默认情况下，项目会把 [`MODEL_ID`](.env.example) 的第一个值同步为 [`agents.defaults.model.primary`](openclaw.json.example:88)，并自动补全为 `default/...`。

如果你配置了第二个 provider，且希望把它的模型设为默认主模型，同时让图片模型也切到其它 provider，可以这样配置：

```bash
MODEL_ID=dashscope/qwen3.5-plus
MODEL2_NAME=aliyun
MODEL2_MODEL_ID=qwen-max,qwen3.5-plus,qwen-vl-max
PRIMARY_MODEL=aliyun/qwen3.5-plus
IMAGE_MODEL_ID=aliyun/qwen-vl-max
```

此时：
- [`models.providers.default`](openclaw.json.example:18) 仍由 [`MODEL_ID`](.env.example) 生成
- [`models.providers.aliyun`](openclaw.json.example:17) 由 `MODEL2_*` 生成
- [`agents.defaults.model.primary`](openclaw.json.example:88) 会优先使用 [`PRIMARY_MODEL`](.env.example)
- [`agents.defaults.imageModel.primary`](openclaw.json.example:91) 会直接使用 [`IMAGE_MODEL_ID`](.env.example)；若未填写，则回退到 [`MODEL_ID`](.env.example)

优先级如下：
- 主模型：[`PRIMARY_MODEL`](.env.example) → [`MODEL_ID`](.env.example)
- 图片模型：[`IMAGE_MODEL_ID`](.env.example) → [`MODEL_ID`](.env.example)

注意：[`PRIMARY_MODEL`](.env.example) 和 [`IMAGE_MODEL_ID`](.env.example) 都可以填写完整引用，即 `provider/model` 格式，例如：
- `default/dashscope/qwen3.5-plus`
- `aliyun/qwen3.5-plus`
- `aliyun/qwen-vl-max`
- `model2/claude-sonnet-4-5`

### Gateway 配置

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `OPENCLAW_GATEWAY_TOKEN` | Gateway 访问令牌 | `123456` |
| `OPENCLAW_GATEWAY_BIND` | 绑定地址 | `lan` |
| `OPENCLAW_GATEWAY_PORT` | Gateway 端口 | `18789` |
| `OPENCLAW_BRIDGE_PORT` | Bridge 端口 | `18790` |

### 工作空间配置

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `WORKSPACE` | 工作空间目录 | `/home/node/.openclaw/workspace` |

---

## 常见问题

### Q: 修改了环境变量但配置没有生效？

容器启动时只有在配置文件不存在时才会生成新配置。如需重新生成配置，请删除现有配置文件：

```bash
# 删除配置文件
rm ~/.openclaw/openclaw.json
# 重启容器
docker-compose restart
```

或者直接删除整个数据目录重新开始：

```bash
rm -rf ~/.openclaw
docker-compose up -d
```

### Q: 连接 AIClient-2-API 失败？

- 确认 AIClient-2-API 服务运行中
- 检查 Base URL 是否正确（OpenAI 协议需要 `/v1` 后缀）
- 尝试使用 `127.0.0.1` 替代 `localhost`

### Q: 401 错误？

- 检查 API Key 是否正确配置
- 确认环境变量 `API_KEY` 已设置

### Q: 模型不可用？

- 在 AIClient-2-API Web UI 确认已配置对应提供商
- 重启容器：`docker-compose restart`

### Q: 飞书机器人能发消息但收不到消息？

- 检查是否配置了事件订阅（最容易遗漏的配置）
- 确认事件配置方式选择了"使用长连接接收事件"
- 确认已添加 `im.message.receive_v1` 事件

### Q: Telegram 机器人如何配对？

如果需要启用 Telegram，必须提供有效的 `TELEGRAM_BOT_TOKEN`，启用后需要进入容器（参考“进入容器”章节）执行以下命令进行配对审批：

```bash
# 先切换到 node 用户
su node

# 执行配对审批
openclaw pairing approve telegram {token}
```

并且需要重启 Docker 服务使配置生效。

### Q: 同样的启动命令，为什么有人报错 `Permission denied`？

这通常不是命令本身不稳定，而是**运行上下文变化**导致：宿主机挂载目录所有者（UID/GID）与容器内进程用户不一致。

#### 为什么会“偶发”

- 同样是 `docker compose up -d`，但目录来源不同：
  - 你手动创建目录：可能是当前用户（如 `1000:1000`）
  - Docker 自动创建或使用 sudo 创建：可能是 `root:root`（`0:0`）
- 本镜像最终以 `node` 用户运行网关；若挂载目录归属不匹配，就可能无法写入。

#### 快速排查

```bash
# 1) 看宿主机目录归属（Linux）
ls -ln ~/.openclaw

# 2) 看容器内运行用户
docker run --rm justlikemaki/openclaw-docker-cn-im:latest id
```

若容器用户是 `uid=1000`，而宿主机目录是 `uid=0` 且权限不足，就会报错。

#### 解决方案（推荐顺序）

1. **宿主机修正目录所有权（最直接）**

```bash
sudo chown -R 1000:1000 ~/.openclaw
```

2. **显式指定容器运行用户（可选）**

在 `.env` 中设置：

```bash
OPENCLAW_RUN_USER=1000:1000
```

然后重启：

```bash
docker compose up -d
```

3. **SELinux 场景（CentOS/RHEL/Fedora）**

若权限看起来没问题但仍拒绝访问，请给挂载卷加 `:z` 或 `:Z` 标签。

#### 本项目已做的稳态处理

- [`docker-compose.yml`](docker-compose.yml) 新增可选 `user` 配置：`OPENCLAW_RUN_USER`（默认 `0:0`）
- [`init.sh`](init.sh) 启动时会：
  - 打印挂载目录当前 UID/GID 与目标 UID/GID
  - 尝试自动修复 `/home/node/.openclaw` 权限
  - 若仍不可写，输出明确的修复命令并失败退出，避免“有时成功有时报错”的隐性状态
---

## 注意事项

1. 确保宿主机的 18789 和 18790 端口未被占用
2. 配置文件中的敏感信息（如 API 密钥、令牌）应妥善保管
3. 首次运行时会自动创建必要的目录和配置文件，包括 `openclaw.json` 配置文件，已存在时不会覆盖
4. 容器以 `node` 用户身份运行，确保挂载的卷有正确的权限
5. IM 平台配置均为可选项，可根据实际需求选择性配置
6. 使用 OpenAI 协议时，Base URL 需要包含 `/v1` 后缀
7. 使用 Claude 协议时，Base URL 不需要 `/v1` 后缀

---

## IM 平台配置

<details>
<summary><b>飞书配置</b></summary>

### 1. 获取飞书机器人凭证

1. 在 [飞书开放平台](https://open.feishu.cn/) 创建自建应用
2. 添加应用能力-机器人
3. 在凭证页面获取 **App ID** 和 **App Secret**
4. 开启所需权限（见下方）⚠️ **重要**
5. 配置事件订阅（见下方）⚠️ **重要**

### 2. 必需权限（租户级别）

| 权限 | 范围 | 说明 |
|------|------|------|
| `im:message` | 消息 | 发送和接收消息（核心权限） |
| `im:message.p2p_msg:readonly` | 私聊 | 读取发给机器人的私聊消息 |
| `im:message.group_at_msg:readonly` | 群聊 | 接收群内 @机器人 的消息 |
| `im:message:send_as_bot` | 发送 | 以机器人身份发送消息 |
| `im:resource` | 媒体 | 上传和下载图片/文件 |
| `im:chat.members:bot_access` | 群成员 | 获取群成员信息 |
| `im:chat.access_event.bot_p2p_chat:read` | 聊天事件 | 读取机器人单聊事件 |

### 3. 推荐权限（租户级别）

| 权限 | 范围 | 说明 |
|------|------|------|
| `contact:user.employee_id:readonly` | 用户信息 | 获取用户员工 ID（用于用户识别） |
| `im:message:readonly` | 读取 | 获取历史消息 |
| `application:application:self_manage` | 应用管理 | 应用自我管理 |
| `application:bot.menu:write` | 机器人菜单 | 配置机器人菜单 |
| `event:ip_list` | IP 列表 | 获取飞书服务器 IP 列表 |

### 4. 可选权限（租户级别）

| 权限 | 范围 | 说明 |
|------|------|------|
| `aily:file:read` | AI 文件读取 | 读取 AI 助手文件 |
| `aily:file:write` | AI 文件写入 | 写入 AI 助手文件 |
| `application:application.app_message_stats.overview:readonly` | 消息统计 | 查看应用消息统计概览 |
| `corehr:file:download` | 人事文件 | 下载人事系统文件 |

### 5. 用户级别权限（可选）

| 权限 | 范围 | 说明 |
|------|------|------|
| `aily:file:read` | AI 文件读取 | 以用户身份读取 AI 助手文件 |
| `aily:file:write` | AI 文件写入 | 以用户身份写入 AI 助手文件 |
| `im:chat.access_event.bot_p2p_chat:read` | 聊天事件 | 以用户身份读取机器人单聊事件 |

<details>
<summary><b>官方飞书插件推荐权限 JSON（默认折叠）</b></summary>

```json
{
  "scopes": {
    "tenant": [
      "contact:contact.base:readonly",
      "docx:document:readonly",
      "im:chat:read",
      "im:chat:update",
      "im:message.group_at_msg:readonly",
      "im:message.p2p_msg:readonly",
      "im:message.pins:read",
      "im:message.pins:write_only",
      "im:message.reactions:read",
      "im:message.reactions:write_only",
      "im:message:readonly",
      "im:message:recall",
      "im:message:send_as_bot",
      "im:message:send_multi_users",
      "im:message:send_sys_msg",
      "im:message:update",
      "im:resource",
      "application:application:self_manage",
      "cardkit:card:write",
      "cardkit:card:read"
    ],
    "user": [
      "contact:user.employee_id:readonly",
      "offline_access",
      "base:app:copy",
      "base:field:create",
      "base:field:delete",
      "base:field:read",
      "base:field:update",
      "base:record:create",
      "base:record:delete",
      "base:record:retrieve",
      "base:record:update",
      "base:table:create",
      "base:table:delete",
      "base:table:read",
      "base:table:update",
      "base:view:read",
      "base:view:write_only",
      "base:app:create",
      "base:app:update",
      "base:app:read",
      "board:whiteboard:node:create",
      "board:whiteboard:node:read",
      "calendar:calendar:read",
      "calendar:calendar.event:create",
      "calendar:calendar.event:delete",
      "calendar:calendar.event:read",
      "calendar:calendar.event:reply",
      "calendar:calendar.event:update",
      "calendar:calendar.free_busy:read",
      "contact:contact.base:readonly",
      "contact:user.base:readonly",
      "contact:user:search",
      "docs:document.comment:create",
      "docs:document.comment:read",
      "docs:document.comment:update",
      "docs:document.media:download",
      "docs:document:copy",
      "docx:document:create",
      "docx:document:readonly",
      "docx:document:write_only",
      "drive:drive.metadata:readonly",
      "drive:file:download",
      "drive:file:upload",
      "im:chat.members:read",
      "im:chat:read",
      "im:message",
      "im:message.group_msg:get_as_user",
      "im:message.p2p_msg:get_as_user",
      "im:message.send_as_user",
      "im:message:readonly",
      "search:docs:read",
      "search:message",
      "space:document:delete",
      "space:document:move",
      "space:document:retrieve",
      "task:comment:read",
      "task:comment:write",
      "task:task:read",
      "task:task:write",
      "task:task:writeonly",
      "task:tasklist:read",
      "task:tasklist:write",
      "wiki:node:copy",
      "wiki:node:create",
      "wiki:node:move",
      "wiki:node:read",
      "wiki:node:retrieve",
      "wiki:space:read",
      "wiki:space:retrieve",
      "wiki:space:write_only"
    ]
  }
}
```

</details>

### 6. 事件订阅 ⚠️

**这是最容易遗漏的配置！** 如果机器人能发消息但收不到消息，请检查此项。

在飞书开放平台的应用后台，进入 **事件与回调** 页面：

1. **事件配置方式**：选择 **使用长连接接收事件**（推荐）
2. **添加事件订阅**，勾选以下事件：

| 事件 | 说明 |
|------|------|
| `im.message.receive_v1` | 接收消息（必需） |
| `im.message.message_read_v1` | 消息已读回执 |
| `im.chat.member.bot.added_v1` | 机器人进群 |
| `im.chat.member.bot.deleted_v1` | 机器人被移出群 |

3. 确保事件订阅的权限已申请并通过审核

### 7. 环境变量配置

在 `.env` 文件中添加：

```bash
FEISHU_APP_ID=your-app-id
FEISHU_APP_SECRET=your-app-secret
# 官方飞书插件独立开关，安装官方插件后建议显式开启
FEISHU_OFFICIAL_PLUGIN_ENABLED=true
```
> 💡 **参考项目**：[clawdbot-feishu](https://github.com/openclaw/openclaw/blob/main/docs/channels/feishu.md) - 飞书机器人完整实现示例

### 飞书官方团队插件配置

本项目已集成飞书官方团队插件 CLI 工具。在容器运行后，推荐按照以下步骤完成配置以获得更强大的能力：

1. **不要在主服务容器内执行安装**：
   `feishu-plugin-onboard install` 会主动触发 OpenClaw 服务重载/重启；如果直接在 [`openclaw-gateway`](docker-compose.yml:4) 容器内执行，会打断当前容器里的主进程。
2. **使用独立安装容器执行向导**：
   先启动主服务：`docker compose up -d openclaw-gateway`

   再启动工具容器：`docker compose --profile tools up -d openclaw-installer`

   如果此前创建过异常退出的旧容器，先执行：`docker compose --profile tools rm -sf openclaw-installer`

   进入工具容器并切换用户：
   `docker exec -it openclaw-installer bash`

   `su node`
3. **在工具容器内执行安装向导**：
   运行 `feishu-plugin-onboard install`。
   - 程序会询问是否卸载旧的 `lark-office` MCP`，输入 `Y`。
   - 输入您的飞书应用 `AppID` 和 `AppSecret`。

   由于 [`openclaw-installer`](docker-compose.yml:82) 只是一次性工具容器，不承载 Gateway 主进程，因此这里发生服务重启不会把主网关容器安装流程打断。

   如果出现 `plugin not found: feishu-openclaw-plugin`，说明**飞书官方团队插件尚未完成交互式安装**，当前镜像里只预装了 [`feishu-plugin-onboard`](README.md:578) CLI 工具，并不会在构建阶段自动完成插件注册。此时请继续在工具容器内执行交互式命令 [`feishu-plugin-onboard install`](README.md:578)，安装完成后再在 [`.env`](.env.example) 中配置 `FEISHU_OFFICIAL_PLUGIN_ENABLED=true` 显式开启官方插件。
   
   如有以下报错：`Error: OpenClaw version mismatch. Expected >= 2026.2.26, found OpenClaw 2026.3.8 (3caab92). Please upgrade.`
   运行 `feishu-plugin-onboard update` 代替安装命令

4. **完成配对**：
   - 在飞书给机器人发消息获取配对码。
   - 在主服务容器或工具容器中执行：`openclaw pairing approve feishu <配对码> --notify`
5. **常用管理指令**：
   - 状态检查：`feishu-plugin-onboard doctor`
   - 自动修复：`feishu-plugin-onboard doctor --fix`
   - 更新插件：`feishu-plugin-onboard update`
   - 批量授权：在飞书对话框输入 `/feishu auth`
6. **安装完成后可关闭工具容器**：
   `docker compose --profile tools stop openclaw-installer`
   或 `docker compose --profile tools rm -sf openclaw-installer`

</details>

<details>
<summary><b>钉钉配置</b></summary>

### 1. 创建钉钉应用

1. 访问 [钉钉开发者后台](https://open-dev.dingtalk.com/)
2. 创建企业内部应用
3. 添加「机器人」能力
4. 配置消息接收模式为 **Stream 模式**
5. 发布应用

### 2. 获取凭证

从开发者后台获取：

- **Client ID**（AppKey）
- **Client Secret**（AppSecret）
- **Robot Code**（与 Client ID 相同）
- **Corp ID**（与 Client ID 相同）
- **Agent ID**（应用 ID）

### 3. 环境变量配置

在 `.env` 文件中添加：

```bash
DINGTALK_CLIENT_ID=your-dingtalk-client-id
DINGTALK_CLIENT_SECRET=your-dingtalk-client-secret
DINGTALK_ROBOT_CODE=your-dingtalk-robot-code
DINGTALK_CORP_ID=your-dingtalk-corp-id
DINGTALK_AGENT_ID=your-dingtalk-agent-id
```

**参数说明**：
- `DINGTALK_CLIENT_ID` - 必需，钉钉应用的 Client ID（AppKey）
- `DINGTALK_CLIENT_SECRET` - 必需，钉钉应用的 Client Secret（AppSecret）
- `DINGTALK_ROBOT_CODE` - 可选，机器人 Code，默认与 Client ID 相同
- `DINGTALK_CORP_ID` - 可选，企业 ID
- `DINGTALK_AGENT_ID` - 可选，应用 Agent ID

> 💡 **参考项目**：[openclaw-channel-dingtalk](https://github.com/soimy/openclaw-channel-dingtalk) - 钉钉渠道完整实现示例

</details>

<details>
<summary><b>QQ 机器人配置</b></summary>

### 1. 获取 QQ 机器人凭证

1. 访问 [QQ 开放平台](https://q.qq.com/)
2. 创建机器人应用
3. 获取 AppID 和 AppSecret（ClientSecret）
4. 获取主机在公网的 IP，配置到 IP 白名单

### 2. 环境变量配置

在 `.env` 文件中添加：

```bash
QQBOT_APP_ID=你的AppID
QQBOT_CLIENT_SECRET=你的AppSecret
```

> 💡 **参考项目**：[qqbot](https://github.com/sliverp/qqbot) - QQ 机器人完整实现示例

</details>

<details>
<summary><b>企业微信配置</b></summary>

### 1. 获取企业微信凭证

1. 访问 [企业微信管理后台](https://work.weixin.qq.com/)
2. 进入"应用管理"，用 API 模式创建一个或多个"智能机器人"应用
3. 在每个应用的"接收消息"配置中设置 Token 和 EncodingAESKey
4. 配置对应回调 URL（见下方单账号/多账号路径说明）

### 2. 单账号配置（兼容旧格式）

在 `.env` 文件中添加：

```bash
WECOM_TOKEN=your-token
WECOM_ENCODING_AES_KEY=your-aes-key
```

> 启动后会自动写入 [`channels.wecom.default`](openclaw.json.example:155) 结构，旧配置无需手工迁移。

### 3. 多账号配置（Multi-Bot）

在 [`openclaw.json`](README.md:648) 的 [`channels.wecom`](openclaw.json.example:154) 下使用字典结构，每个 key 为账号 ID（如 `bot1`、`bot2`），每个 value 为该账号独立配置：

```json
{
  "channels": {
    "wecom": {
      "bot1": {
        "token": "Bot1 的 Token",
        "encodingAesKey": "Bot1 的 EncodingAESKey",
        "adminUsers": ["admin1"],
        "agent": {
          "corpId": "企业 CorpID",
          "corpSecret": "Bot1 应用 Secret",
          "agentId": 1000001,
          "token": "Bot1 回调 Token",
          "encodingAesKey": "Bot1 回调 EncodingAESKey"
        },
        "webhooks": {
          "ops-group": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
        }
      },
      "bot2": {
        "token": "Bot2 的 Token",
        "encodingAesKey": "Bot2 的 EncodingAESKey",
        "agent": {
          "corpId": "企业 CorpID",
          "corpSecret": "Bot2 应用 Secret",
          "agentId": 1000002
        }
      }
    }
  }
}
```

### 4. 多账号环境变量配置（Docker Compose）

现在支持直接在 [`.env.example`](.env.example) / `.env` 中通过 `WECOM_BOTS_JSON` 配置多账号，并由 [`docker-compose.yml`](docker-compose.yml) 自动透传到容器。

示例（单行 JSON）：

```bash
WECOM_BOTS_JSON={"bot1":{"token":"t1","encodingAesKey":"k1","agent":{"corpId":"wwxxx","corpSecret":"s1","agentId":1000001}},"bot2":{"token":"t2","encodingAesKey":"k2","agent":{"corpId":"wwxxx","corpSecret":"s2","agentId":1000002}}}
```

说明：

- `WECOM_BOTS_JSON` 会与现有 [`channels.wecom`](openclaw.json.example:154) 做深度合并，不会粗暴覆盖整个对象
- 若同时配置了 `WECOM_TOKEN` / `WECOM_ENCODING_AES_KEY`，会写入 `default` 账号
- 若 `WECOM_BOTS_JSON` 中也包含 `default`，其字段会覆盖同名字段

### 5. 多账号规则与回调路径

- 账号 ID 仅支持小写字母、数字、`-`、`_`
- 旧单账号结构（`token` 直接写在 `wecom` 下）会自动识别并迁移为 `default` 账号
- WeCom 机器人回调路径按账号分配：`/webhooks/wecom/{accountId}`，例如 `bot1` 对应 `/webhooks/wecom/bot1`
- Agent 回调路径按账号分配：`/webhooks/app/{accountId}`，例如 `bot2` 对应 `/webhooks/app/bot2`
- 动态会话 ID 按账号隔离：`wecom-{accountId}-dm-{userId}`、`wecom-{accountId}-group-{chatId}`
- 启动时会自动检测重复 Token / Agent ID，避免消息路由冲突

⚠️ 多账号模式下，需要在企业微信后台为每个账号分别配置对应 URL（例如 `/webhooks/wecom/bot1`）。

> 💡 **参考项目**：[openclaw-plugin-wecom](https://github.com/sunnoy/openclaw-plugin-wecom) - 企业微信插件完整实现示例

</details>

---

## AIClient-2-API 配置指南

<details>
<summary><b>点击展开 AIClient-2-API 配置说明</b></summary>

本项目已支持 OpenAI 和 Claude 两种协议，可直接对接 [AIClient-2-API](https://github.com/justlovemaki/AIClient-2-API) 服务。

### 前置准备

1. 启动 AIClient-2-API 服务
2. 在 Web UI (`http://localhost:3000`) 配置至少一个提供商
3. 记录配置文件中的 API Key

### 配置方式一：OpenAI 协议（推荐用于 Gemini）

在 `.env` 文件中配置：

```bash
MODEL_ID=gemini-3-flash-preview
BASE_URL=http://localhost:3000/v1
API_KEY=your-api-key
API_PROTOCOL=openai-completions
CONTEXT_WINDOW=1000000
MAX_TOKENS=8192
```

### 配置方式二：Claude 协议（推荐用于 Claude）

在 `.env` 文件中配置：

```bash
MODEL_ID=claude-sonnet-4-5
BASE_URL=http://localhost:3000
API_KEY=your-api-key
API_PROTOCOL=anthropic-messages
CONTEXT_WINDOW=200000
MAX_TOKENS=8192
```

### 指定特定提供商（可选）

如需指定特定提供商，可修改 Base URL：

```bash
# Kiro 提供的 Claude (OpenAI 协议)
BASE_URL=http://localhost:3000/claude-kiro-oauth/v1

# Kiro 提供的 Claude (Claude 协议)
BASE_URL=http://localhost:3000/claude-kiro-oauth

# Gemini CLI (OpenAI 协议)
BASE_URL=http://localhost:3000/gemini-cli-oauth/v1

# Antigravity (OpenAI 协议)
BASE_URL=http://localhost:3000/gemini-antigravity/v1
```

</details>

---

## 高级使用

<details>
<summary><b>使用 Docker 命令运行</b></summary>

如果不使用 Docker Compose，可以直接使用 Docker 命令：

```bash
docker run -d \
  --name openclaw-gateway \
  --cap-add=CHOWN \
  --cap-add=SETUID \
  --cap-add=SETGID \
  --cap-add=DAC_OVERRIDE \
  -e MODEL_ID=model id \
  -e BASE_URL=http://xxxxx/v1 \
  -e API_KEY=123456 \
  -e API_PROTOCOL=openai-completions \
  -e CONTEXT_WINDOW=200000 \
  -e MAX_TOKENS=8192 \
  -e FEISHU_APP_ID=your-app-id \
  -e FEISHU_APP_SECRET=your-app-secret \
  -e DINGTALK_CLIENT_ID=your-dingtalk-client-id \
  -e DINGTALK_CLIENT_SECRET=your-dingtalk-client-secret \
  -e DINGTALK_ROBOT_CODE=your-dingtalk-robot-code \
  -e DINGTALK_CORP_ID=your-dingtalk-corp-id \
  -e DINGTALK_AGENT_ID=your-dingtalk-agent-id \
  -e QQBOT_APP_ID=your-qqbot-app-id \
  -e QQBOT_CLIENT_SECRET=your-qqbot-client-secret \
  -e WECOM_TOKEN=your-token \
  -e WECOM_ENCODING_AES_KEY=your-aes-key \
  -e OPENCLAW_GATEWAY_TOKEN=123456 \
  -e OPENCLAW_GATEWAY_BIND=lan \
  -e OPENCLAW_GATEWAY_PORT=18789 \
  -v ~/.openclaw:/home/node/.openclaw \
  -v ~/.openclaw/workspace:/home/node/.openclaw/workspace \
  -p 18789:18789 \
  -p 18790:18790 \
  --restart unless-stopped \
  justlikemaki/openclaw-docker-cn-im:latest
```

</details>

<details>
<summary><b>数据持久化</b></summary>

容器使用以下卷进行数据持久化：

- `/home/node/.openclaw` - OpenClaw 配置和数据目录
- `/home/node/.openclaw/workspace` - 工作空间目录

</details>

<details>
<summary><b>端口说明</b></summary>

- `18789` - OpenClaw Gateway 端口
- `18790` - OpenClaw Bridge 端口

</details>

<details>
<summary><b>自定义配置文件</b></summary>

如果需要完全自定义配置文件，可以：

1. 在宿主机创建配置文件 `~/.openclaw/openclaw.json`
2. 挂载该目录到容器：`-v ~/.openclaw:/home/node/.openclaw`
3. 容器启动时会检测到已存在的配置文件，跳过自动生成

</details>

---

## 开发者信息

<details>
<summary><b>项目文件说明</b></summary>

- [`Dockerfile`](Dockerfile) - Docker 镜像构建文件
- [`init.sh`](init.sh) - 容器初始化脚本（作为主程序运行）
- [`docker-compose.yml`](docker-compose.yml) - Docker Compose 配置文件
- [`.env.example`](.env.example) - 环境变量配置模板
- [`.dockerignore`](.dockerignore) - Docker 构建忽略文件
- [`openclaw.json.example`](openclaw.json.example) - OpenClaw 默认配置文件示例

</details>

<details>
<summary><b>构建镜像</b></summary>

```bash
docker build -t justlikemaki/openclaw-docker-cn-im:latest .
```

</details>

<details>
<summary><b>初始化脚本功能</b></summary>

[`init.sh`](init.sh) 脚本在容器启动时执行以下操作：

1. 创建必要的目录结构
2. 根据环境变量动态生成配置文件（如果不存在）
3. 设置正确的文件权限
4. 启动 OpenClaw Gateway 服务（verbose 模式）

</details>

<details>
<summary><b>配置文件生成</b></summary>

容器首次启动时，如果 `/home/node/.openclaw/openclaw.json` 不存在，初始化脚本会根据环境变量自动生成配置文件，包括：

- **模型配置**：使用指定的模型和 Provider
- **通道配置**：根据提供的环境变量启用相应的 IM 平台
- **Gateway 配置**：端口、绑定地址、认证令牌
- **插件配置**：自动启用相应的通道插件

</details>

<details>
<summary><b>安装的包</b></summary>

镜像中已全局安装以下 npm 包：

- `openclaw@latest` - OpenClaw 主程序
- `opencode-ai@latest` - OpenCode AI
- `playwright` - Playwright 浏览器自动化工具
- `@openclaw/feishu` - 飞书插件
- `clawdbot-channel-dingtalk` - 钉钉插件（从 GitHub 安装）
- `qqbot` - QQ 机器人插件（先克隆到 `/tmp/qqbot`，然后从本地目录安装）
- `openclaw-plugin-wecom` - 企业微信插件（从 GitHub 安装）

</details>

<details>
<summary><b>启动命令</b></summary>

容器使用以下命令启动 OpenClaw：

```bash
openclaw gateway --verbose
```

这将以详细日志模式启动 Gateway 服务。

</details>

---

## ⭐ Star History

如果这个项目对您有帮助，请给我们一个 Star ⭐️！您的支持是我们持续改进的动力。

[![Star History Chart](https://api.star-history.com/svg?repos=justlovemaki/OpenClaw-Docker-CN-IM&type=Date)](https://star-history.com/#justlovemaki/OpenClaw-Docker-CN-IM&Date)

---

## 💖 赞助支持

如果您觉得这个项目对您有帮助，欢迎赞助支持我们的开发工作！

<p align="center">
  <img src="sponsor.png" alt="微信赞赏码" width="300">
</p>

### 赞助者名单

感谢以下赞助者的支持：

赞助者列表将在这里更新

---

## 许可证

本项目基于 OpenClaw 构建，遵循 GNU General Public License v3.0 (GPL-3.0) 许可证。详见 [`LICENSE`](LICENSE) 文件。
