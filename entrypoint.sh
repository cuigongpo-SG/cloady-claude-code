#!/bin/sh
# Cloady Claude Code 容器启动入口：只负责拉起网页终端。
# 路由器不需要常驻——在终端里运行 `ccr code` 时它会自动启动并把 Claude Code 接过去。
set -e
: "${TTYD_PASS:?TTYD_PASS environment variable is required}"
TTYD_USER="${TTYD_USER:-claude}"
if [ -z "$OPENROUTER_API_KEY" ]; then
  echo "提示：OPENROUTER_API_KEY 未设置。先在 Cloady 变量里加上 key 再用 ccr code，否则路由器没有上游可用。"
fi
# CCR v3 的配置在 SQLite 里，旧版 JSON 配不出来名叫 code 的 profile：
# 每次启动都幂等地往库里写一次 code profile（见 /seed-profile.mjs）。
# 种子失败只记警告，不阻塞终端启动，方便进终端排查。
if [ -f /seed-profile.mjs ]; then
  node /seed-profile.mjs || echo "警告：code profile 种子写入失败，'ccr code' 仍可能报 Profile not found，详见上方日志。" >&2
fi
echo "Claude Code 容器已启动。打开网页终端，登录后运行：ccr code"
exec ttyd -W -p 8080 -c "${TTYD_USER}:${TTYD_PASS}" bash
