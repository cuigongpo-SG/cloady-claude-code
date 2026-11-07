# Cloady 容器里跑 Claude Code CLI + claude-code-router + 网页终端
# 作用：把 Cloady 免费容器当一台迷你 VPS 用，浏览器打开域名就是终端，里面跑 ccr code。
# 密钥不在镜像里：Gemini / OpenRouter key 走 Cloady 环境变量，路由器配置里写 $GEMINI_API_KEY / $OPENROUTER_API_KEY 引用它们。
FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*
# ttyd：网页终端（轻量静态二进制）
RUN curl -fsSL -o /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd
# 版本锁定：seed-profile.mjs 按 ccr 3.1.3 的 SQLite 结构写库，升级 ccr 前务必先
# 确认该结构没变；claude-code 锁定为当前在用的 2.1.319。
RUN npm install -g @anthropic-ai/claude-code@2.1.319 @musistudio/claude-code-router@3.1.3
COPY entrypoint.sh /entrypoint.sh
COPY seed-profile.mjs /seed-profile.mjs
# router-config.json 是旧版 v1 格式：只在容器首次启动、还没有 config.sqlite 时
# 被 ccr 读一次，用来迁移出 gemini / openrouter 供应商；之后改它不再生效。
COPY router-config.json /root/.claude-code-router/config.json
RUN chmod +x /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
