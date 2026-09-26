#!/usr/bin/env bash
set -euo pipefail

# Regression: the keep-awake re-exec must forward the ORIGINAL argv. The top-level
# parse loop shifts "$@" away, so the re-exec used to drop `--once --tool codex`
# and the caffeinated run silently fell back to .env's ACTIVATION_TOOL.
#
# A stub CAFFEINATE_BIN records its argv and exits; exec replaces the engine, so
# nothing after the re-exec runs (no lock, no prompts). The engine is copied into
# a temp root so the real .env/logs are never touched.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"
ENGINE="$TMP_DIR/bin/activate-ai-window.sh"
ARGV_FILE="$TMP_DIR/caffeinate-argv"

cat >"$TMP_DIR/bin/caffeinate-fake" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$ARGV_FILE"
exit 0
SH
chmod +x "$TMP_DIR/bin/caffeinate-fake"
export ARGV_FILE

run_engine() {
  KEEP_AWAKE_MODE=during \
    KEEP_AWAKE_SECONDS=42 \
    CAFFEINATE_BIN="$TMP_DIR/bin/caffeinate-fake" \
    ENABLE_QUOTA_PREFLIGHT=0 \
    CLAUDE_BIN=/nonexistent CODEX_BIN=/nonexistent \
    "$@" >/dev/null 2>&1
}

# A) explicit args survive the re-exec, in order
rm -f "$ARGV_FILE"
run_engine env "$ENGINE" --once --tool codex \
  || { echo "expected the stubbed re-exec to exit 0" >&2; exit 1; }
[[ -f "$ARGV_FILE" ]] || { echo "expected caffeinate to be invoked" >&2; exit 1; }
argv="$(cat "$ARGV_FILE")"
[[ "$argv" == "-i -t 42 "*"/bin/activate-ai-window.sh --once --tool codex" ]] \
  || { echo "re-exec dropped or reordered args: $argv" >&2; exit 1; }

# B) no args (the plist's bare --once is optional): must not trip `set -u` on an
#    empty array, and forwards nothing extra
rm -f "$ARGV_FILE"
run_engine env "$ENGINE" \
  || { echo "expected a no-arg run to re-exec cleanly" >&2; exit 1; }
argv="$(cat "$ARGV_FILE")"
[[ "$argv" == *"/bin/activate-ai-window.sh" ]] \
  || { echo "unexpected no-arg re-exec argv: $argv" >&2; exit 1; }

# C) already caffeinated → no second re-exec
rm -f "$ARGV_FILE"
run_engine env STOKER_CAFFEINATED=1 ACTIVATION_TOOL=codex "$ENGINE" --once --tool codex || true
[[ ! -e "$ARGV_FILE" ]] \
  || { echo "a caffeinated run must not re-exec again" >&2; exit 1; }

echo "caffeinate re-exec test passed"
