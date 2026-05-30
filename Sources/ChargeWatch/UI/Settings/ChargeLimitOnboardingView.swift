import SwiftUI
import AppKit

/// 一次性桥接快捷指令引导。由 AppDelegate 作为独立 NSWindow 呈现（非 sheet，popover 为 transient）。
struct ChargeLimitOnboardingView: View {
    @EnvironmentObject private var chargeLimit: ChargeLimitController
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.classic.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .classic }

    private let steps = [
        "打开\u{201C}快捷指令\u{201D} App，新建一个快捷指令。",
        "添加动作\u{201C}设置电池充电上限 / Set Battery Charge Limit\u{201D}，关闭其中的\u{201C}仅今天\u{201D}。",
        "让该动作的\u{201C}上限\u{201D}取自\u{201C}快捷指令输入\u{201D}（接收输入）。",
        "把快捷指令命名为下面的名称（需完全一致）。"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("在 ChargeWatch 内调节充电上限")
                        .font(AppFont.panelSubheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("macOS 没有程序化创建快捷指令的接口，需要你一次性创建一个包裹系统\u{201C}设置电池充电上限\u{201D}动作的快捷指令。它写入的就是系统设置里那同一个上限。")
                        .font(AppFont.panelCaption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Button("一键导入快捷指令（推荐）") { importBundledShortcut() }
                        .buttonStyle(.borderedProminent)
                    Text("点上方按钮 → 在弹出的预览里点\u{201C}添加快捷指令\u{201D}，即可完成。无需手动搭建。")
                        .font(AppFont.panelCaption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Text("或手动创建：")
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
                    Button("打开\u{201C}快捷指令\u{201D}") { openShortcutsApp() }
                    Button("我已完成（重新检测）") { Task { await chargeLimit.refresh() } }
                    Spacer()
                    Button("改用系统设置") { chargeLimit.openSystemBatterySettings() }
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
            Label("已检测到快捷指令，可在面板中调节", systemImage: "checkmark.circle.fill")
                .font(AppFont.panelCaption)
                .foregroundStyle(AppColor.chargingActive)
        } else {
            Label("尚未检测到该快捷指令", systemImage: AppIcon.info)
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
