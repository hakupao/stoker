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

// Window selection: Codex is weekly-only by design (always its 7-day window);
// Claude honours the 5h/weekly picker.
let codexWeeklyQ = decodeQuota(#"{"ok":true,"five_hour":null,"weekly":{"used_percent":8,"remaining_percent":92}}"#)
precondition(ActivationState.ToolQuota.isWeeklyOnly(tool: "codex"))
precondition(!ActivationState.ToolQuota.isWeeklyOnly(tool: "claude"))
precondition(codexWeeklyQ.window(tool: "codex", preferFiveHour: true)?.remainingPercent == 92)
precondition(codexWeeklyQ.window(tool: "codex", preferFiveHour: false)?.remainingPercent == 92)
let bothQ = decodeQuota(#"{"ok":true,"five_hour":{"remaining_percent":40},"weekly":{"remaining_percent":70}}"#)
// Even a legacy Codex row that still carries a 5h window shows weekly.
precondition(bothQ.window(tool: "codex", preferFiveHour: true)?.remainingPercent == 70)
precondition(bothQ.window(tool: "claude", preferFiveHour: true)?.remainingPercent == 40)
precondition(bothQ.window(tool: "claude", preferFiveHour: false)?.remainingPercent == 70)
precondition(decodeQuota(#"{"ok":true}"#).window(tool: "codex", preferFiveHour: true) == nil)

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

// Skip-reason labels: the Codex idle-window policy has its own label, distinct from
// both "exhausted" and the "quota unknown" catch-all.
let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
AppLanguage.current = .en
precondition(L10n.skipReasonText("window_already_active") == "Weekly window already running")
precondition(L10n.skipReasonText("quota_exhausted") == "Quota exhausted")
precondition(L10n.skipReasonText("preflight_status_missing") == "Quota unknown")
precondition(L10n.weeklyWindowHint == "Weekly window")
precondition(L10n.quotaMiniHelp(remaining: 92, used: 8, weekly: true) == "Weekly window: 92% remaining (8% used)")
precondition(L10n.quotaMiniHelp(remaining: 40, used: nil) == "5-hour window: 40% remaining")
AppLanguage.current = .zh
precondition(L10n.skipReasonText("window_already_active") == "周窗口已在计时")
precondition(L10n.weeklyWindowHint == "周窗口")
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
