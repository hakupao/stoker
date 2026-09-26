#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/logs"

# Hermetic: never read the real machine's omc usage cache (absent until a case
# writes it).
export CLAUDE_USAGE_CACHE_FILE="$TMP_DIR/usage-cache.json"

cat >"$TMP_DIR/.env" <<'ENV'
LABEL=com.example.stoker.test
SCHEDULE_TIMES="06:15,13:15,21:15"
ACTIVATION_TOOL=codex
CODEX_MODEL=gpt-5.6-luna
ENABLE_STATUS_SNAPSHOTS=0
ENABLE_QUOTA_PREFLIGHT=1
KEEP_AWAKE_MODE=during
KEEP_AWAKE_SECONDS=600
ENV

cat >"$TMP_DIR/logs/status.jsonl" <<'JSONL'
{"timestamp":"2026-05-27 10:00:00 JST","run_id":"r1","tool":"claude","ok":true,"five_hour":{"remaining_percent":72},"weekly":{"remaining_percent":61},"sonnet_weekly":{"remaining_percent":58}}
{"timestamp":"2026-05-27 10:01:00 JST","run_id":"r1","tool":"codex","ok":true,"five_hour":{"remaining_percent":81},"weekly":{"remaining_percent":69}}
JSONL

cat >"$TMP_DIR/logs/usage.jsonl" <<'JSONL'
{"timestamp":"2026-05-27 10:02:00 JST","run_id":"r1","tool":"codex","ok":true,"result":"READY"}
JSONL

json="$(
  STOKER_ROOT="$TMP_DIR" \
  STOKER_SKIP_LAUNCHCTL=1 \
  "$ROOT_DIR/bin/activation-state.sh" --json
)"

jq -e '
  .installed == false
  and .running == false
  and .label == "com.example.stoker.test"
  and .schedule.times == ["06:15", "13:15", "21:15"]
  and .config.activation_tool == "codex"
  and .config.codex_model == "gpt-5.6-luna"
  and .config.enable_status_snapshots == false
  and .config.enable_quota_preflight == true
  and .config.codex_activate_only_when_idle == true
  and .keep_awake.mode == "during"
  and .keep_awake.seconds == 600
  and .quota.codex.five_hour.remaining_percent == 81
  and .quota.claude.sonnet_weekly.remaining_percent == 58
  and .last_usage.tool == "codex"
  and .last_usage.result == "READY"
' <<<"$json" >/dev/null

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home/Library/LaunchAgents"

cat >"$TMP_DIR/bin/launchctl" <<'SH'
#!/usr/bin/env bash
cat "$FAKE_LAUNCHCTL_OUTPUT"
SH
chmod +x "$TMP_DIR/bin/launchctl"

write_test_plist() {
  local root="$1"
  cat >"$TMP_DIR/home/Library/LaunchAgents/com.example.stoker.test.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.stoker.test</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${root}/bin/activate-ai-window.sh</string>
    <string>--once</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${root}</string>
</dict>
</plist>
PLIST
}

write_launchctl_output() {
  local root="$1"
  local output="$2"
  cat >"$output" <<OUTPUT
gui/501/com.example.stoker.test = {
	state = not running
	arguments = {
		/bin/bash
		${root}/bin/activate-ai-window.sh
		--once
	}
	working directory = ${root}
}
OUTPUT
}

write_test_plist "$TMP_DIR"
write_launchctl_output "$TMP_DIR" "$TMP_DIR/launchctl.match"

matching_json="$(
  HOME="$TMP_DIR/home" \
  PATH="$TMP_DIR/bin:$PATH" \
  FAKE_LAUNCHCTL_OUTPUT="$TMP_DIR/launchctl.match" \
  STOKER_ROOT="$TMP_DIR" \
  "$ROOT_DIR/bin/activation-state.sh" --json
)"

jq -e '
  .installed == true
  and .launchctl.matches_root == true
  and .launchctl.mismatch == null
' <<<"$matching_json" >/dev/null

OTHER_ROOT="$TMP_DIR/other-stoker"
mkdir -p "$OTHER_ROOT/bin"
write_test_plist "$OTHER_ROOT"
write_launchctl_output "$OTHER_ROOT" "$TMP_DIR/launchctl.mismatch"

mismatch_json="$(
  HOME="$TMP_DIR/home" \
  PATH="$TMP_DIR/bin:$PATH" \
  FAKE_LAUNCHCTL_OUTPUT="$TMP_DIR/launchctl.mismatch" \
  STOKER_ROOT="$TMP_DIR" \
  "$ROOT_DIR/bin/activation-state.sh" --json
)"

jq -e --arg expected "$OTHER_ROOT/bin/activate-ai-window.sh" '
  .installed == false
  and .launchctl.matches_root == false
  and .launchctl.program == $expected
  and (.launchctl.mismatch | contains("current root"))
' <<<"$mismatch_json" >/dev/null

# ── Claude quota freshness: restamp, reset blanking, live-cache override ─────

now_ms=$(( $(date +%s) * 1000 ))
old_ms=$(( now_ms - 36 * 3600 * 1000 ))   # data captured 36h ago

# Snapshot row whose DATA is 36h old, with an exhausted five_hour window whose
# reset has long passed; weekly still in the future.
cat >"$TMP_DIR/logs/status.jsonl" <<JSONL
{"timestamp":"2026-06-12 07:00:20 JST","run_id":"r2","tool":"claude","ok":true,"status_source":"cache","cache_timestamp_ms":${old_ms},"five_hour":{"used_percent":70,"remaining_percent":30,"resets_at":"2026-01-01T00:00:00.123Z"},"weekly":{"used_percent":30,"remaining_percent":70,"resets_at":"2099-01-01T00:00:00Z"},"sonnet_weekly":{"used_percent":0,"remaining_percent":100,"resets_at":null}}
{"timestamp":"2026-06-12 07:00:21 JST","run_id":"r2","tool":"codex","ok":true,"five_hour":{"used_percent":1,"remaining_percent":99,"resets_at":"2099-01-01T00:00:00Z"},"weekly":{"used_percent":0,"remaining_percent":100,"resets_at":"2099-01-01T00:00:00Z"}}
JSONL

# A) no live cache → snapshot kept, but timestamp restamped to the data-capture
#    time and the passed-reset five_hour window blanked; future windows intact.
stale_json="$(STOKER_ROOT="$TMP_DIR" STOKER_SKIP_LAUNCHCTL=1 "$ROOT_DIR/bin/activation-state.sh" --json)"
expected_stamp="$(date -r $(( old_ms / 1000 )) '+%Y-%m-%d %H:%M:%S %Z')"
jq -e --arg ts "$expected_stamp" '
  .quota.claude.timestamp == $ts
  and .quota.claude.status_source == "cache"
  and .quota.claude.five_hour.used_percent == null
  and .quota.claude.five_hour.reset_passed == true
  and .quota.claude.weekly.used_percent == 30
  and .quota.codex.five_hour.remaining_percent == 99
' <<<"$stale_json" >/dev/null

# B) a NEWER live cache wins: quota.claude served from it, stamped with its own
#    data time; codex untouched.
cat >"$CLAUDE_USAGE_CACHE_FILE" <<JSON
{"timestamp":${now_ms},"data":{"fiveHourPercent":4,"fiveHourResetsAt":"2099-01-01T00:00:00.422Z","weeklyPercent":33,"weeklyResetsAt":"2099-01-02T00:00:00Z","sonnetWeeklyPercent":0,"sonnetWeeklyResetsAt":null,"scopedWeeklyBuckets":[{"id":"fable","label":"Fable","percent":61,"resetsAt":"2099-01-03T08:00:00.315Z","isActive":false},{"id":"old","label":"Old","percent":90,"resetsAt":"2026-01-01T00:00:00.315Z","isActive":true}]},"error":false,"source":"anthropic","lastSuccessAt":${now_ms}}
JSON
live_json="$(STOKER_ROOT="$TMP_DIR" STOKER_SKIP_LAUNCHCTL=1 "$ROOT_DIR/bin/activation-state.sh" --json)"
live_stamp="$(date -r $(( now_ms / 1000 )) '+%Y-%m-%d %H:%M:%S %Z')"
jq -e --arg ts "$live_stamp" '
  .quota.claude.status_source == "live-cache"
  and .quota.claude.timestamp == $ts
  and .quota.claude.five_hour.used_percent == 4
  and .quota.claude.five_hour.remaining_percent == 96
  and .quota.claude.weekly.used_percent == 33
  and (.quota.claude.five_hour.reset_passed // false) == false
  and .quota.codex.five_hour.remaining_percent == 99
  and (.quota.claude.scoped_weekly | length) == 2
  and .quota.claude.scoped_weekly[0].label == "Fable"
  and .quota.claude.scoped_weekly[0].used_percent == 61
  and .quota.claude.scoped_weekly[0].remaining_percent == 39
  and .quota.claude.scoped_weekly[0].is_active == false
  and (.quota.claude.scoped_weekly[0].reset_passed // false) == false
  and .quota.claude.scoped_weekly[1].used_percent == null
  and .quota.claude.scoped_weekly[1].reset_passed == true
' <<<"$live_json" >/dev/null

# C) a live cache flagged error=true is ignored even when newer → snapshot wins.
cat >"$CLAUDE_USAGE_CACHE_FILE" <<JSON
{"timestamp":${now_ms},"data":{"fiveHourPercent":4},"error":true,"source":"anthropic","lastSuccessAt":null}
JSON
error_json="$(STOKER_ROOT="$TMP_DIR" STOKER_SKIP_LAUNCHCTL=1 "$ROOT_DIR/bin/activation-state.sh" --json)"
jq -e '
  .quota.claude.status_source == "cache"
  and .quota.claude.weekly.used_percent == 30
' <<<"$error_json" >/dev/null

echo "activation-state JSON test passed"
