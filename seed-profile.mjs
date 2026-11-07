#!/usr/bin/env node
// seed-profile.mjs —— 保证 Claude Code Router v3 里存在名叫 "code" 的 profile。
//
// 背景：CCR v3 把运行配置存在 SQLite 里（~/.claude-code-router/config.sqlite，
// app_config 表 key="default" 的 value_json），旧版 JSON 配置只在还没有 SQLite
// 配置时被读一次用作迁移，且迁移不出名叫 code 的 profile。所以这里直接往
// SQLite 里写 profile，容器每次启动都幂等地执行一次。
//
// 行为：
//  * config.sqlite 还没有初始化时（全新容器），短暂跑一次 `ccr serve`，让 CCR 自己
//    建库并把 router-config.json 里的供应商迁移进去，确认 app_config 行已写入
//    再停掉它；
//  * 在 profile.profiles 最前面 upsert 一个全局、已启用的 claude-code profile
//    "code"（CCR 加载时每种 Agent 只保留第一个已启用的全局 profile，放最前
//    才能保证 code 不被别的全局 profile 顶掉）；
//  * model / opusModel / sonnetModel / haikuModel / fableModel / smallFastModel
//    全部指向 gemini/gemini-3.5-flash；
//  * 全局 Router.fallback 设为 model-chain，备用模型为
//    openrouter/cohere/north-mini-code:free；
//  * 若已存在旧的单配置 profile.claudeCode，把它的模型字段同步为同一模型；
//  * 只改上述字段，其余配置（供应商、密钥、其他 profile）原样保留；
//  * 成功返回 0，失败在 stderr 打印原因并返回非 0。entrypoint 把失败当作
//    非致命警告处理，不阻塞 ttyd 启动。
//
// 依赖 ccr 自带的 better-sqlite3（随 @musistudio/claude-code-router 全局安装
// 一起装好），不需要额外装包。需要 Node 22+。

import { spawn, execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

const PROFILE_NAME = "code";
const PRIMARY_MODEL = "gemini/gemini-3.5-flash";
const FALLBACK_MODEL = "openrouter/cohere/north-mini-code:free";
// 种子 profile 的固定 id（UUID v4 形式）。重复运行时复用同一条 profile；
// 如果用户已在管理界面建过名叫 code 的 profile，则保留它原来的 id。
const SEEDED_PROFILE_ID = "7e4b8f2a-1c3d-4e5f-9a6b-2c8d3e5f7a91";

// 与 CCR v3.1.3 保持一致：非 Windows 下配置目录为 $HOME/.claude-code-router
//（可用 CCR_INTERNAL_HOME_DIR 覆盖）；config.sqlite 就在该目录下。
const CONFIG_DIR =
  process.env.CCR_CONFIG_DIR ??
  path.join(process.env.CCR_INTERNAL_HOME_DIR ?? homedir(), ".claude-code-router");
const DB_PATH = path.join(CONFIG_DIR, "config.sqlite");

function log(message) {
  console.log(`[seed-profile] ${message}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// 从全局安装的 ccr 包自带的 node_modules 里加载 better-sqlite3。
function loadBetterSqlite3() {
  const require = createRequire(import.meta.url);
  const candidates = [];
  try {
    const globalRoot = execFileSync("npm", ["root", "-g"], { encoding: "utf8" }).trim();
    candidates.push(
      path.join(globalRoot, "@musistudio", "claude-code-router", "node_modules", "better-sqlite3"),
    );
  } catch {
    // npm 不可用时继续试下面的固定路径。
  }
  candidates.push(
    "/usr/local/lib/node_modules/@musistudio/claude-code-router/node_modules/better-sqlite3",
    "/usr/lib/node_modules/@musistudio/claude-code-router/node_modules/better-sqlite3",
  );
  for (const candidate of candidates) {
    try {
      const loaded = require(candidate);
      log(`using better-sqlite3 from ${candidate}`);
      return loaded;
    } catch {
      // 换下一个候选路径。
    }
  }
  throw new Error(
    "could not load better-sqlite3 (expected it under the global @musistudio/claude-code-router install)",
  );
}

// 只读试读 app_config 行：库还没建好、表还不存在或正被写时返回 null，调用方重试。
function tryReadAppConfigRow(Database) {
  let db = null;
  try {
    db = new Database(DB_PATH, { readonly: true });
    db.pragma("busy_timeout = 2000");
    const row = db.prepare("SELECT value_json FROM app_config WHERE key = 'default'").get();
    return row ?? null;
  } catch {
    return null;
  } finally {
    try {
      db?.close();
    } catch {
      // 忽略关闭时的错误。
    }
  }
}

// 让 CCR 自己初始化 config.sqlite：短暂跑 `ccr serve`，等 app_config 行出现
// 就停掉它。这样首次启动的 legacy JSON 迁移也由 CCR 官方逻辑完成。
async function bootstrapConfigDatabase(Database) {
  if (tryReadAppConfigRow(Database)) return;
  log(`config database not initialised at ${DB_PATH}; starting 'ccr serve' briefly so CCR can initialise it`);
  mkdirSync(CONFIG_DIR, { recursive: true });
  const child = spawn("ccr", ["serve"], { stdio: "ignore", detached: true });
  let spawnFailed = false;
  child.on("error", (error) => {
    spawnFailed = true;
    log(`failed to start 'ccr serve': ${error.message}`);
  });
  const deadline = Date.now() + 60_000;
  try {
    while (Date.now() < deadline) {
      if (tryReadAppConfigRow(Database)) {
        log("config database initialised by 'ccr serve'");
        return;
      }
      if (spawnFailed || child.exitCode !== null) break;
      await sleep(500);
    }
  } finally {
    try {
      process.kill(-child.pid, "SIGTERM");
    } catch {
      try {
        child.kill("SIGTERM");
      } catch {
        // 进程已退出。
      }
    }
    await sleep(500);
    try {
      process.kill(-child.pid, "SIGKILL");
    } catch {
      // 进程已退出。
    }
  }
  if (!tryReadAppConfigRow(Database)) {
    throw new Error(`config database was not initialised at ${DB_PATH} within 60s`);
  }
}

function readAppConfig(db) {
  const row = db.prepare("SELECT value_json FROM app_config WHERE key = 'default'").get();
  if (!row) return null;
  return JSON.parse(row.value_json);
}

function upsertCodeProfile(config) {
  if (!config || typeof config !== "object") {
    throw new Error("stored app config is not an object");
  }
  config.profile ??= {};
  if (!Array.isArray(config.profile.profiles)) config.profile.profiles = [];
  config.profile.enabled = true;

  const profiles = config.profile.profiles;
  const existingIndex = profiles.findIndex(
    (p) => p && typeof p === "object" && p.name === PROFILE_NAME,
  );
  const existing = existingIndex >= 0 ? profiles[existingIndex] : null;
  if (existingIndex >= 0) profiles.splice(existingIndex, 1);

  const codeProfile = {
    ...(existing ?? {}),
    id: existing?.id ?? SEEDED_PROFILE_ID,
    name: PROFILE_NAME,
    agent: "claude-code",
    enabled: true,
    scope: "global",
    surface: "auto",
    model: PRIMARY_MODEL,
    opusModel: PRIMARY_MODEL,
    sonnetModel: PRIMARY_MODEL,
    haikuModel: PRIMARY_MODEL,
    fableModel: PRIMARY_MODEL,
    smallFastModel: PRIMARY_MODEL,
    availableModels: [PRIMARY_MODEL],
  };
  // 放最前面：CCR 加载时每种 Agent 只保留第一个已启用的全局 profile。
  profiles.unshift(codeProfile);

  // 旧的单配置（管理界面展示的默认 Claude Code 配置）如果存在，也同步模型。
  const legacy = config.profile.claudeCode;
  if (legacy && typeof legacy === "object") {
    legacy.enabled = true;
    legacy.model = PRIMARY_MODEL;
    legacy.opusModel = PRIMARY_MODEL;
    legacy.sonnetModel = PRIMARY_MODEL;
    legacy.haikuModel = PRIMARY_MODEL;
    legacy.fableModel = PRIMARY_MODEL;
    legacy.smallFastModel = PRIMARY_MODEL;
  }

  // 全局回退：主模型失败时按模型链重试备用模型。
  config.Router ??= {};
  config.Router.fallback = {
    mode: "model-chain",
    models: [FALLBACK_MODEL],
    retryCount: 1,
  };
  return codeProfile;
}

async function main() {
  const Database = loadBetterSqlite3();
  await bootstrapConfigDatabase(Database);
  const db = new Database(DB_PATH);
  try {
    db.pragma("busy_timeout = 5000");
    const config = readAppConfig(db);
    if (!config) {
      throw new Error(
        "config database has no app_config row with key 'default' yet; start the router once and retry",
      );
    }
    upsertCodeProfile(config);
    db.prepare(
      `INSERT INTO app_config (key, value_json, updated_at) VALUES ('default', ?, ?)
       ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json, updated_at = excluded.updated_at`,
    ).run(JSON.stringify(config), Date.now());
    // 写完再读一次做校验。
    const saved = readAppConfig(db);
    const savedProfile = saved?.profile?.profiles?.find((p) => p?.name === PROFILE_NAME);
    if (!savedProfile || savedProfile.model !== PRIMARY_MODEL) {
      throw new Error("verification failed: 'code' profile was not persisted as expected");
    }
    log(
      `profile '${PROFILE_NAME}' ready (id ${savedProfile.id}, model ${savedProfile.model}, fallback ${FALLBACK_MODEL})`,
    );
  } finally {
    db.close();
  }
}

main().catch((error) => {
  console.error(`[seed-profile] ERROR: ${error?.message ?? String(error)}`);
  process.exit(1);
});
