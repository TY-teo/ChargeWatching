import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let stream: SampleStream
    private let chargeLimit: ChargeLimitController
    private let smcLimiter: SMCChargeLimiter
    private var bag: Set<AnyCancellable> = []
    private var eventMonitor: Any?

    init(stream: SampleStream,
         chargeLimit: ChargeLimitController,
         smcLimiter: SMCChargeLimiter,
         onOpenHistory: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onExport: @escaping () -> Void) {
        self.stream = stream
        self.chargeLimit = chargeLimit
        self.smcLimiter = smcLimiter
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        self.popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        super.init()
        popover.delegate = self

        let panel = MenuBarPanel(
            onOpenHistory: onOpenHistory,
            onOpenSettings: onOpenSettings,
            onExport: onExport,
            onQuit: { NSApp.terminate(nil) }
        )
        .environmentObject(stream)
        .environmentObject(chargeLimit)
        .environmentObject(smcLimiter)
        // 内容自适应高度：显式让 NSHostingController 依 SwiftUI 内容设 preferredContentSize，
        // 不再硬编码 contentSize，避免新增卡片把底部操作行裁切。
        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        configureButton()
        observeStream()
    }

    // MARK: NSPopoverDelegate — 仅在面板可见时读取/轮询充电上限（关闭即停，护住空闲 CPU）

    func popoverWillShow(_ notification: Notification) {
        chargeLimit.startPolling()
    }

    func popoverDidClose(_ notification: Notification) {
        chargeLimit.stopPolling()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageLeft
        applyDisplay(sample: nil)
    }

    private func observeStream() {
        stream.$latest
            .receive(on: RunLoop.main)
            .sink { [weak self] sample in
                self?.applyDisplay(sample: sample)
            }
            .store(in: &bag)
    }

    private func applyDisplay(sample: PowerSample?) {
        guard let button = statusItem.button else { return }
        let iconName: String
        let title: String
        if let s = sample {
            switch s.status {
            case .charging:
                iconName = AppIcon.chargingActive
                title = "\(Int(s.batteryWatts.rounded()))W"
            case .acPaused:
                iconName = AppIcon.chargingPaused
                title = "AC"
            case .discharging:
                iconName = AppIcon.batterySymbol(for: s.stateOfChargePercent)
                title = s.stateOfChargePercent.map { "\($0)%" } ?? "--"
            case .desktop:
                iconName = AppIcon.powerPlug
                title = s.systemLoadWatts.map { "\(Int($0.rounded()))W" } ?? "--"
            }
        } else {
            iconName = AppIcon.chargingPaused
            title = "--"
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "ChargeWatch")?
            .withSymbolConfiguration(cfg)
        button.title = " " + title

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attr = NSAttributedString(
            string: button.title,
            attributes: [.font: font]
        )
        button.attributedTitle = attr
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            stopEventMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startEventMonitor()
        }
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }
}
