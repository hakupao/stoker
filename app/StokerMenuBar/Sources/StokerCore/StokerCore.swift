import Foundation

public enum EnvFile {
    public static func updating(_ contents: String, values: [String: String]) -> String {
        var seen = Set<String>()
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for index in lines.indices {
            guard let key = key(in: lines[index]), let value = values[key] else {
                continue
            }
            lines[index] = "\(key)=\(format(value))"
            seen.insert(key)
        }

        for key in values.keys.sorted() where !seen.contains(key) {
            lines.append("\(key)=\(format(values[key] ?? ""))")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func key(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else {
            return nil
        }

        let candidate = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty else {
            return nil
        }

        return String(candidate)
    }

    private static func format(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet(charactersIn: " \t,#\"'")) == nil {
            return value
        }

        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public enum ScheduleFormatter {
    public static func times(from raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { normalize($0) }
    }

    public static func normalize(_ entry: String) -> String? {
        let parts = entry.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), (0...23).contains(hour),
              let minute = Int(parts[1]), (0...59).contains(minute) else {
            return nil
        }
        return String(format: "%02d:%02d", hour, minute)
    }
}

public enum ProjectLocator {
    public static func findRoot(
        from start: URL = Bundle.main.bundleURL,
        resourceURL: URL? = Bundle.main.resourceURL,
        applicationSupportURL: URL? = nil
    ) -> URL {
        if let override = ProcessInfo.processInfo.environment["STOKER_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        var current = start
        let fileManager = FileManager.default
        var depth = 0

        while depth < 64 {
            if fileManager.fileExists(atPath: current.appendingPathComponent("bin/activate-ai-window.sh").path) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
            depth += 1
        }

        if let root = bundledRoot(resourceURL: resourceURL, applicationSupportURL: applicationSupportURL) {
            return root
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    public static func bundledRoot(
        resourceURL: URL? = Bundle.main.resourceURL,
        applicationSupportURL: URL? = nil
    ) -> URL? {
        let fileManager = FileManager.default
        guard let resourceURL else {
            return nil
        }

        let bundled = resourceURL.appendingPathComponent("stoker")
        guard fileManager.fileExists(atPath: bundled.appendingPathComponent("bin/activate-ai-window.sh").path) else {
            return nil
        }

        let supportBase = applicationSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let installed = supportBase.appendingPathComponent("Stoker/stoker")
        do {
            try syncBundledRoot(from: bundled, to: installed)
            return installed
        } catch {
            return bundled
        }
    }

    private static func syncBundledRoot(from bundled: URL, to installed: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: installed, withIntermediateDirectories: true)

        let versionFile = installed.appendingPathComponent(".bundled-version")
        let probeFile = installed.appendingPathComponent("codex-probe/probe.py")
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if let existing = try? String(contentsOf: versionFile, encoding: .utf8),
           existing.trimmingCharacters(in: .whitespacesAndNewlines) == bundleVersion,
           fileManager.fileExists(atPath: probeFile.path) {
            return
        }

        for directory in ["bin", "scripts", "codex-probe"] {
            let source = bundled.appendingPathComponent(directory)
            guard fileManager.fileExists(atPath: source.path) else {
                continue
            }

            let destination = installed.appendingPathComponent(directory)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        for directory in ["launchd", "logs", "logs/raw", "run"] {
            try fileManager.createDirectory(
                at: installed.appendingPathComponent(directory),
                withIntermediateDirectories: true
            )
        }

        for file in ["install.sh", ".env.example", "README.md", "README_CN.md", "LICENSE", "CHANGELOG.md"] {
            let source = bundled.appendingPathComponent(file)
            guard fileManager.fileExists(atPath: source.path) else {
                continue
            }

            let destination = installed.appendingPathComponent(file)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        try? bundleVersion.write(to: versionFile, atomically: true, encoding: .utf8)
    }
}

public struct ActivationState: Decodable {
    public var root: String
    public var label: String
    public var installed: Bool
    public var running: Bool
    public var launchctl: Launchctl?
    public var schedule: Schedule
    public var config: Config
    public var keepAwake: KeepAwake
    public var quota: [String: ToolQuota]
    public var lastUsage: LastUsage?

    private enum CodingKeys: String, CodingKey {
        case root, label, installed, running, launchctl, schedule, config, quota
        case keepAwake = "keep_awake"
        case lastUsage = "last_usage"
    }

    public struct Launchctl: Decodable {
        public var state: String?
        public var error: String?
        public var program: String?
        public var workingDirectory: String?
        public var matchesRoot: Bool?
        public var mismatch: String?

        private enum CodingKeys: String, CodingKey {
            case state, error, program, mismatch
            case workingDirectory = "working_directory"
            case matchesRoot = "matches_root"
        }
    }

    public struct Schedule: Decodable {
        public var times: [String]
    }

    public struct Config: Decodable {
        public var activationTool: String
        public var codexModel: String
        public var enableStatusSnapshots: Bool
        public var enableQuotaPreflight: Bool
        public var quotaPreflightOnUnknown: String
        public var quotaExhaustedThresholdPercent: Double

        private enum CodingKeys: String, CodingKey {
            case activationTool = "activation_tool"
            case codexModel = "codex_model"
            case enableStatusSnapshots = "enable_status_snapshots"
            case enableQuotaPreflight = "enable_quota_preflight"
            case quotaPreflightOnUnknown = "quota_preflight_on_unknown"
            case quotaExhaustedThresholdPercent = "quota_exhausted_threshold_percent"
        }
    }

    public struct KeepAwake: Decodable {
        public var mode: String
        public var seconds: Int
    }

    public struct ToolQuota: Decodable {
        public var ok: Bool?
        public var fiveHour: QuotaWindow?
        public var weekly: QuotaWindow?
        public var sonnetWeekly: QuotaWindow?

        private enum CodingKeys: String, CodingKey {
            case ok
            case fiveHour = "five_hour"
            case weekly
            case sonnetWeekly = "sonnet_weekly"
        }
    }

    public struct QuotaWindow: Decodable {
        public var remainingPercent: Double?
        public var usedPercent: Double?
        public var resetsAt: String?

        private enum CodingKeys: String, CodingKey {
            case remainingPercent = "remaining_percent"
            case usedPercent = "used_percent"
            case resetsAt = "resets_at"
        }
    }

    public struct LastUsage: Decodable {
        public var timestamp: String?
        public var tool: String?
        public var ok: Bool?
        public var skipped: Bool?
        public var skipReason: String?
        public var result: String?

        private enum CodingKeys: String, CodingKey {
            case timestamp
            case tool
            case ok
            case skipped
            case skipReason = "skip_reason"
            case result
        }
    }
}

public struct AppSettings {
    public var scheduleTimes: [String]
    public var activationTool: String
    public var codexModel: String
    public var enableStatusSnapshots: Bool
    public var enableQuotaPreflight: Bool
    public var quotaPreflightOnUnknown: String
    public var keepAwakeMode: String
    public var keepAwakeSeconds: String

    public var enableClaude: Bool {
        get { activationTool == "all" || activationTool == "claude" }
        set {
            if newValue && enableCodex { activationTool = "all" }
            else if newValue { activationTool = "claude" }
            else if enableCodex { activationTool = "codex" }
            else { activationTool = "all" }
        }
    }

    public var enableCodex: Bool {
        get { activationTool == "all" || activationTool == "codex" }
        set {
            if enableClaude && newValue { activationTool = "all" }
            else if newValue { activationTool = "codex" }
            else if enableClaude { activationTool = "claude" }
            else { activationTool = "all" }
        }
    }

    public init(values: [String: String]) {
        let timesStr = values["SCHEDULE_TIMES"] ?? "07:00,12:00,17:00,22:00"
        scheduleTimes = ScheduleFormatter.times(from: timesStr)
        activationTool = values["ACTIVATION_TOOL"] ?? "all"
        codexModel = values["CODEX_MODEL"] ?? "gpt-5.4-mini"
        enableStatusSnapshots = values["ENABLE_STATUS_SNAPSHOTS"] != "0"
        enableQuotaPreflight = values["ENABLE_QUOTA_PREFLIGHT"] != "0"
        quotaPreflightOnUnknown = values["QUOTA_PREFLIGHT_ON_UNKNOWN"] ?? "allow"
        keepAwakeMode = values["KEEP_AWAKE_MODE"] ?? "off"
        keepAwakeSeconds = values["KEEP_AWAKE_SECONDS"] ?? "900"
    }

    public var envValues: [String: String] {
        [
            "SCHEDULE_TIMES": scheduleTimes.joined(separator: ","),
            "ACTIVATION_TOOL": activationTool,
            "CODEX_MODEL": codexModel,
            "ENABLE_STATUS_SNAPSHOTS": enableStatusSnapshots ? "1" : "0",
            "ENABLE_QUOTA_PREFLIGHT": enableQuotaPreflight ? "1" : "0",
            "QUOTA_PREFLIGHT_ON_UNKNOWN": quotaPreflightOnUnknown,
            "KEEP_AWAKE_MODE": keepAwakeMode,
            "KEEP_AWAKE_SECONDS": keepAwakeSeconds
        ]
    }
}

public enum EnvParser {
    public static func parse(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]

        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            let rawValue = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values[String(key)] = unquote(String(rawValue))
        }

        return values
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }

        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }
}
