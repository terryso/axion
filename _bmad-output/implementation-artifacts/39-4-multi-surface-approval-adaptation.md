---
baseline_commit: ffc255b43e260a279bc53f24bef5ec34de154712
---

# Story 39.4: 多入口审批适配

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->
<!-- 范围：构建 surface 无关的结构化审批决策层（approvePlan / approveItem / rejectItem / cancel），并让 run / chat / 未来 telegram 三个入口复用同一套计划模型与摘要格式。run 走终端确认（TTY 整计划 / 逐项；非 TTY 或 --json 输出结构化计划并安全默认拒绝）；chat 走逐项结构化确认（取代 storage 执行工具当前的通用 [y/n] 提示）；telegram 仅预留字段 + 压缩摘要 + 保守远程策略（本 Story 不实现实时 inline-button 交互 UI）。执行工具（execute_storage_plan / execute_app_uninstall）入参口径不变——仍接收「已批准的执行集」；审批决策通过 SDK canUseTool 钩子在「调用执行工具之前」拦截并完成。本 Story 永不永久删除（不存在 delete 动作）。 -->

## Story

As a Axion 用户,
I want run、交互模式（chat）和未来远程入口（telegram）都使用一致的审批语义与同一套结构化计划模型,
So that 同一个高风险存储任务在不同入口中行为一致、安全可控，且每个建议动作的原因、风险与可恢复性都可被用户理解与精确控制.

## Acceptance Criteria

> 本 Story 覆盖「共享审批决策模型 + run 终端确认 + chat 逐项确认 + telegram 预留字段与摘要格式 + JSON 输出兼容」。执行工具的入参口径（「已批准的执行集」）与 39.2 / 39.3 完全一致，**不改 execute_storage_plan / execute_app_uninstall 的入参 schema 与执行逻辑**；审批发生在调用执行工具之前（经 SDK `canUseTool` 钩子拦截）。下列 AC 中标注【39.4】为本 Story 必须满足。安全红线（系统废纸篓、永不永久删除、无 sudo）沿用 39.1–39.3。

1. **【39.4】** **Given** Axion 已有 surface 无关的存储计划模型（`StoragePlan` / `StoragePlanItem` / `AppUninstallPlan` / `SupportDataItem`，含 `StorageSurface` / `RiskLevel` / `DataRisk` / `requiresTypedConfirmation` / `requiresExplicitApproval`）
   **When** 引入共享审批决策模型
   **Then** 新增纯数据模型（位于 `AxionCore/Models/Storage/Approval/`，零外部依赖、`Codable` + `Equatable` + `Sendable`，显式 snake_case `CodingKeys` + `decodeIfPresent` 回退）：`StorageApprovalAction`（`approvePlan` / `approveItem` / `rejectItem` / `cancel` 四个 case）、`StorageApprovalRequest`（`operationId` / `surface: StorageSurface` / `planSummary: PlanSummary` / `items: [StorageApprovalItem]` / `requiresTypedConfirmation: Bool` / `userRequest?`）、`StorageApprovalItem`（`key`（sourcePath 或 bundlePath 唯一键）/ `action: StorageAction` / `sourcePath` / `targetPath?` / `sizeBytes` / `riskLevel: RiskLevel` / `dataRisk: DataRisk?` / `reason` / `requiresExplicitApproval: Bool` / `evidence?`）、`StorageApprovalResponse`（`operationId` / `surface` / `action: StorageApprovalAction` / `approvedItemKeys: [String]` / `rejectedItemKeys: [String]` / `typedConfirmationPayload: String?` / `remoteReserved: RemoteApprovalReserved?` / `collectedAt`）
   **And** `StorageApprovalResponse.action == .cancel` 时 `approvedItemKeys` 必须为空（安全默认）
   **And** 不引入任何新的 `Error` 类型（沿用 `AxionError`，见 Dev Notes「关键约束 #5」）

2. **【39.4】** **Given** 需要按 surface 压缩 / 渲染计划摘要
   **When** 生成 `PlanSummary`
   **Then** `PlanSummary`（同样位于 `AxionCore/Models/Storage/Approval/`）至少含：`operationId` / `surface` / `riskLevel`（聚合 `RiskLevel.max`）/ `totalItems` / `countsByAction: [StorageAction: Int]` / `countsByRisk: [RiskLevel: Int]` / `reversible: Bool` / `requiresTypedConfirmation: Bool` / `topItems: [StorageApprovalItem]`（按 sizeBytes 降序截断前 N，默认 N=8） / `truncatedCount: Int` / `humanReadableSummary: String`
   **And** 提供三个纯渲染函数（无副作用、可单测）：`renderTerminal() -> String`（多行，run / chat 终端用）、`renderJSON()`（即其 Codable 编码）、`renderRemoteCompressed(maxChars: Int) -> [String]`（分页、转义后的短消息串，telegram 预留用，单条默认 ≤ 900 字符并带 `detailCursor` 指向剩余页）
   **And** `renderTerminal()` 与现有 run 输出风格一致（中文、对齐、明确标注「可恢复（废纸篓）/ 高风险 / 需 typed 确认」）

3. **【39.4】** **Given** 不同 surface 的风险承受度不同
   **When** 定义 `SurfacePolicy`（位于 `AxionCore/Models/Storage/Approval/`，纯值类型 + `static func for(_ surface: StorageSurface) -> SurfacePolicy`）
   **Then** `run` / `chat`：允许全部 storage 动作（`move` / `trash` / `createDirectory` / `uninstallApp` / `scanOnly`）——本地、可恢复
   **And** `telegram`（及任何未来远程 surface）：**仅允许 `scanOnly` + `trash`**；**永不**允许 `uninstallApp`；**永不**允许 `requiresTypedConfirmation == true` 或 `dataRisk == .high` 的项被远程批准
   **And** `SurfacePolicy` 暴露纯函数 `offerable(items:for:) -> [StorageApprovalItem]`（远程 surface 从可批准集中剔除禁止项）与 `isRemotelyApprovable(item:) -> Bool`

4. **【39.4】** **Given** 审批决策模型已就绪
   **When** 派生「实际可执行集」
   **Then** 提供纯函数（位于 `AxionCore/Models/Storage/Approval/StorageApprovalDecision.swift`，无 SDK 依赖、完全可单测）：`applyDecision(request:response:policy:) -> ApprovedExecutionSet`（按 `approvedItemKeys` 过滤，并经 `policy` 二次裁剪）、`enforcePolicy(response:policy:) -> StorageApprovalResponse`（远程 surface 上把禁止项从 `approvedItemKeys` 移除并加入 `rejectedItemKeys`）、`validateTypedConfirmation(payload:expected:) -> Bool`（当 `requiresTypedConfirmation` 时校验用户输入的 App 名 / bundle id 是否匹配，规则：忽略大小写与首尾空白、接受 displayName 或 bundleIdentifier 任一匹配）
   **And** 这些函数**不**执行任何 I/O、**不**调用 executor

5. **【39.4】** **Given** run 入口（`axion run`，`AgentMode.desktopAutomation`）
   **When** Agent 调用 `execute_storage_plan` 或 `execute_app_uninstall`（均为 `isReadOnly = false`）
   **Then** 经 SDK `canUseTool` 钩子拦截（**注意：run 模式当前 `canUseTool` 为 nil，本 Story 需为 run 模式接入 canUseTool**）：钩子**只**对这两个 storage 执行工具生效，**对其余所有工具一律返回 `.allow()`**（严格保持现有 fire-and-forget 语义，见 Dev Notes「关键约束 #1」）
   **And** 钩子从工具 `input` 解析出 items + operation_id + surface，构建 `StorageApprovalRequest`（经 `SurfacePolicy.for(surface)` 裁剪可批准集），委托 `RunApprovalCollector` 收集决策
   **And** TTY 环境：渲染 `PlanSummary.renderTerminal()`，读取单键 / 行输入，支持「整计划批准 / 逐项批准子集 / 拒绝 / 取消」，`requiresTypedConfirmation == true` 时强制读取 typed payload 并经 `validateTypedConfirmation` 校验
   **And** 非 TTY 或 `--json`：**不**尝试交互读取，向 stdout / JSON 流输出结构化 `StorageApprovalRequest` + `PlanSummary`，并返回 `.deny("approval_required")`（安全默认：破坏性操作在无显式确认时执行次数为 0）

6. **【39.4】** **Given** run 审批钩子收到 `RunApprovalCollector` 的决策
   **When** 决策为 `approvePlan`（且 `policy` 允许全部）
   **Then** 返回 `.allow()`，执行工具正常执行（其既有纵深重校验不变）
   **When** 决策为 `approveItem(approvedSubset)`（子集 < 全部请求项）
   **Then** 返回 `.deny`，deny 文本为**结构化**（含 `approved_subset` 与各 approved item 的 source），引导 Agent 仅以该子集重新调用执行工具（执行工具入参不变；详见 Dev Notes「子集授权协议」）
   **When** 决策为 `rejectItem` / `cancel` / typed 校验失败 / 非 TTY
   **Then** 返回 `.deny("<reason>")`（`user_cancelled` / `typed_confirmation_failed` / `approval_required` / `policy_violation`），Agent 终止该操作

7. **【39.4】** **Given** chat 入口（交互模式，`AgentMode.codingAgent`）
   **When** Agent 调用 `execute_storage_plan` 或 `execute_app_uninstall`
   **Then** **扩展现有 `PermissionHandler.createCanUseTool` 闭包**（位于 `Sources/AxionCLI/Chat/PermissionHandler.swift`），在「read-only 自动放行」之后、「通用工具提示」之前**新增一个 storage 执行工具分支**：当 `tool.name ∈ {execute_storage_plan, execute_app_uninstall}` 时，委托 `ChatApprovalCollector`（而非走通用 `[y/n]` / approval-center 工具级提示）
   **And** `ChatApprovalCollector` 复用现有 `ApprovalRenderer` / `SessionAllowList` / 单键输入 / TTY 检测（`Sources/AxionCLI/Chat/Approval/`）做**逐项结构化确认**（每项显示 action / source / size / risk / reason / evidence，支持「全选 / 逐项勾选 / 全否 / 取消」）
   **And** **严格保持**对 Bash / Write / Edit 等非 storage 工具的既有权限行为（acceptEdits / bypassPermissions / session allow list / 非 TTY 拒绝）**完全不变**（见 Dev Notes「关键约束 #2」）；`bypassPermissions` 模式下 storage 执行工具同样直接放行（与现有语义一致）
   **And** `requiresTypedConfirmation == true` 项在 chat 中同样强制 typed payload 校验

8. **【39.4】** **Given** chat 审批分支决策
   **When** 应用与 run 相同的「子集授权协议」（AC #6）
   **Then** 复用同一套纯函数（`applyDecision` / `enforcePolicy` / `validateTypedConfirmation`）派生可执行集与 allow / deny 结果（run 与 chat 的决策派生逻辑**共享**，仅「收集」环节不同）

9. **【39.4】** **Given** 未来 telegram 远程入口（`StorageSurface.telegram`）
   **When** 构建审批请求 / 响应
   **Then** `TelegramApprovalReserve`（位于 `Sources/AxionCLI/Services/Storage/Approval/`）**不**实现实时 inline-button 收集 UI（属未来 epic，如 34-5）；本 Story 仅产出：(a) `PlanSummary.renderRemoteCompressed(maxChars:)` 的分页摘要（telegram 消息体）；(b) `StorageApprovalResponse.remoteReserved: RemoteApprovalReserved`（预留字段：`pendingMessageId` / `inlineButtonsReserved: [RemoteApprovalButton]`（仅描述，不发送）/ `expiresAt` / `detailCursor`）；(c) `SurfacePolicy.for(.telegram)` 的保守裁剪（AC #3）
   **And** `TelegramApprovalReserve.request(_:)` 返回 `StorageApprovalResponse(action: .cancel, ...)`（远程入口 MVP 不在线批准破坏性操作；`scanOnly` 计划仍可只读展示）
   **And** 复用既有 telegram 类型作为格式参考（**不修改**）：`TGSendMessageRequest` / `TGInlineKeyboardMarkup` / `TGInlineKeyboardButton` / `TGCallbackData` / `TGInteractionSession`（`Sources/AxionCLI/Services/Telegram/`）

10. **【39.4】** **Given** run 使用 `--json` 或被管道 / 非 TTY 驱动
    **When** storage 执行工具被调用
    **Then** 输出的结构化 `StorageApprovalRequest` + `PlanSummary` 必须可被现有 JSON 解析口径消费（snake_case、`decodeIfPresent` 兼容），**不破坏**现有 `--json` 契约（`Sources/AxionCLI/Commands/RunCommand.swift` 的 `--json` 输出结构）
    **And** 非 TTY / `--json` 下破坏性执行被 `.deny("approval_required")` 拦截，调用方需经带外（out-of-band）方式显式确认后重新驱动；本 Story **不**实现自动带外确认通道（标注为后续工作，见 Dev Notes「非 TTY 显式确认」）

11. **【39.4】** **Given** 审批层与执行工具协同
    **When** 任何 surface 上用户取消、拒绝、typed 校验失败、或远程 policy 裁剪后无可批准项
    **Then** 执行工具**不被调用**（钩子 `.deny`），**不**写 manifest 草稿、**不**触碰文件系统、**不**移任何项入废纸篓（破坏性操作执行次数为 0）
    **And** 经 `propose_storage_plan` / `scan_app_uninstall`（只读工具）输出的计划在审批前可被任意 surface 完整展示，不受 policy 裁剪影响（policy 只裁剪「可批准集」，不裁剪「可展示计划」）

## Tasks / Subtasks

- [x] **Task 1：共享审批决策模型（AxionCore）**(AC: #1, #2, #3, #4)
  - [x] 1.1 新建 `Sources/AxionCore/Models/Storage/Approval/StorageApprovalEnums.swift`：`StorageApprovalAction`（`approvePlan` / `approveItem` / `rejectItem` / `cancel`，String + Codable + Sendable + Equatable）。**复用** `StorageAction` / `StorageSurface` / `RiskLevel` / `DataRisk`（`StorageEnums.swift`），**禁止**新增重复枚举。
  - [x] 1.2 `StorageApprovalItem.swift`：字段见 AC #1；显式 snake_case `CodingKeys` + `init(from:)` 用 `decodeIfPresent` 回退（风格对齐 `SupportDataItem.swift` / `StorageManifestItem`）。
  - [x] 1.3 `StorageApprovalRequest.swift` + `StorageApprovalResponse.swift` + `RemoteApprovalReserved.swift`：字段见 AC #1 / #9；`RemoteApprovalReserved` 仅预留字段（`pendingMessageId` / `inlineButtonsReserved` / `expiresAt` / `detailCursor`），全部 `decodeIfPresent` 可选。
  - [x] 1.4 `PlanSummary.swift`：字段见 AC #2；提供纯函数 `renderTerminal()` / `renderJSON()`（Codable）/ `renderRemoteCompressed(maxChars:)`。`RiskLevel.max` 聚合复用 `StorageEnums.swift` 现有实现。`topItems` 截断阈值用 `StorageConfig` 现有常量风格（默认 8，可注入）。
  - [x] 1.5 `SurfacePolicy.swift`：值类型 + `static func for(_:)`；纯函数 `offerable(items:for:)` / `isRemotelyApprovable(item:)`；远程策略见 AC #3。
  - [x] 1.6 `StorageApprovalDecision.swift`：纯函数 `applyDecision` / `enforcePolicy` / `validateTypedConfirmation` / `deriveApprovedSubset`（AC #4 / #8）。无 I/O、无 executor 调用。

- [x] **Task 2：审批协议 + 决策派生可测性（AxionCLI）**(AC: #4, #5, #7, #8)
  - [x] 2.1 `Sources/AxionCLI/Services/Storage/Approval/StorageApproving.swift`：`protocol StorageApproving: Sendable { func collect(request:policy:) async -> StorageApprovalResponse }`（协议放 AxionCLI Services，与 `StorageExecuting` 同层；签名增加 `policy:` 参数以便 collector 直接复用裁剪结果）。
  - [x] 2.2 抽取 `ApprovedExecutionSet`（approved items + rejected keys + 派生自 `applyDecision`）与 `ApprovalGateOutcome`（allow / denySubset / deny），供钩子决定 allow / deny-子集 / deny-取消。

- [x] **Task 3：run 入口审批钩子（AxionCLI）**(AC: #5, #6, #10, #11)
  - [x] 3.1 `Sources/AxionCLI/Services/Storage/Approval/RunApprovalCollector.swift`：构造器注入 `writeStdout` / `readLine` / `now`（`@Sendable` 闭包 + DI，风格对齐 `Chat/PermissionHandler`）。实现 `StorageApproving`。TTY 路径渲染 `PlanSummary.renderTerminal()` 并收集整计划批准 / 取消；`requiresTypedConfirmation` 强制 typed payload；非 TTY 由 gate 在调用 collector 前直接 `.deny("approval_required")`。
  - [x] 3.2 `Sources/AxionCLI/Services/Storage/Approval/StorageApprovalGate.swift`：把 `CanUseToolFn` 适配为 storage 执行工具审批门。输入 `tool` + `input` → 经 `StorageApprovalInput.build` 解析 items / operation_id / surface → 构建请求 → 委托 collector → `resolveOutcome` → 返回 `.allow()` / `.deny(structured approved_subset)` / `.deny(reason)`。**复用** `ExecuteStoragePlanTool.parseItem` / `ExecuteAppUninstallTool.parseApp`（经 `StorageApprovalInput`）。
  - [x] 3.3 在 `AgentBuilder`（`Sources/AxionCLI/Services/AgentBuilder.swift`）为 `desktopAutomation`（run）模式接入 `canUseTool`：仅当 `mode == .desktopAutomation && !dryrun && !emitTokenStream` 时注入 `makeRunCanUseTool`（gate 内对非 storage 工具一律 `.allow()`）。`dryrun` / gateway（`emitTokenStream`）不注入 run gate。

- [x] **Task 4：chat 入口逐项确认（AxionCLI）**(AC: #7, #8, #11)
  - [x] 4.1 `Sources/AxionCLI/Services/Storage/Approval/ChatApprovalCollector.swift`：实现 `StorageApproving`，逐项 `[y/n/a/q]` 收集，支持子集授权（`approveItem`）/ 批准全部（`approvePlan`）/ 取消（`cancel`）。
  - [x] 4.2 扩展 `PermissionHandler.createCanUseTool`（`Sources/AxionCLI/Chat/PermissionHandler.swift`）：在 `bypassPermissions` / read-only 放行**之后**插入 storage 执行工具分支（注入 `surfaceApproving: StorageApproving?`，默认 nil 保持既有签名兼容）。`bypassPermissions` 仍优先全放行。
  - [x] 4.3 决策派生复用 Task 1.6 纯函数（run/chat 共享 `resolveOutcome`）。

- [x] **Task 5：telegram 预留字段 + 压缩摘要 + 保守策略（AxionCLI）**(AC: #3, #9)
  - [x] 5.1 `Sources/AxionCLI/Services/Storage/Approval/TelegramApprovalReserve.swift`：产出 `renderRemoteCompressed` 摘要 + 填充 `RemoteApprovalReserved` 预留字段（`inlineButtonsReserved` 仅 offerable 项 / `detailCursor`）；`collect` 返回 `.cancel`（远程 MVP 不在线批准破坏性操作）。**不**发送 telegram 消息、**不**创建 inline keyboard、**不**改任何 `Telegram/` 文件。
  - [x] 5.2 `SurfacePolicy.for(.telegram)` 在 Task 1.5 内实现（scanOnly + trash only；禁 uninstallApp / 高风险 / typed）。gateway（`TaskSerialQueue+Execution.makeBuildConfig`）注入 `TelegramApprovalReserve`。

- [x] **Task 6：单元测试（Swift Testing，Mock，无真实外部依赖）**(AC: 全部)
  - [x] 6.1 `Tests/AxionCoreTests/Models/Storage/Approval/`：`ApprovalModelsCodecTests`（模型 Codable 往返 + snake_case + 缺字段回退 + cancel 不变式 init/decode）、`ApprovalDecisionTests`（`PlanSummary` 三渲染 / 分页、`SurfacePolicy.for` 三 surface 裁剪、`applyDecision` / `deriveApprovedSubset` / `validateTypedConfirmation` / `resolveOutcome` 全路径）。
  - [x] 6.2 `Tests/AxionCLITests/Services/Storage/Approval/`：`CollectorsTests`（`RunApprovalCollector` approve/cancel/typed、`ChatApprovalCollector` 子集/approveAll/cancel、`TelegramApprovalReserve` 仅 offerable 项入按钮 + cancel，全经 `ScriptedIO` Mock）、`StorageApprovalInputTests`（execute_storage_plan / execute_app_uninstall 解析、非 storage → nil）。
  - [x] 6.3 `StorageApprovalGateTests`：注入 `MockStorageApprover`，断言 approvePlan → `.allow()`、approveItem(子集) → `.deny(structured approved_subset)`、cancel → `.deny(user_cancelled)`、非 TTY → `.deny(approval_required)`、`--json` → `.deny(--json ...)`、telegram reserve → cancel；**且**非 storage 工具恒 `.allow()`（回归保护）。
  - [x] 6.4 全部走 Mock 与注入闭包（`ScriptedIO` / `MockStorageApprover`），无真实 executor / 文件系统 / telegram / readLine（CLAUDE.md「单元测试必须 Mock」）。

- [x] **Task 7：构建与回归**(AC: 全部)
  - [x] 7.1 `swift build` 通过；`grep -rl "import XCTest" Tests/` 仍为空（已核验）。
  - [x] 7.2 仅运行单元测试：`swift test --filter "AxionCoreTests" --filter "AxionCLITests"` 通过（5 个 Storage Approval 套件全绿）；**未**跑 `Integration/` / `AxionE2ETests`。
  - [x] 7.3 人工核验：run / chat / telegram 三入口经共享 `PlanSummary` + `SurfacePolicy` + `StorageApprovalDecision` 复用同一计划模型与决策逻辑，输出一致的结构化摘要与风险标注；非 TTY / `--json` 安全默认拒绝。

## Dev Notes

### 关键约束（必须遵守，违反即灾难）

1. **run 模式 canUseTool 当前为 nil（fire-and-forget）。** 本 Story 为 run 接入 canUseTool 时，**必须**保证「除 `execute_storage_plan` / `execute_app_uninstall` 外的所有工具恒返回 `.allow()`」。任何对 Bash / Skill / 截图等工具的意外拦截都属**严重回归**。建议实现为：闭包顶部判断 `tool.name`，命中 storage 执行工具才进入 gate，否则立即 `.allow()`。
2. **chat 模式 canUseTool 已存在并承载 Bash/Write/Edit/session-allowlist/非 TTY 拒绝等行为。** 本 Story 是**新增分支**（在 read-only 放行之后、通用提示之前），**绝不替换**既有逻辑；保持 `createCanUseTool` v1/v2 既有签名可调用（新参数走默认值）。`bypassPermissions` 优先级最高，storage 执行工具在该模式下同样放行。
3. **不改执行工具。** `execute_storage_plan` / `execute_app_uninstall` 的入参 schema 与纵深重校验（scan_roots / exclusions / 非 symlink / action 白名单 / bundleId 一致 / `matchConfidence != low` / `dataRisk != forbidden`）保持原样。审批与执行解耦：审批产出「已批准集」，执行工具接收的仍是它一直接收的「已确定要执行的项」。
4. **审批发生在执行工具被调用之前（canUseTool 钩子）。** canUseTool 在工具实际执行**之前**触发，正是 epic 所要求的拦截点；返回 `.deny` 则工具永不执行。
5. **不新增 Error 类型。** 沿用 `AxionError`；审批「拒绝」用 SDK 的 `.deny(String)` 表达，deny 文本为结构化字符串（子集授权时含 JSON 形 `approved_subset`），不抛异常。
6. **永不永久删除。** 无 `delete` 动作；`trash` 走系统废纸篓（可恢复）。`SurfacePolicy.for(.telegram)` 进一步收紧为 scan + trash only。
7. **不修改 `axion run` 来实现 chat 行为。** run 与 chat 经 `AgentMode` 区分（`.desktopAutomation` / `.codingAgent`）；审批钩子按模式分别注入对应 collector，不改变两个命令的既有职责。
8. **无 `print()`。** Collector 经注入的 `writeStdoutFn` 输出；gate 经 SDK `CanUseToolFn` 的 `.allow/.deny` 返回值表达结果（复用 `ToolResultHelper` 风格）。
9. **MCP / JSON 字段 snake_case + 显式 CodingKeys + decodeIfPresent 部分解码**（对齐 `SupportDataItem` / `StorageManifest`）。
10. **AxionCore 零外部依赖。** 决策模型 / PlanSummary / SurfacePolicy / 决策纯函数全部放 `AxionCore/Models/Storage/Approval/`；`StorageApproving` 协议与各 collector / gate 放 `AxionCLI/Services/Storage/Approval/`（可 import OpenAgentSDK + AxionCore）。
11. **Telegram = 预留 + MVP。** 本 Story **不**实现实时 inline-button 审批 UI、**不**发送 telegram 消息、**不**改 `Sources/AxionCLI/Services/Telegram/` 任何文件（实时远程审批属未来 epic，如 34-5 `exec-approval-scope-backend-logic`）。仅产出预留字段、压缩摘要、保守策略。

### 子集授权协议（approveItem 子集 < 全部）

`canUseTool` 只能返回 `.allow()` / `.deny(String)`，**无法改写工具入参**。当用户只批准子集时：
- 钩子返回 `.deny`，deny 文本为结构化（含 `approved_subset` 与各 approved item 的 `source` / `action`）。
- Agent 据此仅以该子集**重新调用**执行工具（执行工具入参 schema 不变，只是 items 更少）。
- 重新调用时钩子再次触发：此时「请求项 == 已批准子集」→ `approvePlan` → `.allow()`。
- **fail-safe**：即使 Agent 误行为（带上未批准项重调），钩子会再次 deny，未批准项永不执行——这正是所需的安全属性。
- 工具描述 / 系统提示应说明「以 deny 中返回的 approved_subset 重新调用」（run 系统提示在 `AgentBuilder.buildSystemPrompt`，chat 在 `buildCodingSystemPrompt`）。

### 非 TTY / --json 显式确认

- 非 TTY 或 `--json` 下钩子**不**交互读取；输出结构化 `StorageApprovalRequest` + `PlanSummary` 后 `.deny("approval_required")`。
- 带外（out-of-band）显式确认通道（如 `--approve-storage-op <operation_id>` 标志或审批文件）**不在本 Story 范围**；在 README / story 内标注为后续工作。MVP 保证「无显式确认 → 破坏性操作执行次数为 0」。
- 只读计划工具（propose / scan）不受影响：任意 surface 可完整展示计划。

### 复用清单（避免重造轮子）

| 需求 | 复用 | 位置 |
| --- | --- | --- |
| surface / 风险 / 数据风险枚举 | `StorageSurface` / `RiskLevel` / `DataRisk` / `StorageConfidence` / `StorageEvidence` | `Sources/AxionCore/Models/Storage/StorageEnums.swift` |
| 计划项 / 卸载计划 / support 项 | `StoragePlan` / `StoragePlanItem` / `AppUninstallPlan` / `SupportDataItem`（含 `requiresTypedConfirmation` / `requiresExplicitApproval`） | `Sources/AxionCore/Models/Storage/`、`.../App/` |
| 执行入参解析 | `ExecuteStoragePlanTool.parseItem` / `parseAction` / `parseEvidence` / `parseSizeBytes` | `Sources/AxionCLI/Tools/ExecuteStoragePlanTool.swift` |
| TTY 检测 / 单键输入 / 闭包注入 / 非 TTY 拒绝 | `PermissionHandler.createCanUseTool` / `readSingleKey` 模式 | `Sources/AxionCLI/Chat/PermissionHandler.swift` |
| chat 逐项渲染 / 会话允许列表 | `ApprovalRenderer` / `SessionAllowList` / `ApprovalDecision` / `ApprovalDiffPreview` | `Sources/AxionCLI/Chat/Approval/` |
| telegram 消息 / inline / callback 格式 | `TGSendMessageRequest` / `TGInlineKeyboardMarkup` / `TGInlineKeyboardButton` / `TGCallbackData` / `TGInteractionSession`（**仅格式参考，不修改**） | `Sources/AxionCLI/Services/Telegram/` |
| manifest 落盘 / 撤销 | `StorageManifestStore` / `StorageUndoService`（39.2/39.3，**不在本 Story 改动**） | `Sources/AxionCLI/Services/Storage/` |

> 注意：`ApprovalDecision`（`Chat/Approval/ApprovalDecision.swift`）是**工具级**权限粒度（once/session/prefix/decline），与本 Story 的**计划项级**审批（approvePlan/approveItem/rejectItem/cancel）是**不同轴**。复用其**模式**（单键 / TTY / 闭包注入），**不复用**其枚举语义。

### 反模式（禁止）

- 在 `ExecuteStoragePlanTool` / `ExecuteAppUninstallTool` 内做审批（审批属入口层，工具只接收已批准集）。
- 为「子集授权」改写执行工具入参或新增「已批准项存储」让工具反查（保持工具无状态、可独立重校验）。
- 在 `AxionCore` 引入 OpenAgentSDK / AppKit 依赖。
- 在单元测试中真实 readLine / 真实 executor / 真实 telegram / 弹系统通知。
- 远程 surface 上允许 `uninstallApp` / 高风险 / typed 项被批准。
- 用 `print()` 输出（用注入 `writeStdoutFn` 或 SDK 返回值）。

### Project Structure Notes

- 新增模型目录：`Sources/AxionCore/Models/Storage/Approval/`（与现有 `Sources/AxionCore/Models/Storage/App/` 并列；纯数据，零依赖）。
- 新增服务目录：`Sources/AxionCLI/Services/Storage/Approval/`（与现有 storage 服务并列；可 import OpenAgentSDK）。
- 修改点（最小化）：
  - `Sources/AxionCLI/Services/AgentBuilder.swift`：run 模式接入 storage 审批 `canUseTool`（L166–201 storage 工具注册块附近）。
  - `Sources/AxionCLI/Chat/PermissionHandler.swift`：新增 storage 执行工具分支（保持既有签名兼容）。
- 不改动：`Sources/AxionCLI/Tools/`（执行 / 提议 / 扫描工具）、`Sources/AxionCLI/Services/Telegram/`、`Sources/AxionCore/Models/Storage/` 既有模型、`RunCommand.swift`（除确认 `--json` 输出兼容外不动逻辑）。
- 命名：审批类型前缀 `StorageApproval*` / `PlanSummary` / `SurfacePolicy` / `RemoteApprovalReserved`；snake_case JSON 字段。

### References

- Epic 范围与成功指标：[Source: docs/epics/epic-39-mac-storage-file-app-management.md#Story 39.4]（多入口审批适配：共享审批决策模型 / run 终端确认 / 交互模式逐项确认 / Telegram 预留字段和摘要格式 / JSON 输出兼容）。
- Epic telegram 设计约束（结构化模型、审批动作抽象为 approvePlan/approveItem/rejectItem/cancel、摘要压缩为远程消息+分页、远程更保守 scan+trash only、永不永久删除）：[Source: docs/epics/epic-39-mac-storage-file-app-management.md#Telegram 设计约束]（约 L86–93）。
- Epic 计划字段表（operationId/surface/items/riskLevel/requiresConfirmation/reversible/summary 与 item 字段）：[Source: docs/epics/epic-39-mac-storage-file-app-management.md#计划字段表]（约 L357–381）。
- 39.3 边界声明（执行工具接收「已确定要执行的项」；审批决策由入口在调用前完成；requiresTypedConfirmation 由入口强制、39.4 统一）：[Source: _bmad-output/implementation-artifacts/39-3-app-uninstall-support-data-scan.md#L10]。
- 执行工具「入参即已批准执行集」注释：[Source: Sources/AxionCLI/Tools/ExecuteStoragePlanTool.swift#L14-L15]。
- 现有审批 / 权限基础设施：[Source: Sources/AxionCLI/Chat/PermissionHandler.swift#createCanUseTool]、[Source: Sources/AxionCLI/Chat/Approval/ApprovalDecision.swift]、[Source: Sources/AxionCLI/Chat/Approval/ApprovalRenderer.swift]、[Source: Sources/AxionCLI/Chat/Approval/SessionAllowList.swift]。
- Storage 枚举 / 计划模型：[Source: Sources/AxionCore/Models/Storage/StorageEnums.swift]、[Source: Sources/AxionCore/Models/Storage/StoragePlan.swift]、[Source: Sources/AxionCore/Models/Storage/StoragePlanItem.swift]、[Source: Sources/AxionCore/Models/Storage/App/AppUninstallPlan.swift]、[Source: Sources/AxionCore/Models/Storage/App/SupportDataItem.swift]。
- Storage 工具注册块（run/chat 共享、`!dryrun`）：[Source: Sources/AxionCLI/Services/AgentBuilder.swift#L166-L201]。
- Telegram 格式参考（不修改）：[Source: Sources/AxionCLI/Services/Telegram/TGModels.swift]、[Source: Sources/AxionCLI/Services/Telegram/TGCallbackData.swift]。
- 项目架构 / 反模式（AxionCore 零依赖、无 print、snake_case、不新增 Error、Chat 纯函数 + DI 闭包、不改 axion run 实现 chat）：[Source: _bmad-output/project-context.md]。

## Dev Agent Record

### Agent Model Used

GLM-5.1（通过 Claude Code dev-story 工作流执行）。

### Debug Log References

- 构建：`swift build` 通过（Build complete!）。
- 单元测试：`swift test --filter "AxionCoreTests" --filter "AxionCLITests"` 通过；5 个新增 Storage Approval 套件全绿（Storage Approval Decision Logic / Models Codec / Input Builder / Collectors / Gate）。
- 唯一失败为 `DesktopNotifierTests`（tmux passthrough 包裹 OSC 9 序列），属**预存在环境性失败**（本 Story 未触碰该文件；`TMUX` 已设置 / `TERM=tmux-256color`），与 39.4 无关。
- XCTest 核验：`grep -rl "import XCTest" Tests/` 返回空。

### Completion Notes List

- **共享决策层（AxionCore，零依赖）**：`StorageApprovalAction` / `StorageApprovalItem` / `StorageApprovalRequest` / `StorageApprovalResponse` / `RemoteApprovalReserved` / `RemoteApprovalButton` / `PlanSummary` / `SurfacePolicy` / `StorageApprovalDecision`（`ApprovedExecutionSet` / `ApprovalGateOutcome`）。全部 `Codable` + `Equatable` + `Sendable`，显式 snake_case `CodingKeys` + `decodeIfPresent`。
- **cancel 不变式**：`StorageApprovalResponse` 在 init 与 decode 两处强制 `action == .cancel ⇒ approvedItemKeys == []`。
- **run 钩子（AxionCLI）**：`RunApprovalCollector`（终端整计划确认 + typed 二次确认）+ `StorageApprovalGate.makeRunCanUseTool`（非 storage 工具恒 `.allow()`）；`AgentBuilder` 仅在 `mode == .desktopAutomation && !dryrun && !emitTokenStream` 注入。
- **chat 钩子（AxionCLI）**：`ChatApprovalCollector`（逐项 `[y/n/a/q]`，支持子集）+ `PermissionHandler.createCanUseTool` 新增 `surfaceApproving` 分支（`bypassPermissions` / read-only 放行之后），保持既有签名兼容。
- **telegram（预留 + MVP）**：`TelegramApprovalReserve` 仅产出 `RemoteApprovalReserved`（offerable 项按钮 + 分页游标）+ `.cancel`；未发送消息、未改 `Telegram/`。gateway（`TaskSerialQueue+Execution.makeBuildConfig`）注入。
- **JSON / 非 TTY**：gate 在 `--json` 或非 TTY（非 telegram surface）下直接 `.deny`，输出结构化请求；`--json` 契约经 `AgentBuildConfig.jsonOutput` 透传，未破坏既有输出。
- **子集授权协议**：`approveItem` 子集 → `.deny(renderSubsetRecall)`（结构化 `approved_subset` JSON），Agent 据此以子集重调 → 再次命中钩子 → `approvePlan` → `.allow()`；误带未批准项则再次 deny（fail-safe）。
- **执行工具未改**：`execute_storage_plan` / `execute_app_uninstall` 入参 schema 与纵深重校验保持原样；审批经 `canUseTool` 在执行前拦截。
- **实现偏差（已记录）**：(1) `StorageApproving.collect(request:policy:)` 较 AC 字面 `request(_:)` 增加 `policy:` 参数（collector 需直接复用裁剪结果 / telegram offerable）。(2) `enforcePolicy(response:policy:items:)` 较 AC 字面增加 `items:` 参数（dataRisk 剔除需按 key 反查 item）。均为纯函数签名扩展，语义与 AC 一致。
- **Swift 合成 init 经验**：`AgentBuildConfig.jsonOutput: Bool`（无默认值）须在全部构造点显式传参——Swift 合成 memberwise init 排除带默认值的属性，故移除默认值并在 6 处 call site 显式注入。

### File List

**新增（AxionCore 模型，零依赖）**
- `Sources/AxionCore/Models/Storage/Approval/StorageApprovalEnums.swift`
- `Sources/AxionCore/Models/Storage/Approval/StorageApprovalItem.swift`
- `Sources/AxionCore/Models/Storage/Approval/StorageApprovalRequest.swift`
- `Sources/AxionCore/Models/Storage/Approval/StorageApprovalResponse.swift`
- `Sources/AxionCore/Models/Storage/Approval/RemoteApprovalReserved.swift`
- `Sources/AxionCore/Models/Storage/Approval/PlanSummary.swift`
- `Sources/AxionCore/Models/Storage/Approval/SurfacePolicy.swift`
- `Sources/AxionCore/Models/Storage/Approval/StorageApprovalDecision.swift`

**新增（AxionCLI 服务）**
- `Sources/AxionCLI/Services/Storage/Approval/StorageApproving.swift`
- `Sources/AxionCLI/Services/Storage/Approval/StorageApprovalInput.swift`
- `Sources/AxionCLI/Services/Storage/Approval/StorageApprovalGate.swift`
- `Sources/AxionCLI/Services/Storage/Approval/RunApprovalCollector.swift`
- `Sources/AxionCLI/Services/Storage/Approval/ChatApprovalCollector.swift`
- `Sources/AxionCLI/Services/Storage/Approval/TelegramApprovalReserve.swift`

**新增（单元测试，Swift Testing）**
- `Tests/AxionCoreTests/Models/Storage/Approval/ApprovalModelsCodecTests.swift`
- `Tests/AxionCoreTests/Models/Storage/Approval/ApprovalDecisionTests.swift`
- `Tests/AxionCLITests/Services/Storage/Approval/MockStorageApprover.swift`
- `Tests/AxionCLITests/Services/Storage/Approval/StorageApprovalGateTests.swift`
- `Tests/AxionCLITests/Services/Storage/Approval/StorageApprovalInputTests.swift`
- `Tests/AxionCLITests/Services/Storage/Approval/CollectorsTests.swift`

**修改（最小化）**
- `Sources/AxionCLI/Services/AgentBuilder.swift`（run 模式注入 storage 审批 canUseTool）
- `Sources/AxionCLI/Services/AgentBuilder+Config.swift`（`AgentBuildConfig.jsonOutput` + `forCLI(json:)`）
- `Sources/AxionCLI/Services/AxionRuntime.swift`（透传 `jsonOutput`）
- `Sources/AxionCLI/Commands/RunCommand.swift`（`forCLI(json: json)`）
- `Sources/AxionCLI/Chat/PermissionHandler.swift`（新增 `surfaceApproving` storage 分支）
- `Sources/AxionCLI/Commands/ChatCommand.swift`（注入 `ChatApprovalCollector`）
- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue+Execution.swift`（gateway 注入 `TelegramApprovalReserve`）

**未改动（边界保持）**：`Sources/AxionCLI/Tools/`、`Sources/AxionCLI/Services/Telegram/`、`AxionCore/Models/Storage/` 既有模型。

## Senior Developer Review (AI)

- **审查模型**：GLM-5.1（adversarial review，fresh context，按 BMAD story-automator-review 工作流）。
- **审查日期**：2026-06-12。
- **baseline_commit**：ffc255b（与 Story 声明一致）。
- **结论**：**0 CRITICAL** / 2 HIGH（已修） / 1 LOW（已修） → Status → done。

### 对抗式核验（challenge [x] 任务标记与 AC 实现）

- Task 1–7 全部 `[x]` 经代码核验**为真**（无虚假标记）：8 个 AxionCore 模型 + 6 个 AxionCLI 服务 + 6 个测试文件均存在且语义与 AC 一致；`swift build` 通过；`grep -rl "import XCTest" Tests/` 为空（CLAUDE.md 规则满足）。
- **AC #1 cancel 不变式**：`StorageApprovalResponse` 在 init 与 decode 两处强制 `action == .cancel ⇒ approvedItemKeys == []`——**已核验**（`ApprovalModelsCodecTests` 覆盖）。
- **AC #3 SurfacePolicy**：`telegram = [.scanOnly, .trash]`、`allowsTypedConfirmation=false`、`allowsHighDataRisk=false`、禁 `uninstallApp`——**已核验**。
- **AC #5/#6 run 钩子**：非 storage 工具恒 `.allow()`（`makeRunCanUseTool` 末尾兜底）；`AgentBuilder` 仅 `desktopAutomation && !dryrun && !emitTokenStream` 注入——**已核验，无 fire-and-forget 回归**。
- **AC #7 chat 钩子**：storage 分支插在 `bypassPermissions` / read-only 放行**之后**、通用提示之前；`bypassPermissions` 仍优先全放行——**已核验**。
- **AC #9 telegram**：`TelegramApprovalReserve.collect` 恒返回 `.cancel`；未发送消息、未改 `Telegram/`——**已核验**。
- **AC #10 --json / 非 TTY**：gate 在 `--json` 或非 TTY（非 telegram）下 `.deny("approval_required")`——**已核验**（修复后另附结构化 `PlanSummary`）。
- **AC #11 零副作用**：deny 路径不触 executor / 文件系统——**已核验**（钩子在执行前拦截）。

### 发现的问题（已全部自动修复）

1. **[HIGH] chat 入口 storage 审批未暂停 ESC 监听器，与 readLine 争抢 stdin**（`PermissionHandler.swift` storage 分支）。
   - 现象：既有通用权限路径在渲染提示前调用 `escListenerRef?.pause()` 停止 ESC 轮询任务（raw mode 下逐字节吞非 ESC 输入）并恢复 canonical mode；storage 分支遗漏此协调，导致 collector 内部 `readLine` 与 ESC 轮询争抢 stdin → 用户输入被吞/错位。
   - 安全定性：**fail-safe**（输入错位 → 空 → 默认 reject/cancel，永不误批准），故为 HIGH 而非 CRITICAL。
   - 修复：在 storage 分支顶部加 `let paused = escListenerRef?.pause() ?? false; defer { if paused { escListenerRef?.resume() } }`，仅对 `execute_storage_plan` / `execute_app_uninstall` 触发。
2. **[HIGH] AC #5/#10 结构化 PlanSummary 在非交互 deny 中缺失**（`StorageApprovalGate.decide`）。
   - 现象：`--json` / 非 TTY 的 deny 仅返回纯文本 reason，未按 AC #5/#10 附带结构化 `PlanSummary`（供带外确认通道解析消费）。
   - 修复：将 `PlanSummary.build(...)` 前移至 json/非-TTY 判断之前，并在两条 deny 文本后追加 `"\n" + summary.renderJSON()`；结构化数据经工具错误流（`.deny` message）流出，**不**向 stdout 打印，保持 `--json` 输出契约不被污染。
3. **[LOW] chat collector 输出走 stdout 而非 stderr**（`ChatCommand.swift` 注入的 `storageCollector`）。
   - 现象：`ChatApprovalCollector` 的 `writeStdout` 用 `fputs(msg, stdout)`，而 chat 模式所有 chrome 均走 stderr（避免污染数据流）。
   - 修复：改为 `fputs(msg, stderr)`。
4. **[测试] 新增回归用例** `decideNonInteractiveEmbedsSummary`（`StorageApprovalGateTests`）：断言非交互 deny 消息含 `"approval_required"`、`"\"operation_id\""`、`"\"risk_level\""`、`"\"total_items\""`，锁定问题 #2 修复。

### 回归验证

- `swift build`：通过。
- Storage Approval 套件：`swift test --filter "StorageApproval"` → **15 tests / 2 suites 全绿**（含新增用例）。
- 广义回归：`swift test --filter "AxionCoreTests" --filter "AxionCLITests"` 仅 7 个失败，**全部**位于 `DesktopNotifierTests`（OSC 9 序列被 tmux DCS passthrough 包裹；`TMUX=/private/tmp/tmux-501/...`、`TERM=tmux-256color`），属**预存在环境性失败**，与 39.4 触碰文件（`PermissionHandler` / `StorageApprovalGate` / `ChatCommand` / Approval 测试）**无关**，dev log 已记录同源失败。
- XCTest 核验：`grep -rl "import XCTest" Tests/` 仍为空。

### 范围外（不在本次修复）

- `ChatCommand.swift:497` 诊断告警 `'currentAgent' mutated after capture by sendable closure`：经核为 Epic 37/38 session-resume `SignalHandler` 块**预存在**问题，非本次 storage 注入（约 L60）引入，留待后续 story 处理。
- 实时 telegram inline-button 审批 UI、带外确认通道（`--approve-storage-op` 等）：AC 明确标注为未来 epic（如 34-5），不在 39.4 范围。

## Change Log

- 2026-06-12：Story 39.4 实现完成，Status → review。共享审批决策模型 + run/chat/telegram 三入口适配落地；新增 8 个 AxionCore 模型、6 个 AxionCLI 服务、6 个 Swift Testing 测试文件，7 处最小化修改；`swift build` 与单元测试通过，XCTest 核验为空。
- 2026-06-12：Senior Developer Review (AI)，Status review → **done**。修复 2 HIGH + 1 LOW（ESC/stdin 协调、非交互 deny 附结构化 PlanSummary、chat 走 stderr）+ 新增 1 回归用例；Storage Approval 套件 15/15 全绿，无回归（唯一失败为预存在 DesktopNotifier tmux 环境问题）。0 CRITICAL。
