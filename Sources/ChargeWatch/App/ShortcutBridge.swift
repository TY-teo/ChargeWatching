import Foundation
import AppKit

/// 经用户一次性创建的快捷指令桥接 macOS 26.4 动作 SetBatteryChargeLimitAction。
/// 写入与系统滑块同源的 powerd 值；无 root。
///
/// 传值机制：经实测，`shortcuts run --input-path` 在 macOS 26.4 无法把输入喂给指令，
/// 而 Shortcuts URL scheme（shortcuts://run-shortcut?...&input=text&text=N）可以，
/// 且不抢占前台。因此设置走 URL scheme；成败由 Controller 退避回读 pmset 判定。
struct ShortcutBridge: ChargeLimitSetting {
    let shortcutName: String

    init(shortcutName: String = ChargeLimitConstants.shortcutName) {
        self.shortcutName = shortcutName
    }

    /// shortcuts list 是否包含目标桥接指令。
    func isBridgeAvailable() async -> Bool {
        let result = await ProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 3)
        guard result.exitCode == 0 else { return false }
        return result.stdout
            .split(separator: "\n")
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == shortcutName }
    }

    /// 经 URL scheme 以文本输入运行桥接指令；指令内部"获取数字→设置充电上限"。
    /// URL scheme 不返回执行结果，是否生效由 Controller 回读 pmset 确认。
    func set(percent: Int) async throws {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: shortcutName),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: String(percent)),
        ]
        guard let url = components.url else {
            throw ChargeLimitError.failed("无法构造快捷指令 URL")
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        if !opened {
            throw ChargeLimitError.failed("无法运行快捷指令，请确认已创建：\(shortcutName)")
        }
    }
}
