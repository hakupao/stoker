#!/usr/bin/env bash
set -euo pipefail

# Verifies the `limits` object in activation-state.sh --json and the
# `./install.sh recommend` view: each tool's profile is judged from the windows
# its latest snapshot reports, not from the plan name. Fixtures are modelled on
# real historical status rows (user-specific fields removed). Their resets are
# in the past, so the windows are blanked with reset_passed — a rolled-over
# window still counts as present.
#   1) Claude idle 5h (used 0 / reset null) + weekly      → session_weekly / session_window
#   2) Claude no 5h (used null / reset null) + weekly      → weekly_only / not_needed
#   3) Codex five_hour + weekly objects                    → session_weekly / session_window
#   4) Codex five_hour null + weekly                       → weekly_only / weekly_anchor
#   5) no snapshot, and an ok:false snapshot               → unknown
#   6) Claude 5h rolled over (reset passed)                → session_weekly
#   7) Codex 5h only → session_only / session_window; ok snapshot without
#      windows → none / unknown
#   8) codex `gate` (the engine's idle-gate rule, evaluated at read time): idle 5h
#      with used 1 → inactive; anchored 5h → active five_hour; weekly-only
#      anchored → active weekly; reset passed → inactive; a row without
#      captured_at_epoch is measured from its timestamp; Claude gate is null

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/logs"
# Hermetic: never read the real machine's omc usage cache.
export CLAUDE_USAGE_CACHE_FILE="$TMP_DIR/usage-cache.json"
printf 'LABEL=com.example.stoker.test\nACTIVATION_TOOL=all\n' >"$TMP_DIR/.env"

state() {
  STOKER_ROOT="$TMP_DIR" STOKER_SKIP_LAUNCHCTL=1 "$ROOT_DIR/bin/activation-state.sh" --json
}

expect() {
  local label="$1" filter="$2" json
  json="$(state)"
  jq -e "$filter" <<<"$json" >/dev/null \
    || { echo "$label: limits mismatch: $(jq -c .limits <<<"$json")" >&2; exit 1; }
}

DEFAULT='["07:00","12:00","17:00","22:00"]'

# 1 + 3: Claude idle 5h, Codex plus with a 5-hour window
cat >"$TMP_DIR/logs/status.jsonl" <<'JSONL'
{"timestamp":"2026-11-01 07:00:09 JST","run_id":"r1","tool":"claude","ok":true,"status_source":"cache","source":"anthropic","subscription_type":"max","cache_timestamp_ms":1793469602886,"five_hour":{"used_percent":0,"remaining_percent":100,"resets_at":null},"weekly":{"used_percent":85,"remaining_percent":15,"resets_at":"2026-11-02T07:59:59.746Z"},"sonnet_weekly":{"used_percent":null,"remaining_percent":null,"resets_at":null},"scoped_weekly":[]}
{"timestamp":"2026-09-04 12:00:26 JST","run_id":"r1","tool":"codex","ok":true,"plan_type":"plus","limit_id":"codex","rate_limit_reached_type":null,"five_hour":{"used_percent":0,"remaining_percent":100,"window_minutes":300,"resets_at_epoch":1788508825,"resets_at":"2026-09-04T08:00:25Z"},"weekly":{"used_percent":11,"remaining_percent":89,"window_minutes":10080,"resets_at_epoch":1788755226,"resets_at":"2026-09-07T04:27:06Z"},"error":null}
JSONL
expect "claude idle 5h / codex 5h+weekly" "
  .limits.claude == {profile: \"session_weekly\", session_minutes: 300, weekly_reset: \"fixed\", gate: null, plan: \"max\",
                     recommended: {times: $DEFAULT, days: [], reason: \"session_window\"}}
  and .limits.codex == {profile: \"session_weekly\", session_minutes: 300, weekly_reset: \"on_first_use\", gate: {window: \"five_hour\", active: false}, plan: \"plus\",
                        recommended: {times: $DEFAULT, days: [], reason: \"session_window\"}}
  and .quota.claude.weekly.reset_passed == true"
out="$(STOKER_ROOT="$TMP_DIR" STOKER_SKIP_LAUNCHCTL=1 "$ROOT_DIR/install.sh" recommend)"
grep -q 'CLAUDE_SCHEDULE_TIMES=07:00,12:00,17:00,22:00' <<<"$out" \
  || { echo "recommend must print the Claude .env line: $out" >&2; exit 1; }
grep -q 'CODEX_SCHEDULE_DAYS=daily' <<<"$out" \
  || { echo "recommend must print the Codex days line: $out" >&2; exit 1; }
grep -q '5-hour session' <<<"$out" \
  || { echo "recommend must list the 5-hour window: $out" >&2; exit 1; }

# 2 + 4: Claude without a 5-hour window, Codex weekly-only (plan_type unknown → null)
cat >"$TMP_DIR/logs/status.jsonl" <<'JSONL'
{"timestamp":"2026-11-11 07:00:09 JST","run_id":"r2","tool":"claude","ok":true,"status_source":"cache","source":"anthropic","subscription_type":null,"cache_timestamp_ms":1794231939050,"five_hour":{"used_percent":null,"remaining_percent":null,"resets_at":null},"weekly":{"used_percent":7,"remaining_percent":93,"resets_at":"2026-11-10T07:59:59.862Z"},"sonnet_weekly":{"used_percent":null,"remaining_percent":null,"resets_at":null},"scoped_weekly":[]}
{"timestamp":"2026-11-11 07:00:12 JST","run_id":"r2","tool":"codex","ok":true,"captured_at_epoch":1794348012,"plan_type":"unknown","limit_id":"codex","rate_limit_reached_type":null,"five_hour":null,"weekly":{"used_percent":55,"remaining_percent":45,"window_minutes":10080,"resets_at_epoch":1794297873,"resets_at":"2026-11-10T08:04:33Z"},"error":null}
JSONL
expect "claude no 5h / codex weekly-only" '
  .limits.claude == {profile: "weekly_only", session_minutes: null, weekly_reset: "fixed", gate: null, plan: null,
                     recommended: {times: [], days: [], reason: "not_needed"}}
  and .limits.codex == {profile: "weekly_only", session_minutes: null, weekly_reset: "on_first_use", gate: {window: "weekly", active: false}, plan: null,
                        recommended: {times: ["07:00"], days: [], reason: "weekly_anchor"}}
  and .quota.claude.weekly.reset_passed == true and .quota.codex.weekly.reset_passed == true'
out="$(STOKER_ROOT="$TMP_DIR" STOKER_SKIP_LAUNCHCTL=1 "$ROOT_DIR/install.sh" recommend)"
grep -q 'resets at a fixed time, so check-ins anchor nothing' <<<"$out" \
  || { echo "recommend must explain not_needed: $out" >&2; exit 1; }
grep -q 'ACTIVATION_TOOL=codex' <<<"$out" \
  || { echo "recommend must offer disabling Claude: $out" >&2; exit 1; }
if grep -q 'CLAUDE_SCHEDULE_TIMES=' <<<"$out"; then
  echo "not_needed must not print an empty CLAUDE_SCHEDULE_TIMES line (it falls back to the default)" >&2
  exit 1
fi
grep -q 'CODEX_SCHEDULE_TIMES=07:00$' <<<"$out" \
  || { echo "recommend must print the Codex weekly_anchor line: $out" >&2; exit 1; }
cmp -s <(printf 'LABEL=com.example.stoker.test\nACTIVATION_TOOL=all\n') "$TMP_DIR/.env" \
  || { echo "recommend must not modify .env" >&2; exit 1; }

# 5: Claude snapshot not ok, Codex snapshot missing → unknown with the default times
cat >"$TMP_DIR/logs/status.jsonl" <<'JSONL'
{"timestamp":"2026-11-11 07:00:09 JST","run_id":"r3","tool":"claude","ok":false,"five_hour":null,"weekly":null,"error":"cache unavailable"}
JSONL
expect "not ok / missing" "
  .limits.claude.profile == \"unknown\" and .limits.claude.session_minutes == null
  and .limits.claude.recommended == {times: $DEFAULT, days: [], reason: \"unknown\"}
  and .limits.codex.profile == \"unknown\" and .limits.codex.plan == null and .limits.codex.gate == null
  and .limits.codex.recommended == {times: $DEFAULT, days: [], reason: \"unknown\"}"
rm -f "$TMP_DIR/logs/status.jsonl"
expect "no status log" '.limits.claude.profile == "unknown" and .limits.codex.profile == "unknown"'

# 6 + 7: Claude 5h with a passed reset still exists; Codex 5h-only; then no windows
cat >"$TMP_DIR/logs/status.jsonl" <<'JSONL'
{"timestamp":"2026-09-02 07:00:05 JST","run_id":"r4","tool":"claude","ok":true,"status_source":"cache","source":"anthropic","subscription_type":null,"cache_timestamp_ms":1788300000000,"five_hour":{"used_percent":2,"remaining_percent":98,"resets_at":"2026-09-01T18:00:00.321Z"},"weekly":{"used_percent":40,"remaining_percent":60,"resets_at":"2026-09-07T07:59:59.746Z"},"sonnet_weekly":{"used_percent":null,"remaining_percent":null,"resets_at":null},"scoped_weekly":[]}
{"timestamp":"2026-09-04 12:00:26 JST","run_id":"r4","tool":"codex","ok":true,"plan_type":"plus","five_hour":{"used_percent":0,"remaining_percent":100,"window_minutes":300,"resets_at_epoch":1788508825,"resets_at":"2026-09-04T08:00:25Z"},"weekly":null,"error":null}
JSONL
expect "claude 5h rolled over / codex 5h only" "
  .quota.claude.five_hour.reset_passed == true
  and .limits.claude.profile == \"session_weekly\" and .limits.claude.recommended.reason == \"session_window\"
  and .limits.codex.profile == \"session_only\" and .limits.codex.session_minutes == 300
  and .limits.codex.recommended == {times: $DEFAULT, days: [], reason: \"session_window\"}"
cat >"$TMP_DIR/logs/status.jsonl" <<'JSONL'
{"timestamp":"2026-11-11 07:00:12 JST","run_id":"r5","tool":"codex","ok":true,"plan_type":"plus","five_hour":null,"weekly":null,"error":null}
JSONL
expect "codex no windows" "
  .limits.codex.profile == \"none\" and .limits.codex.recommended == {times: $DEFAULT, days: [], reason: \"unknown\"}"

# 8: gate verdicts. Rows are generated relative to now.
gate_case() {
  local label="$1" row="$2" expected="$3" json
  printf '%s\n' "$row" >"$TMP_DIR/logs/status.jsonl"
  json="$(state)"
  jq -e --argjson want "$expected" '.limits.codex.gate == $want and .limits.claude.gate == null' <<<"$json" >/dev/null \
    || { echo "$label: gate mismatch: $(jq -c .limits.codex.gate <<<"$json")" >&2; exit 1; }
}
codex_row() { # captured five_offset(seconds from capture, or null) weekly_offset
  jq -n -c --argjson c "$1" --argjson f "$2" --argjson w "$3" '
    def win($mins; $off; $used):
      {used_percent: $used, remaining_percent: (100 - $used), window_minutes: $mins,
       resets_at_epoch: ($c + $off), resets_at: (($c + $off) | todateiso8601)};
    {timestamp: "2026-11-11 07:00:12 JST", run_id: "g", tool: "codex", ok: true, plan_type: "plus",
     captured_at_epoch: $c,
     five_hour: (if $f == null then null else win(300; $f; 1) end),
     weekly: win(10080; $w; 40)}'
}
now=$(date +%s)
gate_case "idle 5h, used 1" "$(codex_row "$now" 18000 259200)" '{"window":"five_hour","active":false}'
gate_case "anchored 5h" "$(codex_row "$now" 7200 604800)" '{"window":"five_hour","active":true}'
gate_case "weekly-only anchored" "$(codex_row "$now" null 259200)" '{"window":"weekly","active":true}'
gate_case "weekly-only idle" "$(codex_row "$now" null 604800)" '{"window":"weekly","active":false}'
# Captured 6h ago with a 5h reset: the reset has since passed → inactive.
gate_case "5h reset passed" "$(codex_row $(( now - 21600 )) 7200 259200)" '{"window":"five_hour","active":false}'
# Captured 1h ago as idle (reset = capture + 5h), no captured_at_epoch: measured
# from the row timestamp it is still idle (from now it would look anchored).
then=$(( now - 3600 ))
legacy="$(codex_row "$then" 18000 259200 \
  | jq -c --arg ts "$(date -r "$then" '+%Y-%m-%d %H:%M:%S %Z')" 'del(.captured_at_epoch) | .timestamp = $ts')"
gate_case "legacy row, timestamp capture" "$legacy" '{"window":"five_hour","active":false}'

echo "limits profile test passed"
