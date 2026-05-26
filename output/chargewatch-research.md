# ChargeWatch — 调研报告

## 1. 同类产品扫描（2026）

| 工具 | 形态 | 实时充电功率 | 历史记录 | 价格 | 痛点 |
|---|---|---|---|---|---|
| coconutBattery | 独立窗口 | 不显示瓦数，只显示电压/电流原始值 | Pro 有趋势图 | 免费 / $12.99 | **无菜单栏常驻**，每次要主动打开 |
| AlDente Pro | 菜单栏 | Stats 模块显示，但作为附属 | 仅当前 | 免费 / €18 | 主打充电限制，瓦数不是核心 |
| iStat Menus | 菜单栏 | 有，但混在 CPU/网络一起 | 完整图表 | $11.99 | 收费、功能臃肿、UI 老 |
| Stats (open source) | 菜单栏 | 显示瓦数但 UI 粗糙 | 有限 | 免费 | 电池只是众多模块之一，专注度不够 |
| TurtleBar | 菜单栏 | 不显示瓦数，主打剩余时间 | 无 | $1.99 | 不是功率工具 |
| Juicy | 菜单栏 | 综合方案 | 有 | 付费订阅 | 订阅制 |

**差异化定位**：单一目的（充电功率监控）、原生轻量（< 10 MB）、开箱即用免费、记录可导出。

## 2. macOS 电源 API 选型

### 2.1 IOKit IOPSCopyPowerSourcesInfo（公开 API）
- 提供：`kIOPSIsChargingKey`、`kIOPSCurrentCapacityKey`、`kIOPSPowerAdapterWattsKey`（**适配器额定瓦数**，非实际功率）、`kIOPSTimeToFullChargeKey`
- 优点：完全公开 API，App Store 合规；支持 RunLoop 变化通知
- 缺点：不提供实时充电功率瓦数

### 2.2 IORegistry / AppleSmartBattery（半公开）
- 通过 `IOServiceMatching("AppleSmartBattery")` 读取
- 关键字段（已在 `ioreg -rn AppleSmartBattery` 验证）：
  - `Voltage` (mV)，例如 11560
  - `Amperage` (mA, signed)，正数 = 充入电池，负数 = 放电
  - `InstantAmperage` (mA)
  - `ChargerData.ChargingCurrent` (mA)、`ChargingVoltage` (mV)
  - `AdapterDetails.Watts`（适配器额定）、`AdapterVoltage`、`Current`（适配器协商最大值）
  - `PowerTelemetryData.SystemPowerIn` (mW)：**适配器实际输入到机器的功率**（这是最准的"插座功率"）
  - `PowerTelemetryData.SystemLoad` (mW)：系统当前总功耗
- 实时充电功率公式：
  - **电池侧充入功率** = `Voltage × Amperage / 1e6` (W)
  - **适配器实际输入功率** = `SystemPowerIn / 1000` (W)
  - **系统当前负载** = `SystemLoad / 1000` (W)
  - 当 `Amperage = 0` 且 `ExternalConnected = Yes` → 已接电源但暂停充电（如优化电池充电触发）
- 优点：免费拿到全部所需数据，无 entitlement 要求，本地使用无签名问题
- 缺点：私有 key，App Store 上架可能被拒（本工具仅个人本地使用，可接受）

### 2.3 powermetrics / SMC
- 需要 root 或私有 framework，**放弃**

## 3. 采样与变化通知
- 推荐主循环：每 **1 秒**轮询 IORegistry（开销极小，< 0.1% CPU）
- 充电状态变化（插拔、开始/停止）使用 `IOPSNotificationCreateRunLoopSource` 即时回调
- 不在 App 暂停时关闭采样：用 `NSBackgroundActivityScheduler` 维持后台采样

## 4. 数据存储方案

| 方案 | 优 | 劣 | 决策 |
|---|---|---|---|
| CSV append | 简单、易导出 | 查询慢、易损 | 仅用于导出 |
| SQLite (GRDB.swift) | 快、可索引、原子写 | 引入第三方 | **采用** |
| Core Data | 系统自带 | API 重、迁移痛 | 否 |
| JSON 日志 | 简单 | 体量大 | 否 |

**数据库表设计**：
```sql
CREATE TABLE samples (
  ts INTEGER PRIMARY KEY,         -- Unix 秒
  is_charging INTEGER NOT NULL,   -- 0/1
  external_connected INTEGER NOT NULL,
  battery_watts REAL NOT NULL,    -- 电池侧瓦数（正=充入）
  adapter_watts REAL,             -- 适配器实际输入瓦数
  system_load_watts REAL,         -- 系统当前总功耗
  voltage_mv INTEGER,
  amperage_ma INTEGER,
  soc_percent INTEGER,
  adapter_max_watts INTEGER       -- 适配器额定（用于背景色判断）
);
CREATE INDEX idx_samples_ts ON samples(ts);
```

按 1Hz 采样、每行约 80 bytes：一年 ≈ 2.5 GB（过大）→ **降采样策略**：
- 最近 24h：保留 1Hz
- 24h~7d：聚合为 10s 平均
- 7d~30d：聚合为 1min 平均
- > 30d：聚合为 5min 平均
- 30d 滚动后总大小 < 50 MB

## 5. 关键非功能需求
- 内存常驻 < 50 MB
- 空闲 CPU < 0.5%
- 菜单栏图标刷新 ≤ 1 Hz（避免视觉抖动）
- 开机自启动可选（用 `SMAppService` API，macOS 13+ 推荐）
- 深色 / 浅色模式自适配
- 锁屏 / 睡眠时暂停 UI 渲染但保留采样调度

## 6. 风险与对策

| 风险 | 对策 |
|---|---|
| AppleSmartBattery 字段在 macOS 未来版本变化 | 用 try/optional 解构，缺字段时 fallback 到 IOPS |
| 桌面型 Mac（无电池）启动崩溃 | 启动时检查 `AppleSmartBattery` 是否存在，无电池时显示占位 UI |
| Intel Mac 字段差异 | 仅在 Apple Silicon 上提供完整 telemetry，Intel 上降级显示 |
| 长时间运行 SQLite WAL 膨胀 | 每日 `PRAGMA wal_checkpoint(TRUNCATE)` |

## 7. 引用
- IOPSCopyPowerSourcesInfo: https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo
- IOKitUser IOPowerSources.h: https://github.com/opensource-apple/IOKitUser/blob/master/ps.subproj/IOPowerSources.h
- AlDente: https://apphousekitchen.com/aldente-overview/
- 2026 Mac 电池工具横评: https://www.turtlebar.app/guides/best-mac-battery-apps
- coconutBattery 评测: https://getjuicy.app/directory/mac-battery-apps/coconut-battery/
