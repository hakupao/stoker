#!/usr/bin/env bash
set -euo pipefail

# Verifies the --scheduled gate in activate-ai-window.sh: a launchd run
# (`--once --scheduled --tool <t>`) of a tool that ACTIVATION_TOOL excludes is a
# stale agent and exits 0 without a prompt, lock, or preflight; the same run for
# an enabled tool proceeds, and a manual `--once --tool <t>` (no --scheduled) is
# never gated. Fake CLIs leave sentinels; the engine runs from a temp root.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/codex-probe" "$TMP_DIR/logs"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"
ENGINE="$TMP_DIR/bin/activate-ai-window.sh"
LOG="$TMP_DIR/logs/activation.log"
SENTINELS="$TMP_DIR/sentinels"

cat >"$TMP_DIR/bin/claude-ok" <<SH
#!/usr/bin/env bash
touch "$SENTINELS/claude"
echo '{"type":"result","is_error":false,"api_error_status":null,"result":"READY","session_id":"t","usage":{"input_tokens":1,"output_tokens":1}}'
SH
cat >"$TMP_DIR/bin/codex-ok" <<SH
#!/usr/bin/env bash
touch "$SENTINELS/codex"
echo '{"type":"item.completed","item":{"type":"agent_message","text":"READY"}}'
SH
chmod +x "$TMP_DIR/bin/claude-ok" "$TMP_DIR/bin/codex-ok"

run() {
  rm -rf "$SENTINELS" && mkdir -p "$SENTINELS"
  : >"$LOG"
  env CLAUDE_BIN="$TMP_DIR/bin/claude-ok" CODEX_BIN="$TMP_DIR/bin/codex-ok" \
    CODEX_WORK_DIR="$TMP_DIR/codex-probe" CODEX_AUTO_UPDATE=0 \
    ENABLE_QUOTA_PREFLIGHT=0 ENABLE_STATUS_SNAPSHOTS=0 KEEP_AWAKE_MODE=off LOCK_WAIT_SECONDS=0 \
    "$@" >/dev/null 2>&1
}

# A) disabled tool, scheduled → exit 0, nothing sent, logged; even a held lock is
#    irrelevant (the gate runs before locking).
mkdir -p "$TMP_DIR/run/activation.lock"
run ACTIVATION_TOOL=claude "$ENGINE" --once --scheduled --tool codex || { echo "A: expected exit 0" >&2; exit 1; }
[[ ! -e "$SENTINELS/codex" ]] || { echo "A: disabled tool must not be prompted" >&2; exit 1; }
grep -q "codex disabled by ACTIVATION_TOOL=claude; skipping" "$LOG" || { echo "A: missing gate log: $(cat "$LOG")" >&2; exit 1; }
if grep -q "already active\|Quota preflight" "$LOG"; then
  echo "A: gate must run before the lock and preflight" >&2
  exit 1
fi
rmdir "$TMP_DIR/run/activation.lock"

# B) enabled tool, scheduled → runs (ACTIVATION_TOOL=all and an exact match).
run ACTIVATION_TOOL=all "$ENGINE" --once --scheduled --tool codex || true
[[ -e "$SENTINELS/codex" ]] || { echo "B: enabled codex (all) should run" >&2; exit 1; }
run ACTIVATION_TOOL=claude "$ENGINE" --once --scheduled --tool claude || true
[[ -e "$SENTINELS/claude" ]] || { echo "B: enabled claude should run" >&2; exit 1; }

# C) manual run without --scheduled is never gated.
run ACTIVATION_TOOL=claude "$ENGINE" --once --tool codex || true
[[ -e "$SENTINELS/codex" ]] || { echo "C: manual --tool codex should run" >&2; exit 1; }

echo "scheduled tool gate test passed"
