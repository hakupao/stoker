import StokerCore
import SwiftUI

// MARK: - Claude Settings Card
//
// Replaces the old generic ToolCard toggle + the standalone BackgroundAuthCard: one card for
// everything Claude-specific. The enable toggle always stays interactive (so a disabled tool can
// be turned back on); only the background-auth content below it dims/disables. Carries over
// BackgroundAuthCard's own state and behavior verbatim: the one-click setup sheet, the jump
// target for the header chip (anchor id "backgroundAuth" + a brief highlight ring on focus).
struct ClaudeSettingsCard: View {
    @ObservedObject var model: StokerAppModel
    @Environment(\.stokerTheme) private var theme
    @State private var showAuthSheet = false
    @State private var highlight = false

    private var isHealthy: Bool { model.hasOAuthToken }
    private var accent: Color { isHealthy ? theme.positive : theme.warning }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow

            VStack(alignment: .leading, spacing: 12) {
                authHeader
                statusStrip
                detailText
                actionButton
            }
            .disabled(!model.settings.enableClaude)
            .opacity(model.settings.enableClaude ? 1 : 0.5)
        }
        .padding(DS.cardPadding)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: highlight ? theme.accentOn.opacity(0.35) : .clear, radius: 10)
        .id("backgroundAuth")
        .sheet(isPresented: $showAuthSheet) {
            SetupTokenSheet(model: model)
        }
        .onAppear { if model.focusBackgroundAuth { pulse() } }
        .onChange(of: model.focusBackgroundAuth) { _, focus in
            if focus { pulse() }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Text(L10n.claudeSettingsTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(theme.seriesClaude)
            Spacer()
            Toggle("", isOn: $model.settings.enableClaude)
                .labelsHidden()
                .tint(theme.seriesClaude)
        }
    }

    private var authHeader: some View {
        Label {
            Text(L10n.backgroundAuth)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        } icon: {
            Image(systemName: "key.horizontal.fill")
                .foregroundStyle(theme.accent)
        }
    }

    // Health-tinted status strip, echoing the ToolToggleTile treatment.
    private var statusStrip: some View {
        let tint = accent
        return HStack(spacing: 8) {
            Image(systemName: isHealthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(isHealthy ? L10n.authModeToken : L10n.authModeKeychain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.onSurface)
            Spacer()
            Text(isHealthy ? L10n.authHealthyTag : L10n.authAttentionTag)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint.opacity(0.16)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }

    private var detailText: some View {
        Text(isHealthy ? L10n.authHealthyDetail : L10n.authKeychainWarning)
            .font(.system(size: 12))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous).fill(theme.card)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
            .strokeBorder(highlight ? theme.accentOn : theme.hairline, lineWidth: highlight ? 2 : 1)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isHealthy {
            Button { showAuthSheet = true } label: { ctaLabel(L10n.reauthenticate) }
                .buttonStyle(.bordered)
                .tint(theme.accent)
                .controlSize(.large)
        } else {
            Button { showAuthSheet = true } label: { ctaLabel(L10n.authenticate) }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentOn)
                .controlSize(.large)
        }
    }

    private func ctaLabel(_ title: String) -> some View {
        Label(title, systemImage: "key.horizontal")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }

    /// Brief highlight ring so a jump from the header chip lands somewhere obvious; the actual
    /// scroll is performed by SettingsTabContent, which also clears the trigger.
    private func pulse() {
        withAnimation(.easeInOut(duration: 0.3)) { highlight = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.5)) { highlight = false }
        }
    }
}

// MARK: - Codex Settings Card
//
// Replaces the old generic ToolCard toggle for Codex, and pulls CODEX_MODEL out of
// AdvancedSection alongside the three new Task-3 options: auto-update, model fallback, and
// activate-only-when-idle. Like ClaudeSettingsCard, the enable toggle stays interactive while
// everything below it dims/disables.
struct CodexSettingsCard: View {
    @ObservedObject var model: StokerAppModel
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow

            VStack(alignment: .leading, spacing: 12) {
                modelField
                optionToggle(L10n.codexAutoUpdateLabel, help: L10n.codexAutoUpdateHelp,
                             isOn: $model.settings.codexAutoUpdate)
                optionToggle(L10n.codexFallbackLabel, help: L10n.codexFallbackHelp,
                             isOn: $model.settings.codexModelFallback)
                optionToggle(L10n.codexIdleOnlyLabel, help: L10n.codexIdleOnlyHelp,
                             isOn: $model.settings.codexActivateOnlyWhenIdle)
            }
            .disabled(!model.settings.enableCodex)
            .opacity(model.settings.enableCodex ? 1 : 0.5)
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

    private var titleRow: some View {
        HStack(spacing: 10) {
            Text(L10n.codexSettingsTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(theme.seriesCodex)
            Spacer()
            Toggle("", isOn: $model.settings.enableCodex)
                .labelsHidden()
                .tint(theme.seriesCodex)
        }
    }

    private var modelField: some View {
        HStack {
            Text(L10n.codexModelLabel)
            Spacer()
            TextField(AppSettings.defaultCodexModel, text: $model.settings.codexModel)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func optionToggle(_ label: String, help: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(label, isOn: isOn)
            Text(help)
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
