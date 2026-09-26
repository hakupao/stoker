import StokerCore
import SwiftUI

// MARK: - Alert Banner

/// Shown only while an enabled tool is in `.alert`. "View" jumps the run list to that tool's
/// failures so the user lands on the evidence.
struct ToolAlertBanner: View {
    let snapshot: ToolHealthSnapshot
    let onView: (String) -> Void
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            ForEach(snapshot.alertTools, id: \.self) { tool in
                let health = snapshot.health(tool)
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.danger)
                    Text(L10n.alertBanner(tool: toolName(tool), failures: health.consecutiveFailures,
                                          error: health.lastError))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.onSurface)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(health.lastError ?? "")
                    Spacer(minLength: 6)
                    Button {
                        onView(tool)
                    } label: {
                        HStack(spacing: 2) {
                            Text(L10n.viewDetails)
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.danger)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.danger.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.danger.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

private func toolName(_ tool: String) -> String {
    tool == "codex" ? "Codex" : "Claude"
}

// MARK: - Claude Card

/// Claude: the 5-hour window is the headline; weekly and any per-scope weekly buckets follow.
struct ClaudeCard: View {
    let quota: ActivationState.ToolQuota?
    let health: ToolHealth
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        let now = Date()
        let fiveHour = quota?.fiveHour
        let weekly = quota?.weekly
        let fiveReset = ResetTime.parse(fiveHour?.resetsAt)
        let weeklyReset = ResetTime.parse(weekly?.resetsAt)

        ToolCardFrame(name: "Claude", color: theme.seriesClaude, quota: quota, health: health) {
            PrimaryQuota(
                label: L10n.fiveHour,
                window: fiveHour,
                asOf: asOf(quota),
                resetText: fiveReset.flatMap { d in
                    L10n.resetsInShort(d, now: now).map { "\(L10n.resetAtClock(d)) · \($0)" }
                },
                color: theme.seriesClaude,
                weekly: false,
                now: now
            )
            if quota == nil {
                Text(L10n.quotaSetupHint)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if quota != nil {
                SecondaryQuotaRow(
                    label: L10n.weekly,
                    remaining: weekly?.remainingPercent,
                    used: weekly?.usedPercent,
                    resetText: weeklyReset.flatMap { L10n.resetsIn($0, now: now) },
                    color: theme.seriesClaude,
                    resetPassed: weekly?.hasResetPassed(now: now) == true
                )
            }
            // Index ids: bucket ids aren't guaranteed unique.
            ForEach(Array((quota?.scopedWeekly ?? []).enumerated()), id: \.offset) { _, bucket in
                ScopedWeeklyRow(bucket: bucket, color: theme.seriesClaude)
            }
        }
    }
}

// MARK: - Codex Card

/// Codex has only a 7-day window, so "this week" is the headline; plus free reset credits.
struct CodexCard: View {
    let quota: ActivationState.ToolQuota?
    let health: ToolHealth
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        let now = Date()
        let weekly = quota?.weekly
        let reset = ResetTime.parse(weekly?.resetsAt)

        ToolCardFrame(name: "Codex", color: theme.seriesCodex, quota: quota, health: health) {
            PrimaryQuota(
                label: L10n.thisWeek,
                window: weekly,
                asOf: asOf(quota),
                resetText: reset.flatMap { d in
                    guard d > now else { return nil }
                    let cal = Calendar.current
                    let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                                  to: cal.startOfDay(for: d)).day ?? 0
                    return "\(L10n.resetsLabel) \(L10n.weekdayStamp(d)) · \(L10n.resetsInDays(days))"
                },
                color: theme.seriesCodex,
                weekly: true,
                now: now
            )
            if let rc = quota?.resetCredits, rc.availableCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "ticket")
                        .font(.system(size: 9, weight: .semibold))
                    Text(L10n.resetCredits(count: rc.availableCount,
                                           expiry: ResetTime.parse(rc.earliestExpiresAt)))
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

private func asOf(_ quota: ActivationState.ToolQuota?) -> Date? {
    quota?.timestamp.flatMap(LogTimestamp.parse)
}

// MARK: - Card Frame

/// Shared chrome for both tool cards: identity-coloured name, plan pill, credits, the
/// tool-specific body, then a hairline and the health line pinned to the bottom.
private struct ToolCardFrame<Content: View>: View {
    let name: String
    let color: Color
    let quota: ActivationState.ToolQuota?
    let health: ToolHealth
    @ViewBuilder let content: Content
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                if let plan = quota?.displayPlanLabel {
                    PlanPill(text: plan)
                }
                Spacer(minLength: 4)
                if let credits = creditsText(quota?.credits) {
                    Text(credits)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }
            }

            content

            Spacer(minLength: 0)
            Rectangle().fill(theme.hairline).frame(height: 1)
            HealthLine(health: health)
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
    }

    /// A short credit-balance string, or nil when there is nothing meaningful to show.
    private func creditsText(_ c: ActivationState.Credits?) -> String? {
        guard let c else { return nil }
        if c.unlimited == true { return L10n.creditsUnlimited }
        if let bal = c.balance, !bal.isEmpty { return "\(L10n.creditsLabel) \(bal)" }
        if let used = c.usedCredits, let limit = c.monthlyLimit, limit > 0 {
            return "\(L10n.creditsLabel) \(Int(used.rounded()))/\(Int(limit.rounded()))"
        }
        return nil
    }
}

private struct PlanPill: View {
    let text: String
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .truncationMode(.tail)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(theme.fillSubtle))
    }
}

// MARK: - Quota rows

/// Headline window: label, big health-coloured remaining %, a bar, and the reset text (falls
/// back to "updated HH:mm"). A blank percent reads "quota unknown", or "reset, awaiting
/// refresh" when the window's reset time has already passed.
private struct PrimaryQuota: View {
    let label: String
    let window: ActivationState.QuotaWindow?
    let asOf: Date?
    let resetText: String?
    let color: Color
    let weekly: Bool
    let now: Date
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        let pct = window?.remainingPercent
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let pct {
                    Text("\(Int(pct.rounded()))%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.quotaColor(pct, theme: theme))
                        .monospacedDigit()
                    Text(L10n.remaining)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                } else {
                    Text(window?.hasResetPassed(now: now) == true ? L10n.resetAwaitingRefresh : L10n.quotaUnknownShort)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                }
                Spacer(minLength: 6)
                if let trailing = resetText ?? asOf.map(L10n.updatedAt) {
                    Text(trailing)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            QuotaBar(percent: pct, color: color, height: 6)
        }
        .help(L10n.quotaMiniHelp(remaining: pct, used: window?.usedPercent, weekly: weekly))
    }
}

/// Compact sub-row: label, remaining %, a thin bar, and the reset countdown. Used for
/// Claude's weekly window and per-scope weekly buckets.
private struct SecondaryQuotaRow: View {
    let label: String
    let remaining: Double?
    var used: Double? = nil
    let resetText: String?
    let color: Color
    var inactive: Bool = false
    /// The window rolled over since the snapshot: say so instead of a blank percent + bar.
    var resetPassed: Bool = false
    var help: String? = nil
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 84, alignment: .leading)
            if resetPassed {
                Text(L10n.resetAwaitingRefresh)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Group {
                    if let pct = remaining {
                        Text("\(Int(pct.rounded()))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(inactive ? theme.textMuted : DS.quotaColor(pct, theme: theme))
                            .monospacedDigit()
                    } else {
                        Text(L10n.na)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.textMuted)
                    }
                }
                .frame(width: 36, alignment: .leading)
                QuotaBar(percent: remaining, color: color.opacity(inactive ? 0.35 : 0.8), height: 4)
            }
            Text(inactive ? L10n.scopedInactive : (resetText ?? ""))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 70, alignment: .trailing)
        }
        .help(help ?? L10n.quotaMiniHelp(remaining: remaining, used: used, weekly: true))
    }
}

/// One per-scope weekly bucket under the Claude card. An inactive bucket (doesn't gate runs)
/// is dimmed and marked so its percentage isn't read as a blocker.
private struct ScopedWeeklyRow: View {
    let bucket: ActivationState.ScopedWeeklyBucket
    let color: Color

    var body: some View {
        let inactive = bucket.isActive == false
        SecondaryQuotaRow(
            label: L10n.scopedWeeklyLabel(bucket.label),
            remaining: bucket.remainingPercent,
            used: bucket.usedPercent,
            resetText: ResetTime.parse(bucket.resetsAt).flatMap { L10n.resetsIn($0, now: Date()) },
            color: color,
            inactive: inactive,
            help: inactive ? L10n.scopedInactiveHelp : nil
        )
    }
}

/// Remaining-quota fill bar; empty track when the percent is unknown.
struct QuotaBar: View {
    let percent: Double?
    let color: Color
    var height: CGFloat = 6
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.fillSubtle)
                if let pct = percent {
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(min(100, max(0, pct)) / 100)))
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Health Line

/// Card footer: coloured dot + state, then "last HH:mm ✓ · next MM-dd HH:mm" (or "schedule off").
struct HealthLine: View {
    let health: ToolHealth
    @Environment(\.stokerTheme) private var theme

    private var dotColor: Color {
        switch health.state {
        case .ok, .anchored: theme.positive
        case .pending: theme.textSecondary
        case .warning, .exhausted: theme.warning
        case .alert: theme.danger
        case .unknown, .disabled: theme.textMuted
        }
    }

    private var stateText: String {
        switch health.state {
        case .ok: L10n.healthOK
        case .warning: L10n.healthWarning
        case .alert: health.consecutiveFailures >= 2 ? L10n.healthAlert(health.consecutiveFailures) : L10n.healthAlertGeneric
        case .unknown: L10n.healthUnknown
        case .anchored: L10n.healthAnchored
        case .pending: L10n.healthPending
        case .exhausted: L10n.healthExhausted
        case .disabled: L10n.healthDisabled
        }
    }

    private var runsText: String {
        var parts: [String] = []
        if let last = health.lastRunAt {
            parts.append(L10n.lastRun(last, ok: health.lastRunOK == true))
        }
        if health.state != .disabled {
            parts.append(health.nextActivation.map(L10n.nextRun) ?? L10n.scheduleOffShort)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(stateText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.onSurface)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 6)
            Text(runsText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .help(health.lastError ?? "")
    }
}
