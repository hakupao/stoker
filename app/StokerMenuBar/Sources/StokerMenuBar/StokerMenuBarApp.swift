import StokerCore
import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@main
struct StokerMenuBarApp: App {
    @StateObject private var model = StokerAppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .task {
                await model.refresh()
            }
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)

        Window("Stoker", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 760, height: 720)
    }
}

// MARK: - Menu Bar Label

/// The `MenuBarExtra` label: the branded monochrome Stoker mark (schedule-sweep arc +
/// centered ember dot), loaded as a macOS TEMPLATE image so the system tints it for
/// light/dark menu bars and the highlighted state. The icon no longer encodes
/// installed/not-installed — schedule state is shown by the window + the menu's text rows.
/// The accessible text ("Stoker") is preserved via `Label`. Falls back to an SF Symbol when
/// the bundled template asset is unavailable (e.g. `swift run` without the built bundle).
struct MenuBarLabel: View {
    var body: some View {
        if let icon = Self.templateIcon {
            Label {
                Text("Stoker")
            } icon: {
                Image(nsImage: icon)
            }
        } else {
            Label("Stoker", systemImage: "timer")
        }
    }

    /// The bundled menu bar template, loaded once and marked `isTemplate` so AppKit tints it.
    private static let templateIcon: NSImage? = {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

// MARK: - Model

@MainActor
final class StokerAppModel: ObservableObject {
    @Published var state: ActivationState?
    @Published var settings: AppSettings
    @Published var statusMessage = ""
    @Published var statusIsError = false
    @Published var isBusy = false
    @Published var launchAtLogin: Bool
    @Published var requestToolCheck = false

    let root: URL
    private var keepAwakeProcess: Process?

    init() {
        root = ProjectLocator.findRoot()
        settings = AppSettings(values: EnvParser.parse(Self.readEnv(root: root)))
        launchAtLogin = SMAppService.mainApp.status == .enabled
        updateKeepAwakeProcess()
    }

    deinit {
        keepAwakeProcess?.terminate()
    }

    /// Refresh activation state from the engine.
    /// - Parameters:
    ///   - silent: skip the `isBusy` spinner and error banner — used by background polling.
    ///   - reloadSettings: re-read `.env` into `settings`. Background ticks pass `false` so a
    ///     periodic refresh never clobbers edits the user is typing but hasn't saved yet.
    func refresh(silent: Bool = false, reloadSettings: Bool = true) async {
        if !silent { isBusy = true }
        defer { if !silent { isBusy = false } }

        do {
            let output = try await runExecutable(root.appendingPathComponent("bin/activation-state.sh"), arguments: ["--json"])
            let data = Data(output.utf8)
            state = try JSONDecoder().decode(ActivationState.self, from: data)
            if reloadSettings {
                settings = AppSettings(values: EnvParser.parse(Self.readEnv(root: root)))
            }
            updateKeepAwakeProcess()
        } catch {
            if !silent { showStatus(L10n.failedToReadStatus, isError: true) }
        }
    }

    func toggleSchedule() {
        if state?.installed == true {
            runInstallCommand("uninstall", success: L10n.disabled)
        } else if let mismatch = state?.launchctl?.mismatch, !mismatch.isEmpty {
            // A LaunchAgent is already loaded from a different root (e.g. an
            // app-support copy of the engine). Installing from here would
            // silently repoint the schedule at this copy and strand the user's
            // real setup. Surface it instead of doing a hidden migration.
            showStatus(L10n.scheduleElsewhere, isError: true)
        } else {
            runInstallCommand("install", success: L10n.scheduleOn)
        }
    }

    func runInstall() {
        runInstallCommand("install", success: L10n.savedAndEnabled)
    }

    func runNow() {
        runInstallCommand("run-now", success: L10n.triggered)
    }

    func runNowWithDelayedRefresh() {
        runNow()
        Task {
            try? await Task.sleep(for: .seconds(10))
            await refresh()
        }
    }

    func openLogs() {
        NSWorkspace.shared.open(root.appendingPathComponent("logs"))
    }

    /// Reveal the `.env` that backs every setting (single source of truth shared with the CLI).
    func openConfigFile() {
        let env = root.appendingPathComponent(".env")
        if FileManager.default.fileExists(atPath: env.path) {
            NSWorkspace.shared.activateFileViewerSelecting([env])
        } else {
            NSWorkspace.shared.open(root)
        }
    }

    func openInstallGuide() {
        let file = AppLanguage.current == .zh ? "INSTALL_CN.md" : "INSTALL.md"
        let guide = root.appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: guide.path) {
            NSWorkspace.shared.open(guide)
            return
        }
        NSWorkspace.shared.open(root.appendingPathComponent("INSTALL.md"))
    }

    func saveSettingsAndReload() {
        do {
            let envURL = root.appendingPathComponent(".env")
            let existing: String
            if FileManager.default.fileExists(atPath: envURL.path) {
                existing = try String(contentsOf: envURL, encoding: .utf8)
            } else {
                existing = Self.readEnv(root: root)
            }

            let updated = EnvFile.updating(existing, values: settings.envValues)
            try updated.write(to: envURL, atomically: true, encoding: .utf8)
            updateKeepAwakeProcess()
            runInstall()
        } catch {
            showStatus(L10n.saveFailed, isError: true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            showStatus(L10n.launchAtLoginFailed, isError: true)
        }
    }

    func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
        Task {
            try? await Task.sleep(for: .seconds(3))
            if statusMessage == message {
                withAnimation(.easeOut(duration: 0.3)) {
                    statusMessage = ""
                }
            }
        }
    }

    func addTime(_ time: String) {
        guard let normalized = ScheduleFormatter.normalize(time) else { return }
        if !settings.scheduleTimes.contains(normalized) {
            settings.scheduleTimes.append(normalized)
            settings.scheduleTimes.sort()
        }
    }

    func removeTime(at index: Int) {
        guard settings.scheduleTimes.count > 1, settings.scheduleTimes.indices.contains(index) else { return }
        settings.scheduleTimes.remove(at: index)
    }

    private func runInstallCommand(_ command: String, success: String) {
        Task {
            isBusy = true
            defer { isBusy = false }

            do {
                _ = try await runExecutable(root.appendingPathComponent("install.sh"), arguments: [command])
                showStatus(success, isError: false)
                await refresh()
            } catch {
                showStatus("\(command) \(L10n.failed)", isError: true)
            }
        }
    }

    private func updateKeepAwakeProcess() {
        if settings.keepAwakeMode == "always" {
            guard keepAwakeProcess?.isRunning != true else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            process.arguments = ["-dimsu"]
            do {
                try process.run()
                keepAwakeProcess = process
            } catch {
                statusMessage = L10n.keepAwakeFailed
            }
        } else {
            keepAwakeProcess?.terminate()
            keepAwakeProcess = nil
        }
    }

    private func runExecutable(_ executable: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [root] in
            let process = Process()
            let output = Pipe()
            let error = Pipe()

            process.currentDirectoryURL = root
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error

            try process.run()
            process.waitUntilExit()

            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let outputText = String(data: outputData, encoding: .utf8) ?? ""
            let errorText = String(data: errorData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw CommandError(status: process.terminationStatus, message: errorText.isEmpty ? outputText : errorText)
            }

            return outputText
        }.value
    }

    private static func readEnv(root: URL) -> String {
        let env = root.appendingPathComponent(".env")
        if let contents = try? String(contentsOf: env, encoding: .utf8) {
            return contents
        }
        let example = root.appendingPathComponent(".env.example")
        return (try? String(contentsOf: example, encoding: .utf8)) ?? ""
    }
}

// MARK: - Locale Store

/// Observable source of truth for the UI language. `AppLanguage.current` (UserDefaults) stays
/// what `L10n` reads; this just publishes a change so SwiftUI refreshes. A bare UserDefaults
/// write doesn't refresh views SwiftUI skips during diffing (e.g. `ForEach` rows whose inputs
/// are unchanged) — the run-history list was the visible victim, re-localizing only on hover.
/// The main window re-identifies its content on `language` to rebuild every localized subview
/// at once; the onboarding sheet (presented outside that subtree) observes this store directly.
@MainActor
final class LocaleStore: ObservableObject {
    static let shared = LocaleStore()
    @Published private(set) var language: AppLanguage

    private init() { language = AppLanguage.current }

    /// Flip zh↔en, persist to UserDefaults, and publish so every observer refreshes.
    func toggle() {
        let next: AppLanguage = (language == .zh) ? .en : .zh
        AppLanguage.current = next
        language = next
    }
}

struct CommandError: LocalizedError {
    var status: Int32
    var message: String

    var errorDescription: String? {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "exit \(status)" : cleaned
    }
}

// MARK: - Design System

enum DS {
    static let cardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16

    // Primary text resolves to the correct Light/Dark label color automatically.
    // (Secondary/muted/hairline now flow through StokerTheme so they participate
    // in the synchronized appearance + state theming.)
    static let textPrimary = Color(nsColor: .labelColor)

    static func quotaLabel(_ pct: Double?) -> String {
        guard let pct else { return "--" }
        return "\(Int(pct.rounded()))%"
    }
}

// MARK: - Stoker "Forge" Theme (appearance × state aware)
//
// Single source of truth: design/stoker-ui-pack/design-tokens.json.
// A StokerTheme is a fully-resolved set of semantic role colors for ONE of the
// four variants: (light/dark) × (idle/active). Surfaces (surface/header/card)
// carry the idle→active warmth shift; everything else is flat per appearance.
// Injected via EnvironmentKey so every subview reads the same resolved theme and
// the whole window warms in lockstep off a single `value: isOn` transition.

struct StokerTheme {
    // Surfaces (idle/active warmth shift)
    let surface: Color
    let header: Color
    let card: Color

    // Lines / fills
    let hairline: Color
    let fillSubtle: Color

    // Text tiers
    let onSurface: Color
    let textSecondary: Color
    let textMuted: Color

    // Accents
    let accent: Color       // copper — idle chrome accents
    let accentOn: Color     // ember — ON-signal: toggle tint + status dot
    /// Contrast-safe ember for text/icons ON LIGHT surfaces: plain ember (#E36E43) fails
    /// contrast on cream, so use accentText (#B5482A in Light) for any ember-colored text/icon.
    let accentText: Color   // ember-as-text/icon (contrast-safe per appearance)
    let accentHot: Color    // glow / hot-core highlight only (badge ember)

    // Status
    let positive: Color
    let warning: Color
    let danger: Color

    // Minor cool accent
    let accentSage: Color

    // Data series (kept vendor identity: Claude purple / Codex green)
    let seriesClaude: Color
    let seriesCodex: Color

    // The single coordinated "forge igniting" transition.
    static let forgeTransition: Animation = .easeInOut(duration: 0.45)

    /// Resolve the fully-specified theme for the current appearance and schedule state.
    static func resolve(colorScheme: ColorScheme, isOn: Bool) -> StokerTheme {
        switch colorScheme {
        case .dark:
            return StokerTheme(
                surface:       hex(isOn ? 0x2B211A : 0x1B1B1A),
                header:        hex(isOn ? 0x382819 : 0x232322),
                card:          hex(isOn ? 0x33271E : 0x242423),
                hairline:      Color(red: 243/255, green: 238/255, blue: 230/255, opacity: 0.12),
                fillSubtle:    Color(red: 243/255, green: 238/255, blue: 230/255, opacity: 0.08),
                onSurface:     hex(0xF1ECE3),
                textSecondary: hex(0xB8B1A6),
                textMuted:     hex(0x9D968B),
                accent:        hex(0xB97A54),
                accentOn:      hex(0xFF8A4D),
                accentText:    hex(0xE36E43),
                accentHot:     hex(0xFFB15E),
                positive:      hex(0x43B86C),
                warning:       hex(0xD89D38),
                danger:        hex(0xDC5B54),
                accentSage:    hex(0x9EB392),
                seriesClaude:  hex(0x8F70D9),
                seriesCodex:   hex(0x2EBF7D)
            )
        default: // .light
            return StokerTheme(
                surface:       hex(isOn ? 0xFBEFE3 : 0xF4F0E9),
                header:        hex(isOn ? 0xF6E2CE : 0xECE6DC),
                card:          hex(isOn ? 0xFFF6EC : 0xFBF8F2),
                hairline:      hex(0xDED7CD),
                fillSubtle:    Color(red: 23/255, green: 23/255, blue: 22/255, opacity: 0.06),
                onSurface:     hex(0x1A1916),
                textSecondary: hex(0x55514A),
                textMuted:     hex(0x827C72),
                accent:        hex(0xB97A54),
                accentOn:      hex(0xD85A2C),
                accentText:    hex(0xB5482A),
                accentHot:     hex(0xFFB15E),
                positive:      hex(0x2E8F50),
                warning:       hex(0xA8741E),
                danger:        hex(0xC0392F),
                accentSage:    hex(0x5E7257),
                seriesClaude:  hex(0x7B5FCB),
                seriesCodex:   hex(0x1A8F58)
            )
        }
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct StokerThemeKey: EnvironmentKey {
    static let defaultValue = StokerTheme.resolve(colorScheme: .light, isOn: false)
}

extension EnvironmentValues {
    var stokerTheme: StokerTheme {
        get { self[StokerThemeKey.self] }
        set { self[StokerThemeKey.self] = newValue }
    }
}

// MARK: - Button Style with Press Feedback

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Menu

struct MenuContentView: View {
    @ObservedObject var model: StokerAppModel
    var openSettings: () -> Void

    var body: some View {
        let isOn = model.state?.installed == true
        let loadedElsewhere = model.state?.launchctl?.mismatch?.isEmpty == false

        Button {
            model.toggleSchedule()
        } label: {
            Label(
                loadedElsewhere ? L10n.scheduleElsewhere : (isOn ? L10n.scheduleOn : L10n.scheduleOff),
                systemImage: loadedElsewhere ? "exclamationmark.triangle" : (isOn ? "circle.inset.filled" : "circle")
            )
        }

        if let state = model.state {
            Text("\(L10n.schedule): \(state.schedule.times.joined(separator: ", "))")
            Text(quotaSummary(state.quota))
        }

        Divider()

        Button(L10n.runOnce) { model.runNowWithDelayedRefresh() }

        Divider()

        Button(L10n.environmentCheck) {
            model.requestToolCheck = true
            openSettings()
        }
        Button(L10n.settings) { openSettings() }
        Button(L10n.quit) { NSApplication.shared.terminate(nil) }
    }

    private func quotaSummary(_ quota: [String: ActivationState.ToolQuota]) -> String {
        let claudeH = DS.quotaLabel(quota["claude"]?.fiveHour?.remainingPercent)
        let codexH = DS.quotaLabel(quota["codex"]?.fiveHour?.remainingPercent)
        return "Claude 5h \(claudeH) · Codex 5h \(codexH)"
    }
}

// MARK: - Tool Checker

enum ToolChecker {
    enum ToolCategory: Sendable { case required, optional }

    struct ToolInfo: Sendable {
        var name: String
        var found: Bool
        var builtIn: Bool
        var category: ToolCategory
        var installHint: String
        var descriptionEN: String
        var descriptionZH: String
        /// Resolved at render time (not check time) so it follows a live language switch.
        var toolDescription: String { AppLanguage.current == .zh ? descriptionZH : descriptionEN }
    }

    private static let toolDefinitions: [(name: String, hint: String, cat: ToolCategory, en: String, zh: String)] = [
        ("claude", "npm i -g @anthropic-ai/claude-code", .required,
         "Activate Claude Code usage windows", "激活 Claude Code 使用窗口"),
        ("codex", "npm i -g @openai/codex", .required,
         "Activate Codex usage windows", "激活 Codex 使用窗口"),
        ("jq", "brew install jq", .required,
         "JSON processor for quota data", "JSON 处理工具，用于额度数据"),
        ("node", "brew install node", .optional,
         "Enables Codex quota snapshots", "启用 Codex 额度快照"),
        ("omc", "npm i -g oh-my-claudecode", .optional,
         "Enables Claude quota snapshots", "启用 Claude 额度快照"),
    ]

    static func checkMissingTools(root: URL? = nil) async -> [String] {
        var missing: [String] = []
        for def in toolDefinitions where def.cat == .required {
            let (found, _) = await toolStatus(def.name, root: root)
            if !found { missing.append(def.name) }
        }
        return missing
    }

    static func checkAllTools(root: URL? = nil) async -> [ToolInfo] {
        var results: [ToolInfo] = []
        for def in toolDefinitions {
            let (found, builtIn) = await toolStatus(def.name, root: root)
            results.append(ToolInfo(
                name: def.name, found: found, builtIn: builtIn,
                category: def.cat, installHint: def.hint,
                descriptionEN: def.en, descriptionZH: def.zh
            ))
        }
        return results
    }

    private static let searchPaths = [
        "\(NSHomeDirectory())/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]

    private static func toolStatus(_ name: String, root: URL?) async -> (found: Bool, builtIn: Bool) {
        await Task.detached(priority: .userInitiated) {
            if let root {
                let bundled = root.appendingPathComponent("bin/\(name)").path
                if FileManager.default.isExecutableFile(atPath: bundled) {
                    return (true, true)
                }
            }

            for dir in searchPaths {
                let path = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return (true, false)
                }
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-l", "-c", "which \(name)"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                return (process.terminationStatus == 0, false)
            } catch {
                return (false, false)
            }
        }.value
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var isPresented: Bool
    var root: URL?
    @Environment(\.stokerTheme) private var theme
    @ObservedObject private var locale = LocaleStore.shared
    @AppStorage("hideOnboarding") private var hideOnboarding = false
    @State private var toolResults: [ToolChecker.ToolInfo] = []
    @State private var isChecking = true

    private var requiredTools: [ToolChecker.ToolInfo] {
        toolResults.filter { $0.category == .required }
    }
    private var optionalTools: [ToolChecker.ToolInfo] {
        toolResults.filter { $0.category == .optional }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.environmentCheckTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(L10n.environmentCheckSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
            }
            .padding(DS.cardPadding)

            Rectangle().fill(theme.hairline).frame(height: 1)

            if isChecking {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.checking)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ToolSectionCard(title: L10n.requiredTools, tools: requiredTools)
                        ToolSectionCard(title: L10n.optionalTools, tools: optionalTools)
                    }
                    .padding(.horizontal, DS.cardPadding)
                    .padding(.vertical, DS.cardPadding)
                }
            }

            HStack(spacing: 12) {
                Toggle(L10n.dontShowAgain, isOn: $hideOnboarding)
                    .font(.system(size: 13))
                    .toggleStyle(.checkbox)

                Spacer()

                Button(L10n.close) {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentOn)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(DS.cardPadding)
        }
        .frame(width: 400)
        .task {
            toolResults = await ToolChecker.checkAllTools(root: root)
            isChecking = false
        }
    }
}

struct ToolSectionCard: View {
    var title: String
    var tools: [ToolChecker.ToolInfo]
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(tools.enumerated()), id: \.element.name) { index, tool in
                    ToolStatusRow(tool: tool)
                    if index < tools.count - 1 {
                        Rectangle()
                            .fill(theme.hairline)
                            .frame(height: 1)
                            .padding(.leading, DS.cardPadding)
                    }
                }
            }
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1)
            )
        }
    }
}

struct ToolStatusRow: View {
    var tool: ToolChecker.ToolInfo
    @Environment(\.stokerTheme) private var theme
    @ObservedObject private var locale = LocaleStore.shared

    private var statusText: String {
        if tool.builtIn { return L10n.builtIn }
        if tool.found { return L10n.installed }
        if tool.category == .optional { return L10n.notInstalled }
        return L10n.notFound
    }

    private var statusColor: Color {
        if tool.builtIn { return theme.accent }
        if tool.found { return theme.positive }
        if tool.category == .optional { return theme.warning }
        return theme.danger
    }

    private var statusIcon: String {
        if tool.builtIn { return "shippingbox.circle.fill" }
        if tool.found { return "checkmark.circle.fill" }
        return "xmark.circle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)

                Text(tool.name)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))

                Spacer()

                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            Text(tool.toolDescription)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .padding(.leading, 26)

            if !tool.found && !tool.builtIn {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textMuted)
                    Text(tool.installHint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                }
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, DS.cardPadding)
        .padding(.vertical, 10)
    }
}

struct NotificationBanner: View {
    var message: String
    var isError: Bool
    @Environment(\.stokerTheme) private var theme

    private var icon: String { isError ? "xmark.circle.fill" : "checkmark.circle.fill" }
    private var color: Color { isError ? theme.danger : theme.positive }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
    }
}

// Stoker forge mark, native SwiftUI shapes (no external asset):
// a graphite squircle housing a copper ring, a sage progress arc (upper-right),
// and a central ember core that "stokes" with the schedule — dim copper when
// idle, ignited ember (accentHot glow) when active.
struct AppIconBadge: View {
    var isOn: Bool = false

    /// The real "Forge" app-icon art (the AI concept render), bundled into Resources as
    /// AppBadge.png by build-app.sh so the in-window badge matches the Dock icon exactly.
    /// Falls back to the native vector mark only for `swift run` (no app bundle to load from).
    private static let iconImage: NSImage? = NSImage(named: "AppBadge")

    var body: some View {
        if let icon = Self.iconImage {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        } else {
            ForgeBadgeMark(isOn: isOn)
        }
    }
}

/// Native vector fallback for the in-window badge (used only when AppBadge.png is not bundled,
/// e.g. `swift run`). Mirrors the Forge motif: graphite squircle + copper ring + sage arc + ember core.
private struct ForgeBadgeMark: View {
    var isOn: Bool

    private let graphite = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x16 / 255)
    private let graphite2 = Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x23 / 255)
    private let copper = Color(red: 0xB9 / 255, green: 0x7A / 255, blue: 0x54 / 255)
    private let sage = Color(red: 0x9E / 255, green: 0xB3 / 255, blue: 0x92 / 255)
    private let ember = Color(red: 0xE3 / 255, green: 0x6E / 255, blue: 0x43 / 255)
    private let emberHot = Color(red: 0xFF / 255, green: 0xB1 / 255, blue: 0x5E / 255)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [graphite2, graphite], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(copper.opacity(0.85), lineWidth: 2)
                .frame(width: 26, height: 26)
            Circle()
                .trim(from: 0.0, to: 0.28)
                .stroke(sage, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(RadialGradient(colors: isOn ? [emberHot, ember] : [copper, copper.opacity(0.7)],
                                     center: .center, startRadius: 0, endRadius: 7))
                .frame(width: 12, height: 12)
                .shadow(color: isOn ? emberHot.opacity(0.7) : .clear, radius: isOn ? 6 : 0)
        }
        .frame(width: 44, height: 44)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        .animation(StokerTheme.forgeTransition, value: isOn)
    }
}

// MARK: - Schedule Card

struct ScheduleCard: View {
    @ObservedObject var model: StokerAppModel
    @Environment(\.stokerTheme) private var theme
    @State private var newHour = 8
    @State private var newMinute = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(L10n.schedule)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            } icon: {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(theme.accent)
            }

            FlowLayout(spacing: 8) {
                ForEach(Array(model.settings.scheduleTimes.enumerated()), id: \.offset) { index, time in
                    TimePill(time: time, canDelete: model.settings.scheduleTimes.count > 1) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            model.removeTime(at: index)
                        }
                    }
                }

                AddTimePill(hour: $newHour, minute: $newMinute) {
                    let time = String(format: "%02d:%02d", newHour, newMinute)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.addTime(time)
                    }
                }
            }
        }
        .padding(DS.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
    }
}

struct TimePill: View {
    var time: String
    var canDelete: Bool
    var onDelete: () -> Void

    @Environment(\.stokerTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .font(.system(size: 10))
                .foregroundStyle(theme.accent.opacity(0.85))

            Text(time)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.onSurface)

            if canDelete && isHovering {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(theme.accent.opacity(isHovering ? 0.16 : 0.08))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(theme.accent.opacity(0.2), lineWidth: 1))
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

struct AddTimePill: View {
    @Binding var hour: Int
    @Binding var minute: Int
    var onAdd: () -> Void

    @Environment(\.stokerTheme) private var theme
    @State private var isExpanded = false

    var body: some View {
        if isExpanded {
            HStack(spacing: 4) {
                Picker("", selection: $hour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%02d", h)).tag(h)
                    }
                }
                .frame(width: 56)
                .labelsHidden()

                Text(":")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)

                Picker("", selection: $minute) {
                    ForEach(0..<60, id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .frame(width: 56)
                .labelsHidden()

                Button {
                    onAdd()
                    isExpanded = false
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(theme.accentOn)
                        .clipShape(Circle())
                }
                .buttonStyle(PressButtonStyle())

                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(theme.fillSubtle)
                        .clipShape(Circle())
                }
                .buttonStyle(PressButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.fillSubtle)
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(L10n.add)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(theme.fillSubtle)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(PressButtonStyle())
            .transition(.scale.combined(with: .opacity))
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let maxH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += maxH
            if i > 0 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for (i, row) in rows.enumerated() {
            let maxH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            if i > 0 { y += spacing }
            for sub in row {
                let size = sub.sizeThatFits(.unspecified)
                sub.place(at: CGPoint(x: x, y: y + (maxH - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += maxH
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(sub)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Tool Card

struct ToolCard: View {
    @ObservedObject var model: StokerAppModel
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(L10n.tools)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            } icon: {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(theme.accent)
            }

            HStack(spacing: 10) {
                ToolToggleTile(
                    name: "Claude",
                    icon: "c.circle.fill",
                    color: theme.seriesClaude,
                    isOn: $model.settings.enableClaude
                )
                ToolToggleTile(
                    name: "Codex",
                    icon: "chevron.left.forwardslash.chevron.right",
                    color: theme.seriesCodex,
                    isOn: $model.settings.enableCodex
                )
            }
        }
        .padding(DS.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
    }
}

struct ToolToggleTile: View {
    var name: String
    var icon: String
    var color: Color
    var isOn: Binding<Bool>

    @Environment(\.stokerTheme) private var theme

    var body: some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? color : theme.textMuted)

                Text(name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOn.wrappedValue ? theme.onSurface : theme.textSecondary)

                Spacer()

                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isOn.wrappedValue ? color : theme.textMuted.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isOn.wrappedValue ? color.opacity(0.08) : theme.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn.wrappedValue ? color.opacity(0.3) : theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isOn.wrappedValue)
    }
}

// MARK: - Advanced Settings (full-row clickable)

/// A low-key reveal: content settles down 8pt and fades in, rather than flying in from
/// the window edge. Pairs with a soft spring on `isExpanded`, matching the quiet `.opacity`
/// reveals already used by the run-history rows.
private struct RevealModifier: ViewModifier {
    var progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: (1 - progress) * -8)
    }
}

extension AnyTransition {
    static var advancedReveal: AnyTransition {
        .modifier(
            active: RevealModifier(progress: 0),
            identity: RevealModifier(progress: 1)
        )
    }
}

struct AdvancedSection: View {
    @ObservedObject var model: StokerAppModel
    @Environment(\.stokerTheme) private var theme
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                    Text(L10n.advanced)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textSecondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(L10n.checkQuotaBefore, isOn: $model.settings.enableQuotaPreflight)
                    Toggle(L10n.recordSnapshotAfter, isOn: $model.settings.enableStatusSnapshots)

                    HStack {
                        Text(L10n.codexModel)
                        Spacer()
                        TextField("gpt-5.4-mini", text: $model.settings.codexModel)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.whenQuotaUnavailable)
                            .foregroundStyle(theme.textSecondary)
                        Picker("", selection: $model.settings.quotaPreflightOnUnknown) {
                            Text(L10n.continueAnyway).tag("allow")
                            Text(L10n.skip).tag("skip")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Rectangle().fill(theme.hairline).frame(height: 1)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.keepAwake)
                            .foregroundStyle(theme.textSecondary)
                        Picker("", selection: $model.settings.keepAwakeMode) {
                            Text(L10n.off).tag("off")
                            Text(L10n.duringRun).tag("during")
                            Text(L10n.whileAppOpen).tag("always")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(L10n.keepAwakeNote)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Text(L10n.durationSeconds)
                        Spacer()
                        TextField("900", text: $model.settings.keepAwakeSeconds)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .textFieldStyle(.roundedBorder)
                    }

                    Rectangle().fill(theme.hairline).frame(height: 1)

                    // Launch at Login toggle
                    Toggle(L10n.launchAtLogin, isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))

                    Rectangle().fill(theme.hairline).frame(height: 1)

                    // Reveal the .env behind every setting — the source of truth shared with the CLI.
                    Button {
                        model.openConfigFile()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text(L10n.openConfigFile)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(theme.accentText)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 13))
                .padding(16)
                .background(theme.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.advancedReveal)
            }
        }
    }
}
