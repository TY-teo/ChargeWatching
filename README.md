# ChargeWatch

macOS 菜单栏小工具：实时查看 Mac 充电功率，并完整记录历史。

- 菜单栏图标 + 实时瓦数（SF Symbols，无 emoji）
- 下拉面板：充入电池 / 适配器输入 / 系统负载 / 电池电量 + 60 秒 sparkline
- 历史窗口：今天 / 本周 / 本月，折线图 + 累计 / 平均 / 峰值 / 时长统计
- 一键导出 CSV
- 1Hz 采样写入 SQLite，自动降采样（24h 1Hz → 7d 10s → 30d 1min → 5min）
- 开机自启可选（SMAppService）

## 系统要求

- macOS 13.0+
- Apple Silicon 推荐（Intel 降级显示）
- Xcode 15+ 或 Swift 5.9+ 工具链

## 首次构建

```bash
# 1. 首次需同意 Xcode license
sudo xcodebuild -license accept

# 2. 命令行直接运行（开发模式）
swift run chargewatch

# 3. 打印一次当前采样（调试用）
swift run chargewatch -- --dump

# 4. 打包成 .app 并 ad-hoc 签名
./scripts/build-app.sh
open build/ChargeWatch.app
```

## 数据存储位置

`~/Library/Application Support/ChargeWatch/data.sqlite`

## 技术栈

- Swift 5.9 + SwiftUI + Swift Charts
- IOKit `AppleSmartBattery` IORegistry 读取
- 系统 SQLite3（无第三方依赖）
- SMAppService 开机自启

## 已知限制

- 使用了 IORegistry 私有 key，**不适合上架 App Store**（个人本地使用没问题）
- 桌面 Mac（无电池）显示降级为系统功耗
- 字段在未来 macOS 大版本可能变化
