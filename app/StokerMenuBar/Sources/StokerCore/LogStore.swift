import Foundation

// MARK: - Timestamp Parsing

public enum LogTimestamp: Sendable {
    private static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return f
    }()

    private static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    public static func parse(_ string: String) -> Date? {
        logFormatter.date(from: string)
    }

    public static func display(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? timeOnly.string(from: date) : dateShort.string(from: date)
    }
}

// MARK: - Usage Record

public struct UsageRecord: Decodable, Identifiable, Sendable {
    // Model disambiguates same-second rows (a model-fallback retry shares the run id).
    public var id: String { "\(timestamp)-\(tool ?? "")-\(runId ?? "")-\(model ?? "")" }

    public let timestamp: String
    public let date: Date?
    public let runId: String?
    public let tool: String?
    public let exitCode: Int?
    public let ok: Bool?
    public let result: String?
    public let sessionId: String?
    public let threadId: String?
    public let model: String?
    public let durationMs: Double?
    public let totalCostUsd: Double?
    public let usage: UsageTokens?
    public let rawLog: String?
    public let skipped: Bool?
    public let skipReason: String?
    public let eventCount: Int?
    /// A failed attempt the engine retried with a fallback model in the same run; the
    /// retry's own row carries the outcome, so this one isn't counted as an error.
    public let supersededByFallback: Bool?

    public var status: RunStatus {
        if skipped == true || supersededByFallback == true { return .skipped }
        if ok == true { return .success }
        return .error
    }

    public var toolDisplayName: String {
        switch tool {
        case "claude": "Claude"
        case "codex": "Codex"
        default: tool ?? "Unknown"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, runId, tool, exitCode, ok, result
        case sessionId, threadId, model, durationMs, totalCostUsd
        case usage, rawLog, skipped, skipReason, eventCount, supersededByFallback
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decode(String.self, forKey: .timestamp)
        runId = try c.decodeIfPresent(String.self, forKey: .runId)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
        result = try c.decodeIfPresent(String.self, forKey: .result)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        durationMs = try c.decodeIfPresent(Double.self, forKey: .durationMs)
        totalCostUsd = try c.decodeIfPresent(Double.self, forKey: .totalCostUsd)
        usage = try c.decodeIfPresent(UsageTokens.self, forKey: .usage)
        rawLog = try c.decodeIfPresent(String.self, forKey: .rawLog)
        skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped)
        skipReason = try c.decodeIfPresent(String.self, forKey: .skipReason)
        eventCount = try c.decodeIfPresent(Int.self, forKey: .eventCount)
        supersededByFallback = try c.decodeIfPresent(Bool.self, forKey: .supersededByFallback)
        date = LogTimestamp.parse(timestamp)
    }
}

public struct UsageTokens: Decodable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheCreationInputTokens: Int?
    public let cacheReadInputTokens: Int?
    public let cachedInputTokens: Int?
    public let reasoningOutputTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens, outputTokens
        case cacheCreationInputTokens, cacheReadInputTokens
        case cachedInputTokens, reasoningOutputTokens
    }
}

public enum RunStatus: String, CaseIterable, Sendable {
    case success, skipped, error
}

// MARK: - Status Record

public struct StatusRecord: Decodable, Identifiable, Sendable {
    public var id: String { "\(timestamp)-\(tool)" }

    public let timestamp: String
    public let date: Date?
    public let runId: String?
    public let tool: String
    public let ok: Bool?
    public let subscriptionType: String?
    public let planType: String?
    public let fiveHour: QuotaSnapshotData?
    public let weekly: QuotaSnapshotData?
    public let sonnetWeekly: QuotaSnapshotData?

    private enum CodingKeys: String, CodingKey {
        case timestamp, runId, tool, ok
        case subscriptionType, planType
        case fiveHour, weekly, sonnetWeekly
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decode(String.self, forKey: .timestamp)
        runId = try c.decodeIfPresent(String.self, forKey: .runId)
        tool = try c.decode(String.self, forKey: .tool)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
        subscriptionType = try c.decodeIfPresent(String.self, forKey: .subscriptionType)
        planType = try c.decodeIfPresent(String.self, forKey: .planType)
        fiveHour = try c.decodeIfPresent(QuotaSnapshotData.self, forKey: .fiveHour)
        weekly = try c.decodeIfPresent(QuotaSnapshotData.self, forKey: .weekly)
        sonnetWeekly = try c.decodeIfPresent(QuotaSnapshotData.self, forKey: .sonnetWeekly)
        date = LogTimestamp.parse(timestamp)
    }
}

public struct QuotaSnapshotData: Decodable, Sendable {
    public let usedPercent: Double?
    public let remainingPercent: Double?
    public let resetsAt: String?
    public let windowMinutes: Int?
    public let resetsAtEpoch: Int?

    private enum CodingKeys: String, CodingKey {
        case usedPercent, remainingPercent, resetsAt
        case windowMinutes, resetsAtEpoch
    }
}

// MARK: - Filters

public enum ToolFilter: String, CaseIterable, Sendable {
    case all, claude, codex
}

public enum DateRangeFilter: String, CaseIterable, Sendable {
    case today, week, month, all

    public var cutoff: Date? { cutoff(now: Date()) }

    public func cutoff(now: Date) -> Date? {
        switch self {
        case .today: Calendar.current.startOfDay(for: now)
        case .week: Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .month: Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .all: nil
        }
    }
}

/// One quota line the Activity trend can show. Each series belongs to exactly one tool and
/// window, so the trend never mixes Claude's 5h window with Codex's weekly one.
public enum TrendSeries: String, CaseIterable, Sendable {
    case claudeFiveHour, claudeWeekly, codexWeekly

    public var tool: String { self == .codexWeekly ? "codex" : "claude" }
}

// MARK: - Chart Data

public struct QuotaChartPoint: Identifiable, Sendable {
    public var id: String { "\(tool)-\(segment)-\(date.timeIntervalSince1970)" }
    public var date: Date
    public var tool: String
    public var remainingPercent: Double
    /// Monotonic index that bumps at each quota *reset* (an upward jump in remaining%), so the
    /// chart can break the line per window instead of drawing a fake "refill" ramp across a
    /// reset boundary. Points sharing (tool, segment) form one continuous line.
    public var segment: Int
}

// MARK: - LogStore

/// Size + modification date of one log file (nil when it doesn't exist). Used to skip a reload,
/// and so a republish, when neither log changed since the last load.
public struct LogFileSignature: Equatable, Sendable {
    public var size: UInt64
    public var modified: Date?
}

public struct LogSignatures: Equatable, Sendable {
    public var usage: LogFileSignature?
    public var status: LogFileSignature?
}

/// Parsed logs plus the file signatures they were read at — built off the main actor.
public struct LogSnapshot: Sendable {
    public let usage: [UsageRecord]
    public let status: [StatusRecord]
    public let signatures: LogSignatures
}

@MainActor
public final class LogStore: ObservableObject {
    @Published public var usageRecords: [UsageRecord] = []
    @Published public var statusRecords: [StatusRecord] = []

    @Published public var toolFilter: ToolFilter = .all {
        didSet { recomputeFiltered() }
    }
    @Published public var dateRange: DateRangeFilter = .week {
        didSet { recomputeFiltered() }
    }

    @Published public private(set) var filteredUsage: [UsageRecord] = []

    private let root: URL
    /// Signatures of the files behind the current records; nil until the first load.
    public private(set) var signatures: LogSignatures?

    public init(root: URL) {
        self.root = root
    }

    /// Reload both logs. When neither file changed only the date cutoff is re-applied (so
    /// "today" rolls over at midnight), publishing only if the filtered list actually changes.
    public func load(now: Date = Date()) {
        if let snapshot = Self.read(root: root, unlessUnchangedFrom: signatures) {
            apply(snapshot)
        } else {
            refilter(now: now)
        }
    }

    /// Re-apply the filters against `now` without re-reading the logs; publishes only on change.
    public func refilter(now: Date = Date()) {
        let refreshed = filtered(now: now)
        if refreshed.map(\.id) != filteredUsage.map(\.id) { filteredUsage = refreshed }
    }

    /// Install records read elsewhere (e.g. parsed on a background task by `read`).
    public func apply(_ snapshot: LogSnapshot) {
        usageRecords = snapshot.usage
        statusRecords = snapshot.status
        signatures = snapshot.signatures
        recomputeFiltered()
    }

    /// Parse both logs — callable off the main actor. Returns nil when both files still match
    /// `previous` (same size and modification date), so the caller can skip the reassignment.
    public nonisolated static func read(root: URL, unlessUnchangedFrom previous: LogSignatures?) -> LogSnapshot? {
        let usageURL = root.appendingPathComponent("logs/usage.jsonl")
        let statusURL = root.appendingPathComponent("logs/status.jsonl")
        let current = LogSignatures(usage: signature(usageURL), status: signature(statusURL))
        if let previous, previous == current { return nil }
        return LogSnapshot(usage: parseJSONL(url: usageURL), status: parseJSONL(url: statusURL),
                           signatures: current)
    }

    /// Just the usage rows, off the main actor — for the background alert re-check.
    public nonisolated static func readUsage(root: URL) -> [UsageRecord] {
        parseJSONL(url: root.appendingPathComponent("logs/usage.jsonl"))
    }

    private nonisolated static func signature(_ url: URL) -> LogFileSignature? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return LogFileSignature(size: (attrs[.size] as? NSNumber)?.uint64Value ?? 0,
                                modified: attrs[.modificationDate] as? Date)
    }

    private func recomputeFiltered() {
        filteredUsage = filtered(now: Date())
    }

    private func filtered(now: Date) -> [UsageRecord] {
        let cutoff = dateRange.cutoff(now: now)
        return usageRecords.filter { record in
            if toolFilter != .all, record.tool != toolFilter.rawValue { return false }
            if let cutoff, let date = record.date, date < cutoff { return false }
            return true
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Build chart points for one series, tagging each with a `segment` that bumps whenever
    /// remaining% jumps *up* (a quota reset) so the line breaks per window instead of drawing a
    /// fake "refill" ramp. Honors the date range but not `toolFilter` — the series already picks
    /// its tool, and the run-list tool filter must not blank the trend.
    public func chartPoints(series: TrendSeries) -> [QuotaChartPoint] {
        let resetJump = 2.0  // above this, a rise reads as a reset rather than snapshot noise
        let cutoff = dateRange.cutoff
        var lastPct: Double?
        var segment = 0
        var out: [QuotaChartPoint] = []
        let rows = statusRecords
            .filter { $0.tool == series.tool }
            .compactMap { r in r.date.map { (r, $0) } }
            .filter { row in cutoff.map { row.1 >= $0 } ?? true }
            .sorted { $0.1 < $1.1 }
        for (record, date) in rows {
            let pct: Double? = series == .claudeFiveHour
                ? record.fiveHour?.remainingPercent
                : record.weekly?.remainingPercent
            guard let pct else { continue }
            if let prev = lastPct, pct > prev + resetJump { segment += 1 }
            lastPct = pct
            out.append(QuotaChartPoint(date: date, tool: record.tool, remainingPercent: pct, segment: segment))
        }
        return out
    }

    public var totalRuns: Int { filteredUsage.count }
    public var successCount: Int { filteredUsage.filter { $0.status == .success }.count }
    public var errorCount: Int { filteredUsage.filter { $0.status == .error }.count }
    /// Skips the engine made on purpose (Codex's weekly window is already anchored) — neutral.
    public var plannedSkipCount: Int {
        filteredUsage.filter { $0.skipped == true && $0.skipReason == "window_already_active" }.count
    }
    /// Quota-preflight skips (exhausted / unknown) — worth a warning. Excludes planned skips and
    /// fallback-superseded attempts (those also report `.skipped` status but aren't skips).
    public var quotaSkipCount: Int {
        filteredUsage.filter { $0.skipped == true && $0.skipReason != "window_already_active" }.count
    }

    public var averageCost: Double? {
        let costs = filteredUsage.compactMap(\.totalCostUsd).filter { $0 > 0 }
        guard !costs.isEmpty else { return nil }
        return costs.reduce(0, +) / Double(costs.count)
    }

    public func exportCSV() -> String {
        var lines = ["timestamp,tool,status,result,duration_ms,cost_usd,skip_reason"]
        for r in filteredUsage {
            let fields: [String] = [
                r.timestamp,
                r.tool ?? "",
                r.status.rawValue,
                csvEscape(r.result ?? ""),
                r.durationMs.map { String(format: "%.0f", $0) } ?? "",
                r.totalCostUsd.map { String(format: "%.6f", $0) } ?? "",
                csvEscape(r.skipReason ?? ""),
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private nonisolated static func parseJSONL<T: Decodable>(url: URL) -> [T] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return contents.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }
}
