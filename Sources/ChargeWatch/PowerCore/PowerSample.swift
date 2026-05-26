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
        case .charging: return "充电中"
        case .acPaused: return "已接电源"
        case .discharging: return "电池放电"
        case .desktop: return "市电运行"
        }
    }
}
