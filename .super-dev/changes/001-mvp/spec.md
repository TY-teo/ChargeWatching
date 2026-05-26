# Spec — ChargeWatch MVP (001)

## 范围
实现 PRD 中 P0 + P1 全部能力。架构、UI 严格遵循 architecture.md 与 uiux.md。

## 关键决策（在架构基础上的细化）
1. **依赖最小化**：放弃 GRDB.swift，改用系统自带 `import SQLite3` + 100 行自研薄封装。理由：schema 极简、无 `swift build` 时的网络依赖、单文件可读。
2. **App 形态**：SPM `.executableTarget` + 启动时 `NSApp.setActivationPolicy(.accessory)`。这样 `swift run` 即可作为菜单栏 app 运行，无需 Xcode 工程。最终用脚本生成 `.app` bundle 完成 ad-hoc 签名。
3. **菜单栏 API**：SwiftUI `MenuBarExtra(.window)` 风格，可承载完整下拉面板。
4. **历史/设置窗口**：用 `Window`/`WindowGroup` + 程序化 `openWindow` 召唤。
5. **采样调度**：`DispatchSourceTimer` 1Hz + IOPS 通知回调即时刷新。
6. **降采样**：单线程后台 actor，每 60s 触发一次 roll-up。

## 工作分解（tasks 见 tasks.md）
P0-S1 ~ P1-S9 共 9 个里程碑，详见 tasks.md。

## 验收（与 PRD §8 一致）
- 菜单栏图标 + 数字稳定显示
- 详情面板 4 个数字 + sparkline
- 1Hz 写入，重启不丢
- 历史窗口三档时间范围
- CSV 导出
- 开机自启可开关
- 全源码 0 emoji
- Apple Silicon 实机连续 1h 不崩
