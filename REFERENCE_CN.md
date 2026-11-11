# Stoker 参考文档

[English](REFERENCE.md) · [中文](REFERENCE_CN.md)

这里是 [README](README_CN.md) 背后的细节：所有设置、所有命令、日志文件、App 显示的健康状态，以及一次运行的流程。

- [配置](#配置)
- [命令](#命令)
- [日志](#日志)
- [健康状态](#健康状态)
- [一次运行的流程](#一次运行的流程)
- [Stoker 在哪里运行](#stoker-在哪里运行)
- [激活如何保持精简](#激活如何保持精简)
- [Codex 自动更新与模型回退](#codex-自动更新与模型回退)

## 配置

设置都在 `.env` 里。先把 `.env.example` 复制一份开始。没写的变量会使用默认值，所以手写的 `.env` 可以很短。

菜单栏 App 只把它管理的设置写回同一个 `.env`，其他键和注释都原样保留。独立的 `Stoker.app`（不是从克隆目录启动的）有自己的一份引擎和 `.env`，放在 `~/Library/Application Support/Stoker/stoker`。如果你同时用克隆目录和独立 App，请修改已加载的定时所属的那一份。两份不一致时，App 会提醒你。

在终端里先 `export` 的变量，会覆盖 `.env` 里的同名变量。

### 定时

| 变量 | 作用 | 默认值 |
| --- | --- | --- |
| `CLAUDE_SCHEDULE_TIMES` | Claude 的时间，逗号分隔的 `HH:MM` | `SCHEDULE_TIMES` |
| `CODEX_SCHEDULE_TIMES` | Codex 的时间 | `SCHEDULE_TIMES` |
| `CLAUDE_SCHEDULE_DAYS` | Claude 的星期：`mon,tue,wed,thu,fri,sat,sun` 中任选。留空或写 `daily` 表示每天 | 每天 |
| `CODEX_SCHEDULE_DAYS` | Codex 的星期，格式相同 | 每天 |
| `SCHEDULE_TIMES` | 工具自己的时间未设置或为空时，使用这组时间 | `07:00,12:00,17:00,22:00` |
| `ACTIVATION_TOOL` | 为哪些工具设置定时：`all`、`claude` 或 `codex` | `all` |
| `LABEL` | LaunchAgent 的基础名称。每个工具分别得到 `<LABEL>.claude` 或 `<LABEL>.codex` | `com.stoker.ai-window` |
| `LEGACY_LABELS` | 安装时要移除的旧 agent 名称，避免重复触发 | `com.activation-timer.ai-window` |

时间按 macOS 本地时间计算，每个时间点各自触发。`daily` 不能和星期名称混用。手动修改其中任何一项后，要重新运行 `./install.sh install`。如果某个工具已经不在 `ACTIVATION_TOOL` 里，它的定时运行会直接退出，不发送任何内容。

### Claude

| 变量 | 作用 | 默认值 |
| --- | --- | --- |
| `ACTIVATION_PROMPT` | 发给 Claude 的提示词 | `Reply exactly READY...` |
| `CLAUDE_CODE_OAUTH_TOKEN` | 由 `claude setup-token` 生成的长效令牌，供定时运行使用 | 未设置（使用钥匙串里的登录） |
| `CLAUDE_STATUS_SOURCE` | Claude 额度从哪里读取：`cache`、`native` 或 `omc`。见下文 | `cache` |
| `CLAUDE_USAGE_CACHE_FILE` | `cache` 读取的用量缓存路径 | `~/.claude/plugins/oh-my-claudecode/.usage-cache-anthropic.json` |
| `CLAUDE_ACCOUNT_FILE` | Claude Code 配置文件的路径，用来标注你的套餐 | `~/.claude.json` 或 `$CLAUDE_CONFIG_DIR/.claude.json` |
| `CLAUDE_USAGE_USER_AGENT` | `native` 用量请求使用的 User-Agent | `claude-code/0.4.0` |
| `CLAUDE_BIN` | `claude` 可执行文件的路径 | 自动查找 |

`CLAUDE_STATUS_SOURCE` 有三个取值：

- `cache` 读取 oh-my-claudecode 插件的本地用量缓存。它不接触任何凭证。
- `native` 用钥匙串里的令牌直接查询用量 API，只读。它不需要插件。它从不刷新令牌。令牌过期时，它会跳过这次额度快照。
- `omc` 执行一次实时的 `omc wait status` 查询。在定时运行里，这可能让你平时在终端里登录的 Claude Code 掉登录，所以只为旧配置保留。

Stoker 从 `CLAUDE_ACCOUNT_FILE` 里只读取三项：套餐名、限额档位，以及是否开启了额外用量。你的邮箱、姓名和账号 id 从不会被复制。这个文件是 Claude Code 缓存的账户资料，换套餐后可能滞后。套餐名只用于显示。

### Codex

| 变量 | 作用 | 默认值 |
| --- | --- | --- |
| `CODEX_MODEL` | Codex 激活用的模型。设为 `default` 则由 Codex CLI 自己选 | `gpt-5.6-luna` |
| `CODEX_ACTIVATION_PROMPT` | 发给 Codex 的提示词，只要求读取文件 | `Read only ./probe.py...` |
| `CODEX_WORK_DIR` | Codex 运行所在的小目录 | `<stoker>/codex-probe` |
| `CODEX_ACTIVATE_ONLY_WHEN_IDLE` | `1` 表示窗口已在计时就跳过 Codex。`0` 表示每次都发送 | `1` |
| `CODEX_RESET_WAIT_MAX_SECONDS` | 窗口在这么多秒内就会重置时，等它重置再发送，不跳过。`0` 表示从不等待 | `300` |
| `CODEX_AUTO_UPDATE` | `1` 表示在真实的 Codex 激活前运行 `codex update` | `1` |
| `CODEX_AUTO_UPDATE_INTERVAL_HOURS` | 两次更新尝试之间至少间隔的小时数 | `24` |
| `CODEX_UPDATE_TIMEOUT_SECONDS` | `codex update` 的时间上限 | `180` |
| `CODEX_MODEL_FALLBACK` | `1` 表示 Codex 拒绝所配置的模型时，换一个模型再试 | `1` |
| `CODEX_MODEL_FALLBACK_MAX_TRIES` | 每次运行最多的回退次数 | `3` |
| `CODEX_MODELS_CACHE` | 挑选回退模型时使用的 Codex 模型列表 | `~/.codex/models_cache.json` |
| `CODEX_STATUS_SOURCE` | Codex 额度从哪里读取：`app-server` 或 `native`。见下文 | `app-server` |
| `CODEX_AUTH_FILE` | `native` 读取的 Codex 登录文件 | `~/.codex/auth.json` |
| `CODEX_USAGE_API_URL` | `native` 使用的用量接口 | `https://chatgpt.com/backend-api/wham/usage` |
| `CODEX_USAGE_USER_AGENT` | `native` 请求使用的 User-Agent | `codex_cli_rs/<ver> (darwin)` |
| `CODEX_BIN` | `codex` 可执行文件的路径 | 自动查找 |

`CODEX_ACTIVATE_ONLY_WHEN_IDLE` 看的是你的套餐里最短的那个窗口。有 5 小时窗口就看它，否则看周窗口。这个窗口已在计时的时候，激活不会开启任何新窗口，所以会被跳过，原因记为 `window_already_active`。这个设置需要 `ENABLE_QUOTA_PREFLIGHT=1`。

`CODEX_RESET_WAIT_MAX_SECONDS` 只处理一种边界情况。上一次激活是在定时时间之后几秒才开启窗口的。如果每 5 小时激活一次，下一次激活就会在这个窗口重置前几秒到来。这时 Stoker 会等到重置后约 5 秒再发送，原因记为 `window_resets_soon`。额度已用尽的窗口仍会被跳过。

`CODEX_STATUS_SOURCE` 有两个取值：

- `app-server` 启动 `codex app-server` 并向它查询。它需要 Node.js 和 Codex CLI。
- `native` 用 `~/.codex/auth.json` 里的令牌直接读取 ChatGPT 用量接口，只读。它从不刷新令牌。在支持的情况下，它还会显示你的套餐和 credits 余额。

### 额度检查

| 变量 | 作用 | 默认值 |
| --- | --- | --- |
| `ENABLE_QUOTA_PREFLIGHT` | 发送激活前先检查额度 | `1` |
| `QUOTA_PREFLIGHT_ON_UNKNOWN` | 读不到额度时怎么办：`allow` 或 `skip` | `allow` |
| `QUOTA_EXHAUSTED_THRESHOLD_PERCENT` | 剩余额度低于或等于这个百分比时跳过 | `0` |
| `ENABLE_STATUS_SNAPSHOTS` | 真实运行后再记录一次额度 | `1` |

### 运行控制与路径

| 变量 | 作用 | 默认值 |
| --- | --- | --- |
| `TIMEOUT_SECONDS` | 每个工具的时间上限 | `120` |
| `LOCK_WAIT_SECONDS` | 一次运行等待另一次运行结束的最长时间，超时就放弃。`0` 表示立刻放弃 | `1085` |
| `KEEP_AWAKE_MODE` | `off`、`during`（运行期间保持唤醒）或 `always`（App 打开期间也保持唤醒） | `off` |
| `KEEP_AWAKE_SECONDS` | 单次运行最长的保持唤醒时间 | `900` |
| `JQ_BIN`、`NODE_BIN`、`OMC_BIN` | 这些可执行文件的路径 | 自动查找 |
| `PATH_VALUE` | launchd 和运行脚本使用的 `PATH` | Homebrew、本地和系统路径 |

`LOCK_WAIT_SECONDS` 的默认值足够覆盖最慢的一次 Codex 运行：`TIMEOUT_SECONDS × (1 + CODEX_MODEL_FALLBACK_MAX_TRIES) + CODEX_UPDATE_TIMEOUT_SECONDS + CODEX_RESET_WAIT_MAX_SECONDS + 5 + 120`。开启保持唤醒时，一次运行最多保持唤醒 `KEEP_AWAKE_SECONDS + LOCK_WAIT_SECONDS + CODEX_RESET_WAIT_MAX_SECONDS + 5` 秒。

`KEEP_AWAKE_MODE` 使用 `caffeinate`。它能阻止 Mac 在运行期间睡眠，但不能唤醒已经睡眠的 Mac。唤醒后，`launchd` 只补跑一次错过的任务，不会每个错过的时间都跑一次。Stoker 也不会替你配置 `pmset`。

## 命令

| 命令 | 作用 | 会发送激活吗？ |
| --- | --- | :---: |
| `./install.sh install` | 写入并加载 LaunchAgent。这是默认命令 | 否 |
| `./install.sh uninstall` | 卸载并删除 LaunchAgent | 否 |
| `./install.sh status` | 显示 launchd 状态 | 否 |
| `./install.sh check` | 检查必需的工具是否已安装 | 否 |
| `./install.sh dry-run` | 打印一次运行会用到的完整命令 | 否 |
| `./install.sh quota` | 把当前额度记录到 `logs/status.jsonl` | 否 |
| `./install.sh recommend` | 显示检测到的用量窗口，以及适合它们的运行时间 | 否 |
| `./install.sh app-status` | 打印 App 读取的 JSON 状态 | 否 |
| `./install.sh print-plist` | 打印生成的 plist。加上 `claude` 或 `codex` 只打印一个 | 否 |
| `./install.sh run-now` | 立刻给每个启用的工具发送一次激活 | **是** |

`run-now` 启动的是已安装的 LaunchAgent，所以要先运行 `install`。如果有一次运行正在进行，`run-now` 会把它重新启动。

也可以直接调用运行脚本：

```sh
./bin/activate-ai-window.sh --once                # 一次真实运行，所有启用的工具
./bin/activate-ai-window.sh --once --tool claude  # 只运行一个工具
./bin/activate-ai-window.sh --status              # 只查额度
```

## 日志

| 文件 | 内容 |
| --- | --- |
| `logs/activation.log` | 纯文本的运行记录 |
| `logs/usage.jsonl` | 每个工具每次运行一条记录：token、费用、模型、耗时，或跳过原因 |
| `logs/status.jsonl` | 每次额度检查一条记录，包含套餐上报的用量窗口 |
| `logs/raw/` | CLI 的原始输出，用于排查问题 |
| `logs/launchd.out.log`、`logs/launchd.err.log` | launchd 捕获的输出 |

一次正常运行在 `activation.log` 里是这样的：

```text
Activation run started ...
Quota preflight started
Claude job started
Codex job started
Activation run finished exit=0
```

某个工具被跳过时：

```text
claude job skipped by quota preflight reason=quota_exhausted
```

在 `usage.jsonl` 里，成功的运行有 `ok: true`、`result: READY` 和 `exit_code: 0`。被跳过的运行有 `skipped: true` 和 `skip_reason`。

## 健康状态

App 里每张工具卡片的底部都有一行健康状态。各状态按表中顺序判断。

**Claude**

| 状态 | 显示为 | 条件 |
| --- | --- | --- |
| `disabled` | 「未启用」 | `ACTIVATION_TOOL` 不包含 Claude |
| `unknown` | 「暂无运行」 | 还没有记录到任何真实运行 |
| `alert` | 「连续 N 次失败」或「激活异常」 | 连续两次或更多真实运行失败。或者定时已开启，但最近 24 小时里既没有成功运行，也没有额度跳过 |
| `warning` | 「最近一次失败」 | 最近一次真实运行失败 |
| `ok` | 「激活正常」 | 最近一次真实运行成功 |

**Codex**

| 状态 | 显示为 | 条件 |
| --- | --- | --- |
| `disabled` | 「未启用」 | `ACTIVATION_TOOL` 不包含 Codex |
| `alert` | 「连续 N 次失败」或「激活异常」 | 连续两次或更多真实运行失败 |
| `warning` | 「最近一次失败」 | 最近一次真实运行失败 |
| `exhausted` | 「本周额度用尽」或「5 小时额度用尽」 | 某个窗口的剩余额度低于或等于 `QUOTA_EXHAUSTED_THRESHOLD_PERCENT`，并且还没重置 |
| `anchored` | 「本周已锚定」或「本 5 小时已锚定」 | 决定 Codex 是否跳过的那个窗口（有 5 小时窗口就看它，否则看周窗口）已在计时 |
| `pending` | 「待锚定」 | 窗口空闲、已经重置，或读不到额度 |

真实运行指的是发送了激活的运行。被跳过的运行不算失败。额度跳过还能证明定时仍在工作。未启用的工具从不告警。

Codex 的「下次激活」时间，只有在引擎确实会一直跳过到那时，才会推到窗口重置之后。具体是两种情况：开启 `ENABLE_QUOTA_PREFLIGHT=1` 时窗口额度已用尽；或者在此基础上还开启了 `CODEX_ACTIVATE_ONLY_WHEN_IDLE=1`，并且窗口正在计时。其他情况下，它就是下一个定时时间。

只要有一个工具处于 `alert`，菜单栏的火苗图标上就会显示一个小红点。它每 10 分钟重新检查一次，每次定时运行后不久也会检查。即使 App 主窗口关着也照常检查。

## 一次运行的流程

`launchd` 在每个定时时间启动一次运行。`./install.sh run-now` 会手动启动同样的运行。

1. **加载配置。** 读取 `.env`。
2. **加锁。** 创建 `run/activation.lock`，保证两次运行不会重叠。Claude 和 Codex 可能在同一秒触发，所以后到的那次运行会等待。它每 2 秒检查一次，最多等 `LOCK_WAIT_SECONDS`。到时锁仍被占用，这次运行就正常退出。锁里记录了持有者的进程 id，所以崩溃的运行留下的锁会被接管。`dry-run` 从不加锁。
3. **检查额度。** 额度已用尽的工具会被跳过，跳过会记到 `logs/usage.jsonl`。重置时间已经过去的窗口不算用尽。Claude 按模型划分的周限额，只有在它是当前生效的限额时才计入。Codex 的窗口已在计时的时候，Codex 也会被跳过。读不到额度时，由 `QUOTA_PREFLIGHT_ON_UNKNOWN` 决定。
4. **发送激活。** Claude 回复 `READY`。Codex 读取 `codex-probe/` 里的一个小文件。
5. **记录用量。** 解析每个 CLI 的输出，往 `logs/usage.jsonl` 追加一条记录。
6. **再记录一次额度。** 往 `logs/status.jsonl` 追加一次额度快照。
7. **释放锁。**

每次 CLI 调用都有时间上限（`TIMEOUT_SECONDS`）。卡住的调用会先收到 SIGTERM，两秒后再收到 SIGKILL。

### App 做了什么

App 自己不负责定时，也没有激活逻辑。它运行同一套脚本，再读取脚本的输出：

| App 里的操作 | 脚本 |
| --- | --- |
| 读取状态 | `install.sh app-status` |
| 开启或关闭定时 | `install.sh install` 或 `install.sh uninstall` |
| 保存设置 | 写入 `.env`，然后运行 `install.sh install` |
| 运行一次 | `install.sh run-now` |

## Stoker 在哪里运行

两个 CLI 都在 Stoker 自己的目录里运行。这个目录里只有脚本和日志，没有什么可供它们扫描或修改。

| 安装方式 | 目录 |
| --- | --- |
| `git clone` | 克隆目录，例如 `~/stoker` |
| 从克隆目录构建的 App | 同一个克隆目录 |
| DMG 里的 `Stoker.app` | `~/Library/Application Support/Stoker/stoker/`，首次启动时创建 |

脚本在运行时自己确定所在目录，所以克隆到任何路径都能用。

LaunchAgent 是一个小文件，告诉 macOS `launchd` 什么时候启动某个程序。`install` 会为每个启用的工具，在 `~/Library/LaunchAgents/` 里写入一个 LaunchAgent：`<LABEL>.claude.plist` 和 `<LABEL>.codex.plist`。每个 agent 按自己的时间和星期运行对应的工具。`install` 还会移除你已关闭的工具的 agent，以及旧版本使用的单个 `<LABEL>` agent。

属于另一个 Stoker 目录的 agent 会被保留，并给出警告。安装和卸载时都是如此，旧 agent 和 `<LABEL>.claude` / `<LABEL>.codex` 都适用。Claude 或 Codex 各自的 agent 因此被跳过时，命令会以非零状态退出。设置 `STOKER_FORCE_MIGRATE=1` 可以强制移除。

plist 里包含你这台机器上的路径，所以不会提交到 git。GitHub Actions 只负责校验代码。激活始终在你自己的 Mac 上运行。

```text
stoker/
├── install.sh                  ← 你运行的命令
├── bin/
│   ├── activate-ai-window.sh   ← 执行一次激活
│   └── activation-state.sh     ← 给 App 的状态，以及 `recommend`
├── scripts/
│   └── install-launchd.sh      ← 安装和移除 LaunchAgent
├── app/StokerMenuBar/          ← 菜单栏 App
├── codex-probe/                ← Codex 运行所在的小目录
├── launchd/                    ← 生成的 plist（不提交）
├── logs/                       ← 生成的日志（不提交）
└── .env.example
```

## 激活如何保持精简

一次激活的提示词加回复不到 300 个 token。成本来自每个 CLI 自己附加的内容：指令、插件、工具说明和 hook。这些加起来可能超过 40,000 个 token。Stoker 把它们全部关掉。

**Claude**

| 参数 | 效果 |
| --- | --- |
| `--model haiku` | 最便宜的模型 |
| `--system-prompt "Reply only: READY"` | 最精简的系统提示词 |
| `--setting-sources ""` | 不加载 CLAUDE.md、hook 和插件指令。这一项就省掉约 40K token |
| `--effort low` | 最低推理强度 |
| `--strict-mcp-config --mcp-config '{"mcpServers":{}}'` | 不加载 MCP 服务器，也就没有工具说明 |
| `--tools ""` | 不加载内置工具 |
| `--disable-slash-commands` | 不加载技能 |

结果：按近期记录的运行平均，每次激活约 1.6K 输入 token，≈ $0.0025。不加这些参数时约 40K token、$0.15。按每天 4 次激活算，每月 ≈ $0.30，不加参数则约 $18。

**Codex**

| 参数 | 效果 |
| --- | --- |
| `--ignore-user-config` | 跳过 `~/.codex/config.toml`：不加载插件、MCP 服务器和开发者指令 |
| `--ignore-rules` | 跳过 `.rules` 文件 |
| `--cd "$CODEX_WORK_DIR"` | 让 Codex 留在很小的探针目录里 |
| `--model "$CODEX_MODEL"` | 使用配置的轻量模型 |
| `--sandbox read-only` | Codex 不能写文件 |
| `--ephemeral`、`--skip-git-repo-check` | 不保存会话，不做 git 检查 |
| `-c 'features.memories=false'` | 不用记忆 |
| `-c 'features.multi_agent=false'` | 不用多 agent |
| `-c 'features.goals=false'` | 不用目标 |
| `-c 'features.hooks=false'` | 不用 hook |
| `-c 'features.child_agents_md=false'` | 不加载 AGENTS.md |
| `-c 'model_reasoning_effort="low"'` | 最低推理强度 |

结果：每次激活约 38K 输入 token，其中约 55% 是缓存读取。这个下限由 Codex 自己的系统提示词决定。Codex 激活计入你的套餐额度，没有按美元计的价格。

## Codex 自动更新与模型回退

Codex 经常停用模型、调整套餐。有两个功能让激活持续可用。

**自动更新。** `CODEX_AUTO_UPDATE=1` 是默认值。这时 Stoker 会**不经询问就更新你的 Codex CLI**。想自己管理 Codex 版本，就把它设为 `0`。更新只在真实的 Codex 激活之前运行。被跳过的运行、`dry-run`、`check` 和 `quota` 都不会触发更新。每 `CODEX_AUTO_UPDATE_INTERVAL_HOURS` 小时最多更新一次，时间上限为 `CODEX_UPDATE_TIMEOUT_SECONDS`。更新失败只会记一条警告。用量记录里会多一个 `cli_update` 字段：`{attempted, from, to, exit}`。

**模型回退。** `CODEX_MODEL_FALLBACK=1` 时，如果 Codex 回复「model is not supported」，Stoker 会从 `~/.codex/models_cache.json` 里换一个模型再试，顺序如下：

1. 被拒绝的模型所指定的升级模型，
2. 然后是名称里含 `luna` 的模型，再是 `terra`，再是 `sol`，
3. 最后是其他任何模型。

只有支持低推理强度、并且还没过停用日期的模型才会入选。遇到以下情况 Stoker 就停止：成功、出现其他错误，或者已经尝试了 `CODEX_MODEL_FALLBACK_MAX_TRIES` 次。每次尝试都有自己的用量记录。重试的记录带有 `model_fallback: {from, to, attempt}`。被拒绝后又重试过的那次带有 `superseded_by_fallback: true`，App 不把它算作错误。Stoker 会给出警告，提醒你把 `CODEX_MODEL` 设为成功的那个模型。`.env` 从不会被自动改写。

默认模型是 `gpt-5.6-luna`。之前的默认模型 `gpt-5.4-mini` 已在 2026 年 9 月对 ChatGPT 登录停用。如果你的 `.env` 里还写着已停用的模型，引擎会发出警告并改用 `gpt-5.6-luna`。App 会在你下次保存时更新这个值。
