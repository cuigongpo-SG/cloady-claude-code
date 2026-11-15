# 桥：Muse ↔ Cloady Claude Code

## 这是什么

一座很小的桥，让 Muse 能指挥 Cloady 容器里的 Claude Code 干活，
不用人肉在中间传文件。原理和 Muse↔WorkBuddy 的 GitHub 交接仓库一样：
双方只认仓库里的文件，Muse 写任务、容器轮询接活、干完把结果推回仓库。

```
Muse --写任务--> GitHub 私有仓 phjmmc-handoff
                     (handoff/inbox-claudecode/tasks/*.md)
Cloady 容器 --每 5 分钟拉一次--> 有新任务就用 ccr code -p 干掉
                     --结果--> handoff/inbox-claudecode/out/<任务名>/
                     --信号--> handoff/signals/*-claudecode-build-done.json
Muse --每 30 分钟拉一次--> 收到结果就核验、打包、交给 Codex 复核
```

## 文件说明

| 文件 | 作用 |
|---|---|
| `bridge/poller.sh` | 轮询器：拉仓库、认领任务、跑 `ccr code -p`、推结果、写心跳 |
| `bridge/entrypoint.sh` | 容器启动入口（替换原版）：先起轮询器后台，再起 ttyd 网页终端 |
| `Dockerfile` 改动 | 加 `openssh-client`（git 走 ssh 需要）、`jq`；`COPY bridge/ /root/bridge/` |
| `HANDOFF_DEPLOY_KEY` | Cloady 环境变量：交接仓库的 deploy key **私钥**（只放变量，不进镜像、不进仓库） |

## 部署步骤（Cloady 侧）

1. 把 `bridge/` 里的三个文件放进部署仓库 `cuigongpo-SG/cloady-claude-code`：
   `poller.sh` → `bridge/poller.sh`，`entrypoint.sh` → 替换仓库根目录的
   `entrypoint.sh`，`Dockerfile` 按下面改。
2. `Dockerfile` 改两处：在 `apt-get install` 里加 `openssh-client jq`；
   在 `COPY entrypoint.sh` 附近加 `COPY bridge/ /root/bridge/` 和
   `RUN chmod +x /root/bridge/poller.sh /entrypoint.sh`。
3. 在 Cloady 应用变量里加 `HANDOFF_DEPLOY_KEY`，值是这把新 deploy key 的
   **私钥全文**（ed25519，指纹 SHA256:mWVd1wx3U1rMatDwtTBcb2TwQxx0TUKi2A4GH32Xc94，
   公钥要以 deploy key 形式加到 `chengcheng-Bj/phjmmc-handoff` 仓库的
   Settings → Deploy keys，标题 `cloady-claude-code`，勾选 Allow write access）。
4. 在 Cloady 里重新部署应用。启动后轮询器自己起来，不用进终端手动开。
5. 验证桥通了的标志：仓库里出现 `handoff/heartbeat-claudecode.json`，
   且 `status` 在 `idle` 和 `working` 之间变化；容器里
   `/var/log/poller.log` 有“接到任务/任务完成”的记录。

## 安全说明（实话）

- 这把 key 只对 `phjmmc-handoff` 这一个私有仓库有读写权限，别处用不了；
  丢了就在 GitHub 上删掉 deploy key、换一把，仓库本身不受影响。
- 私钥只存在两处：Muse 这边的工作区（`cloady-bridge/keys/`，不进任何仓库）
  和 Cloady 的环境变量。不要贴进聊天、不要写进仓库文件、不要放进任务文件。
- 轮询器跑 Claude Code 时用了 `--dangerously-skip-permissions`，只限这个
  一次性容器：容器里没有任何生产密钥之外的东西，产物只写工作目录，
  且每次任务限时 20 分钟、一次只做一个。不要把这面旗子用到笔记本上。
- 免费模型的内容可能被拿去训练（Gemini 免费档、OpenRouter 免费款均如此），
  涉密代码、真实客户数据不要放进交给容器的任务。
- 免费档 0.5 核/1G 内存、会不定期重启：大活必须拆小段，每段干完立刻提交，
  重启了下一轮接着干，不要指望一口气跑完。

## 任务协议（Muse 侧怎么写任务）

- 任务文件放在 `handoff/inbox-claudecode/tasks/<任务名>.md`，第一行必须是
  `status: new`，后面写给 Claude Code 的提示词正文。
- 任务要小、要具体、要写清产物放在哪里：产物统一写进
  `handoff/inbox-claudecode/out/<任务名>/`，并附一个 `DONE.md`（做了什么、
  花了多久、用的哪个模型）。
- 容器认领后会把 `status: new` 改成 `claimed`，做完改成 `done`（失败改
  `failed`），并回一个 `signals/` 信号。Muse 只读容器的 out 和信号，
  不改容器写过的文件。
- 卡住了（缺信息、缺权限、数字核不到）容器会发 kind=blocked 的信号，
  等 Michael 定，不要自己编。

## 小试任务（第一次）

`handoff/inbox-claudecode/tasks/2026-11-14-bridge-test.md`：
做一个单页静态页面证明桥通了。产物 `out/2026-11-14-bridge-test/`，
Muse 收到后核验、打包成 zip 交 Michael 下载，再由 Codex 复核。
