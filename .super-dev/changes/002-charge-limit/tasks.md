# Tasks — ChargeWatch 充电上限 (v0.4)

前端优先 + 运行时验证。READ 路径不依赖 spike，先落地；SET 路径经 spike 定型。

## T1 基础设施（无 spike 依赖）
- `PowerCore/ChargeLimit.swift`：`ChargeLimitState` / `ChargeLimitCapability` / `ChargeLimitError` / `ChargeLimitConstants`
- `App/ProcessRunner.swift`：绝对路径 CLI 执行，off-main，超时强杀，异步排空 stdout/stderr
- 验证：`swift build` 成功

## T2 READ 路径（无 spike 依赖）
- `PowerCore/ChargeLimitReader.swift`：解析 `pmset -g battlimit`（reason=manualChargeLimit 甄别，多条/无限制/不支持）
- `App/ChargeLimitController.swift`：`@MainActor ObservableObject`，refresh + 能力门禁（硬件 arm64 + macOS≥26.4 + bridge）+ start/stopPolling + 深链 + openOnboarding
- 验证：CLI/单测核对解析；与 `pmset -g battlimit` 一致（开/关两态）

## T3 接线 + UI（读/状态/深链；前端优先 + 运行时验证 + preview 门）
- `DesignTokens.swift`：`AppIcon.chargeLimit`
- 接线：AppContainer 创建 controller → AppDelegate（含 onOpenOnboarding）→ StatusBarController（NSPopoverDelegate：show→startPolling+refresh，close→stopPolling）→ MenuBarPanel `.environmentObject`
- `UI/MenuBar/ChargeLimitSection.swift`：A/B/B′/C + 加载/进度/错误；固定尾部状态区；当前值 textPrimary；段控 .segmented
- 弹窗尺寸改内容自适应（去 360×380 魔法数）
- 运行时验证：截图，菜单面板显示当前上限；系统设置改上限 → 重开面板刷新一致
- **preview 门：截图给用户确认**

## T4 SET spike（硬门禁，协作）— 架构 §13.9
- 用户一次性创建桥接快捷指令 `ChargeWatch Set Battery Charge Limit`
- 验证：shortcuts run 前台性 / TCC 授权与被拒 / 单指令动态入参(stdin/--input-path) vs 5 指令 / 回读延迟 / 深链锚点
- 产出：spike 结论记入 research §4 勾选；定 SET 入参方案

## T5 SET 路径（按 spike 定型）
- `App/ShortcutBridge.swift`：isBridgeAvailable（shortcuts list）+ set(percent)（shortcuts run + 退避回读 + 错误分类：权限/超时/退出码/未变）
- `UI/Settings/ChargeLimitOnboardingView.swift`：AppDelegate 独立 NSWindow 引导；B′ 权限引导
- 运行时验证：app 内调 80/85/90/95/100 → 系统改变并回读一致；各降级路径

## T6 质量 + 交付
- build + lint 零错误；A/B/B′/C + 深浅/玻璃态截图核对 UIUX
- 提交前审计（密钥/产物/scaffolding/构建）；更新 README/版本号
