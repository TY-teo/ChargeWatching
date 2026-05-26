# Tasks — ChargeWatch MVP

## S1 项目骨架 + 设计 token （前端基础）
- Package.swift（macOS 13+ executable target, swift-tools 5.9）
- DesignTokens: Colors / Typography / Spacing / Radius
- Info.plist 模板（LSUIElement=true）
- 验证：`swift build` 成功

## S2 核心数据模型 + IORegistry 读取（后端最小切片）
- PowerSample struct
- IORegistryReader: 读取 AppleSmartBattery，解析全字段
- CLI 自检：`swift run chargewatch --dump` 打印当前一次采样到 stdout
- 验证：和 `ioreg -rn AppleSmartBattery` 数据一致

## S3 菜单栏壳 + Mock 数据（前端优先 + 运行时验证）
- ChargeWatchApp @main + MenuBarExtra
- MenuBarLabel: SF Symbol + 数字 (mock 67W)
- MenuBarPanel: 状态横幅 + 2×2 数字 + sparkline 骨架 + 4 按钮
- 运行时验证：`swift run chargewatch` 菜单栏出现，下拉看到完整 UI
- **此时停下来截图给用户看一眼**（preview_confirm 门）

## S4 真实采样接入菜单栏
- PowerSampler: 1Hz Timer + IOPS notification
- 用 Combine `CurrentValueSubject<PowerSample?, Never>` 喂给 UI
- 验证：菜单栏数字随实际充电状态变化

## S5 SQLite 持久化
- Database (sqlite3 raw wrapper)
- Migrations: 4 张表
- SampleRepository: insert / query / aggregate / purge
- 验证：跑 10 秒后 `sqlite3 data.sqlite "SELECT count(*) FROM samples_raw;"` 返回 ~10

## S6 历史窗口
- HistoryWindow + RangePicker + ChargeChart (Swift Charts)
- 统计卡片
- 验证：跑 1 分钟后历史窗口能渲染当日折线

## S7 CSV 导出
- CSVExporter
- "导出" 按钮触发 NSSavePanel
- 验证：导出文件 Numbers 可打开

## S8 降采样 + 数据清理
- Downsampler actor, 60s tick
- purgeOlderThan 任务
- 验证：模拟时钟前进，10s/1min/5min 表数据正确

## S9 设置 + 开机自启 + 打包
- SettingsWindow
- SMAppService 注册
- 通知（充满 100%）可选
- 构建脚本 `scripts/build-app.sh`：生成 ChargeWatch.app + ad-hoc 签名
- 验证：开机自启切换、打包后双击 .app 启动正常
