#!/usr/bin/env bash
set -euo pipefail

# Verifies Codex CLI auto-update (CODEX_AUTO_UPDATE) and the one-shot model
# fallback (CODEX_MODEL_FALLBACK) with a stub `codex`:
#   A) an allowed real run updates first (version before/after logged, cli_update
#      recorded in the usage row), then sends the prompt
#   B) the attempt stamp throttles the next run (no second update)
#   C) a failing updater is non-fatal and still stamps (no retry next slot)
#   C2) a hung updater is killed at CODEX_UPDATE_TIMEOUT_SECONDS with its whole
#       process tree (no orphaned grandchild), stamped, run continues
#   C3) a binary that answered --version before the update but not after →
#       ERROR, stamp removed (next slot retries), prompt still attempted
#   C4) a stamp in the future counts as expired
#   D) CODEX_AUTO_UPDATE=0 never updates
#   E) a run skipped by quota preflight never updates
#   F) dry-run never updates
#   G) "model is not supported" → retry with the preferred candidate: luna tier by
#      ascending priority; hidden, no-"low"-effort, retired and rejected models
#      excluded; the first row is marked superseded, the retry records model_fallback
#   G3) the rejected model's own upgrade.model is preferred over the tiers
#   G4) every candidate rejected → capped at CODEX_MODEL_FALLBACK_MAX_TRIES, one
#       row per attempt, run fails
#   H) no candidate left / missing or unreadable cache → ERROR, no retry
#   I) CODEX_MODEL_FALLBACK=0 → no retry
#   J) a different error → no retry
#   K) invalid flag values are rejected up front
#
# Hermetic: the engine is copied into a temp root; codex is a stub; no network.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/codex-probe"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"
ENGINE="$TMP_DIR/bin/activate-ai-window.sh"
USAGE="$TMP_DIR/logs/usage.jsonl"
ACTIVATION_LOG="$TMP_DIR/logs/activation.log"
STAMP="$TMP_DIR/run/codex-update.last"
CACHE="$TMP_DIR/models_cache.json"
export SENTINEL_DIR="$TMP_DIR/sentinels"
export FAKE_VERSION_FILE="$TMP_DIR/fake-version"

# Stub codex: --version reads FAKE_VERSION_FILE; `update` bumps it (or fails with
# UPDATE_FAIL=1); `exec` logs the model and fails with the real 400 text when the
# model equals REJECT_MODEL (or a generic error with OTHER_FAIL=1).
cat >"$TMP_DIR/bin/codex-fake" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    [[ "$(cat "$FAKE_VERSION_FILE")" == "BROKEN" ]] && exit 1
    echo "codex-cli $(cat "$FAKE_VERSION_FILE")"; exit 0 ;;
  update)
    echo update >>"${SENTINEL_DIR}/update-calls"
    [[ "${UPDATE_FAIL:-0}" == "1" ]] && { echo "update failed" >&2; exit 3; }
    [[ "${UPDATE_BREAK:-0}" == "1" ]] && { echo "BROKEN" >"$FAKE_VERSION_FILE"; exit 0; }
    if [[ "${UPDATE_HANG:-0}" == "1" ]]; then
      sleep 30 &
      echo $! >"${SENTINEL_DIR}/grandchild"
      wait
    fi
    echo "9.9.9" >"$FAKE_VERSION_FILE"
    exit 0 ;;
  exec)
    model="default"
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "--model" ]] && model="$2"
      shift
    done
    echo "$model" >>"${SENTINEL_DIR}/exec-models"
    echo '{"type":"thread.started","thread_id":"t"}'
    if [[ "${REJECT_ALL:-0}" == "1" || ( -n "${REJECT_MODEL:-}" && "$model" == "$REJECT_MODEL" ) ]]; then
      printf '{"type":"turn.failed","error":{"message":"{\\"type\\":\\"error\\",\\"status\\":400,\\"error\\":{\\"type\\":\\"invalid_request_error\\",\\"message\\":\\"The %s model is not supported when using Codex with a ChatGPT account.\\"}}"}}\n' "'$model'"
      exit 1
    fi
    if [[ "${OTHER_FAIL:-0}" == "1" ]]; then
      echo '{"type":"turn.failed","error":{"message":"stream disconnected"}}'
      exit 1
    fi
    echo '{"type":"item.completed","item":{"type":"agent_message","text":"READY"}}'
    echo '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
    exit 0 ;;
esac
exit 0
SH
chmod +x "$TMP_DIR/bin/codex-fake"

# Real cache shape. Cache order puts sol first (tier beats order) and lists
# gpt-late-luna before gpt-new-luna with a worse priority (priority beats order).
# Excluded lunas: hidden, no "low" effort, and past retirement.
LOW='[{"effort":"low","description":"x"},{"effort":"medium","description":"y"}]'
cat >"$CACHE" <<JSON
{"models":[
  {"slug":"gpt-x-sol","visibility":"list","priority":1,"upgrade":null,"supported_reasoning_levels":$LOW},
  {"slug":"gpt-hidden-luna","visibility":"hide","priority":0,"upgrade":null,"supported_reasoning_levels":$LOW},
  {"slug":"gpt-nolow-luna","visibility":"list","priority":0,"upgrade":null,"supported_reasoning_levels":[{"effort":"medium"},{"effort":"high"}]},
  {"slug":"gpt-retired-luna","visibility":"list","priority":0,"upgrade":{"model":"gpt-x-sol","retirement_at":"2020-01-01T00:00:00Z"},"supported_reasoning_levels":$LOW},
  {"slug":"gpt-x-terra","visibility":"list","priority":2,"upgrade":null,"supported_reasoning_levels":$LOW},
  {"slug":"gpt-old-luna","visibility":"list","priority":3,"upgrade":null,"supported_reasoning_levels":$LOW},
  {"slug":"gpt-late-luna","visibility":"list","priority":9,"upgrade":null,"supported_reasoning_levels":$LOW},
  {"slug":"gpt-new-luna","visibility":"list","priority":5,"upgrade":null,"supported_reasoning_levels":$LOW}
]}
JSON

reset_state() {
  rm -rf "$SENTINEL_DIR" && mkdir -p "$SENTINEL_DIR"
  echo "1.0.0" >"$FAKE_VERSION_FILE"
}

run_once() {
  CODEX_BIN="$TMP_DIR/bin/codex-fake" \
    CODEX_WORK_DIR="$TMP_DIR/codex-probe" \
    CODEX_MODELS_CACHE="$CACHE" \
    CODEX_MODEL=gpt-old-luna \
    ENABLE_QUOTA_PREFLIGHT=0 \
    ENABLE_STATUS_SNAPSHOTS=0 \
    KEEP_AWAKE_MODE=off \
    "$@" "$ENGINE" --once --tool codex >/dev/null 2>&1
}

update_calls() { [[ -f "$SENTINEL_DIR/update-calls" ]] && wc -l <"$SENTINEL_DIR/update-calls" | tr -d ' ' || echo 0; }
last_usage() { grep '"tool":"codex"' "$USAGE" | tail -1; }

# ── A) first real run updates, then prompts ─────────────────────────────────
reset_state; rm -f "$STAMP"
run_once env || { echo "A: expected the run to succeed" >&2; exit 1; }
[[ "$(update_calls)" == "1" ]] || { echo "A: expected exactly one update" >&2; exit 1; }
[[ -f "$SENTINEL_DIR/exec-models" ]] || { echo "A: expected the prompt to be sent" >&2; exit 1; }
[[ -f "$STAMP" ]] || { echo "A: expected an update stamp" >&2; exit 1; }
jq -e '.ok == true and .model == "gpt-old-luna" and .cli_update.attempted == true and .cli_update.from == "codex-cli 1.0.0"
       and .cli_update.to == "codex-cli 9.9.9" and .cli_update.exit == 0 and (has("model_fallback") | not)' \
  <<<"$(last_usage)" >/dev/null || { echo "A: unexpected usage row: $(last_usage)" >&2; exit 1; }
grep -q 'Codex auto-update finished version=codex-cli 1.0.0 -> codex-cli 9.9.9' "$ACTIVATION_LOG" \
  || { echo "A: expected before/after versions in the log" >&2; exit 1; }

# ── B) throttled on the next run ────────────────────────────────────────────
reset_state
run_once env || { echo "B: expected the run to succeed" >&2; exit 1; }
[[ "$(update_calls)" == "0" ]] || { echo "B: the stamp must throttle updates" >&2; exit 1; }
jq -e 'has("cli_update") | not' <<<"$(last_usage)" >/dev/null \
  || { echo "B: no cli_update expected without an attempt" >&2; exit 1; }

# ── C) failing updater: non-fatal, still stamped ────────────────────────────
reset_state; rm -f "$STAMP"
run_once env UPDATE_FAIL=1 || { echo "C: a failed update must not fail the run" >&2; exit 1; }
[[ "$(update_calls)" == "1" && -f "$SENTINEL_DIR/exec-models" ]] \
  || { echo "C: expected one failed update then the prompt" >&2; exit 1; }
jq -e '.ok == true and .cli_update.exit == 3' <<<"$(last_usage)" >/dev/null \
  || { echo "C: expected cli_update.exit=3: $(last_usage)" >&2; exit 1; }
grep -q 'WARNING: Codex auto-update failed exit=3' "$ACTIVATION_LOG" \
  || { echo "C: expected a failure WARNING" >&2; exit 1; }
reset_state
run_once env UPDATE_FAIL=1 || true
[[ "$(update_calls)" == "0" ]] || { echo "C: a failed attempt must still throttle" >&2; exit 1; }

# C2: hung updater → timeout (exit 124), whole tree killed, stamped, prompt still sent
reset_state; rm -f "$STAMP"
run_once env UPDATE_HANG=1 CODEX_UPDATE_TIMEOUT_SECONDS=1 || { echo "C2: a timed-out update must not fail the run" >&2; exit 1; }
[[ -f "$SENTINEL_DIR/exec-models" ]] || { echo "C2: expected the prompt after the timeout" >&2; exit 1; }
jq -e '.ok == true and .cli_update.exit == 124' <<<"$(last_usage)" >/dev/null \
  || { echo "C2: expected cli_update.exit=124: $(last_usage)" >&2; exit 1; }
[[ -f "$STAMP" ]] || { echo "C2: a timed-out attempt must still be stamped" >&2; exit 1; }
grandchild="$(cat "$SENTINEL_DIR/grandchild")"
if kill -0 "$grandchild" 2>/dev/null; then
  kill "$grandchild" 2>/dev/null || true
  echo "C2: the timed-out command's grandchild (pid $grandchild) was orphaned" >&2; exit 1
fi

# C3: binary unusable after the update → ERROR, stamp dropped, prompt still attempted
reset_state; rm -f "$STAMP"
run_once env UPDATE_BREAK=1 || true
grep -q 'ERROR: codex binary unusable after update' "$ACTIVATION_LOG" \
  || { echo "C3: expected the unusable-binary ERROR" >&2; exit 1; }
[[ ! -f "$STAMP" ]] || { echo "C3: the stamp must be removed so the next slot retries" >&2; exit 1; }
[[ -f "$SENTINEL_DIR/exec-models" ]] || { echo "C3: the run must still be attempted" >&2; exit 1; }

# C4: a stamp in the future (clock moved back) is treated as expired
reset_state
echo $(( $(date +%s) + 100000 )) >"$STAMP"
run_once env || { echo "C4: expected the run to succeed" >&2; exit 1; }
[[ "$(update_calls)" == "1" ]] || { echo "C4: a future stamp must not throttle" >&2; exit 1; }

# ── D) disabled ─────────────────────────────────────────────────────────────
reset_state; rm -f "$STAMP"
run_once env CODEX_AUTO_UPDATE=0 || { echo "D: expected the run to succeed" >&2; exit 1; }
[[ "$(update_calls)" == "0" && ! -f "$STAMP" ]] || { echo "D: CODEX_AUTO_UPDATE=0 must not update" >&2; exit 1; }

# ── E) preflight skip → no update (anchored weekly-only window via native) ──
reset_state; rm -f "$STAMP"
cat >"$TMP_DIR/bin/curl-fake" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '{"plan_type":"plus","rate_limit":{"allowed":true,"primary_window":{"used_percent":5,"limit_window_seconds":604800,"reset_at":%s},"secondary_window":null}}\n' "$(( $(date +%s) + 259200 ))"
SH
chmod +x "$TMP_DIR/bin/curl-fake"
jq -n '{tokens: {access_token: "tok", account_id: "acct"}}' >"$TMP_DIR/auth.json"
run_once env ENABLE_QUOTA_PREFLIGHT=1 CODEX_STATUS_SOURCE=native \
  CODEX_AUTH_FILE="$TMP_DIR/auth.json" CURL_BIN="$TMP_DIR/bin/curl-fake" || true
jq -e '.skipped == true' <<<"$(last_usage)" >/dev/null || { echo "E: expected a skipped run" >&2; exit 1; }
[[ "$(update_calls)" == "0" && ! -f "$STAMP" ]] || { echo "E: a skipped run must not update" >&2; exit 1; }

# ── F) dry-run → no update ──────────────────────────────────────────────────
reset_state
CODEX_BIN="$TMP_DIR/bin/codex-fake" "$ENGINE" --dry-run --tool codex >/dev/null 2>&1
[[ "$(update_calls)" == "0" && ! -f "$STAMP" ]] || { echo "F: dry-run must not update" >&2; exit 1; }

# ── G) model rejected → retry with the preferred candidate ──────────────────
reset_state
rows_before="$(grep -c '"tool":"codex"' "$USAGE" || true)"
run_once env CODEX_AUTO_UPDATE=0 REJECT_MODEL=gpt-old-luna \
  || { echo "G: expected the fallback retry to succeed" >&2; exit 1; }
[[ "$(paste -sd, "$SENTINEL_DIR/exec-models")" == "gpt-old-luna,gpt-new-luna" ]] \
  || { echo "G: expected gpt-old-luna then gpt-new-luna, got $(paste -sd, "$SENTINEL_DIR/exec-models")" >&2; exit 1; }
[[ "$(grep -c '"tool":"codex"' "$USAGE")" == "$(( rows_before + 2 ))" ]] \
  || { echo "G: expected one usage row per attempt" >&2; exit 1; }
first_row="$(grep '"tool":"codex"' "$USAGE" | tail -2 | head -1)"
jq -e '.ok == false and .model == "gpt-old-luna" and (has("model_fallback") | not) and .superseded_by_fallback == true' \
  <<<"$first_row" >/dev/null || { echo "G: unexpected first (rejected) row: $first_row" >&2; exit 1; }
jq -e '.ok == true and .model == "gpt-new-luna" and .model_fallback == {from: "gpt-old-luna", to: "gpt-new-luna", attempt: 1}
       and (has("superseded_by_fallback") | not)' \
  <<<"$(last_usage)" >/dev/null || { echo "G: unexpected fallback row: $(last_usage)" >&2; exit 1; }
grep -q 'WARNING: Set CODEX_MODEL=gpt-new-luna in' "$ACTIVATION_LOG" \
  || { echo "G: expected the loud CODEX_MODEL advice" >&2; exit 1; }

# G2: with no luna left, terra beats the earlier-listed sol
reset_state
jq '.models |= map(select(.slug == "gpt-old-luna" or (.slug | test("luna") | not)))' "$CACHE" >"$TMP_DIR/cache2.json"
run_once env CODEX_AUTO_UPDATE=0 REJECT_MODEL=gpt-old-luna CODEX_MODELS_CACHE="$TMP_DIR/cache2.json" \
  || { echo "G2: expected the fallback retry to succeed" >&2; exit 1; }
jq -e '.model == "gpt-x-terra"' <<<"$(last_usage)" >/dev/null \
  || { echo "G2: expected terra over sol: $(last_usage)" >&2; exit 1; }

# G3: the rejected model's own upgrade.model wins over the tiers
reset_state
jq '.models |= map(if .slug == "gpt-old-luna" then .upgrade = {model: "gpt-x-terra", retirement_at: "2099-01-01T00:00:00Z"} else . end)' \
  "$CACHE" >"$TMP_DIR/cache-upgrade.json"
run_once env CODEX_AUTO_UPDATE=0 REJECT_MODEL=gpt-old-luna CODEX_MODELS_CACHE="$TMP_DIR/cache-upgrade.json" \
  || { echo "G3: expected the fallback retry to succeed" >&2; exit 1; }
jq -e '.model == "gpt-x-terra"' <<<"$(last_usage)" >/dev/null \
  || { echo "G3: expected the upgrade.model target: $(last_usage)" >&2; exit 1; }

# G4: every candidate rejected → capped at MAX_TRIES fallback attempts, run fails
reset_state
rows_before="$(grep -c '"tool":"codex"' "$USAGE" || true)"
if run_once env CODEX_AUTO_UPDATE=0 REJECT_ALL=1 CODEX_MODEL_FALLBACK_MAX_TRIES=2; then
  echo "G4: expected the run to fail when every model is rejected" >&2; exit 1
fi
[[ "$(paste -sd, "$SENTINEL_DIR/exec-models")" == "gpt-old-luna,gpt-new-luna,gpt-late-luna" ]] \
  || { echo "G4: expected 1 + 2 attempts, got $(paste -sd, "$SENTINEL_DIR/exec-models")" >&2; exit 1; }
[[ "$(grep -c '"tool":"codex"' "$USAGE")" == "$(( rows_before + 3 ))" ]] \
  || { echo "G4: expected three usage rows" >&2; exit 1; }
grep '"tool":"codex"' "$USAGE" | tail -3 | jq -s -e '
    map(.superseded_by_fallback // false) == [true, true, false]
    and map(.model_fallback.attempt // 0) == [0, 1, 2]
    and .[2].model_fallback == {from: "gpt-new-luna", to: "gpt-late-luna", attempt: 2}
    and all(.[]; .ok == false)' >/dev/null \
  || { echo "G4: unexpected attempt rows" >&2; exit 1; }
grep -q 'gave up after 2 fallback attempt' "$ACTIVATION_LOG" \
  || { echo "G4: expected the gave-up ERROR" >&2; exit 1; }

# ── H) no candidate left → ERROR, no retry ──────────────────────────────────
reset_state
jq '.models |= map(select(.slug == "gpt-old-luna" or .visibility == "hide" or .slug == "gpt-nolow-luna" or .slug == "gpt-retired-luna"))' \
  "$CACHE" >"$TMP_DIR/cache3.json"
if run_once env CODEX_AUTO_UPDATE=0 REJECT_MODEL=gpt-old-luna CODEX_MODELS_CACHE="$TMP_DIR/cache3.json"; then
  echo "H: expected the run to fail without a candidate" >&2; exit 1
fi
[[ "$(wc -l <"$SENTINEL_DIR/exec-models" | tr -d ' ')" == "1" ]] || { echo "H: must not retry" >&2; exit 1; }
grep -q 'ERROR: Codex rejected model gpt-old-luna and no fallback model is available' "$ACTIVATION_LOG" \
  || { echo "H: expected an ERROR" >&2; exit 1; }
# H2: a missing cache behaves the same
reset_state
if run_once env CODEX_AUTO_UPDATE=0 REJECT_MODEL=gpt-old-luna CODEX_MODELS_CACHE="$TMP_DIR/missing.json"; then
  echo "H2: expected the run to fail with no cache" >&2; exit 1
fi
[[ "$(wc -l <"$SENTINEL_DIR/exec-models" | tr -d ' ')" == "1" ]] || { echo "H2: must not retry" >&2; exit 1; }
# H3: an unreadable cache (no read permission) behaves the same
reset_state
cp "$CACHE" "$TMP_DIR/unreadable.json" && chmod 000 "$TMP_DIR/unreadable.json"
if run_once env CODEX_AUTO_UPDATE=0 REJECT_MODEL=gpt-old-luna CODEX_MODELS_CACHE="$TMP_DIR/unreadable.json"; then
  echo "H3: expected the run to fail with an unreadable cache" >&2; exit 1
fi
chmod 600 "$TMP_DIR/unreadable.json"
[[ "$(wc -l <"$SENTINEL_DIR/exec-models" | tr -d ' ')" == "1" ]] || { echo "H3: must not retry" >&2; exit 1; }

# ── I) fallback disabled ────────────────────────────────────────────────────
reset_state
run_once env CODEX_AUTO_UPDATE=0 CODEX_MODEL_FALLBACK=0 REJECT_MODEL=gpt-old-luna || true
[[ "$(wc -l <"$SENTINEL_DIR/exec-models" | tr -d ' ')" == "1" ]] || { echo "I: CODEX_MODEL_FALLBACK=0 must not retry" >&2; exit 1; }

# ── J) other errors never retry ─────────────────────────────────────────────
reset_state
run_once env CODEX_AUTO_UPDATE=0 OTHER_FAIL=1 || true
[[ "$(wc -l <"$SENTINEL_DIR/exec-models" | tr -d ' ')" == "1" ]] || { echo "J: a non-model error must not retry" >&2; exit 1; }

# ── K) validation ───────────────────────────────────────────────────────────
for bad in "CODEX_AUTO_UPDATE=yes" "CODEX_MODEL_FALLBACK=2" "CODEX_MODEL_FALLBACK_MAX_TRIES=0" "CODEX_AUTO_UPDATE_INTERVAL_HOURS=0" "CODEX_UPDATE_TIMEOUT_SECONDS=abc"; do
  if env "$bad" "$ENGINE" --dry-run --tool codex >/dev/null 2>&1; then
    echo "K: expected $bad to be rejected" >&2; exit 1
  fi
done

echo "codex update/fallback test passed"
