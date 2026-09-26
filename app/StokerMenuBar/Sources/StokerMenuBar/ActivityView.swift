import StokerCore
import Charts
import SwiftUI

// MARK: - Activity Tab Content

struct ActivityTabContent: View {
    @ObservedObject var logStore: LogStore
    @ObservedObject var model: StokerAppModel
    @State private var chartWindow: QuotaWindowType = .fiveHour
    @State private var statusFilter: StatusFilter = .all

    var body: some View {
        VStack(spacing: 10) {
            QuotaOverviewCard(logStore: logStore, model: model, chartWindow: $chartWindow)

            HStack(spacing: 0) {
                StatsStrip(logStore: logStore)
                Spacer()
                Picker("", selection: $logStore.dateRange) {
                    Text(L10n.today).tag(DateRangeFilter.today)
                    Text(L10n.sevenDays).tag(DateRangeFilter.week)
                    Text(L10n.thirtyDays).tag(DateRangeFilter.month)
                    Text(L10n.allTime).tag(DateRangeFilter.all)
                }
                .frame(width: 100)
            }

            RunTimeline(logStore: logStore, statusFilter: $statusFilter)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - Quota Overview (current gauges + mini trend)

/// Replaces the old dual-area trend chart. The top "gauges" show each tool's current remaining%
/// (last snapshot) with a reset countdown; those colored rows double as the legend for the mini
/// trend below. The trend is a clean line — no decorative area, broken at resets, real samples
/// dotted, with a hover readout.
private struct QuotaOverviewCard: View {
    @ObservedObject var logStore: LogStore
    @ObservedObject var model: StokerAppModel
    @Binding var chartWindow: QuotaWindowType
    @Environment(\.stokerTheme) private var theme

    /// Current per-tool quota straight from `model.state.quota` — the SAME source the header
    /// mini-bar and the menu summary read (one "latest per tool" computation, done once in the
    /// engine). Honors the tool filter; only tools that have produced a snapshot row appear.
    private var gaugeTools: [String] {
        guard let quota = model.state?.quota else { return [] }
        let wanted: Set<String>
        switch logStore.toolFilter {
        case .all: wanted = ["claude", "codex"]
        case .claude: wanted = ["claude"]
        case .codex: wanted = ["codex"]
        }
        return ["claude", "codex"].filter { wanted.contains($0) && quota[$0] != nil }
    }

    /// Claude honours the 5h/weekly picker; Codex (weekly-only) always shows weekly.
    private func window(for tool: String) -> ActivationState.QuotaWindow? {
        model.state?.quota[tool]?.window(tool: tool, preferFiveHour: chartWindow == .fiveHour)
    }

    var body: some View {
        let points = logStore.chartPoints(window: chartWindow)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L10n.quotaOverview)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Picker("", selection: $chartWindow) {
                    Text(L10n.fiveHour).tag(QuotaWindowType.fiveHour)
                    Text(L10n.weekly).tag(QuotaWindowType.weekly)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .help(L10n.windowPickerHelp)

                Picker("", selection: $logStore.toolFilter) {
                    Text(L10n.allTools).tag(ToolFilter.all)
                    Text("Claude").tag(ToolFilter.claude)
                    Text("Codex").tag(ToolFilter.codex)
                }
                .frame(width: 90)
            }

            if gaugeTools.isEmpty {
                VStack(spacing: 6) {
                    Text(L10n.noData)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textMuted)
                    Text(L10n.quotaSetupHint)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(gaugeTools, id: \.self) { tool in
                        GaugeRow(
                            tool: tool,
                            window: window(for: tool),
                            asOf: model.state?.quota[tool]?.timestamp.flatMap(LogTimestamp.parse),
                            planType: model.state?.quota[tool]?.displayPlanLabel,
                            isWeeklyOnly: ActivationState.ToolQuota.isWeeklyOnly(tool: tool),
                            credits: model.state?.quota[tool]?.credits,
                            showsWeekly: chartWindow == .weekly
                        )
                        // Claude per-scope weekly limits (e.g. a model-specific bucket) sit
                        // under the Claude gauge, independent of the 5h/weekly picker.
                        if tool == "claude", let buckets = model.state?.quota[tool]?.scopedWeekly {
                            // Index ids: bucket ids aren't guaranteed unique.
                            ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                                ScopedWeeklyRow(bucket: bucket, color: theme.seriesClaude)
                            }
                        }
                    }
                }

                Rectangle().fill(theme.hairline).frame(height: 1)

                MiniTrend(points: points)
                    .frame(height: 84)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Gauge Row

/// One tool's current-quota row: colored name (also the trend legend), an explicit "剩余 N%"
/// (health-colored so low quota warns), a fill bar, and a reset countdown (falls back to an
/// "updated HH:mm" stamp). Hover spells out remaining vs used so the single bar is unambiguous.
private struct GaugeRow: View {
    let tool: String
    let window: ActivationState.QuotaWindow?
    let asOf: Date?
    /// Tool-level plan tier (Codex plan_type / Claude subscription_type); nil hides the badge.
    var planType: String? = nil
    /// Weekly-only tool (Codex): the row always shows the weekly window and says so.
    var isWeeklyOnly: Bool = false
    /// Tool-level credit balance; nil (or empty) hides the credits line.
    var credits: ActivationState.Credits? = nil
    /// The picker is on the weekly view (for the hover text).
    var showsWeekly: Bool = false
    @Environment(\.stokerTheme) private var theme

    private var color: Color {
        tool == "claude" ? theme.seriesClaude : theme.seriesCodex
    }
    private var name: String {
        tool == "claude" ? "Claude" : "Codex"
    }
    private var remaining: Double? { window?.remainingPercent }
    /// A short credit-balance string, or nil when there is nothing meaningful to show.
    private var creditsText: String? {
        guard let c = credits else { return nil }
        if c.unlimited == true { return L10n.creditsUnlimited }
        if let bal = c.balance, !bal.isEmpty { return "\(L10n.creditsLabel) \(bal)" }
        if let used = c.usedCredits, let limit = c.monthlyLimit, limit > 0 {
            return "\(L10n.creditsLabel) \(Int(used.rounded()))/\(Int(limit.rounded()))"
        }
        return nil
    }
    private var resetDate: Date? {
        ResetTime.parse(window?.resetsAt)
    }
    private var trailingText: String {
        if let reset = resetDate, let s = L10n.resetsIn(reset, now: Date()) { return s }
        if let asOf { return L10n.updatedAt(asOf) }
        return ""
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                if let plan = planType, !plan.isEmpty {
                    Text(plan)
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
            .frame(width: 64, alignment: .leading)

            // Explicit "剩余 N%" so the bar is never misread as "used"; the % is health-colored.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let pct = remaining {
                    Text(L10n.remaining)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                    Text("\(Int(pct.rounded()))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.quotaColor(pct, theme: theme))
                        .monospacedDigit()
                } else {
                    Text(L10n.quotaUnknownShort)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .frame(width: 110, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.fillSubtle)
                    if let pct = remaining {
                        Capsule()
                            .fill(color)
                            .frame(width: max(0, geo.size.width * CGFloat(min(100, max(0, pct)) / 100)))
                    }
                }
            }
            .frame(height: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(trailingText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                if isWeeklyOnly {
                    Text(L10n.weeklyWindowHint)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                if let ct = creditsText {
                    Text(ct)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(width: 96, alignment: .trailing)
        }
        // Spell out remaining vs used on hover so the single bar's meaning is unambiguous.
        .help(L10n.quotaMiniHelp(remaining: window?.remainingPercent, used: window?.usedPercent,
                                 weekly: isWeeklyOnly || showsWeekly))
    }
}

// MARK: - Scoped Weekly Row

/// A compact sub-row under the Claude gauge for one per-scope weekly bucket: label, remaining %,
/// a thin bar, and the reset countdown. Aligned to the GaugeRow columns. An inactive bucket
/// (doesn't gate runs) is dimmed and marked so its percentage isn't read as a blocker.
private struct ScopedWeeklyRow: View {
    let bucket: ActivationState.ScopedWeeklyBucket
    let color: Color
    @Environment(\.stokerTheme) private var theme

    private var remaining: Double? { bucket.remainingPercent }
    private var inactive: Bool { bucket.isActive == false }

    private var resetDate: Date? {
        ResetTime.parse(bucket.resetsAt)
    }

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 64, height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(L10n.scopedWeeklyLabel(bucket.label))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                if let pct = remaining {
                    Text("\(Int(pct.rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(inactive ? theme.textMuted : DS.quotaColor(pct, theme: theme))
                        .monospacedDigit()
                } else {
                    Text(L10n.quotaUnknownShort)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .frame(width: 110, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.fillSubtle)
                    if let pct = remaining {
                        Capsule()
                            .fill(color.opacity(inactive ? 0.35 : 0.8))
                            .frame(width: max(0, geo.size.width * CGFloat(min(100, max(0, pct)) / 100)))
                    }
                }
            }
            .frame(height: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if let reset = resetDate, let s = L10n.resetsIn(reset, now: Date()) {
                    Text(s)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }
                if inactive {
                    Text(L10n.scopedInactive)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(width: 96, alignment: .trailing)
        }
        .help(inactive
            ? L10n.scopedInactiveHelp
            : L10n.quotaMiniHelp(remaining: bucket.remainingPercent, used: bucket.usedPercent, weekly: true))
    }
}

// MARK: - Mini Trend

/// Compact history line for the selected window. No area fill; thin per-tool lines colored to
/// match the gauges above; real snapshots dotted; line broken at resets (one series per
/// tool+segment); a little top headroom so 100% never clips; hover shows the nearest sample.
private struct MiniTrend: View {
    let points: [QuotaChartPoint]
    @Environment(\.stokerTheme) private var theme
    @State private var hover: QuotaChartPoint?

    private func color(_ tool: String) -> Color {
        tool.lowercased() == "claude" ? theme.seriesClaude : theme.seriesCodex
    }

    var body: some View {
        if points.isEmpty {
            Text(L10n.noData)
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            Chart {
                ForEach(points) { pt in
                    LineMark(
                        x: .value("t", pt.date),
                        y: .value("r", pt.remainingPercent),
                        series: .value("s", "\(pt.tool)#\(pt.segment)")
                    )
                    .foregroundStyle(color(pt.tool))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    PointMark(
                        x: .value("t", pt.date),
                        y: .value("r", pt.remainingPercent)
                    )
                    .foregroundStyle(color(pt.tool))
                    .symbolSize(12)
                }

                if let h = hover {
                    RuleMark(x: .value("t", h.date))
                        .foregroundStyle(theme.hairline)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("t", h.date), y: .value("r", h.remainingPercent))
                        .foregroundStyle(color(h.tool))
                        .symbolSize(44)
                        .annotation(
                            position: .top,
                            spacing: 4,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                        ) {
                            Text("\(h.tool) \(Int(h.remainingPercent.rounded()))% · \(LogTimestamp.display(h.date))")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(theme.onSurface)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(theme.card)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(theme.hairline, lineWidth: 0.5)
                                        )
                                )
                                .fixedSize()
                        }
                }
            }
            .chartYScale(domain: 0...104)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 100]) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)").font(.system(size: 8)).foregroundStyle(theme.textMuted)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [3]))
                        .foregroundStyle(theme.hairline)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 8))
                        .foregroundStyle(theme.textMuted)
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.2))
                        .foregroundStyle(theme.hairline)
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hover = nearest(to: location, proxy: proxy, geo: geo)
                            case .ended:
                                hover = nil
                            }
                        }
                }
            }
        }
    }

    private func nearest(to location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> QuotaChartPoint? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let plot = geo[plotFrame]
        let x = location.x - plot.origin.x
        guard x >= 0, x <= plot.width,
              let date = proxy.value(atX: x, as: Date.self) else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}

// MARK: - Stats Strip

private struct StatsStrip: View {
    @ObservedObject var logStore: LogStore
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            StatPill(icon: "number", value: "\(logStore.totalRuns)", color: theme.accent)
            StatPill(icon: "checkmark", value: "\(logStore.successCount)", color: theme.positive)
            StatPill(icon: "forward.fill", value: "\(logStore.skippedCount)", color: theme.warning)
            StatPill(icon: "xmark", value: "\(logStore.errorCount)", color: theme.danger)
            if let avg = logStore.averageCost {
                StatPill(icon: "dollarsign", value: String(format: "$%.2f", avg), color: theme.textSecondary)
            }
        }
    }
}

private struct StatPill: View {
    var icon: String
    var value: String
    var color: Color
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(theme.onSurface)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
    }
}

// MARK: - Run Timeline

private struct RunTimeline: View {
    @ObservedObject var logStore: LogStore
    @Binding var statusFilter: StatusFilter
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        let records: [UsageRecord] = {
            let base = logStore.filteredUsage
            if statusFilter == .all { return base }
            return base.filter { $0.status.rawValue == statusFilter.rawValue }
        }()

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.runHistory)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Picker("", selection: $statusFilter) {
                    Text(L10n.allStatus).tag(StatusFilter.all)
                    Text(L10n.success).tag(StatusFilter.success)
                    Text(L10n.skipped).tag(StatusFilter.skipped)
                    Text(L10n.failed).tag(StatusFilter.error)
                }
                .frame(width: 100)
            }

            if records.isEmpty {
                Text(L10n.noRunsInRange)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(records) { record in
                            RunRow(record: record)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

// MARK: - Run Row

private struct RunRow: View {
    var record: UsageRecord
    @Environment(\.stokerTheme) private var theme
    @State private var isExpanded = false
    @State private var isHovered = false

    private var barColor: Color {
        switch record.status {
        case .success: theme.positive
        case .skipped: theme.warning
        case .error: theme.danger
        }
    }

    private var toolColor: Color {
        record.tool == "claude" ? theme.seriesClaude : theme.seriesCodex
    }

    private var statusIcon: String {
        switch record.status {
        case .success: "checkmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    /// Normalized, status-driven label — replaces dumping the model's free-form reply
    /// (which varied every run and read as noise). The raw reply still lives in RunDetail.
    private var statusLabel: String {
        switch record.status {
        case .success:
            return L10n.success
        case .skipped:
            let reason = L10n.skipReasonText(record.skipReason)
            return reason.isEmpty ? L10n.skipped : "\(L10n.skipped) · \(reason)"
        case .error:
            if let code = record.exitCode, code != 0 {
                return "\(L10n.failed) · exit \(code)"
            }
            return L10n.failed
        }
    }

    /// Sub-cent costs (Claude check-ins run ~$0.001) round to "$0.00" under %.2f and read as
    /// free; widen to 4 decimals below a cent so the real number shows.
    private func formatCost(_ cost: Double) -> String {
        cost >= 0.01 ? String(format: "$%.2f", cost) : String(format: "$%.4f", cost)
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(barColor)
                .frame(width: 3)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        if let date = record.date {
                            Text(LogTimestamp.display(date))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 52, alignment: .leading)
                        }

                        Text(record.toolDisplayName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(toolColor)
                            .frame(width: 48, alignment: .leading)

                        HStack(spacing: 4) {
                            Image(systemName: statusIcon)
                                .font(.system(size: 10, weight: .bold))
                            Text(statusLabel)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(barColor)

                        Spacer()

                        if let cost = record.totalCostUsd, cost > 0 {
                            Text(formatCost(cost))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.textMuted)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.textMuted)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    RunDetail(record: record)
                        .padding(.leading, 10)
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
        }
        .background(isHovered ? theme.fillSubtle : .clear)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Run Detail

private struct RunDetail: View {
    var record: UsageRecord
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let usage = record.usage {
                HStack(spacing: 6) {
                    DetailChip(label: L10n.inputLabel, value: formatTokens(usage.inputTokens))
                    DetailChip(label: L10n.outputLabel, value: formatTokens(usage.outputTokens))
                    if let cache = usage.cacheCreationInputTokens ?? usage.cachedInputTokens, cache > 0 {
                        DetailChip(label: L10n.cacheLabel, value: formatTokens(cache))
                    }
                    if let reasoning = usage.reasoningOutputTokens, reasoning > 0 {
                        DetailChip(label: L10n.reasoningLabel, value: formatTokens(reasoning))
                    }
                }
            }

            HStack(spacing: 6) {
                if let ms = record.durationMs {
                    DetailChip(label: L10n.durationLabel, value: String(format: "%.1fs", ms / 1000))
                }
                if let sid = record.sessionId ?? record.threadId {
                    DetailChip(label: L10n.sessionLabel, value: String(sid.prefix(12)) + "…")
                }
                if let cost = record.totalCostUsd, cost > 0 {
                    DetailChip(label: "$", value: String(format: "%.4f", cost))
                }
            }

            if record.skipped != true,
               let reply = record.result?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reply.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.replyLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                    Text(reply)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(6)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func formatTokens(_ count: Int?) -> String {
        guard let count else { return "--" }
        if count >= 1000 { return String(format: "%.1fk", Double(count) / 1000) }
        return "\(count)"
    }
}

private struct DetailChip: View {
    var label: String
    var value: String
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(theme.textMuted)
            Text(value)
                .foregroundStyle(theme.textSecondary)
                .fontWeight(.medium)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(theme.fillSubtle)
        .clipShape(Capsule())
    }
}

// MARK: - Status Filter

enum StatusFilter: String, CaseIterable, Sendable {
    case all, success, skipped, error
}
