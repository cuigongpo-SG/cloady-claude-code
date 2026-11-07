# Cloady 容器里跑 Claude Code CLI + claude-code-router + 网页终端
# 作用：把 Cloady 免费容器当一台迷你 VPS 用，浏览器打开域名就是终端，里面跑 ccr code。
# 密钥不在镜像里：OpenRouter key 走 Cloady 环境变量，路由器配置里写 $OPENROUTER_API_KEY 引用它。
FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*
# ttyd：网页终端（轻量静态二进制）
RUN curl -fsSL -o /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd
RUN npm install -g @anthropic-ai/claude-code @musistudio/claude-code-router
COPY entrypoint.sh /entrypoint.sh
COPY router-config.json /root/.claude-code-router/config.json
RUN chmod +x /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
