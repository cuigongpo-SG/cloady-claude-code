#!/bin/sh
# Cloady Claude Code 容器启动入口（桥接版）：先起轮询器，再起网页终端。
# 轮询器在后台跑，容器重启后它会自己跟着起来，不用手动再开。
set -e
: "${TTYD_PASS:?TTYD_PASS environment variable is required}"
TTYD_USER="${TTYD_USER:-claude}"
if [ -z "$OPENROUTER_API_KEY" ]; then
  echo "提示：OPENROUTER_API_KEY 未设置。先在 Cloady 变量里加上 key 再用 ccr code，否则路由器没有上游可用。"
fi
if [ -z "${HANDOFF_DEPLOY_KEY:-}" ]; then
  echo "提示：HANDOFF_DEPLOY_KEY 未设置，轮询器将空转（只写日志、不接任务）。在 Cloady 变量里加上交接仓库的 deploy key 私钥再重启应用。"
fi
# 启动前先把 ccr 的 code profile 种子化并起网关，否则 ccr code 会报
# "Profile 'code' was not installed or is disabled"。这两步必须在每次启动时做，
# 只靠手动补一次的话容器重建/重新部署后就失效。失败只记日志，不阻断容器启动。
if [ -f /seed-profile.mjs ] && command -v node >/dev/null 2>&1; then
  echo "正在跑种子脚本 /seed-profile.mjs ..."
  node /seed-profile.mjs >> /var/log/poller.log 2>&1 || echo "警告：种子脚本失败，见 /var/log/poller.log"
else
  echo "提示：/seed-profile.mjs 不存在，跳过种子步骤。"
fi
if command -v ccr >/dev/null 2>&1; then
  echo "正在启动 CCR 网关 ..."
  ccr start --daemon >> /var/log/poller.log 2>&1 || echo "警告：网关启动失败，见 /var/log/poller.log"
fi
# 轮询器：后台常驻，日志在 /var/log/poller.log
mkdir -p /var/log
nohup sh /root/bridge/poller.sh >> /var/log/poller.log 2>&1 &
echo "轮询器已启动（PID $!），日志：/var/log/poller.log"
echo "Claude Code 容器已启动。打开网页终端，登录后运行：ccr code"
exec ttyd -W -p 8080 -c "${TTYD_USER}:${TTYD_PASS}" bash
