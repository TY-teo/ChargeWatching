import Foundation

/// 读取系统当前充电上限：解析 `pmset -g battlimit`。无 root，权威，与系统设置同步。
struct ChargeLimitReader: ChargeLimitReading {
    func read() async -> ChargeLimitState {
        let result = await ProcessRunner.run("/usr/bin/pmset", ["-g", "battlimit"], timeout: 2)
        guard result.exitCode == 0 else { return .unsupported }
        return Self.parse(result.stdout)
    }

    /// pmset 返回一个数组，可能含多条 { chargeSocLimitReason=…; chargeSocLimitSoc=…; }。
    /// 优先取 reason=manualChargeLimit 的条目作为用户上限；无则取最小 SoC（最保守）。
    static func parse(_ output: String) -> ChargeLimitState {
        if output.localizedCaseInsensitiveContains("No battery level limits set") {
            return .unlimited
        }
        let entries = parseEntries(output)
        if let manual = entries.first(where: { $0.reason == "manualChargeLimit" }) {
            return .limited(manual.soc)
        }
        if let minSoc = entries.map(\.soc).min() {
            return .limited(minSoc)
        }
        // 既不是"无限制"也解析不出 soc：命令有输出但格式陌生 → 未知；完全空 → 不支持。
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unsupported : .unknown
    }

    private struct Entry { let soc: Int; let reason: String? }

    private static func parseEntries(_ output: String) -> [Entry] {
        guard let socRegex = try? NSRegularExpression(pattern: #"chargeSocLimitSoc\s*=\s*(\d+)"#, options: [.caseInsensitive]) else {
            return []
        }
        let reasonRegex = try? NSRegularExpression(pattern: #"chargeSocLimitReason\s*=\s*([A-Za-z]+)"#, options: [.caseInsensitive])
        var entries: [Entry] = []
        // 以 "}" 切分为各 dict 片段，逐片提取 soc + reason。
        for chunk in output.components(separatedBy: "}") {
            let range = NSRange(chunk.startIndex..., in: chunk)
            guard let m = socRegex.firstMatch(in: chunk, range: range),
                  let socR = Range(m.range(at: 1), in: chunk),
                  let soc = Int(chunk[socR]) else { continue }
            var reason: String?
            if let reasonRegex,
               let rm = reasonRegex.firstMatch(in: chunk, range: range),
               let rr = Range(rm.range(at: 1), in: chunk) {
                reason = String(chunk[rr])
            }
            entries.append(Entry(soc: soc, reason: reason))
        }
        return entries
    }
}
