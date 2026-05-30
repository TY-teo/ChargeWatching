import Foundation

/// 当前充电上限状态（来源：pmset -g battlimit，按 chargeSocLimitReason=manualChargeLimit 甄别）。
enum ChargeLimitState: Equatable {
    case unknown        // 尚未读取（UI 显示 —）
    case unsupported    // 无法读取（非 Apple Silicon / pmset 不可用）
    case unlimited      // 未设上限（等价 100% / 无限制）
    case limited(Int)   // 当前用户上限百分比
}

/// 设置失败的分类，驱动差异化降级 UI。
enum ChargeLimitError: Error, Equatable {
    case permissionDenied      // 自动化(TCC) 授权被拒
    case bridgeMisconfigured   // 退出码 0 但回读未变（如误开 setUntilTomorrow）
    case timeout
    case failed(String)
}

/// 能力门禁：读取 / 平台支持设置 / 桥接已配置 / 可在 app 内设置。
struct ChargeLimitCapability: Equatable {
    var canRead: Bool
    var platformSupportsSet: Bool   // 硬件 Apple Silicon && macOS ≥ 26.4
    var bridgeConfigured: Bool      // 存在名为 ChargeLimitConstants.shortcutName 的快捷指令
    var canSetInApp: Bool           // platformSupportsSet && bridgeConfigured && 自动化未被拒

    static let none = ChargeLimitCapability(canRead: false, platformSupportsSet: false, bridgeConfigured: false, canSetInApp: false)
}

/// 读取/设置抽象（便于注入与测试；与架构文档 §13.3 契约一致）。
protocol ChargeLimitReading {
    func read() async -> ChargeLimitState
}

protocol ChargeLimitSetting {
    func isBridgeAvailable() async -> Bool
    func set(percent: Int) async throws
}

/// 卡片呈现模式（由 ChargeLimitController 依状态 + 能力派生，驱动 UI 分支）。
enum ChargeLimitUIMode {
    case hidden          // 不支持读取 → 整卡隐藏
    case loading         // 尚未读到
    case control         // 可在 app 内调节（段控）
    case onboarding      // 平台支持但桥接未配置 → 引导
    case permissionDenied // 桥接已配但自动化授权被拒
    case deepLinkOnly    // 旧系统/Intel：只读 + 深链
}

/// 单一事实源：档位与桥接快捷指令名称（PRD/架构/UIUX/代码共用）。
enum ChargeLimitConstants {
    static let steps: [Int] = [80, 85, 90, 95, 100]
    /// 桥接快捷指令名称——onboarding 文案、isBridgeAvailable 探测、shortcuts run 三处必须一致。
    static let shortcutName = "ChargeWatch Set Battery Charge Limit"
}
