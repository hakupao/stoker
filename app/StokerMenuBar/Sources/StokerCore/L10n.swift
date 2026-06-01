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
