#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/logs"

cat >"$TMP_DIR/.env" <<'ENV'
LABEL=com.example.stoker.test
SCHEDULE_TIMES="06:15,13:15,21:15"
ACTIVATION_TOOL=codex
CODEX_MODEL=gpt-5.4-mini
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
  and .config.codex_model == "gpt-5.4-mini"
  and .config.enable_status_snapshots == false
  and .config.enable_quota_preflight == true
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

echo "activation-state JSON test passed"
