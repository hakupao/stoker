#!/usr/bin/env bash
set -eo pipefail

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

set -u

LABEL="${LABEL:-com.stoker.ai-window}"
# Boot out agents from the pre-Stoker rename (formerly "Activation Timer") so an
# upgrade in place cleanly replaces the old LaunchAgent instead of leaving it loaded.
# The pre-per-tool single agent (plain ${LABEL}) is always cleaned up as well.
LEGACY_LABELS="${LEGACY_LABELS:-com.activation-timer.ai-window}"
LAUNCHD_DIR="${ROOT_DIR}/launchd"
LOG_DIR="${ROOT_DIR}/logs"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PATH_VALUE="${PATH_VALUE:-${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
ACTIVATION_TOOL="${ACTIVATION_TOOL:-all}"
LAUNCHCTL_BIN="${LAUNCHCTL_BIN:-launchctl}"
TOOLS=(claude codex)

usage() {
  cat <<'USAGE'
Usage: install-launchd.sh install|uninstall|status|run-now|print-plist [claude|codex]

install     Generate, validate, and load one LaunchAgent per enabled tool.
uninstall   Unload and remove the LaunchAgents.
status      Print launchd status for each agent.
run-now     Trigger each enabled agent immediately.
print-plist Regenerate and print the plists without installing
            (with claude|codex: print only that tool's plist).

Each tool gets its own agent (${LABEL}.claude / ${LABEL}.codex) running
`activate-ai-window.sh --once --scheduled --tool <tool>`; ACTIVATION_TOOL picks which
are installed. Re-run install after changing *_SCHEDULE_* or ACTIVATION_TOOL.

install also removes the old single ${LABEL} agent and LEGACY_LABELS, except
ones whose plist points at another Stoker root (warned and kept unless
STOKER_FORCE_MIGRATE=1).

Configuration can be set in .env or environment variables:
  LABEL=com.stoker.ai-window
  ACTIVATION_TOOL=all                      # all|claude|codex
  CLAUDE_SCHEDULE_TIMES=07:00,12:00,17:00,22:00
  CODEX_SCHEDULE_TIMES=07:00
  CLAUDE_SCHEDULE_DAYS=                    # empty/daily = every day, else mon,tue,...,sun
  CODEX_SCHEDULE_DAYS=mon,thu
  SCHEDULE_TIMES=07:00,12:00,17:00,22:00   # fallback when a tool's times are unset
  LEGACY_LABELS="old.label.to.remove another.old.label"
USAGE
}

validate_activation_tool() {
  case "$ACTIVATION_TOOL" in
    all|claude|codex) ;;
    *)
      echo "ACTIVATION_TOOL must be all, claude, or codex" >&2
      exit 2
      ;;
  esac
}

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

tool_enabled() {
  [[ "$ACTIVATION_TOOL" == "all" || "$ACTIVATION_TOOL" == "$1" ]]
}

enabled_tools() {
  local tool
  for tool in "${TOOLS[@]}"; do
    tool_enabled "$tool" && printf '%s\n' "$tool"
  done
  return 0
}

tool_label() {
  printf '%s.%s' "$LABEL" "$1"
}

tool_display_name() {
  case "$1" in
    claude) printf 'Claude' ;;
    codex) printf 'Codex' ;;
  esac
}

# Parses a tool's schedule into globals (no subshell, so validation errors exit
# the script): SCHED_TIMES (sorted unique HH:MM), SCHED_DAYS (mon..sun order;
# empty = every day), SCHED_WEEKDAYS (launchd ints, 1=Mon..6=Sat, 0=Sun).
# Times fall back <TOOL>_SCHEDULE_TIMES -> SCHEDULE_TIMES -> default.
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
  SCHED_WEEKDAYS=()
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
    local index
    for index in "${!all_days[@]}"; do
      if [[ "$seen" == *" ${all_days[$index]} "* ]]; then
        SCHED_DAYS+=("${all_days[$index]}")
        SCHED_WEEKDAYS+=("$(( (index + 1) % 7 ))")
      fi
    done
    # All seven days selected is just "every day".
    if (( ${#SCHED_DAYS[@]} == 7 )); then
      SCHED_DAYS=()
      SCHED_WEEKDAYS=()
    fi
  fi
}

render_schedule_intervals() {
  local time hour minute weekday
  for time in "${SCHED_TIMES[@]}"; do
    hour="$((10#${time%%:*}))"
    minute="$((10#${time##*:}))"
    if (( ${#SCHED_WEEKDAYS[@]} == 0 )); then
      cat <<PLIST
    <dict>
      <key>Hour</key>
      <integer>${hour}</integer>
      <key>Minute</key>
      <integer>${minute}</integer>
    </dict>
PLIST
      continue
    fi
    for weekday in "${SCHED_WEEKDAYS[@]}"; do
      cat <<PLIST
    <dict>
      <key>Weekday</key>
      <integer>${weekday}</integer>
      <key>Hour</key>
      <integer>${hour}</integer>
      <key>Minute</key>
      <integer>${minute}</integer>
    </dict>
PLIST
    done
  done
}

# Requires load_tool_schedule for the same tool first.
schedule_description() {
  local times days
  times="$(printf '%s, ' "${SCHED_TIMES[@]}")"
  times="${times%, }"
  if (( ${#SCHED_DAYS[@]} == 0 )); then
    days="daily"
  else
    days="$(printf '%s, ' "${SCHED_DAYS[@]}")"
    days="${days%, }"
  fi
  printf '%s: %s (%s)' "$(tool_display_name "$1")" "$times" "$days"
}

repo_plist() {
  printf '%s/%s.plist' "$LAUNCHD_DIR" "$(tool_label "$1")"
}

installed_plist() {
  printf '%s/%s.plist' "$LAUNCH_AGENTS_DIR" "$1"
}

# Requires load_tool_schedule for the same tool first.
generate_plist() {
  local tool="$1" label plist_repo
  label="$(tool_label "$tool")"
  plist_repo="$(repo_plist "$tool")"
  mkdir -p "$LAUNCHD_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"

  local root_xml home_xml path_xml out_xml err_xml
  root_xml="$(printf '%s' "$ROOT_DIR" | xml_escape)"
  home_xml="$(printf '%s' "$HOME" | xml_escape)"
  path_xml="$(printf '%s' "$PATH_VALUE" | xml_escape)"
  out_xml="$(printf '%s' "${LOG_DIR}/launchd.out.log" | xml_escape)"
  err_xml="$(printf '%s' "${LOG_DIR}/launchd.err.log" | xml_escape)"

  cat >"$plist_repo" <<PLIST
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
    <string>${root_xml}/bin/activate-ai-window.sh</string>
    <string>--once</string>
    <string>--scheduled</string>
    <string>--tool</string>
    <string>${tool}</string>
  </array>

  <key>WorkingDirectory</key>
  <string>${root_xml}</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${home_xml}</string>
    <key>PATH</key>
    <string>${path_xml}</string>
  </dict>

  <key>StartCalendarInterval</key>
  <array>
$(render_schedule_intervals)
  </array>

  <key>StandardOutPath</key>
  <string>${out_xml}</string>
  <key>StandardErrorPath</key>
  <string>${err_xml}</string>

  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
PLIST

  plutil -lint "$plist_repo" >/dev/null
}

bootout_label() {
  local label="$1"
  "$LAUNCHCTL_BIN" bootout "gui/${UID}/${label}" >/dev/null 2>&1 || true
  "$LAUNCHCTL_BIN" bootout "gui/${UID}" "$(installed_plist "$label")" >/dev/null 2>&1 || true
}

agent_present() {
  [[ -f "$(installed_plist "$1")" ]] || "$LAUNCHCTL_BIN" print "gui/${UID}/$1" >/dev/null 2>&1
}

remove_agent() {
  bootout_label "$1"
  rm -f "$(installed_plist "$1")"
}

# Succeeds (and warns) when an installed agent's plist points at another Stoker
# root: that agent is someone else's schedule. An unreadable plist or
# STOKER_FORCE_MIGRATE=1 counts as ours.
agent_is_foreign() {
  local label="$1" plist program working_dir
  [[ "${STOKER_FORCE_MIGRATE:-0}" == "1" ]] && return 1
  plist="$(installed_plist "$label")"
  program="$(plutil -extract ProgramArguments.1 raw -o - "$plist" 2>/dev/null || true)"
  working_dir="$(plutil -extract WorkingDirectory raw -o - "$plist" 2>/dev/null || true)"
  [[ -z "$program$working_dir" ]] && return 1
  [[ "$program" == "${ROOT_DIR}/bin/activate-ai-window.sh" && "$working_dir" == "$ROOT_DIR" ]] && return 1
  echo "WARNING: kept agent ${label}: it points to ${working_dir:-$program}, not ${ROOT_DIR}. Set STOKER_FORCE_MIGRATE=1 to replace it anyway." >&2
  return 0
}

# Legacy agents are removed only when they belong to this root.
remove_legacy_agents() {
  local legacy tool skip
  for legacy in "$LABEL" $LEGACY_LABELS; do
    skip=0
    for tool in "${TOOLS[@]}"; do
      [[ "$legacy" == "$(tool_label "$tool")" ]] && skip=1
    done
    (( skip == 1 )) && continue
    agent_present "$legacy" || continue
    agent_is_foreign "$legacy" && continue
    remove_agent "$legacy"
    REMOVED_AGENTS+=("$legacy")
  done
  return 0
}

install_agent() {
  validate_activation_tool
  local tool label descriptions=() installed=() foreign=()
  # Validate every enabled tool's schedule before touching launchd.
  while IFS= read -r tool; do
    load_tool_schedule "$tool"
    generate_plist "$tool"
    descriptions+=("$(schedule_description "$tool")")
  done < <(enabled_tools)

  REMOVED_AGENTS=()
  remove_legacy_agents
  # The pre-per-tool generated plist is no longer used.
  rm -f "${LAUNCHD_DIR}/${LABEL}.plist"
  for tool in "${TOOLS[@]}"; do
    label="$(tool_label "$tool")"
    if agent_present "$label" && agent_is_foreign "$label"; then
      foreign+=("$label")
      continue
    fi
    bootout_label "$label"
    if tool_enabled "$tool"; then
      cp "$(repo_plist "$tool")" "$(installed_plist "$label")"
      if ! "$LAUNCHCTL_BIN" bootstrap "gui/${UID}" "$(installed_plist "$label")"; then
        rm -f "$(installed_plist "$label")"
        echo "ERROR: failed to load ${label}." >&2
        if (( ${#installed[@]} > 0 )); then
          echo "Installed before the failure: ${installed[*]}" >&2
        else
          echo "No agents were installed." >&2
        fi
        exit 1
      fi
      "$LAUNCHCTL_BIN" enable "gui/${UID}/${label}" >/dev/null 2>&1 || true
      installed+=("$label")
      echo "Installed ${label}"
    else
      rm -f "$(installed_plist "$label")"
    fi
  done
  if (( ${#REMOVED_AGENTS[@]} > 0 )); then
    echo "Removed legacy agents: ${REMOVED_AGENTS[*]}"
  fi
  printf 'Schedule (local time):\n'
  printf '  %s\n' "${descriptions[@]}"
  echo "Logs: ${LOG_DIR}/activation.log"
  if (( ${#foreign[@]} > 0 )); then
    echo "ERROR: skipped ${foreign[*]} (installed from another Stoker root)." >&2
    exit 1
  fi
}

uninstall_agent() {
  local tool label
  REMOVED_AGENTS=()
  for tool in "${TOOLS[@]}"; do
    label="$(tool_label "$tool")"
    agent_present "$label" || continue
    remove_agent "$label"
    REMOVED_AGENTS+=("$label")
  done
  remove_legacy_agents
  if (( ${#REMOVED_AGENTS[@]} == 0 )); then
    echo "No Stoker LaunchAgents were installed."
  else
    echo "Uninstalled ${REMOVED_AGENTS[*]}"
  fi
}

status_agent() {
  local tool label status=0
  for tool in "${TOOLS[@]}"; do
    label="$(tool_label "$tool")"
    if ! "$LAUNCHCTL_BIN" print "gui/${UID}/${label}"; then
      echo "${label} is not currently loaded."
      tool_enabled "$tool" && status=1
    fi
  done
  return "$status"
}

run_now() {
  validate_activation_tool
  local tool label status=0
  while IFS= read -r tool; do
    label="$(tool_label "$tool")"
    if "$LAUNCHCTL_BIN" kickstart -k "gui/${UID}/${label}"; then
      echo "Triggered ${label}."
    else
      echo "Failed to trigger ${label}; is it installed?" >&2
      status=1
    fi
  done < <(enabled_tools)
  echo "Check ${LOG_DIR}/activation.log"
  return "$status"
}

print_plists() {
  validate_activation_tool
  local tool="${1:-}"
  if [[ -n "$tool" ]]; then
    case "$tool" in
      claude|codex) ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
    load_tool_schedule "$tool"
    generate_plist "$tool"
    cat "$(repo_plist "$tool")"
    return
  fi
  while IFS= read -r tool; do
    load_tool_schedule "$tool"
    generate_plist "$tool"
    echo "==> $(repo_plist "$tool") <=="
    cat "$(repo_plist "$tool")"
  done < <(enabled_tools)
}

cmd="${1:-}"
case "$cmd" in
  install)
    install_agent
    ;;
  uninstall)
    uninstall_agent
    ;;
  status)
    status_agent
    ;;
  run-now)
    run_now
    ;;
  print-plist)
    print_plists "${2:-}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
