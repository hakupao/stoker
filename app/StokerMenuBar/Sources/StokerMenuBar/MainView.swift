import StokerCore
import SwiftUI

// MARK: - Tab

enum MainTab: String, CaseIterable, Identifiable {
    case activity, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .activity: L10n.activity
        case .settings: AppLanguage.current == .zh ? "设置" : "Settings"
        }
    }
}

// MARK: - Main View

struct MainView: View {
    @ObservedObject var model: StokerAppModel

    var body: some View {
        MainPanel(model: model, root: model.root)
    }
}

private struct MainPanel: View {
    @ObservedObject var model: StokerAppModel
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var logStore: LogStore
    @State private var selectedTab = MainTab.activity
    @State private var langRefresh = false
    @AppStorage("hideOnboarding") private var hideOnboarding = false
    @State private var showOnboarding = false

    init(model: StokerAppModel, root: URL) {
        self._model = ObservedObject(wrappedValue: model)
        self._logStore = StateObject(wrappedValue: LogStore(root: root))
    }

    private var isOn: Bool { model.state?.installed == true }

    // The single resolved theme for this appearance + schedule state. Injected
    // into the environment so header, body, cards, and footer all warm together.
    private var theme: StokerTheme {
        StokerTheme.resolve(colorScheme: colorScheme, isOn: isOn)
    }

    var body: some View {
        VStack(spacing: 0) {
            UnifiedHeader(model: model, selectedTab: $selectedTab, langRefresh: $langRefresh)

            Group {
                switch selectedTab {
                case .activity:
                    ActivityTabContent(logStore: logStore)
                case .settings:
                    SettingsTabContent(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomActionBar(model: model, logStore: logStore, selectedTab: selectedTab)
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
            logStore.load()
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
        .onChange(of: langRefresh) { _, _ in
            logStore.objectWillChange.send()
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
    @Binding var langRefresh: Bool
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
                    AppLanguage.current = AppLanguage.current == .zh ? .en : .zh
                    model.objectWillChange.send()
                    langRefresh.toggle()
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
                .help(AppLanguage.current == .zh ? "Switch to English" : "切换到中文")
            }

            HStack(spacing: 16) {
                QuotaMiniBar(
                    label: "Claude",
                    percent: model.state?.quota["claude"]?.fiveHour?.remainingPercent,
                    color: theme.seriesClaude
                )
                QuotaMiniBar(
                    label: "Codex",
                    percent: model.state?.quota["codex"]?.fiveHour?.remainingPercent,
                    color: theme.seriesCodex
                )
                Spacer()
                TabPicker(selected: $selectedTab)
            }

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
    var percent: Double?
    var color: Color
    @Environment(\.stokerTheme) private var theme

    private var quotaColor: Color {
        guard let percent else { return theme.textMuted }
        if percent > 50 { return theme.positive }
        if percent > 20 { return theme.warning }
        return theme.danger
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 42, alignment: .leading)

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
    }
}

// MARK: - Settings Tab Content

struct SettingsTabContent: View {
    @ObservedObject var model: StokerAppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ScheduleCard(model: model)
                ToolCard(model: model)
                AdvancedSection(model: model)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.3"
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
