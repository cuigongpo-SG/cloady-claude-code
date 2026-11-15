#!/bin/sh
# Cloady 容器里的轮询器：每 5 分钟去 GitHub 交接仓库看有没有新任务，
# 有就用 Claude Code（经 ccr 路由到免费模型）干掉，干完把结果推回仓库。
# 设计原则：容器随时可能重启，所以状态只认仓库里的文件，不认容器内存；
# 每次只做一个任务，单个任务最多 20 分钟，超时就停并报 blocked。
set -u

REPO="git@github.com:chengcheng-Bj/phjmmc-handoff.git"
DIR="/root/handoff"
WORK="/root/work"
POLL_SECS="${POLL_SECS:-300}"
TASK_TIMEOUT="${TASK_TIMEOUT:-1200}"
LOG="/var/log/poller.log"

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [poller] $*" >> "$LOG"; }

# --- 1. 交接仓库的 deploy key：只认 Cloady 环境变量，不进镜像、不进仓库 ---
mkdir -p /root/.ssh
if [ -n "${HANDOFF_DEPLOY_KEY:-}" ]; then
  printf '%s\n' "$HANDOFF_DEPLOY_KEY" > /root/.ssh/id_handoff
  chmod 600 /root/.ssh/id_handoff
  export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i /root/.ssh/id_handoff"
  log "deploy key 已就位（指纹以 ssh-keygen -lf 为准，不打印私钥）"
else
  log "警告：HANDOFF_DEPLOY_KEY 未设置，轮询器只能空转。请在 Cloady 变量里加上它再重启应用。"
fi
git config --global user.name "claudecode-cloady" 2>/dev/null || true
git config --global user.email "claudecode@phjmmc.local" 2>/dev/null || true
git config --global --add safe.directory "$DIR" 2>/dev/null || true

# --- 2. 心跳：证明桥还活着（只在内容变化时提交，避免空提交刷屏）---
heartbeat() {
  # $1 = 状态 idle|working，$2 = 当前任务（可空）
  mkdir -p "$DIR/handoff"
  NOW="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '{\n  "agent": "claudecode-cloady",\n  "time": "%s",\n  "status": "%s",\n  "task": "%s",\n  "poll_secs": %s\n}\n' "$NOW" "$1" "$2" "$POLL_SECS" > "$DIR/handoff/heartbeat-claudecode.json"
  cd "$DIR" || return 0
  if ! git diff --quiet -- handoff/heartbeat-claudecode.json 2>/dev/null; then
    git add handoff/heartbeat-claudecode.json
    git commit -qm "heartbeat claudecode $NOW ($1)" 2>/dev/null || true
    git push -q origin main 2>/dev/null || log "心跳 push 失败，下一轮重试"
  fi
}

signal() {
  # $1 = kind，$2 = task 名，$3 = note
  NOW="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  F="$DIR/handoff/signals/$(date -u '+%Y-%m-%dT%H%M')-claudecode-$1.json"
  mkdir -p "$DIR/handoff/signals"
  printf '{\n  "from": "claudecode-cloady",\n  "to": "muse",\n  "kind": "%s",\n  "time": "%s",\n  "task": "%s",\n  "note": "%s"\n}\n' "$1" "$NOW" "$2" "$3" > "$F"
  cd "$DIR" || return 0
  git add "$F" 2>/dev/null
  git commit -qm "signal claudecode $1 $2" 2>/dev/null || true
  git push -q origin main 2>/dev/null || log "信号 push 失败：$1 $2"
}

# --- 3. 主循环 ---
while true; do
  if [ -z "${HANDOFF_DEPLOY_KEY:-}" ]; then
    sleep "$POLL_SECS"; continue
  fi

  if [ ! -d "$DIR/.git" ]; then
    rm -rf "$DIR"
    git clone -q "$REPO" "$DIR" 2>>"$LOG" || { log "clone 失败，下一轮重试"; sleep "$POLL_SECS"; continue; }
    log "交接仓库已 clone"
  fi
  cd "$DIR" || { sleep "$POLL_SECS"; continue; }
  git pull -q --ff-only origin main 2>>"$LOG" || { log "pull 失败，下一轮重试"; sleep "$POLL_SECS"; continue; }

  TASK=""
  for f in handoff/inbox-claudecode/tasks/*.md; do
    [ -f "$f" ] || continue
    if grep -q '^status: new' "$f" 2>/dev/null; then TASK="$f"; break; fi
  done

  if [ -z "$TASK" ]; then
    heartbeat idle ""
    sleep "$POLL_SECS"; continue
  fi

  NAME="$(basename "$TASK" .md)"
  log "接到任务：$NAME"
  # 认领：先把状态改成 claimed 并推上去，避免重复接单
  sed -i 's/^status: new/status: claimed/' "$TASK"
  git add "$TASK"; git commit -qm "claudecode claimed $NAME" 2>/dev/null || true
  git push -q origin main 2>/dev/null || log "认领 push 失败，继续干活（结果提交时再试）"
  heartbeat working "$NAME"

  mkdir -p "$WORK/$NAME" "$DIR/handoff/inbox-claudecode/out/$NAME"
  # 任务文件正文（去掉 status 行）就是给 Claude Code 的提示词
  grep -v '^status: ' "$TASK" > "$WORK/$NAME/PROMPT.md"
  PROMPT="$(cat "$WORK/$NAME/PROMPT.md")"

  cd "$WORK/$NAME" || { sleep "$POLL_SECS"; continue; }
  START="$(date +%s)"
  # -p 非交互模式；--dangerously-skip-permissions 只限这个一次性容器，
  # 容器里没有任何生产密钥之外的东西，产物只写进工作目录
  timeout "$TASK_TIMEOUT" ccr code -p --dangerously-skip-permissions "$PROMPT" > "$WORK/$NAME/run.log" 2>&1
  RC=$?
  END="$(date +%s)"
  MINS=$(( (END - START) / 60 ))

  cd "$DIR" || { sleep "$POLL_SECS"; continue; }
  OUT="handoff/inbox-claudecode/out/$NAME"
  cp "$WORK/$NAME/run.log" "$OUT/run.log" 2>/dev/null || true
  if [ "$RC" -eq 0 ]; then
    printf 'status: done\ntook_minutes: %s\n' "$MINS" > "$OUT/DONE.md"
    sed -i 's/^status: claimed/status: done/' "$TASK"
    git add "$TASK" "$OUT" 2>/dev/null
    git commit -qm "claudecode done $NAME (${MINS}m)" 2>/dev/null || true
    git push -q origin main 2>/dev/null || log "结果 push 失败，下一轮重试"
    signal build-done "$NAME" "已完成，用时约 ${MINS} 分钟，结果在 $OUT"
    log "任务完成：$NAME（${MINS} 分钟）"
  else
    printf 'status: failed\ntook_minutes: %s\nexit_code: %s\nsee: run.log\n' "$MINS" "$RC" > "$OUT/FAILED.md"
    sed -i 's/^status: claimed/status: failed/' "$TASK"
    git add "$TASK" "$OUT" 2>/dev/null
    git commit -qm "claudecode failed $NAME rc=$RC" 2>/dev/null || true
    git push -q origin main 2>/dev/null || true
    signal blocked "$NAME" "执行失败，退出码 $RC，详见 $OUT/run.log，需 Michael 定夺"
    log "任务失败：$NAME（退出码 $RC）"
  fi
  heartbeat idle ""
  sleep 5
done
