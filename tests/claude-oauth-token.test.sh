#!/usr/bin/env bash
set -euo pipefail

# Verifies the headless-auth wiring around CLAUDE_CODE_OAUTH_TOKEN:
#   A) dry-run reports the auth source and never leaks the token value
#   B) a 401 from the CLI is recorded (ok=false, api_error_status=401) and the
#      activation log prints an actionable `claude setup-token` hint
#   C) a normal READY run does not emit the auth-failure hint (no false positive)
#
# The engine derives ROOT_DIR from its own location, so it is copied into a temp
# root to keep logs/locks hermetic and away from the real install.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"
ENGINE="$TMP_DIR/bin/activate-ai-window.sh"
LOG="$TMP_DIR/logs/activation.log"
USAGE="$TMP_DIR/logs/usage.jsonl"

# Fake Claude CLIs.
cat >"$TMP_DIR/bin/claude-401" <<'SH'
#!/usr/bin/env bash
echo '{"type":"result","is_error":true,"api_error_status":401,"result":"Failed to authenticate. API Error: 401 Invalid authentication credentials","session_id":"t","usage":{"input_tokens":0,"output_tokens":0}}'
exit 1
SH
cat >"$TMP_DIR/bin/claude-ok" <<'SH'
#!/usr/bin/env bash
echo '{"type":"result","is_error":false,"api_error_status":null,"result":"READY","session_id":"t","usage":{"input_tokens":10,"output_tokens":2}}'
exit 0
SH
chmod +x "$TMP_DIR/bin/claude-401" "$TMP_DIR/bin/claude-ok"

# ── A) dry-run auth visibility + no token leak ──────────────────────────────
secret='sk-ant-oat01-SECRETLEAKCANARY'
out_token="$(CLAUDE_CODE_OAUTH_TOKEN="$secret" ACTIVATION_TOOL=claude "$ENGINE" --dry-run --tool claude 2>&1)"
grep -q 'DRY-RUN Claude auth=CLAUDE_CODE_OAUTH_TOKEN' <<<"$out_token" \
  || { echo "expected dry-run to report token auth mode" >&2; exit 1; }
if grep -q "$secret" <<<"$out_token" || grep -q "$secret" "$LOG"; then
  echo "token value leaked into output/log" >&2
  exit 1
fi

out_keychain="$(ACTIVATION_TOOL=claude "$ENGINE" --dry-run --tool claude 2>&1)"
grep -q 'DRY-RUN Claude auth=keychain' <<<"$out_keychain" \
  || { echo "expected dry-run to report keychain auth mode when token unset" >&2; exit 1; }

# ── B) 401 is recorded and surfaced with an actionable hint ─────────────────
: >"$LOG"
CLAUDE_BIN="$TMP_DIR/bin/claude-401" \
  ACTIVATION_TOOL=claude \
  ENABLE_QUOTA_PREFLIGHT=0 \
  ENABLE_STATUS_SNAPSHOTS=0 \
  "$ENGINE" --once --tool claude >/dev/null 2>&1 || true

last_claude="$(grep '"tool":"claude"' "$USAGE" | tail -1)"
jq -e '.ok == false and .api_error_status == 401' <<<"$last_claude" >/dev/null \
  || { echo "expected usage row ok=false api_error_status=401" >&2; exit 1; }
grep -q "claude setup-token" "$LOG" \
  || { echo "expected activation log to hint at 'claude setup-token'" >&2; exit 1; }
grep -q "authentication failed (401)" "$LOG" \
  || { echo "expected activation log to flag the 401 auth failure" >&2; exit 1; }

# ── C) a successful run does not emit the auth-failure hint ─────────────────
: >"$LOG"
CLAUDE_BIN="$TMP_DIR/bin/claude-ok" \
  ACTIVATION_TOOL=claude \
  ENABLE_QUOTA_PREFLIGHT=0 \
  ENABLE_STATUS_SNAPSHOTS=0 \
  "$ENGINE" --once --tool claude >/dev/null 2>&1 || true

last_ok="$(grep '"tool":"claude"' "$USAGE" | tail -1)"
jq -e '.ok == true and .api_error_status == null' <<<"$last_ok" >/dev/null \
  || { echo "expected successful usage row ok=true api_error_status=null" >&2; exit 1; }
if grep -q "claude setup-token" "$LOG"; then
  echo "did not expect an auth-failure hint on a successful run" >&2
  exit 1
fi

# ── D) the token is actually exported into the claude subprocess env ─────────
# The fake CLI records the value it received via a side-channel file (never via
# the model output), so a regression that dropped the `export` would be caught.
cat >"$TMP_DIR/bin/claude-echoenv" <<'SH'
#!/usr/bin/env bash
printf '%s' "${CLAUDE_CODE_OAUTH_TOKEN:-MISSING}" >"$PROBE_OUT"
echo '{"type":"result","is_error":false,"api_error_status":null,"result":"READY","session_id":"t","usage":{"input_tokens":1,"output_tokens":1}}'
exit 0
SH
chmod +x "$TMP_DIR/bin/claude-echoenv"

: >"$LOG"
probe_token='sk-ant-oat01-PROPAGATIONPROBE'
PROBE_OUT="$TMP_DIR/probe-env.txt" \
  CLAUDE_BIN="$TMP_DIR/bin/claude-echoenv" \
  CLAUDE_CODE_OAUTH_TOKEN="$probe_token" \
  ACTIVATION_TOOL=claude \
  ENABLE_QUOTA_PREFLIGHT=0 \
  ENABLE_STATUS_SNAPSHOTS=0 \
  "$ENGINE" --once --tool claude >/dev/null 2>&1 || true

[[ "$(cat "$TMP_DIR/probe-env.txt" 2>/dev/null)" == "$probe_token" ]] \
  || { echo "expected CLAUDE_CODE_OAUTH_TOKEN to reach the claude subprocess env" >&2; exit 1; }
if grep -q "$probe_token" "$LOG"; then
  echo "token value leaked into activation.log during a real run" >&2
  exit 1
fi

echo "claude oauth token test passed"
