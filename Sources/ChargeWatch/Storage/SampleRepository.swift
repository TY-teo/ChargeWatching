import Foundation

enum Granularity: String {
    case raw, tenSecond, oneMinute, fiveMinute

    var table: String {
        switch self {
        case .raw: return "samples_raw"
        case .tenSecond: return "samples_10s"
        case .oneMinute: return "samples_1min"
        case .fiveMinute: return "samples_5min"
        }
    }
}

struct AggregateStats {
    let totalChargedEnergyWh: Double
    let averageChargingWatts: Double
    let peakChargingWatts: Double
    let chargingDurationSeconds: Int
    let sampleCount: Int
}

actor SampleRepository: ObservableObject {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func insert(_ sample: PowerSample) throws {
        let sql = """
        INSERT OR REPLACE INTO samples_raw
        (ts, is_charging, external_connected, has_battery, battery_watts,
         adapter_watts, system_load_watts, voltage_mv, amperage_ma,
         soc_percent, adapter_max_watts, adapter_desc)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.write(sql) { s in
            try s.bind(1, Int(sample.timestamp.timeIntervalSince1970))
            try s.bind(2, sample.isCharging ? 1 : 0)
            try s.bind(3, sample.externalConnected ? 1 : 0)
            try s.bind(4, sample.hasBattery ? 1 : 0)
            try s.bind(5, sample.batteryWatts)
            try s.bind(6, nullable: sample.wallOutputWatts)
            try s.bind(7, nullable: sample.systemLoadWatts)
            try s.bind(8, nullable: sample.voltageMillivolts)
            try s.bind(9, nullable: sample.amperageMilliamps)
            try s.bind(10, nullable: sample.stateOfChargePercent)
            try s.bind(11, nullable: sample.adapterRatedWatts)
            try s.bind(12, nullable: sample.adapterDescription)
        }
    }

    func query(from: Date, to: Date, granularity: Granularity) throws -> [TimeSeriesPoint] {
        let table = granularity.table
        let sql = """
        SELECT ts, battery_watts, adapter_watts, system_load_watts, soc_percent,
               is_charging, external_connected
        FROM \(table)
        WHERE ts >= ? AND ts <= ?
        ORDER BY ts ASC;
        """
        return try db.query(sql, bind: { s in
            try s.bind(1, Int(from.timeIntervalSince1970))
            try s.bind(2, Int(to.timeIntervalSince1970))
        }, map: { s in
            TimeSeriesPoint(
                timestamp: Date(timeIntervalSince1970: TimeInterval(s.int64(0))),
                batteryWatts: s.double(1),
                wallOutputWatts: s.doubleOpt(2),
                systemLoadWatts: s.doubleOpt(3),
                stateOfChargePercent: s.intOpt(4),
                isCharging: s.int(5) == 1,
                externalConnected: s.int(6) == 1
            )
        })
    }

    func aggregate(from: Date, to: Date) throws -> AggregateStats {
        let series = try query(from: from, to: to, granularity: bestGranularity(from: from, to: to))
        guard !series.isEmpty else {
            return AggregateStats(totalChargedEnergyWh: 0, averageChargingWatts: 0,
                                  peakChargingWatts: 0, chargingDurationSeconds: 0, sampleCount: 0)
        }
        var totalEnergyWs: Double = 0
        var chargingSamples = 0
        var chargingWattsSum: Double = 0
        var peak: Double = 0
        var prevTs: Date? = nil
        for p in series {
            if let prev = prevTs {
                let dt = p.timestamp.timeIntervalSince(prev)
                if dt > 0, dt < 600, p.batteryWatts > 0 {
                    totalEnergyWs += p.batteryWatts * dt
                }
            }
            if p.batteryWatts > 0.5 {
                chargingSamples += 1
                chargingWattsSum += p.batteryWatts
                peak = max(peak, p.batteryWatts)
            }
            prevTs = p.timestamp
        }
        let avg = chargingSamples > 0 ? chargingWattsSum / Double(chargingSamples) : 0
        let granularityStep = bestGranularity(from: from, to: to).stepSeconds
        return AggregateStats(
            totalChargedEnergyWh: totalEnergyWs / 3600.0,
            averageChargingWatts: avg,
            peakChargingWatts: peak,
            chargingDurationSeconds: chargingSamples * granularityStep,
            sampleCount: series.count
        )
    }

    func purge(olderThan date: Date, table: String) throws {
        try db.write("DELETE FROM \(table) WHERE ts < ?") { s in
            try s.bind(1, Int(date.timeIntervalSince1970))
        }
    }

    func count(table: String) throws -> Int {
        let r = try db.scalar("SELECT count(*) FROM \(table)") { _ in } map: { $0.int(0) }
        return r ?? 0
    }

    func aggregateBucket(from sourceTable: String, to destTable: String, bucketSeconds: Int, until: Date) throws {
        let cutoff = Int(until.timeIntervalSince1970)
        let sql = """
        INSERT OR REPLACE INTO \(destTable)
          (ts, battery_watts, adapter_watts, system_load_watts, soc_percent,
           is_charging, external_connected)
        SELECT
          (ts / ?) * ? AS bucket,
          AVG(battery_watts),
          AVG(adapter_watts),
          AVG(system_load_watts),
          CAST(AVG(soc_percent) AS INTEGER),
          MAX(is_charging),
          MAX(external_connected)
        FROM \(sourceTable)
        WHERE ts < ?
        GROUP BY bucket;
        """
        try db.write(sql) { s in
            try s.bind(1, bucketSeconds)
            try s.bind(2, bucketSeconds)
            try s.bind(3, cutoff)
        }
    }

    func checkpoint() async {
        db.checkpoint()
    }

    private func bestGranularity(from: Date, to: Date) -> Granularity {
        let seconds = to.timeIntervalSince(from)
        if seconds < 86_400 { return .raw }
        if seconds < 86_400 * 7 { return .tenSecond }
        if seconds < 86_400 * 30 { return .oneMinute }
        return .fiveMinute
    }
}

struct TimeSeriesPoint: Identifiable, Equatable {
    var id: TimeInterval { timestamp.timeIntervalSince1970 }
    let timestamp: Date
    let batteryWatts: Double
    let wallOutputWatts: Double?
    let systemLoadWatts: Double?
    let stateOfChargePercent: Int?
    let isCharging: Bool
    let externalConnected: Bool
}

private extension Granularity {
    var stepSeconds: Int {
        switch self {
        case .raw: return 1
        case .tenSecond: return 10
        case .oneMinute: return 60
        case .fiveMinute: return 300
        }
    }
}
