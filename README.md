# ChargeWatch

macOS 菜单栏的充电功率监控 + 原生级电池充电上限。到达上限后**停止充电、由电源适配器直接供电、电池静置不放电**，像 macOS 原生「充电上限」一样温和，不再「一会儿充一会儿不充」。

<p>
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS%2013%2B-black">
  <img alt="silicon" src="https://img.shields.io/badge/charge%20limit-Apple%20Silicon-orange">
  <img alt="swift" src="https://img.shields.io/badge/Swift-5.9-orange">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue">
</p>

<p>
  <img src="picture/charge-limit-redesign-light.png" width="380" alt="ChargeWatch 浅色面板">
  <img src="picture/charge-limit-redesign-dark.png" width="380" alt="ChargeWatch 深色面板">
</p>

## 这是什么

ChargeWatch 是一个常驻菜单栏的轻量工具，做两件事：

1. **实时充电功率监控**——在菜单栏直接看到当前充入电池的瓦数、适配器输出、系统负载与电量，并完整记录历史、可导出 CSV。
2. **电池充电上限**——把电量保持在你设定的上限（80%–100%）附近，减少电池长期满电的损耗。关键在于实现方式：到达上限后只是**停止充电**，适配器继续给整机供电、电池保持不动（既不充也不放），而不是断开适配器逼电池放电。

## 功能特性

- **菜单栏实时瓦数**：SF Symbols 图标 + 当前功率，无 emoji。
- **下拉面板**：充入电池 / 适配器输出 / 系统负载 / 电池电量 四项指标 + 最近 60 秒功率曲线，原生「系统玻璃」材质。
- **充电上限（核心）**：原生滑块设定 80%–100%；到达上限**停充不放电、只走适配器**；带 5% 滞回，循环极慢，几乎不微充放。
- **自动满充校准**：每 7 天放行充满一次，维持系统电量计（SoC）估算准确。
- **历史与统计**：今天 / 本周 / 本月折线图，累计 / 平均 / 峰值 / 时长。
- **一键导出 CSV**。
- **退出即停止**：退出 App 会真正停用充电上限、恢复正常充电，不在后台静默限充。
- **纯本地**：1Hz 采样写入本地 SQLite，无任何联网与遥测。

## 系统要求

- **充电功率监控**：macOS 13 或更高。
- **电池充电上限**：**Apple Silicon Mac**（M 系列）。已在 macOS 26.4（Tahoe）实测；通过写 SMC 的 `CHTE` 键实现「停充不放电」，不支持的机型自动回退到断开适配器方式。Intel Mac 不提供充电上限（仅监控）。

## 下载与安装

1. 到 [Releases](https://github.com/TY-teo/ChargeWatch/releases) 下载最新的 `ChargeWatch-x.y.z.zip`。
2. 解压得到 `ChargeWatch.app`，拖到「应用程序」。
3. 本应用为 ad-hoc 自签名（非 App Store / 未公证），首次打开 macOS 会拦截。**右键点击 App 图标 → 打开 → 再次确认打开** 即可；或在终端执行：

   ```bash
   xattr -dr com.apple.quarantine /Applications/ChargeWatch.app
   ```

4. 首次开启「充电上限」时，会请求一次管理员密码以安装后台组件（root 守护进程，负责写 SMC）。之后调节上限不再需要密码。

## 使用

- 点击菜单栏图标展开面板，查看实时功率与电量。
- 在面板的「充电上限」分组打开开关，用滑块设定目标上限（如 80%）。
- 到达上限后菜单栏与系统都会显示「已接电、暂停充电」，电池停在上限不动。
- 想临时充满：把开关关掉（或上限拉到 100%），即恢复正常充电。
- 退出 App 即停用上限、恢复正常充电。

## 充电上限是怎么工作的

很多充电限制工具靠**断开适配器**（强制走电池放电）来「卡住」电量，副作用是电池被反复微充放、菜单栏显示在用电池，甚至在上限点来回跳动。ChargeWatch 走的是和 macOS 原生「充电上限」一致的思路：

- **停充不放电**：到达上限写 SMC 键 `CHTE = 1`——停止充电，但**适配器保持连接、由它给整机供电**，电池既不充也不放（`pmset` 显示 `AC Power / not charging`、电流约 0）。
- **物理在位判断**：用 SMC 的 `AC-W` 判断电源线是否真的插着，不受充电控制影响，避免「自己断电 → 误判拔线 → 来回跳动」的反馈环。
- **5% 滞回**：对齐 Apple 官方做法（电量自然掉超过 5% 才补回上限），循环极慢、几乎不损耗。
- **自动满充校准**：每 7 天放行充满到 100% 一次，维持电量计估算准确。
- **fail-safe**：守护进程一旦退出 / 崩溃 / 收到信号，立即写回「允许充电、接通适配器」，不会把你卡在「不充电」状态。

## 透明度：它改动了什么、如何彻底卸载

充电上限功能会在系统里留下三样东西（都可逆）：

- 一个 root 后台守护进程：`/Library/LaunchDaemons/com.chenran.chargewatch.helper.plist` 与 `/Library/PrivilegedHelperTools/com.chenran.chargewatch.helper`
- 配置文件：`/Users/Shared/ChargeWatch/smc-limit.json`
- 一个挥发性的 SMC 键（`CHTE`，断电 / SMC 重置即清除）

它**不会**改动或删除 macOS 原生的「优化电池充电 / 充电上限」设置，两者相互独立。

彻底卸载守护进程（恢复完全正常的充电）：

```bash
sudo bash scripts/install-helper.sh uninstall
```

## 隐私

完全本地运行，不联网、不收集任何数据、无遥测。历史数据库仅存在本机：

```
~/Library/Application Support/ChargeWatch/data.sqlite
```

## 从源码构建

需要 Swift 5.9+ / Xcode 15+ 工具链。

```bash
# 同意 Xcode license（首次）
sudo xcodebuild -license accept

# 开发模式直接运行
swift run chargewatch

# 打印一次当前采样（调试用）
swift run chargewatch -- --dump

# 打包成 .app（ad-hoc 签名，内含 root helper 与安装脚本）
./scripts/build-app.sh
open build/ChargeWatch.app
```

## 技术栈

- Swift 5.9 + SwiftUI + Swift Charts
- IOKit：`AppleSmartBattery` 读电量、`AppleSMC` 读写充电键
- 系统 SQLite3（无第三方依赖）
- root LaunchDaemon 守护进程负责 SMC 写入；用户态 App 仅写配置文件

## 已知限制

- 充电上限仅支持 Apple Silicon；SMC 键名为社区逆向所得，未来 macOS 大版本可能变化。
- 使用了 IORegistry 私有字段，不适合上架 App Store（个人本地使用没问题）。
- 桌面 Mac（无电池）功率显示降级为系统功耗。

## 致谢

充电控制的实现与 SMC 键研究参考了以下开源项目：

- [charlie0129/batt](https://github.com/charlie0129/batt)
- [mhaeuser/Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit)
- [AlDente](https://apphousekitchen.com/)

并对照了 Apple 官方文档（[Mac 充电上限](https://support.apple.com/en-us/102338)、[iPhone 充电上限](https://support.apple.com/en-us/108055)）的机制。

## 免责声明

本工具会写入 SMC 充电相关寄存器。虽然带有写后回读校验与多重 fail-safe（异常一律恢复充电），但属于对硬件的非官方控制，**请自行评估并承担风险**。作者不对任何电池或硬件问题负责。

## 许可证

[MIT](LICENSE)
