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
