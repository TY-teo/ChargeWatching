# ChargeWatch — UI / UX 设计文档

## 0. 视觉硬性禁令（编码前必须自检）

- **禁止 emoji 字符**：所有图标必须来自 SF Symbols。源码中不得出现 Unicode 范围 U+2600-U+27BF、U+1F300-U+1FAFF
- **禁止紫/粉渐变**：拒绝典型 AI 模板观感
- **禁止默认系统字体直出**：必须显式声明 SF Pro Display / SF Pro Text + 字号 + 字重 token
- **禁止硬编码颜色**：颜色必须来自 `DesignTokens/Colors.swift`，不得在视图代码里写 `Color(hex: "#xxxxxx")`

## 1. 设计哲学

> "**少即是多**。Mac 用户多年没有合适的菜单栏功率工具，是因为别人都在加功能。ChargeWatch 只做一件事：让你 0.5 秒内知道现在多少瓦。"

- 信息密度高但层级清晰
- 像系统自带工具一样原生
- 不抢注意力，不弹通知（除非用户主动开）

## 2. 设计 Token

### 2.1 色彩（语义化，深浅模式自适配）

```swift
enum AppColor {
    static let chargingActive = Color("ChargingActive")    // 浅: #1F9E4A 深: #34D363
    static let chargingPaused = Color("ChargingPaused")    // 浅: #6B7280 深: #9CA3AF
    static let discharging    = Color("Discharging")       // 浅: #C2410C 深: #FB923C
    static let warningHigh    = Color("WarningHigh")       // 浅: #B91C1C 深: #F87171
    static let bgPrimary      = Color("BgPrimary")
    static let bgSecondary    = Color("BgSecondary")
    static let textPrimary    = Color("TextPrimary")
    static let textSecondary  = Color("TextSecondary")
    static let divider        = Color("Divider")
}
```

颜色资源放入 Assets.xcassets，每个色提供 Any/Dark 两套。

### 2.2 字体

```swift
enum AppFont {
    static let menuBarNumber  = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
    static let panelHeadline  = Font.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
    static let panelLabel     = Font.system(size: 11, weight: .medium).uppercaseSmallCaps()
    static let panelBody      = Font.system(size: 13, weight: .regular)
    static let panelCaption   = Font.system(size: 11, weight: .regular)
    static let chartAxis      = Font.system(size: 10, weight: .medium)
}
```

### 2.3 间距 / 圆角

```swift
enum AppSpacing { static let xs = 4.0; static let s = 8.0; static let m = 12.0; static let l = 16.0; static let xl = 24.0 }
enum AppRadius  { static let s = 6.0; static let m = 10.0; static let l = 14.0 }
```

### 2.4 主题系统（v0.2 新增）

**主题枚举**：

| 主题 | 菜单栏面板背景 | 历史/设置窗口背景 |
|---|---|---|
| `classic`（默认） | `AppColor.bgPrimary`（系统不透明） | `AppColor.bgPrimary`（系统不透明） |
| `vibrancy` | `NSVisualEffectView(.popover, .behindWindow)` 磨砂 | `NSVisualEffectView(.sidebar, .behindWindow)` + `Color.accentColor.opacity(0.12)` tint |

**关键约束**：
- 玻璃主题下窗口必须 `window.isOpaque = false` + `window.backgroundColor = .clear` + `titlebarAppearsTransparent = true`
- 不得硬编码 hex 蓝色；蓝色 tint 用 `Color.accentColor.opacity(0.12)` 叠加在 sidebar 材质上
- 玻璃主题下 sparkline / 历史折线必须与磨砂背景保持对比度（线宽 +0.5pt，添加 1pt 描边）
- 主题切换实时生效，无需重启 app（用 `@AppStorage("appTheme")` 驱动）
- 默认值是 `classic`，与 v0.1.0 视觉完全一致（升级用户不会感到突变）

**持久化**：UserDefaults key = `appTheme`，值 = `"classic"` / `"vibrancy"`

### 2.5 图标库锁定

**唯一来源：SF Symbols 5（系统自带）**

| 用途 | 符号 |
|---|---|
| 充电中 | `bolt.fill` |
| 已接电源未充电 | `bolt.slash.fill` |
| 放电中 | `battery.50percent`（按电量动态切换 0/25/50/75/100） |
| 适配器 | `powerplug.fill` |
| 系统负载 | `cpu.fill` |
| 历史 | `chart.xyaxis.line` |
| 设置 | `gearshape.fill` |
| 导出 | `square.and.arrow.up` |
| 退出 | `power` |
| 信息 | `info.circle` |
| 时间范围 | `calendar` |

## 3. 页面层级

```
ChargeWatch
├── 菜单栏图标 (MenuBarExtra label)
│   └── 下拉详情面板 (MenuBarExtra content, 360pt 宽)
│       ├── [查看完整历史] → 独立窗口
│       ├── [设置]         → 独立窗口
│       └── [退出]         → app terminate
└── 独立窗口
    ├── 历史窗口 (720×480)
    └── 设置窗口 (480×320)
```

## 4. 菜单栏图标设计

宽度自适应（让图标 + 数字紧凑显示）：

```
状态           显示
充电中 67W    [⚡SF] 67W
充电暂停       [⚡⃠SF] AC
放电中 54%    [▮▮▮▯SF] 54%
无电池 21W    [🔌SF] 21W
```

布局规则：
- SF Symbol 12pt + 4pt 间距 + 数字（monospaced digit 防止抖动）
- 字号 12pt semibold rounded
- 颜色跟随系统状态栏（白/黑），不强制着色
- 充电中数字带 0.5pt 阴影增强可读性

## 5. 下拉详情面板（核心 UI）

```
┌────────────────────────────────────────────┐
│ ▌充电中 · 67.2 W                           │ ← 状态横幅 48pt，左侧色条 4pt
│                                            │
│ ┌─────────────┬─────────────┐              │
│ │ 充入电池    │ 适配器输入  │              │
│ │   67.2 W    │   72.4 W    │              │ ← 关键数字 2×2，每格 110×72
│ ├─────────────┼─────────────┤              │
│ │ 系统负载    │ 电池 SoC    │              │
│ │   18.5 W    │    54%      │              │
│ └─────────────┴─────────────┘              │
│                                            │
│ ▸ 100W PD · 20V/3.6A 协商                 │ ← 适配器卡片 32pt
│                                            │
│ 最近 60 秒                                 │ ← label
│ ╲╱╲___╱╲╱╲╲╲╲___                          │ ← sparkline 60pt
│                                            │
│ ────────────────────────────               │
│  📊 完整历史   ⤴ 导出   ⚙ 设置   ⏻ 退出   │ ← 4 个 textbutton（图标全为 SF Symbol）
└────────────────────────────────────────────┘
```

**注**：上图中 `📊` `⤴` `⚙` `⏻` 仅为 ASCII 占位示意，**实际渲染必须替换为对应 SF Symbol**。

### 5.1 状态横幅
- 高 48pt
- 左侧 4pt 色条（充电=绿、暂停=灰、放电=橙）
- 文字：状态名 + `·` + 主数字（瓦数或 SoC）
- 主数字字号 18pt semibold rounded monospaced

### 5.2 关键数字 2×2
- 每格 110×72pt，圆角 10pt
- 背景 `bgSecondary`
- 上方 caption 11pt uppercaseSmallCaps `textSecondary`
- 下方数字 28pt semibold rounded monospaced `textPrimary`
- 数字带单位上标（`W` 14pt）

### 5.3 Sparkline
- 用 Swift Charts `LineMark`
- 60 点数据，最近 60 秒
- 仅画线，无 x/y 轴刻度
- 线色：充电中=`chargingActive`，否则 `discharging`
- 高度 60pt，左右内边距 8pt

### 5.4 操作行
- 水平 4 等分
- 每按钮：SF Symbol 14pt + label 11pt（图标上、文字下）
- hover 时背景 `bgSecondary`，圆角 6pt

## 6. 历史窗口

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ChargeWatch · 历史                                            [─][▢][×]│
├──────────────────────────────────────────────────────────────────────────┤
│  [今天] [本周] [本月] [自定义 ▾]                          [⤴ 导出CSV]    │ ← Toolbar
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   100W ┤                                                                 │
│        │      ╱╲      ╱╲╲                                                │
│    75W ┤    ╱╱  ╲    ╱   ╲                                               │
│        │  ╱╱     ╲╲╱╱     ╲╲╲                                            │
│    50W ┤╱                    ╲                                           │
│        │                      ╲___                                       │
│    25W ┤                          ╲                                      │
│        │_______________________________________________________________  │
│         09:00   12:00   15:00   18:00   21:00                            │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  累计充入     平均功率     峰值功率     充电时长                          │
│   1.42 kWh    52.3 W       89.7 W      2h 14min                          │
└──────────────────────────────────────────────────────────────────────────┘
```

- 顶部 segmented control 切换范围
- 主图：Swift Charts `LineMark` + 可选 SoC 副坐标（虚线）
- hover/tap 显示十字光标 + 数值 tooltip
- 底部 4 个统计卡（与下拉面板一致样式）

## 7. 设置窗口

```
┌─────────────────────────────────────────────────┐
│  设置                                  [×]     │
├─────────────────────────────────────────────────┤
│                                                 │
│  通用                                           │
│    [✓] 开机自动启动                            │
│    [ ] 充电完成时通知 (100%)                   │
│    [ ] 充电达到阈值时通知   [80] %             │
│                                                 │
│  数据                                           │
│    数据库位置:                                  │
│    ~/Library/Application Support/ChargeWatch    │
│    [打开] [清空所有数据]                        │
│                                                 │
│  关于                                           │
│    ChargeWatch v0.1.0                          │
│    [GitHub] [反馈]                             │
└─────────────────────────────────────────────────┘
```

## 8. 交互状态

| 状态 | 视觉 |
|---|---|
| 加载中（首次启动 < 1s） | 菜单栏显示 `--` |
| 数据库错误 | 菜单栏显示 SF Symbol `exclamationmark.triangle` + 详情面板顶部红色横幅 |
| 无电池机型 | 详情面板隐藏 SoC 格，"充入电池"格替换为"-" |
| 桌面 Mac 永远在 AC | 横幅显示"已接电源"，无充电曲线 |

## 9. 动效

- 菜单栏数字变化：无动画（避免抖动）
- 详情面板出现：系统默认 0.2s 渐入
- Sparkline 新数据：左移 + 右侧 fade-in
- 状态横幅色条切换：0.3s 颜色过渡

## 10. 无障碍

- 所有图标按钮提供 `accessibilityLabel`
- 颜色对比度满足 WCAG AA（前景文字对背景 ≥ 4.5:1）
- 键盘可达：菜单栏面板 Tab 顺序：4 数字格 → 操作行
- VoiceOver 朗读："当前充电功率 67.2 瓦"

## 11. 自检清单（每次写 UI 代码前过一遍）

- [ ] 图标全部来自 SF Symbols（grep 源码无 `🔋`、`⚡`、`🔌` 等字符）
- [ ] 颜色全部来自 `AppColor.*`（grep 源码无 `Color(hex:` 也无 `Color(red:`）
- [ ] 字号字重全部来自 `AppFont.*`
- [ ] 间距全部来自 `AppSpacing.*`
- [ ] 深色 / 浅色模式都在 SwiftUI Preview 里验证过
- [ ] 数字使用 `monospacedDigit()` 防止抖动
- [ ] 主操作按钮 `accessibilityLabel` 已写

## 12. v0.3 重设计（磨砂协调 + 数据真实性）

> 触发：用户反馈现有 UI 在磨砂面板下不协调，且充电瞬间「充入电池」瓦数不实时。设计北极星 = macOS 原生控制中心（电池 / Wi-Fi 弹窗）：磨砂底 + 半透明分组瓦片 + 细分隔线 + 无左侧色条。参考图见 `reference/`。

### 12.1 卡片材质系统（替换不透明 controlBackgroundColor）

新增主题感知卡片表面 `cardSurface(theme:)`，所有指标卡 / 适配器行 / 设置分组统一使用：

| 主题 | 卡片填充 | 描边（hairline） |
|---|---|---|
| `classic` | `AppColor.bgSecondary`（系统不透明，保持 v0.2 观感） | `Color.primary.opacity(0.05)` 1px |
| `vibrancy` | `.ultraThinMaterial`（半透明磨砂瓦片，透出面板底纹） | `Color.primary.opacity(0.08)` 1px |

- 圆角沿用 `AppRadius.m`（10pt），适配器行 `AppRadius.s`。
- 磨砂态下卡片不再是「白底块」，而是与面板同质的磨砂瓦片，达到原生控制中心协调感。
- 硬约束：禁止再在视图层直接 `.background(AppColor.bgSecondary)` 充当卡片；一律走 `cardSurface(theme:)`。

### 12.2 状态横幅重设计（去掉左侧竖色条）

- **移除** `Rectangle().frame(width: 4, height: 36)` 竖色条。
- 改为「状态图标瓦片 + 双行文字」原生布局：
  - 左：28×28 圆角瓦片（`AppRadius.s`），填充 `状态色.opacity(0.16)`，内置 SF Symbol（充电=`bolt.fill`、暂停=`bolt.slash.fill`、放电=动态电池符号、市电=`powerplug.fill`），图标着状态色。
  - 右：上行状态名（`panelCaption`，`textSecondary`）；下行主数字（`panelSubheadline` 18pt，`textPrimary`）。
- 颜色仍来自 `AppColor` 语义色，不新增硬编码。

### 12.3 Sparkline 数值标注（最近 60 秒）

- 取消 `.chartYAxis(.hidden)`：
  - 启用 `.chartYAxis` `AxisMarks(desiredCount: 3)`，`chartAxis` 字号、`textSecondary`，hairline 网格线（`divider`）。
- 标题行右侧追加当前值 `xx.x W`（`panelLabel`/`textSecondary`），随最新采样实时更新（「曲线旁数值标注」）。
- 曲线末端加 `PointMark` 端点圆点（状态色），锚定当前读数位置。
- X 轴仍隐藏，保持紧凑。

### 12.4 设置窗玻璃外观重设计

- `windowBackground(.vibrancy)`：**去掉** `Color.accentColor.opacity(0.12)` 的厚重蓝色 tint，材质由 `.sidebar` 改为更干净的 `.underWindowBackground`（无蓝色水洗）。
- `ThemeWindowConfigurator.prepareForThemeable` 补齐玻璃必需项：`titlebarAppearsTransparent = true` + `titleVisibility = .hidden`（仅 vibrancy 需要透明标题栏，glass 才不脏）。
- 各设置分组（外观 / 通用 / 数据）用 `cardSurface(theme:)` 包裹，形成原生分组卡片层级。

### 12.5 数据真实性修复（充入电池实时瓦数）

非 UI，但属本次同源修复，记录于此以便回归：

- 根因 1：`batteryWatts` 用顶层 `Amperage`（多秒滚动平均），刚插充电器时严重滞后，而 sparkline 的系统负载分支用瞬时 `SystemLoad`，造成「图在跳、瓦数不动」。
- 根因 2：`readInt` 用 `NSNumber.intValue`(Int32) 解码接近 2⁶⁴ 的遥测无符号大值会错位，导致系统负载显示负值。
- 修复：电池功率幅度优先取瞬时 `PowerTelemetryData.BatteryPower` → 回退 `Voltage×InstantAmperage` → 回退 `Voltage×Amperage`；方向由 `isCharging` 决定（充电为正）。遥测字段统一 `readSignedInt`(int64) 解码 + 取绝对值幅度。

### 12.6 v0.3 预览反馈修订

针对第一轮预览反馈的二次调整：

- **窗口标题栏**：撤销 `titlebarAppearsTransparent`（曾导致标题栏整条透明、窗口无法拖动）。改为保留系统标题栏（可见、可拖拽），玻璃感仅由内容区材质提供。
- **玻璃亮度**：玻璃主题统一强制浅色外观——`VisualEffectView.forceAqua = true`（材质走浅色变体，更亮）+ 内容 `environment(\.colorScheme, .light)`。解决「切到玻璃后整体偏暗」。
- **配色回归经典**：强制浅色后，`chargingActive` / `discharging` / sparkline 颜色不再走暗模式霓虹变体，回到经典浅色配色（绿 `#1F9E4A` / 橙 `#C2410C`），与原生参考一致。
- **状态图标**：移除状态横幅图标的 `状态色.opacity(0.16)` 圆角色块底衬（放电态被感知为电池周围「阴影」）。改为纯 SF Symbol（放电=单个电池符号）着状态色，无背景块。
- **卡片亮度**：玻璃态卡片由 `.ultraThinMaterial` 调整为 `Color.white.opacity(0.5)` 叠 `.regularMaterial` + `black.opacity(0.06)` hairline，瓦片更亮更清晰。
- **文案**：玻璃主题描述去掉「蓝色 tint」表述。

## 13. 充电上限调节 UI（v0.4 新增）

> 依据 PRD §9 与架构 §13。遵循 v0.3 设计系统：`cardSurface(theme:)` 卡片、`AppColor`/`AppFont`/`AppSpacing` 令牌、SF Symbols、无 emoji、`monospacedDigit()`。北极星是系统设置充电上限那一格（`reference/README.png`：80/85/90/95/100 离散档位）。
>
> **同步表述（与 PRD §9.2 一致）**：app→系统 实时；系统→app 仅在面板打开时回读刷新。卡片不暗示"任何时刻实时同步"。

### 13.1 面板内位置与弹窗尺寸
菜单面板新增"充电上限"卡片，置于 **sparkline 之后、`Divider()` + 操作行之前**：
```
banner → 2×2 指标 → 适配器行 → 最近60秒 → [充电上限卡片] → Divider → 操作行
```
卡片用 `cardSurface(theme:)`。**弹窗尺寸（评审 must-fix）**：现有 `StatusBarController` 把 `popover.contentSize` 硬编码为 360×380，新增卡片会被裁切。改为**内容自适应高度**（`NSHostingController` 让内容决定尺寸 / 取 fitting size），不再用魔法数；若保留固定高度，须按**最高态**预算（状态 B：标题 + caption + 两个按钮）。卡片自身高度随 A/B/C 变化，面板整体随之伸缩。

### 13.2 卡片状态（A/B/C + 权限被拒）
标题行统一布局：`[AppIcon.chargeLimit] 充电上限`（左）+ **固定宽度的尾部状态区**（右）。尾部区预留固定宽度，在 `当前值 ↔ ProgressView ↔ 警告图标` 之间切换时**不引起重排**。

**状态 A — 支持且已配置（可在 app 内调节）**
```
┌────────────────────────────────────────────┐
│ [icon] 充电上限                      80%   │ ← label(左) / 尾部区:当前值(textPrimary,等宽)
│ ┌────┬────┬────┬────┬────┐                  │
│ │ 80 │ 85 │ 90 │ 95 │100 │                  │ ← 5 档 segmented，选中=当前上限
│ └────┴────┴────┴────┴────┘                  │
└────────────────────────────────────────────┘
```
- 选档 → `ChargeLimitController.set(percent:)`；设置中段控 `disabled` + 尾部区显示 `ProgressView`（小号）；退避回读成功后刷新选中。
- 失败：尾部区显示 `AppIcon.warning`（`exclamationmark.triangle`）+ 卡片底部 caption 错误说明 + 深链按钮。
- 读到的当前值不在 5 档内：显示真实值，段控不精确选中（高亮最近档，避免误导）。

**状态 B — 可读但未配置桥接指令**
```
│ [icon] 充电上限                      80%   │
│ 在 ChargeWatch 内调节需一次性设置          │ ← panelCaption / textSecondary
│ [一次性设置]            [在系统设置中调节] │ ← 主(开 onboarding) + 次(深链)
```

**状态 B′ — 已配置但"自动化"权限被拒（spike 揭示的真实子态）**
```
│ [icon] 充电上限                      80%   │
│ 需授予"自动化"权限才能在 app 内调节        │
│ [去授权]                [在系统设置中调节] │ ← "去授权"开系统设置>隐私与安全性>自动化引导
```

**状态 C — 不支持 app 内设置（旧系统 / Intel）**
```
│ [icon] 充电上限                      80%   │ ← 若 canRead；否则整卡隐藏
│ [在系统设置中调节]                          │ ← 仅分级深链
```
- `.unsupported` 且 read 失败 → 整张卡片隐藏，避免空壳。

### 13.3 当前值文案与配色
- `.limited(80)`→"80%"；`.unlimited`→"未设上限"；`.unknown`→"—"。
- 数字 `AppFont.panelSubheadline` + `monospacedDigit()`；label `AppFont.panelLabel`。
- **颜色取自 token**：当前值用 `AppColor.textPrimary`（与 2×2 指标数值一致），**不写"accent"/不硬编码**（设计系统无 accent 文本 token）。段控选中色用控件自带 tint（系统 accent），属控件内建，符合 §0 颜色纪律。

### 13.4 Onboarding 引导（ChargeLimitOnboardingView）
- **呈现方式（评审 must-fix）**：app 是 `.accessory` 无主窗场景，且 popover 为 `.transient`（点外即关、无法承载 sheet）。故 onboarding 必须是 **AppDelegate 管理的独立 `NSWindow`**，完全照 `showSettings()` 模式（titled+closable、center、`isReleasedWhenClosed=false`、`ThemeWindowConfigurator.prepareForThemeable`、`windowBackground(theme:)`）；新增 `onOpenOnboarding` 闭包，与 `onOpenSettings` 同样从 AppDelegate 经 StatusBarController 串到 `ChargeLimitSection`。打开引导前先关 popover。
- 标题：在 ChargeWatch 内调节充电上限。
- 说明：macOS 无程序化创建快捷指令的 API，需一次性创建一个包裹系统「设置电池充电上限」动作的快捷指令（写入的就是系统那同一上限）。
- 步骤（有序，纯文本 + 文字编号，**禁用 emoji**）：
  1. 打开「快捷指令」App
  2. 新建快捷指令，添加动作「设置电池充电上限 / Set Battery Charge Limit」
  3. 关闭"仅今天"；按 spike 结论：单指令则让"上限"取自快捷指令输入，或每档建一个固定指令
  4. 命名为 `ChargeLimitConstants.shortcutName`（文案直接展示该字面量，供用户精确复制）
- 按钮：`打开快捷指令`、`我已完成（重新检测）`（重查 `isBridgeAvailable`）、`改用系统设置`（分级深链）。
- 视觉：复用 SettingsWindow 的分组卡片风格（其 `section(title:)` 为私有，需抽取为共享 helper 或在本视图复述同一 cardSurface 分组模式）。

### 13.5 图标与令牌
- 卡片图标：在 `DesignTokens.swift` 的 `AppIcon` 枚举**集中新增 `AppIcon.chargeLimit`**（构建期验证有效的单一 SF Symbol，推荐 `minus.plus.batteryblock`；勿在视图内联 systemName）。**不得用 emoji**。
- 段控 `.pickerStyle(.segmented)`（与设置页主题选择器一致）；5 档标签在 360 − `AppSpacing.l`×2 ≈ 328pt 内可容纳，"100" + 选中态最紧，标签用 `monospacedDigit()`。
- 间距/圆角沿用 `AppSpacing`/`AppRadius`。

### 13.6 交互与反馈
- 设置中：段控禁用 + 尾部区 `ProgressView`；成功：退避回读刷新选中（无动画，防跳变）；慢-但-成功 不误报失败。
- 失败分类反馈：权限被拒 → 状态 B′ 引导；退出码 0 但回读未变 → 判桥接配置错误，引导 onboarding；超时/其他 → caption 错误 + 深链。
- 系统侧改动：面板打开时（`popoverWillShow`）立即回读 + 打开期间 ≤15s 轮询刷新选中；关闭即停（不后台 spawn）。

### 13.7 本期裁剪
- **去掉**"已达上限，暂停充电"副文案：依赖代码中尚不存在的 `NotChargingReason`（`PowerSample`/`IORegistryReader` 未读取），且语义未确认。横幅已表达 acPaused。列为后续可选。

### 13.8 自检（沿用 §11 + 本节）
- [ ] 段控/当前值无 emoji，图标来自 `AppIcon.chargeLimit`（SF Symbols）
- [ ] 颜色全部 `AppColor.*`（当前值=textPrimary），卡片走 `cardSurface(theme:)`
- [ ] A/B/B′/C + 加载/进度/错误 在玻璃/经典、深/浅模式下均验证
- [ ] 尾部状态区固定宽度，值/进度/警告切换不重排
- [ ] 新卡片不被弹窗裁切（弹窗尺寸内容自适应）
- [ ] onboarding 为独立 NSWindow，开前先关 popover
