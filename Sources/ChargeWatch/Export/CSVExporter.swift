import Foundation

enum CSVExporter {
    static func makeCSV(from points: [TimeSeriesPoint]) -> String {
        var out = "timestamp,iso8601,is_charging,external_connected,battery_watts,wall_output_watts,system_load_watts,soc_percent\n"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for p in points {
            let ts = Int(p.timestamp.timeIntervalSince1970)
            let iso = formatter.string(from: p.timestamp)
            out += "\(ts),\(iso),"
            out += "\(p.isCharging ? 1 : 0),\(p.externalConnected ? 1 : 0),"
            out += String(format: "%.3f", p.batteryWatts) + ","
            out += p.wallOutputWatts.map { String(format: "%.3f", $0) } ?? ""
            out += ","
            out += p.systemLoadWatts.map { String(format: "%.3f", $0) } ?? ""
            out += ","
            out += p.stateOfChargePercent.map { String($0) } ?? ""
            out += "\n"
        }
        return out
    }
}
