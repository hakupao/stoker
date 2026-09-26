#!/usr/bin/env bash
set -euo pipefail

# Verifies the Codex idle-window preflight policy (CODEX_ACTIVATE_ONLY_WHEN_IDLE):
# Codex is weekly-only (7-day window since Sept 2026), so a prompt is skipped with reason
# window_already_active while the 7-day window is already anchored, and allowed
# while it is idle. Cases:
#   A) idle signature (resets_at == now + full window) → allow
#   B) anchored (resets_at < now + window - 15min)      → skip window_already_active
#   D) CODEX_ACTIVATE_ONLY_WHEN_IDLE=0                   → allow
#   E) anchored AND exhausted                            → skip quota_exhausted
#   F) invalid CODEX_ACTIVATE_ONLY_WHEN_IDLE             → rejected up front
#   G) boundaries: 10 min short of a full window → allow (inside the 15-min
#      slack); ~17 min short → skip; reset already passed → allow
#   H) the anchor test is measured from the row's captured_at_epoch, not the
#      decision time: a row captured an hour before the decision still reads idle
#
# Quota comes from CODEX_STATUS_SOURCE=native with a fake curl (no node, no
# network); `codex exec` is a fake that leaves a sentinel. The engine is copied
# into a temp root so the real .env/logs are never touched.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/codex-probe"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"
ENGINE="$TMP_DIR/bin/activate-ai-window.sh"
USAGE="$TMP_DIR/logs/usage.jsonl"
AUTH="$TMP_DIR/auth.json"
export SENTINEL_DIR="$TMP_DIR/sentinels"

jq -n '{tokens: {access_token: "tok", account_id: "acct"}}' >"$AUTH"

# Fake wham/usage: one weekly window (used $USED_PCT, resets $RESET_OFFSET seconds
# from now) — Codex reports no 5-hour window.
cat >"$TMP_DIR/bin/curl-fake" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
[[ "${CURL_FAIL:-0}" == "1" ]] && exit 22
now=$(date +%s)
weekly="{\"used_percent\":${USED_PCT},\"limit_window_seconds\":604800,\"reset_at\":$(( now + RESET_OFFSET ))}"
printf '{"plan_type":"plus","rate_limit":{"allowed":true,"primary_window":%s,"secondary_window":null}}\n' "$weekly"
SH
cat >"$TMP_DIR/bin/codex-fake" <<'SH'
#!/usr/bin/env bash
touch "${SENTINEL_DIR}/codex-invoked"
echo '{"type":"item.completed","item":{"type":"agent_message","text":"READY"}}'
SH
chmod +x "$TMP_DIR/bin/curl-fake" "$TMP_DIR/bin/codex-fake"

run_once() {
  rm -rf "$SENTINEL_DIR" && mkdir -p "$SENTINEL_DIR"
  CODEX_STATUS_SOURCE=native \
    CODEX_AUTH_FILE="$AUTH" \
    CURL_BIN="$TMP_DIR/bin/curl-fake" \
    CODEX_BIN="$TMP_DIR/bin/codex-fake" \
    CODEX_WORK_DIR="$TMP_DIR/codex-probe" \
    ACTIVATION_TOOL=codex \
    KEEP_AWAKE_MODE=off \
    "$@" "$ENGINE" --once --tool codex >/dev/null 2>&1 || true
}

last_codex_usage() { grep '"tool":"codex"' "$USAGE" | tail -1; }

expect_allowed() {
  local label="$1"
  [[ -e "$SENTINEL_DIR/codex-invoked" ]] \
    || { echo "$label: expected the Codex prompt to be sent" >&2; exit 1; }
  jq -e '(.skipped // false) == false' <<<"$(last_codex_usage)" >/dev/null \
    || { echo "$label: expected a non-skipped usage row" >&2; exit 1; }
}

expect_skipped() {
  local label="$1" reason="$2"
  [[ ! -e "$SENTINEL_DIR/codex-invoked" ]] \
    || { echo "$label: expected the Codex prompt to be skipped" >&2; exit 1; }
  jq -e --arg r "$reason" '.skipped == true and .skip_reason == $r' <<<"$(last_codex_usage)" >/dev/null \
    || { echo "$label: expected skip_reason=$reason, got: $(last_codex_usage)" >&2; exit 1; }
}

# A) idle: resets exactly one full window from now (drifts with each query)
run_once env USED_PCT=0 RESET_OFFSET=604800
expect_allowed "idle window"

# B) anchored: 3 days left in the running window
run_once env USED_PCT=5 RESET_OFFSET=259200
expect_skipped "anchored window" "window_already_active"
jq -e '.preflight.exhausted == [] and .preflight.status_ok == true' <<<"$(last_codex_usage)" >/dev/null \
  || { echo "anchored skip must not be reported as exhaustion: $(last_codex_usage)" >&2; exit 1; }

# D) policy disabled
run_once env USED_PCT=5 RESET_OFFSET=259200 CODEX_ACTIVATE_ONLY_WHEN_IDLE=0
expect_allowed "policy disabled"

# E) exhaustion keeps priority and its own reason
run_once env USED_PCT=100 RESET_OFFSET=259200
expect_skipped "anchored + exhausted" "quota_exhausted"

# F) invalid value rejected
if CODEX_ACTIVATE_ONLY_WHEN_IDLE=yes "$ENGINE" --dry-run --tool codex >/dev/null 2>&1; then
  echo "expected CODEX_ACTIVATE_ONLY_WHEN_IDLE=yes to be rejected" >&2
  exit 1
fi

# G) boundaries around the 15-minute slack, and a passed reset
run_once env USED_PCT=0 RESET_OFFSET=$(( 604800 - 600 ))
expect_allowed "within slack"
run_once env USED_PCT=1 RESET_OFFSET=$(( 604800 - 1000 ))
expect_skipped "just past slack" "window_already_active"
run_once env USED_PCT=5 RESET_OFFSET=-600
expect_allowed "reset passed"

# H) capture time, not decision time. With the live query failing (CURL_FAIL=1),
#    the decision falls back to a pre-seeded row for this RUN_ID captured an hour
#    ago whose reset is exactly one window after its capture (idle signature).
STATUS="$TMP_DIR/logs/status.jsonl"
seed_row() {
  local run_id="$1" with_captured="$2"
  local captured=$(( $(date +%s) - 3600 ))
  jq -n -c --arg run_id "$run_id" --argjson captured "$captured" --argjson with "$with_captured" '
    {tool: "codex", run_id: $run_id, ok: true, five_hour: null,
     weekly: {used_percent: 0, remaining_percent: 100, window_minutes: 10080,
              resets_at_epoch: ($captured + 604800)}}
    + (if $with then {captured_at_epoch: $captured} else {} end)' >>"$STATUS"
}
seed_row "seeded-captured" true
run_once env RUN_ID=seeded-captured CURL_FAIL=1 USED_PCT=0 RESET_OFFSET=0
expect_allowed "captured an hour ago, idle at capture"
# Same row without captured_at_epoch falls back to decision time → looks anchored.
seed_row "seeded-legacy" false
run_once env RUN_ID=seeded-legacy CURL_FAIL=1 USED_PCT=0 RESET_OFFSET=0
expect_skipped "legacy row without captured_at" "window_already_active"

echo "codex idle-window test passed"
