import SwiftUI
import Charts

/// 菜单栏弹出面板。采用"系统玻璃"风格：vibrancy 主题下用系统 popover 材质透出桌面。
/// 顶部状态横幅，主指标用 2x2 卡片网格（cardSurface 与玻璃主题统一），其下为适配器紧凑行、
/// 最近 60 秒图表，再到原生 `GroupBox` 充电上限分组与钉底操作行。
/// 仅保留唯一一处语义强调色（充电功率用系统级绿色），图表线统一用高辨识度蓝。
/// 面板宽度固定、高度跟随内容（无底部空白）；所有读数单行 + monospacedDigit、图表固定高度，
/// 保证 1Hz 采样刷新时每帧高度稳定，不引起外框抖动。
struct MenuBarPanel: View {
    let onOpenHistory: () -> Void
    let onOpenSettings: () -> Void
    let onExport: () -> Void
    let onQuit: () -> Void

    @EnvironmentObject private var stream: SampleStream
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.classic.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .classic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            statusBanner
            metricsGrid
            adapterRow
            sparklineGroup
            SMCChargeLimitSection()
            Divider()
            actionRow
        }
        .padding(AppSpacing.l)
        .frame(width: 360, alignment: .top)
        .panelBackground(theme: theme)
    }

    // MARK: - 状态横幅

    private var statusBanner: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: bannerIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(stream.latest?.status.displayName ?? "采集中")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(bannerHeadline)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(bannerHeadlineColor)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var bannerIcon: String {
        switch stream.latest?.status {
        case .charging: return AppIcon.chargingActive
        case .acPaused: return AppIcon.chargingPaused
        case .discharging: return AppIcon.batterySymbol(for: stream.latest?.stateOfChargePercent)
        case .desktop: return AppIcon.powerPlug
        case .none: return AppIcon.chargingPaused
        }
    }

    /// 唯一一处语义强调色：充电中的功率读数用系统级绿色，其余跟随系统主文字色。
    private var bannerHeadlineColor: Color {
        stream.latest?.status == .charging ? AppColor.chargingActive : .primary
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

    // MARK: - 指标 2x2 卡片网格（cardSurface 与玻璃主题统一，充入电池充电时高亮绿）

    private var metricsGrid: some View {
        Grid(horizontalSpacing: AppSpacing.s, verticalSpacing: AppSpacing.s) {
            GridRow {
                MetricCell(label: "充入电池",
                           value: stream.latest?.batteryWatts,
                           unit: "W",
                           formatter: wattText,
                           highlight: stream.latest?.status == .charging,
                           theme: theme)
                MetricCell(label: "墙插输出",
                           value: stream.latest?.wallOutputWatts,
                           unit: "W",
                           formatter: wattText,
                           highlight: false,
                           theme: theme)
            }
            GridRow {
                MetricCell(label: "系统负载",
                           value: stream.latest?.systemLoadWatts,
                           unit: "W",
                           formatter: wattText,
                           highlight: false,
                           theme: theme)
                MetricCell(label: "电池电量",
                           value: stream.latest?.stateOfChargePercent.map(Double.init),
                           unit: "%",
                           formatter: percentText,
                           highlight: false,
                           theme: theme)
            }
        }
    }

    // MARK: - 适配器紧凑行（独立 cardSurface 行）

    private var adapterRow: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: AppIcon.powerPlug)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(stream.latest?.adapterDescription ?? "未检测到适配器")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.m)
        .padding(.vertical, AppSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(theme: theme, radius: AppRadius.s)
    }

    // MARK: - 最近 60 秒（原生 GroupBox 包裹，固定高度避免抖动）

    private var sparklineGroup: some View {
        let points = Array(stream.rolling.suffix(60).enumerated().map(SparkPoint.init))
        let lastID = points.last?.id
        let currentW = points.last?.y
        return GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("最近 60 秒")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(currentW.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text("W")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Chart(points) { p in
                    LineMark(x: .value("idx", p.x), y: .value("W", p.y))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(AppColor.chartLine)
                    AreaMark(x: .value("idx", p.x), y: .value("W", p.y))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(AppColor.chartLine.opacity(0.22))
                    if p.id == lastID {
                        PointMark(x: .value("idx", p.x), y: .value("W", p.y))
                            .foregroundStyle(AppColor.chartLine)
                            .symbolSize(28)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(.separator)
                        AxisValueLabel {
                            if let w = value.as(Double.self) {
                                Text("\(Int(w.rounded()))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 64)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 操作行（钉底）

    private var actionRow: some View {
        HStack(spacing: 0) {
            ActionButton(icon: AppIcon.history, label: "完整历史", action: onOpenHistory)
            ActionButton(icon: AppIcon.export, label: "导出 CSV", action: onExport)
            ActionButton(icon: AppIcon.settings, label: "设置", action: onOpenSettings)
            ActionButton(icon: AppIcon.quit, label: "退出", action: onQuit)
        }
    }

    private func wattText(_ value: Double) -> String { String(format: "%.1f", value) }
    private func percentText(_ value: Double) -> String { "\(Int(value))" }
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

/// 指标卡片：标签在上、读数在下，经 cardSurface 抬升为浮于面板之上的实体卡片
/// （classic 用系统设置内嵌卡底，vibrancy 用玻璃上的薄层叠加，均不引入纯白卡底）。
/// 读数单行 + monospacedDigit，数字变化不改变高度，配合面板内容驱动高度时不引起抖动。
/// 充入电池在充电态用语义绿高亮，其余跟随系统主文字色。
private struct MetricCell: View {
    let label: String
    let value: Double?
    let unit: String
    let formatter: (Double) -> String
    let highlight: Bool
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(formatter) ?? "--")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(highlight ? AppColor.chargingActive : .primary)
                    .lineLimit(1)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .cardSurface(theme: theme)
    }
}

/// 操作行按钮：图标在上、文字在下，悬停时浅底反馈，全部使用系统语义文字色。
private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: AppRadius.s, style: .continuous)
                    .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}
