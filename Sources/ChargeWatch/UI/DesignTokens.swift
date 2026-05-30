import SwiftUI

enum AppColor {
    static let chargingActive = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.204, green: 0.827, blue: 0.388, alpha: 1) : NSColor(red: 0.122, green: 0.620, blue: 0.290, alpha: 1)
    })
    static let chargingPaused = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.612, green: 0.639, blue: 0.686, alpha: 1) : NSColor(red: 0.420, green: 0.447, blue: 0.502, alpha: 1)
    })
    static let discharging = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.984, green: 0.573, blue: 0.235, alpha: 1) : NSColor(red: 0.761, green: 0.255, blue: 0.047, alpha: 1)
    })
    static let warningHigh = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.973, green: 0.443, blue: 0.443, alpha: 1) : NSColor(red: 0.725, green: 0.110, blue: 0.110, alpha: 1)
    })
    static let bgPrimary = Color(nsColor: .windowBackgroundColor)
    static let bgSecondary = Color(nsColor: .controlBackgroundColor)
    static let bgTertiary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04)
    })
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let divider = Color(nsColor: .separatorColor)
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

enum AppFont {
    static let menuBarNumber = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
    static let panelHeadline = Font.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
    static let panelSubheadline = Font.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit()
    static let panelLabel = Font.system(size: 10, weight: .medium).smallCaps()
    static let panelBody = Font.system(size: 13, weight: .regular)
    static let panelCaption = Font.system(size: 11, weight: .regular)
    static let buttonLabel = Font.system(size: 11, weight: .medium)
    static let chartAxis = Font.system(size: 10, weight: .medium)
    static let unitSuffix = Font.system(size: 14, weight: .medium, design: .rounded)
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum AppRadius {
    static let s: CGFloat = 6
    static let m: CGFloat = 10
    static let l: CGFloat = 14
}

enum AppIcon {
    static let chargingActive = "bolt.fill"
    static let chargingPaused = "bolt.slash.fill"
    static let powerPlug = "powerplug.fill"
    static let cpu = "cpu.fill"
    static let history = "chart.xyaxis.line"
    static let settings = "gearshape.fill"
    static let export = "square.and.arrow.up"
    static let quit = "power"
    static let info = "info.circle"
    static let warning = "exclamationmark.triangle"
    static let calendar = "calendar"
    static let chargeLimit = "minus.plus.batteryblock"

    static func batterySymbol(for soc: Int?) -> String {
        guard let soc else { return "battery.0" }
        switch soc {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
