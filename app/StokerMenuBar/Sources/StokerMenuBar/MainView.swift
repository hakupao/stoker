import StokerCore
import SwiftUI

// MARK: - Tab

enum MainTab: String, CaseIterable, Identifiable {
    case activity, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .activity: L10n.activity
        case .settings: L10n.settingsTab
        }
    }
}

// MARK: - Main View

struct MainView: View {
    @ObservedObject var model: StokerAppModel

    var body: some View {
        MainPanel(model: model)
    }
}

private struct MainPanel: View {
    @ObservedObject var model: StokerAppModel
    @ObservedObject private var locale = LocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var logStore: LogStore
    @State private var selectedTab = MainTab.activity
    @AppStorage("hideOnboarding") private var hideOnboarding = false
    @State private var showOnboarding = false

    init(model: StokerAppModel) {
        self._model = ObservedObject(wrappedValue: model)
        // The model owns the one shared LogStore (the menu and alert dot read it too).
        self._logStore = ObservedObject(wrappedValue: model.logStore)
    }

    private var isOn: Bool { model.state?.installed == true }

    // The single resolved theme for this appearance + schedule state. Injected
    // into the environment so header, body, cards, and footer all warm together.
    private var theme: StokerTheme {
        StokerTheme.resolve(colorScheme: colorScheme, isOn: isOn)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                UnifiedHeader(model: model, selectedTab: $selectedTab)

                Group {
                    switch selectedTab {
                    case .activity:
                        ActivityTabContent(logStore: logStore, model: model)
                    case .settings:
                        SettingsTabContent(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                BottomActionBar(model: model, logStore: logStore, selectedTab: selectedTab)
            }
            // Re-identify the whole localized subtree on a language switch so EVERY subview
            // re-reads L10n at once — including ForEach rows (e.g. run history) that SwiftUI
            // would otherwise skip because their inputs didn't change. The lifecycle modifiers
            // below stay on the OUTER container, so this never re-fires onAppear/.task or
            // re-presents the onboarding sheet.
            .id(locale.language)
        }
        .frame(minWidth: 720, minHeight: 600)
        .background(theme.surface)
        .environment(\.stokerTheme, theme)
        // ONE coordinated "forge igniting" transition: window base, header,
        // cards, hairlines, and accents all warm in lockstep off `isOn`.
        .animation(StokerTheme.forgeTransition, value: isOn)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding, root: model.root)
                .environment(\.stokerTheme, theme)
        }
        .onAppear {
            // `refresh` reloads the shared logs before publishing state.
            Task { await model.refresh() }
            if model.requestToolCheck {
                showOnboarding = true
                model.requestToolCheck = false
            } else if !hideOnboarding {
                Task {
                    let missing = await ToolChecker.checkMissingTools(root: model.root)
                    if !missing.isEmpty { showOnboarding = true }
                }
            }
        }
        .task {
            // Auto-refresh while the window is open; SwiftUI cancels this task when the
            // window closes. Ticks are silent and don't re-read settings, so polling never
            // flashes the busy spinner or clobbers edits the user hasn't saved yet.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                await model.refresh(silent: true, reloadSettings: false)
            }
        }
        .onChange(of: model.requestToolCheck) { _, newValue in
            if newValue {
                showOnboarding = true
                model.requestToolCheck = false
            }
        }
    }
}

// MARK: - Unified Header

private struct UnifiedHeader: View {
    @ObservedObject var model: StokerAppModel
    @Binding var selectedTab: MainTab
    @Environment(\.stokerTheme) private var theme

    private var isOn: Bool { model.state?.installed == true }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                AppIconBadge(isOn: isOn)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stoker")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.onSurface)
                    if let state = model.state {
                        Text(state.schedule.times.joined(separator: " · "))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                        if isOn, !state.schedule.times.isEmpty {
                            // Self-updating countdown to the next fire: re-evaluates every
                            // minute and rolls over to the following time on its own.
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                if let next = ScheduleFormatter.nextFire(times: state.schedule.times, now: context.date) {
                                    let total = ScheduleFormatter.minutesRemaining(until: next, now: context.date)
                                    Text("\(L10n.nextRunPrefix) \(ScheduleFormatter.clock(next)) · \(L10n.nextRunCountdown(hours: total / 60, minutes: total % 60))")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(theme.accentText)
                                }
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    // Ember status dot — ignites on activate (scale 0.85→1.0 +
                    // ember glow), then settles static. No perpetual pulse.
                    Circle()
                        .fill(isOn ? theme.accentOn : theme.textMuted.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(isOn ? 1.0 : 0.85)
                        .shadow(color: isOn ? theme.accentOn.opacity(0.6) : .clear, radius: 4)
                        .animation(.easeOut(duration: 0.3), value: isOn)

                    Toggle("", isOn: Binding(
                        get: { isOn },
                        set: { _ in model.toggleSchedule() }
                    ))
                    .toggleStyle(.switch)
                    .tint(theme.accentOn)
                    .labelsHidden()
                    .scaleEffect(0.8)
                }

                if model.isBusy {
                    ProgressView().controlSize(.small)
                }

                Button {
                    LocaleStore.shared.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .semibold))
                        Text(AppLanguage.current == .zh ? "EN" : "中")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(theme.fillSubtle)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(AppLanguage.current == .zh ? L10n.switchToEnglish : L10n.switchToChinese)
            }

            HStack(spacing: 16) {
                Text(L10n.quotaRemaining)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                // Claude shows its 5-hour window; Codex is weekly-only (7-day window).
                let health = model.healthSnapshot
                QuotaMiniBar(
                    label: "Claude \(L10n.fiveHourShort)",
                    window: model.state?.quota["claude"]?.window(tool: "claude", preferFiveHour: true),
                    color: theme.seriesClaude,
                    health: health.claude.state
                )
                QuotaMiniBar(
                    label: "Codex \(L10n.weeklyShort)",
                    window: model.state?.quota["codex"]?.window(tool: "codex", preferFiveHour: true),
                    color: theme.seriesCodex,
                    health: health.codex.state,
                    isWeeklyOnly: true
                )
                Spacer()
                TabPicker(selected: $selectedTab)
            }

            AuthStatusBar(model: model, selectedTab: $selectedTab)

            if let mismatch = model.state?.launchctl?.mismatch, !mismatch.isEmpty {
                // Persistent warning: a LaunchAgent is loaded from a different
                // root, so `installed` reads false and the toggle shows OFF.
                // Explain why instead of leaving the user with a silent OFF.
                NotificationBanner(message: L10n.scheduleElsewhere, isError: true)
            }

            if !model.statusMessage.isEmpty {
                NotificationBanner(message: model.statusMessage, isError: model.statusIsError)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        // Explicit header fill (one half-step deeper than surface) so the header
        // shift is intentional and warms together with the rest of the window.
        .background(theme.header)
        .animation(.easeInOut(duration: 0.25), value: model.statusMessage)
    }
}

// MARK: - Auth Status Bar
//
// Always-visible (both tabs) one-line indicator of how scheduled background runs authenticate:
// green shield = their own long-lived token; amber shield = borrowing the rotating Keychain login
// (can 401 overnight). The trailing button jumps straight to the Advanced → Background auth row.
private struct AuthStatusBar: View {
    @ObservedObject var model: StokerAppModel
    @Binding var selectedTab: MainTab
    @Environment(\.stokerTheme) private var theme

    private var healthy: Bool { model.hasOAuthToken }
    private var accent: Color { healthy ? theme.positive : theme.warning }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: healthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
            Text(L10n.backgroundAuth)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            Text(healthy ? L10n.authModeToken : L10n.authModeKeychain)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            Spacer()
            Button {
                selectedTab = .settings
                model.focusBackgroundAuth = true
            } label: {
                HStack(spacing: 3) {
                    Text(healthy ? L10n.manage : L10n.setUpNow)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(healthy ? theme.textSecondary : theme.accentText)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(healthy ? theme.fillSubtle : theme.accentOn.opacity(0.16))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(healthy ? L10n.authModeToken : L10n.authKeychainWarning)
        }
    }
}

// MARK: - Tab Picker

private struct TabPicker: View {
    @Binding var selected: MainTab
    @Environment(\.stokerTheme) private var theme
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { tab in
                Text(tab.label)
                    .font(.system(size: 12, weight: selected == tab ? .bold : .medium, design: .rounded))
                    .foregroundStyle(selected == tab ? theme.onSurface : theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background {
                        if selected == tab {
                            Capsule()
                                .fill(theme.accent.opacity(0.18))
                                .matchedGeometryEffect(id: "activeTab", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { selected = tab }
            }
        }
        .padding(3)
        .background(theme.fillSubtle)
        .clipShape(Capsule())
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
    }
}

// MARK: - Quota Mini Bar

private struct QuotaMiniBar: View {
    var label: String
    var window: ActivationState.QuotaWindow?
    var color: Color
    /// Activation health (same snapshot as the Activity cards) for the leading dot.
    var health: ToolHealthState
    /// Weekly-only tool (Codex): the label carries the window tag; this picks the tooltip wording.
    var isWeeklyOnly: Bool = false
    @Environment(\.stokerTheme) private var theme

    private var percent: Double? { window?.remainingPercent }

    // Health color shared with the Activity gauge (one definition in DS.quotaColor).
    private var quotaColor: Color { DS.quotaColor(percent, theme: theme) }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DS.healthColor(health, theme: theme))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(0, geo.size.width * ((percent ?? 0) / 100)))
                }
            }
            .frame(width: 80, height: 5)

            Text(DS.quotaLabel(percent))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(quotaColor)
                .frame(width: 30, alignment: .trailing)
        }
        // Spell out remaining vs used so the bar's meaning is unambiguous on hover.
        .help(L10n.quotaMiniHelp(remaining: window?.remainingPercent, used: window?.usedPercent,
                                 weekly: isWeeklyOnly))
    }
}

// MARK: - Settings Tab Content

struct SettingsTabContent: View {
    @ObservedObject var model: StokerAppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ScheduleCard(model: model)
                    ToolCard(model: model)
                    BackgroundAuthCard(model: model)
                    AdvancedSection(model: model)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .onAppear { if model.focusBackgroundAuth { scrollToAuth(proxy) } }
            .onChange(of: model.focusBackgroundAuth) { _, focus in
                if focus { scrollToAuth(proxy) }
            }
        }
    }

    /// Give AdvancedSection a beat to expand, then center the background-auth row and clear the
    /// one-shot trigger.
    private func scrollToAuth(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo("backgroundAuth", anchor: .center)
            }
            try? await Task.sleep(for: .seconds(1.6))
            model.focusBackgroundAuth = false
        }
    }
}

// MARK: - Bottom Action Bar

struct BottomActionBar: View {
    @ObservedObject var model: StokerAppModel
    @ObservedObject var logStore: LogStore
    var selectedTab: MainTab
    @Environment(\.stokerTheme) private var theme

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.6"
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    model.saveSettingsAndReload()
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        logStore.load()
                    }
                } label: {
                    Label(L10n.save, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentOn)

                Button {
                    model.runNowWithDelayedRefresh()
                    Task {
                        try? await Task.sleep(for: .seconds(12))
                        logStore.load()
                    }
                } label: {
                    Label(L10n.runOnce, systemImage: "play.fill")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)

                Spacer()

                if selectedTab == .activity {
                    Button(action: exportCSV) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                    }
                    .help(L10n.exportCsv)
                }

                Button { model.openLogs() } label: {
                    Image(systemName: "doc.text").font(.system(size: 13))
                }
                .help(L10n.logs)

                Button { model.openInstallGuide() } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 13))
                }
                .help(L10n.help)
            }

            HStack {
                Spacer()
                Text("v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "stoker-export.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? logStore.exportCSV().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
