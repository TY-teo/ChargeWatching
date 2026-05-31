// ChargeWatchHelper —— 以 root 运行的充电上限守护进程（macOS 26.4 / Apple Silicon）。
//
// 机制（本机 M5 实测确认）：CH0C/CH0B 不存在、CHTE 对充电惰性；唯一可用键是
// CHIE（适配器开关）：写 0x08 断开适配器(走电池→停充)，写 0x00 接通(允许充电)。
// 限到 N%：SoC ≥ N 断适配器，SoC ≤ N-deadband 接通，在小区间内滞回保持。
//
// 安全（仿 batt/Battery-Toolkit）：
// - 退出/崩溃/信号一律写回 CHIE=0x00（fail-safe 恢复充电），由 launchd KeepAlive 重启。
// - 写后回读校验；限值 clamp 到 [50,100]；deadband 默认 3。
// - SoC 来自 IORegistry(免 root 读)；仅在已接电时才介入。
// 配置来自用户态 app 写的 JSON：/Users/Shared/ChargeWatch/smc-limit.json
//   {"enabled":true,"limit":80,"deadband":3}
import Foundation
import IOKit

// MARK: SMC（已在本机验证的 Apple Silicon 接口）
enum SMC {
    static let kOpen: UInt32 = 0, kYPC: UInt32 = 2
    static let kRead: UInt8 = 5, kWrite: UInt8 = 6, kInfo: UInt8 = 9, kOK: UInt8 = 0
    static let SZ = 80, OKEY = 0, ODSIZE = 28, ORES = 40, OD8 = 42, OBYTES = 48
    static var conn: io_connect_t = 0

    static func start() -> Bool {
        let smc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard smc != 0 else { return false }
        defer { IOObjectRelease(smc) }
        guard IOServiceOpen(smc, mach_task_self_, 1, &conn) == KERN_SUCCESS else { return false }
        _ = IOConnectCallMethod(conn, kOpen, nil, 0, nil, 0, nil, nil, nil, nil)
        return true
    }
    static func fourCC(_ s: String) -> UInt32 { var r: UInt32 = 0; for b in s.utf8 { r = (r << 8) | UInt32(b) }; return r }
    private static func putU32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) { b[o]=UInt8(v&0xff); b[o+1]=UInt8((v>>8)&0xff); b[o+2]=UInt8((v>>16)&0xff); b[o+3]=UInt8((v>>24)&0xff) }
    private static func call(_ input: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: SZ); var sz = SZ
        let kr = input.withUnsafeBytes { i in out.withUnsafeMutableBytes { o in
            IOConnectCallStructMethod(conn, kYPC, i.baseAddress, SZ, o.baseAddress, &sz) } }
        return kr == KERN_SUCCESS ? out : nil
    }
    static func keyInfoSize(_ key: String) -> UInt32? {
        var b = [UInt8](repeating: 0, count: SZ); putU32(&b, OKEY, fourCC(key)); b[OD8] = kInfo
        guard let o = call(b), o[ORES] == kOK else { return nil }
        return UInt32(o[ODSIZE]) | (UInt32(o[ODSIZE+1])<<8) | (UInt32(o[ODSIZE+2])<<16) | (UInt32(o[ODSIZE+3])<<24)
    }
    static func read(_ key: String, _ size: UInt32) -> [UInt8]? {
        guard size > 0, size <= 32 else { return nil }
        var b = [UInt8](repeating: 0, count: SZ); putU32(&b, OKEY, fourCC(key)); putU32(&b, ODSIZE, size); b[OD8] = kRead
        guard let o = call(b), o[ORES] == kOK else { return nil }
        return Array(o[OBYTES..<OBYTES+Int(size)])
    }
    @discardableResult
    static func write(_ key: String, _ value: [UInt8]) -> Bool {
        var b = [UInt8](repeating: 0, count: SZ); putU32(&b, OKEY, fourCC(key)); putU32(&b, ODSIZE, UInt32(value.count)); b[OD8] = kWrite
        for (i, v) in value.enumerated() { b[OBYTES+i] = v }
        guard let o = call(b), o[ORES] == kOK else { return false }
        // 写后回读校验
        return read(key, UInt32(value.count)) == value
    }
}

// MARK: 电池读数（IORegistry，免 root）
struct Battery { let soc: Int; let external: Bool; let charging: Bool }
func readBattery() -> Battery? {
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard svc != 0 else { return nil }
    defer { IOObjectRelease(svc) }
    var p: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(svc, &p, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let d = p?.takeRetainedValue() as? [String: Any] else { return nil }
    let soc = (d["CurrentCapacity"] as? NSNumber)?.intValue ?? -1
    return Battery(soc: soc,
                   external: (d["ExternalConnected"] as? Bool) ?? false,
                   charging: (d["IsCharging"] as? Bool) ?? false)
}

// MARK: 配置
struct Config { var enabled: Bool; var limit: Int; var deadband: Int }
let configPath = "/Users/Shared/ChargeWatch/smc-limit.json"
func readConfig() -> Config {
    guard let data = FileManager.default.contents(atPath: configPath),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return Config(enabled: false, limit: 80, deadband: 3)
    }
    let limit = min(100, max(50, (j["limit"] as? Int) ?? 80))
    let dead = min(10, max(1, (j["deadband"] as? Int) ?? 3))
    return Config(enabled: (j["enabled"] as? Bool) ?? false, limit: limit, deadband: dead)
}

// MARK: CHIE 控制
let CHIE = "CHIE"
let CHIE_ON: [UInt8] = [0x00]   // 接通适配器（允许充电）
let CHIE_OFF: [UInt8] = [0x08]  // 断开适配器（停充/走电池）
func log(_ m: String) { FileHandle.standardError.write(("[chargewatch-helper] " + m + "\n").data(using: .utf8)!) }

func allowCharging() { SMC.write(CHIE, CHIE_ON) }
func failSafeExit(_ code: Int32) -> Never { allowCharging(); log("exit -> CHIE=0x00 (allow charging)"); exit(code) }

// MARK: 启动
guard SMC.start() else { log("AppleSMC open failed (need root)"); exit(3) }
guard let sz = SMC.keyInfoSize(CHIE), sz == 1 else { log("CHIE unsupported on this machine; idling without control"); allowCharging(); exit(0) }
signal(SIGTERM) { _ in failSafeExit(0) }
signal(SIGINT) { _ in failSafeExit(0) }
atexit { allowCharging() }
log("started; CHIE size=\(sz); config=\(configPath)")

// 滞回状态：当前是否处于"已断开适配器"
var inhibiting = false
var lastMissedGuard = Date()

while true {
    let cfg = readConfig()
    guard let bat = readBattery(), bat.soc >= 0 else { allowCharging(); inhibiting = false; Thread.sleep(forTimeInterval: 10); continue }

    if !cfg.enabled || !bat.external || cfg.limit >= 100 {
        // 未启用 / 未接电 / 上限=100 → 允许充电
        if inhibiting || !cfg.enabled { allowCharging(); inhibiting = false }
        Thread.sleep(forTimeInterval: 10); continue
    }

    let upper = cfg.limit
    let lower = max(50, cfg.limit - cfg.deadband)
    if bat.soc >= upper && !inhibiting {
        if SMC.write(CHIE, CHIE_OFF) { inhibiting = true; log("SoC \(bat.soc)% >= \(upper)% -> inhibit (CHIE=0x08)") }
    } else if bat.soc <= lower && inhibiting {
        allowCharging(); inhibiting = false; log("SoC \(bat.soc)% <= \(lower)% -> allow (CHIE=0x00)")
    } else if inhibiting {
        // 维持禁充：周期性重写，防 SMC 状态被唤醒/睡眠重置
        SMC.write(CHIE, CHIE_OFF)
    }
    Thread.sleep(forTimeInterval: 10)
    _ = lastMissedGuard
}
