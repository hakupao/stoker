#!/usr/bin/env bash
set -euo pipefail

# Verifies the default CODEX_STATUS_SOURCE=app-server path end-to-end with a fake
# `codex app-server` that speaks the JSON-RPC the engine expects. Focus:
#   A) normal account (primary=5h, secondary=weekly) maps correctly, and a numeric
#      credits balance is coerced to a string (so the app's String? decode holds)
#   B) length-based classification: a lone weekly-length window reported as `primary`
#      routes to weekly, never mislabeled as the 5-hour window
#
# Skipped when node is absent (the app-server path needs it), matching validate.sh.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NODE_BIN="$(command -v node 2>/dev/null || true)"
if [[ -z "$NODE_BIN" ]]; then
  echo "node not found; skipping codex app-server source test"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"
ENGINE="$TMP_DIR/bin/activate-ai-window.sh"
STATUS="$TMP_DIR/logs/status.jsonl"

# Fake `codex app-server`: answer initialize (id 1), then account/rateLimits/read
# (id 2) with the JSON supplied in $RATE_LIMITS.
cat >"$TMP_DIR/bin/codex-fake" <<'SH'
#!/usr/bin/env bash
while IFS= read -r line; do
  case "$line" in
    *'"method":"initialize"'*) printf '%s\n' '{"id":1,"result":{}}' ;;
    *'account/rateLimits/read'*) printf '%s\n' "$RATE_LIMITS"; exit 0 ;;
  esac
done
SH
chmod +x "$TMP_DIR/bin/codex-fake"

run_appserver() {
  CODEX_BIN="$TMP_DIR/bin/codex-fake" \
    NODE_BIN="$NODE_BIN" \
    RATE_LIMITS="$1" \
    "$ENGINE" --status --tool codex >/dev/null 2>&1
}

# ── A) normal account: primary=5h(300min), secondary=weekly(10080min) ───────
run_appserver '{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"planType":"pro","rateLimitReachedType":null,"credits":{"hasCredits":true,"unlimited":false,"balance":42},"primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":1785000000},"secondary":{"usedPercent":70,"windowDurationMins":10080,"resetsAt":1785500000}}}}}' \
  || { echo "expected app-server snapshot to succeed" >&2; exit 1; }
row="$(grep '"tool":"codex"' "$STATUS" | tail -1)"
jq -e '
    .ok == true
    and .plan_type == "pro"
    and .five_hour.used_percent == 40
    and .five_hour.window_minutes == 300
    and .weekly.used_percent == 70
    and .weekly.window_minutes == 10080
    and .credits.balance == "42"
    and .credits.has_credits == true
  ' <<<"$row" >/dev/null \
  || { echo "unexpected app-server row: $row" >&2; exit 1; }

# ── B) weekly-as-primary: a lone 10080-min window must route to weekly ──────
run_appserver '{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"planType":"plus","primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1785500000}}}}}' \
  || { echo "expected weekly-as-primary snapshot to succeed" >&2; exit 1; }
row="$(grep '"tool":"codex"' "$STATUS" | tail -1)"
jq -e '
    .five_hour == null
    and .weekly.window_minutes == 10080
    and .weekly.used_percent == 0
  ' <<<"$row" >/dev/null \
  || { echo "expected weekly-as-primary to route to weekly (not 5h): $row" >&2; exit 1; }

echo "codex app-server source test passed"
