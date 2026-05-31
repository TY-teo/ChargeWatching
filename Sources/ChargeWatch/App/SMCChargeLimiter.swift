import Foundation
import SwiftUI
import AppKit

/// 直接控制充电上限（绕开快捷指令）：经一个以 root 运行的 helper 守护进程写 SMC 键 CHIE。
/// 首次"开启"时经 macOS 管理员授权安装 helper（一次性密码），之后纯写配置文件、无需再授权。
/// 与系统原生充电上限相互独立，互不删除；停用/卸载即恢复正常充电。
@MainActor
final class SMCChargeLimiter: ObservableObject {
    @Published private(set) var installed: Bool = false
    @Published private(set) var enabled: Bool = false
    @Published private(set) var limit: Int = 80
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?

    /// CHIE 路径可做任意上限（含 <80%，系统原生做不到的区间）。
    static let steps: [Int] = [50, 60, 70, 80, 90]

    private let configDir = "/Users/Shared/ChargeWatch"
    private let configPath = "/Users/Shared/ChargeWatch/smc-limit.json"
    private let plistPath = "/Library/LaunchDaemons/com.chenran.chargewatch.helper.plist"
    private let deadband = 3

    init() { reload() }

    /// 从磁盘刷新安装状态与配置。
    func reload() {
        installed = FileManager.default.fileExists(atPath: plistPath)
        if let data = FileManager.default.contents(atPath: configPath),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            enabled = (j["enabled"] as? Bool) ?? false
            limit = (j["limit"] as? Int) ?? 80
        }
    }

    // MARK: 开启 / 调节 / 关闭

    /// 开启上限：未安装则先经管理员授权安装 helper，再写启用配置。
    func enable(limit percent: Int) {
        lastError = nil
        if installed {
            limit = percent; enabled = true
            writeConfig()
        } else {
            install { [weak self] ok in
                guard let self else { return }
                if ok { self.limit = percent; self.enabled = true; self.writeConfig() }
            }
        }
    }

    func setLimit(_ percent: Int) {
        limit = percent
        if enabled { writeConfig() }
    }

    func disable() {
        enabled = false
        writeConfig()
    }

    // MARK: 安装 / 卸载（osascript 管理员授权，弹一次系统密码框）

    func install(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard let script = bundledPath("install-helper", "sh"),
              let helper = bundledPath("chargewatch-helper", nil) else {
            lastError = "未找到打包内的 helper / 安装脚本"; completion(false); return
        }
        runAdmin("bash '\(script)' install '\(helper)'") { [weak self] ok, err in
            guard let self else { return }
            self.installed = FileManager.default.fileExists(atPath: self.plistPath)
            if !ok && !self.installed { self.lastError = err ?? "安装失败" }
            completion(self.installed)
        }
    }

    func uninstall() {
        guard let script = bundledPath("install-helper", "sh") else { return }
        enabled = false; writeConfig()
        runAdmin("bash '\(script)' uninstall") { [weak self] _, _ in
            guard let self else { return }
            self.installed = FileManager.default.fileExists(atPath: self.plistPath)
        }
    }

    // MARK: 内部

    private func writeConfig() {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let obj: [String: Any] = ["enabled": enabled, "limit": limit, "deadband": deadband]
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
    }

    /// 打包资源路径（.app/Contents/Resources）；开发态回退到 .build/release 与 scripts/。
    private func bundledPath(_ name: String, _ ext: String?) -> String? {
        if let res = Bundle.main.resourceURL {
            let u = res.appendingPathComponent(ext == nil ? name : "\(name).\(ext!)")
            if FileManager.default.fileExists(atPath: u.path) { return u.path }
        }
        let dev = name == "chargewatch-helper"
            ? FileManager.default.currentDirectoryPath + "/.build/release/chargewatch-helper"
            : FileManager.default.currentDirectoryPath + "/scripts/\(name).\(ext ?? "")"
        return FileManager.default.fileExists(atPath: dev) ? dev : nil
    }

    private func runAdmin(_ shellCommand: String, _ completion: @escaping (Bool, String?) -> Void) {
        busy = true
        let escaped = shellCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", appleScript]
            let errPipe = Pipe(); p.standardError = errPipe; p.standardOutput = Pipe()
            var ok = false; var err: String?
            do {
                try p.run(); p.waitUntilExit()
                ok = (p.terminationStatus == 0)
                if !ok { err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) }
            } catch { err = error.localizedDescription }
            let fok = ok; let ferr = err
            await MainActor.run { self.busy = false; completion(fok, ferr) }
        }
    }
}
