#!/usr/bin/env bash
set -euo pipefail

# Verifies CODEX_STATUS_SOURCE=native (read-only HTTP quota, no app-server):
#   A) a valid auth file → snapshot recorded from the wham/usage response, mapping
#      primary/secondary windows to five_hour/weekly, plan_type, and credits
#   B) neither the access token nor the account id leaks (both ride the stdin
#      header block, never argv/logs); the raw artifact carries no PII
#   C) a failed request (e.g. 401 expired token) records no row and never refreshes
#   D) a missing auth file degrades without a row
#   E) window classification is by length, not name: a lone weekly-length window
#      routes to weekly (never mislabeled as the 5-hour window)
#   F) an invalid CODEX_STATUS_SOURCE is rejected up front
#
# The engine derives ROOT_DIR from its own location, so it is copied into a temp
# root to keep logs hermetic and away from the real install. curl is faked so no
# network or real credential is ever touched.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"
ENGINE="$TMP_DIR/bin/activate-ai-window.sh"
STATUS="$TMP_DIR/logs/status.jsonl"
AUTH="$TMP_DIR/auth.json"

export SENTINEL_DIR="$TMP_DIR/sentinels"
mkdir -p "$SENTINEL_DIR"

# Canary token + account id: any appearance in argv/logs is a leak.
TOKEN_CANARY='sk-codex-ACCESSTOKENCANARY'
ACCT_CANARY='acct-ACCOUNTIDCANARY'
PII_CANARY='PIICANARY'   # stands in for email/user_id/account_id in the response body

write_auth() {
  jq -n --arg tok "$TOKEN_CANARY" --arg acct "$ACCT_CANARY" '
    { tokens: { access_token: $tok, account_id: $acct, id_token: "x.y.z", refresh_token: "rt" },
      last_refresh: "2026-07-21T00:00:00Z", auth_mode: "chatgpt" }' >"$AUTH"
}

# Fake curl: consumes the stdin header block (-H @-), records argv to a sentinel,
# and prints a wham/usage response that INCLUDES PII (to prove redaction). Set
# CURL_FAIL=1 to simulate a non-2xx (curl -f exits non-zero).
cat >"$TMP_DIR/bin/curl-fake" <<'SH'
#!/usr/bin/env bash
cat >/dev/null                                   # drain the stdin header block
printf '%s\n' "$*" >>"${SENTINEL_DIR}/curl-args"
touch "${SENTINEL_DIR}/curl-invoked"
[[ "${CURL_FAIL:-0}" == "1" ]] && exit 22
future=$(( $(date +%s) + 3600 ))
future_wk=$(( $(date +%s) + 500000 ))
cat <<JSON
{"account_id":"acct-PIICANARY","email":"PIICANARY@example.com","user_id":"user-PIICANARY","plan_type":"pro","rate_limit":{"allowed":true,"primary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_after_seconds":3600,"reset_at":${future}},"secondary_window":{"used_percent":71,"limit_window_seconds":604800,"reset_after_seconds":500000,"reset_at":${future_wk}}},"credits":{"balance":"12.50","approx_local_messages":[100,200],"approx_cloud_messages":[5,10]},"rate_limit_reset_credits":{"available_count":3}}
JSON
SH
chmod +x "$TMP_DIR/bin/curl-fake"

run_native() {
  CODEX_STATUS_SOURCE=native \
    CODEX_AUTH_FILE="$AUTH" \
    CURL_BIN="$TMP_DIR/bin/curl-fake" \
    CODEX_USAGE_API_URL="https://example.invalid/wham/usage" \
    "$@" "$ENGINE" --status --tool codex >/dev/null 2>&1
}

# ── A) valid auth → snapshot recorded, windows/plan/credits mapped ───────────
write_auth
run_native env || { echo "expected native codex snapshot to succeed" >&2; exit 1; }

row="$(grep '"tool":"codex"' "$STATUS" | tail -1)"
jq -e '
    .ok == true
    and (.captured_at_epoch | type) == "number"
    and (now - .captured_at_epoch) < 60
    and .plan_type == "pro"
    and .five_hour.used_percent == 42
    and .five_hour.remaining_percent == 58
    and .five_hour.window_minutes == 300
    and .weekly.used_percent == 71
    and .weekly.window_minutes == 10080
    and .credits.balance == "12.50"
    and .credits.has_credits == true
    and .rate_limit_reached_type == null
  ' <<<"$row" >/dev/null \
  || { echo "unexpected native codex row: $row" >&2; exit 1; }

[[ -e "$SENTINEL_DIR/curl-invoked" ]] \
  || { echo "expected native mode to query the usage API" >&2; exit 1; }

# ── B) no token/account/PII leak ────────────────────────────────────────────
raw_log="$(jq -r '.raw_log' <<<"$row")"
[[ -f "$raw_log" ]] || { echo "expected redacted raw artifact at $raw_log" >&2; exit 1; }
# PII must be absent from the ENTIRE logs tree (raw artifact + status.jsonl + activation.log).
if grep -rq "$PII_CANARY" "$TMP_DIR/logs"; then
  echo "PII (email/user_id/account_id) leaked into the logs tree" >&2; exit 1
fi
if grep -rq "$TOKEN_CANARY" "$TMP_DIR/logs" || grep -q "$TOKEN_CANARY" "$SENTINEL_DIR/curl-args"; then
  echo "access token leaked into logs/argv" >&2; exit 1
fi
if grep -q "$ACCT_CANARY" "$SENTINEL_DIR/curl-args"; then
  echo "account id leaked into curl argv (must ride stdin)" >&2; exit 1
fi
# The GET must carry the codex_cli_rs User-Agent + originator (future-proofing).
grep -q 'User-Agent: codex_cli_rs/' "$SENTINEL_DIR/curl-args" \
  || { echo "expected a codex_cli_rs User-Agent header on the native usage request" >&2; exit 1; }

# ── C) failed request (401/expired) → no row, no refresh ────────────────────
rows_before="$(grep -c '"tool":"codex"' "$STATUS" || true)"
if run_native env CURL_FAIL=1; then
  echo "expected native snapshot to fail on a non-2xx response" >&2; exit 1
fi
rows_after="$(grep -c '"tool":"codex"' "$STATUS" || true)"
[[ "$rows_before" == "$rows_after" ]] \
  || { echo "expected no status row for a failed request" >&2; exit 1; }

# ── D) missing auth file → degrade without a row ────────────────────────────
rm -f "$AUTH"
if run_native env; then
  echo "expected native snapshot to fail when the auth file is missing" >&2; exit 1
fi

# ── E) window classification by length: lone weekly-length window ───────────
# A single exhausted primary window that is actually 7 days long must route to
# weekly (five_hour null), never be mislabeled as the 5-hour window.
cat >"$TMP_DIR/bin/curl-weekly" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
future_wk=$(( $(date +%s) + 500000 ))
cat <<JSON
{"plan_type":"plus","rate_limit":{"allowed":false,"primary_window":{"used_percent":100,"limit_window_seconds":604800,"reset_after_seconds":100,"reset_at":${future_wk}}},"credits":{"balance":null}}
JSON
SH
chmod +x "$TMP_DIR/bin/curl-weekly"
write_auth
CODEX_STATUS_SOURCE=native CODEX_AUTH_FILE="$AUTH" \
  CURL_BIN="$TMP_DIR/bin/curl-weekly" \
  CODEX_USAGE_API_URL="https://example.invalid/wham/usage" \
  "$ENGINE" --status --tool codex >/dev/null 2>&1 \
  || { echo "expected weekly-only native snapshot to succeed" >&2; exit 1; }
row="$(grep '"tool":"codex"' "$STATUS" | tail -1)"
jq -e '
    .five_hour == null
    and .weekly.used_percent == 100
    and .weekly.window_minutes == 10080
    and .rate_limit_reached_type == "secondary"
  ' <<<"$row" >/dev/null \
  || { echo "expected a lone weekly-length window to route to weekly: $row" >&2; exit 1; }

# ── G) 5h window exhausted → reached_type "primary"; numeric balance coerced ─
cat >"$TMP_DIR/bin/curl-5h" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
future=$(( $(date +%s) + 600 ))
cat <<JSON
{"plan_type":"pro","rate_limit":{"allowed":false,"primary_window":{"used_percent":100,"limit_window_seconds":18000,"reset_after_seconds":600,"reset_at":${future}}},"credits":{"balance":42}}
JSON
SH
chmod +x "$TMP_DIR/bin/curl-5h"
write_auth
CODEX_STATUS_SOURCE=native CODEX_AUTH_FILE="$AUTH" CURL_BIN="$TMP_DIR/bin/curl-5h" \
  CODEX_USAGE_API_URL="https://example.invalid/wham/usage" \
  "$ENGINE" --status --tool codex >/dev/null 2>&1 \
  || { echo "expected 5h-exhausted native snapshot to succeed" >&2; exit 1; }
row="$(grep '"tool":"codex"' "$STATUS" | tail -1)"
jq -e '
    .rate_limit_reached_type == "primary"
    and .five_hour.used_percent == 100
    and .five_hour.window_minutes == 300
    and .weekly == null
    and .credits.balance == "42"
  ' <<<"$row" >/dev/null \
  || { echo "expected reached_type=primary + numeric balance coerced to string: $row" >&2; exit 1; }

# ── H) a 200 body carrying no quota fields records no row (ok is not faked) ──
cat >"$TMP_DIR/bin/curl-empty" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
echo '{}'
SH
chmod +x "$TMP_DIR/bin/curl-empty"
rows_before="$(grep -c '"tool":"codex"' "$STATUS" || true)"
if CODEX_STATUS_SOURCE=native CODEX_AUTH_FILE="$AUTH" CURL_BIN="$TMP_DIR/bin/curl-empty" \
   CODEX_USAGE_API_URL="https://example.invalid/wham/usage" \
   "$ENGINE" --status --tool codex >/dev/null 2>&1; then
  echo "expected an empty 200 body to fail the snapshot" >&2; exit 1
fi
rows_after="$(grep -c '"tool":"codex"' "$STATUS" || true)"
[[ "$rows_before" == "$rows_after" ]] \
  || { echo "expected no row for an empty 200 body" >&2; exit 1; }

# ── F) invalid CODEX_STATUS_SOURCE is rejected ──────────────────────────────
if CODEX_STATUS_SOURCE=bogus "$ENGINE" --status --tool codex >/dev/null 2>&1; then
  echo "expected CODEX_STATUS_SOURCE=bogus to be rejected" >&2; exit 1
fi

echo "codex native source test passed"
