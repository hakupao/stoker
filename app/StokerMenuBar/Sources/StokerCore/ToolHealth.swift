import Foundation

public enum ToolHealthState: String, Sendable { case ok, warning, alert, unknown, anchored, pending, exhausted }

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
