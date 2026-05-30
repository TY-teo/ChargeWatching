# Spec — ChargeWatch 充电上限调节 (v0.4)

> 来源文档：`output/chargewatch-charge-limit-research.md`、`output/chargewatch-prd.md` §9、`output/chargewatch-architecture.md` §13、`output/chargewatch-uiux.md` §13。文档确认门已通过。

## 目标
在菜单面板内显示并调节电池充电上限（80/85/90/95/100），与系统设置充电上限同步，无 root。

## 范围
- READ：`/usr/bin/pmset -g battlimit`，按 `chargeSocLimitReason = manualChargeLimit` 甄别用户上限；实时、无 root。
- SET：经用户一次性快捷指令包裹 macOS 26.4 动作 `SetBatteryChargeLimitAction`，`/usr/bin/shortcuts run` 触发，退避回读确认。
- 降级：能力门禁不满足 / 桥接缺失 / 自动化权限被拒 → 只读显示 + 分级深链 / 引导。
- 不做：<80%、"仅今天"、SMC 限位、"已达上限"副文案。

## 验收（= PRD §9.6）
- 编码前 spike（架构 §13.9）完成并记录；READ 正确同步；SET 通过则 app 内可调并回读确认，否则降级；A/B/B′/C 态齐备；弹窗不裁切；无 root；无 emoji，令牌合规。

## 关键约束
- 仅 Apple Silicon（硬件探测）+ macOS 26.4+ 支持 app 内 SET。
- `ProcessRunner` 绝对路径、不过 shell、入参仅取自 `ChargeLimitConstants.steps`；超时强杀 + 异步排空管道。
- 接线镜像现有 `SampleStream`；刷新/轮询由 `NSPopoverDelegate` 显示/关闭驱动。
- Info.plist 增 `NSAppleEventsUsageDescription`。
