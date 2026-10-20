#!/usr/bin/env bash
set -euo pipefail

# Verifies install/uninstall in scripts/install-launchd.sh against a fake
# launchctl (LAUNCHCTL_BIN) with a temp HOME and STOKER_ROOT, so the real
# ~/Library/LaunchAgents and gui/<uid> domain are never touched:
#   A) install loads enabled tools only, removes a stray disabled-tool agent, the
#      old single-label agent of this root, and the old repo plist
#   B) a legacy agent from another root is kept with a warning, unless
#      STOKER_FORCE_MIGRATE=1
#   C) a bootstrap failure removes that agent's plist, names what was installed,
#      and exits non-zero
#   D) uninstall ignores ACTIVATION_TOOL, removes both tools + legacy, and only
#      reports agents that existed
#   E) a per-tool agent from another root is kept (warning, non-zero exit) while
#      the other tool still installs, unless STOKER_FORCE_MIGRATE=1
#   F) uninstall keeps a per-tool agent from another root (warning, non-zero
#      exit) while removing this root's, unless STOKER_FORCE_MIGRATE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ROOT="$TMP_DIR/root"
HOME_DIR="$TMP_DIR/home"
AGENTS="$HOME_DIR/Library/LaunchAgents"
LOADED="$TMP_DIR/loaded"
OTHER_ROOT="$TMP_DIR/other-root"
mkdir -p "$ROOT/launchd" "$AGENTS" "$LOADED" "$TMP_DIR/bin"
SCRIPT="$ROOT_DIR/scripts/install-launchd.sh"
BASE="com.example.stoker.test"

# Fake launchctl: a label is "loaded" while $LOADED/<label> exists.
cat >"$TMP_DIR/bin/launchctl" <<'SH'
#!/usr/bin/env bash
case "$1" in
  print)
    [[ -e "$FAKE_LOADED/${2##*/}" ]] || exit 113
    echo "state = not running"
    ;;
  bootstrap)
    label="$(basename "$3" .plist)"
    [[ "$label" == "${FAKE_BOOTSTRAP_FAIL:-}" ]] && { echo "Bootstrap failed: 5" >&2; exit 5; }
    touch "$FAKE_LOADED/$label"
    ;;
  bootout)
    if [[ $# -ge 3 ]]; then rm -f "$FAKE_LOADED/$(basename "$3" .plist)"; else rm -f "$FAKE_LOADED/${2##*/}"; fi
    ;;
esac
exit 0
SH
chmod +x "$TMP_DIR/bin/launchctl"

run_script() {
  env -u SCHEDULE_TIMES -u CLAUDE_SCHEDULE_TIMES -u CODEX_SCHEDULE_TIMES \
    -u CLAUDE_SCHEDULE_DAYS -u CODEX_SCHEDULE_DAYS -u ACTIVATION_TOOL -u STOKER_FORCE_MIGRATE \
    STOKER_ROOT="$ROOT" HOME="$HOME_DIR" LABEL="$BASE" LEGACY_LABELS="com.example.old.timer" \
    LAUNCHCTL_BIN="$TMP_DIR/bin/launchctl" FAKE_LOADED="$LOADED" \
    "$@"
}

# seed_agent <label> <root>: an installed + loaded agent pointing at <root>.
seed_agent() {
  cat >"$AGENTS/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$2/bin/activate-ai-window.sh</string><string>--once</string></array>
  <key>WorkingDirectory</key><string>$2</string>
</dict>
</plist>
PLIST
  touch "$LOADED/$1"
}

loaded() { [[ -e "$LOADED/$1" ]]; }
fail() { echo "$1" >&2; exit 1; }

# A) ACTIVATION_TOOL=claude with a stray codex agent and the old single agent.
seed_agent "$BASE" "$ROOT"
seed_agent "$BASE.codex" "$ROOT"
echo old >"$ROOT/launchd/$BASE.plist"
out="$(run_script ACTIVATION_TOOL=claude "$SCRIPT" install)"
loaded "$BASE.claude" && [[ -f "$AGENTS/$BASE.claude.plist" ]] || fail "A: claude agent not installed"
! loaded "$BASE.codex" && [[ ! -f "$AGENTS/$BASE.codex.plist" ]] || fail "A: stray codex agent not removed"
! loaded "$BASE" && [[ ! -f "$AGENTS/$BASE.plist" ]] || fail "A: old single-label agent not removed"
[[ ! -f "$ROOT/launchd/$BASE.plist" ]] || fail "A: old repo plist not removed"
grep -q "Installed $BASE.claude" <<<"$out" || fail "A: missing install line: $out"
grep -q "Removed legacy agents: $BASE" <<<"$out" || fail "A: missing legacy line: $out"
grep -q "Claude: 07:00, 12:00, 17:00, 22:00 (daily)" <<<"$out" || fail "A: missing schedule line: $out"
plutil -extract ProgramArguments.3 raw -o - "$AGENTS/$BASE.claude.plist" | grep -qx -- "--scheduled" \
  || fail "A: plist lacks --scheduled"

# B) legacy agent from another root is kept unless forced.
seed_agent com.example.old.timer "$OTHER_ROOT"
run_script ACTIVATION_TOOL=all "$SCRIPT" install >/dev/null 2>"$TMP_DIR/err"
loaded com.example.old.timer && [[ -f "$AGENTS/com.example.old.timer.plist" ]] || fail "B: foreign legacy agent removed"
grep -q "WARNING: kept agent com.example.old.timer" "$TMP_DIR/err" || fail "B: missing warning"
{ loaded "$BASE.claude" && loaded "$BASE.codex"; } || fail "B: both tool agents should be installed"
run_script ACTIVATION_TOOL=all STOKER_FORCE_MIGRATE=1 "$SCRIPT" install >/dev/null 2>&1
! loaded com.example.old.timer && [[ ! -f "$AGENTS/com.example.old.timer.plist" ]] || fail "B: forced migrate did not remove"

# C) codex bootstrap fails → its plist removed, claude reported, non-zero exit.
status=0
run_script ACTIVATION_TOOL=all FAKE_BOOTSTRAP_FAIL="$BASE.codex" "$SCRIPT" install >/dev/null 2>"$TMP_DIR/err" || status=$?
[[ "$status" != "0" ]] || fail "C: expected non-zero exit"
[[ ! -f "$AGENTS/$BASE.codex.plist" ]] || fail "C: failed agent's plist left behind"
grep -q "Installed before the failure: $BASE.claude" "$TMP_DIR/err" || fail "C: missing partial report: $(cat "$TMP_DIR/err")"

# D) uninstall works with an invalid ACTIVATION_TOOL and reports only what existed.
seed_agent "$BASE" "$ROOT"
out="$(run_script ACTIVATION_TOOL=bogus "$SCRIPT" uninstall)"
[[ "$out" == "Uninstalled $BASE.claude $BASE" ]] || fail "D: unexpected uninstall output: $out"
[[ -z "$(ls "$LOADED")" ]] || fail "D: agents still loaded: $(ls "$LOADED")"
out="$(run_script "$SCRIPT" uninstall)"
[[ "$out" == "No Stoker LaunchAgents were installed." ]] || fail "D: second uninstall: $out"
out="$(run_script ACTIVATION_TOOL=bogus "$SCRIPT" status 2>&1)" || fail "D: status must not validate ACTIVATION_TOOL"
[[ "$(grep -c "is not currently loaded" <<<"$out")" == "2" ]] || fail "D: status should list both labels: $out"
if run_script ACTIVATION_TOOL=bogus "$SCRIPT" install >/dev/null 2>&1; then
  fail "D: install must reject an invalid ACTIVATION_TOOL"
fi

# E) another root owns the codex label.
seed_agent "$BASE.codex" "$OTHER_ROOT"
status=0
run_script ACTIVATION_TOOL=all "$SCRIPT" install >"$TMP_DIR/out" 2>"$TMP_DIR/err" || status=$?
[[ "$status" != "0" ]] || fail "E: expected non-zero exit for a foreign per-tool agent"
grep -q "WARNING: kept agent $BASE.codex" "$TMP_DIR/err" || fail "E: missing warning: $(cat "$TMP_DIR/err")"
plutil -extract WorkingDirectory raw -o - "$AGENTS/$BASE.codex.plist" | grep -qx "$OTHER_ROOT" \
  || fail "E: foreign codex plist was overwritten"
loaded "$BASE.codex" || fail "E: foreign codex agent was booted out"
{ loaded "$BASE.claude" && grep -q "Installed $BASE.claude" "$TMP_DIR/out"; } || fail "E: claude should still install"
# Also kept when its tool is disabled.
status=0
run_script ACTIVATION_TOOL=claude "$SCRIPT" install >/dev/null 2>&1 || status=$?
{ [[ "$status" != "0" ]] && loaded "$BASE.codex"; } || fail "E: disabled foreign agent must be kept with non-zero exit"
run_script ACTIVATION_TOOL=all STOKER_FORCE_MIGRATE=1 "$SCRIPT" install >/dev/null 2>&1 || fail "E: forced install failed"
plutil -extract WorkingDirectory raw -o - "$AGENTS/$BASE.codex.plist" | grep -qx "$ROOT" \
  || fail "E: forced install did not replace the foreign agent"
run_script "$SCRIPT" uninstall >/dev/null

# F) uninstall must not remove another root's per-tool agent.
seed_agent "$BASE.claude" "$ROOT"
seed_agent "$BASE.codex" "$OTHER_ROOT"
status=0
run_script "$SCRIPT" uninstall >"$TMP_DIR/out" 2>"$TMP_DIR/err" || status=$?
[[ "$status" != "0" ]] || fail "F: expected non-zero exit when a foreign agent is kept"
grep -q "WARNING: kept agent $BASE.codex" "$TMP_DIR/err" || fail "F: missing warning: $(cat "$TMP_DIR/err")"
{ loaded "$BASE.codex" && [[ -f "$AGENTS/$BASE.codex.plist" ]]; } || fail "F: foreign codex agent was removed"
{ ! loaded "$BASE.claude" && [[ ! -f "$AGENTS/$BASE.claude.plist" ]]; } || fail "F: own claude agent not removed"
[[ "$(cat "$TMP_DIR/out")" == "Uninstalled $BASE.claude" ]] || fail "F: unexpected output: $(cat "$TMP_DIR/out")"
run_script STOKER_FORCE_MIGRATE=1 "$SCRIPT" uninstall >/dev/null 2>&1 || fail "F: forced uninstall failed"
{ ! loaded "$BASE.codex" && [[ ! -f "$AGENTS/$BASE.codex.plist" ]]; } || fail "F: forced uninstall kept the foreign agent"

echo "launchd install lifecycle test passed"
