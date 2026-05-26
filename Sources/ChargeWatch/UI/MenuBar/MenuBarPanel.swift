import SwiftUI
import Charts

struct MenuBarPanel: View {
    let onOpenHistory: () -> Void
    let onOpenSettings: () -> Void
    let onExport: () -> Void
    let onQuit: () -> Void

    @EnvironmentObject private var stream: SampleStream

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            statusBanner
            metricsGrid
            adapterRow
            sparkline
            Divider()
            actionRow
        }
        .padding(AppSpacing.l)
        .frame(width: 360)
        .background(AppColor.bgPrimary)
    }

    private var statusBanner: some View {
        HStack(spacing: AppSpacing.m) {
            Rectangle()
                .fill(bannerColor)
                .frame(width: 4, height: 36)
                .cornerRadius(2)
            VStack(alignment: .leading, spacing: 2) {
                Text(stream.latest?.status.displayName ?? "采集中")
                    .font(AppFont.panelBody)
                    .foregroundStyle(AppColor.textSecondary)
                Text(bannerHeadline)
                    .font(AppFont.panelSubheadline)
                    .foregroundStyle(AppColor.textPrimary)
            }
            Spacer()
        }
    }

    private var bannerColor: Color {
        switch stream.latest?.status {
        case .charging: return AppColor.chargingActive
        case .acPaused: return AppColor.chargingPaused
        case .discharging: return AppColor.discharging
        case .desktop, .none: return AppColor.chargingPaused
        }
    }

    private var bannerHeadline: String {
        guard let s = stream.latest else { return "--" }
        switch s.status {
        case .charging:
            return String(format: "%.1f W", s.batteryWatts)
        case .acPaused:
            return s.stateOfChargePercent.map { "AC · \($0)%" } ?? "AC"
        case .discharging:
            return s.stateOfChargePercent.map { "电池 · \($0)%" } ?? "放电中"
        case .desktop:
            return s.systemLoadWatts.map { String(format: "系统 %.1f W", $0) } ?? "市电"
        }
    }

    private var metricsGrid: some View {
        Grid(horizontalSpacing: AppSpacing.s, verticalSpacing: AppSpacing.s) {
            GridRow {
                MetricCell(label: "充入电池",
                           value: stream.latest?.batteryWatts,
                           formatter: wattFormatter,
                           accent: AppColor.chargingActive)
                MetricCell(label: "墙插输出",
                           value: stream.latest?.wallOutputWatts,
                           formatter: wattFormatter,
                           accent: AppColor.textPrimary)
            }
            GridRow {
                MetricCell(label: "系统负载",
                           value: stream.latest?.systemLoadWatts,
                           formatter: wattFormatter,
                           accent: AppColor.textPrimary)
                MetricCell(label: "电池电量",
                           value: stream.latest?.stateOfChargePercent.map(Double.init),
                           formatter: percentFormatter,
                           accent: AppColor.textPrimary)
            }
        }
    }

    private var adapterRow: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: AppIcon.powerPlug)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
            Text(stream.latest?.adapterDescription ?? "未检测到适配器")
                .font(AppFont.panelCaption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(AppSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgTertiary)
        .cornerRadius(AppRadius.s)
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("最近 60 秒")
                .font(AppFont.panelLabel)
                .foregroundStyle(AppColor.textSecondary)
            Chart(stream.rolling.suffix(60).enumerated().map(SparkPoint.init)) { p in
                LineMark(x: .value("idx", p.x), y: .value("W", p.y))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(sparkColor)
                AreaMark(x: .value("idx", p.x), y: .value("W", p.y))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(sparkColor.opacity(0.18))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 60)
        }
    }

    private var sparkColor: Color {
        switch stream.latest?.status {
        case .charging: return AppColor.chargingActive
        case .discharging: return AppColor.discharging
        default: return AppColor.chargingPaused
        }
    }

    private var actionRow: some View {
        HStack(spacing: 0) {
            ActionButton(icon: AppIcon.history, label: "完整历史", action: onOpenHistory)
            ActionButton(icon: AppIcon.export, label: "导出 CSV", action: onExport)
            ActionButton(icon: AppIcon.settings, label: "设置", action: onOpenSettings)
            ActionButton(icon: AppIcon.quit, label: "退出", action: onQuit)
        }
    }

    private var wattFormatter: (Double) -> String { { String(format: "%.1f", $0) } }
    private var percentFormatter: (Double) -> String { { "\(Int($0))" } }
}

private struct SparkPoint: Identifiable {
    let id: Int
    let x: Int
    let y: Double
    init(_ entry: EnumeratedSequence<ArraySlice<PowerSample>>.Element) {
        self.id = entry.offset
        self.x = entry.offset
        let sample = entry.element
        self.y = sample.status == .charging ? sample.batteryWatts : (sample.systemLoadWatts ?? abs(sample.batteryWatts))
    }
}

private struct MetricCell: View {
    let label: String
    let value: Double?
    let formatter: (Double) -> String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(AppFont.panelLabel)
                .foregroundStyle(AppColor.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(formatter) ?? "--")
                    .font(AppFont.panelHeadline)
                    .foregroundStyle(accent)
                Text(unitText)
                    .font(AppFont.unitSuffix)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(AppColor.bgSecondary)
        .cornerRadius(AppRadius.m)
    }

    private var unitText: String {
        label.contains("电量") ? "%" : "W"
    }
}

private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(AppFont.buttonLabel)
            }
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(hovering ? AppColor.bgTertiary : .clear)
            .cornerRadius(AppRadius.s)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
