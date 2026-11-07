# cloady-claude-code

Claude Code CLI + claude-code-router (cc switch) + 网页终端，跑在 Cloady 免费容器里，
把容器当一台迷你 VPS 用：浏览器打开域名、登录终端，里面跑 `ccr code` 就是 Claude Code。

## 用法

1. 打开 Cloady 给的域名，ttyd 登录（用户名/密码见 Cloady 变量 `TTYD_USER` / `TTYD_PASS`）。
2. 终端里运行：
   ```
   ccr code
   ```
   路由器自动启动，Claude Code 的请求主走 Gemini（Google API，免费 key），
   备用走 OpenRouter 的免费模型。
3. 在 Claude Code 里运行 `/status`，看到路由后的模型名（不是 Anthropic 模型）即表示接通。

## 变量（Cloady 里设置，不进仓库）

- `TTYD_USER`：网页终端用户名（默认 `claude`）
- `TTYD_PASS`：网页终端密码（必填，没有它容器拒绝启动）
- `GEMINI_API_KEY`：Google AI Studio 的免费 key（主用，必填；去 aistudio.google.com 申请，
  免绑卡）。没有它，`ccr code` 发不出请求。
- `OPENROUTER_API_KEY`：OpenRouter 的 key（备用通道，去 openrouter.ai/keys 申请）。
  没给也不影响主用；给了才能切到备用模型。

## 模型

- 主用：`gemini-3.5-flash`（Gemini provider，直连 Google API）。
- 备用：`cohere/north-mini-code:free`（OpenRouter 免费）。
- 换模型改本仓库的 `router-config.json` 里的模型名，改完在终端里跑 `ccr restart`。

## 诚实说明

- 免费档只有 0.5 vCPU / 1GB 内存，还要和同工作区的 xray 应用共享：轻量会话可以，
  长 agent 循环、大上下文可能内存不足。真要重度用，得是正经 VPS（Oracle Always Free
  那种，2 核/12GB，但注册要真信用卡验证）。
- Gemini 免费档约 1,500 次/天，免绑卡、无过期；免费档内容 Google 可能会拿去训练，
  涉密代码别放这里。
- 免费模型有每日限额；非 Claude 模型接 Claude Code，工具调用会比原生 Claude 弱一些。
