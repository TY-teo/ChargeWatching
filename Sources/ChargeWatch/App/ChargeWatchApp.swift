import SwiftUI
import AppKit

@main
struct ChargeWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--dump") {
            DumpCommand.runAndExit()
        }
        if let i = CommandLine.arguments.firstIndex(of: "--shot") {
            let out = CommandLine.arguments.count > i + 1
                ? CommandLine.arguments[i + 1]
                : FileManager.default.currentDirectoryPath
            ShotCommand.runAndExit(outDir: out)
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
    private var languageObserver: Any?
    private var lastLanguageRaw: String = ""

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
        observeLanguageChanges()
    }

    // MARK: 语言切换

    /// SwiftUI 视图经 @AppStorage(L10n.storageKey) 自动重绘，但 NSWindow.title 不在视图树内，
    /// 所以在这里盯住语言键的变化，手动回刷已创建窗口的标题。
    private func observeLanguageChanges() {
        lastLanguageRaw = currentLanguageRaw
        languageObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshWindowTitlesIfLanguageChanged() }
        }
    }

    private var currentLanguageRaw: String {
        UserDefaults.standard.string(forKey: L10n.storageKey) ?? AppLanguage.system.rawValue
    }

    private func refreshWindowTitlesIfLanguageChanged() {
        let raw = currentLanguageRaw
        guard raw != lastLanguageRaw else { return }
        lastLanguageRaw = raw
        let L = L10n.current
        historyWindow?.title = L.t("window.history")
        onboardingWindow?.title = L.t("window.charge_limit")
        settingsWindow?.title = L.t("window.settings")
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.stop()
        // 退出即真正停止限充：写 enabled=false，root 守护进程下一轮（≤10s）恢复正常充电。
        // 配置为同步写盘，进程退出前即落地。不强制卸载后台组件（避免每次退出弹管理员密码）。
        if container.smcLimiter.installed {
            container.smcLimiter.disable()
        }
    }

    private func showHistory() {
        if historyWindow == nil {
            let root = HistoryWindow()
                .environmentObject(container.sampleStream)
                .environmentObject(container.repository)
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = L10n.current.t("window.history")
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
            win.title = L10n.current.t("window.charge_limit")
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
            win.title = L10n.current.t("window.settings")
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
