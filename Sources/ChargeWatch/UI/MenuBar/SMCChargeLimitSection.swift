import SwiftUI

/// 面板内"充电上限"卡片——直接 SMC 控制（经 root helper），点一下即开。
struct SMCChargeLimitSection: View {
    @EnvironmentObject private var limiter: SMCChargeLimiter
    @EnvironmentObject private var stream: SampleStream
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.classic.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .classic }

    private var soc: Int? { stream.latest?.stateOfChargePercent }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            header
            content
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(theme: theme)
    }

    private var header: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: AppIcon.chargeLimit)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityHidden(true)
            Text("充电上限")
                .font(AppFont.panelLabel)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            trailing.frame(minWidth: 56, alignment: .trailing)
        }
    }

    @ViewBuilder private var trailing: some View {
        if limiter.busy {
            ProgressView().controlSize(.small)
        } else if limiter.enabled {
            Text("\(limiter.limit)%")
                .font(AppFont.panelSubheadline)
                .foregroundStyle(AppColor.chargingActive)
        } else if let soc {
            Text("\(soc)%")
                .font(AppFont.panelSubheadline)
                .foregroundStyle(AppColor.textPrimary)
        } else {
            Text("—").font(AppFont.panelSubheadline).foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder private var content: some View {
        if !limiter.installed {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("开启后将电量保持在上限附近。首次需授权安装后台组件（仅一次）。")
                    .font(AppFont.panelCaption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("开启充电上限") { limiter.enable(limit: 80) }
                    .buttonStyle(.borderedProminent)
                    .disabled(limiter.busy)
            }
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Toggle("启用充电上限", isOn: Binding(
                    get: { limiter.enabled },
                    set: { $0 ? limiter.enable(limit: limiter.limit) : limiter.disable() }
                ))
                .font(AppFont.panelBody)
                .disabled(limiter.busy)

                if limiter.enabled {
                    Picker("充电上限", selection: Binding(
                        get: { limiter.limit },
                        set: { limiter.setLimit($0) }
                    )) {
                        ForEach(SMCChargeLimiter.steps, id: \.self) { Text("\($0)").monospacedDigit().tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(limiter.busy)
                }
            }
        }
        if let err = limiter.lastError {
            Text(err).font(AppFont.panelCaption).foregroundStyle(AppColor.discharging)
        }
    }
}
