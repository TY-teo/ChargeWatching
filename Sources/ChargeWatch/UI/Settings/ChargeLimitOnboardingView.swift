import SwiftUI
import AppKit

/// 一次性桥接快捷指令引导。由 AppDelegate 作为独立 NSWindow 呈现（非 sheet，popover 为 transient）。
struct ChargeLimitOnboardingView: View {
    @EnvironmentObject private var chargeLimit: ChargeLimitController
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.classic.rawValue
    @AppStorage(L10n.storageKey) private var languageRaw: String = AppLanguage.system.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .classic }
    private var L: L10n { L10n(language: AppLanguage(rawValue: languageRaw) ?? .system) }

    private var steps: [String] {
        (1...4).map { L.t("onboarding.step\($0)") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(L.t("onboarding.title"))
                        .font(AppFont.panelSubheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(L.t("onboarding.intro"))
                        .font(AppFont.panelCaption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Button(L.t("onboarding.import_button")) { importBundledShortcut() }
                        .buttonStyle(.borderedProminent)
                    Text(L.t("onboarding.import_hint"))
                        .font(AppFont.panelCaption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Text(L.t("onboarding.manual_header"))
                    .font(AppFont.panelLabel)
                    .foregroundStyle(AppColor.textSecondary)

                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: AppSpacing.s) {
                            Text("\(index + 1)")
                                .font(AppFont.buttonLabel)
                                .foregroundStyle(AppColor.textPrimary)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(AppColor.bgTertiary))
                            Text(text)
                                .font(AppFont.panelBody)
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(ChargeLimitConstants.shortcutName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColor.textPrimary)
                        .textSelection(.enabled)
                        .padding(AppSpacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(theme: theme, radius: AppRadius.s)
                }

                HStack(spacing: AppSpacing.s) {
                    statusLabel
                    Spacer()
                }

                HStack(spacing: AppSpacing.s) {
                    Button(L.t("onboarding.open_shortcuts")) { openShortcutsApp() }
                    Button(L.t("onboarding.recheck")) { Task { await chargeLimit.refresh() } }
                    Spacer()
                    Button(L.t("onboarding.use_system")) { chargeLimit.openSystemBatterySettings() }
                }
            }
            .padding(AppSpacing.xl)
        }
        .frame(width: 460, height: 380)
        .windowBackground(theme: theme)
        .task { await chargeLimit.refresh() }
    }

    @ViewBuilder private var statusLabel: some View {
        if chargeLimit.capability.bridgeConfigured {
            Label(L.t("onboarding.status.ok"), systemImage: "checkmark.circle.fill")
                .font(AppFont.panelCaption)
                .foregroundStyle(AppColor.chargingActive)
        } else {
            Label(L.t("onboarding.status.missing"), systemImage: AppIcon.info)
                .font(AppFont.panelCaption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 打开打进 app 的桥接快捷指令文件，触发系统"添加快捷指令"导入预览。
    private func importBundledShortcut() {
        if let resources = Bundle.main.resourceURL {
            let url = resources.appendingPathComponent("\(ChargeLimitConstants.shortcutName).shortcut")
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        openShortcutsApp()
    }
}
