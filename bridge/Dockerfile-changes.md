# Dockerfile 改动（对仓库 cuigongpo-SG/cloady-claude-code 的 Dockerfile）

只改两处，其余不动：

## 1. apt-get install 里加两个包

原来：

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates procps \
```

改成：

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates procps openssh-client jq \
```

原因：轮询器用 git 走 ssh 拉私有仓库，需要 `ssh` 客户端；
`jq` 备用（目前心跳用 printf 手写 JSON，留着以后用）。

## 2. 复制桥的文件并加执行权限

在 `COPY entrypoint.sh /entrypoint.sh` 那两行附近加：

```
COPY bridge/ /root/bridge/
RUN chmod +x /root/bridge/poller.sh /entrypoint.sh
```

注意：`bridge/` 目录要先放进仓库根目录（`bridge/poller.sh`、
`bridge/entrypoint.sh`），`entrypoint.sh` 本身用桥接版替换仓库根目录原版。
