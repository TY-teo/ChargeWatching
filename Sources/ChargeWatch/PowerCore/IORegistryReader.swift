import Foundation
import IOKit

final class IORegistryReader {

    func read() -> PowerSample {
        let timestamp = Date()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))

        guard service != 0 else {
            return desktopFallback(timestamp: timestamp)
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dict = propsRef?.takeRetainedValue() as? [String: Any] else {
            return desktopFallback(timestamp: timestamp)
        }

        let voltage = readInt(dict, "Voltage")
        let amperage = readSignedInt(dict, "Amperage")
        let isCharging = (dict["IsCharging"] as? Bool) ?? false
        let externalConnected = (dict["ExternalConnected"] as? Bool) ?? false
        let soc = readInt(dict, "CurrentCapacity")

        let adapterDetails = dict["AdapterDetails"] as? [String: Any]
        let adapterRated = readInt(adapterDetails ?? [:], "Watts")
        let adapterDesc = formatAdapter(adapterDetails)

        let telemetry = dict["PowerTelemetryData"] as? [String: Any]
        let systemLoadMilliwatts = readInt(telemetry ?? [:], "SystemLoad")
        let systemPowerInMilliwatts = readInt(telemetry ?? [:], "SystemPowerIn")
        let adapterEfficiencyLossMilliwatts = readInt(telemetry ?? [:], "AdapterEfficiencyLoss")

        let batteryWatts: Double
        if let v = voltage, let a = amperage {
            batteryWatts = Double(v) * Double(a) / 1_000_000.0
        } else {
            batteryWatts = 0
        }

        let systemLoadWatts = systemLoadMilliwatts.map { Double($0) / 1000.0 }

        // 墙插输出功率（从插座拉了多少瓦）
        // 优先用 SMC 直接测量的 SystemPowerIn + AdapterEfficiencyLoss
        // SystemPowerIn = 0 时（采样间隙）fallback 到能量守恒 (load + battery)
        let wallOutputWatts: Double?
        if externalConnected {
            if let sysIn = systemPowerInMilliwatts, sysIn > 0 {
                let lossMw = adapterEfficiencyLossMilliwatts ?? 0
                wallOutputWatts = Double(sysIn + lossMw) / 1000.0
            } else if let load = systemLoadWatts {
                wallOutputWatts = max(0, load + batteryWatts)
            } else {
                wallOutputWatts = nil
            }
        } else {
            wallOutputWatts = nil
        }

        return PowerSample(
            timestamp: timestamp,
            isCharging: isCharging,
            externalConnected: externalConnected,
            hasBattery: true,
            batteryWatts: batteryWatts,
            wallOutputWatts: wallOutputWatts,
            systemLoadWatts: systemLoadWatts,
            voltageMillivolts: voltage,
            amperageMilliamps: amperage,
            stateOfChargePercent: soc,
            adapterRatedWatts: adapterRated,
            adapterDescription: adapterDesc
        )
    }

    private func desktopFallback(timestamp: Date) -> PowerSample {
        PowerSample(
            timestamp: timestamp,
            isCharging: false,
            externalConnected: true,
            hasBattery: false,
            batteryWatts: 0,
            wallOutputWatts: nil,
            systemLoadWatts: nil,
            voltageMillivolts: nil,
            amperageMilliamps: nil,
            stateOfChargePercent: nil,
            adapterRatedWatts: nil,
            adapterDescription: nil
        )
    }

    private func readInt(_ dict: [String: Any], _ key: String) -> Int? {
        guard let n = dict[key] as? NSNumber else { return nil }
        return n.intValue
    }

    private func readSignedInt(_ dict: [String: Any], _ key: String) -> Int? {
        guard let n = dict[key] as? NSNumber else { return nil }
        let bits = n.int64Value
        return Int(truncatingIfNeeded: bits)
    }

    private func formatAdapter(_ details: [String: Any]?) -> String? {
        guard let d = details, let watts = readInt(d, "Watts") else { return nil }
        let mv = readInt(d, "AdapterVoltage")
        let ma = readInt(d, "Current")
        let desc = (d["Description"] as? String)?.uppercased() ?? "ADAPTER"
        if let mv, let ma {
            let v = Double(mv) / 1000.0
            let a = Double(ma) / 1000.0
            return String(format: "%dW %@ · %.0fV/%.1fA", watts, desc, v, a)
        }
        return "\(watts)W \(desc)"
    }
}
