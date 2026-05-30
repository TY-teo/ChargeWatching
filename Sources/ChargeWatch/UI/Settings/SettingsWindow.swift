import SwiftUI
import ServiceManagement

struct SettingsWindow: View {
    @AppStorage("notifyOnFull") private var notifyOnFull: Bool = false
    @AppStorage("notifyAtThreshold") private var notifyAtThreshold: Bool = false
    @AppStorage("notifyThresholdPercent") private var notifyThresholdPercent: Int = 80
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.classic.rawValue
    @State private var autoLaunchEnabled: Bool = false

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .classic
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                section(title: "外观") {
                    Picker(selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { t in
                            Text(t.displayName).tag(t.rawValue)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    Text((AppTheme(rawValue: themeRaw) ?? .classic).description)
                        .font(AppFont.panelCaption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                section(title: "通用") {
                    Toggle("开机自动启动", isOn: $autoLaunchEnabled)
                        .onChange(of: autoLaunchEnabled) { newValue in
                            setAutoLaunch(newValue)
                        }
                    Toggle("充电完成时通知（100%）", isOn: $notifyOnFull)
                    HStack {
                        Toggle("充电达到阈值时通知", isOn: $notifyAtThreshold)
                        Stepper(value: $notifyThresholdPercent, in: 30...95, step: 5) {
                            Text("\(notifyThresholdPercent) %")
                                .font(AppFont.panelBody)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .disabled(!notifyAtThreshold)
                    }
                }

                section(title: "数据") {
                    Text(AppContainer.databaseURL().path)
                        .font(AppFont.panelCaption)
                        .foregroundStyle(AppColor.textSecondary)
                        .textSelection(.enabled)
                    HStack {
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([AppContainer.databaseURL()])
                        }
                        Spacer()
                    }
                }

                HStack {
                    Text("ChargeWatch v0.4.0")
                        .font(AppFont.panelCaption)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                }
            }
            .padding(AppSpacing.xl)
        }
        .frame(width: 480, height: 360)
        .windowBackground(theme: theme)
        .onAppear {
            autoLaunchEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(title)
                .font(AppFont.panelLabel)
                .foregroundStyle(AppColor.textSecondary)
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.m)
            .cardSurface(theme: theme)
        }
    }

    private func setAutoLaunch(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("auto-launch toggle failed: \(error)")
            autoLaunchEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }
}
