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

### 2.4 图标库锁定

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
