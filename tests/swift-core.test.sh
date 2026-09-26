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
    precondition(TrendSeries.allCases == [.claudeFiveHour, .claudeWeekly, .codexWeekly])
    precondition(TrendSeries.codexWeekly.tool == "codex" && TrendSeries.claudeWeekly.tool == "claude")
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
precondition(L10n.codexIdleOnlyHelp == "周窗口已在计时时跳过，约每周只激活一次")
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
