// ChargeWatchHelper —— 以 root 运行的充电上限守护进程（Apple Silicon / macOS 26.x Tahoe）。
//
// 机制（本机实测确认，对齐 batt 的 Tahoe 路径）：
// - 充电控制键 CHIE（断适配器/放电）误用会导致电池真实放电，且 ExternalConnected 被自己污染成 No
//   → 产生“限充→误判拔电→松手→再限充”的高频抖动反馈环。本版改用 charge-disable 语义：
// - CHTE（ui32）：写 0x00000001 = 停充但保持适配器供电、电池不放电（CHSC 即时 1→0）；写 0 = 允许充电。
// - 物理适配器在位用 SMC 的 AC-W（≥0 在位，0xff 拔掉），不受充电控制污染；不再用 ExternalConnected 当真值。
// - 滞回：SoC ≥ limit 停充；SoC ≤ limit-deadband 恢复。deadband 默认 5，对齐 Apple 官方“掉超过 5% 才回充”。
// - 自动校准：每 calibrationDays 天放行充满到 100% 一次，维持电量计（SoC）估算准确（对齐 Apple“偶尔充满”）。
//
// 安全（fail-safe）：退出/崩溃/信号一律写回 CHTE=0 且 CHIE=0（恢复充电、接通适配器），由 launchd KeepAlive 重启。
// 配置来自用户态 app 写的 JSON：/Users/Shared/ChargeWatch/smc-limit.json
//   {"enabled":true,"limit":80,"deadband":5,"calibrationDays":7}
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
        return read(key, UInt32(value.count)) == value  // 写后回读校验
    }
}

// MARK: 电池读数
// SoC 来自 IORegistry(免 root)；物理适配器在位来自 SMC AC-W（不受 CHTE/CHIE 污染）。
// 注意：IORegistry 的 IsCharging/Amperage 刷新很慢，不用于控制判断。
struct Battery { let soc: Int; let fullyCharged: Bool; let adapterPresent: Bool }
func readBattery() -> Battery? {
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard svc != 0 else { return nil }
    defer { IOObjectRelease(svc) }
    var p: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(svc, &p, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let d = p?.takeRetainedValue() as? [String: Any] else { return nil }
    let soc = (d["CurrentCapacity"] as? NSNumber)?.intValue ?? -1
    let full = (d["FullyCharged"] as? Bool) ?? false
    return Battery(soc: soc, fullyCharged: full, adapterPresent: adapterPhysicallyPresent(fallback: d))
}

/// 物理适配器是否在位：优先 SMC AC-W（≥0 在位，<0 拔掉），失败时回退 IORegistry。
func adapterPhysicallyPresent(fallback d: [String: Any]) -> Bool {
    if let b = SMC.read("AC-W", 1) {
        return Int8(bitPattern: b[0]) >= 0
    }
    if let ad = d["AdapterDetails"] as? [String: Any], (ad["Watts"] as? NSNumber)?.intValue ?? 0 > 0 { return true }
    return (d["ExternalConnected"] as? Bool) ?? false
}

// MARK: 配置
struct Config { var enabled: Bool; var limit: Int; var deadband: Int; var calibrationDays: Int }
let configPath = "/Users/Shared/ChargeWatch/smc-limit.json"
func readConfig() -> Config {
    guard let data = FileManager.default.contents(atPath: configPath),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return Config(enabled: false, limit: 80, deadband: 5, calibrationDays: 7)
    }
    let limit = min(100, max(50, (j["limit"] as? Int) ?? 80))
    let dead = min(10, max(1, (j["deadband"] as? Int) ?? 5))
    let calib = min(60, max(0, (j["calibrationDays"] as? Int) ?? 7))  // 0 = 关闭校准
    return Config(enabled: (j["enabled"] as? Bool) ?? false, limit: limit, deadband: dead, calibrationDays: calib)
}

// MARK: 校准状态持久化（跨 helper 重启保留上次满充时间）
let calibStatePath = "/Users/Shared/ChargeWatch/calib-state.json"
func readLastFullCharge() -> Date {
    if let data = FileManager.default.contents(atPath: calibStatePath),
       let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let t = j["lastFullChargeAt"] as? Double {
        return Date(timeIntervalSince1970: t)
    }
    let now = Date()           // 首次：以当前为基准，避免一上来就触发校准
    writeLastFullCharge(now)
    return now
}
func writeLastFullCharge(_ date: Date) {
    let obj: [String: Any] = ["lastFullChargeAt": date.timeIntervalSince1970]
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        try? data.write(to: URL(fileURLWithPath: calibStatePath))
    }
}

// MARK: 充电控制（charge-disable 优先，CHIE 仅兜底）
let CHTE = "CHTE"
let CHTE_ALLOW: [UInt8] = [0x00, 0x00, 0x00, 0x00]  // 允许充电
let CHTE_HOLD:  [UInt8] = [0x01, 0x00, 0x00, 0x00]  // 停充（保持适配器供电、电池不放电）
let CHIE = "CHIE"
let CHIE_CONNECT: [UInt8] = [0x00]  // 接通适配器
let CHIE_DISCONNECT: [UInt8] = [0x08]  // 断开适配器（仅 CHTE 不可用时兜底）

var useCHTE = false  // 启动时探测
func log(_ m: String) { FileHandle.standardError.write(("[chargewatch-helper] " + m + "\n").data(using: .utf8)!) }

/// 允许充电：清掉一切抑制（CHTE=0 且确保适配器接通）。
func allowCharging() {
    if useCHTE { SMC.write(CHTE, CHTE_ALLOW) }
    SMC.write(CHIE, CHIE_CONNECT)
}
/// 停充：保持适配器供电、电池不放电（CHTE）；CHTE 不可用时退回断适配器（CHIE）。
func holdCharging() {
    if useCHTE { SMC.write(CHTE, CHTE_HOLD) }
    else { SMC.write(CHIE, CHIE_DISCONNECT) }
}
func failSafeExit(_ code: Int32) -> Never { allowCharging(); log("exit -> 恢复充电 (CHTE=0, CHIE=0)"); exit(code) }

// MARK: 启动
guard SMC.start() else { log("AppleSMC open failed (need root)"); exit(3) }
useCHTE = (SMC.keyInfoSize(CHTE) == 4)
if !useCHTE && SMC.keyInfoSize(CHIE) != 1 {
    log("本机既无 CHTE 也无 CHIE，无法控制充电；放行并退出"); allowCharging(); exit(0)
}
signal(SIGTERM) { _ in failSafeExit(0) }
signal(SIGINT) { _ in failSafeExit(0) }
atexit { allowCharging() }
log("started; actuator=\(useCHTE ? "CHTE(charge-disable)" : "CHIE(adapter-disable fallback)"); config=\(configPath)")

// MARK: 主循环
var holding = false          // 当前是否处于停充
var lastFullCharge = readLastFullCharge()

func calibrationDue(_ cfg: Config) -> Bool {
    guard cfg.calibrationDays > 0, cfg.limit < 100 else { return false }
    return Date().timeIntervalSince(lastFullCharge) >= Double(cfg.calibrationDays) * 86_400
}

while true {
    let cfg = readConfig()
    guard let bat = readBattery(), bat.soc >= 0 else {
        if holding { allowCharging(); holding = false }
        Thread.sleep(forTimeInterval: 10); continue
    }

    // 满充即记录校准基准（也覆盖用户手动充满）
    if bat.soc >= 100 || bat.fullyCharged { lastFullCharge = Date(); writeLastFullCharge(lastFullCharge) }

    // 未启用 / 上限=100 / 未插电 → 放行充电
    if !cfg.enabled || cfg.limit >= 100 || !bat.adapterPresent {
        if holding { allowCharging(); holding = false }
        Thread.sleep(forTimeInterval: 10); continue
    }

    // 到期校准：放行充满，到 100% 后由上面的分支记录并自动退出校准
    if calibrationDue(cfg) {
        if holding { allowCharging(); holding = false }
        log("calibrating -> 放行充满至 100%（距上次满充 \(Int(Date().timeIntervalSince(lastFullCharge)/86_400)) 天）")
        Thread.sleep(forTimeInterval: 30); continue
    }

    let upper = cfg.limit
    let lower = max(20, cfg.limit - cfg.deadband)
    if bat.soc >= upper {
        if !holding { holding = true; holdCharging(); log("SoC \(bat.soc)% >= \(upper)% -> 停充 (CHTE=1，适配器供电、不放电)") }
        else { holdCharging() }  // 周期重写，防睡眠/唤醒重置
    } else if bat.soc <= lower {
        if holding { allowCharging(); holding = false; log("SoC \(bat.soc)% <= \(lower)% -> 恢复充电 (CHTE=0)") }
    } else {
        // 滞回带 (lower, upper)：维持当前状态。停充语义下电池基本静止，仅靠自然漏电缓慢下滑，循环极慢。
        if holding { holdCharging() } else { allowCharging() }
    }
    Thread.sleep(forTimeInterval: 10)
}
