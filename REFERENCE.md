# Stoker reference

[English](REFERENCE.md) · [中文](REFERENCE_CN.md)

The details behind the [README](README.md): every setting, every command, the log files, the
health states the app shows, and how a run works.

- [Configuration](#configuration)
- [Commands](#commands)
- [Logs](#logs)
- [Health states](#health-states)
- [How a run works](#how-a-run-works)
- [Where Stoker runs](#where-stoker-runs)
- [How check-ins stay small](#how-check-ins-stay-small)
- [Codex updates and model fallback](#codex-updates-and-model-fallback)

## Configuration

Settings live in `.env`. Copy `.env.example` to start. A variable you leave out uses its
default, so a hand-written `.env` can be very short.

The menu bar app writes the settings it manages back to the same `.env` and leaves every
other key and comment alone. A standalone `Stoker.app` (one not started from a clone) keeps
its own engine and `.env` under `~/Library/Application Support/Stoker/stoker`. If you use
both a clone and the standalone app, edit the copy that owns the loaded schedule. The app
warns you when they differ.

A variable you `export` in the terminal first wins over the same variable in `.env`.

### Schedule

| Variable | What it sets | Default |
| --- | --- | --- |
| `CLAUDE_SCHEDULE_TIMES` | Claude's times, as comma-separated `HH:MM` | `SCHEDULE_TIMES` |
| `CODEX_SCHEDULE_TIMES` | Codex's times | `SCHEDULE_TIMES` |
| `CLAUDE_SCHEDULE_DAYS` | Claude's days: any of `mon,tue,wed,thu,fri,sat,sun`. Empty or `daily` means every day | every day |
| `CODEX_SCHEDULE_DAYS` | Codex's days, same format | every day |
| `SCHEDULE_TIMES` | Times for a tool whose own times are unset or empty | `07:00,12:00,17:00,22:00` |
| `ACTIVATION_TOOL` | Which tools are scheduled: `all`, `claude`, or `codex` | `all` |
| `LABEL` | Base name of the LaunchAgents. Each tool gets `<LABEL>.claude` or `<LABEL>.codex` | `com.stoker.ai-window` |
| `LEGACY_LABELS` | Old agent names to remove at install, so they do not fire twice | `com.activation-timer.ai-window` |

Times are local macOS time, and each time fires on its own. `daily` cannot be mixed with day
names. After you change any of these by hand, run `./install.sh install` again. A scheduled
run of a tool that `ACTIVATION_TOOL` no longer enables exits without sending anything.

### Claude

| Variable | What it sets | Default |
| --- | --- | --- |
| `ACTIVATION_PROMPT` | The prompt sent to Claude | `Reply exactly READY...` |
| `CLAUDE_CODE_OAUTH_TOKEN` | Long-lived token from `claude setup-token`, for scheduled runs | unset (uses the Keychain sign-in) |
| `CLAUDE_STATUS_SOURCE` | Where Claude quota comes from: `cache`, `native`, or `omc`. See below | `cache` |
| `CLAUDE_USAGE_CACHE_FILE` | Path of the usage cache read by `cache` | `~/.claude/plugins/oh-my-claudecode/.usage-cache-anthropic.json` |
| `CLAUDE_ACCOUNT_FILE` | Path of Claude Code's config file, used to label your plan | `~/.claude.json`, or `$CLAUDE_CONFIG_DIR/.claude.json` |
| `CLAUDE_USAGE_USER_AGENT` | User-Agent for the `native` usage request | `claude-code/0.4.0` |
| `CLAUDE_BIN` | Path of the `claude` binary | found automatically |

`CLAUDE_STATUS_SOURCE` has three values:

- `cache` reads the oh-my-claudecode plugin's local usage cache. It touches no credentials.
- `native` asks the usage API directly with your Keychain token, read-only. It needs no
  plugin. It never refreshes the token, and skips the snapshot when the token has expired.
- `omc` runs a live `omc wait status` query. In a scheduled run this can sign your
  interactive sessions out, so it is kept only for old setups.

From `CLAUDE_ACCOUNT_FILE` Stoker takes only the plan name, the rate-limit tier, and whether
extra usage is on. Your email, name, and account ids are never copied. The file is Claude
Code's cached profile, so it can lag behind a plan change. The plan name is for display only.

### Codex

| Variable | What it sets | Default |
| --- | --- | --- |
| `CODEX_MODEL` | Model for Codex check-ins. `default` lets the Codex CLI choose | `gpt-5.6-luna` |
| `CODEX_ACTIVATION_PROMPT` | The read-only prompt sent to Codex | `Read only ./probe.py...` |
| `CODEX_WORK_DIR` | The small folder Codex runs in | `<stoker>/codex-probe` |
| `CODEX_ACTIVATE_ONLY_WHEN_IDLE` | `1` skips Codex while its window is already running. `0` always sends | `1` |
| `CODEX_RESET_WAIT_MAX_SECONDS` | Wait for a window that resets within this many seconds, instead of skipping. `0` never waits | `300` |
| `CODEX_AUTO_UPDATE` | `1` runs `codex update` before a real Codex check-in | `1` |
| `CODEX_AUTO_UPDATE_INTERVAL_HOURS` | Minimum hours between update attempts | `24` |
| `CODEX_UPDATE_TIMEOUT_SECONDS` | Time limit for `codex update` | `180` |
| `CODEX_MODEL_FALLBACK` | `1` tries another model when Codex rejects the configured one | `1` |
| `CODEX_MODEL_FALLBACK_MAX_TRIES` | Most fallback attempts per run | `3` |
| `CODEX_MODELS_CACHE` | The Codex model list used to pick a fallback | `~/.codex/models_cache.json` |
| `CODEX_STATUS_SOURCE` | Where Codex quota comes from: `app-server` or `native`. See below | `app-server` |
| `CODEX_AUTH_FILE` | Codex sign-in file read by `native` | `~/.codex/auth.json` |
| `CODEX_USAGE_API_URL` | Usage endpoint for `native` | `https://chatgpt.com/backend-api/wham/usage` |
| `CODEX_USAGE_USER_AGENT` | User-Agent for `native` requests | `codex_cli_rs/<ver> (darwin)` |
| `CODEX_BIN` | Path of the `codex` binary | found automatically |

`CODEX_ACTIVATE_ONLY_WHEN_IDLE` looks at the shortest window your plan has: the 5-hour window
if there is one, otherwise the weekly one. While that window is already running, a check-in
would start nothing, so it is skipped with the reason `window_already_active`. This needs
`ENABLE_QUOTA_PREFLIGHT=1`.

`CODEX_RESET_WAIT_MAX_SECONDS` covers one edge case. The previous check-in opened its window a
few seconds after its scheduled time. With a check-in every five hours, the next one therefore
arrives a few seconds before that window resets. Stoker then waits until about 5 seconds after
the reset and sends, with the reason `window_resets_soon`. A used-up window is still skipped.

`CODEX_STATUS_SOURCE` has two values:

- `app-server` starts `codex app-server` and asks it. It needs Node.js and the Codex CLI.
- `native` reads the ChatGPT usage endpoint directly, read-only, with the token in
  `~/.codex/auth.json`. It never refreshes the token. It also reports your plan and credit
  balance where available.

### Quota checks

| Variable | What it sets | Default |
| --- | --- | --- |
| `ENABLE_QUOTA_PREFLIGHT` | Check quota before sending a prompt | `1` |
| `QUOTA_PREFLIGHT_ON_UNKNOWN` | What to do when quota cannot be read: `allow` or `skip` | `allow` |
| `QUOTA_EXHAUSTED_THRESHOLD_PERCENT` | Skip when remaining quota is at or below this percent | `0` |
| `ENABLE_STATUS_SNAPSHOTS` | Record quota again after a real run | `1` |

### Runs, timing and paths

| Variable | What it sets | Default |
| --- | --- | --- |
| `TIMEOUT_SECONDS` | Time limit for each tool | `120` |
| `LOCK_WAIT_SECONDS` | How long a run waits for another run to finish before giving up. `0` gives up at once | `1085` |
| `KEEP_AWAKE_MODE` | `off`, `during` (awake during a run), or `always` (also while the app is open) | `off` |
| `KEEP_AWAKE_SECONDS` | Longest keep-awake time for one run | `900` |
| `JQ_BIN`, `NODE_BIN`, `OMC_BIN` | Paths of those binaries | found automatically |
| `PATH_VALUE` | The `PATH` used by launchd and the runner | Homebrew, local and system paths |

The `LOCK_WAIT_SECONDS` default is long enough for the slowest possible Codex run:
`TIMEOUT_SECONDS × (1 + CODEX_MODEL_FALLBACK_MAX_TRIES) + CODEX_UPDATE_TIMEOUT_SECONDS +
CODEX_RESET_WAIT_MAX_SECONDS + 5 + 120`. A keep-awake run stays awake for
`KEEP_AWAKE_SECONDS + LOCK_WAIT_SECONDS + CODEX_RESET_WAIT_MAX_SECONDS + 5` seconds at most.

`KEEP_AWAKE_MODE` uses `caffeinate`. It stops the Mac from sleeping during a run. It cannot
wake a sleeping Mac. `launchd` runs a missed job once on wake, not once per missed time, and
Stoker does not configure `pmset` for you.

## Commands

| Command | What it does | Sends a check-in? |
| --- | --- | :---: |
| `./install.sh install` | Writes the LaunchAgents and loads them. This is the default command | No |
| `./install.sh uninstall` | Unloads and removes the LaunchAgents | No |
| `./install.sh status` | Shows the launchd status | No |
| `./install.sh check` | Checks that the required tools are installed | No |
| `./install.sh dry-run` | Prints the exact commands a run would use | No |
| `./install.sh quota` | Records your current quota in `logs/status.jsonl` | No |
| `./install.sh recommend` | Shows your detected windows and the schedule that fits them | No |
| `./install.sh app-status` | Prints the JSON state the app reads | No |
| `./install.sh print-plist` | Prints the generated plists. Add `claude` or `codex` for one | No |
| `./install.sh run-now` | Sends one check-in now to each enabled tool | **Yes** |

`run-now` starts the installed LaunchAgents, so run `install` first. If a run is already in
progress, `run-now` restarts it.

You can also call the runner directly:

```sh
./bin/activate-ai-window.sh --once                # one real run, all enabled tools
./bin/activate-ai-window.sh --once --tool claude  # one tool
./bin/activate-ai-window.sh --status              # quota only
```

## Logs

| File | What it holds |
| --- | --- |
| `logs/activation.log` | Plain-text run history |
| `logs/usage.jsonl` | One record per tool per run: tokens, cost, model, duration, or the skip reason |
| `logs/status.jsonl` | One record per quota check, with the windows your plan reports |
| `logs/raw/` | Raw output from the CLIs, for debugging |
| `logs/launchd.out.log`, `logs/launchd.err.log` | Output captured by launchd |

A normal run in `activation.log`:

```text
Activation run started ...
Quota preflight started
Claude job started
Codex job started
Activation run finished exit=0
```

A skipped tool:

```text
claude job skipped by quota preflight reason=quota_exhausted
```

In `usage.jsonl`, a successful run has `ok: true`, `result: READY`, and `exit_code: 0`. A
skipped one has `skipped: true` and a `skip_reason`.

## Health states

Each tool card in the app ends with a health line. The states are checked in the order shown.

**Claude**

| State | Shown as | When |
| --- | --- | --- |
| `disabled` | "Disabled" | `ACTIVATION_TOOL` excludes Claude |
| `unknown` | "No runs yet" | No real run has been recorded |
| `alert` | "N failures in a row" or "Activation failing" | Two or more real runs failed in a row. Or the schedule is on and the last 24 hours had neither a successful run nor a quota skip |
| `warning` | "Last run failed" | The most recent real run failed |
| `ok` | "Activating normally" | The most recent real run succeeded |

**Codex**

| State | Shown as | When |
| --- | --- | --- |
| `disabled` | "Disabled" | `ACTIVATION_TOOL` excludes Codex |
| `alert` | "N failures in a row" or "Activation failing" | Two or more real runs failed in a row |
| `warning` | "Last run failed" | The most recent real run failed |
| `exhausted` | "Weekly quota used up" or "5-hour quota used up" | A window is at or below `QUOTA_EXHAUSTED_THRESHOLD_PERCENT` and has not reset yet |
| `anchored` | "Anchored this week" or "Anchored this 5h window" | The window that decides whether Codex is skipped is already running. That is the 5-hour window if your plan has one, otherwise the weekly one |
| `pending` | "Will anchor next slot" | The window is idle, has already reset, or quota is unknown |

A real run is one that sent a prompt. A skipped run is not a failure, and a quota skip proves
the scheduler is alive. A disabled tool never alerts.

The "next activation" time for Codex moves past a window's reset only when the engine would
really skip until then: a used-up window with `ENABLE_QUOTA_PREFLIGHT=1`, or a running window
with `CODEX_ACTIVATE_ONLY_WHEN_IDLE=1` as well. Otherwise it is the next scheduled time.

The flame in the menu bar shows a red dot while either tool is in `alert`. It is rechecked
every 10 minutes and shortly after each scheduled run, even when the app window is closed.

## How a run works

`launchd` starts a run at each scheduled time. `./install.sh run-now` starts the same run by
hand.

1. **Load the config.** Read `.env`.
2. **Take the lock.** Create `run/activation.lock` so two runs never overlap. Claude and
   Codex can fire in the same second, so the second run waits, checking every 2 seconds for
   up to `LOCK_WAIT_SECONDS`. If the lock is still held after that, the run exits cleanly.
   The lock records its owner's process id, so a lock left by a crashed run is taken over.
   `dry-run` never takes the lock.
3. **Check quota.** Skip a tool whose quota is used up, and record the skip in
   `logs/usage.jsonl`. A window whose reset time has passed does not count as used up.
   Claude's per-model weekly limits count only while they are the active limit. Codex is
   also skipped while its window is already running. When quota cannot be read,
   `QUOTA_PREFLIGHT_ON_UNKNOWN` decides.
4. **Send the prompt.** Claude replies `READY`. Codex reads one small file in `codex-probe/`.
5. **Record usage.** Parse each CLI's output and append a record to `logs/usage.jsonl`.
6. **Record quota again.** Append a snapshot to `logs/status.jsonl`.
7. **Release the lock.**

Each CLI call has a time limit (`TIMEOUT_SECONDS`). A call that hangs is sent SIGTERM, then
SIGKILL two seconds later.

### What the app does

The app has no scheduler and no activation logic. It runs the same scripts and reads their
output:

| In the app | Script |
| --- | --- |
| Read status | `install.sh app-status` |
| Turn the schedule on or off | `install.sh install` or `install.sh uninstall` |
| Save settings | Write `.env`, then `install.sh install` |
| Run Once | `install.sh run-now` |

## Where Stoker runs

Both CLIs run inside Stoker's own folder. It holds only scripts and logs, so there is nothing
for them to scan or change.

| How you installed | Folder |
| --- | --- |
| `git clone` | The clone, for example `~/stoker` |
| App built from a clone | The same clone |
| `Stoker.app` from the DMG | `~/Library/Application Support/Stoker/stoker/`, created on first launch |

The scripts find their own folder at run time, so a clone works from any path.

A LaunchAgent is the small file that tells macOS `launchd` when to start a program.
`install` writes one per enabled tool into `~/Library/LaunchAgents/`:
`<LABEL>.claude.plist` and `<LABEL>.codex.plist`. Each runs that tool on its own times and
days. `install` also removes the agent of a tool you turned off, and the single `<LABEL>`
agent that older versions used.

An agent that belongs to a different Stoker folder is left alone, with a warning. This
applies at install and at uninstall, to old agents and to `<LABEL>.claude` / `<LABEL>.codex`.
When a per-tool agent is skipped this way, the command exits non-zero. Set
`STOKER_FORCE_MIGRATE=1` to remove it anyway.

The plists contain paths for your machine, so they are not committed to git. GitHub Actions
only validates the code. Check-ins always run on your own Mac.

```text
stoker/
├── install.sh                  ← the command you run
├── bin/
│   ├── activate-ai-window.sh   ← runs a check-in
│   └── activation-state.sh     ← state for the app, and `recommend`
├── scripts/
│   └── install-launchd.sh      ← installs and removes the LaunchAgents
├── app/StokerMenuBar/          ← the menu bar app
├── codex-probe/                ← the small folder Codex runs in
├── launchd/                    ← generated plists (not committed)
├── logs/                       ← generated logs (not committed)
└── .env.example
```

## How check-ins stay small

A check-in needs under 300 tokens of prompt and reply. The cost comes from what each CLI adds
by itself: instructions, plugins, tool descriptions and hooks, which can pass 40,000 tokens.
Stoker turns all of that off.

**Claude**

| Flag | Effect |
| --- | --- |
| `--model haiku` | The cheapest model |
| `--system-prompt "Reply only: READY"` | A minimal system prompt |
| `--setting-sources ""` | No CLAUDE.md, hooks or plugin instructions. This removes about 40K tokens |
| `--effort low` | Minimal reasoning |
| `--strict-mcp-config --mcp-config '{"mcpServers":{}}'` | No MCP servers, so no tool descriptions |
| `--tools ""` | No built-in tools |
| `--disable-slash-commands` | No skills |

Result: about 1.6K input tokens and ≈ $0.0025 per check-in, averaged over recent logged runs.
Without these flags it is about 40K tokens and $0.15. At four check-ins a day that is
≈ $0.30 a month instead of about $18.

**Codex**

| Flag | Effect |
| --- | --- |
| `--ignore-user-config` | Skips `~/.codex/config.toml`: no plugins, MCP servers or developer instructions |
| `--ignore-rules` | Skips `.rules` files |
| `--cd "$CODEX_WORK_DIR"` | Keeps Codex inside the small probe folder |
| `--model "$CODEX_MODEL"` | The configured lightweight model |
| `--sandbox read-only` | Codex cannot write files |
| `--ephemeral`, `--skip-git-repo-check` | No saved session, no git checks |
| `-c 'features.memories=false'` | No memories |
| `-c 'features.multi_agent=false'` | No multi-agent |
| `-c 'features.goals=false'` | No goals |
| `-c 'features.hooks=false'` | No hooks |
| `-c 'features.child_agents_md=false'` | No AGENTS.md loading |
| `-c 'model_reasoning_effort="low"'` | Minimal reasoning |

Result: about 38K input tokens per check-in, about 55% of them cache reads. Codex's own system
prompt sets that floor. Codex check-ins count against your plan quota, not a dollar price.

## Codex updates and model fallback

Codex retires models and changes plans often. Two features keep check-ins working.

**Automatic update.** With `CODEX_AUTO_UPDATE=1`, the default, Stoker **updates your Codex
CLI without asking**. Set it to `0` to manage Codex versions yourself. The update runs just
before a real Codex check-in, never on a skipped run, `dry-run`, `check` or `quota`. It runs
at most once every `CODEX_AUTO_UPDATE_INTERVAL_HOURS`, with a time limit of
`CODEX_UPDATE_TIMEOUT_SECONDS`. A failed update only logs a warning. The usage record gets a
`cli_update` field: `{attempted, from, to, exit}`.

**Model fallback.** With `CODEX_MODEL_FALLBACK=1`, when Codex answers "model is not
supported", Stoker tries another model from `~/.codex/models_cache.json`:

1. the model the rejected one names as its upgrade,
2. then models whose name contains `luna`, then `terra`, then `sol`,
3. then anything else.

Only models that support low reasoning effort and are not past their retirement date
qualify. Stoker stops on success, on any other error, or after
`CODEX_MODEL_FALLBACK_MAX_TRIES` attempts. Each attempt gets its own usage record. A retry carries
`model_fallback: {from, to, attempt}`. A rejected attempt that was retried carries
`superseded_by_fallback: true` and is not counted as an error in the app. A warning
asks you to set `CODEX_MODEL` to the model that worked. `.env` is never rewritten.

The default model is `gpt-5.6-luna`. The earlier default, `gpt-5.4-mini`, was retired for
ChatGPT sign-ins in September 2026. If your `.env` still names a retired model, the engine
warns and uses `gpt-5.6-luna`, and the app updates the value the next time you save.
