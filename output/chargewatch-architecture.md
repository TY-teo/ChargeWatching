# ChargeWatch — 架构文档

## 1. 技术栈锁定

| 维度 | 选型 | 版本 | 理由 |
|---|---|---|---|
| 语言 | Swift | 5.9+（项目用 Swift 6 模式） | 原生、零开销 |
| UI 框架 | SwiftUI + AppKit 桥接 | macOS 13+ | 菜单栏用 `MenuBarExtra` (macOS 13+)，必要时降级 `NSStatusItem` |
| 数据库 | GRDB.swift | 6.x | 成熟、轻量、无 Core Data 复杂度 |
| 图表 | Swift Charts | macOS 13+ | 系统自带，无第三方 |
| 图标 | SF Symbols 5 | 系统自带 | **唯一图标来源，不得使用 emoji** |
| 构建 | Swift Package Manager + Xcode 15+ | — | 单一 Package.swift 管理依赖 |
| 签名 | ad-hoc 本地签名 | — | 个人使用，不发布 |

## 2. 模块拆分

```
chargewatch/
├── Package.swift
├── Sources/
│   ├── ChargeWatchApp/              # App 入口 + DI 容器
│   │   ├── ChargeWatchApp.swift     # @main，MenuBarExtra
│   │   └── AppContainer.swift       # 单例服务装配
│   ├── PowerCore/                   # 核心采集（无 UI 依赖）
│   │   ├── PowerSampler.swift       # 1Hz 采样器
│   │   ├── IORegistryReader.swift   # AppleSmartBattery 解析
│   │   ├── IOPSReader.swift         # IOPowerSources 降级路径
│   │   └── PowerSample.swift        # 数据模型
│   ├── Storage/                     # 持久化
│   │   ├── Database.swift           # GRDB 连接池
│   │   ├── SampleRepository.swift   # CRUD
│   │   ├── Migrations.swift         # schema 演进
│   │   └── Downsampler.swift        # 24h/7d/30d 聚合任务
│   ├── UI/                          # SwiftUI 视图
│   │   ├── MenuBar/
│   │   │   ├── MenuBarLabel.swift   # 菜单栏图标 + 数字
│   │   │   └── MenuBarPanel.swift   # 下拉详情面板
│   │   ├── History/
│   │   │   ├── HistoryWindow.swift  # 历史窗口主视图
│   │   │   ├── ChargeChart.swift    # Swift Charts 折线图
│   │   │   └── RangePicker.swift
│   │   ├── Settings/
│   │   │   └── SettingsWindow.swift # SMAppService 开关等
│   │   └── DesignTokens/
│   │       ├── Colors.swift         # 设计 token，禁止硬编码 hex
│   │       └── Typography.swift
│   └── Export/
│       └── CSVExporter.swift
└── Tests/
    ├── PowerCoreTests/
    └── StorageTests/
```

## 3. 核心数据流

```
┌─────────────────┐    1Hz    ┌──────────────┐
│ PowerSampler    │ ───────▶ │ IORegistry   │
│ (Timer/         │           │ Reader       │
│  DispatchSource)│           └──────┬───────┘
└────────┬────────┘                  │ parse
         │                           ▼
         │                    ┌──────────────┐
         │                    │ PowerSample  │
         │                    │ (struct)     │
         │                    └──────┬───────┘
         │                           │
         ├───────────┬───────────────┤
         ▼           ▼               ▼
   ┌──────────┐ ┌─────────┐  ┌──────────────┐
   │ Combine  │ │ GRDB    │  │ Downsampler  │
   │ Subject  │ │ insert  │  │ (每分钟)     │
   └────┬─────┘ └─────────┘  └──────────────┘
        │
        ▼
   ┌──────────────┐
   │ UI 订阅      │
   │ MenuBarLabel │
   │ MenuBarPanel │
   └──────────────┘
```

## 4. PowerSample 数据模型

```swift
struct PowerSample: Equatable, Codable {
    let timestamp: Date
    let isCharging: Bool
    let externalConnected: Bool
    let batteryWatts: Double          // 正 = 充入电池
    let adapterInputWatts: Double?    // 适配器实际输入
    let systemLoadWatts: Double?      // 系统总功耗
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?       // signed
    let stateOfChargePercent: Int?
    let adapterRatedWatts: Int?       // 适配器额定
    let adapterDescription: String?   // "100W PD 20V/5A"
}
```

## 5. 关键 API 契约

### 5.1 IORegistryReader
```swift
protocol IORegistryReading {
    func readBatterySnapshot() throws -> RawBatterySnapshot
}

struct RawBatterySnapshot {
    let voltage: Int?           // mV
    let amperage: Int?          // mA, signed
    let isCharging: Bool
    let externalConnected: Bool
    let adapterDetails: [String: Any]?
    let powerTelemetry: [String: Any]?
    let stateOfCharge: Int?
}
```

实现要点：
- `IOServiceMatching("AppleSmartBattery")` → `IORegistryEntryCreateCFProperties`
- 全字段 optional，缺失时不抛错
- 桌面 Mac 无 AppleSmartBattery 时返回 nil，由上层走 IOPS 降级路径

### 5.2 PowerSampler
```swift
final class PowerSampler {
    let publisher: AnyPublisher<PowerSample, Never>
    func start()  // 启动 1Hz 采样 + IOPS 通知回调
    func stop()
}
```

### 5.3 SampleRepository
```swift
protocol SampleRepository {
    func insert(_ sample: PowerSample) async throws
    func query(from: Date, to: Date, granularity: Granularity) async throws -> [PowerSample]
    func aggregate(from: Date, to: Date) async throws -> AggregateStats
    func purgeOlderThan(_ date: Date) async throws
}

enum Granularity { case raw, tenSecond, oneMinute, fiveMinute }

struct AggregateStats {
    let totalEnergyWh: Double      // 累计充入
    let averageWatts: Double
    let peakWatts: Double
    let chargingDurationSeconds: Int
}
```

## 6. 数据库 Schema

```sql
-- 主表（原始 1Hz 数据，仅保留 24h）
CREATE TABLE samples_raw (
  ts INTEGER PRIMARY KEY,
  is_charging INTEGER NOT NULL,
  external_connected INTEGER NOT NULL,
  battery_watts REAL NOT NULL,
  adapter_watts REAL,
  system_load_watts REAL,
  voltage_mv INTEGER,
  amperage_ma INTEGER,
  soc_percent INTEGER,
  adapter_max_watts INTEGER,
  adapter_desc TEXT
);

-- 聚合表（10s 粒度，保留 7 天）
CREATE TABLE samples_10s (...同结构, ts 为该 10s 起始);

-- 聚合表（1min 粒度，保留 30 天）
CREATE TABLE samples_1min (...);

-- 聚合表（5min 粒度，长期保留）
CREATE TABLE samples_5min (...);

CREATE INDEX idx_raw_ts ON samples_raw(ts);
CREATE INDEX idx_10s_ts ON samples_10s(ts);
-- ...
```

降采样任务（Downsampler）：
- 每 10s：把 10s 前的 raw 数据聚合写入 samples_10s，删除已聚合的 raw
- 每分钟：把 1min 前的 10s 数据聚合写入 samples_1min
- 每 5 分钟：同理
- 每天凌晨：`PRAGMA wal_checkpoint(TRUNCATE)` + purge 过期数据

## 7. UI 数据契约

### MenuBarLabel
- 输入：`@Published var latest: PowerSample?`
- 渲染：SF Symbol + `Text("\(Int(watts))W")`
- 状态映射：
  - `isCharging && batteryWatts > 0`：`bolt.fill` + 黄色 token
  - `externalConnected && !isCharging`：`bolt.slash` + 灰色 token
  - `!externalConnected`：`battery.\(socBucket)` + 颜色按 SoC

### MenuBarPanel（下拉详情）
布局（垂直）：
1. 状态横幅（高 48pt）
2. 关键数字 2×2 网格：充入功率 / 适配器输入 / 系统负载 / SoC
3. 适配器卡片（一行）
4. Sparkline（高 60pt，最近 60 个样本）
5. 操作行：4 个 TextButton

## 8. 启动与生命周期

```
App launch
  ├─ AppContainer 装配
  │   ├─ Database.open() (~/Library/Application Support/ChargeWatch/data.sqlite)
  │   ├─ SampleRepository(database)
  │   ├─ IORegistryReader()
  │   ├─ PowerSampler(reader, repository)
  │   └─ Downsampler(repository)  // 注册 NSBackgroundActivityScheduler
  ├─ MenuBarExtra 注册
  ├─ PowerSampler.start()
  └─ 接收 IOPS 通知（插拔/状态变化即时刷新）

App quit
  └─ PowerSampler.stop() → flush DB
```

## 9. 非功能保证

| 项 | 设计 |
|---|---|
| 启动速度 | 数据库懒加载，UI 先用占位，1s 内显示首个真实样本 |
| 内存 | GRDB 连接池上限 4；UI 订阅最近 60 个样本，旧数据按需查询 |
| CPU | 采样器使用 `DispatchSourceTimer`，无 RunLoop 唤醒浪费 |
| 崩溃恢复 | SQLite WAL 模式，进程崩溃不丢已写入数据 |
| 锁屏 | 继续采样（轻量），UI 暂停渲染 |

## 10. 测试策略

- **PowerCoreTests**：用 fixture 字典模拟 IORegistry 输出，覆盖：充电中 / AC 未充 / 放电 / 无电池 / 字段缺失
- **StorageTests**：内存模式 SQLite，覆盖 insert / query / aggregate / 降采样幂等
- **ManualTest**：插拔充电器、跑高负载（编译大项目）验证瓦数飙升

## 11. 部署与分发

- 构建：`swift build -c release` 或 Xcode Archive
- 签名：ad-hoc (`codesign --sign - ChargeWatch.app`)
- 安装：拷贝到 `~/Applications/`
- 自启：首次启动 onboarding 引导启用 `SMAppService`

## 12. 与 super-dev.yaml 对齐

> 后续生成 `super-dev.yaml` 时记录：tech_stack = swift+swiftui+grdb；platform = macos-menubar；distribution = local-adhoc

## 13. 充电上限调节模块（v0.4 新增）

> 设计依据：`output/chargewatch-charge-limit-research.md`。核心原则：**读取真同步、设置经 App Intents 桥接、无 root、全程可降级**。
>
> **基线校正（重要）**：本文 §1–§8 的目录树/模块名是 v0.3 之前的初稿，已与实际代码不符（实际：`Sources/ChargeWatch/{App,PowerCore,Storage,Export,UI/{MenuBar,History,Settings}}` + `UI/DesignTokens.swift`、`UI/ThemeManager.swift`、`UI/VisualEffectView.swift`；菜单栏是 **AppKit `NSStatusItem` + `NSPopover`**（`StatusBarController`），**不是** `MenuBarExtra`；无 GRDB 外部依赖）。**本节 §13 的路径与接线以实际代码为准**，§1–§8 仅作历史参考。

### 13.1 新增文件（落在实际 `Sources/ChargeWatch/` 结构）
```
PowerCore/
  ChargeLimit.swift             # 模型：ChargeLimitState / ChargeLimitCapability / ChargeLimitConstants
  ChargeLimitReader.swift       # 读：/usr/bin/pmset -g battlimit 解析（按 reason 甄别）
App/
  ProcessRunner.swift           # 通用 CLI 执行（off-main、超时、强杀、异步排空 stdout/stderr）
  ShortcutBridge.swift          # 写：检测/运行桥接快捷指令(SetBatteryChargeLimitAction)
  ChargeLimitController.swift   # @MainActor ObservableObject：状态发布 + set 编排 + 能力门禁 + 轮询生命周期
UI/MenuBar/
  ChargeLimitSection.swift      # 面板内"充电上限"卡片（5 档控件 + 当前值 + A/B/C/进度/错误态）
UI/Settings/
  ChargeLimitOnboardingView.swift  # 一次性桥接指令引导（AppDelegate 管理的独立 NSWindow）
```
`DesignTokens.swift` 的 `AppIcon` 枚举新增 `AppIcon.chargeLimit`（构建期验证有效的单一 SF Symbol，候选 `minus.plus.batteryblock`），不在视图里内联 systemName 字符串。

### 13.2 常量（单一事实源，三处文档/代码共用）
```swift
enum ChargeLimitConstants {
    static let steps: [Int] = [80, 85, 90, 95, 100]
    // 桥接快捷指令名称：onboarding 文案、isBridgeAvailable 探测、shortcuts run 三处必须用同一字面量
    static let shortcutName = "ChargeWatch Set Battery Charge Limit"
}
```
> 取代评审指出的不存在的 `Constants` 类型；PRD §9 / 架构 §13 / UIUX §13 一律引用 `ChargeLimitConstants.shortcutName`。

### 13.3 数据模型与契约
```swift
enum ChargeLimitState: Equatable {
    case unknown            // 尚未读取（UI 显示 —）
    case unsupported        // 无法读取（非 Apple Silicon / pmset 不可用）
    case unlimited          // 未设上限（等价 100%/无限制）
    case limited(Int)       // 当前用户上限（来自 pmset，reason=manualChargeLimit）
}

struct ChargeLimitCapability {
    let canRead: Bool       // pmset -g battlimit 可解析
    let bridgeConfigured: Bool   // shortcuts list 含 ChargeLimitConstants.shortcutName
    let canSetInApp: Bool   // arm64(硬件) && macOS≥26.4 && bridgeConfigured && automation 未被拒
}

protocol ChargeLimitReading {           // ChargeLimitReader
    func read() async -> ChargeLimitState
}

protocol ChargeLimitSetting {           // ShortcutBridge
    func isBridgeAvailable() async -> Bool          // shortcuts list 含目标指令
    func set(percent: Int) async throws             // shortcuts run；区分权限拒绝/超时/退出码
}
```

`ChargeLimitController`（@MainActor，UI 唯一数据源；由 `AppContainer` 创建）：
```swift
@MainActor final class ChargeLimitController: ObservableObject {
    @Published private(set) var state: ChargeLimitState = .unknown
    @Published private(set) var capability: ChargeLimitCapability
    @Published private(set) var lastError: ChargeLimitError?   // permissionDenied / bridgeMisconfigured / timeout / failed
    func refresh() async                 // popover 打开 / set 后 / 轮询
    func set(_ percent: Int) async       // 编排 set → 退避回读确认 → 刷新；失败置 lastError
    func startPolling(); func stopPolling()   // 由 StatusBarController 在 popover 显示/关闭时调用
    func openSystemBatterySettings()     // 深链兜底（分级）
    func openOnboarding()                // 触发 AppDelegate 管理的引导窗口
}
```

### 13.4 接线（镜像现有 SampleStream 注入链，必须照此实现）
1. `AppContainer.init` 创建并持有 `let chargeLimitController: ChargeLimitController`（与 `sampleStream` 并列）。
2. `AppDelegate.applicationDidFinishLaunching` 把 `container.chargeLimitController` 与新的 `onOpenOnboarding` 闭包传入 `StatusBarController`。
3. `StatusBarController.init` 增参，在 `MenuBarPanel` rootView 上追加 `.environmentObject(chargeLimitController)`（与现有 `.environmentObject(stream)` 并列）。
4. `MenuBarPanel` 增 `@EnvironmentObject private var chargeLimit: ChargeLimitController`，在 sparkline 与 Divider 之间渲染 `ChargeLimitSection`。
5. **刷新/轮询生命周期**：`StatusBarController` 实现 `NSPopoverDelegate`，在 `popoverWillShow`→`controller.startPolling()`（立即 refresh + 启动 15s 定时器），`popoverDidClose`→`controller.stopPolling()`（invalidate 定时器）。**不依赖** SwiftUI `onAppear`（NSPopover 复用 hosting controller，onAppear 不保证每次重显都触发），从而满足 prd §5 的 <0.5% 空闲 CPU（关闭时不 spawn）。

### 13.5 读取路径（无 root，权威，已本机验证）
- 执行 `/usr/bin/pmset -g battlimit`（`ProcessRunner`，工具队列，超时 2s）。
- 解析规则（评审要点：pmset 返回**数组**，`chargeSocLimitSoc` 可能多条）：
  - 含 `No battery level limits set` → `.unlimited`。
  - 否则提取所有 `{ ... chargeSocLimitReason = X; chargeSocLimitSoc = N; ... }` 条目，**优先取 `chargeSocLimitReason = manualChargeLimit` 的条目**作为用户上限；若有多条 manual 取其一致值，无 manual 条目则取最小 SoC（最保守）。
  - 正则对大小写/空白宽松（`chargeSocLimitSoc\s*=\s*(\d+)`），并解析对应 reason；解析失败/命令缺失 → `.unsupported`。
  - 读到的 N 若不在 `steps` 内：`.limited(N)` 照常用于**显示**，但段控按"最近档高亮 + 不精确选中"处理。
- 触发时机：popover 显示时 refresh + 仅可见时 15s 轮询；set 之后退避回读。**不**进 1Hz 采样链。
- 明确**不**用 `AppleSmartBattery.DailyMaxSoc`（实测为遥测，未设上限时仍=80）。

### 13.6 设置路径（App Intents 桥接，无 root，同步）— spike 已定型为 URL scheme
> spike 结论（本机 macOS 26.4 实测，见 §13.9）：`shortcuts run --input-path`/stdin **无法把值喂给指令**（对任意指令都报"无法处理快捷指令的输入"）；而 **Shortcuts URL scheme 可以**，且不抢占前台。故设置走 URL scheme，**单条用户指令即可，无需 5 条、无需剪贴板、无需 root**。

- 目标动作：`SetBatteryChargeLimitAction`（macOS 26.4），写入与系统滑块同源的 powerd 值。
- 桥接指令（用户一次性创建，名 `ChargeLimitConstants.shortcutName`）：`获取数字(快捷指令输入) → 设置充电上限`，`setUntilTomorrow=false`（持久）。
- App 调用：`NSWorkspace.shared.open("shortcuts://run-shortcut?name=<name>&input=text&text=<percent>")`（用 `URLComponents`/`URLQueryItem` 编码）。URL scheme 异步、无返回码。
- 回读确认（退避，覆盖异步执行延迟）：set 后按 0.6/1.0/1.5/2.0/2.5s 重读 `pmset`（至多 ~7.6s），命中即刷新选中；期间 UI 显示进度。始终未变 → 判 `bridgeMisconfigured`，引导 onboarding。
- `isBridgeAvailable`：`/usr/bin/shortcuts list` 含 `ChargeLimitConstants.shortcutName`（pmset/list 仍用 `ProcessRunner`）。
- 能力门禁：硬件 Apple Silicon（`sysctl hw.optional.arm64`，不用进程架构以防 Rosetta 误判）&& `ProcessInfo.isOperatingSystemAtLeast(26.4)` && `bridgeConfigured`。最终正确性以回读为准。

### 13.7 自动化授权（TCC）——实测非阻塞
- spike 实测：经 `NSWorkspace.open` 触发 URL scheme 运行指令**未触发自动化授权弹窗、未阻塞、未抢前台**（前台仍为调用方）。比 `Process` 调 `shortcuts run` 更省心。
- 仍保留 `NSAppleEventsUsageDescription`（Info.plist）作为兜底说明。
- 若个别环境 URL 打开失败（`open` 返回 false）→ `ShortcutBridge.set` 抛错，回读也不会命中 → 走 onboarding/深链降级。

### 13.8 降级与兜底（含权限态）
- `canRead==false`（`.unsupported`）：整张卡片隐藏，避免空壳。
- `canRead==true` 但 `canSetInApp==false`：显示当前上限（只读）+ 分级深链按钮。
- `bridgeConfigured==false`：显示当前上限 + onboarding 引导 + 深链。
- automation 被拒：显示当前上限 + "授予自动化权限"引导（区别于 onboarding）+ 深链。
- 深链（分级）：`NSWorkspace.shared.open` 试 `x-apple.systempreferences:com.apple.Battery-Settings.extension`，返回 false 再退化为打开"系统设置" App 本体；确切锚点页为 §13.9 验证项。

### 13.9 编码前 spike — 结论（本机 macOS 26.4 / M5 实测）
1. **动态入参**：`shortcuts run --input-path`（文件）/stdin 对任意指令均失败（"无法处理快捷指令的输入"）。→ 弃用 CLI 传值。
2. **URL scheme**：`open "shortcuts://run-shortcut?name=…&input=text&text=90"` 成功把值喂入，`pmset chargeSocLimitSoc` 由 95→90。→ **采用**。
3. **前台/TCC**：URL scheme 运行后前台仍为调用方（Terminal），无自动化授权弹窗、无阻塞。
4. **回读延迟**：~数秒内 pmset 反映新值；退避窗口取至 ~7.6s。
5. **端到端**：经真实 `ChargeLimitController.set(85)` → URL scheme → 回读，`state=limited(85)`、`pmset=85`，无错误。
6. **深链锚点**：`x-apple.systempreferences:com.apple.Battery-Settings.extension` 为首选，失败回退打开系统设置本体（保留为运行时确认项）。

### 13.10 进程执行安全（ProcessRunner）
- 固定绝对路径（`/usr/bin/pmset`、`/usr/bin/shortcuts`），不经 shell、不拼接用户输入；百分比仅取自 `ChargeLimitConstants.steps`，杜绝注入。
- 后台队列执行；**异步排空 stdout/stderr**（防子进程写满管道缓冲死锁）；超时强制 `terminate`（必要时 `SIGKILL`）；pmset 2s、shortcuts 10–15s 两档超时。
- 主线程仅接收结果与错误分类（权限/超时/退出码/回读未变）。

### 13.11 本期范围裁剪（评审采纳）
- **去掉**"已达上限，暂停充电"副文案：`NotChargingReason` 当前不在 `PowerSample`/`IORegistryReader` 中，引入需新增字段+解析+语义确认，超出本期；横幅已表达 acPaused 状态。列为后续可选项。
- **关上限（回到无限制）**：本期段控仅 80/85/90/95/100。能否从 app 内"清除上限"取决于该动作语义（选 100 = 限 100 还是清除？）——列为 §13.9 验证项；若动作不支持清除，则"无限制"为只读显示 + 深链清除。
