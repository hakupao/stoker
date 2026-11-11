import Foundation

public enum ToolHealthState: String, Sendable { case ok, warning, alert, unknown, anchored, pending, exhausted, disabled }

public struct ToolHealth: Equatable, Sendable {
    public var state: ToolHealthState
    public var consecutiveFailures: Int
    public var lastRunAt: Date?
    public var lastRunOK: Bool?
    public var lastError: String?
    public var nextActivation: Date?
    /// The anchored/pending/exhausted state describes the 5h/session window (Codex on a plan
    /// that has one), not the weekly window — picks the health copy.
    public var stateWindowIsSession: Bool = false
    public var isAlert: Bool { state == .alert }
}

/// Health of each tool's scheduled activation, derived only from usage rows + the latest
/// quota window. "Real runs" exclude preflight skips and fallback-superseded attempts
/// (Claude's staleness check still counts skips as proof the schedule is running).
public enum ToolHealthEvaluator {
    static let staleAfter: TimeInterval = 24 * 3600
    /// How long after a scheduled fire its usage row may take to land before the slot counts as
    /// missed: the run's timeout (~10 min with retries/fallbacks) plus an hour of slack for a
    /// Mac that slept through the slot and fires late on wake.
    static let missedFireGrace: TimeInterval = 70 * 60

    static func realRuns(_ records: [UsageRecord], tool: String) -> [UsageRecord] {
        records
            .filter { $0.tool == tool && $0.skipped != true && $0.supersededByFallback != true && $0.date != nil }
            .sorted { $0.date! > $1.date! }            // newest first
    }

    static func summary(_ runs: [UsageRecord]) -> (failures: Int, last: UsageRecord?, lastError: String?) {
        let failures = runs.prefix { $0.ok != true }.count
        let lastError = runs.first(where: { $0.ok != true })?.result.map { String($0.prefix(140)) }
        return (failures, runs.first, failures > 0 ? lastError : nil)
    }

    private static func build(state: ToolHealthState,
                              summary s: (failures: Int, last: UsageRecord?, lastError: String?),
                              nextActivation: Date?) -> ToolHealth {
        ToolHealth(state: state, consecutiveFailures: s.failures, lastRunAt: s.last?.date,
                  lastRunOK: s.last.map { $0.ok == true }, lastError: s.lastError, nextActivation: nextActivation)
    }

    public static func claude(records: [UsageRecord], scheduleOn: Bool, times: [String], days: [String] = [],
                              now: Date = Date(), calendar: Calendar = .current) -> ToolHealth {
        let runs = realRuns(records, tool: "claude")
        let s = summary(runs)
        let next = scheduleOn ? ScheduleFormatter.nextFire(times: times, days: days, now: now, calendar: calendar) : nil

        // Stale = no real success AND no preflight skip (any reason) within 24h, AND Claude's own
        // schedule (times + days) had a slot after that proof which is past its grace — so a
        // weekly-only schedule isn't flagged between its slots, while a daily one behaves as the
        // plain 24h rule. A skip proves the scheduler ran (e.g. weekly quota exhausted), so it
        // isn't a stalled schedule. "No success ever" counts as stale too.
        let lastOK = runs.first(where: { $0.ok == true })?.date
        let lastSkip = records
            .filter { $0.tool == "claude" && $0.skipped == true }
            .compactMap(\.date).max()
        let lastProof = [lastOK, lastSkip].compactMap { $0 }.max()
        let stale = lastProof.map { proof in
            guard now.timeIntervalSince(proof) > staleAfter,
                  let missed = ScheduleFormatter.nextFire(times: times, days: days, now: proof, calendar: calendar)
            else { return false }
            return missed < now.addingTimeInterval(-missedFireGrace)
        } ?? true

        let state: ToolHealthState
        if runs.isEmpty {
            state = .unknown
        } else if s.failures >= 2 {
            state = .alert
        } else if scheduleOn, !times.isEmpty, stale {
            state = .alert
        } else if s.failures == 1 {
            state = .warning
        } else {
            state = .ok
        }
        return build(state: state, summary: s, nextActivation: next)
    }

    /// `preflight` / `idleOnly` / `exhaustedThreshold` mirror the engine's ENABLE_QUOTA_PREFLIGHT,
    /// CODEX_ACTIVATE_ONLY_WHEN_IDLE and QUOTA_EXHAUSTED_THRESHOLD_PERCENT (engine defaults: on, on, 0).
    /// Like the engine, anchored/pending follow the gating window — the shortest one the account
    /// has (`fiveHour` when `hasSession`, else `weekly`) — while every present window counts
    /// toward exhaustion. `engineGateActive` is the engine's `limits.codex.gate.active`.
    public static func codex(records: [UsageRecord], weekly: ActivationState.QuotaWindow?,
                             windowMinutes: Int = 10080,
                             fiveHour: ActivationState.QuotaWindow? = nil, hasSession: Bool = false,
                             sessionMinutes: Int = 300, engineGateActive: Bool? = nil,
                             resetWaitMax: TimeInterval = 300,
                             scheduleOn: Bool, times: [String], days: [String] = [],
                             preflight: Bool = true, idleOnly: Bool = true, exhaustedThreshold: Double = 0,
                             now: Date = Date(), calendar: Calendar = .current) -> ToolHealth {
        let runs = realRuns(records, tool: "codex")
        let s = summary(runs)
        func resetAt(_ w: ActivationState.QuotaWindow?) -> Date? { ResetTime.parse(w?.resetsAt) }
        // Exhausted only while its reset is still ahead (a passed reset has rolled over).
        func exhausted(_ w: ActivationState.QuotaWindow?) -> Bool {
            guard let w, let r = resetAt(w), r > now else { return false }
            return (w.remainingPercent ?? 100) <= exhaustedThreshold
        }
        let gate = hasSession ? fiveHour : weekly
        let gateMinutes = hasSession ? sessionMinutes : windowMinutes
        let gateReset = resetAt(gate)
        let active = gateReset.map { $0 > now } ?? false
        let cycleStart = gateReset?.addingTimeInterval(-Double(gateMinutes) * 60)
        let ranThisCycle = cycleStart.map { start in runs.contains { $0.ok == true && $0.date! >= start } } ?? false
        let used = gate?.usedPercent ?? 0
        let exhaustedWindows = (hasSession ? [fiveHour, weekly] : [weekly]).filter(exhausted)
        let anyExhausted = !exhaustedWindows.isEmpty
        // The engine anchors on the *window*, independent of a later failure overriding the
        // displayed state to warning/alert. This drives both the state chain below and, when the
        // engine would actually skip, `from` for nextActivation.
        // The engine's verdict wins when it reports one: idle windows often show used ≥ 1, so
        // the used/ran heuristic is only the fallback for an older engine.
        let anchoredWindow = active && (exhausted(gate) || (engineGateActive ?? (used > 0 || ranThisCycle)))

        let state: ToolHealthState
        if s.failures >= 2 { state = .alert }
        else if s.failures == 1 { state = .warning }
        else if anyExhausted { state = .exhausted }
        else if anchoredWindow { state = .anchored }
        else { state = .pending }

        // The engine only skips inside the quota preflight: an exhausted window always (until
        // the last exhausted one resets), the anchored gate only under the idle-only policy —
        // and a slot within `resetWaitMax` before the gate's reset waits it out and sends.
        var skipUntil: [Date] = []
        if preflight {
            skipUntil += exhaustedWindows.compactMap(resetAt)
            if anchoredWindow, idleOnly, let gateReset {
                skipUntil.append(gateReset.addingTimeInterval(-max(0, resetWaitMax)))
            }
        }
        var next: Date? = nil
        if scheduleOn {
            let from = max(now, skipUntil.max() ?? now)
            next = ScheduleFormatter.nextFire(times: times, days: days, now: from, calendar: calendar)
        }
        var health = build(state: state, summary: s, nextActivation: next)
        // An exhausted weekly window outranks the session one in the copy.
        health.stateWindowIsSession = hasSession && !(anyExhausted && exhausted(weekly))
        return health
    }
}

/// Both tools' health from one evaluation, so every surface (Activity cards, alert banner,
/// header, menu) shows the same verdict. Recomputed from the latest logs + state on refresh —
/// never ticker-driven.
public struct ToolHealthSnapshot: Sendable {
    public var claude: ToolHealth
    public var codex: ToolHealth
    /// Enabled tools currently in `.alert`, Claude first.
    public var alertTools: [String]
    public var anyAlert: Bool { !alertTools.isEmpty }

    public func health(_ tool: String) -> ToolHealth {
        switch tool {
        case "claude": claude
        case "codex": codex
        default: ToolHealth(state: .unknown, consecutiveFailures: 0, lastRunAt: nil, lastRunOK: nil,
                            lastError: nil, nextActivation: nil)
        }
    }
}

extension ToolHealthEvaluator {
    /// A tool excluded by `ACTIVATION_TOOL` isn't scheduled: it becomes `.disabled` (last-run info
    /// kept, no next activation) and so never alerts — card, banner and menu always agree.
    public static func snapshot(records: [UsageRecord], quota: [String: ActivationState.ToolQuota],
                                installed: Bool, claudeSchedule: ToolSchedule, codexSchedule: ToolSchedule,
                                activationTool: String,
                                preflight: Bool = true, idleOnly: Bool = true, exhaustedThreshold: Double = 0,
                                codexProfile: WindowProfile? = nil, codexSessionMinutes: Int? = nil,
                                codexGateActive: Bool? = nil, codexResetWaitMax: TimeInterval = 300,
                                now: Date = Date(), calendar: Calendar = .current) -> ToolHealthSnapshot {
        let enabled = ToolRequirements.requiredCLIs(activationTool: activationTool)
        func gated(_ h: ToolHealth, _ tool: String) -> ToolHealth {
            guard !enabled.contains(tool) else { return h }
            var d = h
            d.state = .disabled
            d.nextActivation = nil
            return d
        }
        let claudeHealth = Self.claude(records: records, scheduleOn: installed && enabled.contains("claude"),
                                       times: claudeSchedule.times, days: claudeSchedule.days,
                                       now: now, calendar: calendar)
        // No profile from the caller → read it off the snapshot (an unknown one gates on weekly).
        let profile = codexProfile ?? quota["codex"]?.windowProfile(tool: "codex") ?? .unknown
        let codexHealth = Self.codex(records: records, weekly: quota["codex"]?.weekly,
                                     fiveHour: quota["codex"]?.fiveHour,
                                     hasSession: profile.hasSession(tool: "codex"),
                                     sessionMinutes: codexSessionMinutes ?? 300,
                                     engineGateActive: codexGateActive, resetWaitMax: codexResetWaitMax,
                                     scheduleOn: installed && enabled.contains("codex"),
                                     times: codexSchedule.times, days: codexSchedule.days,
                                     preflight: preflight, idleOnly: idleOnly,
                                     exhaustedThreshold: exhaustedThreshold, now: now, calendar: calendar)
        let claudeFinal = gated(claudeHealth, "claude")
        let codexFinal = gated(codexHealth, "codex")
        let alertTools = [("claude", claudeFinal), ("codex", codexFinal)]
            .filter { $0.1.isAlert }
            .map(\.0)
        return ToolHealthSnapshot(claude: claudeFinal, codex: codexFinal, alertTools: alertTools)
    }

    /// Both tools on one shared, every-day schedule (the pre-per-tool shape).
    public static func snapshot(records: [UsageRecord], quota: [String: ActivationState.ToolQuota],
                                installed: Bool, times: [String], activationTool: String,
                                preflight: Bool = true, idleOnly: Bool = true, exhaustedThreshold: Double = 0,
                                now: Date = Date(), calendar: Calendar = .current) -> ToolHealthSnapshot {
        let shared = ToolSchedule(times: times, days: [])
        return snapshot(records: records, quota: quota, installed: installed, claudeSchedule: shared,
                        codexSchedule: shared, activationTool: activationTool, preflight: preflight,
                        idleOnly: idleOnly, exhaustedThreshold: exhaustedThreshold, now: now, calendar: calendar)
    }

    /// Convenience over the app's decoded state; the schedule counts as on exactly when the
    /// header toggle does (`state.installed`).
    public static func snapshot(records: [UsageRecord], state: ActivationState?,
                                now: Date = Date()) -> ToolHealthSnapshot {
        let none = ToolSchedule(times: [], days: [])
        return snapshot(records: records, quota: state?.quota ?? [:], installed: state?.installed == true,
                 claudeSchedule: state?.schedule.claude ?? none, codexSchedule: state?.schedule.codex ?? none,
                 activationTool: state?.config.activationTool ?? "all",
                 preflight: state?.config.enableQuotaPreflight ?? true,
                 idleOnly: state?.config.codexActivateOnlyWhenIdle ?? true,
                 exhaustedThreshold: state?.config.quotaExhaustedThresholdPercent ?? 0,
                 codexProfile: state?.windowProfile("codex"),
                 codexSessionMinutes: state?.limits?.codex?.sessionMinutes,
                 codexGateActive: state?.limits?.codex?.gate?.active,
                 codexResetWaitMax: TimeInterval(state?.config.codexResetWaitMaxSeconds ?? 300),
                 now: now)
    }
}

// MARK: - Background alert re-check
// The app's alert decision is `snapshot(records:state:).anyAlert`; time alone can flip it
// (Claude staleness), so the app also re-evaluates it off a clock.

extension ToolHealthSnapshot {
    /// When to re-check after the next scheduled activation: the earliest `nextActivation`
    /// plus the run's timeout plus a margin for the usage row to land. Nil when nothing is scheduled.
    public func recheckAt(timeoutSeconds: TimeInterval, margin: TimeInterval = 60) -> Date? {
        [claude.nextActivation, codex.nextActivation].compactMap { $0 }.min()?
            .addingTimeInterval(timeoutSeconds + margin)
    }
}
