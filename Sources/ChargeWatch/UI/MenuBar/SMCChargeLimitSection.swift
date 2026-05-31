import SwiftUI

/// 面板内"充电上限"分组——直接 SMC 控制（经 root helper），点一下即开。
/// 采用 StayAwake 同款原生 `GroupBox` + 原生 `Toggle .switch` / `Slider` / `Button`，
/// 文字一律 `.primary` / `.secondary`，滑块用系统强调色（`.tint`）。
/// 核心控件为原生 Slider（步进 5%，区间 80...100，对齐 SMCChargeLimiter.steps），
/// 仅在松手（onEditingChanged == false）写入 limiter，拖动途中不写盘，避免反复改写 SMC 配置。
struct SMCChargeLimitSection: View {
    @EnvironmentObject private var limiter: SMCChargeLimiter
    @EnvironmentObject private var stream: SampleStream

    private var soc: Int? { stream.latest?.stateOfChargePercent }

    /// 拖动期间的就地草稿值；仅松手时写入 limiter，外部变化经 onChange 回灌。
    @State private var draft: Double = 80

    /// 与 SMCChargeLimiter.steps（80/85/90/95/100）对齐：5% 步进、80...100 区间。
    private static let sliderRange: ClosedRange<Double> = 80...100
    private static let sliderStep: Double = 5
    private static let tickValues: [Int] = SMCChargeLimiter.steps

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { draft = clampToRange(Double(limiter.limit)) }
        .onChange(of: limiter.limit) { newValue in
            let synced = clampToRange(Double(newValue))
            if draft != synced { draft = synced }
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.s) {
            Label("充电上限", systemImage: AppIcon.chargeLimit)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)
            Spacer()
            trailing.frame(minWidth: 56, alignment: .trailing)
        }
    }

    @ViewBuilder private var trailing: some View {
        if limiter.busy {
            ProgressView().controlSize(.small)
        } else if limiter.enabled {
            percentBadge(limiter.limit, tint: AppColor.chargingActive)
        } else if let soc {
            percentBadge(soc, tint: .primary)
        } else {
            Text("—")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// 头部百分比徽标：数字 monospacedDigit + 紧凑 % 后缀，层级清晰、宽度稳定。
    private func percentBadge(_ value: Int, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(value)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text("%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        if !limiter.installed {
            enablePrompt
        } else {
            Divider()
            Toggle(isOn: Binding(
                get: { limiter.enabled },
                set: { $0 ? limiter.enable(limit: limiter.limit) : limiter.disable() }
            )) {
                rowLabel("启用充电上限", "将电量保持在设定上限附近")
            }
            .toggleStyle(.switch)
            .disabled(limiter.busy)

            if limiter.enabled {
                sliderControl
            } else {
                disabledHint
            }
        }
        if let err = limiter.lastError {
            Text(err)
                .font(.caption)
                .foregroundStyle(AppColor.discharging)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enablePrompt: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("开启后将电量保持在上限附近。首次需授权安装后台组件（仅一次）。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("开启充电上限") { limiter.enable(limit: 80) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(limiter.busy)
        }
    }

    private var sliderControl: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            readout
            Slider(
                value: $draft,
                in: Self.sliderRange,
                step: Self.sliderStep,
                onEditingChanged: { editing in
                    if !editing { commit() }
                }
            )
            .disabled(limiter.busy)
            .accessibilityValue("\(Int(draft.rounded())) 百分比")
            tickRuler
        }
    }

    private var readout: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("目标上限")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(draft.rounded()))")
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.chargingActive)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let soc {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("当前电量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(soc)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var tickRuler: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.tickValues.enumerated()), id: \.element) { index, tick in
                Text("\(tick)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(
                        Int(draft.rounded()) == tick ? .primary : .secondary
                    )
                    .frame(maxWidth: .infinity,
                           alignment: tickAlignment(index: index, count: Self.tickValues.count))
            }
        }
        .accessibilityHidden(true)
    }

    private var disabledHint: some View {
        Text("已安装后台组件，打开开关即可设定上限。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 松手提交：仅当落定值与当前 limiter.limit 不同才写盘，避免重复 setLimit。
    private func commit() {
        let value = Int(draft.rounded())
        guard value != limiter.limit else { return }
        limiter.setLimit(value)
    }

    private func clampToRange(_ value: Double) -> Double {
        min(max(value, Self.sliderRange.lowerBound), Self.sliderRange.upperBound)
    }

    private func tickAlignment(index: Int, count: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == count - 1 { return .trailing }
        return .center
    }

    private func rowLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
