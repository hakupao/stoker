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
LEGACY_LABELS="${LEGACY_LABELS:-com.activation-timer.ai-window}"
LAUNCHCTL_BIN="${LAUNCHCTL_BIN:-launchctl}"
ACTIVATION_TOOL="${ACTIVATION_TOOL:-all}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-luna}"
ENABLE_STATUS_SNAPSHOTS="${ENABLE_STATUS_SNAPSHOTS:-1}"
ENABLE_QUOTA_PREFLIGHT="${ENABLE_QUOTA_PREFLIGHT:-1}"
QUOTA_PREFLIGHT_ON_UNKNOWN="${QUOTA_PREFLIGHT_ON_UNKNOWN:-allow}"
QUOTA_EXHAUSTED_THRESHOLD_PERCENT="${QUOTA_EXHAUSTED_THRESHOLD_PERCENT:-0}"
CODEX_ACTIVATE_ONLY_WHEN_IDLE="${CODEX_ACTIVATE_ONLY_WHEN_IDLE:-1}"
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
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
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

tool_enabled() {
  [[ "$ACTIVATION_TOOL" != "claude" && "$ACTIVATION_TOOL" != "codex" ]] || [[ "$ACTIVATION_TOOL" == "$1" ]]
}

# Mirrors load_tool_schedule in scripts/install-launchd.sh (keep behavior in
# sync): sets SCHED_TIMES (sorted unique HH:MM) and SCHED_DAYS (mon..sun order;
# empty = every day). Times fall back <TOOL>_SCHEDULE_TIMES -> SCHEDULE_TIMES ->
# default. Invalid values exit 2.
load_tool_schedule() {
  local tool="$1" upper times_var days_var raw_times raw_days source_name entries
  upper="$(printf '%s' "$tool" | tr '[:lower:]' '[:upper:]')"
  times_var="${upper}_SCHEDULE_TIMES"
  days_var="${upper}_SCHEDULE_DAYS"
  raw_times="${!times_var:-}"
  source_name="$times_var"
  if [[ -z "${raw_times//[[:space:]]/}" ]]; then
    raw_times="${SCHEDULE_TIMES:-}"
    source_name="SCHEDULE_TIMES"
  fi
  if [[ -z "${raw_times//[[:space:]]/}" ]]; then
    raw_times="07:00,12:00,17:00,22:00"
  fi

  local raw_time trimmed hour minute parsed_times=()
  IFS=',' read -r -a entries <<<"$raw_times"
  for raw_time in "${entries[@]}"; do
    trimmed="$(printf '%s' "$raw_time" | tr -d '[:space:]')"
    if ! [[ "$trimmed" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
      echo "${source_name} entries must be in HH:MM format" >&2
      exit 2
    fi
    hour="${trimmed%%:*}"
    minute="${trimmed##*:}"
    if (( 10#$hour < 0 || 10#$hour > 23 )); then
      echo "Hour must be 0-23 in ${source_name} entry: ${trimmed}" >&2
      exit 2
    fi
    if (( 10#$minute < 0 || 10#$minute > 59 )); then
      echo "Minute must be 0-59 in ${source_name} entry: ${trimmed}" >&2
      exit 2
    fi
    parsed_times+=("$(printf '%02d:%02d' "$((10#$hour))" "$((10#$minute))")")
  done
  if (( ${#parsed_times[@]} == 0 )); then
    echo "${source_name} must contain at least one time" >&2
    exit 2
  fi
  SCHED_TIMES=()
  while IFS= read -r trimmed; do
    SCHED_TIMES+=("$trimmed")
  done < <(printf '%s\n' "${parsed_times[@]}" | sort -u)

  raw_days="$(printf '%s' "${!days_var:-}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  local day seen=" " all_days=(mon tue wed thu fri sat sun)
  SCHED_DAYS=()
  if [[ -n "$raw_days" && "$raw_days" != "daily" ]]; then
    IFS=',' read -r -a entries <<<"$raw_days"
    for day in "${entries[@]}"; do
      [[ -z "$day" ]] && continue
      case "$day" in
        mon|tue|wed|thu|fri|sat|sun) seen="${seen}${day} " ;;
        *)
          echo "${days_var} entries must be mon,tue,wed,thu,fri,sat,sun or daily: ${day}" >&2
          exit 2
          ;;
      esac
    done
    for day in "${all_days[@]}"; do
      [[ "$seen" == *" ${day} "* ]] && SCHED_DAYS+=("$day")
    done
    # All seven days selected is just "every day".
    (( ${#SCHED_DAYS[@]} == 7 )) && SCHED_DAYS=()
  fi
  return 0
}

tool_schedule_json() {
  load_tool_schedule "$1"
  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  "$JQ_BIN" -n -c \
    --arg times "$(printf '%s\n' "${SCHED_TIMES[@]}")" \
    --arg days "$(printf '%s\n' "${SCHED_DAYS[@]+"${SCHED_DAYS[@]}"}")" '
      { times: ($times | split("\n") | map(select(length > 0))),
        days: ($days | split("\n") | map(select(length > 0))) }
    '
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
  local plist="$1" key="$2"
  if [[ ! -f "$plist" ]]; then
    return 1
  fi

  plutil -extract "$key" raw -o - "$plist" 2>/dev/null
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

# Probes one tool's agent into AGENT_* globals.
probe_agent() {
  local label="$1" plist output probe_status
  plist="${LAUNCH_AGENTS_DIR}/${label}.plist"
  AGENT_LOADED=false
  AGENT_STATE="not_loaded"
  AGENT_ERROR=""
  AGENT_PROGRAM=""
  AGENT_WORKING_DIRECTORY=""
  AGENT_MATCHES_ROOT=false
  AGENT_MISMATCH=""

  if [[ "${STOKER_SKIP_LAUNCHCTL:-0}" == "1" ]]; then
    AGENT_STATE="skipped"
    return 0
  fi

  output="$("$LAUNCHCTL_BIN" print "gui/${UID}/${label}" 2>&1)" && probe_status=0 || probe_status=$?
  if [[ "$probe_status" != "0" ]]; then
    AGENT_ERROR="$(printf '%s' "$output" | tr '\n' ' ' | cut -c 1-240)"
    return 0
  fi

  AGENT_LOADED=true
  AGENT_STATE="$(printf '%s\n' "$output" | awk -F'= ' '/state = / {print $2; exit}')"
  [[ -z "$AGENT_STATE" ]] && AGENT_STATE="unknown"
  AGENT_PROGRAM="$(plist_value "$plist" ProgramArguments.1 || true)"
  AGENT_WORKING_DIRECTORY="$(plist_value "$plist" WorkingDirectory || true)"
  if [[ -z "$AGENT_PROGRAM" ]]; then
    AGENT_PROGRAM="$(printf '%s\n' "$output" | loaded_program_from_launchctl)"
  fi
  if [[ -z "$AGENT_WORKING_DIRECTORY" ]]; then
    AGENT_WORKING_DIRECTORY="$(printf '%s\n' "$output" | awk -F'= ' '/working directory = / {print $2; exit}')"
  fi
  if [[ "$AGENT_PROGRAM" == "$EXPECTED_PROGRAM" && "$AGENT_WORKING_DIRECTORY" == "$ROOT_DIR" ]]; then
    AGENT_MATCHES_ROOT=true
  else
    AGENT_MISMATCH="Loaded LaunchAgent ${label} points to ${AGENT_WORKING_DIRECTORY:-unknown root}; current root is ${ROOT_DIR}"
  fi
  return 0
}

# Top-level launchctl fields describe the first enabled tool's agent; installed
# requires every enabled agent loaded from this root and nothing stray (a loaded
# agent of a disabled tool, or a legacy agent of this root, both fixed by a
# reinstall); mismatch is the first enabled or legacy agent that points elsewhere.
installed=true
running=false
launchctl_state="unavailable"
launchctl_error=""
launchctl_program=""
launchctl_working_directory=""
launchctl_matches_root=false
launchctl_mismatch=""
first_enabled=1
agents='{}'

for tool in claude codex; do
  label="${LABEL}.${tool}"
  probe_agent "$label"
  stray=false
  if ! tool_enabled "$tool" && [[ "$AGENT_LOADED" == "true" ]]; then
    stray=true
    installed=false
    # A disabled tool's agent from another root is someone else's schedule.
    [[ -z "$launchctl_mismatch" && -n "$AGENT_MISMATCH" ]] && launchctl_mismatch="$AGENT_MISMATCH"
  fi
  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  agents="$("$JQ_BIN" -c --arg tool "$tool" --arg label "$label" --arg state "$AGENT_STATE" \
    --argjson loaded "$AGENT_LOADED" --argjson stray "$stray" \
    '.[$tool] = {label: $label, loaded: $loaded, state: $state, stray: $stray}' <<<"$agents")"
  tool_enabled "$tool" || continue

  if (( first_enabled == 1 )); then
    first_enabled=0
    launchctl_state="$AGENT_STATE"
    launchctl_error="$AGENT_ERROR"
    launchctl_program="$AGENT_PROGRAM"
    launchctl_working_directory="$AGENT_WORKING_DIRECTORY"
    launchctl_matches_root="$AGENT_MATCHES_ROOT"
  fi
  [[ "$AGENT_MATCHES_ROOT" == "true" ]] || installed=false
  [[ -z "$launchctl_mismatch" && -n "$AGENT_MISMATCH" ]] && launchctl_mismatch="$AGENT_MISMATCH"
  [[ "$AGENT_STATE" == "running" ]] && running=true
done
(( first_enabled == 1 )) && installed=false

# The pre-per-tool single agent (${LABEL}) and renamed-project agents: only loaded
# ones are listed. One from another root is a schedule installed elsewhere
# (mismatch); one from this root still runs here and needs a reinstall.
legacy='[]'
needs_migration=false
for label in "$LABEL" $LEGACY_LABELS; do
  [[ "$label" == "${LABEL}.claude" || "$label" == "${LABEL}.codex" ]] && continue
  probe_agent "$label"
  [[ "$AGENT_LOADED" == "true" ]] || continue
  # shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
  legacy="$("$JQ_BIN" -c --arg label "$label" --argjson matches "$AGENT_MATCHES_ROOT" \
    --arg program "$AGENT_PROGRAM" --arg wd "$AGENT_WORKING_DIRECTORY" \
    '. + [{label: $label, loaded: true, matches_root: $matches,
           program: (if $program == "" then null else $program end),
           working_directory: (if $wd == "" then null else $wd end)}]' <<<"$legacy")"
  if [[ "$AGENT_MATCHES_ROOT" == "true" ]]; then
    needs_migration=true
    installed=false
  elif [[ -z "$launchctl_mismatch" ]]; then
    launchctl_mismatch="$AGENT_MISMATCH"
  fi
done

claude_schedule="$(tool_schedule_json claude)"
codex_schedule="$(tool_schedule_json codex)"
# shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
schedule="$("$JQ_BIN" -n -c \
  --argjson claude "$claude_schedule" \
  --argjson codex "$codex_schedule" \
  --argjson claude_on "$(tool_enabled claude && printf true || printf false)" \
  --argjson codex_on "$(tool_enabled codex && printf true || printf false)" '
    {
      times: ((if $claude_on then $claude.times else [] end)
              + (if $codex_on then $codex.times else [] end) | unique),
      claude: $claude,
      codex: $codex
    }
  ')"
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
        subscription_type: ($c.subscriptionType // null),
        credits: ($c.credits // null),
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
        },
        scoped_weekly: (
          if ($d.scopedWeeklyBuckets | type) == "array" then
            $d.scopedWeeklyBuckets
            | map(select(type == "object")
                | (if (.percent | type) == "number" then .percent else null end) as $pct
                | {
                    id: ((.id // .label // "unknown") | tostring),
                    label: ((.label // .id // "unknown") | tostring),
                    used_percent: $pct,
                    remaining_percent: (if $pct == null then null else (100 - $pct) end),
                    resets_at: (.resetsAt // null),
                    is_active: (if (.isActive | type) == "boolean" then .isActive else null end)
                  })
          else [] end
        )
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
      | (if (.scoped_weekly | type) == "array" then .scoped_weekly |= map(normalize_window) else . end)
    else
      .
    end
  )
' <<<"$quota" 2>/dev/null || true)"
[[ -n "$normalized" ]] && quota="$normalized"

last_usage="$(read_last_jsonl "$USAGE_LOG")"
enable_status_snapshots="$(bool_from_1 "$ENABLE_STATUS_SNAPSHOTS")"
enable_quota_preflight="$(bool_from_1 "$ENABLE_QUOTA_PREFLIGHT")"
codex_activate_only_when_idle="$(bool_from_1 "$CODEX_ACTIVATE_ONLY_WHEN_IDLE")"

# shellcheck disable=SC2016 # jq variables are intentionally evaluated by jq.
"$JQ_BIN" -n -c \
  --arg root "$ROOT_DIR" \
  --arg label "$LABEL" \
  --arg activation_tool "$ACTIVATION_TOOL" \
  --arg codex_model "$CODEX_MODEL" \
  --arg quota_preflight_on_unknown "$QUOTA_PREFLIGHT_ON_UNKNOWN" \
  --argjson quota_exhausted_threshold_percent "$QUOTA_EXHAUSTED_THRESHOLD_PERCENT" \
  --argjson codex_activate_only_when_idle "$codex_activate_only_when_idle" \
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
  --argjson agents "$agents" \
  --argjson legacy "$legacy" \
  --argjson needs_migration "$needs_migration" \
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
        mismatch: (if $launchctl_mismatch == "" then null else $launchctl_mismatch end),
        agents: $agents,
        legacy: $legacy,
        needs_migration: $needs_migration
      },
      schedule: $schedule,
      config: {
        activation_tool: $activation_tool,
        codex_model: $codex_model,
        enable_status_snapshots: $enable_status_snapshots,
        enable_quota_preflight: $enable_quota_preflight,
        quota_preflight_on_unknown: $quota_preflight_on_unknown,
        quota_exhausted_threshold_percent: $quota_exhausted_threshold_percent,
        codex_activate_only_when_idle: $codex_activate_only_when_idle
      },
      keep_awake: {
        mode: $keep_awake_mode,
        seconds: $keep_awake_seconds
      },
      quota: $quota,
      last_usage: $last_usage
    }
  '
