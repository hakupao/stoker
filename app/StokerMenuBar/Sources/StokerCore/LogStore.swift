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
    public var id: String { "\(timestamp)-\(tool ?? "")-\(runId ?? "")" }

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

    public var status: RunStatus {
        if skipped == true { return .skipped }
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
        case usage, rawLog, skipped, skipReason, eventCount
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

    public var cutoff: Date? {
        switch self {
        case .today: Calendar.current.startOfDay(for: Date())
        case .week: Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .month: Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .all: nil
        }
    }
}

public enum QuotaWindowType: String, CaseIterable, Sendable {
    case fiveHour, weekly
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
    @Published public private(set) var filteredStatus: [StatusRecord] = []

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func load() {
        usageRecords = Self.parseJSONL(url: root.appendingPathComponent("logs/usage.jsonl"))
        statusRecords = Self.parseJSONL(url: root.appendingPathComponent("logs/status.jsonl"))
        recomputeFiltered()
    }

    private func recomputeFiltered() {
        filteredUsage = usageRecords.filter { record in
            if toolFilter != .all, record.tool != toolFilter.rawValue { return false }
            if let cutoff = dateRange.cutoff, let date = record.date, date < cutoff { return false }
            return true
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        filteredStatus = statusRecords.filter { record in
            if toolFilter != .all, record.tool != toolFilter.rawValue { return false }
            if let cutoff = dateRange.cutoff, let date = record.date, date < cutoff { return false }
            return true
        }
        .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// Build chart points for the selected window, tagging each with a `segment` that bumps
    /// whenever remaining% jumps *up* (a quota reset). filteredStatus is already sorted ascending
    /// by date, so one pass — keyed per tool — assigns segments correctly even though Claude and
    /// Codex rows are interleaved.
    public func chartPoints(window: QuotaWindowType) -> [QuotaChartPoint] {
        let resetJump = 2.0  // above this, a rise reads as a reset rather than snapshot noise
        var lastPct: [String: Double] = [:]
        var segmentOf: [String: Int] = [:]
        var out: [QuotaChartPoint] = []
        for record in filteredStatus {
            guard let date = record.date else { continue }
            let pct: Double?
            switch window {
            case .fiveHour: pct = record.fiveHour?.remainingPercent
            case .weekly: pct = record.weekly?.remainingPercent
            }
            guard let pct else { continue }
            let key = record.tool
            if let prev = lastPct[key], pct > prev + resetJump {
                segmentOf[key, default: 0] += 1
            }
            lastPct[key] = pct
            out.append(QuotaChartPoint(
                date: date,
                tool: record.tool.capitalized,
                remainingPercent: pct,
                segment: segmentOf[key, default: 0]
            ))
        }
        return out
    }

    public var totalRuns: Int { filteredUsage.count }
    public var successCount: Int { filteredUsage.filter { $0.status == .success }.count }
    public var skippedCount: Int { filteredUsage.filter { $0.status == .skipped }.count }
    public var errorCount: Int { filteredUsage.filter { $0.status == .error }.count }

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

    private static func parseJSONL<T: Decodable>(url: URL) -> [T] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return contents.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }
}
