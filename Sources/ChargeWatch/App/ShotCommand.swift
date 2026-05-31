import SwiftUI
import AppKit

/// 截图模式（仅用于生成 README 展示图）：把真实菜单栏面板放进带系统 popover 材质、
/// 置于桌面之上的窗口，浅色/深色各截一张，用 screencapture 区域抓取（含真实玻璃质感）。
/// 用法：swift run chargewatch -- --shot <输出目录>
/// 调用点在 ChargeWatchApp.init（主线程），故此处直接操作 UI。
enum ShotCommand {
    @MainActor
    static func runAndExit(outDir: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let sampler = PowerSampler()
        let stream = SampleStream(sampler: sampler)
        let chargeLimit = ChargeLimitController()
        let smc = SMCChargeLimiter()
        UserDefaults.standard.set(AppTheme.vibrancy.rawValue, forKey: "appTheme")
        // 读本机真实数据：启动采样器，等它采到当前真实功率/电量再截图（无任何 mock）。
        sampler.start()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        for (name, appearance) in [
            ("light", NSAppearance(named: .aqua)!),
            ("dark", NSAppearance(named: .darkAqua)!)
        ] {
            let panel = MenuBarPanel(onOpenHistory: {}, onOpenSettings: {}, onExport: {}, onQuit: {})
                .environmentObject(stream)
                .environmentObject(chargeLimit)
                .environmentObject(smc)
            let host = NSHostingView(rootView: panel)
            host.appearance = appearance
            host.layoutSubtreeIfNeeded()
            var size = host.fittingSize
            if size.width < 100 || size.height < 100 { size = NSSize(width: 392, height: 560) }

            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.appearance = appearance
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 12
            effect.layer?.masksToBounds = true
            host.frame = effect.bounds
            host.autoresizingMask = [.width, .height]
            effect.addSubview(host)

            let screen = NSScreen.main!
            let origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
            let win = NSWindow(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = true
            win.appearance = appearance
            win.contentView = effect
            win.level = .floating
            win.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            // 切到干净桌面：隐藏其它 App，让玻璃透出桌面壁纸而非终端等窗口。
            app.hideOtherApplications(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(1.6))

            let f = win.frame
            let cgY = screen.frame.height - f.maxY
            let out = (outDir as NSString).appendingPathComponent("panel-\(name).png")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-R\(f.origin.x),\(cgY),\(f.width),\(f.height)", out]
            try? p.run(); p.waitUntilExit()
            FileHandle.standardError.write("[shot] wrote \(out)\n".data(using: .utf8)!)
            win.orderOut(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        // 截完恢复其它 App 的显示，避免把用户的窗口一直藏着。
        app.unhideAllApplications(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        exit(0)
    }
}
