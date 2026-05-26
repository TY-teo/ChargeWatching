import SwiftUI
import Charts
import AppKit

struct HistoryWindow: View {
    @EnvironmentObject private var repoHolder: SampleRepositoryHolder
    @State private var range: TimeRange = .today
    @State private var points: [TimeSeriesPoint] = []
    @State private var stats: AggregateStats = .zero
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            chart
            Divider()
            statsBar
        }
        .background(AppColor.bgPrimary)
        .task(id: range) { await reload() }
    }

    private var toolbar: some View {
        HStack(spacing: AppSpacing.m) {
            Picker("", selection: $range) {
                ForEach(TimeRange.allCases, id: \.self) { r in
                    Text(r.title).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            Spacer()
            Button {
                exportCSV()
            } label: {
                Label("导出 CSV", systemImage: AppIcon.export)
            }
        }
        .padding(AppSpacing.m)
    }

    private var chart: some View {
        Group {
            if points.isEmpty {
                VStack(spacing: AppSpacing.s) {
                    Image(systemName: AppIcon.history)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(AppColor.textSecondary)
                    Text(isLoading ? "加载中…" : "暂无数据")
                        .font(AppFont.panelBody)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(points) { p in
                        LineMark(
                            x: .value("time", p.timestamp),
                            y: .value("W", max(0, p.batteryWatts))
                        )
                        .foregroundStyle(AppColor.chargingActive)
                        .interpolationMethod(.monotone)
                    }
                    ForEach(points) { p in
                        if let soc = p.stateOfChargePercent {
                            LineMark(
                                x: .value("time", p.timestamp),
                                y: .value("SoC", Double(soc)),
                                series: .value("series", "soc")
                            )
                            .foregroundStyle(AppColor.chargingPaused)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                }
                .chartYScale(domain: 0...max(120, (points.map(\.batteryWatts).max() ?? 0) + 10))
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine().foregroundStyle(AppColor.divider)
                        AxisValueLabel().font(AppFont.chartAxis)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine().foregroundStyle(AppColor.divider)
                        AxisValueLabel().font(AppFont.chartAxis)
                    }
                }
                .padding(AppSpacing.l)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statsBar: some View {
        HStack(spacing: AppSpacing.l) {
            statBox(title: "累计充入", value: String(format: "%.2f Wh", stats.totalChargedEnergyWh))
            statBox(title: "平均功率", value: String(format: "%.1f W", stats.averageChargingWatts))
            statBox(title: "峰值功率", value: String(format: "%.1f W", stats.peakChargingWatts))
            statBox(title: "充电时长", value: formatDuration(stats.chargingDurationSeconds))
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.m)
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.panelLabel)
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(AppFont.panelSubheadline)
                .foregroundStyle(AppColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.m)
        .background(AppColor.bgSecondary)
        .cornerRadius(AppRadius.m)
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        guard let repo = repoHolder.repository else { return }
        let (from, to) = range.bounds
        do {
            let pts = try await repo.query(from: from, to: to, granularity: range.granularity)
            let agg = try await repo.aggregate(from: from, to: to)
            await MainActor.run {
                self.points = pts
                self.stats = agg
            }
        } catch {
            NSLog("history reload error: \(error)")
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)min" }
        return "\(m) min"
    }

    private func exportCSV() {
        guard let repo = repoHolder.repository else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "chargewatch-\(range.fileSlug).csv"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            Task {
                do {
                    let (from, to) = range.bounds
                    let pts = try await repo.query(from: from, to: to, granularity: .raw)
                    let csv = CSVExporter.makeCSV(from: pts)
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    NSLog("export error: \(error)")
                }
            }
        }
    }
}

enum TimeRange: CaseIterable, Hashable {
    case today, week, month

    var title: String {
        switch self {
        case .today: return "今天"
        case .week: return "本周"
        case .month: return "本月"
        }
    }

    var fileSlug: String {
        switch self {
        case .today: return "today"
        case .week: return "week"
        case .month: return "month"
        }
    }

    var bounds: (Date, Date) {
        let now = Date()
        let cal = Calendar.current
        switch self {
        case .today:
            let start = cal.startOfDay(for: now)
            return (start, now)
        case .week:
            let start = cal.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .month:
            let start = cal.date(byAdding: .day, value: -30, to: now) ?? now
            return (start, now)
        }
    }

    var granularity: Granularity {
        switch self {
        case .today: return .raw
        case .week: return .tenSecond
        case .month: return .oneMinute
        }
    }
}

extension AggregateStats {
    static let zero = AggregateStats(totalChargedEnergyWh: 0,
                                     averageChargingWatts: 0,
                                     peakChargingWatts: 0,
                                     chargingDurationSeconds: 0,
                                     sampleCount: 0)
}
