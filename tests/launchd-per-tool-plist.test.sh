#!/usr/bin/env bash
set -euo pipefail

# Verifies per-tool LaunchAgent generation in scripts/install-launchd.sh using
# print-plist only (never install/launchctl): one plist per enabled tool with
# `--once --scheduled --tool <tool>`, no Weekday key for daily schedules, launchd Weekday ints
# (1=Mon..6=Sat, 0=Sun) for day lists, SCHEDULE_TIMES fallback, and rejection of
# invalid days. STOKER_ROOT + a temp HOME keep the real repo and
# ~/Library/LaunchAgents untouched.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/home"
SCRIPT="$ROOT_DIR/scripts/install-launchd.sh"
LABEL_BASE="com.example.stoker.test"

print_plist() {
  env -u SCHEDULE_TIMES -u CLAUDE_SCHEDULE_TIMES -u CODEX_SCHEDULE_TIMES \
    -u CLAUDE_SCHEDULE_DAYS -u CODEX_SCHEDULE_DAYS -u ACTIVATION_TOOL \
    STOKER_ROOT="$TMP_DIR" HOME="$TMP_DIR/home" LABEL="$LABEL_BASE" \
    "$@" "$SCRIPT" print-plist "${PLIST_TOOL:-}"
}

# plist_json <tool> [env...] → the tool's plist as JSON
plist_json() {
  local tool="$1"
  shift
  PLIST_TOOL="$tool" print_plist "$@" >"$TMP_DIR/$tool.plist"
  plutil -lint "$TMP_DIR/$tool.plist" >/dev/null
  plutil -convert json -o - "$TMP_DIR/$tool.plist"
}

# A) defaults: both tools daily at the default times, correct label + --tool arg.
for tool in claude codex; do
  json="$(plist_json "$tool")"
  jq -e --arg label "$LABEL_BASE.$tool" --arg tool "$tool" --arg root "$TMP_DIR" '
    .Label == $label
    and .ProgramArguments == ["/bin/bash", ($root + "/bin/activate-ai-window.sh"), "--once", "--scheduled", "--tool", $tool]
    and .WorkingDirectory == $root
    and .RunAtLoad == false
    and (.StartCalendarInterval | map([.Hour, .Minute])) == [[7,0],[12,0],[17,0],[22,0]]
    and all(.StartCalendarInterval[]; has("Weekday") | not)
  ' <<<"$json" >/dev/null || { echo "default $tool plist wrong: $json" >&2; exit 1; }
done

# B) per-tool times + days: Codex Mon/Thu/Sun → Weekday 1, 4, 0 for every time,
#    sorted/deduped; Claude falls back to SCHEDULE_TIMES and stays daily.
json="$(plist_json codex CODEX_SCHEDULE_TIMES="7:00, 19:30,07:00" CODEX_SCHEDULE_DAYS="Sun,thu,MON,thu")"
jq -e '
  (.StartCalendarInterval | map([.Weekday, .Hour, .Minute]))
    == [[1,7,0],[4,7,0],[0,7,0],[1,19,30],[4,19,30],[0,19,30]]
' <<<"$json" >/dev/null || { echo "weekly codex plist wrong: $json" >&2; exit 1; }

json="$(plist_json claude SCHEDULE_TIMES="06:15,21:15" CODEX_SCHEDULE_TIMES="07:00")"
jq -e '
  (.StartCalendarInterval | map([.Hour, .Minute])) == [[6,15],[21,15]]
  and all(.StartCalendarInterval[]; has("Weekday") | not)
' <<<"$json" >/dev/null || { echo "SCHEDULE_TIMES fallback wrong: $json" >&2; exit 1; }

# An empty per-tool value also falls back; "daily" and all seven days mean every day.
json="$(plist_json codex CODEX_SCHEDULE_TIMES="" SCHEDULE_TIMES="08:00" CODEX_SCHEDULE_DAYS="daily")"
jq -e '(.StartCalendarInterval | map([.Hour, .Minute])) == [[8,0]] and all(.StartCalendarInterval[]; has("Weekday") | not)' \
  <<<"$json" >/dev/null || { echo "empty/daily fallback wrong: $json" >&2; exit 1; }
json="$(plist_json codex CODEX_SCHEDULE_DAYS="mon,tue,wed,thu,fri,sat,sun")"
jq -e 'all(.StartCalendarInterval[]; has("Weekday") | not)' <<<"$json" >/dev/null \
  || { echo "seven days should collapse to daily: $json" >&2; exit 1; }

# C) print-plist without a tool prints one header + plist per ENABLED tool only.
out="$(print_plist ACTIVATION_TOOL=codex)"
[[ "$(grep -c '^==> ' <<<"$out")" == "1" ]] || { echo "expected one plist for ACTIVATION_TOOL=codex: $out" >&2; exit 1; }
grep -q "^==> $TMP_DIR/launchd/$LABEL_BASE.codex.plist <==\$" <<<"$out" \
  || { echo "missing codex header: $out" >&2; exit 1; }
out="$(print_plist ACTIVATION_TOOL=all)"
[[ "$(grep -c '^==> ' <<<"$out")" == "2" ]] || { echo "expected two plists for ACTIVATION_TOOL=all" >&2; exit 1; }

# D) invalid values are rejected with exit 2 before anything is printed.
expect_rejected() {
  local label="$1"
  shift
  local status=0
  PLIST_TOOL=codex print_plist "$@" >"$TMP_DIR/out" 2>"$TMP_DIR/err" || status=$?
  [[ "$status" == "2" ]] || { echo "$label: expected exit 2, got $status" >&2; exit 1; }
  [[ ! -s "$TMP_DIR/out" ]] || { echo "$label: expected no plist output" >&2; exit 1; }
}
expect_rejected "invalid day" CODEX_SCHEDULE_DAYS="mon,funday"
expect_rejected "daily mixed with days" CODEX_SCHEDULE_DAYS="daily,mon"
expect_rejected "invalid time" CODEX_SCHEDULE_TIMES="25:00"
expect_rejected "invalid ACTIVATION_TOOL" ACTIVATION_TOOL=both
grep -q "ACTIVATION_TOOL" "$TMP_DIR/err" || { echo "missing ACTIVATION_TOOL error" >&2; exit 1; }
status=0
PLIST_TOOL=gemini print_plist >/dev/null 2>&1 || status=$?
[[ "$status" == "2" ]] || { echo "unknown print-plist tool should exit 2, got $status" >&2; exit 1; }

echo "launchd per-tool plist test passed"
