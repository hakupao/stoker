#!/usr/bin/env bash
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ -f "$ENV_FILE" ]]; then
  # Caller's environment takes precedence over .env values.
  _saved_exports="$(export -p)"
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
  eval "$_saved_exports"
  unset _saved_exports
fi

set -u

LOG_DIR="${ROOT_DIR}/logs"
RAW_LOG_DIR="${LOG_DIR}/raw"
USAGE_LOG="${LOG_DIR}/usage.jsonl"
STATUS_LOG="${LOG_DIR}/status.jsonl"
RUN_DIR="${ROOT_DIR}/run"
LOCK_DIR="${RUN_DIR}/activation.lock"

PATH_VALUE="${PATH_VALUE:-${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
export PATH="${PATH_VALUE}:${PATH:-}"
export HOME="${HOME}"

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || true)}"
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
  _bundled_jq="${ROOT_DIR}/bin/jq"
  [[ -x "$_bundled_jq" ]] && JQ_BIN="$_bundled_jq"
  unset _bundled_jq
fi
NODE_BIN="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"
OMC_BIN="${OMC_BIN:-$(command -v omc 2>/dev/null || true)}"
ACTIVATION_PROMPT="${ACTIVATION_PROMPT:-Reply exactly READY. Do not inspect files, run tools, or modify anything.}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.4-mini}"
CODEX_WORK_DIR="${CODEX_WORK_DIR:-${ROOT_DIR}/codex-probe}"
CODEX_ACTIVATION_PROMPT="${CODEX_ACTIVATION_PROMPT:-Read only ./probe.py. Do not inspect any other path. Do not modify files. In two short bullets, explain what activation_probe_score returns for SAMPLE_EVENTS, then end with READY.}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
ACTIVATION_TOOL="${ACTIVATION_TOOL:-all}"
ENABLE_STATUS_SNAPSHOTS="${ENABLE_STATUS_SNAPSHOTS:-1}"
ENABLE_QUOTA_PREFLIGHT="${ENABLE_QUOTA_PREFLIGHT:-1}"
QUOTA_PREFLIGHT_ON_UNKNOWN="${QUOTA_PREFLIGHT_ON_UNKNOWN:-allow}"
QUOTA_EXHAUSTED_THRESHOLD_PERCENT="${QUOTA_EXHAUSTED_THRESHOLD_PERCENT:-0}"
CLAUDE_STATUS_SOURCE="${CLAUDE_STATUS_SOURCE:-cache}"
CLAUDE_USAGE_CACHE_FILE="${CLAUDE_USAGE_CACHE_FILE:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/plugins/oh-my-claudecode/.usage-cache-anthropic.json}"
KEEP_AWAKE_MODE="${KEEP_AWAKE_MODE:-off}"
KEEP_AWAKE_SECONDS="${KEEP_AWAKE_SECONDS:-900}"
RUN_ID="${RUN_ID:-$(date '+%Y%m%d-%H%M%S')-$$}"

# Optional long-lived OAuth token for unattended auth (from `claude setup-token`).
# When present, the scheduled `claude -p` run authenticates with this token instead
# of the interactive session's shared macOS Keychain login — which is short-lived and
# gets rotated out from under an unattended run, surfacing as "401 Invalid
# authentication credentials". Only keep it exported when non-empty so a blank value
# never overrides the normal Keychain login.
if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  export CLAUDE_CODE_OAUTH_TOKEN
else
  unset CLAUDE_CODE_OAUTH_TOKEN
fi

MODE="once"
TOOL="$ACTIVATION_TOOL"

usage() {
  cat <<'USAGE'
Usage: activate-ai-window.sh [--once] [--dry-run] [--check] [--status] [--tool all|claude|codex]

Runs a tiny scheduled check-in against Claude Code and Codex to start usage
windows at predictable times. The default mode is --once.

Environment overrides:
  CLAUDE_BIN=/path/to/claude
  CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...   # long-lived headless auth (claude setup-token)
  CODEX_BIN=/path/to/codex
  ACTIVATION_PROMPT='Reply exactly READY...'
  CODEX_MODEL=gpt-5.4-mini
  CODEX_WORK_DIR=/path/to/probe-dir
  CODEX_ACTIVATION_PROMPT='Read only ./probe.py...'
  TIMEOUT_SECONDS=120
  ACTIVATION_TOOL=all
  ENABLE_STATUS_SNAPSHOTS=1
  ENABLE_QUOTA_PREFLIGHT=1
  QUOTA_PREFLIGHT_ON_UNKNOWN=allow
  QUOTA_EXHAUSTED_THRESHOLD_PERCENT=0
  CLAUDE_STATUS_SOURCE=cache
  CLAUDE_USAGE_CACHE_FILE=/path/to/.usage-cache-anthropic.json
  KEEP_AWAKE_MODE=off
  KEEP_AWAKE_SECONDS=900
  JQ_BIN=/path/to/jq
  NODE_BIN=/path/to/node
  OMC_BIN=/path/to/omc
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)
      MODE="once"
      shift
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --check)
      MODE="check"
      shift
      ;;
    --status)
      MODE="status"
      shift
      ;;
    --tool)
      if [[ $# -lt 2 ]]; then
        echo "--tool requires all, claude, or codex" >&2
        exit 2
      fi
      TOOL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$TOOL" in
  all|claude|codex) ;;
  *)
    echo "--tool must be all, claude, or codex" >&2
    exit 2
    ;;
esac

case "$QUOTA_PREFLIGHT_ON_UNKNOWN" in
  allow|skip) ;;
  *)
    echo "QUOTA_PREFLIGHT_ON_UNKNOWN must be allow or skip" >&2
    exit 2
    ;;
esac

case "$CLAUDE_STATUS_SOURCE" in
  cache|omc) ;;
  *)
    echo "CLAUDE_STATUS_SOURCE must be cache or omc" >&2
    exit 2
    ;;
esac

case "$KEEP_AWAKE_MODE" in
  off|during|always) ;;
  *)
    echo "KEEP_AWAKE_MODE must be off, during, or always" >&2
    exit 2
    ;;
esac

if ! [[ "$KEEP_AWAKE_SECONDS" =~ ^[0-9]+$ ]] || (( 10#$KEEP_AWAKE_SECONDS <= 0 )); then
  echo "KEEP_AWAKE_SECONDS must be a positive integer" >&2
  exit 2
fi

mkdir -p "$LOG_DIR" "$RAW_LOG_DIR" "$RUN_DIR"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S %Z'
}

stamp_for_file() {
  date '+%Y%m%d-%H%M%S'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*" | tee -a "${LOG_DIR}/activation.log"
}

require_bin() {
  local name="$1"
  local path="$2"
  if [[ -z "$path" || ! -x "$path" ]]; then
    log "ERROR: ${name} binary not found or not executable: ${path:-<empty>}"
    return 1
  fi
}

maybe_reexec_with_caffeinate() {
  if [[ "$MODE" != "once" || "$KEEP_AWAKE_MODE" == "off" || "${STOKER_CAFFEINATED:-0}" == "1" ]]; then
    return 0
  fi

  local caffeinate_bin
  caffeinate_bin="${CAFFEINATE_BIN:-$(command -v caffeinate 2>/dev/null || true)}"
  if [[ -z "$caffeinate_bin" || ! -x "$caffeinate_bin" ]]; then
    log "WARNING: caffeinate not found; continuing without keep-awake protection"
    return 0
  fi

  log "Keep-awake enabled mode=${KEEP_AWAKE_MODE} seconds=${KEEP_AWAKE_SECONDS}"
  STOKER_CAFFEINATED=1 exec "$caffeinate_bin" -i -t "$KEEP_AWAKE_SECONDS" "$BASH" "$0" "$@"
}

run_with_timeout() {
  local output_file="$1"
  shift

  "$@" >"$output_file" 2>&1 &
  local pid=$!
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= TIMEOUT_SECONDS )); then
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
}

summarize_output() {
  local output_file="$1"
  if grep -q 'READY' "$output_file" 2>/dev/null; then
    printf 'result=READY'
    return
  fi

  local first_line
  first_line="$(sed -n '1p' "$output_file" | tr '\n' ' ' | cut -c 1-180)"
  if [[ -n "$first_line" ]]; then
    printf 'result=%s' "$first_line"
  else
    printf 'result=<empty>'
  fi
}

record_claude_usage() {
  local exit_code="$1"
  local output_file="$2"

  if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
    log "WARNING: jq not found; Claude usage snapshot was not recorded"
    return 0
  fi

  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  if "$JQ_BIN" -c -Rcs \
    --arg timestamp "$(timestamp)" \
    --arg run_id "$RUN_ID" \
    --arg tool "claude" \
    --argjson exit_code "$exit_code" \
    --arg raw_log "$output_file" '
      (split("\n") | map(select(length > 0) | try fromjson catch empty) | first // {}) as $o
      | {
          timestamp: $timestamp,
          run_id: $run_id,
          tool: $tool,
          exit_code: $exit_code,
          ok: ($exit_code == 0),
          api_error_status: ($o.api_error_status // null),
          result: ($o.result // null),
          session_id: ($o.session_id // null),
          model: ($o.model // $o.model_name // null),
          duration_ms: ($o.duration_ms // null),
          total_cost_usd: ($o.total_cost_usd // null),
          usage: ($o.usage // $o.token_usage // null),
          raw_log: $raw_log
        }
    ' "$output_file" >>"$USAGE_LOG" 2>/dev/null; then
    log "Claude usage snapshot recorded usage_log=${USAGE_LOG}"
  else
    log "WARNING: failed to parse Claude usage snapshot from ${output_file}"
  fi
}

record_codex_usage() {
  local exit_code="$1"
  local output_file="$2"

  if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
    log "WARNING: jq not found; Codex usage snapshot was not recorded"
    return 0
  fi

  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  if "$JQ_BIN" -c -Rcs \
    --arg timestamp "$(timestamp)" \
    --arg run_id "$RUN_ID" \
    --arg tool "codex" \
    --arg model "$CODEX_MODEL" \
    --argjson exit_code "$exit_code" \
    --arg raw_log "$output_file" '
      (split("\n") | map(select(length > 0) | try fromjson catch empty)) as $events
      | ($events | map(select(.type == "thread.started")) | first // {}) as $thread
      | ($events | map(select(.type == "turn.completed")) | last // {}) as $completed
      | ($events | map(select(.type == "turn.failed")) | last // null) as $failed
      | ($events | map(select(.type == "item.completed" and .item.type == "agent_message")) | last // {}) as $message
      | {
          timestamp: $timestamp,
          run_id: $run_id,
          tool: $tool,
          exit_code: $exit_code,
          ok: ($exit_code == 0 and ($completed.type == "turn.completed")),
          thread_id: ($thread.thread_id // null),
          model: $model,
          result: ($message.item.text // null),
          usage: ($completed.usage // null),
          failure: ($failed // null),
          event_count: ($events | length),
          raw_log: $raw_log
        }
    ' "$output_file" >>"$USAGE_LOG" 2>/dev/null; then
    log "Codex usage snapshot recorded usage_log=${USAGE_LOG}"
  else
    log "WARNING: failed to parse Codex usage snapshot from ${output_file}"
  fi
}

record_claude_status() {
  local output_file
  output_file="${RAW_LOG_DIR}/$(stamp_for_file)-claude-status.log"
  local status_exit=0
  local cache_file="$CLAUDE_USAGE_CACHE_FILE"

  if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
    log "WARNING: jq not found; Claude status snapshot was not recorded"
    return 0
  fi

  if [[ "$CLAUDE_STATUS_SOURCE" == "omc" ]]; then
    # Legacy live query. In an unattended run `omc wait status` reads the shared
    # Keychain OAuth credential and, once the access token has expired, consumes
    # its refresh token without being able to persist the replacement — logging
    # the interactive Claude Code session out. Prefer CLAUDE_STATUS_SOURCE=cache.
    if [[ -z "$OMC_BIN" || ! -x "$OMC_BIN" ]]; then
      log "WARNING: omc not found; Claude quota status snapshot was not recorded"
      return 1
    fi
    "$OMC_BIN" wait status >"$output_file" 2>&1 || status_exit=$?
  fi

  if [[ ! -f "$cache_file" ]]; then
    log "WARNING: Claude usage cache not found at ${cache_file}; the oh-my-claudecode plugin writes it during interactive Claude Code use"
    return 1
  fi

  if [[ "$CLAUDE_STATUS_SOURCE" == "cache" ]]; then
    # No live query: snapshot the plugin's last-known quota so unattended runs
    # never touch the shared Keychain OAuth credential. cache_age_seconds in the
    # row tells consumers how old the data is.
    cp "$cache_file" "$output_file" 2>/dev/null || true
  fi

  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  "$JQ_BIN" -c \
    --arg timestamp "$(timestamp)" \
    --arg run_id "$RUN_ID" \
    --arg tool "claude" \
    --arg status_source "$CLAUDE_STATUS_SOURCE" \
    --argjson query_exit_code "$status_exit" \
    --arg raw_log "$output_file" '
      . as $cache
      | ($cache.data // {}) as $d
      | {
          timestamp: $timestamp,
          run_id: $run_id,
          tool: $tool,
          ok: ($query_exit_code == 0 and ($cache.error // false | not)),
          query_exit_code: $query_exit_code,
          status_source: $status_source,
          source: ($cache.source // null),
          subscription_type: null,
          cache_age_seconds: (if $cache.timestamp == null then null else ((now - ($cache.timestamp / 1000)) | round) end),
          cache_timestamp_ms: ($cache.timestamp // null),
          last_success_at_ms: ($cache.lastSuccessAt // null),
          five_hour: {
            used_percent: ($d.fiveHourPercent // null),
            remaining_percent: (if $d.fiveHourPercent == null then null else (100 - $d.fiveHourPercent) end),
            resets_at: ($d.fiveHourResetsAt // null)
          },
          weekly: {
            used_percent: ($d.weeklyPercent // null),
            remaining_percent: (if $d.weeklyPercent == null then null else (100 - $d.weeklyPercent) end),
            resets_at: ($d.weeklyResetsAt // null)
          },
          sonnet_weekly: {
            used_percent: ($d.sonnetWeeklyPercent // null),
            remaining_percent: (if $d.sonnetWeeklyPercent == null then null else (100 - $d.sonnetWeeklyPercent) end),
            resets_at: ($d.sonnetWeeklyResetsAt // null)
          },
          raw_log: $raw_log
        }
    ' "$cache_file" >>"$STATUS_LOG" 2>/dev/null || {
      log "WARNING: failed to parse Claude status snapshot"
      return 1
    }

  log "Claude status snapshot recorded source=${CLAUDE_STATUS_SOURCE} status_log=${STATUS_LOG}"
}

record_codex_status() {
  local output_file
  output_file="${RAW_LOG_DIR}/$(stamp_for_file)-codex-status.log"

  if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
    log "WARNING: jq not found; Codex status snapshot was not recorded"
    return 0
  fi

  if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
    log "WARNING: node not found; Codex status snapshot was not recorded"
    return 1
  fi

  if [[ -z "$CODEX_BIN" || ! -x "$CODEX_BIN" ]]; then
    log "WARNING: Codex binary not found; Codex status snapshot was not recorded"
    return 1
  fi

  CODEX_BIN="$CODEX_BIN" "$NODE_BIN" >"$output_file" 2>&1 <<'NODE' || true
const { spawn } = require("child_process");

const codexBin = process.env.CODEX_BIN || "codex";
const child = spawn(codexBin, ["app-server", "--listen", "stdio://"], {
  cwd: process.cwd(),
  stdio: ["pipe", "pipe", "pipe"],
});

let stdoutBuffer = "";
let settled = false;

function finish(code) {
  if (settled) return;
  settled = true;
  try { child.stdin.end(); } catch {}
  try { child.kill("SIGTERM"); } catch {}
  process.exit(code);
}

function send(obj) {
  child.stdin.write(JSON.stringify(obj) + "\n");
}

const timer = setTimeout(() => {
  console.log(JSON.stringify({ kind: "codex_rate_limits_error", error: "timeout" }));
  finish(124);
}, 15000);

child.stdout.on("data", (buf) => {
  stdoutBuffer += buf.toString();
  let idx;
  while ((idx = stdoutBuffer.indexOf("\n")) >= 0) {
    const line = stdoutBuffer.slice(0, idx).trim();
    stdoutBuffer = stdoutBuffer.slice(idx + 1);
    if (!line) continue;

    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }

    if (msg.id === 1) {
      send({ id: 2, method: "account/rateLimits/read" });
      continue;
    }

    if (msg.id === 2) {
      clearTimeout(timer);
      if (msg.error) {
        console.log(JSON.stringify({ kind: "codex_rate_limits_error", error: msg.error }));
        finish(1);
      } else {
        console.log(JSON.stringify({ kind: "codex_rate_limits", result: msg.result }));
        finish(0);
      }
    }
  }
});

child.stderr.on("data", (buf) => {
  process.stderr.write(buf);
});

child.on("error", (err) => {
  console.log(JSON.stringify({ kind: "codex_rate_limits_error", error: err.message }));
  clearTimeout(timer);
  finish(1);
});

child.on("exit", (code, signal) => {
  if (!settled) {
    console.log(JSON.stringify({ kind: "codex_rate_limits_error", error: `app-server exited code=${code} signal=${signal}` }));
    clearTimeout(timer);
    finish(code || 1);
  }
});

send({
  id: 1,
  method: "initialize",
  params: {
    clientInfo: { name: "stoker", version: "0.3.1" },
    capabilities: null,
  },
});
NODE

  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  "$JQ_BIN" -c -Rcs \
    --arg timestamp "$(timestamp)" \
    --arg run_id "$RUN_ID" \
    --arg tool "codex" \
    --arg raw_log "$output_file" '
      (split("\n") | map(select(length > 0) | try fromjson catch empty)) as $events
      | ($events | map(select(.kind == "codex_rate_limits")) | last) as $record
      | ($events | map(select(.kind == "codex_rate_limits_error")) | last // null) as $error
      | ($record.result.rateLimitsByLimitId.codex // $record.result.rateLimits // {}) as $snapshot
      | ($snapshot.primary // {}) as $primary
      | ($snapshot.secondary // {}) as $secondary
      | {
          timestamp: $timestamp,
          run_id: $run_id,
          tool: $tool,
          ok: ($record != null),
          plan_type: ($snapshot.planType // null),
          limit_id: ($snapshot.limitId // null),
          limit_name: ($snapshot.limitName // null),
          rate_limit_reached_type: ($snapshot.rateLimitReachedType // null),
          credits: ($snapshot.credits // null),
          five_hour: {
            used_percent: ($primary.usedPercent // null),
            remaining_percent: (if $primary.usedPercent == null then null else (100 - $primary.usedPercent) end),
            window_minutes: ($primary.windowDurationMins // null),
            resets_at_epoch: ($primary.resetsAt // null),
            resets_at: (if $primary.resetsAt == null then null else ($primary.resetsAt | todateiso8601) end)
          },
          weekly: {
            used_percent: ($secondary.usedPercent // null),
            remaining_percent: (if $secondary.usedPercent == null then null else (100 - $secondary.usedPercent) end),
            window_minutes: ($secondary.windowDurationMins // null),
            resets_at_epoch: ($secondary.resetsAt // null),
            resets_at: (if $secondary.resetsAt == null then null else ($secondary.resetsAt | todateiso8601) end)
          },
          error: $error,
          raw_log: $raw_log
        }
    ' "$output_file" >>"$STATUS_LOG" 2>/dev/null || {
      log "WARNING: failed to parse Codex status snapshot"
      return 1
    }

  log "Codex status snapshot recorded status_log=${STATUS_LOG}"
}

record_status_snapshots() {
  local status=0

  if [[ "$TOOL" == "all" || "$TOOL" == "claude" ]]; then
    record_claude_status || status=1
  fi

  if [[ "$TOOL" == "all" || "$TOOL" == "codex" ]]; then
    record_codex_status || status=1
  fi

  return "$status"
}

quota_preflight_decision() {
  local tool="$1"

  if [[ "$ENABLE_QUOTA_PREFLIGHT" != "1" ]]; then
    printf '{"tool":"%s","action":"allow","reason":"preflight_disabled"}\n' "$tool"
    return 0
  fi

  if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
    printf '{"tool":"%s","action":"allow","reason":"jq_unavailable"}\n' "$tool"
    return 0
  fi

  if [[ ! -f "$STATUS_LOG" ]]; then
    printf '{"tool":"%s","action":"%s","reason":"preflight_status_missing"}\n' "$tool" "$QUOTA_PREFLIGHT_ON_UNKNOWN"
    return 0
  fi

  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  "$JQ_BIN" -s -c \
    --arg tool "$tool" \
    --arg run_id "$RUN_ID" \
    --arg on_unknown "$QUOTA_PREFLIGHT_ON_UNKNOWN" \
    --argjson threshold "$QUOTA_EXHAUSTED_THRESHOLD_PERCENT" '
      def unknown($reason):
        {
          tool: $tool,
          action: (if $on_unknown == "skip" then "skip" else "allow" end),
          reason: $reason,
          status_ok: false
        };
      def n($x):
        if $x == null then null
        elif ($x | type) == "number" then $x
        elif ($x | type) == "string" then ($x | tonumber? // null)
        else null
        end;
      # Snapshots can be last-known data (CLAUDE_STATUS_SOURCE=cache): a window
      # whose resets_at is already in the past has rolled over since the data
      # was captured, so it must not count as exhausted.
      def reset_passed($w):
        ($w.resets_at // null) as $r
        | if $r == null then false
          else
            ((try ($r | tostring | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null)) as $t
            | if $t == null then false else ($t < now) end
          end;
      def exhausted($name; $w):
        if reset_passed($w) then empty
        else
          (n($w.remaining_percent // null)) as $remaining
          | (n($w.used_percent // null)) as $used
          | if ($remaining != null and $remaining <= $threshold) then
              $name + "_remaining_exhausted"
            elif ($used != null and $used >= (100 - $threshold)) then
              $name + "_used_exhausted"
            else
              empty
            end
        end;

      (map(select(.tool == $tool and .run_id == $run_id)) | last // null) as $s
      | if $s == null then
          unknown("preflight_status_missing")
        elif ($s.ok != true) then
          unknown("preflight_status_not_ok")
        else
          ($s.five_hour // {}) as $five
          | ($s.weekly // {}) as $weekly
          | ($s.sonnet_weekly // {}) as $sonnet_weekly
          | (($s.rate_limit_reached_type // "") | tostring) as $rate_limit_reached_type
          | [
              exhausted("five_hour"; $five),
              exhausted("weekly"; $weekly),
              (if $tool == "claude" then exhausted("sonnet_weekly"; $sonnet_weekly) else empty end),
              (
                if $tool == "codex" and $rate_limit_reached_type != "" and $rate_limit_reached_type != "null" then
                  "rate_limit_reached:" + $rate_limit_reached_type
                else
                  empty
                end
              )
            ] as $reasons
          | {
              tool: $tool,
              action: (if ($reasons | length) > 0 then "skip" else "allow" end),
              reason: (if ($reasons | length) > 0 then "quota_exhausted" else "quota_available" end),
              status_ok: true,
              exhausted: $reasons,
              status_timestamp: ($s.timestamp // null),
              rate_limit_reached_type: ($s.rate_limit_reached_type // null),
              five_hour_remaining_percent: ($five.remaining_percent // null),
              weekly_remaining_percent: ($weekly.remaining_percent // null),
              sonnet_weekly_remaining_percent: ($sonnet_weekly.remaining_percent // null)
            }
        end
    ' "$STATUS_LOG" 2>/dev/null || {
      printf '{"tool":"%s","action":"%s","reason":"preflight_decision_failed"}\n' "$tool" "$QUOTA_PREFLIGHT_ON_UNKNOWN"
    }
}

record_skipped_usage() {
  local tool="$1"
  local reason="$2"
  local decision_json="$3"

  if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
    log "WARNING: jq not found; skipped ${tool} usage snapshot was not recorded"
    return 0
  fi

  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  "$JQ_BIN" -n -c \
    --arg timestamp "$(timestamp)" \
    --arg run_id "$RUN_ID" \
    --arg tool "$tool" \
    --arg reason "$reason" \
    --argjson decision "$decision_json" '
      {
        timestamp: $timestamp,
        run_id: $run_id,
        tool: $tool,
        ok: true,
        skipped: true,
        skip_reason: $reason,
        preflight: $decision
      }
    ' >>"$USAGE_LOG" 2>/dev/null || {
      log "WARNING: failed to record skipped ${tool} usage snapshot"
      return 1
    }

  log "${tool} usage snapshot recorded as skipped usage_log=${USAGE_LOG}"
}

maybe_skip_for_quota() {
  local tool="$1"
  local decision_json
  local action
  local reason

  if [[ "$MODE" == "dry-run" || "$ENABLE_QUOTA_PREFLIGHT" != "1" ]]; then
    return 1
  fi

  decision_json="$(quota_preflight_decision "$tool")"
  if [[ -n "$JQ_BIN" && -x "$JQ_BIN" ]]; then
    action="$(printf '%s' "$decision_json" | "$JQ_BIN" -r '.action // "allow"' 2>/dev/null || printf 'allow')"
    reason="$(printf '%s' "$decision_json" | "$JQ_BIN" -r '.reason // "unknown"' 2>/dev/null || printf 'unknown')"
  else
    action="allow"
    reason="jq_unavailable"
  fi

  if [[ "$action" == "skip" ]]; then
    log "${tool} job skipped by quota preflight reason=${reason}"
    record_skipped_usage "$tool" "$reason" "$decision_json"
    return 0
  fi

  if [[ "$reason" != "quota_available" && "$reason" != "preflight_disabled" ]]; then
    log "WARNING: ${tool} quota preflight was inconclusive reason=${reason}; proceeding because QUOTA_PREFLIGHT_ON_UNKNOWN=${QUOTA_PREFLIGHT_ON_UNKNOWN}"
  else
    log "${tool} quota preflight passed"
  fi

  return 1
}

run_claude() {
  local output_file
  output_file="${RAW_LOG_DIR}/$(stamp_for_file)-claude.log"
  local cmd=(
    "$CLAUDE_BIN"
    -p "$ACTIVATION_PROMPT"
    --model haiku
    --system-prompt "Reply only: READY"
    --setting-sources ""
    --effort low
    --strict-mcp-config
    --mcp-config '{"mcpServers":{}}'
    --output-format json
    --no-session-persistence
    --disable-slash-commands
    --tools ""
  )

  # Report the auth source without ever logging the token value.
  local auth_mode="keychain (interactive login)"
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    auth_mode="CLAUDE_CODE_OAUTH_TOKEN (setup-token)"
  fi

  if [[ "$MODE" == "dry-run" ]]; then
    log "DRY-RUN Claude auth=${auth_mode}"
    log "DRY-RUN Claude: ${cmd[*]}"
    return 0
  fi

  require_bin "Claude" "$CLAUDE_BIN" || return 1
  log "Claude job started auth=${auth_mode}"
  run_with_timeout "$output_file" "${cmd[@]}"
  local exit_code=$?
  record_claude_usage "$exit_code" "$output_file"
  if (( exit_code != 0 )) \
    && grep -qiE '"api_error_status": ?401|Invalid authentication credentials|Failed to authenticate' "$output_file" 2>/dev/null; then
    if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
      log "ERROR: Claude authentication failed (401) while using CLAUDE_CODE_OAUTH_TOKEN: the token is invalid or expired. Re-mint it with 'claude setup-token' and update CLAUDE_CODE_OAUTH_TOKEN in ${ENV_FILE}. See README (Headless authentication)."
    else
      log "ERROR: Claude authentication failed (401): the unattended run is sharing the short-lived interactive Keychain login. Run 'claude setup-token' and set CLAUDE_CODE_OAUTH_TOKEN in ${ENV_FILE} so it authenticates on its own. See README (Headless authentication)."
    fi
  fi
  log "Claude job completed exit=${exit_code} $(summarize_output "$output_file") raw=${output_file}"
  return "$exit_code"
}

run_codex() {
  local output_file
  output_file="${RAW_LOG_DIR}/$(stamp_for_file)-codex.log"
  local cmd=(
    "$CODEX_BIN"
    exec
    --cd "$CODEX_WORK_DIR"
    --ephemeral
    --skip-git-repo-check
    --sandbox read-only
    --ignore-user-config
    --ignore-rules
    -c 'features.memories=false'
    -c 'features.multi_agent=false'
    -c 'features.goals=false'
    -c 'features.codex_hooks=false'
    -c 'features.child_agents_md=false'
    -c 'model_reasoning_effort="low"'
  )

  if [[ "$CODEX_MODEL" != "default" ]]; then
    cmd+=(--model "$CODEX_MODEL")
  fi

  cmd+=(
    --json
    "$CODEX_ACTIVATION_PROMPT"
  )

  if [[ "$MODE" == "dry-run" ]]; then
    log "DRY-RUN Codex: ${cmd[*]}"
    return 0
  fi

  require_bin "Codex" "$CODEX_BIN" || return 1
  if [[ ! -d "$CODEX_WORK_DIR" ]]; then
    log "ERROR: Codex work directory not found: $CODEX_WORK_DIR"
    return 1
  fi
  log "Codex job started"
  run_with_timeout "$output_file" "${cmd[@]}"
  local exit_code=$?
  record_codex_usage "$exit_code" "$output_file"
  log "Codex job completed exit=${exit_code} $(summarize_output "$output_file") raw=${output_file}"
  return "$exit_code"
}

run_check() {
  local status=0
  if [[ "$TOOL" == "all" || "$TOOL" == "claude" ]]; then
    if require_bin "Claude" "$CLAUDE_BIN"; then
      log "Claude binary: $CLAUDE_BIN ($("$CLAUDE_BIN" --version 2>&1 | tr '\n' ' '))"
    else
      status=1
    fi
  fi
  if [[ "$TOOL" == "all" || "$TOOL" == "codex" ]]; then
    if require_bin "Codex" "$CODEX_BIN"; then
      log "Codex binary: $CODEX_BIN ($("$CODEX_BIN" --version 2>&1 | tr '\n' ' '))"
      log "Codex model: $CODEX_MODEL"
      log "Codex work directory: $CODEX_WORK_DIR"
    else
      status=1
    fi
  fi
  if [[ -n "$JQ_BIN" && -x "$JQ_BIN" ]]; then
    log "jq binary: $JQ_BIN ($("$JQ_BIN" --version 2>&1 | tr '\n' ' '))"
  else
    log "WARNING: jq not found; usage.jsonl parsing will be disabled"
  fi
  if [[ -n "$NODE_BIN" && -x "$NODE_BIN" ]]; then
    log "node binary: $NODE_BIN ($("$NODE_BIN" --version 2>&1 | tr '\n' ' '))"
  else
    log "WARNING: node not found; Codex status snapshots will be disabled"
  fi
  if [[ "$CLAUDE_STATUS_SOURCE" == "cache" ]]; then
    if [[ -f "$CLAUDE_USAGE_CACHE_FILE" ]]; then
      log "Claude usage cache: $CLAUDE_USAGE_CACHE_FILE"
    else
      log "WARNING: Claude usage cache not found at $CLAUDE_USAGE_CACHE_FILE; quota snapshots will be skipped until the oh-my-claudecode plugin writes it"
    fi
  elif [[ -n "$OMC_BIN" && -x "$OMC_BIN" ]]; then
    log "omc binary: $OMC_BIN ($("$OMC_BIN" --version 2>&1 | tr '\n' ' '))"
  else
    log "WARNING: omc not found; CLAUDE_STATUS_SOURCE=omc Claude quota snapshots will be disabled"
  fi
  return "$status"
}

main() {
  cd "$ROOT_DIR" || return 1

  if [[ "$MODE" == "check" ]]; then
    run_check
    return $?
  fi

  if [[ "$MODE" == "status" ]]; then
    record_status_snapshots
    return $?
  fi

  if [[ "$MODE" != "dry-run" ]]; then
    maybe_reexec_with_caffeinate "$@"
  fi

  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another activation run is already active; skipping."
    return 0
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

  local status=0
  local sent_prompt=0
  local preflight_ran=0
  log "Activation run started run_id=${RUN_ID} mode=${MODE} tool=${TOOL} root=${ROOT_DIR}"

  if [[ "$MODE" != "dry-run" && "$ENABLE_QUOTA_PREFLIGHT" == "1" ]]; then
    log "Quota preflight started"
    record_status_snapshots || log "WARNING: one or more quota preflight snapshots failed"
    preflight_ran=1
  fi

  if [[ "$TOOL" == "all" || "$TOOL" == "claude" ]]; then
    if ! maybe_skip_for_quota "claude"; then
      sent_prompt=1
      run_claude || status=$?
    fi
  fi

  if [[ "$TOOL" == "all" || "$TOOL" == "codex" ]]; then
    if ! maybe_skip_for_quota "codex"; then
      sent_prompt=1
      run_codex || status=$?
    fi
  fi

  if [[ "$MODE" == "dry-run" ]]; then
    log "Status snapshots skipped in dry-run mode"
  elif [[ "$preflight_ran" == "1" && "$sent_prompt" == "0" ]]; then
    log "Post-run status snapshots skipped because quota preflight skipped all enabled prompts"
  elif [[ "$ENABLE_STATUS_SNAPSHOTS" == "1" ]]; then
    record_status_snapshots || log "WARNING: one or more status snapshots failed"
  else
    log "Status snapshots disabled by ENABLE_STATUS_SNAPSHOTS=${ENABLE_STATUS_SNAPSHOTS}"
  fi

  log "Activation run finished exit=${status}"
  return "$status"
}

main "$@"
