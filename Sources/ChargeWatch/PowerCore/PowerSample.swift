import Foundation

struct PowerSample: Equatable {
    let timestamp: Date
    let isCharging: Bool
    let externalConnected: Bool
    let hasBattery: Bool
    let batteryWatts: Double
    let wallOutputWatts: Double?
    let systemLoadWatts: Double?
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?
    let stateOfChargePercent: Int?
    let adapterRatedWatts: Int?
    let adapterDescription: String?

    var status: ChargeStatus {
        if !hasBattery { return .desktop }
        if isCharging && batteryWatts > 0.5 { return .charging }
        if externalConnected { return .acPaused }
        return .discharging
    }

    var displayWatts: Double {
        switch status {
        case .charging: return batteryWatts
        case .desktop: return systemLoadWatts ?? 0
        case .acPaused, .discharging: return abs(batteryWatts)
        }
    }
}

enum ChargeStatus: Equatable {
    case charging
    case acPaused
    case discharging
    case desktop

    var displayName: String {
        switch self {
        case .charging: return L10n.current.t("status.charging")
        case .acPaused: return L10n.current.t("status.ac_paused")
        case .discharging: return L10n.current.t("status.discharging")
        case .desktop: return L10n.current.t("status.desktop")
        }
    }
}
