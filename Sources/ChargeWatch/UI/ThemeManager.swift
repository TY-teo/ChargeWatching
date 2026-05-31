import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case classic
    case vibrancy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "经典"
        case .vibrancy: return "玻璃"
        }
    }

    var description: String {
        switch self {
        case .classic: return "不透明面板，跟随系统深浅模式"
        case .vibrancy: return "磨砂玻璃质感，桌面隐约可见"
        }
    }
}

extension View {
    /// 面板背景。
    /// vibrancy：不再叠加自定义材质——面板就放在 NSPopover 自带的系统 popover 材质之上，
    /// 由系统提供唯一一层玻璃（与参考项目 MenuBarExtra(.window) 同一种系统材质，明亮且清晰）。
    /// 此前在 popover 自带材质之上又叠了一层 .popover/.behindWindow，双层材质导致发暗、文字看不清。
    /// classic：不透明窗口底。两者都完全跟随系统深浅模式，不强制配色。
    @ViewBuilder
    func panelBackground(theme: AppTheme) -> some View {
        switch theme {
        case .classic:
            background(AppColor.bgPrimary)
        case .vibrancy:
            self
        }
    }

    /// 独立窗口背景。classic 不透明；vibrancy 用窗下材质透出桌面，跟随系统外观。
    @ViewBuilder
    func windowBackground(theme: AppTheme) -> some View {
        switch theme {
        case .classic:
            background(AppColor.bgPrimary)
        case .vibrancy:
            background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        }
    }

    /// 主题感知卡片表面：实体抬升的卡片，而非凹陷的灰槽。
    /// classic：用比窗口底高一级的 controlBackgroundColor 实体填充 + separator hairline +
    /// 极淡投影，正是 macOS 系统设置内嵌卡片的配方，深浅模式自动反相，卡片浮于面板之上。
    /// vibrancy：popover 材质之上不再叠第二层材质（避免 glass-on-glass），改用抬升的
    /// 半透明 secondary 填充（前进色，非凹陷的 quaternary）+ 顶部白色微高光描边 + 极淡投影，
    /// 读起来像贴合玻璃的薄层叠加，桌面透出时仍保持对比度。两种主题都跟随系统外观，不强制配色。
    /// 此签名被 Settings / History / Onboarding 共享，必须保留。
    @ViewBuilder
    func cardSurface(theme: AppTheme, radius: CGFloat = AppRadius.m) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch theme {
        case .classic:
            self
                .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
        case .vibrancy:
            // 玻璃主题：卡片底用 SwiftUI 层级填充 .quaternary——在真正的系统材质之上它会按
            // vibrancy 渲染、深浅模式自动适配并抬升（此前发灰发暗是因为面板叠了双层材质、
            // 不是真材质环境；现在面板只剩 NSPopover 单层系统玻璃，层级填充即可正确提亮）。
            // 配 separator hairline 勾边；不叠第二层模糊材质（非 glass-on-glass）。
            self
                .background(shape.fill(.quaternary))
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }

    /// 兼容保留：历史上用于强制玻璃主题浅色配色，现已废弃为 no-op，
    /// 外观一律跟随系统。保留签名以免调用点破裂。
    @available(*, deprecated, message: "外观跟随系统，无需强制配色；此修饰符已为 no-op")
    @ViewBuilder
    func glassAppearance(_ theme: AppTheme) -> some View {
        self
    }
}

@MainActor
enum ThemeWindowConfigurator {
    /// 让窗口允许 SwiftUI 控制背景，并支持 vibrancy 透传桌面。
    /// 标题栏保留默认 chrome（含标题文本），最大化兼容 v0.1.0 视觉。
    static func prepareForThemeable(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        // 保留系统标题栏（可见、可拖拽）；玻璃感由内容区材质提供，不再让标题栏透明。
    }
}
