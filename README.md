# OpenClaw-CN-Docker

> 面向中国 IM 场景的 OpenClaw Docker 整合镜像，预装飞书、钉钉、QQ 机器人、企业微信等常用插件，适合快速搭建统一的 AI 机器人网关。

> 🚀 **推荐搭配**：OpenClaw 功能强大但 Token 消耗较大，推荐配合 [AIClient-2-API](https://github.com/justlovemaki/AIClient-2-API) 项目使用，将各大 AI 客户端转换为 API 接口，实现无限 Token 调用，彻底解决 Token 焦虑！本项目已支持 OpenAI 和 Claude 两种协议，可直接对接 AIClient-2-API 服务。

> 💡 **AI 助手提示**：克隆本项目并准备好渠道机器人与 AI API 信息填入 `.env.example` 文件中，在 AI CLI（如 Claude Code/Gemini CLI）中输入：`请参考 .env.example，quick-start.md 和 docker-compose.yml 帮我完成本项目的部署与环境配置`。

<table align="center">
  <thead>
    <tr>
      <th align="center">镜像下载量超100k</th>
      <th align="center">好用给个赞助吧</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center" valign="middle">
        <img src="https://docker-card.justlikemaki.workers.dev/justlikemaki/openclaw-docker-cn-im?layout=compact&theme=github" alt="openclaw-docker-cn-im" style="width: 100%; max-width: 520px; height: 320px; object-fit: contain;" />
      </td>
      <td align="center" valign="middle">
        <img src="sponsor.png" alt="微信赞赏码" style="width: 100%; max-width: 260px; height: 320px; object-fit: cover; object-position: center;" />
      </td>
    </tr>
  </tbody>
</table>

## 🚀 核心特性

本项目提供开箱即用的 OpenClaw 体验，并针对国内 IM 场景进行了深度增强：

- **全平台支持**：预装飞书（官方/旧版）、钉钉、QQ 机器人、企业微信插件，并集成 [Agent Reach](https://github.com/Panniantong/Agent-Reach) 支持 Twitter、小红书、微博、抖音等全网渠道。
- **配置驱动**：支持通过环境变量自动生成配置，提供 [`.env.example`](.env.example) (完整版) 和 [`.env.minimal`](.env.minimal) (精简版) 快速上手。
- **工具集增强**：集成 [Agent Reach](https://github.com/Panniantong/Agent-Reach)、OpenCode AI、Playwright、FFmpeg、中文 TTS 等 AI 常用工具。
- **安全沙箱**：支持 Docker-in-Docker 沙箱模式，实现 Python 代码与 Shell 脚本的隔离运行，确保宿主机安全(使用官方最小镜像，无使用示例)。
- **生产友好**：支持数据持久化挂载，提供独立工具容器用于飞书插件安装等一次性操作。

## 📖 文档索引

| 文档名称 | 主要内容 |
| :--- | :--- |
| 🚀 [**快速开始**](docs/quick-start.md) | **新手必读**：部署、升级、日志查看与进入容器 |
| ⚙️ [配置指南](docs/configuration.md) | 环境变量、模型 Gateway、工作空间详细说明 |
| 🔌 [插件文档](#-支持的平台) | 各 IM 平台的官方及第三方插件配置链接 |
| 💡 [AIClient 对接](docs/aiclient-2-api.md) | 对接 AIClient-2-API 提升 Token 效率的推荐方式 |
| 🛠️ [进阶指南](docs/advanced.md) | Docker 运行命令、持久化存储及自定义配置 |
| ❓ [常见问题](docs/faq.md) | FAQ 与故障排查 |

> 🚩 **开发相关**：关于镜像构建与初始化脚本说明，请参考 [`docs/developer-notes.md`](docs/developer-notes.md)。

## 🧩 支持的平台

- ✅ **飞书**：[官方团队插件](https://github.com/larksuite/openclaw-lark) / [旧版内置](https://github.com/openclaw/openclaw/blob/main/docs/channels/feishu.md)
- ✅ **钉钉**：[soimy/dingtalk](https://github.com/soimy/openclaw-channel-dingtalk)
- ✅ **QQ 机器人**：[sliverp/qqbot](https://github.com/sliverp/qqbot)
- ✅ **企业微信**：[sunnoy/wecom](https://github.com/sunnoy/openclaw-plugin-wecom)
- ✅ **微信**：[官方插件接入指南](docs/wechat.md)
- ✅ **全网渠道搜索**：通过集成 [Agent Reach](https://github.com/Panniantong/Agent-Reach) 支持 Twitter、小红书、微博、抖音、小宇宙等。可在对话中输入 `禁止使用web_search，web_fetch 工具， 必须使用 agent-reach 的工具来替代你自带的web_search，web_fetch ，并写入tools和记忆文档中` 进行初始化。

## 📦 快速部署

Docker Hub：[`justlikemaki/openclaw-docker-cn-im`](https://hub.docker.com/r/justlikemaki/openclaw-docker-cn-im)

```bash
docker pull justlikemaki/openclaw-docker-cn-im:latest
```

建议克隆本仓库，参考 [`.env.example`](.env.example) (或更简洁的 [`.env.minimal`](.env.minimal)) 配置环境变量，然后执行：
```bash
docker compose up -d
```

## 💡 使用建议

- 生产或长期维护场景，建议直接克隆仓库而不是只单独下载 [`docker-compose.yml`](docker-compose.yml) 和 [`.env.example`](.env.example)
- 每次升级前，先同步 [`README.md`](README.md)、[`docker-compose.yml`](docker-compose.yml)、[`.env.example`](.env.example) 与新增文档
- 如果你手动维护 [`openclaw.json`](openclaw.json.example)，建议同时关注 [`openclaw.json.example`](openclaw.json.example) 的结构变化
- 如需启用 **Docker 沙箱** 功能，请确保在 `.env` 中设置 `OPENCLAW_SANDBOX_MODE=all` (或 `non-main`)，并取消 `docker-compose.yml` 中 `/var/run/docker.sock` 挂载行的注释。

## 📈 Star History

- 如果项目对你有帮助，欢迎点一个 Star。

[![Star History Chart](https://api.star-history.com/svg?repos=justlovemaki/OpenClaw-CN-Docker&type=Date)](https://star-history.com/#justlovemaki/OpenClaw-CN-Docker&Date)

## 许可证

本项目基于 OpenClaw 构建，遵循 GNU General Public License v3.0 (GPL-3.0) 许可证，详见 [`LICENSE`](LICENSE)。
