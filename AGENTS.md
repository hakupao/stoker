# AGENTS.md

This file provides guidance to coding agents (Claude Code, Codex, and other AGENTS.md-aware
tools) when working with code in this repository. It mirrors CLAUDE.md — when editing one,
apply the same change to the other.

## What this is

**Stoker** is a macOS `launchd` scheduler that sends tiny low-cost check-in prompts to the
Claude Code and Codex CLIs at fixed times to keep usage windows "lit," then records activation
logs, per-run token usage, and quota snapshots. There are two entry points over **one shared
Bash engine**: the CLI/`launchd` path (`install.sh`) and an optional SwiftUI menu bar app that
shells out to the same scripts. The app contains no scheduler or activation logic of its own.

(The project was renamed from "Activation Timer" to "Stoker" — you'll still find the legacy
`com.activation-timer.*` identifiers referenced by the upgrade/migration paths.)

## Commands

```sh
# Validate / test — THE canonical gate. CONTRIBUTING.md mandates it pre-PR; CI runs it verbatim.
./scripts/validate.sh

# Run a single test (all 5 are standalone executables; self-locate ROOT_DIR, run from anywhere)
tests/swift-core.test.sh          # swiftc-compiles StokerCore + a driver, asserts via precondition()
tests/activation-state.test.sh    # bin/activation-state.sh --json output (needs jq)
tests/keep-awake-config.test.sh   # rejects invalid KEEP_AWAKE_MODE / KEEP_AWAKE_SECONDS
tests/release-packaging.test.sh   # package-release.sh --check
tests/app-bundle-assets.test.sh   # icon generation + bundle wiring (needs `file`)

# Menu bar app
swift build --package-path app/StokerMenuBar     # compile-check the SwiftUI app
./app/StokerMenuBar/build-app.sh && open dist/Stoker.app   # build a runnable .app bundle

# Shell engine (safe inspection — no model prompts)
./install.sh check        # verify claude/codex/jq/node/omc binaries
./install.sh dry-run      # print the exact claude/codex command arrays, send nothing
./install.sh quota        # snapshot quota into logs/status.jsonl, send nothing
./install.sh app-status   # the JSON state the menu bar app consumes (bin/activation-state.sh --json)
./install.sh print-plist  # regenerate + cat the launchd plist without installing

# Shell engine (consumes real quota — sends model prompts)
./install.sh install      # generate, plutil-lint, and load the LaunchAgent
./install.sh run-now      # trigger one real activation now
bin/activate-ai-window.sh --once --tool claude   # single real run, one tool (--tool all|claude|codex)
```

There is **no Makefile / npm / `swift test`**. `scripts/validate.sh` *is* the test runner: it
runs `bash -n` + `shellcheck` on 7 scripts, `plutil -lint`s the plist, runs `dry-run` + `app-status`
smoke checks, runs the 5 `tests/*.test.sh` in order, then `swift build`s the app. `shellcheck`,
`plutil`, and `swift` are skipped if absent; `jq`, `swiftc`, and `file` are **not** guarded and will
hard-fail their test if missing.

## Architecture

**Shared Bash engine (three scripts, not one).** `install.sh` is a thin dispatcher; real behavior
is split across:
- `bin/activate-ai-window.sh` — the activation runner (config load → lock → quota preflight →
  send prompt → record usage → post-run snapshot). Owns the Claude/Codex invocation arrays.
- `scripts/install-launchd.sh` — owns plist generation + the `launchctl` lifecycle
  (`bootstrap`/`bootout`/`kickstart` in the `gui/$UID` domain).
- `bin/activation-state.sh` — owns the JSON state contract consumed by the app. Claude quota
  prefers the live omc usage cache when it is newer than the last snapshot row, restamps
  `timestamp` with the data-capture time (not the snapshot-write time), and blanks any window
  whose `resets_at` already passed (`reset_passed: true`) so stale numbers are never shown as
  current.

**Path independence.** Every script computes `ROOT_DIR` at runtime from `${BASH_SOURCE[0]}`
(`install.sh` uses its own dir; the rest use `…/..`), so the project works from any clone path
with no hardcoded paths. The plist embeds absolute paths and is therefore git-ignored and
machine-specific.

**Config sourcing.** `activate-ai-window.sh`, `activation-state.sh`, and `install-launchd.sh` all
source `${ROOT_DIR}/.env` with `set -a`, but snapshot the caller's exported env first
(`export -p`) and re-apply it after — so **the caller's environment always wins over `.env`**.
The full `.env` variable surface is documented in `README.md` (don't duplicate it here);
`.env.example` is the committed template, `.env` is git-ignored.

**Runtime flow** of a real `--once` run: `cd ROOT_DIR` → optional `caffeinate` re-exec → acquire
lock via `mkdir run/activation.lock` (atomic; a concurrent trigger logs and exits 0) → trap
`rmdir LOCK_DIR` on EXIT → quota preflight (if enabled) → per-tool `run_claude`/`run_codex` →
post-run quota snapshot → release lock. Per-tool calls use `run_with_timeout()` (poll → SIGTERM →
2s → SIGKILL, exit 124 on timeout, default `TIMEOUT_SECONDS=120`).

**Quota preflight** writes a status snapshot, then reads back only the row matching this tool *and*
`RUN_ID` before deciding. A tool whose quota is exhausted is skipped and recorded to
`logs/usage.jsonl` with `skipped:true`. When quota can't be determined, it falls back to
`QUOTA_PREFLIGHT_ON_UNKNOWN` (default `allow`; only the literal `skip` skips). An exhausted
window whose `resets_at` is already in the past does **not** count as exhausted (snapshots can be
last-known data). Note the quota *sources* (`CLAUDE_STATUS_SOURCE`): `cache` (default) reads the
**oh-my-claudecode plugin's local usage cache** directly — zero credential access; `native` reads
the Keychain OAuth token **read-only** and queries the usage API, skipping whenever the token is
expired (it never refreshes — that refresh-and-drop is what logs interactive sessions out);
`omc` (legacy) forces a live `omc wait status` query, which in headless runs consumes the shared
Keychain refresh token without persisting the replacement. Codex status spawns
`codex app-server` over JSON-RPC via an inline **Node.js** heredoc.

**Three log streams** under `logs/`: `activation.log` (human-readable), `usage.jsonl` (one row per
tool run), `status.jsonl` (one row per quota snapshot); raw CLI output goes to `logs/raw/`.

**SwiftUI menu bar app** (`app/StokerMenuBar/`, Swift 6.0 tools, macOS 14+), two targets:
- `StokerCore` — logic/models with no UI: `EnvFile`, `ScheduleFormatter`, `ProjectLocator`,
  `LogStore` (parses `usage.jsonl`/`status.jsonl`), `L10n` (EN/中 bilingual). This is what
  `swift-core.test.sh` compiles and tests.
- `StokerMenuBar` — the SwiftUI UI (`MenuBarExtra` + `Window`, `LSUIElement`, no Dock icon);
  links `ServiceManagement` for launch-at-login.

The app drives the engine through `Process()`: it runs `install.sh app-status` (status),
`install.sh install`/`uninstall` (toggle schedule, after writing `.env`), and `install.sh run-now`,
then decodes stdout JSON into Swift models. `ProjectLocator.findRoot` walks up from the app bundle
looking for `bin/activate-ai-window.sh`; for a standalone `.app` it falls back to copying the
bundled engine (shipped in `Contents/Resources/stoker`) into
`~/Library/Application Support/Stoker/stoker` and uses that copy.

## Conventions & gotchas

- **`run-now` and `install` consume real quota** (they send model prompts). `dry-run`, `quota`,
  `check`, `app-status`, and `print-plist` are safe and send nothing.
- **Adding a test** = create `tests/<name>.test.sh` (executable, `set -euo pipefail`, hermetic via
  `mktemp -d`) **and** add an explicit line to `scripts/validate.sh`. There is no glob
  auto-discovery — an unlisted test silently never runs.
- **Test isolation env vars:** `STOKER_ROOT` overrides the engine root and `STOKER_SKIP_LAUNCHCTL=1`
  short-circuits the `launchctl` probe. Use these instead of touching the real install.
- **Design system (`DS` enum in `StokerMenuBarApp.swift`):** the app UI is **adaptive** — it follows
  the system Light/Dark setting and does **not** force a color scheme. Use the adaptive `DS` tiers
  (`DS.textPrimary`/`textSecondary`/`textMuted`/`hairline`, which wrap `NSColor` label colors) for
  all text/surfaces. Never hardcode `Color.white…` or raw `.secondary`/`.tertiary` — they don't
  adapt across appearances.
- **Version bumps touch 8 sites** (keep in sync). `package-release.sh --check` only checks file
  presence — it does **not** catch a version mismatch, so after editing always `grep -rn` the old
  version to confirm none remain. Line numbers below drift; treat them as hints and anchor on the
  identifier:
  1. `scripts/package-release.sh:5` — `VERSION` default (overridable via `VERSION=` env).
  2. `app/StokerMenuBar/build-app.sh` (~:123) — `CFBundleShortVersionString` in the inline Info.plist
     (the `CFBundleVersion` build number just below, ~:125, is a *separate* integer — bump it too).
  3. `app/StokerMenuBar/Sources/StokerMenuBar/MainView.swift` (~:302) — the `?? "…"` UI version fallback.
  4. `bin/activate-ai-window.sh` (~:484) — the MCP `clientInfo` `version:` sent to the model.
  5. `README.md:17` — the `version-…` shields.io badge.
  6. `README_CN.md:17` — the same version badge.
  7. `CHANGELOG.md` — add the new release header.
  8. `docs/` landing page — the hardcoded `v0.2.x` appears in `docs/index.html` (the
     `hero.meta` line) **and** `docs/main.js` (the `hero.meta` string in *both* the `en` and
     `zh` i18n dicts, so 3 occurrences total). `grep -rn` the old version under `docs/` to
     confirm none remain. (The GitHub Pages site is served from `/docs`; it is not part of
     `validate.sh`.)
- **Rename migration:** `install-launchd.sh` defaults `LEGACY_LABELS=com.activation-timer.ai-window`
  and boots out/removes those agents at install/uninstall.
- **Release:** `scripts/package-release.sh` builds three artifacts into `dist/`
  (`stoker-cli-<v>.tar.gz`, `stoker-gui-<v>.dmg`, `stoker-gui-<v>.zip`; DMG only if `hdiutil` exists).
  The GUI build (`build-app.sh`) bundles the full CLI engine + an ad-hoc-codesigned `jq` into the
  `.app` — if `jq` is missing on the build host it only warns and ships a degraded app.
- **Don't commit** generated artifacts: `.env`, `logs/*.log`, `logs/*.jsonl`, `logs/raw/`, `run/`,
  `launchd/*.plist`, `dist/`, `.omx/`, `.omc/` (all git-ignored).
- **CI** (`.github/workflows/ci.yml`) runs `./scripts/validate.sh` on `macos-15` with Xcode 16.4;
  triggers on push to `main` and on **all** pull requests. A clean local `validate.sh` is the
  contract.
