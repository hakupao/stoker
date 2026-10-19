#!/usr/bin/env bash
set -euo pipefail

# Verifies the bounded run-lock wait (LOCK_WAIT_SECONDS) in activate-ai-window.sh,
# which lets the per-tool agents fire in the same second without one being dropped:
#   A) a held lock released after ~3s lets a waiting --once run proceed
#   B) LOCK_WAIT_SECONDS=0 skips immediately (pre-wait behavior)
#   C) a lock held past the wait bound is skipped after waiting, exit 0
#   D) a non-integer LOCK_WAIT_SECONDS is rejected up front
#   E) a lock whose recorded owner PID is dead is reclaimed at once; a lock with
#      no pid file is reclaimed once its directory is older than the wait bound
#   F) the run records its PID in the lock and removes lock + pid on exit
#   G) dry-run never waits for (or takes) the lock
#   H) the default wait covers a worst-case Codex run
#   I) four waiters racing on one dead-owner lock: exactly one reclaim, and the
#      runs never overlap
#
# The engine is copied into a temp root (logs/locks stay hermetic) and Claude is a
# fake CLI that leaves a sentinel, so no real prompt is ever sent.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/run"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"
ENGINE="$TMP_DIR/bin/activate-ai-window.sh"
LOG="$TMP_DIR/logs/activation.log"
LOCK_DIR="$TMP_DIR/run/activation.lock"
SENTINEL="$TMP_DIR/claude-invoked"

cat >"$TMP_DIR/bin/claude-ok" <<SH
#!/usr/bin/env bash
touch "$SENTINEL"
echo '{"type":"result","is_error":false,"api_error_status":null,"result":"READY","session_id":"t","usage":{"input_tokens":10,"output_tokens":2}}'
SH
chmod +x "$TMP_DIR/bin/claude-ok"

run_once() {
  env CLAUDE_BIN="$TMP_DIR/bin/claude-ok" \
    ACTIVATION_TOOL=claude \
    ENABLE_QUOTA_PREFLIGHT=0 \
    ENABLE_STATUS_SNAPSHOTS=0 \
    KEEP_AWAKE_MODE=off \
    "$@" "$ENGINE" --once --tool claude >/dev/null 2>&1
}

# A) the lock is released while the second run waits → it proceeds.
rm -f "$SENTINEL"
mkdir "$LOCK_DIR"
( sleep 3; rmdir "$LOCK_DIR" ) &
releaser=$!
start=$(date +%s)
run_once LOCK_WAIT_SECONDS=20
elapsed=$(( $(date +%s) - start ))
wait "$releaser"
[[ -e "$SENTINEL" ]] || { echo "A: expected the waiting run to send its prompt" >&2; exit 1; }
(( elapsed >= 2 )) || { echo "A: expected the run to wait for the lock (elapsed ${elapsed}s)" >&2; exit 1; }
grep -q "waiting up to 20s" "$LOG" || { echo "A: expected a wait log line" >&2; exit 1; }
grep -q "Acquired activation lock after waiting" "$LOG" || { echo "A: expected an acquired-after-wait log line" >&2; exit 1; }
[[ ! -e "$LOCK_DIR" ]] || { echo "A: expected the lock to be released after the run" >&2; exit 1; }

# B) LOCK_WAIT_SECONDS=0 → immediate skip, exit 0, no prompt.
rm -f "$SENTINEL"
: >"$LOG"
mkdir "$LOCK_DIR"
start=$(date +%s)
run_once LOCK_WAIT_SECONDS=0 || { echo "B: expected exit 0 on lock skip" >&2; exit 1; }
elapsed=$(( $(date +%s) - start ))
[[ ! -e "$SENTINEL" ]] || { echo "B: expected no prompt while the lock is held" >&2; exit 1; }
(( elapsed < 2 )) || { echo "B: expected an immediate skip (elapsed ${elapsed}s)" >&2; exit 1; }
grep -q "already active; skipping after waiting 0s" "$LOG" || { echo "B: expected a skip log line" >&2; exit 1; }
[[ -d "$LOCK_DIR" ]] || { echo "B: the skipping run must not remove another run's lock" >&2; exit 1; }

# C) held past the bound → skipped after waiting, lock untouched.
: >"$LOG"
run_once LOCK_WAIT_SECONDS=4 || { echo "C: expected exit 0 on lock skip" >&2; exit 1; }
[[ ! -e "$SENTINEL" ]] || { echo "C: expected no prompt while the lock is held" >&2; exit 1; }
grep -q "skipping after waiting 4s" "$LOG" || { echo "C: expected a skip-after-wait log line: $(cat "$LOG")" >&2; exit 1; }
[[ -d "$LOCK_DIR" ]] || { echo "C: the skipping run must not remove another run's lock" >&2; exit 1; }
rmdir "$LOCK_DIR"

# D) invalid value rejected.
if run_once LOCK_WAIT_SECONDS=soon; then
  echo "D: expected LOCK_WAIT_SECONDS=soon to be rejected" >&2
  exit 1
fi

# E) dead owner PID → reclaimed immediately even with a long wait bound.
sleep 0 &
dead_pid=$!
wait "$dead_pid" || true
rm -f "$SENTINEL"
: >"$LOG"
mkdir "$LOCK_DIR"
echo "$dead_pid" >"$LOCK_DIR/pid"
start=$(date +%s)
run_once LOCK_WAIT_SECONDS=300 || { echo "E: expected exit 0" >&2; exit 1; }
elapsed=$(( $(date +%s) - start ))
[[ -e "$SENTINEL" ]] || { echo "E: expected the run to reclaim the dead lock and proceed" >&2; exit 1; }
(( elapsed < 30 )) || { echo "E: expected no wait for a dead owner (elapsed ${elapsed}s)" >&2; exit 1; }
grep -q "Reclaimed stale activation lock (owner pid ${dead_pid} is not running)" "$LOG" \
  || { echo "E: expected a reclaim log line: $(cat "$LOG")" >&2; exit 1; }
[[ ! -e "$LOCK_DIR" ]] || { echo "F: expected the lock (and pid file) removed after the run" >&2; exit 1; }

# A live owner PID is respected.
rm -f "$SENTINEL"
mkdir "$LOCK_DIR"
echo "$$" >"$LOCK_DIR/pid"
run_once LOCK_WAIT_SECONDS=0 || true
[[ ! -e "$SENTINEL" ]] || { echo "E: a live owner's lock must not be reclaimed" >&2; exit 1; }
rm -f "$LOCK_DIR/pid"

# No pid file: fresh → respected; older than the longest possible run
# (TIMEOUT*(1+fallback tries)+update timeout = 660s by default) → reclaimed.
run_once LOCK_WAIT_SECONDS=0 || true
[[ ! -e "$SENTINEL" ]] || { echo "E: a fresh pid-less lock must not be reclaimed" >&2; exit 1; }
touch -t "$(date -v-8M '+%Y%m%d%H%M.%S')" "$LOCK_DIR"
run_once LOCK_WAIT_SECONDS=0 || true
[[ ! -e "$SENTINEL" ]] || { echo "E: an 8-minute-old pid-less lock is within a possible run" >&2; exit 1; }
touch -t "$(date -v-30M '+%Y%m%d%H%M.%S')" "$LOCK_DIR"
: >"$LOG"
run_once LOCK_WAIT_SECONDS=0 || true
[[ -e "$SENTINEL" ]] || { echo "E: expected an old pid-less lock to be reclaimed" >&2; exit 1; }
grep -q "Reclaimed stale activation lock (no owner pid" "$LOG" \
  || { echo "E: expected a pid-less reclaim log line" >&2; exit 1; }

# F) the PID is written while the run holds the lock.
cat >"$TMP_DIR/bin/claude-peek" <<SH
#!/usr/bin/env bash
cp "$LOCK_DIR/pid" "$TMP_DIR/pid-seen" 2>/dev/null
echo '{"type":"result","is_error":false,"api_error_status":null,"result":"READY","session_id":"t","usage":{"input_tokens":1,"output_tokens":1}}'
SH
chmod +x "$TMP_DIR/bin/claude-peek"
run_once CLAUDE_BIN="$TMP_DIR/bin/claude-peek" LOCK_WAIT_SECONDS=0 || true
[[ "$(tr -cd '0-9' <"$TMP_DIR/pid-seen")" =~ ^[0-9]+$ ]] || { echo "F: expected a pid file inside the lock" >&2; exit 1; }
[[ ! -e "$LOCK_DIR" ]] || { echo "F: expected the lock removed after the run" >&2; exit 1; }

# G) dry-run with a held lock: no wait, no skip message, lock untouched.
mkdir "$LOCK_DIR"
: >"$LOG"
start=$(date +%s)
env ACTIVATION_TOOL=claude CLAUDE_BIN="$TMP_DIR/bin/claude-ok" LOCK_WAIT_SECONDS=30 \
  "$ENGINE" --dry-run --tool claude >/dev/null 2>&1 || { echo "G: dry-run failed" >&2; exit 1; }
elapsed=$(( $(date +%s) - start ))
(( elapsed < 2 )) || { echo "G: dry-run waited for the lock (${elapsed}s)" >&2; exit 1; }
if grep -q "waiting up to\|already active" "$LOG"; then
  echo "G: dry-run must not touch the lock" >&2
  exit 1
fi
[[ -d "$LOCK_DIR" ]] || { echo "G: dry-run removed another run's lock" >&2; exit 1; }

# H) default = TIMEOUT*(1+fallback tries) + update timeout + 120: with a held
#    live lock and caffeinate off, the wait log line shows the computed bound.
echo "$$" >"$LOCK_DIR/pid"
: >"$LOG"
( sleep 3; rm -f "$LOCK_DIR/pid"; rmdir "$LOCK_DIR" ) &
releaser=$!
env -u LOCK_WAIT_SECONDS CLAUDE_BIN="$TMP_DIR/bin/claude-ok" ACTIVATION_TOOL=claude ENABLE_QUOTA_PREFLIGHT=0 \
  ENABLE_STATUS_SNAPSHOTS=0 KEEP_AWAKE_MODE=off \
  TIMEOUT_SECONDS=10 CODEX_MODEL_FALLBACK_MAX_TRIES=2 CODEX_UPDATE_TIMEOUT_SECONDS=30 \
  "$ENGINE" --once --tool claude >/dev/null 2>&1 || true
wait "$releaser"
grep -q "waiting up to 180s" "$LOG" || { echo "H: expected default wait 10*3+30+120=180: $(cat "$LOG")" >&2; exit 1; }
if TIMEOUT_SECONDS=abc "$ENGINE" --dry-run >/dev/null 2>&1; then
  echo "H: expected TIMEOUT_SECONDS=abc to be rejected" >&2
  exit 1
fi

# I) concurrent waiters + dead-owner lock.
cat >"$TMP_DIR/bin/claude-span" <<SH
#!/usr/bin/env bash
perl -MTime::HiRes=time -e 'printf "start %.3f\n", time' >>"$TMP_DIR/spans"
sleep 2
perl -MTime::HiRes=time -e 'printf "end %.3f\n", time' >>"$TMP_DIR/spans"
echo '{"type":"result","is_error":false,"api_error_status":null,"result":"READY","session_id":"t","usage":{"input_tokens":1,"output_tokens":1}}'
SH
chmod +x "$TMP_DIR/bin/claude-span"
sleep 0 &
dead_pid=$!
wait "$dead_pid" || true
rm -f "$TMP_DIR/spans"
: >"$LOG"
mkdir "$LOCK_DIR"
echo "$dead_pid" >"$LOCK_DIR/pid"
waiters=()
for _ in 1 2 3 4; do
  run_once CLAUDE_BIN="$TMP_DIR/bin/claude-span" LOCK_WAIT_SECONDS=60 &
  waiters+=("$!")
done
wait "${waiters[@]}"
[[ "$(grep -c "Reclaimed stale activation lock" "$LOG")" == "1" ]] \
  || { echo "I: expected exactly one reclaim: $(grep Reclaimed "$LOG")" >&2; exit 1; }
[[ "$(grep -c '^start' "$TMP_DIR/spans")" == "4" ]] || { echo "I: expected all four runs: $(cat "$TMP_DIR/spans")" >&2; exit 1; }
# Spans must alternate start,end,start,end in time order (no overlap).
order="$(sort -k2 -n "$TMP_DIR/spans" | awk '{printf "%s ", $1}')"
[[ "$order" == "start end start end start end start end " ]] || { echo "I: runs overlapped: $(cat "$TMP_DIR/spans")" >&2; exit 1; }
[[ ! -e "$LOCK_DIR" && ! -e "$LOCK_DIR.reclaim" ]] || { echo "I: lock or reclaim marker left behind" >&2; exit 1; }

echo "lock wait test passed"
