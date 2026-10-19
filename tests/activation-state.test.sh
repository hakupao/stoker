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
{"timestamp":"2026-05-27 10:01:00 JST","run_id":"r1","tool":"codex","ok":true,"five_hour":{"remaining_percent":81},"weekly":{"remaining_percent":69},"reset_credits":{"available_count":1,"earliest_expires_at":"2026-10-22T20:37:22Z"}}
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
  and .schedule.codex == {"times": ["06:15", "13:15", "21:15"], "days": []}
  and .schedule.claude == {"times": ["06:15", "13:15", "21:15"], "days": []}
  and .launchctl.state == "skipped"
  and .launchctl.agents.codex == {"label": "com.example.stoker.test.codex", "loaded": false, "state": "skipped", "stray": false}
  and .launchctl.agents.claude.label == "com.example.stoker.test.claude"
  and .config.activation_tool == "codex"
  and .config.codex_model == "gpt-5.6-luna"
  and .config.enable_status_snapshots == false
  and .config.enable_quota_preflight == true
  and .config.codex_activate_only_when_idle == true
  and .keep_awake.mode == "during"
  and .keep_awake.seconds == 600
  and .quota.codex.five_hour.remaining_percent == 81
  and .quota.codex.reset_credits.available_count == 1
  and .quota.claude.sonnet_weekly.remaining_percent == 58
  and .last_usage.tool == "codex"
  and .last_usage.result == "READY"
' <<<"$json" >/dev/null

# Per-tool schedules: each tool falls back to SCHEDULE_TIMES on its own, days are
# normalized to mon..sun order, and schedule.times is the union over ENABLED tools.
json="$(
  STOKER_ROOT="$TMP_DIR" \
  STOKER_SKIP_LAUNCHCTL=1 \
  ACTIVATION_TOOL=all \
  CLAUDE_SCHEDULE_TIMES="22:00, 7:00,12:00,07:00" \
  CLAUDE_SCHEDULE_DAYS="" \
  CODEX_SCHEDULE_TIMES="07:30" \
  CODEX_SCHEDULE_DAYS="Thu,mon,THU" \
  "$ROOT_DIR/bin/activation-state.sh" --json
)"
jq -e '
  .schedule.claude == {"times": ["07:00", "12:00", "22:00"], "days": []}
  and .schedule.codex == {"times": ["07:30"], "days": ["mon", "thu"]}
  and .schedule.times == ["07:00", "07:30", "12:00", "22:00"]
' <<<"$json" >/dev/null

json="$(
  STOKER_ROOT="$TMP_DIR" \
  STOKER_SKIP_LAUNCHCTL=1 \
  CODEX_SCHEDULE_TIMES="07:30" \
  CLAUDE_SCHEDULE_DAYS="daily" \
  "$ROOT_DIR/bin/activation-state.sh" --json
)"
jq -e '
  .schedule.times == ["07:30"]
  and .schedule.claude == {"times": ["06:15", "13:15", "21:15"], "days": []}
' <<<"$json" >/dev/null

if STOKER_ROOT="$TMP_DIR" STOKER_SKIP_LAUNCHCTL=1 CODEX_SCHEDULE_DAYS="mon,funday" \
  "$ROOT_DIR/bin/activation-state.sh" --json >/dev/null 2>&1; then
  echo "expected an invalid CODEX_SCHEDULE_DAYS to be rejected" >&2
  exit 1
fi

# The app's Codex next-activation mirrors the engine's skip toggles, so both must reach
# the config block (caller env wins over .env).
json="$(
  STOKER_ROOT="$TMP_DIR" \
  STOKER_SKIP_LAUNCHCTL=1 \
  CODEX_ACTIVATE_ONLY_WHEN_IDLE=0 \
  ENABLE_QUOTA_PREFLIGHT=0 \
  QUOTA_EXHAUSTED_THRESHOLD_PERCENT=5 \
  "$ROOT_DIR/bin/activation-state.sh" --json
)"
jq -e '
  .config.codex_activate_only_when_idle == false
  and .config.enable_quota_preflight == false
  and .config.quota_exhausted_threshold_percent == 5
' <<<"$json" >/dev/null

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home/Library/LaunchAgents" "$TMP_DIR/loaded"

# Fake launchctl: `print gui/<uid>/<label>` succeeds only for labels that have a
# file in $FAKE_LOADED_DIR (its content is the print output); everything else is
# "not loaded".
cat >"$TMP_DIR/bin/launchctl" <<'SH'
#!/usr/bin/env bash
label="${2##*/}"
if [[ "$1" == "print" && -f "$FAKE_LOADED_DIR/$label" ]]; then
  cat "$FAKE_LOADED_DIR/$label"
  exit 0
fi
echo "Could not find service \"$label\"" >&2
exit 113
SH
chmod +x "$TMP_DIR/bin/launchctl"

# load_agent <label> <root>: installed plist + "loaded" launchctl output for it.
load_agent() {
  local label="$1" root="$2"
  cat >"$TMP_DIR/home/Library/LaunchAgents/${label}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
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
  cat >"$TMP_DIR/loaded/${label}" <<OUTPUT
gui/501/${label} = {
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

reset_agents() {
  rm -f "$TMP_DIR/loaded/"* "$TMP_DIR/home/Library/LaunchAgents/"*
}

state_json() {
  env HOME="$TMP_DIR/home" \
    LAUNCHCTL_BIN="$TMP_DIR/bin/launchctl" \
    FAKE_LOADED_DIR="$TMP_DIR/loaded" \
    STOKER_ROOT="$TMP_DIR" \
    "$@" "$ROOT_DIR/bin/activation-state.sh" --json
}

OTHER_ROOT="$TMP_DIR/other-stoker"
mkdir -p "$OTHER_ROOT/bin"

# ACTIVATION_TOOL=codex (.env): the Codex agent from this root is all it takes.
load_agent com.example.stoker.test.codex "$TMP_DIR"
matching_json="$(state_json)"
jq -e '
  .installed == true
  and .launchctl.matches_root == true
  and .launchctl.mismatch == null
  and .launchctl.agents.codex.loaded == true
  and .launchctl.agents.codex.state == "not running"
  and .launchctl.agents.codex.stray == false
  and .launchctl.agents.claude.loaded == false
  and .launchctl.legacy == []
  and .launchctl.needs_migration == false
' <<<"$matching_json" >/dev/null || { echo "matching: $matching_json" >&2; exit 1; }

# With both tools enabled, installed needs BOTH agents.
partial_json="$(state_json ACTIVATION_TOOL=all)"
jq -e '
  .installed == false
  and .launchctl.state == "not_loaded"
  and .launchctl.agents.claude.loaded == false
  and .launchctl.agents.codex.loaded == true
' <<<"$partial_json" >/dev/null || { echo "partial: $partial_json" >&2; exit 1; }

# A loaded agent of a disabled tool is stray and keeps installed false.
load_agent com.example.stoker.test.claude "$TMP_DIR"
stray_json="$(state_json)"
jq -e '
  .installed == false
  and .launchctl.agents.claude.stray == true
  and .launchctl.agents.codex.stray == false
  and .launchctl.mismatch == null
' <<<"$stray_json" >/dev/null || { echo "stray: $stray_json" >&2; exit 1; }
both_json="$(state_json ACTIVATION_TOOL=all)"
jq -e '.installed == true and .launchctl.agents.claude.stray == false' <<<"$both_json" >/dev/null \
  || { echo "both: $both_json" >&2; exit 1; }

# A stray agent of a disabled tool from ANOTHER root is someone else's schedule:
# it fills mismatch too.
reset_agents
load_agent com.example.stoker.test.codex "$TMP_DIR"
load_agent com.example.stoker.test.claude "$OTHER_ROOT"
stray_elsewhere_json="$(state_json)"
jq -e '
  .installed == false
  and .launchctl.agents.claude.stray == true
  and (.launchctl.mismatch | contains("com.example.stoker.test.claude"))
' <<<"$stray_elsewhere_json" >/dev/null || { echo "stray elsewhere: $stray_elsewhere_json" >&2; exit 1; }

# The enabled agent pointing at another root → mismatch.
reset_agents
load_agent com.example.stoker.test.codex "$OTHER_ROOT"
mismatch_json="$(state_json)"
jq -e --arg expected "$OTHER_ROOT/bin/activate-ai-window.sh" '
  .installed == false
  and .launchctl.matches_root == false
  and .launchctl.program == $expected
  and (.launchctl.mismatch | contains("current root"))
' <<<"$mismatch_json" >/dev/null || { echo "mismatch: $mismatch_json" >&2; exit 1; }

# Old single-label agent from THIS root: listed, needs_migration, not installed
# (even with the new agent also loaded).
reset_agents
load_agent com.example.stoker.test "$TMP_DIR"
load_agent com.example.stoker.test.codex "$TMP_DIR"
migrate_json="$(state_json)"
jq -e --arg root "$TMP_DIR" '
  .installed == false
  and .launchctl.needs_migration == true
  and .launchctl.mismatch == null
  and .launchctl.legacy == [{"label": "com.example.stoker.test", "loaded": true, "matches_root": true,
                             "program": ($root + "/bin/activate-ai-window.sh"), "working_directory": $root}]
' <<<"$migrate_json" >/dev/null || { echo "migrate: $migrate_json" >&2; exit 1; }

# A LEGACY_LABELS agent from ANOTHER root: mismatch (the app's "installed
# elsewhere" guard), no migration.
reset_agents
load_agent com.example.old.timer "$OTHER_ROOT"
elsewhere_json="$(state_json LEGACY_LABELS=com.example.old.timer)"
jq -e '
  .installed == false
  and .launchctl.needs_migration == false
  and (.launchctl.mismatch | contains("com.example.old.timer"))
  and .launchctl.legacy[0].label == "com.example.old.timer"
  and .launchctl.legacy[0].matches_root == false
' <<<"$elsewhere_json" >/dev/null || { echo "elsewhere: $elsewhere_json" >&2; exit 1; }

# Skipped probing lists no legacy agents.
skipped_json="$(state_json STOKER_SKIP_LAUNCHCTL=1 LEGACY_LABELS=com.example.old.timer)"
jq -e '.launchctl.legacy == [] and .launchctl.needs_migration == false and .launchctl.agents.claude.stray == false' \
  <<<"$skipped_json" >/dev/null || { echo "skipped: $skipped_json" >&2; exit 1; }
reset_agents

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
