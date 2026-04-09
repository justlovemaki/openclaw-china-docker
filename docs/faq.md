# 常见问题

本文汇总 [`OpenClaw-CN-Docker`](../README.md) 当前版本的高频问题与排查建议，内容以 [`docker-compose.yml`](../docker-compose.yml)、[`.env.example`](../.env.example)、[`init.sh`](../init.sh) 与仓库内现有说明为准。

## 修改了环境变量，但配置没有按预期生效

### 现象

你修改了 [`.env`](../.env.example) 里的变量，但容器内行为似乎没有变化。

### 原因

当前项目并不是“仅在配置文件不存在时才初始化一次”。容器启动时会执行 [`init.sh`](../init.sh)，并根据当前环境变量同步模型、渠道、插件、Gateway 等配置到 `openclaw.json`。

但以下情况仍会让你感觉“没有生效”：

- 实际启动的不是你刚修改的那份 [`.env`](../.env.example)
- 容器没有重建或重启
- 你手动维护的 `openclaw.json` 中存在与环境变量冲突的旧字段
- 相关渠道缺少必要环境变量，结果被启动脚本自动禁用

### 建议排查顺序

1. 确认当前目录下的 [`.env`](../.env.example) 已保存
2. 执行以下命令重建或重启容器：

```bash
docker compose up -d --force-recreate
```

3. 查看启动日志里是否出现“同步完成”“渠道同步”“已禁用渠道”等提示：

```bash
docker compose logs -f openclaw-gateway
```

4. 进入容器检查实际配置：

```bash
docker compose exec openclaw-gateway /bin/bash
su node
cat ~/.openclaw/openclaw.json
```

### 什么时候需要删除旧配置

如果你想彻底回到“从当前环境变量重新生成基础结构”的状态，可以删除数据目录中的 `openclaw.json` 后再启动：

```bash
docker compose exec openclaw-gateway /bin/bash
rm -f /home/node/.openclaw/openclaw.json
exit
docker compose restart openclaw-gateway
```

如果你连同历史插件数据、运行状态一起清空，再删除整个宿主机数据目录。

---

## 启动后看不到某个平台生效

### 原因

[`init.sh`](../init.sh) 会根据是否提供了“必需环境变量”来启用或禁用渠道。

例如：

- 飞书需要 `FEISHU_APP_ID` 和 `FEISHU_APP_SECRET`，或提供 `FEISHU_ACCOUNTS_JSON`
- 钉钉需要 `DINGTALK_CLIENT_ID` 和 `DINGTALK_CLIENT_SECRET`，或提供 `DINGTALK_ACCOUNTS_JSON`
- QQ 机器人需要 `QQBOT_APP_ID` 和 `QQBOT_CLIENT_SECRET`，或提供 `QQBOT_BOTS_JSON`
- 企业微信需要 `WECOM_BOT_ID` 和 `WECOM_SECRET`，或提供 `WECOM_ACCOUNTS_JSON`
- NapCat 需要 `NAPCAT_REVERSE_WS_PORT`

缺字段时，启动脚本会把对应插件或渠道设为禁用。

### 排查方式

```bash
docker compose logs -f openclaw-gateway
```

重点看这些日志关键词：

- `渠道同步`
- `已禁用渠道`
- `未提供环境变量`
- `已根据 ... 多账号环境变量启用插件`

详细变量说明见 [`docs/configuration.md`](configuration.md)。

---

## 飞书机器人能发消息，但收不到消息

优先检查飞书开放平台后台的“事件与回调”配置：

- 是否选择“使用长连接接收事件”
- 是否订阅 `im.message.receive_v1`
- 相关权限是否已申请并通过审核
- 机器人是否确实安装到了目标聊天或群组

如果你启用的是飞书官方团队插件，还要确认交互式安装已经完成，而不是只设置了环境变量。

---

## 飞书官方插件为什么没有自动安装

### 原因

飞书官方团队插件安装命令：

```bash
npx -y @larksuite/openclaw-lark-tools install
```

是交互式流程，无法在 [`Dockerfile`](../Dockerfile) 构建阶段自动完成，所以项目只在镜像里准备运行环境，不会直接帮你走完安装向导。

### 正确做法

使用 [`docker-compose.yml`](../docker-compose.yml) 中的 `openclaw-installer` 工具容器：

```bash
docker compose up -d openclaw-gateway
docker compose --profile tools up -d openclaw-installer
docker exec -it openclaw-installer bash
su node
npx -y @larksuite/openclaw-lark-tools install
```

安装完成后，再按需在 [`.env`](../.env.example) 中设置：

```bash
FEISHU_OFFICIAL_PLUGIN_ENABLED=true
```

完整流程可参考 [`docs/quick-start.md`](quick-start.md) 中的工具容器使用说明。

---

## 出现 `plugin not found: openclaw-lark`

这通常说明飞书官方团队插件尚未完成交互式安装，或者安装发生在错误的容器里。

建议重新按 [`docs/quick-start.md`](quick-start.md) 中的工具容器流程执行：

```bash
docker compose --profile tools up -d openclaw-installer
docker exec -it openclaw-installer bash
su node
npx -y @larksuite/openclaw-lark-tools install
```

如果只是版本不匹配，可尝试：

```bash
npx -y @larksuite/openclaw-lark-tools update
```

---

## NapCat 应该怎么启用

NapCat 相关扩展已在镜像中预装，但是否启用取决于环境变量。

至少需要设置：

```bash
NAPCAT_REVERSE_WS_PORT=3001
```

常用可选项还有：

- `NAPCAT_HTTP_URL`
- `NAPCAT_ACCESS_TOKEN`
- `NAPCAT_ADMINS`
- `NAPCAT_DM_POLICY`
- `NAPCAT_GROUP_POLICY`

启动后可通过日志确认是否出现 NapCat 渠道同步信息。

---

## 连接 AI / Provider 失败

按以下顺序排查：

- 检查 `BASE_URL` 是否正确
- 如果是 OpenAI 兼容接口，通常需要带 `/v1`
- 检查 `API_KEY` 是否正确
- 检查 `API_PROTOCOL` 是否与服务实际协议一致
- 如果配置了多个 Provider，检查 `MODEL2_*`、`MODEL3_*` 等是否填完整
- 如果显式设置了 `PRIMARY_MODEL` 或 `IMAGE_MODEL_ID`，检查引用格式是否正确

例如：

- `default/gpt-4o`
- `aliyun/qwen3.5-plus`

模型与 Provider 规则见 [`docs/configuration.md`](configuration.md) 与 [`docs/aiclient-2-api.md`](aiclient-2-api.md)。

---

## 出现 401 / 403 错误

常见原因：

- `API_KEY` 填错
- Provider 后端本身拒绝当前模型或当前账号
- 代理层改写或丢失了认证头
- 使用了不匹配的 `BASE_URL` / `API_PROTOCOL`

建议先用最小配置只保留一组模型参数验证，再逐步叠加复杂配置。

---

## `PRIMARY_MODEL` 或 `IMAGE_MODEL_ID` 写了以后模型还是不对

当前项目会对模型引用做归一化处理。

### 规则

- 不带 `/` 时，会自动视为 `default/<模型名>`
- 带 `/` 且前缀是已知 Provider 名称时，视为完整引用
- 带 `/` 但前缀不是已知 Provider 名称时，会被视为 `default/...`

例如：

```bash
MODEL_ID=qwen3.5-plus
MODEL2_NAME=aliyun
MODEL2_MODEL_ID=qwen-max,qwen3.5-plus
PRIMARY_MODEL=aliyun/qwen3.5-plus
IMAGE_MODEL_ID=default/qwen3.5-plus
```

相关规则见 [`docs/configuration.md`](configuration.md) 与 [`init.sh`](../init.sh)。

---

## 出现 `Permission denied`

这通常不是命令偶发失败，而是宿主机挂载目录与容器内用户权限不一致。

### 当前项目的处理方式

- 默认允许容器先以 root 启动
- [`init.sh`](../init.sh) 会尝试修复 `/home/node/.openclaw` 权限
- 修复完成后，再以 `node` 用户启动 OpenClaw Gateway

### 常见原因

- 宿主机目录由 `root` 或其他 UID 创建
- 目录可读但不可写
- SELinux 对挂载卷做了额外限制

### 建议排查

查看容器日志是否出现权限检查失败提示：

```bash
docker compose logs -f openclaw-gateway
```

Linux 宿主机可修复目录所有权：

```bash
sudo chown -R 1000:1000 ~/.openclaw
```

如果你明确知道宿主机 UID:GID，也可以在 [`.env`](../.env.example) 里设置：

```bash
OPENCLAW_RUN_USER=1000:1000
```

如果宿主机启用了 SELinux，挂载卷可能还需要添加 `:z` 或 `:Z`。

---

## 容器里应该用哪个用户执行命令

推荐在进入容器后切换到 `node` 用户再执行大多数 OpenClaw 相关命令：

```bash
docker compose exec openclaw-gateway /bin/bash
su node
```

尤其是插件安装、配对审批、查看用户目录配置时，使用 `node` 用户更符合实际运行环境。

更多说明见 [`docs/quick-start.md`](quick-start.md)。

---

## 日志里提示 JSON 非法或配置冲突

当前版本的 [`init.sh`](../init.sh) 会对部分历史格式做兼容迁移，也会自动校验多账号冲突。

常见报错包括：

- `FEISHU_ACCOUNTS_JSON 不是合法 JSON`
- `DINGTALK_ACCOUNTS_JSON 不是合法 JSON`
- `WECOM_ACCOUNTS_JSON 不是合法 JSON`
- `QQBOT_BOTS_JSON 不是合法 JSON`
- 飞书 App ID 冲突
- 钉钉 clientId / robotCode / Agent ID 冲突
- 企业微信 botId / Agent ID 冲突
- QQ 机器人 AppID 冲突

遇到这类问题时，优先检查对应 JSON 是否为合法对象，以及账号标识是否重复。

---

## 还可以看哪里

- 快速开始：[`docs/quick-start.md`](quick-start.md)
- 配置指南：[`docs/configuration.md`](configuration.md)
- AIClient-2-API：[`docs/aiclient-2-api.md`](aiclient-2-api.md)
- 开发者说明：[`docs/developer-notes.md`](developer-notes.md)
- 项目总览：[`README.md`](../README.md)
