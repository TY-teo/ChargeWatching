import SwiftUI
import ServiceManagement

struct SettingsWindow: View {
    @AppStorage("notifyOnFull") private var notifyOnFull: Bool = false
    @AppStorage("notifyAtThreshold") private var notifyAtThreshold: Bool = false
    @AppStorage("notifyThresholdPercent") private var notifyThresholdPercent: Int = 80
    @State private var autoLaunchEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
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

            Spacer()

            HStack {
                Text("ChargeWatch v0.1.0")
                    .font(AppFont.panelCaption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 480, height: 320, alignment: .topLeading)
        .background(AppColor.bgPrimary)
        .onAppear {
            autoLaunchEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(title)
                .font(AppFont.panelLabel)
                .foregroundStyle(AppColor.textSecondary)
            content()
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
