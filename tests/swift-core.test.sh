#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

let original = """
# keep comments
LABEL=com.stoker.ai-window
SCHEDULE_TIMES=07:00,12:00
"""

let updated = EnvFile.updating(
    original,
    values: [
        "SCHEDULE_TIMES": "06:15,13:15,21:15",
        "KEEP_AWAKE_MODE": "during",
        "CODEX_MODEL": "gpt-5.4-mini"
    ]
)

precondition(updated.contains("# keep comments"))
precondition(updated.contains("LABEL=com.stoker.ai-window"))
precondition(updated.contains("SCHEDULE_TIMES=\"06:15,13:15,21:15\""))
precondition(updated.contains("KEEP_AWAKE_MODE=during"))
precondition(updated.contains("CODEX_MODEL=gpt-5.4-mini"))

// ToolRequirements: ACTIVATION_TOOL decides which CLIs the app treats as required.
precondition(ToolRequirements.requiredCLIs(activationTool: "claude") == Set(["claude"]))
precondition(ToolRequirements.requiredCLIs(activationTool: " CODEX ") == Set(["codex"]))
precondition(ToolRequirements.requiredCLIs(activationTool: "all") == Set(["claude", "codex"]))
precondition(ToolRequirements.requiredCLIs(activationTool: nil) == Set(["claude", "codex"]))
precondition(ToolRequirements.requiredCLIs(activationTool: "bogus") == Set(["claude", "codex"]))

// ClaudeQuotaSource: mirrors the engine's cache-path precedence so the app can
// recognize a plugin-installed oh-my-claudecode (no omc binary on PATH).
precondition(ClaudeQuotaSource.usageCacheFile(env: [:], home: "/Users/u")
    == "/Users/u/.claude/plugins/oh-my-claudecode/.usage-cache-anthropic.json")
precondition(ClaudeQuotaSource.usageCacheFile(env: ["CLAUDE_CONFIG_DIR": "/cfg"], home: "/Users/u")
    == "/cfg/plugins/oh-my-claudecode/.usage-cache-anthropic.json")
precondition(ClaudeQuotaSource.usageCacheFile(env: ["CLAUDE_CONFIG_DIR": "~/cfg"], home: "/Users/u")
    == "/Users/u/cfg/plugins/oh-my-claudecode/.usage-cache-anthropic.json")
precondition(ClaudeQuotaSource.usageCacheFile(
    env: ["CLAUDE_USAGE_CACHE_FILE": "~/x.json", "CLAUDE_CONFIG_DIR": "/ignored"], home: "/Users/u")
    == "/Users/u/x.json")
precondition(ClaudeQuotaSource.usageCacheFile(env: ["CLAUDE_USAGE_CACHE_FILE": ""], home: "/Users/u")
    == "/Users/u/.claude/plugins/oh-my-claudecode/.usage-cache-anthropic.json")

// $HOME spellings: .env.example's own template line uses "${HOME}/…", which bash
// expands when sourcing but EnvParser hands over verbatim.
precondition(ClaudeQuotaSource.usageCacheFile(env: ["CLAUDE_USAGE_CACHE_FILE": "${HOME}/x.json"], home: "/Users/u")
    == "/Users/u/x.json")
precondition(ClaudeQuotaSource.usageCacheFile(env: ["CLAUDE_USAGE_CACHE_FILE": "$HOME/x.json"], home: "/Users/u")
    == "/Users/u/x.json")
precondition(ClaudeQuotaSource.usageCacheFile(env: ["CLAUDE_CONFIG_DIR": "${HOME}/cfg"], home: "/Users/u")
    == "/Users/u/cfg/plugins/oh-my-claudecode/.usage-cache-anthropic.json")
// $HOME must only match at a path-component boundary.
precondition(ClaudeQuotaSource.usageCacheFile(env: ["CLAUDE_USAGE_CACHE_FILE": "$HOMES/x.json"], home: "/Users/u")
    == "$HOMES/x.json")

// usageCacheSignalFile: the cache file only counts while the engine will read it
// (CLAUDE_STATUS_SOURCE cache/unset/empty). Legacy `omc`, `native`, and casings the
// engine's validator rejects must not produce a green "installed".
precondition(ClaudeQuotaSource.usageCacheSignalFile(env: [:], home: "/Users/u")
    == "/Users/u/.claude/plugins/oh-my-claudecode/.usage-cache-anthropic.json")
precondition(ClaudeQuotaSource.usageCacheSignalFile(env: ["CLAUDE_STATUS_SOURCE": ""], home: "/Users/u") != nil)
precondition(ClaudeQuotaSource.usageCacheSignalFile(env: ["CLAUDE_STATUS_SOURCE": "cache"], home: "/Users/u") != nil)
precondition(ClaudeQuotaSource.usageCacheSignalFile(env: ["CLAUDE_STATUS_SOURCE": "omc"], home: "/Users/u") == nil)
precondition(ClaudeQuotaSource.usageCacheSignalFile(env: ["CLAUDE_STATUS_SOURCE": "native"], home: "/Users/u") == nil)
precondition(ClaudeQuotaSource.usageCacheSignalFile(env: ["CLAUDE_STATUS_SOURCE": "Cache"], home: "/Users/u") == nil)
// Inline comments survive EnvParser but bash strips them — only the first token counts.
precondition(ClaudeQuotaSource.usageCacheSignalFile(env: ["CLAUDE_STATUS_SOURCE": "cache # plugin cache"], home: "/Users/u") != nil)
precondition(ClaudeQuotaSource.usageCacheSignalFile(env: ["CLAUDE_STATUS_SOURCE": "omc # legacy"], home: "/Users/u") == nil)

let schedule = ScheduleFormatter.times(from: "6:05, 13:05,21:05")
precondition(schedule == ["06:05", "13:05", "21:05"])

// ScheduleFormatter.nextFire / minutesRemaining / clock.
// Fixed date (2026-06-01, no DST transition) keeps these assertions deterministic.
let cal = Calendar.current
var comps = DateComponents()
comps.year = 2026; comps.month = 6; comps.day = 1; comps.hour = 8
let at8 = cal.date(from: comps)!
let today = cal.startOfDay(for: at8)

// 08:00 → next time today is 12:00
let next1 = ScheduleFormatter.nextFire(times: ["07:00", "12:00", "17:00"], now: at8, calendar: cal)
precondition(next1 == cal.date(byAdding: .minute, value: 12 * 60, to: today)!)

// 23:00 → every time today has passed, wrap to earliest tomorrow (07:00)
comps.hour = 23
let at23 = cal.date(from: comps)!
let next2 = ScheduleFormatter.nextFire(times: ["07:00", "12:00"], now: at23, calendar: cal)
let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
precondition(next2 == cal.date(byAdding: .minute, value: 7 * 60, to: tomorrow)!)

// empty list → nil
precondition(ScheduleFormatter.nextFire(times: [], now: at8, calendar: cal) == nil)

// a time exactly at `now` is "already firing", not upcoming (08:00 at 08:00 → 12:00)
let next3 = ScheduleFormatter.nextFire(times: ["08:00", "12:00"], now: at8, calendar: cal)
precondition(next3 == cal.date(byAdding: .minute, value: 12 * 60, to: today)!)

// minutesRemaining floors and clamps at zero
precondition(ScheduleFormatter.minutesRemaining(until: at8.addingTimeInterval(3600), now: at8) == 60)
precondition(ScheduleFormatter.minutesRemaining(until: at8.addingTimeInterval(-100), now: at8) == 0)

// clock renders local HH:MM
precondition(ScheduleFormatter.clock(at8, calendar: cal) == "08:00")

// DST correctness (regression guard): an explicit America/New_York calendar so the
// transition days are deterministic regardless of the host time zone.
var nyCal = Calendar(identifier: .gregorian)
nyCal.timeZone = TimeZone(identifier: "America/New_York")!
// Spring forward 2026-03-08 (02:00->03:00): a 12:00 entry must still read 12:00, not 13:00.
var springComps = DateComponents()
springComps.year = 2026; springComps.month = 3; springComps.day = 8
springComps.hour = 0; springComps.minute = 30
let springMorning = nyCal.date(from: springComps)!
let springNext = ScheduleFormatter.nextFire(times: ["12:00"], now: springMorning, calendar: nyCal)!
precondition(ScheduleFormatter.clock(springNext, calendar: nyCal) == "12:00")
// Fall back 2026-11-01 (02:00->01:00): a 12:00 entry must read 12:00, not 11:00.
var fallComps = DateComponents()
fallComps.year = 2026; fallComps.month = 11; fallComps.day = 1
fallComps.hour = 0; fallComps.minute = 30
let fallMorning = nyCal.date(from: fallComps)!
let fallNext = ScheduleFormatter.nextFire(times: ["12:00"], now: fallMorning, calendar: nyCal)!
precondition(ScheduleFormatter.clock(fallNext, calendar: nyCal) == "12:00")

let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(UUID().uuidString)
let resources = tempRoot.appendingPathComponent("Stoker.app/Contents/Resources")
let bundledRoot = resources.appendingPathComponent("stoker")
let support = tempRoot.appendingPathComponent("Application Support")

try FileManager.default.createDirectory(
    at: bundledRoot.appendingPathComponent("bin"),
    withIntermediateDirectories: true
)
try "#!/usr/bin/env bash\n".write(
    to: bundledRoot.appendingPathComponent("bin/activate-ai-window.sh"),
    atomically: true,
    encoding: .utf8
)
try "#!/usr/bin/env bash\n".write(
    to: bundledRoot.appendingPathComponent("install.sh"),
    atomically: true,
    encoding: .utf8
)
try "LABEL=com.stoker.ai-window\n".write(
    to: bundledRoot.appendingPathComponent(".env.example"),
    atomically: true,
    encoding: .utf8
)
try FileManager.default.createDirectory(
    at: bundledRoot.appendingPathComponent("codex-probe"),
    withIntermediateDirectories: true
)
try "print(2)\n".write(
    to: bundledRoot.appendingPathComponent("codex-probe/probe.py"),
    atomically: true,
    encoding: .utf8
)

let installedRoot = ProjectLocator.findRoot(
    from: tempRoot.appendingPathComponent("Stoker.app/Contents/MacOS"),
    resourceURL: resources,
    applicationSupportURL: support
)

precondition(installedRoot.path == support.appendingPathComponent("Stoker/stoker").path)
precondition(FileManager.default.fileExists(atPath: installedRoot.appendingPathComponent("bin/activate-ai-window.sh").path))
precondition(FileManager.default.fileExists(atPath: installedRoot.appendingPathComponent("codex-probe/probe.py").path))

// FlameTicker: the scoped flicker driver — ticks only while running, resets on stop.
// Top-level code in this bare-swiftc build is nonisolated, so hop onto the main actor
// explicitly (this driver runs on the main thread, so assumeIsolated always holds).
// Spinning the main run loop pumps the Timer; ticks apply synchronously in its callback,
// so once setRunning(false) returns no stale tick can resurrect the counter.
MainActor.assumeIsolated {
    let ticker = FlameTicker()
    precondition(!ticker.isRunning && ticker.frame == 0, "fresh ticker must be idle at frame 0")
    ticker.setRunning(true)
    ticker.setRunning(true) // idempotent: must not install a second timer
    precondition(ticker.isRunning)
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    precondition(ticker.frame >= 1, "ticker never ticked")
    ticker.setRunning(false)
    precondition(!ticker.isRunning && ticker.frame == 0, "stopping must reset the ticker")
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    precondition(ticker.frame == 0, "stopped ticker kept ticking")
}
SWIFT

swiftc \
  "$ROOT_DIR/app/StokerMenuBar/Sources/StokerCore/StokerCore.swift" \
  "$ROOT_DIR/app/StokerMenuBar/Sources/StokerCore/FlameTicker.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/swift-core-test"

"$TMP_DIR/swift-core-test" &
TEST_PID=$!
( sleep 30; kill "$TEST_PID" 2>/dev/null ) &
TIMER_PID=$!
if ! wait "$TEST_PID"; then
  kill "$TIMER_PID" 2>/dev/null; wait "$TIMER_PID" 2>/dev/null || true
  echo "swift-core-test failed or timed out" >&2
  exit 1
fi
kill "$TIMER_PID" 2>/dev/null; wait "$TIMER_PID" 2>/dev/null || true

echo "swift core test passed"
