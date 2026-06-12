#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${STOKER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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

LABEL="${LABEL:-com.stoker.ai-window}"
SCHEDULE_TIMES="${SCHEDULE_TIMES:-07:00,12:00,17:00,22:00}"
ACTIVATION_TOOL="${ACTIVATION_TOOL:-all}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.4-mini}"
ENABLE_STATUS_SNAPSHOTS="${ENABLE_STATUS_SNAPSHOTS:-1}"
ENABLE_QUOTA_PREFLIGHT="${ENABLE_QUOTA_PREFLIGHT:-1}"
QUOTA_PREFLIGHT_ON_UNKNOWN="${QUOTA_PREFLIGHT_ON_UNKNOWN:-allow}"
QUOTA_EXHAUSTED_THRESHOLD_PERCENT="${QUOTA_EXHAUSTED_THRESHOLD_PERCENT:-0}"
KEEP_AWAKE_MODE="${KEEP_AWAKE_MODE:-off}"
KEEP_AWAKE_SECONDS="${KEEP_AWAKE_SECONDS:-900}"
JQ_BIN="${JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
  _bundled_jq="${ROOT_DIR}/bin/jq"
  [[ -x "$_bundled_jq" ]] && JQ_BIN="$_bundled_jq"
  unset _bundled_jq
fi
CLAUDE_USAGE_CACHE_FILE="${CLAUDE_USAGE_CACHE_FILE:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/plugins/oh-my-claudecode/.usage-cache-anthropic.json}"

LOG_DIR="${ROOT_DIR}/logs"
USAGE_LOG="${LOG_DIR}/usage.jsonl"
STATUS_LOG="${LOG_DIR}/status.jsonl"
PLIST_INSTALLED="${HOME}/Library/LaunchAgents/${LABEL}.plist"
EXPECTED_PROGRAM="${ROOT_DIR}/bin/activate-ai-window.sh"

usage() {
  cat <<'USAGE'
Usage: activation-state.sh --json

Prints a JSON snapshot for the menu bar app and other integrations.
USAGE
}

if [[ "${1:-}" != "--json" ]]; then
  usage >&2
  exit 2
fi

if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
  echo "jq is required to render activation state JSON" >&2
  exit 1
fi

bool_from_1() {
  if [[ "${1:-}" == "1" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

schedule_json() {
  local raw_time trimmed
  IFS=',' read -r -a times <<<"$SCHEDULE_TIMES"
  for raw_time in "${times[@]}"; do
    trimmed="$(printf '%s' "$raw_time" | tr -d '[:space:]')"
    if ! [[ "$trimmed" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
      echo "SCHEDULE_TIMES entries must be in HH:MM format" >&2
      exit 2
    fi
    local hour="${trimmed%%:*}" minute="${trimmed##*:}"
    if (( 10#$hour < 0 || 10#$hour > 23 )); then
      echo "Hour must be 0-23 in SCHEDULE_TIMES entry: ${trimmed}" >&2
      exit 2
    fi
    if (( 10#$minute < 0 || 10#$minute > 59 )); then
      echo "Minute must be 0-59 in SCHEDULE_TIMES entry: ${trimmed}" >&2
      exit 2
    fi
    printf '%02d:%02d\n' "$((10#$hour))" "$((10#$minute))"
  done | "$JQ_BIN" -R -s -c 'split("\n") | map(select(length > 0))'
}

read_latest_by_tool() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf '{}'
    return
  fi

  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  "$JQ_BIN" -s -c '
    reduce .[] as $row ({};
      if (($row.tool // null) != null) then
        .[$row.tool] = $row
      else
        .
      end
    )
  ' "$file" 2>/dev/null || printf '{}'
}

read_last_jsonl() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf 'null'
    return
  fi

  "$JQ_BIN" -s -c 'last // null' "$file" 2>/dev/null || printf 'null'
}

plist_value() {
  local key="$1"
  if [[ ! -f "$PLIST_INSTALLED" ]]; then
    return 1
  fi

  plutil -extract "$key" raw -o - "$PLIST_INSTALLED" 2>/dev/null
}

loaded_program_from_launchctl() {
  awk '
    /^[[:space:]]*arguments = \{/ {
      in_args = 1
      arg_index = 0
      next
    }
    in_args && /^[[:space:]]*\}/ {
      in_args = 0
      next
    }
    in_args {
      arg_index += 1
      if (arg_index == 2) {
        sub(/^[[:space:]]+/, "")
        print
        exit
      }
    }
  '
}

installed=false
running=false
launchctl_state="unavailable"
launchctl_error=""
launchctl_program=""
launchctl_working_directory=""
launchctl_matches_root=false
launchctl_mismatch=""

if [[ "${STOKER_SKIP_LAUNCHCTL:-0}" == "1" ]]; then
  launchctl_state="skipped"
else
  launchctl_output="$(launchctl print "gui/${UID}/${LABEL}" 2>&1)" && launchctl_status=0 || launchctl_status=$?
  if [[ "$launchctl_status" == "0" ]]; then
    launchctl_state="$(printf '%s\n' "$launchctl_output" | awk -F'= ' '/state = / {print $2; exit}')"
    [[ -z "$launchctl_state" ]] && launchctl_state="unknown"
    launchctl_program="$(plist_value ProgramArguments.1 || true)"
    launchctl_working_directory="$(plist_value WorkingDirectory || true)"
    if [[ -z "$launchctl_program" ]]; then
      launchctl_program="$(printf '%s\n' "$launchctl_output" | loaded_program_from_launchctl)"
    fi
    if [[ -z "$launchctl_working_directory" ]]; then
      launchctl_working_directory="$(printf '%s\n' "$launchctl_output" | awk -F'= ' '/working directory = / {print $2; exit}')"
    fi
    if [[ "$launchctl_program" == "$EXPECTED_PROGRAM" && "$launchctl_working_directory" == "$ROOT_DIR" ]]; then
      installed=true
      launchctl_matches_root=true
    else
      launchctl_mismatch="Loaded LaunchAgent points to ${launchctl_working_directory:-unknown root}; current root is ${ROOT_DIR}"
    fi
    if [[ "$launchctl_state" == "running" ]]; then
      running=true
    fi
  else
    launchctl_state="not_loaded"
    launchctl_error="$(printf '%s' "$launchctl_output" | tr '\n' ' ' | cut -c 1-240)"
  fi
fi

schedule="$(schedule_json)"
quota="$(read_latest_by_tool "$STATUS_LOG")"

# ── Claude quota freshness ────────────────────────────────────────────────────
# Snapshot rows freeze at the last scheduled run, and a cache-sourced snapshot
# may itself carry much older data. Whenever the live omc usage cache is newer
# than the recorded data, serve the Claude quota from it directly (no network,
# no credentials); otherwise keep the snapshot row but restamp `timestamp` with
# the time the DATA was captured, so the app's "Updated" line never overstates
# freshness. All failures fall through to the unmodified snapshot.
claude_data_ms="$("$JQ_BIN" -r '.claude.cache_timestamp_ms // 0' <<<"$quota" 2>/dev/null || printf '0')"
[[ "$claude_data_ms" =~ ^[0-9]+$ ]] || claude_data_ms=0
live_ms=0
if [[ -f "$CLAUDE_USAGE_CACHE_FILE" ]]; then
  live_ms="$("$JQ_BIN" -r 'if (.error // false) then 0 else (.timestamp // 0) end' "$CLAUDE_USAGE_CACHE_FILE" 2>/dev/null || printf '0')"
fi
[[ "$live_ms" =~ ^[0-9]+$ ]] || live_ms=0

if (( live_ms > claude_data_ms )); then
  live_stamp="$(date -r "$((live_ms / 1000))" '+%Y-%m-%d %H:%M:%S %Z')"
  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  refreshed="$("$JQ_BIN" -c --arg ts "$live_stamp" --slurpfile cache "$CLAUDE_USAGE_CACHE_FILE" '
    ($cache[0]) as $c
    | ($c.data // {}) as $d
    | .claude = {
        timestamp: $ts,
        tool: "claude",
        ok: true,
        status_source: "live-cache",
        source: ($c.source // null),
        subscription_type: null,
        cache_timestamp_ms: ($c.timestamp // null),
        last_success_at_ms: ($c.lastSuccessAt // null),
        cache_age_seconds: (if $c.timestamp == null then null else ((now - ($c.timestamp / 1000)) | round) end),
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
        }
      }
  ' <<<"$quota" 2>/dev/null || true)"
  [[ -n "$refreshed" ]] && quota="$refreshed"
elif (( claude_data_ms > 0 )); then
  data_stamp="$(date -r "$((claude_data_ms / 1000))" '+%Y-%m-%d %H:%M:%S %Z')"
  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  restamped="$("$JQ_BIN" -c --arg ts "$data_stamp" '.claude.timestamp = $ts' <<<"$quota" 2>/dev/null || true)"
  [[ -n "$restamped" ]] && quota="$restamped"
fi

# A window whose resets_at is already in the past has rolled over since the data
# was captured: its percentages are no longer true, so blank them (the app then
# shows "quota unknown") instead of presenting stale numbers as current.
# shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
normalized="$("$JQ_BIN" -c '
  def normalize_window:
    if (. // null) == null then .
    else
      (.resets_at // null) as $r
      | ((try ($r | tostring | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch null)) as $t
      | if ($t != null and $t < now) then
          . + {used_percent: null, remaining_percent: null, reset_passed: true}
        else
          .
        end
    end;
  map_values(
    if type == "object" then
      (if has("five_hour") then .five_hour |= normalize_window else . end)
      | (if has("weekly") then .weekly |= normalize_window else . end)
      | (if has("sonnet_weekly") then .sonnet_weekly |= normalize_window else . end)
    else
      .
    end
  )
' <<<"$quota" 2>/dev/null || true)"
[[ -n "$normalized" ]] && quota="$normalized"

last_usage="$(read_last_jsonl "$USAGE_LOG")"
enable_status_snapshots="$(bool_from_1 "$ENABLE_STATUS_SNAPSHOTS")"
enable_quota_preflight="$(bool_from_1 "$ENABLE_QUOTA_PREFLIGHT")"

# shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
"$JQ_BIN" -n -c \
  --arg root "$ROOT_DIR" \
  --arg label "$LABEL" \
  --arg activation_tool "$ACTIVATION_TOOL" \
  --arg codex_model "$CODEX_MODEL" \
  --arg quota_preflight_on_unknown "$QUOTA_PREFLIGHT_ON_UNKNOWN" \
  --argjson quota_exhausted_threshold_percent "$QUOTA_EXHAUSTED_THRESHOLD_PERCENT" \
  --arg keep_awake_mode "$KEEP_AWAKE_MODE" \
  --argjson keep_awake_seconds "$KEEP_AWAKE_SECONDS" \
  --arg launchctl_state "$launchctl_state" \
  --arg launchctl_error "$launchctl_error" \
  --arg launchctl_program "$launchctl_program" \
  --arg launchctl_working_directory "$launchctl_working_directory" \
  --arg launchctl_mismatch "$launchctl_mismatch" \
  --argjson installed "$installed" \
  --argjson running "$running" \
  --argjson launchctl_matches_root "$launchctl_matches_root" \
  --argjson schedule "$schedule" \
  --argjson quota "$quota" \
  --argjson last_usage "$last_usage" \
  --argjson enable_status_snapshots "$enable_status_snapshots" \
  --argjson enable_quota_preflight "$enable_quota_preflight" '
    {
      root: $root,
      label: $label,
      installed: $installed,
      running: $running,
      launchctl: {
        state: $launchctl_state,
        error: (if $launchctl_error == "" then null else $launchctl_error end),
        program: (if $launchctl_program == "" then null else $launchctl_program end),
        working_directory: (if $launchctl_working_directory == "" then null else $launchctl_working_directory end),
        matches_root: $launchctl_matches_root,
        mismatch: (if $launchctl_mismatch == "" then null else $launchctl_mismatch end)
      },
      schedule: {
        times: $schedule
      },
      config: {
        activation_tool: $activation_tool,
        codex_model: $codex_model,
        enable_status_snapshots: $enable_status_snapshots,
        enable_quota_preflight: $enable_quota_preflight,
        quota_preflight_on_unknown: $quota_preflight_on_unknown,
        quota_exhausted_threshold_percent: $quota_exhausted_threshold_percent
      },
      keep_awake: {
        mode: $keep_awake_mode,
        seconds: $keep_awake_seconds
      },
      quota: $quota,
      last_usage: $last_usage
    }
  '
