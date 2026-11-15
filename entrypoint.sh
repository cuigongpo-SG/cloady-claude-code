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
# 轮询器：后台常驻，日志在 /var/log/poller.log
mkdir -p /var/log
nohup sh /root/bridge/poller.sh >> /var/log/poller.log 2>&1 &
echo "轮询器已启动（PID $!），日志：/var/log/poller.log"
echo "Claude Code 容器已启动。打开网页终端，登录后运行：ccr code"
exec ttyd -W -p 8080 -c "${TTYD_USER}:${TTYD_PASS}" bash
