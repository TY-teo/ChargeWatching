import SwiftUI
import AppKit

@main
struct ChargeWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--dump") {
            DumpCommand.runAndExit()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: AppContainer
    private var statusBarController: StatusBarController?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    override init() {
        self.container = AppContainer()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        container.start()
        container.chargeLimitController.onOpenOnboarding = { [weak self] in self?.showChargeLimitOnboarding() }
        statusBarController = StatusBarController(
            stream: container.sampleStream,
            chargeLimit: container.chargeLimitController,
            smcLimiter: container.smcLimiter,
            onOpenHistory: { [weak self] in self?.showHistory() },
            onOpenSettings: { [weak self] in self?.showSettings() },
            onExport: { [weak self] in self?.exportCSV() }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.stop()
    }

    private func showHistory() {
        if historyWindow == nil {
            let root = HistoryWindow()
                .environmentObject(container.sampleStream)
                .environmentObject(container.repository)
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "ChargeWatch · 历史"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 720, height: 480))
            win.center()
            win.isReleasedWhenClosed = false
            ThemeWindowConfigurator.prepareForThemeable(win)
            historyWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    private func showChargeLimitOnboarding() {
        if onboardingWindow == nil {
            let root = ChargeLimitOnboardingView()
                .environmentObject(container.chargeLimitController)
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "ChargeWatch · 充电上限设置"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 460, height: 380))
            win.center()
            win.isReleasedWhenClosed = false
            ThemeWindowConfigurator.prepareForThemeable(win)
            onboardingWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        if settingsWindow == nil {
            let root = SettingsWindow()
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "ChargeWatch · 设置"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 480, height: 360))
            win.center()
            win.isReleasedWhenClosed = false
            ThemeWindowConfigurator.prepareForThemeable(win)
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func exportCSV() {
        guard let repo = container.repository.repository else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "chargewatch-export.csv"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            Task {
                do {
                    let now = Date()
                    let from = Calendar.current.startOfDay(for: now)
                    let pts = try await repo.query(from: from, to: now, granularity: .raw)
                    let csv = CSVExporter.makeCSV(from: pts)
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    NSLog("export error: \(error)")
                }
            }
        }
    }
}
