import Foundation

enum DumpCommand {
    static func runAndExit() -> Never {
        let reader = IORegistryReader()
        let sample = reader.read()
        let formatter = ISO8601DateFormatter()

        print("=== ChargeWatch sample dump ===")
        print("timestamp:           \(formatter.string(from: sample.timestamp))")
        print("status:              \(sample.status.displayName)")
        print("hasBattery:          \(sample.hasBattery)")
        print("isCharging:          \(sample.isCharging)")
        print("externalConnected:   \(sample.externalConnected)")
        print(String(format: "batteryWatts:        %.2f W", sample.batteryWatts))
        if let v = sample.wallOutputWatts {
            print(String(format: "wallOutputWatts:     %.2f W", v))
        } else {
            print("wallOutputWatts:     -")
        }
        if let v = sample.systemLoadWatts {
            print(String(format: "systemLoadWatts:     %.2f W", v))
        } else {
            print("systemLoadWatts:     -")
        }
        print("voltageMV:           \(sample.voltageMillivolts.map(String.init) ?? "-")")
        print("amperageMA:          \(sample.amperageMilliamps.map(String.init) ?? "-")")
        print("SoC:                 \(sample.stateOfChargePercent.map { "\($0)%" } ?? "-")")
        print("adapter:             \(sample.adapterDescription ?? "-")")

        let limit = blockingRead { await ChargeLimitReader().read() }
        print("chargeLimit:         \(limit)")
        print("===============================")
        exit(0)
    }

    /// 同步等待一次异步读取（仅供 --dump 诊断使用）。
    private static func blockingRead<T>(_ work: @escaping () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task {
            box.value = await work()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value!
    }
}

private final class ResultBox<T> {
    var value: T?
}
