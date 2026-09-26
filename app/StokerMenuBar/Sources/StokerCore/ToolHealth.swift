import Foundation

public enum ToolHealthState: String, Sendable { case ok, warning, alert, unknown, anchored, pending, exhausted, disabled }

public struct ToolHealth: Equatable, Sendable {
    public var state: ToolHealthState
    public var consecutiveFailures: Int
    public var lastRunAt: Date?
    public var lastRunOK: Bool?
    public var lastError: String?
    public var nextActivation: Date?
    public var isAlert: Bool { state == .alert }
}

/// Health of each tool's scheduled activation, derived only from usage rows + the latest
/// quota window. "Real runs" exclude preflight skips and fallback-superseded attempts.
public enum ToolHealthEvaluator {
    static let staleAfter: TimeInterval = 24 * 3600

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

    public static func claude(records: [UsageRecord], scheduleOn: Bool, times: [String],
                              now: Date = Date(), calendar: Calendar = .current) -> ToolHealth {
        let runs = realRuns(records, tool: "claude")
        let s = summary(runs)
        let next = scheduleOn ? ScheduleFormatter.nextFire(times: times, now: now, calendar: calendar) : nil

        // "No success ever" counts as stale too, so this is written as an explicit
        // lastOK lookup rather than folded into the branch condition.
        let lastOK = runs.first(where: { $0.ok == true })?.date
        let stale = lastOK == nil || now.timeIntervalSince(lastOK!) > staleAfter

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

    public static func codex(records: [UsageRecord], weekly: ActivationState.QuotaWindow?,
                             windowMinutes: Int = 10080, scheduleOn: Bool, times: [String],
                             now: Date = Date(), calendar: Calendar = .current) -> ToolHealth {
        let runs = realRuns(records, tool: "codex")
        let s = summary(runs)
        let resetAt = ResetTime.parse(weekly?.resetsAt)
        let active = resetAt.map { $0 > now } ?? false
        let cycleStart = resetAt?.addingTimeInterval(-Double(windowMinutes) * 60)
        let ranThisCycle = cycleStart.map { start in runs.contains { $0.ok == true && $0.date! >= start } } ?? false
        let used = weekly?.usedPercent ?? 0
        let exhaustedByPercent = (weekly?.remainingPercent ?? 100) <= 0
        // The engine anchors on the *window*, independent of a later failure overriding the
        // displayed state to warning/alert — it still skips runs while the window is anchored.
        // This drives both the state chain below and `from` for nextActivation.
        let anchoredWindow = active && (exhaustedByPercent || used > 0 || ranThisCycle)

        let state: ToolHealthState
        if s.failures >= 2 { state = .alert }
        else if s.failures == 1 { state = .warning }
        else if anchoredWindow, exhaustedByPercent { state = .exhausted }
        else if anchoredWindow { state = .anchored }
        else { state = .pending }

        var next: Date? = nil
        if scheduleOn {
            let from = anchoredWindow ? max(now, resetAt ?? now) : now
            next = ScheduleFormatter.nextFire(times: times, now: from, calendar: calendar)
        }
        return build(state: state, summary: s, nextActivation: next)
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
                                installed: Bool, times: [String], activationTool: String,
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
                                       times: times, now: now, calendar: calendar)
        let codexHealth = Self.codex(records: records, weekly: quota["codex"]?.weekly,
                                     scheduleOn: installed && enabled.contains("codex"),
                                     times: times, now: now, calendar: calendar)
        let claudeFinal = gated(claudeHealth, "claude")
        let codexFinal = gated(codexHealth, "codex")
        let alertTools = [("claude", claudeFinal), ("codex", codexFinal)]
            .filter { $0.1.isAlert }
            .map(\.0)
        return ToolHealthSnapshot(claude: claudeFinal, codex: codexFinal, alertTools: alertTools)
    }

    /// Convenience over the app's decoded state; the schedule counts as on exactly when the
    /// header toggle does (`state.installed`).
    public static func snapshot(records: [UsageRecord], state: ActivationState?,
                                now: Date = Date()) -> ToolHealthSnapshot {
        snapshot(records: records, quota: state?.quota ?? [:], installed: state?.installed == true,
                 times: state?.schedule.times ?? [], activationTool: state?.config.activationTool ?? "all",
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
