import Foundation
import SwiftUI
import AppKit

/// 充电上限 UI 的唯一数据源：读取 + 设置编排 + 能力门禁 + 轮询生命周期 + 降级。
/// 由 AppContainer 创建，经 StatusBarController 注入 MenuBarPanel。
@MainActor
final class ChargeLimitController: ObservableObject {
    @Published private(set) var state: ChargeLimitState = .unknown
    @Published private(set) var capability: ChargeLimitCapability = .none
    @Published private(set) var lastError: ChargeLimitError?
    @Published private(set) var isSetting = false

    /// 由 AppDelegate 设置：打开一次性引导窗口（NSWindow，非 sheet）。
    var onOpenOnboarding: (() -> Void)?

    private let reader: any ChargeLimitReading
    private let bridge: any ChargeLimitSetting
    private var pollTimer: Timer?

    init(reader: any ChargeLimitReading = ChargeLimitReader(), bridge: any ChargeLimitSetting = ShortcutBridge()) {
        self.reader = reader
        self.bridge = bridge
    }

    // MARK: 轮询生命周期（由 StatusBarController 在 popover 显示/关闭时调用）

    func startPolling() {
        Task { await refresh() }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: 读取

    func refresh() async {
        let newState = await reader.read()
        let bridgeConfigured = await bridge.isBridgeAvailable()
        state = newState
        capability = Self.computeCapability(
            state: newState,
            bridgeConfigured: bridgeConfigured,
            permissionDenied: lastError == .permissionDenied
        )
    }

    // MARK: 设置

    func set(_ percent: Int) async {
        guard ChargeLimitConstants.steps.contains(percent) else { return }
        isSetting = true
        lastError = nil
        defer { isSetting = false }
        do {
            try await bridge.set(percent: percent)
            await confirmReadBack(expected: percent)
        } catch let error as ChargeLimitError {
            lastError = error
            await refresh()
        } catch {
            lastError = .failed(error.localizedDescription)
            await refresh()
        }
    }

    /// 退避回读，覆盖 URL scheme 异步执行延迟；始终未变 → 判桥接配置错误。
    private func confirmReadBack(expected: Int) async {
        for delay in [0.6, 1.0, 1.5, 2.0, 2.5] {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if case .limited(let n) = await reader.read(), n == expected {
                await refresh()
                return
            }
        }
        lastError = .bridgeMisconfigured
        await refresh()
    }

    // MARK: UI 模式

    var uiMode: ChargeLimitUIMode {
        switch state {
        case .unsupported: return .hidden
        case .unknown: return .loading
        case .unlimited, .limited:
            if capability.canSetInApp { return .control }
            if capability.platformSupportsSet && capability.bridgeConfigured && lastError == .permissionDenied { return .permissionDenied }
            if capability.platformSupportsSet && !capability.bridgeConfigured { return .onboarding }
            return .deepLinkOnly
        }
    }

    /// 段控当前选中（不在档位集内或无限制时为 nil = 不高亮）。
    var selectedStep: Int? {
        if case .limited(let n) = state, ChargeLimitConstants.steps.contains(n) { return n }
        return nil
    }

    var currentValueText: String {
        switch state {
        case .limited(let n): return "\(n)%"
        case .unlimited: return "未设上限"
        case .unknown, .unsupported: return "—"
        }
    }

    // MARK: 降级动作

    func openOnboarding() {
        onOpenOnboarding?()
    }

    func openSystemBatterySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.battery",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 能力计算

    static func computeCapability(state: ChargeLimitState, bridgeConfigured: Bool, permissionDenied: Bool) -> ChargeLimitCapability {
        let canRead = state != .unsupported
        let osOK = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        )
        let platformSupportsSet = osOK && isAppleSiliconHardware()
        let canSetInApp = platformSupportsSet && bridgeConfigured && !permissionDenied
        return ChargeLimitCapability(
            canRead: canRead,
            platformSupportsSet: platformSupportsSet,
            bridgeConfigured: bridgeConfigured,
            canSetInApp: canSetInApp
        )
    }

    /// 硬件是否 Apple Silicon（用 sysctl，而非进程架构——避免 Rosetta 误判）。
    private static func isAppleSiliconHardware() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }
}
