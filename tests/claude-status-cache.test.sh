#!/usr/bin/env bash
set -euo pipefail

# Verifies the Claude quota snapshot sources (CLAUDE_STATUS_SOURCE):
#   A) cache mode (default) records a snapshot from the omc plugin usage cache
#      without invoking `omc` or `claude` — the keychain-safety contract
#   B) a missing cache fails the snapshot and appends no row
#   C) a cache with error=true records ok=false
#   D) legacy omc mode still shells out to `omc wait status`
#   E) an invalid CLAUDE_STATUS_SOURCE is rejected up front
#   F) quota preflight ignores an exhausted window whose resets_at has passed
#      (stale last-known data must not skip a run after the window rolled over)
#
# The engine derives ROOT_DIR from its own location, so it is copied into a temp
# root to keep logs/locks hermetic and away from the real install.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"
ENGINE="$TMP_DIR/bin/activate-ai-window.sh"
STATUS="$TMP_DIR/logs/status.jsonl"
USAGE="$TMP_DIR/logs/usage.jsonl"
CACHE="$TMP_DIR/usage-cache.json"

# Sentinel-writing fakes: any invocation of omc/claude leaves a footprint.
cat >"$TMP_DIR/bin/omc-fake" <<'SH'
#!/usr/bin/env bash
touch "${SENTINEL_DIR}/omc-invoked"
echo "Rate Limits: OK"
SH
cat >"$TMP_DIR/bin/claude-fake" <<'SH'
#!/usr/bin/env bash
touch "${SENTINEL_DIR}/claude-invoked"
echo '{"type":"result","is_error":false,"api_error_status":null,"result":"READY","session_id":"t","usage":{"input_tokens":1,"output_tokens":1}}'
SH
chmod +x "$TMP_DIR/bin/omc-fake" "$TMP_DIR/bin/claude-fake"
export SENTINEL_DIR="$TMP_DIR/sentinels"

write_cache() {
  local five_percent="$1" five_resets="$2" error="${3:-false}"
  jq -n \
    --argjson now_ms "$(( $(date +%s) * 1000 ))" \
    --argjson five_percent "$five_percent" \
    --arg five_resets "$five_resets" \
    --argjson error "$error" '
      {
        timestamp: $now_ms,
        data: {
          fiveHourPercent: $five_percent,
          fiveHourResetsAt: $five_resets,
          weeklyPercent: 8,
          weeklyResetsAt: "2099-01-01T00:00:00.000Z",
          sonnetWeeklyPercent: 0,
          sonnetWeeklyResetsAt: null
        },
        error: $error,
        source: "anthropic",
        lastSuccessAt: $now_ms
      }' >"$CACHE"
}

run_status() {
  CLAUDE_USAGE_CACHE_FILE="$CACHE" \
    OMC_BIN="$TMP_DIR/bin/omc-fake" \
    CLAUDE_BIN="$TMP_DIR/bin/claude-fake" \
    "$@" "$ENGINE" --status --tool claude >/dev/null 2>&1
}

# ── A) cache mode: snapshot recorded, zero omc/claude invocations ───────────
mkdir -p "$SENTINEL_DIR"
write_cache 38 "2099-01-01T00:00:00.673Z"
run_status env || { echo "expected cache-mode status snapshot to succeed" >&2; exit 1; }

row="$(grep '"tool":"claude"' "$STATUS" | tail -1)"
jq -e '
    .ok == true
    and .status_source == "cache"
    and .source == "anthropic"
    and .five_hour.used_percent == 38
    and .five_hour.remaining_percent == 62
    and (.cache_age_seconds | type == "number")
    and .cache_age_seconds >= 0
  ' <<<"$row" >/dev/null \
  || { echo "unexpected cache-mode status row: $row" >&2; exit 1; }
raw_log="$(jq -r '.raw_log' <<<"$row")"
[[ -f "$raw_log" ]] || { echo "expected raw snapshot artifact at $raw_log" >&2; exit 1; }
[[ ! -e "$SENTINEL_DIR/omc-invoked" ]] \
  || { echo "cache mode must not invoke omc" >&2; exit 1; }
[[ ! -e "$SENTINEL_DIR/claude-invoked" ]] \
  || { echo "cache mode must not invoke claude" >&2; exit 1; }

# ── B) missing cache: snapshot fails, no row appended ───────────────────────
rows_before="$(grep -c '"tool":"claude"' "$STATUS" || true)"
rm -f "$CACHE"
if run_status env; then
  echo "expected status snapshot to fail when the cache file is missing" >&2
  exit 1
fi
rows_after="$(grep -c '"tool":"claude"' "$STATUS" || true)"
[[ "$rows_before" == "$rows_after" ]] \
  || { echo "expected no status row for a missing cache" >&2; exit 1; }

# ── C) cache with error=true records ok=false ───────────────────────────────
write_cache 38 "2099-01-01T00:00:00.673Z" true
run_status env || true
jq -e '.ok == false and .status_source == "cache"' \
  <<<"$(grep '"tool":"claude"' "$STATUS" | tail -1)" >/dev/null \
  || { echo "expected ok=false for an error cache" >&2; exit 1; }

# ── D) legacy omc mode still performs the live query ────────────────────────
rm -rf "$SENTINEL_DIR" && mkdir -p "$SENTINEL_DIR"
write_cache 38 "2099-01-01T00:00:00.673Z"
run_status env CLAUDE_STATUS_SOURCE=omc \
  || { echo "expected omc-mode status snapshot to succeed" >&2; exit 1; }
[[ -e "$SENTINEL_DIR/omc-invoked" ]] \
  || { echo "omc mode must invoke omc" >&2; exit 1; }
jq -e '.status_source == "omc"' \
  <<<"$(grep '"tool":"claude"' "$STATUS" | tail -1)" >/dev/null \
  || { echo "expected status_source=omc in legacy mode" >&2; exit 1; }

# ── E) invalid CLAUDE_STATUS_SOURCE is rejected ─────────────────────────────
if CLAUDE_STATUS_SOURCE=bogus "$ENGINE" --status --tool claude >/dev/null 2>&1; then
  echo "expected CLAUDE_STATUS_SOURCE=bogus to be rejected" >&2
  exit 1
fi

# ── F) preflight: exhausted window with a passed resets_at must not skip ────
run_once() {
  CLAUDE_USAGE_CACHE_FILE="$CACHE" \
    OMC_BIN="$TMP_DIR/bin/omc-fake" \
    CLAUDE_BIN="$TMP_DIR/bin/claude-fake" \
    ACTIVATION_TOOL=claude \
    "$ENGINE" --once --tool claude >/dev/null 2>&1 || true
}

rm -rf "$SENTINEL_DIR" && mkdir -p "$SENTINEL_DIR"
past="$(date -u -v-2H '+%Y-%m-%dT%H:%M:%S.000Z')"
write_cache 100 "$past"
run_once
[[ -e "$SENTINEL_DIR/claude-invoked" ]] \
  || { echo "expected run to proceed when the exhausted window already reset" >&2; exit 1; }
jq -e '(.skipped // false) == false' \
  <<<"$(grep '"tool":"claude"' "$USAGE" | tail -1)" >/dev/null \
  || { echo "expected a non-skipped usage row after a passed reset" >&2; exit 1; }

rm -rf "$SENTINEL_DIR" && mkdir -p "$SENTINEL_DIR"
future="$(date -u -v+2H '+%Y-%m-%dT%H:%M:%S.000Z')"
write_cache 100 "$future"
run_once
[[ ! -e "$SENTINEL_DIR/claude-invoked" ]] \
  || { echo "expected run to be skipped while the window is still exhausted" >&2; exit 1; }
jq -e '.skipped == true and .skip_reason == "quota_exhausted"' \
  <<<"$(grep '"tool":"claude"' "$USAGE" | tail -1)" >/dev/null \
  || { echo "expected a skipped usage row for an unexpired exhausted window" >&2; exit 1; }

echo "claude status cache test passed"
