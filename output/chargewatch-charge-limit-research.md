# ChargeWatch — 充电上限功能 可行性研究

> 阶段：research（evolve）。目标：在 ChargeWatch 内调节电池充电上限（80%–100%，5% 步长），并与系统设置的充电上限同步。
> 本机基线：macOS 26.4（build 25E246）、Apple M5、MacBook Air (Mac17,4)、arm64。
> 方法：宿主联网研究（4 源并行）+ 对抗式综合 + 本机只读实测验证。下文结论以**本机实测**为准，联网研究中被实测证伪的说法已剔除。

## 1. 核心结论（TL;DR）

| 能力 | 可行性 | 路径 | 是否与系统滑块同步 | 是否需 root |
|---|---|---|---|---|
| **读取当前上限** | 已确认可行 | `pmset -g battlimit` 解析 `chargeSocLimitSoc` | 是（权威源） | 否 |
| **设置上限** | 可行（自动化桥接） | App Intents 动作 `SetBatteryChargeLimitAction`（macOS 26.4）经用户快捷指令 + `/usr/bin/shortcuts run` | 是（写入同一 powerd 值） | 否 |
| **打开系统控制** | 已确认可行 | 深链 `x-apple.systempreferences:com.apple.Battery-Settings.extension` | 系统原生 | 否 |
| ~~SMC 软限位~~ | 不推荐 | CHWA/CH0B/CH0C/CHTE 写入 | **否（并行冲突）** | 是 + 特权助手 |

**没有**公开 Swift/IOKit SDK 可在进程内直接 set 上限；但 macOS 26.4 新增的 App Intents 动作让"真同步设置"在**无 root**下可达，代价是一次性快捷指令配置 + `shortcuts run` 的可靠性需验证。

## 2. 已在本机验证的事实

### 2.1 读取（权威、无 root、实时同步）
`pmset -g battlimit` 在用户把系统上限设为 80% 后返回：
```
Battery level limits:
( { chargeSocLimitReason = manualChargeLimit; chargeSocLimitSoc = 80; ... }, { ... chargeSocLimitSoc = 80; } )
```
- 研究初期（未设上限时）该命令返回 `No battery level limits set` → 证明它**实时反映**系统滑块状态。
- `manualChargeLimit` 表示用户手动设的上限；`chargeSocLimitSoc` 即百分比。
- 无需 root 即可读。
- 备用读源：`/Library/Preferences/com.apple.powerd.charging.plist`（root:wheel，644 全局可读，但为 NSKeyedArchiver 二进制，解析更脆）。优先用 `pmset -g battlimit`。

### 2.2 设置（App Intents 动作，已确认存在于本机）
`/System/Library/PrivateFrameworks/ActionKit.framework/.../extract.actionsdata` 中确认：
- `ActionKit.SetBatteryChargeLimitAction`，`introducedVersion: 26.4`（macOS/iOS/watchOS）。
- `openAppWhenRun: false`、`authenticationPolicy: 0`、`isDiscoverable: true`。
- 参数：
  - `limit`：`ChargeLimit` 实体，`dynamicOptionsSupport: 1`（动态选项 = 80/85/90/95/100），描述 "The battery charge limit percentage to set."
  - `setUntilTomorrow`：Bool，"启用后第二天恢复为之前的值"（镜像系统"仅今天"行为）。
- 该动作写入的是 **powerd 管理的同一上限值**（与滑块同源）→ 真同步。
- 调用链：`/usr/bin/shortcuts run "<用户创建的快捷指令>" [--input-path <文件>]`（CLI 已确认存在）。

### 2.3 不是设定值的"坑"
- `AppleSmartBattery.DailyMaxSoc`：实测在**未设任何上限**时仍 = 80 → 是电量计遥测，**不是**用户上限。不得用作设定值来源。
- `NotChargingReason` / `ChargerInhibitReason`：实测当前 = 0（68% 充向 80% 上限途中）。是充电状态诊断位，可作辅助显示，非设定值。

## 3. 被否决的方案：SMC 软限位（AlDente / Battery-Toolkit / batt 类）

- 原理：root 特权助手轮询 SoC，写 Apple Silicon 充电抑制键（CHTE/CH0B/CH0C）在阈值附近开关充电——是**独立的第二套限位器**。
- 致命问题（与用户目标直接冲突）：
  - **不同步**：与系统原生上限并行运行，会冲突；这些工具明确要求用户**关闭**系统原生功能。
  - 需 root + 特权助手（SMAppService/SMJobBless），是对现有只读 app 的重架构；**不可上 Mac App Store**。
  - 真正的原生寄存器 `CHWA` 自 macOS 15 起被 entitlement 封锁。
  - `batt` 维护者自述"macOS 26.4+ 不需要 batt"——在本机 OS 上属倒退方案。
- 结论：**放弃**。仅在需要 <80% 或支持老系统时才有意义，均不符合本需求。

## 4. 推荐架构（无 root，真同步，渐进降级）

分层，三段式，互相兜底：

1. **READ（始终可用）**：后台周期性 `pmset -g battlimit` 解析当前上限，菜单面板实时显示（"充电上限 80%" / "未设上限"）。这是单一可信源，与系统滑块一致。
2. **SET（在 app 内调节，真同步）**：80/85/90/95/100 控件 → 调用 `SetBatteryChargeLimitAction`（经用户一次性创建的快捷指令 + `shortcuts run`）。
3. **降级/兜底**：若快捷指令未配置或 `shortcuts run` 不可用 → 显示一次性引导 + 深链直达系统设置电池页，用户手动调。读显示始终有效。

### 编码前 spike 结论（本机 macOS 26.4 / M5 实测，已定型）
- [x] `shortcuts run --input-path`/stdin **不可用**——对任意指令均报"无法处理快捷指令的输入"。弃用 CLI 传值。
- [x] **Shortcuts URL scheme 可用**：`open "shortcuts://run-shortcut?name=…&input=text&text=90"` 成功，`pmset` 由 95→90。**单条用户指令即可，无需 5 条/剪贴板/root。**
- [x] URL scheme 运行后**前台仍为调用方、无自动化授权弹窗、无阻塞**。
- [x] 回读延迟数秒内；退避窗口取至 ~7.6s。端到端 `ChargeLimitController.set(85)` → `state=limited(85)`、`pmset=85`、无错误。
- 结论：SET = `NSWorkspace.open` URL scheme（见架构 §13.6）。桥接指令结构 = `获取数字(快捷指令输入) → 设置充电上限`。

## 5. 对用户目标的诚实评估

- "在工具里直接调节" + "与系统同步"：**可达**，经 App Intents 桥接（无 root，写同一系统值）。
- 唯一代价：**一次性**让用户在"快捷指令"app 里建一个包裹该动作的指令（无程序化创建指令的 API）。之后 app 内调节即生效。
- 若用户不接受该一次性配置，则退化为"读显示 + 一键跳系统设置"（仍比手动找设置快）。

## 6. 引用（联网研究）
- Apple App Intents / Shortcuts（`SetBatteryChargeLimitAction`，macOS 26.4 元数据，本机确认）。
- `pmset` battlimit 行为（本机实测）。
- 开源对照：mhaeuser/Battery-Toolkit、AppHouseKitchen/AlDente、charlie0129/batt（SMC 软限位，确认为并行非同步方案）。
- macOS Sequoia+ 充电上限滑块 80–100%/5%（用户截图 `reference/README.png` 确认 UI 与档位）。
