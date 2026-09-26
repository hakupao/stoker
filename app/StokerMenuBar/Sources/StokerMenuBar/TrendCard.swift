import StokerCore
import Charts
import SwiftUI

// MARK: - Trend Card

/// Quota history, one series at a time (Claude 5h | Claude weekly | Codex weekly) so the two
/// tools' different windows never share an axis. Drawn in the series tool's identity colour.
struct TrendCard: View {
    @ObservedObject var logStore: LogStore
    @State private var series: TrendSeries = .claudeFiveHour
    @Environment(\.stokerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.quotaTrend)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Picker("", selection: $series) {
                    ForEach(TrendSeries.allCases, id: \.self) { s in
                        Text(Self.label(s)).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
            }

            TrendChart(
                points: logStore.chartPoints(series: series),
                color: series.tool == "codex" ? theme.seriesCodex : theme.seriesClaude,
                label: Self.label(series)
            )
            .id(series)  // fresh hover state per series
            .frame(height: 64)
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

    static func label(_ series: TrendSeries) -> String {
        switch series {
        case .claudeFiveHour: L10n.trendClaude5h
        case .claudeWeekly: L10n.trendClaudeWeekly
        case .codexWeekly: L10n.trendCodexWeekly
        }
    }
}

// MARK: - Trend Chart

/// A clean line — no area fill; real snapshots dotted; broken at resets (one series per
/// segment); a little top headroom so 100% never clips; hover shows the nearest sample.
private struct TrendChart: View {
    let points: [QuotaChartPoint]
    let color: Color
    let label: String
    @Environment(\.stokerTheme) private var theme
    @State private var hover: QuotaChartPoint?

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
                        series: .value("s", pt.segment)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    PointMark(
                        x: .value("t", pt.date),
                        y: .value("r", pt.remainingPercent)
                    )
                    .foregroundStyle(color)
                    .symbolSize(12)
                }

                if let h = hover {
                    RuleMark(x: .value("t", h.date))
                        .foregroundStyle(theme.hairline)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("t", h.date), y: .value("r", h.remainingPercent))
                        .foregroundStyle(color)
                        .symbolSize(44)
                        .annotation(
                            position: .top,
                            spacing: 4,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                        ) {
                            Text("\(label) \(Int(h.remainingPercent.rounded()))% · \(LogTimestamp.display(h.date))")
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
