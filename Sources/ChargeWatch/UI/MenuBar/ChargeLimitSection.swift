import SwiftUI

/// 菜单面板内"充电上限"卡片。依 ChargeLimitController.uiMode 渲染 A(控制)/onboarding/权限/只读 等态。
struct ChargeLimitSection: View {
    @EnvironmentObject private var chargeLimit: ChargeLimitController
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.classic.rawValue
    @AppStorage(L10n.storageKey) private var languageRaw: String = AppLanguage.system.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .classic }
    private var L: L10n { L10n(language: AppLanguage(rawValue: languageRaw) ?? .system) }

    var body: some View {
        if chargeLimit.uiMode == .hidden {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                header
                modeBody
            }
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(theme: theme)
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: AppIcon.chargeLimit)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityHidden(true)
            Text(L.t("limit.title"))
                .font(AppFont.panelLabel)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            trailing
                .frame(minWidth: 56, alignment: .trailing)   // 固定尾部区，避免值/进度/警告切换重排
        }
    }

    @ViewBuilder private var trailing: some View {
        if chargeLimit.isSetting {
            ProgressView().controlSize(.small)
        } else if chargeLimit.lastError != nil && chargeLimit.uiMode != .onboarding {
            Image(systemName: AppIcon.warning)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.discharging)
        } else {
            Text(chargeLimit.currentValueText)
                .font(AppFont.panelSubheadline)
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    @ViewBuilder private var modeBody: some View {
        switch chargeLimit.uiMode {
        case .control:
            stepperPicker
            if chargeLimit.lastError == .bridgeMisconfigured {
                caption(L.t("limit.step_not_applied"), action: L.t("limit.open_in_system")) { chargeLimit.openSystemBatterySettings() }
            }
        case .enableInSystem:
            caption(L.t("limit.enable_in_system_caption")) {
                actionButton(L.t("limit.enable_in_system_button"), primary: true) { chargeLimit.openSystemBatterySettings() }
            }
        case .onboarding:
            caption(L.t("limit.onboarding_caption")) {
                actionButton(L.t("limit.onboarding_button"), primary: true) { chargeLimit.openOnboarding() }
                actionButton(L.t("limit.open_in_system")) { chargeLimit.openSystemBatterySettings() }
            }
        case .permissionDenied:
            caption(L.t("limit.permission_caption")) {
                actionButton(L.t("limit.permission_button"), primary: true) { chargeLimit.openSystemBatterySettings() }
                actionButton(L.t("limit.open_in_system")) { chargeLimit.openSystemBatterySettings() }
            }
        case .deepLinkOnly:
            HStack {
                actionButton(L.t("limit.open_in_system"), primary: true) { chargeLimit.openSystemBatterySettings() }
                Spacer()
            }
        case .loading, .hidden:
            EmptyView()
        }
    }

    private var stepperPicker: some View {
        Picker(L.t("limit.title"), selection: Binding(
            get: { chargeLimit.selectedStep },
            set: { newValue in
                if let value = newValue { Task { await chargeLimit.set(value) } }
            }
        )) {
            ForEach(ChargeLimitConstants.steps, id: \.self) { step in
                Text("\(step)").monospacedDigit().tag(Optional(step))
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .disabled(chargeLimit.isSetting)
    }

    // MARK: 小组件

    private func caption(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(text)
                .font(AppFont.panelCaption)
                .foregroundStyle(AppColor.textSecondary)
            HStack {
                actionButton(action) { perform() }
                Spacer()
            }
        }
    }

    private func caption<Buttons: View>(_ text: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(text)
                .font(AppFont.panelCaption)
                .foregroundStyle(AppColor.textSecondary)
            HStack(spacing: AppSpacing.s) { buttons() }
        }
    }

    private func actionButton(_ title: String, primary: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(AppFont.buttonLabel)
                .padding(.horizontal, AppSpacing.s)
                .padding(.vertical, AppSpacing.xs)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(primary ? AppColor.chargingActive : AppColor.textSecondary)
    }
}
