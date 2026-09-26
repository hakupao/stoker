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

    /// The next scheduled fire strictly after `now`, given "HH:MM" entries (local wall
    /// clock, matching launchd's `StartCalendarInterval`). Uses `Calendar.nextDate` so the
    /// result stays correct across DST transitions — a 12:00 entry reads 12:00 even on the
    /// spring-forward/fall-back day, instead of drifting an hour. Returns nil when no valid
    /// times exist. A time exactly at `now` counts as already firing, so the next one is
    /// returned (matching `after:` semantics).
    public static func nextFire(times: [String], now: Date = Date(), calendar: Calendar = .current) -> Date? {
        times.compactMap { entry -> Date? in
            guard let (hour, minute) = hourMinute(entry) else { return nil }
            var match = DateComponents()
            match.hour = hour
            match.minute = minute
            match.second = 0
            return calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime)
        }.min()
    }

    /// Whole minutes from `now` until `date`, clamped at zero.
    public static func minutesRemaining(until date: Date, now: Date = Date()) -> Int {
        max(0, Int(date.timeIntervalSince(now) / 60))
    }

    /// Local "HH:MM" clock string for a date.
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        String(format: "%02d:%02d",
               calendar.component(.hour, from: date),
               calendar.component(.minute, from: date))
    }

    private static func hourMinute(_ entry: String) -> (Int, Int)? {
        guard let normalized = normalize(entry) else { return nil }
        let parts = normalized.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return (hour, minute)
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
        /// Timestamp of the snapshot row this quota came from (log format, e.g.
        /// "2026-06-08 13:07:11 JST") — lets the UI honestly show "updated HH:mm".
        public var timestamp: String?
        public var fiveHour: QuotaWindow?
        public var weekly: QuotaWindow?
        public var sonnetWeekly: QuotaWindow?
        /// Per-scope weekly limits (Claude only, e.g. a model-specific bucket). nil when the
        /// row predates the field or carries a malformed value; empty when the account has none.
        public var scopedWeekly: [ScopedWeeklyBucket]?
        /// Codex plan tier (free/plus/pro/team). Claude carries its tier in `subscriptionType`.
        public var planType: String?
        /// Claude subscription tier (pro/max). Codex carries its tier in `planType`.
        public var subscriptionType: String?
        /// Overage/credit balance. Shape differs by tool (Codex balance vs Claude
        /// extra_usage), so every field is optional; nil when the source has none.
        public var credits: Credits?

        /// The plan/tier to display, whichever tool populated it.
        public var displayPlan: String? { planType ?? subscriptionType }

        private enum CodingKeys: String, CodingKey {
            case ok, timestamp
            case fiveHour = "five_hour"
            case weekly
            case sonnetWeekly = "sonnet_weekly"
            case scopedWeekly = "scoped_weekly"
            case planType = "plan_type"
            case subscriptionType = "subscription_type"
            case credits
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
            timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
            fiveHour = try c.decodeIfPresent(QuotaWindow.self, forKey: .fiveHour)
            weekly = try c.decodeIfPresent(QuotaWindow.self, forKey: .weekly)
            sonnetWeekly = try c.decodeIfPresent(QuotaWindow.self, forKey: .sonnetWeekly)
            // Defensive like `credits`: a surprise shape must not fail the whole decode, and
            // one malformed bucket is dropped on its own instead of losing the whole array.
            scopedWeekly = ((try? c.decodeIfPresent([LossyScopedBucket].self, forKey: .scopedWeekly)) ?? nil)
                .map { $0.compactMap(\.value) }
            planType = try c.decodeIfPresent(String.self, forKey: .planType)
            subscriptionType = try c.decodeIfPresent(String.self, forKey: .subscriptionType)
            // Defensive: a surprise `credits` shape (e.g. a bare string carried by an
            // older snapshot row) must not fail the whole ActivationState decode.
            credits = (try? c.decodeIfPresent(Credits.self, forKey: .credits)) ?? nil
        }
    }

    /// Credit/overage balance. Populated differently per tool — Codex fills
    /// balance/hasCredits/unlimited; Claude fills the extra_usage fields — so all
    /// are optional and the UI shows whichever are present.
    public struct Credits: Decodable {
        public var balance: String?
        public var hasCredits: Bool?
        public var unlimited: Bool?
        public var isEnabled: Bool?
        public var monthlyLimit: Double?
        public var usedCredits: Double?
        public var utilization: Double?

        private enum CodingKeys: String, CodingKey {
            case balance
            case hasCredits = "has_credits"
            case unlimited
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case utilization
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

    /// One per-scope weekly limit. Only an `isActive == true` bucket gates the engine's quota
    /// preflight; `isActive == nil` means the source doesn't say (native usage API).
    public struct ScopedWeeklyBucket: Decodable, Identifiable {
        public var id: String
        public var label: String
        public var usedPercent: Double?
        public var remainingPercent: Double?
        public var resetsAt: String?
        public var isActive: Bool?
        /// Set by activation-state.sh when `resetsAt` already passed (percentages blanked).
        public var resetPassed: Bool?

        private enum CodingKeys: String, CodingKey {
            case id, label
            case usedPercent = "used_percent"
            case remainingPercent = "remaining_percent"
            case resetsAt = "resets_at"
            case isActive = "is_active"
            case resetPassed = "reset_passed"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let rawId = try c.decodeIfPresent(String.self, forKey: .id)
            let rawLabel = try c.decodeIfPresent(String.self, forKey: .label)
            id = rawId ?? rawLabel ?? "unknown"
            label = rawLabel ?? rawId ?? "unknown"
            usedPercent = try c.decodeIfPresent(Double.self, forKey: .usedPercent)
            remainingPercent = try c.decodeIfPresent(Double.self, forKey: .remainingPercent)
            resetsAt = try c.decodeIfPresent(String.self, forKey: .resetsAt)
            isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive)
            resetPassed = try c.decodeIfPresent(Bool.self, forKey: .resetPassed)
        }
    }

    /// Decodes one array element, yielding nil instead of throwing for a malformed bucket.
    private struct LossyScopedBucket: Decodable {
        let value: ScopedWeeklyBucket?
        init(from decoder: Decoder) throws {
            value = try? ScopedWeeklyBucket(from: decoder)
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
        codexModel = AppSettings.migratedCodexModel(values["CODEX_MODEL"])
        enableStatusSnapshots = values["ENABLE_STATUS_SNAPSHOTS"] != "0"
        enableQuotaPreflight = values["ENABLE_QUOTA_PREFLIGHT"] != "0"
        quotaPreflightOnUnknown = values["QUOTA_PREFLIGHT_ON_UNKNOWN"] ?? "allow"
        keepAwakeMode = values["KEEP_AWAKE_MODE"] ?? "off"
        keepAwakeSeconds = values["KEEP_AWAKE_SECONDS"] ?? "900"
    }

    /// Current default Codex activation model (mirrors the engine's CODEX_DEFAULT_MODEL).
    public static let defaultCodexModel = "gpt-5.6-luna"
    /// Models retired for ChatGPT-account sign-ins (mirrors the engine's CODEX_RETIRED_MODELS).
    public static let retiredCodexModels: Set<String> = ["gpt-5.4-mini"]

    /// Missing or retired → the current default, so the next save rewrites a stale .env pin.
    public static func migratedCodexModel(_ raw: String?) -> String {
        guard let raw, !retiredCodexModels.contains(raw) else { return defaultCodexModel }
        return raw
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

public enum ToolRequirements {
    /// Maps the engine's ACTIVATION_TOOL setting to the CLIs the schedule will
    /// actually invoke, so the app only treats those as required. Unknown values
    /// fall back to requiring both — a typo must not hide a missing CLI.
    public static func requiredCLIs(activationTool raw: String?) -> Set<String> {
        switch raw?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "claude": return ["claude"]
        case "codex": return ["codex"]
        default: return ["claude", "codex"]
        }
    }
}

public enum ClaudeQuotaSource {
    /// Resolves the oh-my-claudecode usage cache path exactly like the engine does
    /// (bin/activate-ai-window.sh): CLAUDE_USAGE_CACHE_FILE wins, then
    /// ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/oh-my-claudecode/.usage-cache-anthropic.json.
    /// Both install routes (npm and Claude Code plugin) write this cache, so its
    /// presence means quota snapshots work even with no `omc` binary on PATH.
    public static func usageCacheFile(env: [String: String], home: String) -> String {
        if let override = nonEmpty(env["CLAUDE_USAGE_CACHE_FILE"]) {
            return expandHome(override, home: home)
        }
        let configDir = nonEmpty(env["CLAUDE_CONFIG_DIR"]).map { expandHome($0, home: home) }
            ?? home + "/.claude"
        return configDir + "/plugins/oh-my-claudecode/.usage-cache-anthropic.json"
    }

    /// The cache file proves quota snapshots will work only when the engine will
    /// actually read it: CLAUDE_STATUS_SOURCE=cache, unset, or empty (the engine
    /// defaults empty to cache via ${VAR:-cache}). Any other value — including
    /// casings the engine's validator would reject — returns nil so a stale
    /// legacy `omc` setting can't render a green "installed" over snapshots
    /// that fail every run.
    public static func usageCacheSignalFile(env: [String: String], home: String) -> String? {
        // First whitespace-delimited token: bash reads `cache # comment` in an unquoted
        // .env assignment as just `cache` (the rest is a comment), while EnvParser keeps
        // the whole line — the token is what the engine actually sees.
        let source = (env["CLAUDE_STATUS_SOURCE"] ?? "")
            .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard source.isEmpty || source == "cache" else { return nil }
        return usageCacheFile(env: env, home: home)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Expands the HOME spellings .env files actually use: `~`, `$HOME`, `${HOME}`.
    /// bash only tilde-expands unquoted values, but EnvParser strips quotes before
    /// we see them — expanding unconditionally is a deliberate leniency (a detector
    /// false-"installed" on a quoted `"~/…"` beats nagging every unquoted one).
    /// Full shell expansion is out of scope.
    private static func expandHome(_ path: String, home: String) -> String {
        if path == "~" || path == "$HOME" || path == "${HOME}" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        if path.hasPrefix("${HOME}/") { return home + String(path.dropFirst(7)) }
        if path.hasPrefix("$HOME/") { return home + String(path.dropFirst(5)) }
        return path
    }
}
