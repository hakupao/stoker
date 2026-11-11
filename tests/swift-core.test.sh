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
        "CODEX_MODEL": "gpt-5.6-luna"
    ]
)

precondition(updated.contains("# keep comments"))
precondition(updated.contains("LABEL=com.stoker.ai-window"))
precondition(updated.contains("SCHEDULE_TIMES=\"06:15,13:15,21:15\""))
precondition(updated.contains("KEEP_AWAKE_MODE=during"))
precondition(updated.contains("CODEX_MODEL=gpt-5.6-luna"))

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

// ---- Per-tool schedule: days + nextFire(times:days:) ----
precondition(ScheduleFormatter.days(from: "Sun, mon,MON,fri") == ["mon", "fri", "sun"])
precondition(ScheduleFormatter.days(from: "") == [] && ScheduleFormatter.days(from: "Daily") == [])
precondition(ScheduleFormatter.days(from: "mon,bogus") == ["mon"], "unknown tokens are dropped")
// NIT-10: `daily` mixed with days still means every day; the next save writes "".
precondition(ScheduleFormatter.days(from: "daily,mon") == [] && ScheduleFormatter.days(from: "Mon, DAILY") == [])
precondition(AppSettings(values: ["CODEX_SCHEDULE_DAYS": "daily,mon"]).envValues["CODEX_SCHEDULE_DAYS"] == "")
// NIT-11: normalize matches the engine's ^[0-9]{1,2}:[0-9]{2}$ (then range-checks).
precondition(ScheduleFormatter.normalize("7:05") == "07:05" && ScheduleFormatter.normalize("23:59") == "23:59")
for bad in ["7:5", "+7:00", "07:00:00", "007:00", "7:", ":05", " 7:05", "24:00", "07:60", "-1:00", "7:+5", "٧:٠٥"] {
    precondition(ScheduleFormatter.normalize(bad) == nil, "normalize must reject \(bad)")
}
precondition(ScheduleFormatter.times(from: "7:5,8:05") == ["08:05"])
precondition(ScheduleFormatter.days(from: "mon,tue,wed,thu,fri,sat,sun") == [], "all seven = every day")
precondition(ScheduleFormatter.normalizeDays(["SAT", "tue", "tue"]) == ["tue", "sat"])
var dayCal = Calendar(identifier: .gregorian); dayCal.timeZone = TimeZone(identifier: "UTC")!
var dayComps = DateComponents(); dayComps.year = 2026; dayComps.month = 6; dayComps.day = 1; dayComps.hour = 8
let mon8 = dayCal.date(from: dayComps)!
precondition(dayCal.component(.weekday, from: mon8) == 2, "2026-06-01 is a Monday")
func utcDate(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var c = DateComponents(); c.year = 2026; c.month = 6; c.day = day; c.hour = hour; c.minute = minute
    return dayCal.date(from: c)!
}
// days [] matches the old daily signature.
precondition(ScheduleFormatter.nextFire(times: ["07:00", "12:00"], days: [], now: mon8, calendar: dayCal)
    == ScheduleFormatter.nextFire(times: ["07:00", "12:00"], now: mon8, calendar: dayCal))
// Monday-only: 12:00 later today; 07:00 already passed → next Monday (crosses the week boundary).
precondition(ScheduleFormatter.nextFire(times: ["07:00", "12:00"], days: ["mon"], now: mon8, calendar: dayCal) == utcDate(1, 12))
precondition(ScheduleFormatter.nextFire(times: ["07:00"], days: ["mon"], now: mon8, calendar: dayCal) == utcDate(8, 7))
// Sunday maps to Calendar.weekday 1 (not 7 = Saturday).
precondition(ScheduleFormatter.nextFire(times: ["09:30"], days: ["sun"], now: mon8, calendar: dayCal) == utcDate(7, 9, 30))
precondition(ScheduleFormatter.nextFire(times: ["09:30"], days: ["sat"], now: mon8, calendar: dayCal) == utcDate(6, 9, 30))
// Earliest across days and times; Thursday beats next Monday.
precondition(ScheduleFormatter.nextFire(times: ["07:00", "22:00"], days: ["thu", "mon"], now: utcDate(1, 23), calendar: dayCal) == utcDate(4, 7))
precondition(ScheduleFormatter.nextFire(times: [], days: ["mon"], now: mon8, calendar: dayCal) == nil)
precondition(ToolSchedule(times: ["07:00"], days: ["tue"]).nextFire(now: mon8, calendar: dayCal) == utcDate(2, 7))

// AppSettings: D1 fallback chain (per-tool → SCHEDULE_TIMES → default; empty = unset).
let sDefault = AppSettings(values: [:])
precondition(sDefault.claudeScheduleTimes == ["07:00", "12:00", "17:00", "22:00"])
precondition(sDefault.codexScheduleTimes == ["07:00", "12:00", "17:00", "22:00"])
precondition(sDefault.claudeScheduleDays == [] && sDefault.codexScheduleDays == [])
let sLegacy = AppSettings(values: ["SCHEDULE_TIMES": "06:15,13:15", "CODEX_SCHEDULE_TIMES": ""])
precondition(sLegacy.claudeScheduleTimes == ["06:15", "13:15"] && sLegacy.codexScheduleTimes == ["06:15", "13:15"])
let sPerTool = AppSettings(values: ["SCHEDULE_TIMES": "06:15", "CLAUDE_SCHEDULE_TIMES": "07:00,12:00",
                                    "CODEX_SCHEDULE_TIMES": "7:30", "CODEX_SCHEDULE_DAYS": "Thu,mon",
                                    "CLAUDE_SCHEDULE_DAYS": "daily"])
precondition(sPerTool.claudeScheduleTimes == ["07:00", "12:00"] && sPerTool.claudeScheduleDays == [])
precondition(sPerTool.codexScheduleTimes == ["07:30"] && sPerTool.codexScheduleDays == ["mon", "thu"])
precondition(sPerTool.scheduleTimes("codex") == ["07:30"] && sPerTool.scheduleDays("claude") == [])
// envValues writes the four per-tool keys (empty days → ""), never SCHEDULE_TIMES.
let ev = sPerTool.envValues
precondition(ev["CLAUDE_SCHEDULE_TIMES"] == "07:00,12:00" && ev["CLAUDE_SCHEDULE_DAYS"] == "")
precondition(ev["CODEX_SCHEDULE_TIMES"] == "07:30" && ev["CODEX_SCHEDULE_DAYS"] == "mon,thu")
precondition(ev["SCHEDULE_TIMES"] == nil)
var sEdit = sPerTool
sEdit.setScheduleDays(["sun", "mon", "tue", "wed", "thu", "fri", "sat"], for: "codex")
precondition(sEdit.codexScheduleDays == [], "selecting all seven days normalizes to every day")
sEdit.setScheduleDays(["fri", "mon"], for: "claude")
sEdit.setScheduleTimes(["22:00"], for: "codex")
// Round-trip through .env text: legacy SCHEDULE_TIMES line survives, empty days stay empty.
let envText = EnvFile.updating("# c\nSCHEDULE_TIMES=06:15\nCODEX_SCHEDULE_DAYS=mon\n", values: sEdit.envValues)
precondition(envText.contains("SCHEDULE_TIMES=06:15\n"))
precondition(envText.contains("\nCODEX_SCHEDULE_DAYS=\n"), "empty days written as KEY=")
let reparsed = AppSettings(values: EnvParser.parse(envText))
precondition(reparsed.claudeScheduleTimes == ["07:00", "12:00"] && reparsed.claudeScheduleDays == ["mon", "fri"])
precondition(reparsed.codexScheduleTimes == ["22:00"] && reparsed.codexScheduleDays == [])

// Schedule decode: per-tool fields when present, `times` + every day when absent (older engine).
let newSchedule = try! JSONDecoder().decode(ActivationState.Schedule.self, from: Data(#"""
{"times":["07:00","12:00"],"claude":{"times":["07:00","12:00"],"days":[]},"codex":{"times":["07:00"],"days":["Thu","mon"]}}
"""#.utf8))
precondition(newSchedule.forTool("claude") == ToolSchedule(times: ["07:00", "12:00"], days: []))
precondition(newSchedule.forTool("codex") == ToolSchedule(times: ["07:00"], days: ["mon", "thu"]))
let oldSchedule = try! JSONDecoder().decode(ActivationState.Schedule.self, from: Data(#"{"times":["06:00","18:00"]}"#.utf8))
precondition(oldSchedule.claude == ToolSchedule(times: ["06:00", "18:00"], days: []) && oldSchedule.codex == oldSchedule.claude)
// launchctl.agents is optional and tolerated when malformed.
let lcAgents = try! JSONDecoder().decode(ActivationState.Launchctl.self, from: Data(#"""
{"state":"running","agents":{"claude":{"label":"com.stoker.ai-window.claude","loaded":true,"state":"waiting"},"codex":{"label":"com.stoker.ai-window.codex","loaded":false}}}
"""#.utf8))
precondition(lcAgents.agents?["claude"]?.loaded == true && lcAgents.agents?["codex"]?.loaded == false)
precondition(try! JSONDecoder().decode(ActivationState.Launchctl.self, from: Data(#"{"state":"x"}"#.utf8)).agents == nil)
precondition(try! JSONDecoder().decode(ActivationState.Launchctl.self, from: Data(#"{"agents":"bad"}"#.utf8)).agents == nil)
// Fix round 1: legacy / needs_migration / stray are optional and tolerated when malformed.
let lcMigrate = try! JSONDecoder().decode(ActivationState.Launchctl.self, from: Data(#"""
{"needs_migration":true,"legacy":[{"label":"com.stoker.ai-window","loaded":true,"matches_root":false,"program":"/p","working_directory":"/w"}],
 "agents":{"claude":{"label":"c","loaded":true,"stray":false}}}
"""#.utf8))
precondition(lcMigrate.needsMigration == true && lcMigrate.needsReinstall)
precondition(lcMigrate.legacy?.first?.label == "com.stoker.ai-window" && lcMigrate.legacy?.first?.matchesRoot == false)
precondition(lcMigrate.legacy?.first?.workingDirectory == "/w")
let lcStray = try! JSONDecoder().decode(ActivationState.Launchctl.self, from: Data(#"""
{"needs_migration":false,"agents":{"claude":{"loaded":true},"codex":{"loaded":true,"stray":true}}}
"""#.utf8))
precondition(lcStray.needsReinstall && lcStray.agents?["codex"]?.stray == true)
let lcBad = try! JSONDecoder().decode(ActivationState.Launchctl.self, from: Data(#"""
{"state":"x","needs_migration":"yes","legacy":{"label":"oops"}}
"""#.utf8))
precondition(lcBad.needsMigration == nil && lcBad.legacy == nil && !lcBad.needsReinstall)
precondition(!lcAgents.needsReinstall, "plain loaded agents need no re-install")

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

// ToolQuota: plan/subscription/credits decode with a PLAIN JSONDecoder (the app
// uses no convertFromSnakeCase, so the snake_case CodingKeys must carry the fields).
let quotaDecoder = JSONDecoder()
func decodeQuota(_ json: String) -> ActivationState.ToolQuota {
    try! quotaDecoder.decode(ActivationState.ToolQuota.self, from: Data(json.utf8))
}
// Codex row: top-level plan_type + a balance-style credits object.
let codexQ = decodeQuota(#"{"ok":true,"plan_type":"pro","credits":{"has_credits":true,"balance":"12.50"},"five_hour":{"used_percent":42,"remaining_percent":58}}"#)
precondition(codexQ.planType == "pro")
precondition(codexQ.displayPlan == "pro")
precondition(codexQ.credits?.balance == "12.50")
precondition(codexQ.credits?.hasCredits == true)
precondition(codexQ.fiveHour?.remainingPercent == 58)
// Claude row: subscription_type + extra_usage-style credits; displayPlan falls back to it.
let claudeQ = decodeQuota(#"{"ok":true,"subscription_type":"max","credits":{"is_enabled":true,"used_credits":25,"monthly_limit":100},"five_hour":{"used_percent":10,"remaining_percent":90}}"#)
precondition(claudeQ.subscriptionType == "max")
precondition(claudeQ.displayPlan == "max")
precondition(claudeQ.credits?.usedCredits == 25)
precondition(claudeQ.credits?.monthlyLimit == 100)
// Defensive: a surprise `credits` shape (bare string from an older snapshot row)
// must degrade to nil, never fail the whole decode.
let legacyQ = decodeQuota(#"{"ok":true,"plan_type":"plus","credits":"legacy-string"}"#)
precondition(legacyQ.planType == "plus")
precondition(legacyQ.credits == nil)
// No plan/credits at all → all nil, displayPlan nil (Claude cache-source default).
let bareQ = decodeQuota(#"{"ok":true,"five_hour":{"used_percent":5,"remaining_percent":95}}"#)
precondition(bareQ.displayPlan == nil)
precondition(bareQ.credits == nil)
precondition(bareQ.scopedWeekly == nil)

// Plan pill labels: known tiers, humanized unknown tiers, "unknown" hidden.
precondition(ActivationState.ToolQuota.planLabel("self_serve_business_prolite") == "Business Pro Lite")
precondition(ActivationState.ToolQuota.planLabel("plus") == "Plus")
precondition(ActivationState.ToolQuota.planLabel("prolite") == "Pro Lite")
precondition(ActivationState.ToolQuota.planLabel("max") == "Max")
precondition(ActivationState.ToolQuota.planLabel("enterprise") == "Enterprise")
precondition(ActivationState.ToolQuota.planLabel("new-shiny_tier") == "New Shiny Tier")
precondition(ActivationState.ToolQuota.planLabel("unknown") == nil)
precondition(ActivationState.ToolQuota.planLabel("UNKNOWN") == nil)
precondition(ActivationState.ToolQuota.planLabel("") == nil)
precondition(decodeQuota(#"{"ok":true,"plan_type":"self_serve_business_prolite"}"#).displayPlanLabel == "Business Pro Lite")
precondition(decodeQuota(#"{"ok":true,"plan_type":"unknown"}"#).displayPlanLabel == nil)
precondition(claudeQ.displayPlanLabel == "Max")

// Window presence follows the snapshot, not the tool (plans differ). Fixtures are the four real
// row shapes: Claude idle 5h (0/null), Claude without 5h (null/null), Codex 5h + weekly, Codex
// weekly-only (five_hour: null).
let claudeIdle5h = decodeQuota(#"{"ok":true,"five_hour":{"used_percent":0,"remaining_percent":100,"resets_at":null},"weekly":{"used_percent":14,"remaining_percent":86,"resets_at":"2026-11-16T07:59:59.776Z"}}"#)
let claudeNo5h = decodeQuota(#"{"ok":true,"five_hour":{"used_percent":null,"remaining_percent":null,"resets_at":null},"weekly":{"used_percent":14,"remaining_percent":86,"resets_at":"2026-11-16T07:59:59.776Z"}}"#)
let codexPlus = decodeQuota(#"{"ok":true,"plan_type":"plus","five_hour":{"used_percent":0,"remaining_percent":100,"window_minutes":300,"resets_at":"2026-11-11T05:00:00Z"},"weekly":{"used_percent":8,"remaining_percent":92,"window_minutes":10080,"resets_at":"2026-11-17T00:00:00Z"}}"#)
let codexWeeklyQ = decodeQuota(#"{"ok":true,"five_hour":null,"weekly":{"used_percent":8,"remaining_percent":92}}"#)
precondition(claudeIdle5h.windowProfile(tool: "claude") == .sessionWeekly)
precondition(claudeNo5h.windowProfile(tool: "claude") == .weeklyOnly, "an all-null Claude five_hour object is no window")
precondition(codexPlus.windowProfile(tool: "codex") == .sessionWeekly)
precondition(codexWeeklyQ.windowProfile(tool: "codex") == .weeklyOnly)
// A Claude window that only rolled over still counts as present.
precondition(decodeQuota(#"{"ok":true,"five_hour":{"used_percent":null,"resets_at":null,"reset_passed":true},"weekly":{"used_percent":1}}"#)
    .windowProfile(tool: "claude") == .sessionWeekly)
precondition(decodeQuota(#"{"ok":false,"five_hour":{"used_percent":3}}"#).windowProfile(tool: "claude") == .unknown)
precondition(decodeQuota(#"{"ok":true}"#).windowProfile(tool: "codex") == .none)
// Not detected yet keeps the display defaults (Claude 5h, Codex weekly).
precondition(WindowProfile.unknown.hasSession(tool: "claude") && !WindowProfile.unknown.hasSession(tool: "codex"))
precondition(WindowProfile.sessionWeekly.hasSession(tool: "codex") && WindowProfile.sessionOnly.hasSession(tool: "codex"))
precondition(!WindowProfile.weeklyOnly.hasSession(tool: "claude") && !WindowProfile.none.hasSession(tool: "claude"))

// Claude per-scope weekly buckets: decoded with ids/labels/percent/active flag; a
// reset-passed bucket keeps its blanked percentages; inactive stays distinguishable
// from "unknown" (nil).
let scopedQ = decodeQuota(#"{"ok":true,"scoped_weekly":[{"id":"fable","label":"Fable","used_percent":61,"remaining_percent":39,"resets_at":"2026-09-28T08:00:00.315Z","is_active":false},{"id":"x","label":null,"used_percent":null,"remaining_percent":null,"resets_at":null,"is_active":true,"reset_passed":true},{"id":"y","label":"Y","used_percent":5,"remaining_percent":95,"resets_at":null,"is_active":null}]}"#)
precondition(scopedQ.scopedWeekly?.count == 3)
precondition(scopedQ.scopedWeekly?[0].id == "fable")
precondition(scopedQ.scopedWeekly?[0].label == "Fable")
precondition(scopedQ.scopedWeekly?[0].usedPercent == 61)
precondition(scopedQ.scopedWeekly?[0].remainingPercent == 39)
precondition(scopedQ.scopedWeekly?[0].resetsAt == "2026-09-28T08:00:00.315Z")
precondition(scopedQ.scopedWeekly?[0].isActive == false)
precondition(scopedQ.scopedWeekly?[1].label == "x", "label falls back to id")
precondition(scopedQ.scopedWeekly?[1].remainingPercent == nil)
precondition(scopedQ.scopedWeekly?[1].resetPassed == true)
precondition(scopedQ.scopedWeekly?[2].isActive == nil)
// Empty array stays empty (account without scoped limits).
precondition(decodeQuota(#"{"ok":true,"scoped_weekly":[]}"#).scopedWeekly?.isEmpty == true)
// Malformed value degrades to nil without failing the row.
let badScopedQ = decodeQuota(#"{"ok":true,"plan_type":"max","scoped_weekly":"bogus"}"#)
precondition(badScopedQ.scopedWeekly == nil)
precondition(badScopedQ.planType == "max")
// One malformed element is dropped on its own; the rest survive.
let mixedScopedQ = decodeQuota(#"{"ok":true,"scoped_weekly":[{"id":"a","label":"A","used_percent":"oops"},42,{"id":"b","label":"B","used_percent":10,"remaining_percent":90}]}"#)
precondition(mixedScopedQ.scopedWeekly?.count == 1)
precondition(mixedScopedQ.scopedWeekly?.first?.id == "b")

// ResetTime: fractional and plain ISO, nil/garbage → nil
precondition(ResetTime.parse("2026-09-28T07:59:59.914Z") != nil)
precondition(ResetTime.parse("2026-10-03T13:49:45Z") != nil)
precondition(ResetTime.parse(nil) == nil)
precondition(ResetTime.parse("soon") == nil)

// reset_credits decode: present, absent, malformed (must not drop the quota)
let rc = decodeQuota(#"{"ok":true,"weekly":{"used_percent":1},"reset_credits":{"available_count":1,"earliest_expires_at":"2026-10-22T20:37:22Z"}}"#)
precondition(rc.resetCredits?.availableCount == 1)
precondition(rc.resetCredits?.earliestExpiresAt == "2026-10-22T20:37:22Z")
precondition(decodeQuota(#"{"ok":true}"#).resetCredits == nil)
let badRC = decodeQuota(#"{"ok":true,"weekly":{"used_percent":5},"reset_credits":"oops"}"#)
precondition(badRC.resetCredits == nil && badRC.weekly?.usedPercent == 5)

// Retired Codex model migration: a stale .env pin is replaced by the current default
// (the next save persists it); custom and "default" values are kept.
precondition(AppSettings(values: ["CODEX_MODEL": "gpt-5.4-mini"]).codexModel == "gpt-5.6-luna")
precondition(AppSettings(values: [:]).codexModel == "gpt-5.6-luna")
precondition(AppSettings(values: ["CODEX_MODEL": "default"]).codexModel == "default")
precondition(AppSettings(values: ["CODEX_MODEL": "gpt-9-custom"]).codexModel == "gpt-9-custom")
precondition(AppSettings(values: ["CODEX_MODEL": "gpt-5.4-mini"]).envValues["CODEX_MODEL"] == "gpt-5.6-luna")

// Codex settings: auto-update, model-fallback, activate-only-when-idle (default true when key absent, false only when value is "0")
let s0 = AppSettings(values: [:])
precondition(s0.codexAutoUpdate && s0.codexModelFallback && s0.codexActivateOnlyWhenIdle)
var s1 = AppSettings(values: ["CODEX_AUTO_UPDATE": "0", "CODEX_MODEL_FALLBACK": "1", "CODEX_ACTIVATE_ONLY_WHEN_IDLE": "0"])
precondition(!s1.codexAutoUpdate && s1.codexModelFallback && !s1.codexActivateOnlyWhenIdle)
s1.codexAutoUpdate = true
precondition(s1.envValues["CODEX_AUTO_UPDATE"] == "1")
precondition(s1.envValues["CODEX_ACTIVATE_ONLY_WHEN_IDLE"] == "0")
precondition(s1.envValues["CODEX_MODEL_FALLBACK"] == "1")

// Skip-reason labels: the Codex idle-window policy has its own label, distinct from
// both "exhausted" and the "quota unknown" catch-all.
let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
AppLanguage.current = .en
precondition(L10n.skipReasonText("window_already_active") == "Weekly window already running")
precondition(L10n.skipReasonText("quota_exhausted") == "Quota exhausted")
precondition(L10n.skipReasonText("preflight_status_missing") == "Quota unknown")
precondition(L10n.quotaMiniHelp(remaining: 92, used: 8, weekly: true) == "Weekly window: 92% remaining (8% used)")
precondition(L10n.quotaMiniHelp(remaining: 40, used: nil) == "5-hour window: 40% remaining")
AppLanguage.current = .zh
precondition(L10n.skipReasonText("window_already_active") == "周窗口已在计时")
// Usage rows (LogStore decodes with convertFromSnakeCase): a failed attempt superseded by
// a model-fallback retry counts as skipped, not as an error; ids differ by model.
let usageDecoder = JSONDecoder()
usageDecoder.keyDecodingStrategy = .convertFromSnakeCase
let supersededRow = try! usageDecoder.decode(UsageRecord.self, from: Data(#"{"timestamp":"2026-09-27 07:00:05 JST","run_id":"r","tool":"codex","ok":false,"exit_code":1,"model":"gpt-old","superseded_by_fallback":true}"#.utf8))
let retryRow = try! usageDecoder.decode(UsageRecord.self, from: Data(#"{"timestamp":"2026-09-27 07:00:05 JST","run_id":"r","tool":"codex","ok":true,"exit_code":0,"model":"gpt-new","model_fallback":{"from":"gpt-old","to":"gpt-new","attempt":1}}"#.utf8))
let plainErrorRow = try! usageDecoder.decode(UsageRecord.self, from: Data(#"{"timestamp":"2026-09-27 07:00:06 JST","run_id":"r","tool":"codex","ok":false,"exit_code":1}"#.utf8))
precondition(supersededRow.supersededByFallback == true)
precondition(supersededRow.status == .skipped, "a superseded attempt must not count as an error")
precondition(retryRow.status == .success)
precondition(plainErrorRow.status == .error)
precondition(supersededRow.id != retryRow.id, "same-second rows must not share an id")

if let savedLanguage {
    UserDefaults.standard.set(savedLanguage, forKey: "appLanguage")
} else {
    UserDefaults.standard.removeObject(forKey: "appLanguage")
}

// ---- ToolHealth ----
var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
func rec(_ ts: String, _ tool: String, ok: Bool? = nil, skipped: Bool? = nil,
         superseded: Bool? = nil, result: String? = nil) -> UsageRecord {
    var o: [String: Any] = ["timestamp": ts, "tool": tool]
    if let ok { o["ok"] = ok }
    if let skipped { o["skipped"] = skipped }
    // UsageRecord's own CodingKeys carry camelCase raw values (no convertFromSnakeCase
    // here, unlike the LogStore decoder above), so a plain JSONDecoder expects
    // "supersededByFallback", not "superseded_by_fallback".
    if let superseded { o["supersededByFallback"] = superseded }
    if let result { o["result"] = result }
    let d = try! JSONSerialization.data(withJSONObject: o)
    return try! JSONDecoder().decode(UsageRecord.self, from: d)
}
func iso(_ s: String) -> Date { ResetTime.parse(s)! }
let slots = ["07:00", "12:00", "17:00", "22:00"]
let toolHealthNow = iso("2026-09-27T00:00:00Z")   // 00:00 UTC

// Claude: no history → unknown
precondition(ToolHealthEvaluator.claude(records: [], scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .unknown)
// Claude: last real run ok → ok; skipped + superseded rows ignored
let cOK = ToolHealthEvaluator.claude(records: [
    rec("2026-09-26 22:00:05 UTC", "claude", ok: true),
    rec("2026-09-26 23:00:00 UTC", "claude", skipped: true),
    rec("2026-09-26 23:30:00 UTC", "claude", ok: false, superseded: true)],
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(cOK.state == .ok && cOK.lastRunOK == true && cOK.consecutiveFailures == 0)
// Claude: one failure → warning; two → alert
precondition(ToolHealthEvaluator.claude(records: [
    rec("2026-09-26 17:00:00 UTC", "claude", ok: true),
    rec("2026-09-26 22:00:00 UTC", "claude", ok: false, result: "401")],
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .warning)
let cAlert = ToolHealthEvaluator.claude(records: [
    rec("2026-09-26 17:00:00 UTC", "claude", ok: false),
    rec("2026-09-26 22:00:00 UTC", "claude", ok: false, result: "HTTP 401 unauthorized")],
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(cAlert.state == .alert && cAlert.consecutiveFailures == 2 && cAlert.lastError == "HTTP 401 unauthorized")
// Claude: schedule on, last success > 24h ago → alert even without 2 failures
precondition(ToolHealthEvaluator.claude(records: [rec("2026-09-25 12:00:00 UTC", "claude", ok: true)],
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .alert)
// ...but schedule off → no staleness alert, and nextActivation nil
let cOff = ToolHealthEvaluator.claude(records: [rec("2026-09-25 12:00:00 UTC", "claude", ok: true)],
    scheduleOn: false, times: slots, now: toolHealthNow, calendar: utc)
precondition(cOff.state == .ok && cOff.nextActivation == nil)
// Claude next activation = next slot
precondition(cOK.nextActivation == iso("2026-09-27T07:00:00Z"))

// Codex windows
func win(_ used: Double?, _ resets: String?) -> ActivationState.QuotaWindow {
    var o: [String: Any] = [:]
    if let used { o["used_percent"] = used; o["remaining_percent"] = 100 - used }
    if let resets { o["resets_at"] = resets }
    return try! JSONDecoder().decode(ActivationState.QuotaWindow.self, from: try! JSONSerialization.data(withJSONObject: o))
}
// anchored (used>0, reset in future) → next activation = first slot AFTER the reset (next day 07:00)
let xAnch = ToolHealthEvaluator.codex(records: [rec("2026-09-26 22:56:00 UTC", "codex", ok: true)],
    weekly: win(8, "2026-10-03T22:49:45Z"), scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(xAnch.state == .anchored)
precondition(xAnch.nextActivation == iso("2026-10-04T07:00:00Z"))
// anchored by a successful run this cycle even when used rounds to 0
precondition(ToolHealthEvaluator.codex(records: [rec("2026-09-26 22:56:00 UTC", "codex", ok: true)],
    weekly: win(0, "2026-10-03T22:49:45Z"), scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .anchored)
// idle window (used 0, no run this cycle) → pending, next = next slot
let xIdle = ToolHealthEvaluator.codex(records: [], weekly: win(0, "2026-10-04T00:00:00Z"),
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(xIdle.state == .pending && xIdle.nextActivation == iso("2026-09-27T07:00:00Z"))
// reset already passed → pending
precondition(ToolHealthEvaluator.codex(records: [], weekly: win(40, "2026-09-26T13:00:00Z"),
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .pending)
// exhausted
precondition(ToolHealthEvaluator.codex(records: [rec("2026-09-26 22:56:00 UTC", "codex", ok: true)],
    weekly: win(100, "2026-10-03T22:49:45Z"), scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .exhausted)
// last real run failed → warning even though anchored (skipped rows in between ignored);
// nextActivation must still track the anchored WINDOW (first slot after resetsAt), not the
// warning-overridden state — the engine skips runs while the window is anchored regardless.
let xWarningAnchored = ToolHealthEvaluator.codex(records: [
    rec("2026-09-26 22:55:00 UTC", "codex", ok: false),
    rec("2026-09-26 23:54:00 UTC", "codex", skipped: true)],
    weekly: win(8, "2026-10-03T22:49:45Z"), scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(xWarningAnchored.state == .warning)
precondition(xWarningAnchored.nextActivation == iso("2026-10-04T07:00:00Z"))
// pending window (not anchored: used 0, no run this cycle) + 1 failure → still warning
precondition(ToolHealthEvaluator.codex(records: [rec("2026-09-26 22:00:00 UTC", "codex", ok: false)],
    weekly: win(0, "2026-10-04T00:00:00Z"), scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .warning)
// schedule off → no nextActivation even for an anchored window
precondition(ToolHealthEvaluator.codex(records: [], weekly: win(8, "2026-10-03T22:49:45Z"),
    scheduleOn: false, times: slots, now: toolHealthNow, calendar: utc).nextActivation == nil)
// two consecutive real failures → alert, overriding anchored/exhausted
let xAlert = ToolHealthEvaluator.codex(records: [
    rec("2026-09-19 22:00:00 UTC", "codex", ok: false),
    rec("2026-09-20 07:00:00 UTC", "codex", ok: false, result: "model is not supported")],
    weekly: win(100, "2026-10-03T22:49:45Z"), scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(xAlert.state == .alert && xAlert.consecutiveFailures == 2)
// fallback-superseded failure followed by success → not a failure
precondition(ToolHealthEvaluator.codex(records: [
    rec("2026-09-26 22:55:00 UTC", "codex", ok: false, superseded: true),
    rec("2026-09-26 22:55:30 UTC", "codex", ok: true)],
    weekly: win(8, "2026-10-03T22:49:45Z"), scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .anchored)
// other tool's rows ignored
precondition(ToolHealthEvaluator.codex(records: [rec("2026-09-26 22:00:00 UTC", "claude", ok: false),
    rec("2026-09-26 22:01:00 UTC", "claude", ok: false)],
    weekly: nil, scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .pending)
// empty times → nextActivation nil
precondition(ToolHealthEvaluator.codex(records: [], weekly: nil, scheduleOn: true, times: [], now: toolHealthNow, calendar: utc).nextActivation == nil)

// ---- Task 4: LogStore split skip counts + per-series trend points ----
MainActor.assumeIsolated {
    let logRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("stoker-logstore-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: logRoot.appendingPathComponent("logs"),
                                             withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: logRoot) }
    let usageLines = [
        #"{"timestamp":"2026-09-26 07:00:05 UTC","run_id":"a","tool":"claude","ok":true,"exit_code":0}"#,
        #"{"timestamp":"2026-09-26 07:00:06 UTC","run_id":"a","tool":"codex","skipped":true,"skip_reason":"window_already_active"}"#,
        #"{"timestamp":"2026-09-26 12:00:06 UTC","run_id":"b","tool":"claude","skipped":true,"skip_reason":"quota_exhausted"}"#,
        #"{"timestamp":"2026-09-26 17:00:06 UTC","run_id":"c","tool":"codex","ok":false,"exit_code":1,"model":"old","superseded_by_fallback":true}"#,
    ]
    let statusLines = [
        #"{"timestamp":"2026-09-26 07:00:10 UTC","tool":"claude","ok":true,"five_hour":{"remaining_percent":90},"weekly":{"remaining_percent":70}}"#,
        #"{"timestamp":"2026-09-26 07:00:11 UTC","tool":"codex","ok":true,"weekly":{"remaining_percent":99}}"#,
        #"{"timestamp":"2026-09-26 12:00:10 UTC","tool":"claude","ok":true,"five_hour":{"remaining_percent":60},"weekly":{"remaining_percent":65}}"#,
        #"{"timestamp":"2026-09-26 12:00:11 UTC","tool":"codex","ok":true,"weekly":{"remaining_percent":95}}"#,
    ]
    try! usageLines.joined(separator: "\n").write(to: logRoot.appendingPathComponent("logs/usage.jsonl"), atomically: true, encoding: .utf8)
    try! statusLines.joined(separator: "\n").write(to: logRoot.appendingPathComponent("logs/status.jsonl"), atomically: true, encoding: .utf8)
    let store = LogStore(root: logRoot)
    store.dateRange = .all
    store.load()
    precondition(store.totalRuns == 4)
    precondition(store.plannedSkipCount == 1, "window_already_active is a planned skip")
    precondition(store.quotaSkipCount == 1, "quota skips exclude planned + superseded rows")
    precondition(store.errorCount == 0, "a superseded attempt is not an error")
    let codexPts = store.chartPoints(series: .codexWeekly)
    precondition(codexPts.count == 2 && codexPts.allSatisfy { $0.tool == "codex" })
    precondition(codexPts.map(\.remainingPercent) == [99, 95])
    let c5 = store.chartPoints(series: .claudeFiveHour)
    precondition(c5.count == 2 && c5.allSatisfy { $0.tool == "claude" })
    precondition(c5.map(\.remainingPercent) == [90, 60])
    precondition(store.chartPoints(series: .claudeWeekly).map(\.remainingPercent) == [70, 65])
    // The run-list tool filter must not empty the trend (the trend picks its own tool).
    store.toolFilter = .claude
    precondition(store.chartPoints(series: .codexWeekly).count == 2)
    precondition(TrendSeries.allCases == [.claudeFiveHour, .claudeWeekly, .codexFiveHour, .codexWeekly])
    precondition(TrendSeries.codexWeekly.tool == "codex" && TrendSeries.claudeWeekly.tool == "claude")
    precondition(TrendSeries.codexFiveHour.tool == "codex" && TrendSeries.codexFiveHour.isSession)
    precondition(!TrendSeries.codexWeekly.isSession && TrendSeries.claudeFiveHour.isSession)
    // Codex 5h series reads the Codex rows' five_hour (none in these weekly-only rows).
    precondition(store.chartPoints(series: .codexFiveHour).isEmpty)
    // Only the windows the accounts have are offered.
    precondition(TrendSeries.available(claudeHasSession: true, codexHasSession: false)
        == [.claudeFiveHour, .claudeWeekly, .codexWeekly])
    precondition(TrendSeries.available(claudeHasSession: false, codexHasSession: true)
        == [.claudeWeekly, .codexFiveHour, .codexWeekly])
    precondition(TrendSeries.available(claudeHasSession: false, codexHasSession: false) == [.claudeWeekly, .codexWeekly])
    // 5h history in the loaded rows keeps that series on offer even without a session window.
    precondition(store.sessionHistoryTools == ["claude"], "Claude rows carry 5h data, Codex rows don't")
}

// A 5h-gated Codex row: the planned-skip label follows preflight.gate_window (via LogStore's decoder).
MainActor.assumeIsolated {
    let gateRoot = FileManager.default.temporaryDirectory.appendingPathComponent("stoker-gate-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: gateRoot.appendingPathComponent("logs"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: gateRoot) }
    let lines = [
        #"{"timestamp":"2026-11-11 07:00:06 UTC","run_id":"a","tool":"codex","skipped":true,"skip_reason":"window_already_active","preflight":{"action":"skip","gate_window":"five_hour"}}"#,
        #"{"timestamp":"2026-11-11 12:00:06 UTC","run_id":"b","tool":"codex","skipped":true,"skip_reason":"window_already_active","preflight":{"action":"skip"}}"#,
        #"{"timestamp":"2026-11-11 17:00:06 UTC","run_id":"c","tool":"codex","skipped":true,"skip_reason":"window_already_active","preflight":"bad"}"#,
        #"{"timestamp":"2026-11-11 17:30:00 UTC","tool":"codex","ok":true,"five_hour":{"remaining_percent":80},"weekly":{"remaining_percent":90}}"#,
    ]
    try! lines.joined(separator: "\n").write(to: gateRoot.appendingPathComponent("logs/usage.jsonl"), atomically: true, encoding: .utf8)
    try! lines[3].write(to: gateRoot.appendingPathComponent("logs/status.jsonl"), atomically: true, encoding: .utf8)
    let gateStore = LogStore(root: gateRoot)
    gateStore.dateRange = .all
    gateStore.load()
    let byRun = Dictionary(gateStore.usageRecords.compactMap { r in r.runId.map { ($0, r) } }, uniquingKeysWith: { a, _ in a })
    precondition(byRun["a"]?.gateWindow == "five_hour")
    precondition(byRun["b"]?.gateWindow == nil && byRun["c"]?.gateWindow == nil, "absent/malformed → weekly (nil)")
    precondition(gateStore.chartPoints(series: .codexFiveHour).map(\.remainingPercent) == [80])
    precondition(gateStore.sessionHistoryTools == ["codex"])
}
// No 5h data loaded → nothing kept on offer beyond what the accounts have.
MainActor.assumeIsolated {
    let emptyRoot = FileManager.default.temporaryDirectory.appendingPathComponent("stoker-nohist-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: emptyRoot.appendingPathComponent("logs"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: emptyRoot) }
    try! #"{"timestamp":"2026-11-11 07:00:10 UTC","tool":"claude","ok":true,"five_hour":{"used_percent":null,"remaining_percent":null},"weekly":{"remaining_percent":86}}"#
        .write(to: emptyRoot.appendingPathComponent("logs/status.jsonl"), atomically: true, encoding: .utf8)
    let noHist = LogStore(root: emptyRoot)
    noHist.load()
    precondition(noHist.sessionHistoryTools.isEmpty, "an all-null 5h object is no history")
}

// ---- Task 4: shared health snapshot (one evaluation for Activity tab + header/menu) ----
let snapQuota: [String: ActivationState.ToolQuota] = [
    "codex": decodeQuota(#"{"ok":true,"weekly":{"used_percent":8,"remaining_percent":92,"resets_at":"2026-10-03T22:49:45Z"}}"#)
]
let snapRecords = [
    rec("2026-09-26 17:00:00 UTC", "claude", ok: false),
    rec("2026-09-26 22:00:00 UTC", "claude", ok: false, result: "HTTP 401"),
    rec("2026-09-26 22:56:00 UTC", "codex", ok: true),
]
let snap = ToolHealthEvaluator.snapshot(records: snapRecords, quota: snapQuota, installed: true,
    times: slots, activationTool: "all", now: toolHealthNow, calendar: utc)
precondition(snap.claude.state == .alert && snap.codex.state == .anchored)
precondition(snap.codex.nextActivation == iso("2026-10-04T07:00:00Z"), "codex uses the weekly window")
precondition(snap.alertTools == ["claude"] && snap.anyAlert)
// A tool excluded by ACTIVATION_TOOL is not scheduled: no next activation, never alerts.
let snapCodexOnly = ToolHealthEvaluator.snapshot(records: snapRecords, quota: snapQuota, installed: true,
    times: slots, activationTool: "codex", now: toolHealthNow, calendar: utc)
precondition(snapCodexOnly.claude.nextActivation == nil && snapCodexOnly.alertTools.isEmpty && !snapCodexOnly.anyAlert)
// Fix round 1: a disabled tool is .disabled (never .alert), so the card and banner agree;
// its last-run info is kept.
precondition(snapCodexOnly.claude.state == .disabled && !snapCodexOnly.claude.isAlert)
precondition(snapCodexOnly.claude.lastRunAt != nil && snapCodexOnly.claude.lastRunOK == false)
precondition(snapCodexOnly.codex.state == .anchored)
precondition(snapCodexOnly.health("claude").state == .disabled && snapCodexOnly.health("codex").state == .anchored)
precondition(snapCodexOnly.health("bogus").state == .unknown)
precondition(snap.health("claude").isAlert == snap.anyAlert)
// Schedule off → no next activation for either tool.
let snapOff = ToolHealthEvaluator.snapshot(records: snapRecords, quota: snapQuota, installed: false,
    times: slots, activationTool: "all", now: toolHealthNow, calendar: utc)
precondition(snapOff.claude.nextActivation == nil && snapOff.codex.nextActivation == nil)

// ---- Task 4: L10n strings ----
let savedLanguage4 = UserDefaults.standard.string(forKey: "appLanguage")
AppLanguage.current = .en
precondition(L10n.healthAlert(3).contains("3"))
precondition(L10n.resetsInDays(4) == "in 4 days")
precondition(L10n.resetCredits(count: 2, expiry: nil) == "2 reset credits")
precondition(L10n.resetCredits(count: 1, expiry: iso("2026-10-05T12:00:00Z")).hasPrefix("1 reset credit · expires "))
precondition(L10n.alertBanner(tool: "Codex", failures: 3, error: "boom").contains("3"))
precondition(L10n.alertBanner(tool: "Codex", failures: 3, error: "boom").contains("boom"))
precondition(L10n.alertBanner(tool: "Codex", failures: 1, error: nil) == "Codex activation is failing")
precondition(L10n.alertBanner(tool: "Codex", failures: 0, error: "x") == "Codex activation is failing · last error: x")
precondition(L10n.healthDisabled == "Disabled")
precondition(L10n.resetsInDays(0) == "today" && L10n.resetsInDays(1) == "in 1 day")
// Fixed-format stamps: noon UTC is the same calendar day in every zone from -11 to +11;
// expected parts come from the (current-zone) calendar so the check is zone-independent.
let stampDate = iso("2026-10-03T12:00:00Z")
let stampParts = Calendar.current.dateComponents([.month, .day, .hour, .minute, .weekday], from: stampDate)
let stampClock = String(format: "%02d:%02d", stampParts.hour!, stampParts.minute!)
let stampMD = String(format: "%02d-%02d", stampParts.month!, stampParts.day!)
let enWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
let zhWeekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
precondition(L10n.weekdayStamp(stampDate) == "\(stampMD) \(enWeekdays[stampParts.weekday! - 1]) \(stampClock)")
precondition(L10n.resetAtClock(stampDate) == "resets \(stampClock)")
precondition(L10n.resetCredits(count: 1, expiry: stampDate) == "1 reset credit · expires \(stampMD)")
precondition(L10n.windowRunning == "Weekly window running")
precondition(L10n.resetsIn(toolHealthNow.addingTimeInterval(3 * 3600 + 60), now: toolHealthNow) == "resets in 3h")
AppLanguage.current = .zh
precondition(L10n.healthAlert(3).contains("3"))
precondition(L10n.resetsInDays(4) == "4 天后")
precondition(L10n.resetCredits(count: 1, expiry: nil) == "重置券 ×1")
precondition(L10n.resetCredits(count: 1, expiry: iso("2026-10-05T12:00:00Z")).hasSuffix(" 过期"))
precondition(L10n.plannedSkip == "按计划跳过" && L10n.quotaSkip == "额度跳过")
precondition(L10n.healthDisabled == "未启用")
precondition(L10n.resetsInDays(0) == "今天" && L10n.resetsInDays(1) == "1 天后")
precondition(L10n.weekdayStamp(stampDate) == "\(stampMD) \(zhWeekdays[stampParts.weekday! - 1]) \(stampClock)")
precondition(L10n.resetAtClock(stampDate) == "\(stampClock) 重置")
precondition(L10n.resetCredits(count: 2, expiry: stampDate) == "重置券 ×2 · \(stampMD) 过期")
// resetPassed: the engine flag wins; otherwise a blank window whose reset is in the past.
let flagged = try! JSONDecoder().decode(ActivationState.QuotaWindow.self,
    from: Data(#"{"used_percent":null,"remaining_percent":null,"resets_at":"2099-01-01T00:00:00Z","reset_passed":true}"#.utf8))
precondition(flagged.resetPassed == true && flagged.hasResetPassed(now: toolHealthNow))
precondition(win(nil, "2026-09-26T00:00:00Z").hasResetPassed(now: toolHealthNow))
precondition(!win(40, "2026-09-26T00:00:00Z").hasResetPassed(now: toolHealthNow), "a live percent is not a passed reset")
precondition(!win(nil, "2026-10-26T00:00:00Z").hasResetPassed(now: toolHealthNow))
precondition(L10n.resetsIn(toolHealthNow.addingTimeInterval(3 * 3600 + 60), now: toolHealthNow) == "3 小时后重置")
precondition(L10n.resetsInShort(toolHealthNow.addingTimeInterval(3 * 3600 + 60), now: toolHealthNow) == "3 小时后")
if let savedLanguage4 {
    UserDefaults.standard.set(savedLanguage4, forKey: "appLanguage")
} else {
    UserDefaults.standard.removeObject(forKey: "appLanguage")
}

// ---- Task 5 fix 1: background alert re-check ----
// Staleness alone flips the alert: last success at 07:00, schedule on — fine an hour later,
// alerting once >24h pass with no new success (records unchanged, only `now` moves).
// Exactly the app's decision (`applyAlert`): snapshot(...).anyAlert.
func alertDecision(records: [UsageRecord], quota: [String: ActivationState.ToolQuota], installed: Bool,
                   times: [String], activationTool: String, now: Date) -> Bool {
    ToolHealthEvaluator.snapshot(records: records, quota: quota, installed: installed, times: times,
                                 activationTool: activationTool, now: now).anyAlert
}
let staleRecords = [rec("2026-09-26 07:00:05 UTC", "claude", ok: true)]
let staleBase = iso("2026-09-26T07:00:05Z")
precondition(!alertDecision(records: staleRecords, quota: [:], installed: true, times: slots,
    activationTool: "claude", now: staleBase.addingTimeInterval(3600)))
precondition(alertDecision(records: staleRecords, quota: [:], installed: true, times: slots,
    activationTool: "claude", now: staleBase.addingTimeInterval(25 * 3600)))
// Disabled tool never alerts; schedule off → no staleness alert.
precondition(!alertDecision(records: staleRecords, quota: [:], installed: true, times: slots,
    activationTool: "codex", now: staleBase.addingTimeInterval(25 * 3600)))
precondition(!alertDecision(records: staleRecords, quota: [:], installed: false, times: slots,
    activationTool: "claude", now: staleBase.addingTimeInterval(25 * 3600)))
// Two consecutive failures alert regardless of time.
let twoFails = [rec("2026-09-26 07:00:05 UTC", "codex", ok: false), rec("2026-09-26 12:00:05 UTC", "codex", ok: false)]
precondition(alertDecision(records: twoFails, quota: [:], installed: true, times: slots,
    activationTool: "codex", now: staleBase.addingTimeInterval(6 * 3600)))
// One-shot re-check: earliest next activation + run timeout + margin; nil with nothing scheduled.
let recheckSnap = ToolHealthEvaluator.snapshot(records: [], quota: [:], installed: true, times: slots,
    activationTool: "all", now: toolHealthNow, calendar: utc)
let earliestNext = [recheckSnap.claude.nextActivation, recheckSnap.codex.nextActivation].compactMap { $0 }.min()!
precondition(recheckSnap.recheckAt(timeoutSeconds: 120) == earliestNext.addingTimeInterval(180))
precondition(recheckSnap.recheckAt(timeoutSeconds: 300, margin: 0) == earliestNext.addingTimeInterval(300))
let offSnap = ToolHealthEvaluator.snapshot(records: [], quota: [:], installed: false, times: slots,
    activationTool: "all", now: toolHealthNow, calendar: utc)
precondition(offSnap.recheckAt(timeoutSeconds: 120) == nil)
// Off-main reader parses usage.jsonl with the LogStore decoding (snake_case keys).
let readerRoot = FileManager.default.temporaryDirectory.appendingPathComponent("stoker-reader-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: readerRoot.appendingPathComponent("logs"), withIntermediateDirectories: true)
try! #"{"timestamp":"2026-09-26 07:00:05 UTC","tool":"codex","ok":false,"superseded_by_fallback":true}"#
    .appending("\n\n")
    .write(to: readerRoot.appendingPathComponent("logs/usage.jsonl"), atomically: true, encoding: .utf8)
let readBack = LogStore.readUsage(root: readerRoot)
precondition(readBack.count == 1 && readBack[0].supersededByFallback == true)
precondition(LogStore.readUsage(root: readerRoot.appendingPathComponent("missing")).isEmpty)
try? FileManager.default.removeItem(at: readerRoot)

// ---- Task 5: menu quota lines ----
let savedLanguage5 = UserDefaults.standard.string(forKey: "appLanguage")
for lang in [AppLanguage.en, .zh] {
    AppLanguage.current = lang
    let line = L10n.menuQuotaLine(tool: "Codex", windowLabel: L10n.weeklyShort, remaining: "1%", reset: "10-03")
    precondition(line.contains("Codex") && line.contains("1%") && line.contains("10-03") && line.contains(L10n.weeklyShort))
    let noReset = L10n.menuQuotaLine(tool: "Claude", windowLabel: L10n.fiveHourShort, remaining: "93%", reset: nil)
    precondition(noReset == "Claude 5h 93%", "no reset → no trailing segment")
    precondition(L10n.monthDay(stampDate) == stampMD)
}
AppLanguage.current = .en
precondition(L10n.menuQuotaLine(tool: "Claude", windowLabel: "5h", remaining: "93%", reset: "00:10") == "Claude 5h 93% · resets 00:10")
AppLanguage.current = .zh
precondition(L10n.menuQuotaLine(tool: "Codex", windowLabel: "周", remaining: "1%", reset: "10-03") == "Codex 周 1% · 10-03 重置")
if let savedLanguage5 {
    UserDefaults.standard.set(savedLanguage5, forKey: "appLanguage")
} else {
    UserDefaults.standard.removeObject(forKey: "appLanguage")
}

// ---- Task 6: Claude/Codex settings card L10n strings ----
let savedLanguage6 = UserDefaults.standard.string(forKey: "appLanguage")
AppLanguage.current = .en
let enStrings6 = [
    L10n.claudeSettingsTitle, L10n.codexSettingsTitle, L10n.codexModelLabel, L10n.codexModelHelp,
    L10n.codexAutoUpdateLabel, L10n.codexAutoUpdateHelp, L10n.codexFallbackLabel, L10n.codexFallbackHelp,
    L10n.codexIdleOnlyLabel, L10n.codexIdleOnlyHelp
]
precondition(enStrings6.allSatisfy { !$0.isEmpty }, "every new settings-card string must be non-empty in EN")
AppLanguage.current = .zh
let zhStrings6 = [
    L10n.claudeSettingsTitle, L10n.codexSettingsTitle, L10n.codexModelLabel, L10n.codexModelHelp,
    L10n.codexAutoUpdateLabel, L10n.codexAutoUpdateHelp, L10n.codexFallbackLabel, L10n.codexFallbackHelp,
    L10n.codexIdleOnlyLabel, L10n.codexIdleOnlyHelp
]
precondition(zhStrings6.allSatisfy { !$0.isEmpty }, "every new settings-card string must be non-empty in ZH")
precondition(zip(enStrings6, zhStrings6).allSatisfy { $0 != $1 }, "every new settings-card string must differ between EN and ZH")
// Exact ZH copy from the brief.
precondition(L10n.codexModelHelp == "默认 \(AppSettings.defaultCodexModel)；设为 default 交给 Codex CLI")
precondition(L10n.codexAutoUpdateHelp == "在真正运行 Codex 前自动 codex update，每 24 小时最多一次")
precondition(L10n.codexFallbackHelp == "模型被下架时自动换可用模型重试")
precondition(L10n.codexIdleOnlyHelp == "窗口已在计时时跳过（有 5 小时窗口时看 5 小时，否则看周窗口），每个窗口只激活一次")
if let savedLanguage6 {
    UserDefaults.standard.set(savedLanguage6, forKey: "appLanguage")
} else {
    UserDefaults.standard.removeObject(forKey: "appLanguage")
}

// ---- Final fix wave ----
// I-1: Codex nextActivation follows the toggles that actually make the engine skip.
// Anchored window, preflight on + idle-only off → the engine runs at the next slot.
let xIdleOff = ToolHealthEvaluator.codex(records: [rec("2026-09-26 22:56:00 UTC", "codex", ok: true)],
    weekly: win(8, "2026-10-03T22:49:45Z"), scheduleOn: true, times: slots,
    preflight: true, idleOnly: false, now: toolHealthNow, calendar: utc)
precondition(xIdleOff.state == .anchored, "window state is informational, independent of the toggles")
precondition(xIdleOff.nextActivation == iso("2026-09-27T07:00:00Z"), "idle-only off → no postponement")
// Anchored window, preflight off → nothing skips.
precondition(ToolHealthEvaluator.codex(records: [rec("2026-09-26 22:56:00 UTC", "codex", ok: true)],
    weekly: win(8, "2026-10-03T22:49:45Z"), scheduleOn: true, times: slots,
    preflight: false, idleOnly: true, now: toolHealthNow, calendar: utc).nextActivation == iso("2026-09-27T07:00:00Z"))
// Exhausted window: postponed past the reset whenever preflight is on (idle-only irrelevant)...
let xExh = ToolHealthEvaluator.codex(records: [rec("2026-09-26 22:56:00 UTC", "codex", ok: true)],
    weekly: win(100, "2026-10-03T22:49:45Z"), scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(xExh.state == .exhausted && xExh.nextActivation == iso("2026-10-04T07:00:00Z"))
precondition(ToolHealthEvaluator.codex(records: [], weekly: win(100, "2026-10-03T22:49:45Z"),
    scheduleOn: true, times: slots, preflight: true, idleOnly: false,
    now: toolHealthNow, calendar: utc).nextActivation == iso("2026-10-04T07:00:00Z"))
// ...and not at all with preflight off.
let xExhNoPre = ToolHealthEvaluator.codex(records: [], weekly: win(100, "2026-10-03T22:49:45Z"),
    scheduleOn: true, times: slots, preflight: false, idleOnly: false, now: toolHealthNow, calendar: utc)
precondition(xExhNoPre.state == .exhausted && xExhNoPre.nextActivation == iso("2026-09-27T07:00:00Z"))
// M-8: exhausted uses the engine threshold (remaining <= QUOTA_EXHAUSTED_THRESHOLD_PERCENT).
precondition(ToolHealthEvaluator.codex(records: [], weekly: win(97, "2026-10-03T22:49:45Z"),
    scheduleOn: true, times: slots, exhaustedThreshold: 5, now: toolHealthNow, calendar: utc).state == .exhausted)
precondition(ToolHealthEvaluator.codex(records: [], weekly: win(97, "2026-10-03T22:49:45Z"),
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .anchored)
// Config decode: idle-only defaults to true and the threshold to 0 when absent.
func decodeConfig(_ json: String) -> ActivationState.Config {
    try! JSONDecoder().decode(ActivationState.Config.self, from: Data(json.utf8))
}
let cfgBase = #""activation_tool":"all","codex_model":"m","enable_status_snapshots":true,"enable_quota_preflight":true,"quota_preflight_on_unknown":"allow""#
let cfgDefault = decodeConfig("{\(cfgBase)}")
precondition(cfgDefault.codexActivateOnlyWhenIdle && cfgDefault.quotaExhaustedThresholdPercent == 0)
let cfgSet = decodeConfig("{\(cfgBase),\"codex_activate_only_when_idle\":false,\"quota_exhausted_threshold_percent\":5}")
precondition(!cfgSet.codexActivateOnlyWhenIdle && cfgSet.quotaExhaustedThresholdPercent == 5)
// The state-driven snapshot wires the config toggles through.
func stateJSON(idle: Bool, preflight: Bool) -> ActivationState {
    let json = """
    {"root":"/r","label":"l","installed":true,"running":false,"schedule":{"times":["07:00","12:00","17:00","22:00"]},
     "config":{"activation_tool":"codex","codex_model":"m","enable_status_snapshots":true,
       "enable_quota_preflight":\(preflight),"quota_preflight_on_unknown":"allow",
       "quota_exhausted_threshold_percent":0,"codex_activate_only_when_idle":\(idle)},
     "keep_awake":{"mode":"off","seconds":0},
     "quota":{"codex":{"ok":true,"weekly":{"used_percent":8,"remaining_percent":92,"resets_at":"2099-10-03T22:49:45Z"}}}}
    """
    return try! JSONDecoder().decode(ActivationState.self, from: Data(json.utf8))
}
let stateNow = Date()
let plainNext = ScheduleFormatter.nextFire(times: slots, now: stateNow)
precondition(ToolHealthEvaluator.snapshot(records: [], state: stateJSON(idle: false, preflight: true), now: stateNow)
    .codex.nextActivation == plainNext)
precondition(ToolHealthEvaluator.snapshot(records: [], state: stateJSON(idle: true, preflight: false), now: stateNow)
    .codex.nextActivation == plainNext)
precondition(ToolHealthEvaluator.snapshot(records: [], state: stateJSON(idle: true, preflight: true), now: stateNow)
    .codex.nextActivation! > iso("2099-10-03T22:49:45Z"))

// I-2: a preflight skip proves the scheduler is running, so it counts against staleness.
// Weekly exhausted: last real success 4 days ago, then only quota skips every slot → not alert.
var skipDays: [UsageRecord] = [rec("2026-09-23 22:00:05 UTC", "claude", ok: true)]
for day in ["24", "25", "26"] {
    for slot in ["07", "12", "17", "22"] {
        skipDays.append(rec("2026-09-\(day) \(slot):00:05 UTC", "claude", skipped: true))
    }
}
let cSkipOnly = ToolHealthEvaluator.claude(records: skipDays, scheduleOn: true, times: slots,
                                           now: toolHealthNow, calendar: utc)
precondition(cSkipOnly.state == .ok && !cSkipOnly.isAlert, "skips within 24h keep Claude out of alert")
// No success and no skip in the last 24h (both older), schedule on → alert.
precondition(ToolHealthEvaluator.claude(records: [
    rec("2026-09-25 12:00:00 UTC", "claude", ok: true),
    rec("2026-09-25 17:00:05 UTC", "claude", skipped: true)],
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .alert)
// M-10: a single failure with no success in 24h → alert (staleness outranks warning).
precondition(ToolHealthEvaluator.claude(records: [
    rec("2026-09-25 17:00:00 UTC", "claude", ok: true),
    rec("2026-09-26 22:00:00 UTC", "claude", ok: false)],
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .alert)
// ...but the same failure right after a recent skip is only a warning.
precondition(ToolHealthEvaluator.claude(records: [
    rec("2026-09-25 17:00:00 UTC", "claude", ok: true),
    rec("2026-09-26 17:00:05 UTC", "claude", skipped: true),
    rec("2026-09-26 22:00:00 UTC", "claude", ok: false)],
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .warning)
// Schedule on with no times → no slot is due, so no staleness alert and no next activation.
let cNoTimes = ToolHealthEvaluator.claude(records: [rec("2026-09-20 12:00:00 UTC", "claude", ok: true)],
    scheduleOn: true, times: [], now: toolHealthNow, calendar: utc)
precondition(cNoTimes.state == .ok && cNoTimes.nextActivation == nil)

// Per-tool staleness: Claude's own times + days decide whether a slot was missed.
let mondayOnly = ["mon"]   // toolHealthNow = 2026-09-27 00:00 UTC, a Sunday
precondition(utc.component(.weekday, from: toolHealthNow) == 1)
// Weekly-only (Mon 07:00), last run Thu 09-24 07:00 — 3 days ago, no Monday slot missed yet → no alert.
let cWeekly = ToolHealthEvaluator.claude(records: [rec("2026-09-24 07:00:05 UTC", "claude", ok: true)],
    scheduleOn: true, times: ["07:00"], days: mondayOnly, now: toolHealthNow, calendar: utc)
precondition(cWeekly.state == .ok && !cWeekly.isAlert, "weekly Claude schedule is not stale between slots")
precondition(cWeekly.nextActivation == iso("2026-09-28T07:00:00Z"))
// Same history on a daily schedule → stale (>24h and slots missed).
precondition(ToolHealthEvaluator.claude(records: [rec("2026-09-24 07:00:05 UTC", "claude", ok: true)],
    scheduleOn: true, times: ["07:00"], now: toolHealthNow, calendar: utc).state == .alert)
// Weekly schedule whose Monday slot passed (+grace) with no proof → alert.
precondition(ToolHealthEvaluator.claude(records: [rec("2026-09-21 07:00:05 UTC", "claude", ok: true)],
    scheduleOn: true, times: ["07:00"], days: mondayOnly, now: iso("2026-09-28T08:30:00Z"), calendar: utc).state == .alert)
// ...but still within the grace after the slot → not yet.
precondition(ToolHealthEvaluator.claude(records: [rec("2026-09-21 07:00:05 UTC", "claude", ok: true)],
    scheduleOn: true, times: ["07:00"], days: mondayOnly, now: iso("2026-09-28T07:30:00Z"), calendar: utc).state == .ok)
// Snapshot: each tool uses its own schedule; Codex nextActivation follows Codex's times.
let perToolSnap = ToolHealthEvaluator.snapshot(records: [], quota: [:], installed: true,
    claudeSchedule: ToolSchedule(times: slots, days: []),
    codexSchedule: ToolSchedule(times: ["09:15"], days: ["tue"]),
    activationTool: "all", now: toolHealthNow, calendar: utc)
precondition(perToolSnap.claude.nextActivation == iso("2026-09-27T07:00:00Z"))
precondition(perToolSnap.codex.nextActivation == iso("2026-09-29T09:15:00Z"))
// The state-driven snapshot pulls the per-tool schedules out of app-status JSON.
let perToolState = try! JSONDecoder().decode(ActivationState.self, from: Data("""
{"root":"/r","label":"l","installed":true,"running":false,
 "schedule":{"times":["07:00","12:00"],"claude":{"times":["12:00"],"days":[]},"codex":{"times":["07:00"],"days":["wed"]}},
 "config":{"activation_tool":"all","codex_model":"m","enable_status_snapshots":true,
   "enable_quota_preflight":true,"quota_preflight_on_unknown":"allow"},
 "keep_awake":{"mode":"off","seconds":0},"quota":{}}
""".utf8))
let perToolStateSnap = ToolHealthEvaluator.snapshot(records: [], state: perToolState, now: stateNow)
precondition(perToolStateSnap.claude.nextActivation == ScheduleFormatter.nextFire(times: ["12:00"], now: stateNow))
precondition(perToolStateSnap.codex.nextActivation == ScheduleFormatter.nextFire(times: ["07:00"], days: ["wed"], now: stateNow))

// L10n schedule strings.
let savedLanguageSched = UserDefaults.standard.string(forKey: "appLanguage")
AppLanguage.current = .en
precondition(L10n.scheduleNeedsReinstall.hasPrefix("Schedule needs updating"))
precondition(L10n.everyDay == "Every day" && L10n.weekdayShort("mon") == "Mon" && L10n.weekdayShort("sun") == "Sun")
precondition(L10n.toolScheduleLine(tool: "Claude", times: slots, days: []) == "Claude 07·12·17·22")
precondition(L10n.toolScheduleLine(tool: "Codex", times: ["07:30"], days: ["mon", "thu"]) == "Codex 07:30 (Mon, Thu)")
precondition(L10n.toolScheduleLine(tool: "Codex", times: ["07:00", "12:30"], days: [], compact: false) == "Codex 07:00, 12:30")
AppLanguage.current = .zh
precondition(L10n.scheduleNeedsReinstall.hasPrefix("调度需要更新"))
precondition(L10n.everyDay == "每天" && L10n.weekdayShort("sun") == "日")
precondition(L10n.toolScheduleLine(tool: "Codex", times: ["07:00"], days: ["mon", "thu"]) == "Codex 07（周一、四）")
if let savedLanguageSched {
    UserDefaults.standard.set(savedLanguageSched, forKey: "appLanguage")
} else {
    UserDefaults.standard.removeObject(forKey: "appLanguage")
}

// M-3: Codex bools parse like the engine — absent (or empty) → on, otherwise only "1" is on.
let s2 = AppSettings(values: ["CODEX_AUTO_UPDATE": "yes", "CODEX_MODEL_FALLBACK": "true", "CODEX_ACTIVATE_ONLY_WHEN_IDLE": ""])
precondition(!s2.codexAutoUpdate && !s2.codexModelFallback && s2.codexActivateOnlyWhenIdle)
precondition(AppSettings(values: ["CODEX_AUTO_UPDATE": "1"]).codexAutoUpdate)

// M-2: a short-circuited reload (files unchanged) still re-applies the date cutoff, so the
// "today" filter rolls over at midnight.
MainActor.assumeIsolated {
    let rollRoot = FileManager.default.temporaryDirectory.appendingPathComponent("stoker-roll-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: rollRoot.appendingPathComponent("logs"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rollRoot) }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
    let rollNow = Date()
    try! #"{"timestamp":"\#(fmt.string(from: rollNow))","tool":"claude","ok":true}"#
        .write(to: rollRoot.appendingPathComponent("logs/usage.jsonl"), atomically: true, encoding: .utf8)
    let rollStore = LogStore(root: rollRoot)
    rollStore.dateRange = .today
    rollStore.load(now: rollNow)
    precondition(rollStore.totalRuns == 1)
    rollStore.load(now: rollNow.addingTimeInterval(2 * 86400))   // files unchanged, two days later
    precondition(rollStore.totalRuns == 0, "the today cutoff must roll over without a file change")
}

// ---- Plan-aware windows: `limits` decoding + Codex health on a 5h-gated plan ----
func decodeState(_ extra: String, quota: String = "{}") -> ActivationState {
    let json = """
    {"root":"/r","label":"l","installed":true,"running":false,"schedule":{"times":["07:00"]},
     "config":{"activation_tool":"all","codex_model":"m","enable_status_snapshots":true,
       "enable_quota_preflight":true,"quota_preflight_on_unknown":"allow"},
     "keep_awake":{"mode":"off","seconds":0},"quota":\(quota)\(extra)}
    """
    return try! JSONDecoder().decode(ActivationState.self, from: Data(json.utf8))
}
let limitsState = decodeState(#","limits":{"claude":{"profile":"weekly_only","session_minutes":null,"weekly_reset":"fixed","plan":"max","recommended":{"times":[],"days":[],"reason":"not_needed"}},"codex":{"profile":"session_weekly","session_minutes":300,"weekly_reset":"on_first_use","plan":"plus","recommended":{"times":["07:00","12:00","17:00","22:00"],"days":[],"reason":"session_window"}}}"#)
precondition(limitsState.limits?.claude?.profile == .weeklyOnly && limitsState.limits?.claude?.plan == "max")
precondition(limitsState.limits?.claude?.sessionMinutes == nil && limitsState.limits?.claude?.weeklyReset == "fixed")
precondition(limitsState.limits?.claude?.recommended == .init(times: [], days: [], reason: "not_needed"))
precondition(limitsState.limits?.codex?.sessionMinutes == 300 && limitsState.limits?.codex?.recommended?.times.count == 4)
precondition(limitsState.windowProfile("claude") == .weeklyOnly && limitsState.windowProfile("codex") == .sessionWeekly)
precondition(!ActivationState.hasSessionWindow("claude", in: limitsState))
precondition(ActivationState.hasSessionWindow("codex", in: limitsState))
// Older engine: no `limits` (or null) → decoded, profile derived from the quota snapshot.
let noLimits = decodeState("", quota: #"{"claude":{"ok":true,"five_hour":{"used_percent":null,"remaining_percent":null,"resets_at":null},"weekly":{"used_percent":14,"remaining_percent":86}},"codex":{"ok":true,"five_hour":{"used_percent":3,"remaining_percent":97,"resets_at":"2026-11-11T05:00:00Z"},"weekly":{"used_percent":8,"remaining_percent":92}}}"#)
precondition(noLimits.limits == nil)
precondition(noLimits.windowProfile("claude") == .weeklyOnly && noLimits.windowProfile("codex") == .sessionWeekly)
precondition(ActivationState.headlineWindow("claude", in: noLimits)?.remainingPercent == 86, "no 5h → weekly headline")
precondition(ActivationState.headlineWindow("codex", in: noLimits)?.remainingPercent == 97, "5h present → 5h headline")
precondition(decodeState(#","limits":null"#).limits == nil)
// Malformed shapes never fail the decode; an "unknown"/unrecognized profile falls back to the quota.
precondition(decodeState(#","limits":"bad""#).limits == nil)
let oddLimits = decodeState(#","limits":{"claude":{"profile":"mystery","recommended":{"times":"x"}},"codex":7}"#,
                            quota: #"{"claude":{"ok":true,"five_hour":{"used_percent":0},"weekly":{"used_percent":1}}}"#)
precondition(oddLimits.limits?.claude?.profile == nil && oddLimits.limits?.codex == nil)
precondition(oddLimits.limits?.claude?.recommended?.times == [])
precondition(oddLimits.windowProfile("claude") == .sessionWeekly && oddLimits.windowProfile("codex") == .unknown)
precondition(decodeState(#","limits":{"codex":{"profile":"unknown"}}"#, quota: #"{"codex":{"ok":true,"five_hour":null,"weekly":{"used_percent":1}}}"#)
    .windowProfile("codex") == .weeklyOnly)
// No state at all: display defaults.
precondition(ActivationState.hasSessionWindow("claude", in: nil) && !ActivationState.hasSessionWindow("codex", in: nil))

// Recommendation → form: matches compares normalized; apply fills times + days, never an empty list.
var recSettings = AppSettings(values: ["CODEX_SCHEDULE_TIMES": "12:00,7:00", "CODEX_SCHEDULE_DAYS": "mon"])
let sessionRec = ActivationState.Recommendation(times: ["07:00", "12:00", "17:00", "22:00"], days: [], reason: "session_window")
precondition(!recSettings.matches(sessionRec, tool: "codex"))
recSettings.apply(sessionRec, tool: "codex")
precondition(recSettings.codexScheduleTimes == ["07:00", "12:00", "17:00", "22:00"] && recSettings.codexScheduleDays == [])
precondition(recSettings.matches(sessionRec, tool: "codex"))
precondition(recSettings.matches(.init(times: ["22:00", "7:00", "12:00", "17:00"],
                                       days: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"], reason: nil), tool: "codex"))
let claudeBefore = recSettings.claudeScheduleTimes
recSettings.apply(.init(times: [], days: [], reason: "not_needed"), tool: "claude")
precondition(recSettings.claudeScheduleTimes == claudeBefore, "an empty recommendation never clears the schedule")

// Codex health on a plan with a 5h window gates on the 5h window (engine: shortest window).
// now = 00:00 UTC; slots 07/12/17/22.
let five = { (used: Double, reset: String) in win(used, reset) }
// Idle 5h (used 0, no run this 5h cycle) while the weekly is anchored → pending, next = next slot.
let x5Idle = ToolHealthEvaluator.codex(records: [rec("2026-09-26 18:00:00 UTC", "codex", ok: true)],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(0, "2026-09-27T05:00:00Z"), hasSession: true,
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(x5Idle.state == .pending, "a run 6h ago doesn't anchor a 5h window")
precondition(x5Idle.nextActivation == iso("2026-09-27T07:00:00Z") && x5Idle.stateWindowIsSession)
// The same rows evaluated weekly-only stay anchored → unchanged weekly behaviour.
let x5AsWeekly = ToolHealthEvaluator.codex(records: [rec("2026-09-26 18:00:00 UTC", "codex", ok: true)],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(0, "2026-09-27T05:00:00Z"), hasSession: false,
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(x5AsWeekly.state == .anchored && x5AsWeekly.nextActivation == iso("2026-10-04T07:00:00Z"))
precondition(!x5AsWeekly.stateWindowIsSession)
// Anchored 5h (used > 0, reset ahead) → anchored; idle-only → next slot after the 5h reset.
let x5Anch = ToolHealthEvaluator.codex(records: [],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(12, "2026-09-27T09:30:00Z"), hasSession: true,
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(x5Anch.state == .anchored && x5Anch.stateWindowIsSession)
precondition(x5Anch.nextActivation == iso("2026-09-27T12:00:00Z"))
// Anchored by a run inside this 5h cycle even at used 0.
precondition(ToolHealthEvaluator.codex(records: [rec("2026-09-26 23:00:00 UTC", "codex", ok: true)],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(0, "2026-09-27T04:00:00Z"), hasSession: true,
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .anchored)
// Idle-only off → anchored but runs at the next slot.
precondition(ToolHealthEvaluator.codex(records: [],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(12, "2026-09-27T09:30:00Z"), hasSession: true,
    scheduleOn: true, times: slots, idleOnly: false, now: toolHealthNow, calendar: utc).nextActivation == iso("2026-09-27T07:00:00Z"))
// 5h exhausted → exhausted (session copy), postponed past the 5h reset.
let x5Exh = ToolHealthEvaluator.codex(records: [],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(100, "2026-09-27T09:30:00Z"), hasSession: true,
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(x5Exh.state == .exhausted && x5Exh.stateWindowIsSession && x5Exh.nextActivation == iso("2026-09-27T12:00:00Z"))
// Weekly exhausted while the 5h is idle → exhausted (weekly copy), postponed past the weekly reset.
let x5WkExh = ToolHealthEvaluator.codex(records: [],
    weekly: win(100, "2026-10-03T22:49:45Z"), fiveHour: five(0, "2026-09-27T05:00:00Z"), hasSession: true,
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(x5WkExh.state == .exhausted && !x5WkExh.stateWindowIsSession)
precondition(x5WkExh.nextActivation == iso("2026-10-04T07:00:00Z"))
// 5h reset passed → pending.
precondition(ToolHealthEvaluator.codex(records: [],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(40, "2026-09-26T23:00:00Z"), hasSession: true,
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .pending)
// The engine's gate verdict overrides the used/ran heuristic: idle 5h windows often report used ≥ 1.
let x5UsedIdle = ToolHealthEvaluator.codex(records: [],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(1, "2026-09-27T05:00:00Z"), hasSession: true,
    engineGateActive: false, scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(x5UsedIdle.state == .pending && x5UsedIdle.nextActivation == iso("2026-09-27T07:00:00Z"))
// Without the verdict (older engine) the same row falls back to the heuristic → anchored.
precondition(ToolHealthEvaluator.codex(records: [],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(1, "2026-09-27T05:00:00Z"), hasSession: true,
    scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .anchored)
// gate.active with used 0 and no run → anchored, postponed past the 5h reset.
let x5GateOn = ToolHealthEvaluator.codex(records: [],
    weekly: win(8, "2026-10-03T22:49:45Z"), fiveHour: five(0, "2026-09-27T09:30:00Z"), hasSession: true,
    engineGateActive: true, scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
precondition(x5GateOn.state == .anchored && x5GateOn.nextActivation == iso("2026-09-27T12:00:00Z"))
// Weekly-only with gate.active=false and used 8 → pending (engine verdict), exhaustion still wins.
precondition(ToolHealthEvaluator.codex(records: [], weekly: win(8, "2026-10-03T22:49:45Z"),
    engineGateActive: false, scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .pending)
precondition(ToolHealthEvaluator.codex(records: [], weekly: win(100, "2026-10-03T22:49:45Z"),
    engineGateActive: false, scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc).state == .exhausted)
// Decoding: gate present (codex), null (claude), malformed → nil; and the state snapshot uses it.
let gateState = decodeState(#","limits":{"claude":{"profile":"weekly_only","gate":null},"codex":{"profile":"session_weekly","session_minutes":300,"gate":{"window":"five_hour","active":false}}}"#,
    quota: #"{"codex":{"ok":true,"five_hour":{"used_percent":1,"remaining_percent":99,"resets_at":"2099-01-01T05:00:00Z"},"weekly":{"used_percent":8,"remaining_percent":92,"resets_at":"2099-10-03T22:49:45Z"}}}"#)
precondition(gateState.limits?.codex?.gate == .init(window: "five_hour", active: false) && gateState.limits?.claude?.gate == nil)
precondition(decodeState(#","limits":{"codex":{"gate":{"window":1}}}"#).limits?.codex?.gate == nil)
let gateSnap = ToolHealthEvaluator.snapshot(records: [], state: gateState, now: toolHealthNow).codex
precondition(gateSnap.state == .pending && gateSnap.nextActivation! < iso("2026-09-29T00:00:00Z"),
             "engine says idle → next slot, not after the 5h reset")

// Resets-soon wait: a slot within CODEX_RESET_WAIT_MAX_SECONDS before the anchored gate's reset
// still sends (the engine waits it out). Slots 07/12/17/22 UTC, now 00:00.
func x5Reset(_ reset: String, used: Double = 12, wait: TimeInterval = 300) -> ToolHealth {
    ToolHealthEvaluator.codex(records: [], weekly: win(8, "2026-10-03T22:49:45Z"),
        fiveHour: five(used, reset), hasSession: true, engineGateActive: used < 100 ? true : nil,
        resetWaitMax: wait, scheduleOn: true, times: slots, now: toolHealthNow, calendar: utc)
}
let rSoon = x5Reset("2026-09-27T12:00:10Z")
precondition(rSoon.state == .anchored && rSoon.nextActivation == iso("2026-09-27T12:00:00Z"), "reset 10s after the slot → that slot sends")
precondition(x5Reset("2026-09-27T12:06:40Z").nextActivation == iso("2026-09-27T17:00:00Z"), "400s > wait → following slot")
precondition(x5Reset("2026-09-27T12:00:10Z", wait: 0).nextActivation == iso("2026-09-27T17:00:00Z"), "wait 0 → skip as before")
let rExh = x5Reset("2026-09-27T12:00:10Z", used: 100)
precondition(rExh.state == .exhausted && rExh.nextActivation == iso("2026-09-27T17:00:00Z"), "exhaustion never waits")
// Weekly-only, reset far away: unchanged.
precondition(ToolHealthEvaluator.codex(records: [rec("2026-09-26 22:56:00 UTC", "codex", ok: true)],
    weekly: win(8, "2026-10-03T22:49:45Z"), resetWaitMax: 300, scheduleOn: true, times: slots,
    now: toolHealthNow, calendar: utc).nextActivation == iso("2026-10-04T07:00:00Z"))
// Config: missing → 300, explicit 0 kept; the state snapshot passes it through.
precondition(decodeConfig("{\(cfgBase)}").codexResetWaitMaxSeconds == 300)
precondition(decodeConfig("{\(cfgBase),\"codex_reset_wait_max_seconds\":0}").codexResetWaitMaxSeconds == 0)
// The state path runs on Calendar.current, so the reset sits 10 s after the next local 12:00 slot.
let waitNow = iso("2099-01-01T00:00:00Z")
let localSlot = ScheduleFormatter.nextFire(times: ["12:00"], now: waitNow)!
let waitReset = ISO8601DateFormatter().string(from: localSlot.addingTimeInterval(10))
func waitState(_ wait: String) -> ActivationState {
    let json = """
    {"root":"/r","label":"l","installed":true,"running":false,"schedule":{"times":["12:00"]},
     "config":{"activation_tool":"codex","codex_model":"m","enable_status_snapshots":true,
       "enable_quota_preflight":true,"quota_preflight_on_unknown":"allow"\(wait)},
     "keep_awake":{"mode":"off","seconds":0},
     "limits":{"codex":{"profile":"session_weekly","session_minutes":300,"gate":{"window":"five_hour","active":true}}},
     "quota":{"codex":{"ok":true,"five_hour":{"used_percent":12,"remaining_percent":88,"resets_at":"\(waitReset)"},"weekly":{"used_percent":8,"remaining_percent":92,"resets_at":"2099-01-09T00:00:00Z"}}}}
    """
    return try! JSONDecoder().decode(ActivationState.self, from: Data(json.utf8))
}
precondition(ToolHealthEvaluator.snapshot(records: [], state: waitState(""), now: waitNow).codex.nextActivation == localSlot,
             "default 300 s wait → the slot right before the reset sends")
precondition(ToolHealthEvaluator.snapshot(records: [], state: waitState(#","codex_reset_wait_max_seconds":0"#), now: waitNow)
    .codex.nextActivation == localSlot.addingTimeInterval(86400), "wait 0 → the following day's slot")

// The snapshot wires the profile from quota (no limits) and from `limits`.
let plusQuota: [String: ActivationState.ToolQuota] = ["codex": decodeQuota(#"{"ok":true,"five_hour":{"used_percent":12,"remaining_percent":88,"resets_at":"2026-09-27T09:30:00Z"},"weekly":{"used_percent":8,"remaining_percent":92,"resets_at":"2026-10-03T22:49:45Z"}}"#)]
let plusSnap = ToolHealthEvaluator.snapshot(records: [], quota: plusQuota, installed: true,
    claudeSchedule: ToolSchedule(times: slots, days: []), codexSchedule: ToolSchedule(times: slots, days: []),
    activationTool: "all", now: toolHealthNow, calendar: utc)
precondition(plusSnap.codex.state == .anchored && plusSnap.codex.nextActivation == iso("2026-09-27T12:00:00Z"))
let plusAsWeekly = ToolHealthEvaluator.snapshot(records: [], quota: plusQuota, installed: true,
    claudeSchedule: ToolSchedule(times: slots, days: []), codexSchedule: ToolSchedule(times: slots, days: []),
    activationTool: "all", codexProfile: .weeklyOnly, now: toolHealthNow, calendar: utc)
precondition(plusAsWeekly.codex.nextActivation == iso("2026-10-04T07:00:00Z"), "limits profile wins over the quota")
// The app's state-driven snapshot passes the `limits` profile through: weekly_only limits on a
// row that still carries a 5h window gates on weekly (reset 2099 → next fire after it).
let limitsGated = decodeState(#","limits":{"codex":{"profile":"weekly_only"}}"#,
    quota: #"{"codex":{"ok":true,"five_hour":{"used_percent":12,"remaining_percent":88,"resets_at":"2099-01-01T05:00:00Z"},"weekly":{"used_percent":8,"remaining_percent":92,"resets_at":"2099-10-03T22:49:45Z"}}}"#)
precondition(ToolHealthEvaluator.snapshot(records: [], state: limitsGated).codex.nextActivation! > iso("2099-10-03T22:49:45Z"))
let sessionGated = decodeState(#","limits":{"codex":{"profile":"session_weekly","session_minutes":300}}"#,
    quota: #"{"codex":{"ok":true,"five_hour":{"used_percent":12,"remaining_percent":88,"resets_at":"2099-01-01T05:00:00Z"},"weekly":{"used_percent":8,"remaining_percent":92,"resets_at":"2099-10-03T22:49:45Z"}}}"#)
let sessionNext = ToolHealthEvaluator.snapshot(records: [], state: sessionGated).codex.nextActivation!
precondition(sessionNext > iso("2099-01-01T05:00:00Z") && sessionNext < iso("2099-01-03T00:00:00Z"))

// L10n: new copy exists in both languages.
let savedLanguagePlan = UserDefaults.standard.string(forKey: "appLanguage")
AppLanguage.current = .en
precondition(L10n.detectedWindows(.sessionWeekly, plan: "Plus") == "Detected: 5-hour + weekly · Plus")
precondition(L10n.detectedWindows(.weeklyOnly, plan: nil) == "Detected: weekly only")
precondition(L10n.detectedWindows(.unknown, plan: nil) == "Windows not detected yet")
precondition(L10n.recommendation(times: ["07:00"], days: [], reason: "weekly_anchor").hasPrefix("Recommended: 07:00 — "))
precondition(L10n.healthAnchoredSession != L10n.healthAnchored && L10n.trendCodex5h == "Codex 5h")
AppLanguage.current = .zh
precondition(L10n.detectedWindows(.sessionWeekly, plan: "Max") == "检测到：5 小时 + 周 · Max")
precondition(L10n.detectedWindows(.sessionOnly, plan: nil) == "检测到：仅 5 小时窗口")
precondition(L10n.recommendation(times: ["07:00", "12:00"], days: ["mon"], reason: nil) == "推荐：07:00、12:00（周一）")
precondition(L10n.useRecommended == "套用推荐" && L10n.windowRunningSession.hasPrefix("5 小时"))
if let savedLanguagePlan {
    UserDefaults.standard.set(savedLanguagePlan, forKey: "appLanguage")
} else {
    UserDefaults.standard.removeObject(forKey: "appLanguage")
}

SWIFT

swiftc \
  "$ROOT_DIR/app/StokerMenuBar/Sources/StokerCore/StokerCore.swift" \
  "$ROOT_DIR/app/StokerMenuBar/Sources/StokerCore/FlameTicker.swift" \
  "$ROOT_DIR/app/StokerMenuBar/Sources/StokerCore/L10n.swift" \
  "$ROOT_DIR/app/StokerMenuBar/Sources/StokerCore/LogStore.swift" \
  "$ROOT_DIR/app/StokerMenuBar/Sources/StokerCore/ToolHealth.swift" \
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
