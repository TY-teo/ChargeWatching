import Foundation

/// 界面语言。`system` 跟随 macOS 语言偏好，其余为用户在设置中的显式覆盖。
/// 取值持久化在 UserDefaults 的 `L10n.storageKey`，视图侧用 @AppStorage 同键订阅，
/// 切换语言时所有 SwiftUI 视图自动重绘（窗口标题由 AppDelegate 另行刷新）。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    /// 语言名用该语言自称，不随界面语言变化（`system` 除外）。
    var displayName: String {
        switch self {
        case .system:  return L10n.current.t("language.system")
        case .english: return "English"
        case .russian: return "Русский"
        case .chinese: return "简体中文"
        }
    }
}

/// 轻量取串器：按选定语言解析出对应的 .lproj bundle，查不到键时回退到 en。
/// 值类型、构造极廉价，视图可在 body 内直接按需构造（见各视图的 `private var L`）。
struct L10n {
    static let storageKey = "appLanguage"

    /// 回退语言：与 Package.swift 的 defaultLocalization 一致。
    private static let fallbackCode = "en"

    private let bundle: Bundle
    private let fallback: Bundle

    init(language: AppLanguage) {
        self.bundle = Self.lprojBundle(code: Self.resolvedCode(for: language)) ?? .module
        self.fallback = Self.lprojBundle(code: Self.fallbackCode) ?? .module
    }

    /// 非视图上下文（窗口标题、错误文案、状态枚举等）用这个即时读取当前设置。
    static var current: L10n {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return L10n(language: AppLanguage(rawValue: raw) ?? .system)
    }

    /// 取串；传入参数时按 String(format:) 展开（数字格式与项目其余处一致，不做本地化小数点）。
    func t(_ key: String, _ args: CVarArg...) -> String {
        let format = lookup(key)
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    private func lookup(_ key: String) -> String {
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        if value != key { return value }
        // 选定语言缺键 → 回退 en；仍缺则原样返回键名（开发期可见）。
        return fallback.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func resolvedCode(for language: AppLanguage) -> String {
        guard language == .system else { return language.rawValue }
        let available = Bundle.module.localizations
        return Bundle.preferredLocalizations(from: available).first ?? fallbackCode
    }

    /// SPM 会把 `zh-Hans.lproj` 落盘成小写 `zh-hans.lproj`，而 `path(forResource:)` 区分大小写，
    /// 所以先按 Bundle 自己报告的 localizations 规范化一次再取路径。
    private static func lprojBundle(code: String) -> Bundle? {
        let available = Bundle.module.localizations
        let normalized = available.first { $0.caseInsensitiveCompare(code) == .orderedSame } ?? code
        guard let path = Bundle.module.path(forResource: normalized, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}
