import StokerCore
import Charts
import SwiftUI

// MARK: - Activity Tab Content

struct ActivityTabContent: View {
    @ObservedObject var logStore: LogStore
    @State private var chartWindow: QuotaWindowType = .fiveHour
    @State private var statusFilter: StatusFilter = .all

    var body: some View {
        VStack(spacing: 10) {
            QuotaChart(logStore: logStore, chartWindow: $chartWindow)
                .frame(height: 150)

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

// MARK: - Quota Chart

private struct QuotaChart: View {
    @ObservedObject var logStore: LogStore
    @Binding var chartWindow: QuotaWindowType
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.quotaTrend)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Picker("", selection: $chartWindow) {
                    Text(L10n.fiveHour).tag(QuotaWindowType.fiveHour)
                    Text(L10n.weekly).tag(QuotaWindowType.weekly)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Picker("", selection: $logStore.toolFilter) {
                    Text(L10n.allTools).tag(ToolFilter.all)
                    Text("Claude").tag(ToolFilter.claude)
                    Text("Codex").tag(ToolFilter.codex)
                }
                .frame(width: 90)
            }

            let data = logStore.chartPoints(window: chartWindow)

            if data.isEmpty {
                Text(L10n.noData)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                let claudeData = data.filter { $0.tool == "Claude" }
                let codexData = data.filter { $0.tool == "Codex" }

                Chart {
                    ForEach(claudeData) { pt in
                        AreaMark(
                            x: .value("T", pt.date),
                            y: .value("R", pt.remainingPercent),
                            series: .value("Tool", "Claude")
                        )
                        .foregroundStyle(theme.seriesClaude.opacity(0.12))
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("T", pt.date),
                            y: .value("R", pt.remainingPercent),
                            series: .value("Tool", "Claude")
                        )
                        .foregroundStyle(theme.seriesClaude)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    ForEach(codexData) { pt in
                        AreaMark(
                            x: .value("T", pt.date),
                            y: .value("R", pt.remainingPercent),
                            series: .value("Tool", "Codex")
                        )
                        .foregroundStyle(theme.seriesCodex.opacity(0.12))
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("T", pt.date),
                            y: .value("R", pt.remainingPercent),
                            series: .value("Tool", "Codex")
                        )
                        .foregroundStyle(theme.seriesCodex)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%").font(.system(size: 10)).foregroundStyle(theme.textMuted)
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4]))
                            .foregroundStyle(theme.hairline)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9))
                            .foregroundStyle(theme.textMuted)
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.2))
                            .foregroundStyle(theme.hairline)
                    }
                }
                .chartLegend(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
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
