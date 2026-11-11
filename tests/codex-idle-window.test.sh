#!/usr/bin/env bash
set -euo pipefail

# Verifies the Codex idle-window preflight policy (CODEX_ACTIVATE_ONLY_WHEN_IDLE):
# the gate looks at the shortest window the snapshot reports (five_hour when the
# plan has one, else weekly): a prompt is skipped with reason window_already_active
# while that window is already anchored, and allowed while it is idle. Cases
# A-H are weekly-only plans; I-K add a 5-hour window:
#   A) idle signature (resets_at == now + full window) → allow
#   B) anchored (resets_at < now + window - 15min)      → skip window_already_active
#   D) CODEX_ACTIVATE_ONLY_WHEN_IDLE=0                   → allow
#   E) anchored AND exhausted                            → skip quota_exhausted
#   F) invalid CODEX_ACTIVATE_ONLY_WHEN_IDLE             → rejected up front
#   G) boundaries: 10 min short of a full window → allow (inside the 15-min
#      slack); ~17 min short → skip; reset already passed → allow
#   H) the anchor test is measured from the row's captured_at_epoch, not the
#      decision time: a row captured an hour before the decision still reads idle
#   I) 5h idle + weekly anchored                        → allow (gate_window five_hour)
#   J) 5h anchored + weekly idle                        → skip window_already_active
#   K) 5h reset already passed + weekly anchored        → allow
#   L) anchored gate window resetting within CODEX_RESET_WAIT_MAX_SECONDS → wait
#      for the reset, then a real run (5h and weekly-only); max=0 or a reset
#      beyond the max → skip window_already_active; an invalid max is rejected
#   M) gate window exhausted AND resetting within the max → skip quota_exhausted
#      at once (exhaustion wins; no wait)
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

# Fake wham/usage: a weekly window (used $USED_PCT, resets $RESET_OFFSET seconds
# from now). With FIVE_USED_PCT/FIVE_RESET_OFFSET set it also reports a 5-hour
# window as primary (weekly then secondary); unset, the plan is weekly-only.
cat >"$TMP_DIR/bin/curl-fake" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
[[ "${CURL_FAIL:-0}" == "1" ]] && exit 22
now=$(date +%s)
weekly="{\"used_percent\":${USED_PCT},\"limit_window_seconds\":604800,\"reset_at\":$(( now + RESET_OFFSET ))}"
if [[ -n "${FIVE_USED_PCT:-}" ]]; then
  five="{\"used_percent\":${FIVE_USED_PCT},\"limit_window_seconds\":18000,\"reset_at\":$(( now + FIVE_RESET_OFFSET ))}"
  printf '{"plan_type":"plus","rate_limit":{"allowed":true,"primary_window":%s,"secondary_window":%s}}\n' "$five" "$weekly"
else
  printf '{"plan_type":"plus","rate_limit":{"allowed":true,"primary_window":%s,"secondary_window":null}}\n' "$weekly"
fi
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
jq -e '.preflight.gate_window == "weekly"' <<<"$(last_codex_usage)" >/dev/null \
  || { echo "weekly-only skip must gate on weekly: $(last_codex_usage)" >&2; exit 1; }

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

# I) 5h idle (reset one full 5h window out) while the week is anchored → allow
#    (weekly-only gating would skip this; the snapshot must carry the 5h lane).
run_once env FIVE_USED_PCT=1 FIVE_RESET_OFFSET=18000 USED_PCT=40 RESET_OFFSET=259200
expect_allowed "5h idle, weekly anchored"
grep '"tool":"codex"' "$TMP_DIR/logs/status.jsonl" | tail -1 \
  | jq -e '.five_hour.window_minutes == 300 and .weekly.window_minutes == 10080' >/dev/null \
  || { echo "5h fixture must yield a five_hour + weekly snapshot" >&2; exit 1; }

# J) 5h anchored (2h left) while the week is idle → skip on the 5h window
run_once env FIVE_USED_PCT=10 FIVE_RESET_OFFSET=7200 USED_PCT=0 RESET_OFFSET=604800
expect_skipped "5h anchored" "window_already_active"
jq -e '.preflight.gate_window == "five_hour" and .preflight.exhausted == []' <<<"$(last_codex_usage)" >/dev/null \
  || { echo "5h anchored skip must gate on five_hour: $(last_codex_usage)" >&2; exit 1; }

# K) 5h reset already passed (window rolled over) while the week is anchored → allow
run_once env FIVE_USED_PCT=10 FIVE_RESET_OFFSET=-600 USED_PCT=40 RESET_OFFSET=259200
expect_allowed "5h reset passed, weekly anchored"

# L) reset a few seconds away: the runner sleeps until reset + 5s, then sends
expect_waited() {
  local label="$1" started="$2"
  expect_allowed "$label"
  (( $(date +%s) - started >= 5 )) \
    || { echo "$label: expected the run to wait for the reset" >&2; exit 1; }
  grep -q 'codex quota preflight: anchored window resets soon; waiting' "$TMP_DIR/logs/activation.log" \
    || { echo "$label: expected the wait to be logged" >&2; exit 1; }
}
: >"$TMP_DIR/logs/activation.log"
started=$(date +%s)
run_once env FIVE_USED_PCT=10 FIVE_RESET_OFFSET=2 USED_PCT=40 RESET_OFFSET=259200
expect_waited "5h resets soon" "$started"
: >"$TMP_DIR/logs/activation.log"
started=$(date +%s)
run_once env USED_PCT=40 RESET_OFFSET=2
expect_waited "weekly resets soon" "$started"

run_once env FIVE_USED_PCT=10 FIVE_RESET_OFFSET=2 USED_PCT=40 RESET_OFFSET=259200 CODEX_RESET_WAIT_MAX_SECONDS=0
expect_skipped "reset wait disabled" "window_already_active"
run_once env FIVE_USED_PCT=10 FIVE_RESET_OFFSET=400 USED_PCT=40 RESET_OFFSET=259200
expect_skipped "reset beyond the default max" "window_already_active"
run_once env FIVE_USED_PCT=10 FIVE_RESET_OFFSET=30 USED_PCT=40 RESET_OFFSET=259200 CODEX_RESET_WAIT_MAX_SECONDS=10
expect_skipped "reset beyond a custom max" "window_already_active"

# M) exhaustion wins over the reset wait: skipped immediately, no sleep
started=$(date +%s)
run_once env FIVE_USED_PCT=100 FIVE_RESET_OFFSET=60 USED_PCT=40 RESET_OFFSET=259200
expect_skipped "5h exhausted, resets soon" "quota_exhausted"
(( $(date +%s) - started < 30 )) \
  || { echo "exhausted + resets soon must not wait for the reset" >&2; exit 1; }
jq -e '.preflight.wait_seconds == null' <<<"$(last_codex_usage)" >/dev/null \
  || { echo "exhausted skip must carry no wait: $(last_codex_usage)" >&2; exit 1; }

if CODEX_RESET_WAIT_MAX_SECONDS=-1 "$ENGINE" --dry-run --tool codex >/dev/null 2>&1; then
  echo "expected CODEX_RESET_WAIT_MAX_SECONDS=-1 to be rejected" >&2
  exit 1
fi

echo "codex idle-window test passed"
