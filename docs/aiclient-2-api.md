# AIClient-2-API 对接指南

[`OpenClaw-CN-Docker`](../README.md) 已支持 OpenAI 协议与 Claude 协议，可直接对接 [`AIClient-2-API`](https://github.com/justlovemaki/AIClient-2-API)。

## 前置准备

1. 启动 AIClient-2-API 服务
2. 在 Web UI（通常为 `http://localhost:3000`）中配置至少一个 Provider
3. 记录用于访问的 API Key

## 方式一：OpenAI 协议

适合 Gemini 等模型：

```bash
MODEL_ID=gemini-3-flash-preview
BASE_URL=http://localhost:3000/v1
API_KEY=your-api-key
API_PROTOCOL=openai-completions
CONTEXT_WINDOW=1000000
MAX_TOKENS=8192
```

## 方式二：Claude 协议

适合 Claude 模型：

```bash
MODEL_ID=claude-sonnet-4-5
BASE_URL=http://localhost:3000
API_KEY=your-api-key
API_PROTOCOL=anthropic-messages
CONTEXT_WINDOW=200000
MAX_TOKENS=8192
```

## 指定某个 Provider 路由

如果 AIClient-2-API 中配置了多个路由，可通过 `BASE_URL` 指向特定 Provider：

```bash
# Kiro 提供的 Claude（OpenAI 协议）
BASE_URL=http://localhost:3000/claude-kiro-oauth/v1

# Kiro 提供的 Claude（Claude 协议）
BASE_URL=http://localhost:3000/claude-kiro-oauth

# Gemini CLI（OpenAI 协议）
BASE_URL=http://localhost:3000/gemini-cli-oauth/v1

# Antigravity（OpenAI 协议）
BASE_URL=http://localhost:3000/gemini-antigravity/v1
```

## 常见检查项

- OpenAI 协议通常需要 `/v1`
- Claude 协议通常不需要 `/v1`
- 优先尝试使用 `127.0.0.1` 替代 `localhost`
- 修改 [`.env`](../.env.example) 后如未生效，可删除旧配置重新生成，见 [`docs/configuration.md`](configuration.md)

## 相关文档

- 快速开始：[`docs/quick-start.md`](quick-start.md)
- 配置指南：[`docs/configuration.md`](configuration.md)
- 常见问题：[`docs/faq.md`](faq.md)
