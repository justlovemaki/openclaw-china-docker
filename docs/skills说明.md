## Skills 

OpenClaw 的 Skill 本质上是一个目录，核心文件是 SKILL.md（YAML frontmatter + Markdown 指令）。

OpenClaw 会把可用 Skills 注入到智能体上下文，让模型知道：

- 这个 Skill 叫啥
- 能解决什么问题
- 需要什么工具/环境

简单理解：**Skill = 给智能体的一份“可调用能力说明书”**。

## 加载位置与优先级

OpenClaw 默认会从这些位置加载 Skills：

1. 内置 Skills`（随 OpenClaw 发布）`
2. 托管/本地 Skills：`~/.openclaw/skills`
3. 工作区 Skills：`/.openclaw/<workspace>/skills`

同名冲突时，优先级是：

`~/.openclaw/<workspace>/skills` >` ~/.openclaw/skills` > `内置 Skills`

另外你还能在配置里加额外目录：

`skills.load.extraDirs`（优先级最低）

## 安装 Skills

### 本地安装

1. 复制技能到 OpenClaw 扩展目录

```bash
创建自定义扩展目录
mkdir -p ~/.openclaw/extensions/custom/skills/

复制技能文件（从你的 workspace）
cp -r /home/node/.openclaw/workspace/skills/conversation-diagnosis-jira \
  ~/.openclaw/extensions/custom/skills/
```

2. 安装技能依赖

```bash
cd ~/.openclaw/extensions/custom/skills/conversation-diagnosis-jira

安装依赖
npm install
```

3. 配置环境变量（可选，用于 JIRA 功能）

```bash

添加到 ~/.bashrc 或 ~/.zshrc
export JIRA_BASE_URL=https://jira.xiaoduoai.com
export JIRA_USERNAME=你的用户名
export JIRA_PASSWORD=你的密码

立即生效
source ~/.bashrc
```

4. 重启 OpenClaw 网关

```bash

停止网关
openclaw gateway stop

启动网关
openclaw gateway
```

或后台运行：
```bash
openclaw gateway &
```

5. 验证安装

```bash
openclaw skills list | grep jira
```

### clawhub安装



## 查找 Skills

最实用的方式是 ClawHub：

```
clawhub search "postgres backups"
clawhub search "image edit" --limit 20
```

如果把自己本地 Skills 备份到云端：

```
clawhub publish ./my-skill --slug my-skill --name "My Skill" --version 1.0.0 --tags latest
# 或批量
clawhub sync --all
```

## 配置 Skills（核心：`~/.openclaw/openclaw.json`）

```json
{
  "skills": {
    "allowBundled": ["gemini", "peekaboo"],
    "load": {
      "extraDirs": [
        "~/Projects/shared-skills",
        "~/Projects/team-skill-pack/skills"
      ],
      "watch": true,
      "watchDebounceMs": 250
    },
    "install": {
      "preferBrew": true,
      "nodeManager": "npm"
    },
    "entries": {
      "nano-banana-pro": {
        "enabled": true,
        "apiKey": "GEMINI_KEY_HERE",
        "env": {
          "GEMINI_API_KEY": "GEMINI_KEY_HERE"
        },
        "config": {
          "endpoint": "https://example.invalid",
          "model": "nano-pro"
        }
      },
      "sag": {
        "enabled": false
      }
    }
  }
}

```

allowBundled：只对白名单里的“内置 Skills”开放
load.extraDirs：附加扫描目录（低优先级）
load.watch：是否监听技能文件变化自动刷新
install.nodeManager：安装器优先 npm/pnpm/yarn/bun
entries.<skillKey>.enabled：单 Skill 开关
entries.<skillKey>.env：为该轮智能体运行注入环境变量
entries.<skillKey>.apiKey：和 primaryEnv 联动的快捷密钥字段
entries.<skillKey>.config：Skill 的自定义配置容器

-------------------------
## 使用 Skills（会话里如何触发）

大多数情况下，你不需要手动“调用 API”，只要在用户请求中给出明确任务，模型会根据已加载 Skills 自动选择。

但要注意这几个 frontmatter 开关：

- user-invocable: true|false：是否暴露为用户可触发命令

- disable-model-invocation: true|false：是否禁止模型自动调用
- command-dispatch: tool：斜杠命令直接分发到工具
- command-tool: <tool_name>：命令分发目标工具
- command-arg-mode: raw：原始参数直传工具

-------------------------
## 进阶：门控（加载过滤）

你可以在 `metadata.openclaw` 里声明依赖，让 Skill 仅在条件满足时加载。

```
---
name: nano-banana-pro
description: Generate or edit images via Gemini 3 Pro Image
metadata:
  {
    "openclaw":
      {
        "requires":
          {
            "bins": ["uv"],
            "env": ["GEMINI_API_KEY"],
            "config": ["browser.enabled"]
          },
        "primaryEnv": "GEMINI_API_KEY"
      }
  }
---

```

常用门控字段：

- `requires.bins` / `requires.anyBins`
- `requires.env`
- `requires.config`
- `os`（`darwin|linux|win32`）
- `always: true`

## 沙箱模式注意事项（很容易踩坑）

当智能体跑在 Docker 沙箱里时：

- 宿主机环境变量不会自动带入容器

- skills.entries.*.env/apiKey 主要作用于宿主机流程
- 需要在 agents.defaults.sandbox.docker.env（或 agent 级）单独配置
- requires.bins 在宿主机会检查，真正执行时容器里也必须有对应二进制

结论：宿主机可用 != 沙箱可用。

-------------------------
## 常见问题与排障

### 我安装了 Skill，但会话里没生效

按顺序检查：

1. 安装目录是否在 <workspace>/skills 或 ~/.openclaw/skills

2. 是否有同名 Skill 被更高优先级目录覆盖
3. skills.entries.<key>.enabled 是否被设为 false
4. requires.* 条件是否满足（bin/env/config）
5. 是否开启新会话（会话会缓存 Skills 快照）

改了 SKILL.md，为什么没立即更新

1. 确认 skills.load.watch: true
2. 确认 watchDebounceMs 不是过大
3. 保守做法：开新会话或重启 Gateway

插件带的 Skills 不出现

1. openclaw plugins list 看插件是否启用
2. 检查 plugins.entries.<id>.enabled
3. 检查插件是否声明了 skills 目录
4. 修改插件配置后重启 Gateway

