import Foundation

public enum AppLanguage: String, Sendable {
    case zh, en

    public static var current: AppLanguage {
        get {
            if let saved = UserDefaults.standard.string(forKey: "appLanguage") {
                return AppLanguage(rawValue: saved) ?? .system
            }
            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
        }
    }

    private static var system: AppLanguage {
        Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true ? .zh : .en
    }
}

public enum L10n {
    // MARK: - Header
    public static var appSubtitle: String {
        AppLanguage.current == .zh ? "定时激活 Claude 和 Codex 的使用窗口" : "Schedule Claude and Codex activation windows"
    }

    // MARK: - Status Card
    public static var scheduleOn: String {
        AppLanguage.current == .zh ? "定时已开启" : "Schedule On"
    }
    public static var scheduleOff: String {
        AppLanguage.current == .zh ? "定时未开启" : "Schedule Off"
    }

    // MARK: - Quota
    public static var fiveHour: String {
        AppLanguage.current == .zh ? "5 小时" : "5 Hour"
    }
    public static var weekly: String {
        AppLanguage.current == .zh ? "周" : "Weekly"
    }
    public static var noData: String {
        AppLanguage.current == .zh ? "暂无数据" : "No data"
    }
    public static var na: String {
        AppLanguage.current == .zh ? "暂无" : "N/A"
    }
    /// Legend clarifying that the header bars show *remaining* quota, not used.
    public static var quotaRemaining: String {
        AppLanguage.current == .zh ? "剩余额度" : "Remaining"
    }
    /// Tooltip spelling out both sides of the 5-hour window so "余额 vs 已用" is unambiguous.
    public static func quotaMiniHelp(remaining: Double?, used: Double?) -> String {
        guard let remaining else {
            return AppLanguage.current == .zh ? "暂无额度数据" : "No quota data yet"
        }
        let r = Int(remaining.rounded())
        if AppLanguage.current == .zh {
            var s = "本 5 小时窗口剩余 \(r)%"
            if let used { s += "（已用 \(Int(used.rounded()))%）" }
            return s
        } else {
            var s = "5-hour window: \(r)% remaining"
            if let used { s += " (\(Int(used.rounded()))% used)" }
            return s
        }
    }
    public static var noRunHistory: String {
        AppLanguage.current == .zh ? "暂无运行记录" : "No run history"
    }
    public static var lastRun: String {
        AppLanguage.current == .zh ? "上次运行：" : "Last run: "
    }
    public static var skipped: String {
        AppLanguage.current == .zh ? "跳过" : "Skipped"
    }

    // MARK: - Schedule
    public static var schedule: String {
        AppLanguage.current == .zh ? "运行时间" : "Schedule"
    }
    public static var add: String {
        AppLanguage.current == .zh ? "添加" : "Add"
    }
    public static var nextRunPrefix: String {
        AppLanguage.current == .zh ? "下次" : "Next"
    }
    /// Countdown to the next scheduled run, e.g. "还有 2 小时 13 分" / "in 2h 13m".
    public static func nextRunCountdown(hours: Int, minutes: Int) -> String {
        if AppLanguage.current == .zh {
            if hours > 0 { return "还有 \(hours) 小时 \(minutes) 分" }
            if minutes > 0 { return "还有 \(minutes) 分钟" }
            return "即将运行"
        } else {
            if hours > 0 { return "in \(hours)h \(minutes)m" }
            if minutes > 0 { return "in \(minutes)m" }
            return "due now"
        }
    }

    // MARK: - Tools
    public static var tools: String {
        AppLanguage.current == .zh ? "工具" : "Tools"
    }
    public static var toolsDescription: String {
        AppLanguage.current == .zh ? "选择要定时激活的 AI 工具。" : "Select AI tools to activate on schedule."
    }

    // MARK: - Advanced
    public static var advanced: String {
        AppLanguage.current == .zh ? "高级设置" : "Advanced"
    }
    public static var checkQuotaBefore: String {
        AppLanguage.current == .zh ? "运行前检查剩余额度" : "Check quota before running"
    }
    public static var recordSnapshotAfter: String {
        AppLanguage.current == .zh ? "运行后记录额度快照" : "Record quota snapshot after running"
    }
    public static var codexModel: String {
        AppLanguage.current == .zh ? "Codex 模型" : "Codex model"
    }
    public static var whenQuotaUnavailable: String {
        AppLanguage.current == .zh ? "查不到额度时" : "When quota unavailable"
    }
    public static var continueAnyway: String {
        AppLanguage.current == .zh ? "照常运行" : "Continue"
    }
    public static var skip: String {
        AppLanguage.current == .zh ? "跳过" : "Skip"
    }
    public static var keepAwake: String {
        AppLanguage.current == .zh ? "防睡眠" : "Keep Awake"
    }
    /// Spells out the launchd sleep behavior next to the Keep Awake picker (per user request:
    /// neither README nor app surfaced this before).
    public static var keepAwakeNote: String {
        AppLanguage.current == .zh
            ? "睡眠期间 launchd 不会触发（唤醒后只补跑一次）；防睡眠仅保护运行期间，不会唤醒电脑。要让定时可靠命中，请让 Mac 在计划时刻保持唤醒。"
            : "launchd doesn't fire while the Mac sleeps (it runs one missed job on wake). Keep-awake only protects a run in progress — it can't wake the Mac. Keep the Mac awake at those times to hit the schedule reliably."
    }
    public static var openConfigFile: String {
        AppLanguage.current == .zh ? "打开配置文件（.env）" : "Open config file (.env)"
    }
    public static var off: String {
        AppLanguage.current == .zh ? "关闭" : "Off"
    }
    public static var duringRun: String {
        AppLanguage.current == .zh ? "运行期间" : "During run"
    }
    public static var whileAppOpen: String {
        AppLanguage.current == .zh ? "App 打开时" : "While app open"
    }
    public static var durationSeconds: String {
        AppLanguage.current == .zh ? "保护时长（秒）" : "Duration (seconds)"
    }
    public static var launchAtLogin: String {
        AppLanguage.current == .zh ? "登录时自动启动" : "Launch at login"
    }

    // MARK: - Actions
    public static var save: String {
        AppLanguage.current == .zh ? "保存" : "Save"
    }
    public static var runOnce: String {
        AppLanguage.current == .zh ? "运行一次" : "Run Once"
    }
    public static var logs: String {
        AppLanguage.current == .zh ? "日志" : "Logs"
    }
    public static var help: String {
        AppLanguage.current == .zh ? "帮助" : "Help"
    }

    // MARK: - Menu
    public static var quit: String {
        AppLanguage.current == .zh ? "退出" : "Quit"
    }
    public static var settings: String {
        AppLanguage.current == .zh ? "设置..." : "Settings..."
    }
    /// Tab label — no trailing ellipsis, unlike the menu's `settings`.
    public static var settingsTab: String {
        AppLanguage.current == .zh ? "设置" : "Settings"
    }
    public static var environmentCheck: String {
        AppLanguage.current == .zh ? "环境检查..." : "Environment Check..."
    }

    // MARK: - Notifications
    public static var savedAndEnabled: String {
        AppLanguage.current == .zh ? "已保存并开启" : "Saved and enabled"
    }
    public static var disabled: String {
        AppLanguage.current == .zh ? "已关闭" : "Disabled"
    }
    public static var scheduleElsewhere: String {
        AppLanguage.current == .zh
            ? "定时已加载，但来自另一个副本；请在那个目录里开关，此处操作无效"
            : "Schedule is loaded from a different copy; manage it from that folder — toggling here won't apply"
    }
    public static var triggered: String {
        AppLanguage.current == .zh ? "已触发，额度稍后更新" : "Triggered, quota will update shortly"
    }
    public static var failedToReadStatus: String {
        AppLanguage.current == .zh ? "读取状态失败" : "Failed to read status"
    }
    public static var saveFailed: String {
        AppLanguage.current == .zh ? "保存失败" : "Save failed"
    }
    public static var failed: String {
        AppLanguage.current == .zh ? "失败" : "failed"
    }
    public static var keepAwakeFailed: String {
        AppLanguage.current == .zh ? "防睡眠启动失败" : "Keep-awake failed"
    }
    public static var launchAtLoginFailed: String {
        AppLanguage.current == .zh ? "登录启动设置失败" : "Launch at login failed"
    }

    // MARK: - Background Auth
    public static var backgroundAuth: String {
        AppLanguage.current == .zh ? "后台认证" : "Background auth"
    }
    public static var authModeToken: String {
        AppLanguage.current == .zh ? "长效令牌" : "Long-lived token"
    }
    public static var authModeKeychain: String {
        AppLanguage.current == .zh ? "钥匙串登录" : "Keychain login"
    }
    /// Shown in the keychain-fallback state: why unattended runs are unreliable without a token.
    public static var authKeychainWarning: String {
        AppLanguage.current == .zh
            ? "未配置长效令牌，后台运行将沿用交互式钥匙串登录，可能因令牌过期而中断并需重新登录。"
            : "No long-lived token configured. Background runs fall back to the interactive Keychain login, which may expire and require re-login."
    }
    public static var authenticate: String {
        AppLanguage.current == .zh ? "配置长效令牌" : "Configure token"
    }
    public static var reauthenticate: String {
        AppLanguage.current == .zh ? "重新生成令牌" : "Regenerate token"
    }
    public static var authSheetTitle: String {
        AppLanguage.current == .zh ? "配置后台认证令牌" : "Configure background authentication"
    }
    public static var authSheetIntro: String {
        AppLanguage.current == .zh
            ? "在弹出的浏览器中完成登录，令牌将自动写入 .env。此后 launchd 定时任务可独立认证，无需 /login，且不影响交互式会话。令牌有效期约一年，按订阅计费。"
            : "Complete the login in the browser that opens; the token is written to .env automatically. Scheduled launchd runs then authenticate independently, with no /login required and no impact on interactive sessions. The token is valid for about one year and bills to your subscription."
    }
    public static var authStart: String {
        AppLanguage.current == .zh ? "开始（将打开浏览器）" : "Start (opens browser)"
    }
    public static var authWaiting: String {
        AppLanguage.current == .zh ? "等待浏览器登录完成…" : "Waiting for browser login…"
    }
    public static var authOpenLoginPage: String {
        AppLanguage.current == .zh ? "打开登录页面" : "Open login page"
    }
    public static var authPasteManually: String {
        AppLanguage.current == .zh ? "手动输入令牌" : "Enter token manually"
    }
    public static var authOpenInTerminal: String {
        AppLanguage.current == .zh ? "在终端运行 claude setup-token" : "Run claude setup-token in Terminal"
    }
    public static var authPastePlaceholder: String { "sk-ant-oat01-…" }
    public static var authSaved: String {
        AppLanguage.current == .zh ? "令牌已保存至 .env" : "Token saved to .env"
    }
    public static var authSavedDetail: String {
        AppLanguage.current == .zh
            ? "后台运行将使用此长效令牌独立认证，无需 /login，且不影响交互式会话。"
            : "Background runs will authenticate with this long-lived token — no /login required, with no impact on interactive sessions."
    }
    public static var done: String {
        AppLanguage.current == .zh ? "完成" : "Done"
    }
    public static var manage: String {
        AppLanguage.current == .zh ? "管理" : "Manage"
    }
    public static var setUpNow: String {
        AppLanguage.current == .zh ? "配置" : "Configure"
    }
    public static var authHealthyTag: String {
        AppLanguage.current == .zh ? "已配置" : "Configured"
    }
    public static var authAttentionTag: String {
        AppLanguage.current == .zh ? "未配置" : "Not configured"
    }
    public static var authHealthyDetail: String {
        AppLanguage.current == .zh
            ? "后台运行正使用专属长效令牌认证，稳定可靠；可随时重新生成。"
            : "Background runs authenticate with a dedicated long-lived token. You can regenerate it at any time."
    }
    public static var authTokenInvalid: String {
        AppLanguage.current == .zh ? "令牌格式无效（须以 sk-ant-oat01- 开头）。" : "Invalid token format (must start with sk-ant-oat01-)."
    }
    public static var authFailed: String {
        AppLanguage.current == .zh ? "未能获取令牌，请重试或手动输入。" : "Could not obtain the token. Retry, or enter it manually."
    }
    public static var authTimedOut: String {
        AppLanguage.current == .zh ? "操作超时，请重试或手动输入。" : "Timed out. Retry, or enter the token manually."
    }
    public static var authClaudeNotFound: String {
        AppLanguage.current == .zh
            ? "未找到 claude 命令，请确认已安装，或手动输入令牌。"
            : "claude command not found. Verify it is installed, or enter the token manually."
    }
    public static var authPtyFailed: String {
        AppLanguage.current == .zh ? "无法启动认证流程，请改用手动输入。" : "Could not start authentication. Enter the token manually."
    }

    // MARK: - Onboarding
    public static var environmentCheckTitle: String {
        AppLanguage.current == .zh ? "环境检查" : "Environment Check"
    }
    public static var environmentCheckSubtitle: String {
        AppLanguage.current == .zh ? "检测所需命令行工具是否已安装" : "Check if required CLI tools are installed"
    }
    public static var notFound: String {
        AppLanguage.current == .zh ? "未找到" : "Not found"
    }
    public static var installed: String {
        AppLanguage.current == .zh ? "已安装" : "Installed"
    }
    public static var requiredTools: String {
        AppLanguage.current == .zh ? "必需" : "Required"
    }
    public static var optionalTools: String {
        AppLanguage.current == .zh ? "可选" : "Optional"
    }
    public static var builtIn: String {
        AppLanguage.current == .zh ? "已内置" : "Built-in"
    }
    public static var notInstalled: String {
        AppLanguage.current == .zh ? "未安装" : "Not installed"
    }
    public static var dontShowAgain: String {
        AppLanguage.current == .zh ? "不再提示" : "Don't show again"
    }
    public static var close: String {
        AppLanguage.current == .zh ? "关闭" : "Close"
    }
    public static var processing: String {
        AppLanguage.current == .zh ? "处理中..." : "Processing..."
    }

    // MARK: - Language Toggle
    public static var switchToEnglish: String { "Switch to English" }
    public static var switchToChinese: String { "切换到中文" }

    // MARK: - Activity
    public static var activity: String {
        AppLanguage.current == .zh ? "活动" : "Activity"
    }
    public static var quotaTrend: String {
        AppLanguage.current == .zh ? "额度趋势" : "Quota Trend"
    }
    public static var quotaOverview: String {
        AppLanguage.current == .zh ? "额度概览" : "Quota Overview"
    }
    /// Shown in a gauge row when a tool is configured but its latest snapshot has no readable quota.
    public static var quotaUnknownShort: String {
        AppLanguage.current == .zh ? "额度未知" : "Quota unknown"
    }
    /// Shown under the quota card's empty state so users can discover the optional quota feature
    /// without it ever being required — core scheduling works fine without any quota source.
    public static var quotaSetupHint: String {
        AppLanguage.current == .zh
            ? "可选：安装 oh-my-claudecode 插件，或在 .env 中设 CLAUDE_STATUS_SOURCE=native，即可显示 Claude 额度"
            : "Optional: install the oh-my-claudecode plugin — or set CLAUDE_STATUS_SOURCE=native in .env — to show Claude quota"
    }
    /// Inline tag on the gauge bar so the % is unambiguously "remaining", not "used".
    public static var remaining: String {
        AppLanguage.current == .zh ? "剩余" : "Remaining"
    }
    /// Reset countdown from the snapshot's absolute reset time (accurate even when the remaining%
    /// reading is stale). Returns nil once the reset is in the past. Scales the unit to the
    /// distance — minutes < 1h, hours < 1 day, else days — so the weekly window (resets up to
    /// ~7 days out) reads "3 天后重置" instead of "71 小时后重置".
    public static func resetsIn(_ resetAt: Date, now: Date) -> String? {
        let secs = resetAt.timeIntervalSince(now)
        guard secs > 0 else { return nil }
        let totalMin = Int(secs / 60)
        let h = totalMin / 60
        let m = totalMin % 60
        let d = Int((Double(h) / 24).rounded())
        if AppLanguage.current == .zh {
            if h >= 24 { return "\(d) 天后重置" }
            if h >= 1 { return "\(h) 小时后重置" }
            return "\(max(1, m)) 分钟后重置"
        } else {
            if h >= 24 { return "resets in \(d)d" }
            if h >= 1 { return "resets in \(h)h" }
            return "resets in \(max(1, m))m"
        }
    }
    /// Honest "as of" label for the gauge — the remaining% is the last snapshot's value, not live.
    public static func updatedAt(_ date: Date) -> String {
        let t = LogTimestamp.display(date)
        return AppLanguage.current == .zh ? "更新于 \(t)" : "updated \(t)"
    }
    public static var allTools: String {
        AppLanguage.current == .zh ? "全部" : "All"
    }
    public static var today: String {
        AppLanguage.current == .zh ? "今天" : "Today"
    }
    public static var sevenDays: String {
        AppLanguage.current == .zh ? "7 天" : "7 Days"
    }
    public static var thirtyDays: String {
        AppLanguage.current == .zh ? "30 天" : "30 Days"
    }
    public static var allTime: String {
        AppLanguage.current == .zh ? "全部" : "All Time"
    }
    public static var allStatus: String {
        AppLanguage.current == .zh ? "全部状态" : "All Status"
    }
    public static var exportCsv: String {
        AppLanguage.current == .zh ? "导出 CSV" : "Export CSV"
    }
    public static var totalRuns: String {
        AppLanguage.current == .zh ? "总运行" : "Total Runs"
    }
    public static var avgCost: String {
        AppLanguage.current == .zh ? "均价" : "Avg Cost"
    }
    public static var runHistory: String {
        AppLanguage.current == .zh ? "运行记录" : "Run History"
    }
    public static var noRunsInRange: String {
        AppLanguage.current == .zh ? "所选范围内暂无记录" : "No runs in selected range"
    }
    public static var noRunsYet: String {
        AppLanguage.current == .zh ? "暂无运行数据" : "No activity yet"
    }
    public static var noRunsHint: String {
        AppLanguage.current == .zh ? "运行一次后，活动记录会显示在这里" : "Activity will appear here after the first run"
    }
    public static var inputLabel: String {
        AppLanguage.current == .zh ? "输入" : "In"
    }
    public static var outputLabel: String {
        AppLanguage.current == .zh ? "输出" : "Out"
    }
    public static var cacheLabel: String {
        AppLanguage.current == .zh ? "缓存" : "Cache"
    }
    public static var reasoningLabel: String {
        AppLanguage.current == .zh ? "推理" : "Reason"
    }
    public static var durationLabel: String {
        AppLanguage.current == .zh ? "耗时" : "Time"
    }
    public static var sessionLabel: String {
        AppLanguage.current == .zh ? "会话" : "Session"
    }
    public static var exported: String {
        AppLanguage.current == .zh ? "已导出" : "Exported"
    }
    /// Label for the model's raw reply, shown in the expanded run detail (the run-history
    /// row headline now shows a normalized status marker instead of this free-form text).
    public static var replyLabel: String {
        AppLanguage.current == .zh ? "回复" : "Reply"
    }
    /// Human-readable label for a usage row's machine `skip_reason`. The quota preflight only
    /// emits a small known set; anything that isn't an outright "exhausted" verdict means the
    /// preflight couldn't read quota, so it collapses to "quota unknown" rather than leaking a
    /// raw token like `preflight_status_missing` into the UI.
    public static func skipReasonText(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        switch raw {
        case "quota_exhausted":
            return AppLanguage.current == .zh ? "配额耗尽" : "Quota exhausted"
        default:
            return AppLanguage.current == .zh ? "额度未知" : "Quota unknown"
        }
    }

    // MARK: - Misc
    public static var checking: String {
        AppLanguage.current == .zh ? "正在检测…" : "Checking…"
    }
    public static var unknown: String {
        AppLanguage.current == .zh ? "未知" : "Unknown"
    }
    public static var success: String {
        AppLanguage.current == .zh ? "成功" : "Success"
    }
}
