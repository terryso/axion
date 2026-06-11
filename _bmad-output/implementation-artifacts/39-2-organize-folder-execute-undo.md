---
baseline_commit: 294fddd4418c7a1fc1b1a5e07697dfc6e5bd9f06
---

# Story 39.2: 整理目录执行与撤销

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->
<!-- 范围：执行已批准计划项（move / trash / createDirectory）+ manifest 草稿→补全 + 撤销。uninstallApp 执行与 support 数据扫描属于 39.3；run/chat/TG 统一审批语义（approvePlan/approveItem/rejectItem/cancel）属于 39.4。本 Story 永不永久删除（不存在 delete 动作）；破坏性动作默认走系统废纸篓（可恢复）。 -->

## Story

As a Mac 用户,
I want 批准计划后让 Axion 实际整理文件（移动 / 移入废纸篓）,
So that Downloads / Desktop 等目录能安全变干净，且我能撤销任何一步.

## Acceptance Criteria

> 本 Story 只覆盖「执行已批准项 + manifest + 撤销」。`uninstallApp` 的执行、support 数据扫描与清理、多候选 disambiguation 属于 39.3；`run`/`chat`/未来 `telegram` 的统一审批 UI/语义（`approvePlan`/`approveItem`/`rejectItem`/`cancel`）属于 39.4。本 Story 的执行工具接收「已确定要执行的项」——审批决策由调用方/入口在调用工具**之前**完成（run 走终端确认，交互模式走逐项确认；39.4 再统一结构化）。下列 AC 中标注【39.2】为本 Story 必须满足。

1. **【39.2】** **Given** 用户已批准一个含 `move` 项的计划
   **When** Agent 调用 `execute_storage_plan`，传入要执行的项
   **Then** 仅执行显式传入（即已批准）的项，文件被移动到 `targetPath`
   **And** 移动前自动创建缺失的中间目录（`createDirectory` 行为内嵌）
   **And** manifest 记录每项的原路径、目标路径、大小与执行结果

2. **【39.2】** **Given** 计划含 `trash` 项（如大文件、安装包、旧压缩包）
   **When** 执行该动作
   **Then** 通过 `FileManager.trashItem(at:resultingItemURL:)` 移入系统废纸篓（用户可恢复）
   **And** manifest 记录 `trashResultPath`（实际落位路径）
   **And** **绝不永久删除**（不存在 `delete` 动作，本 Story 也不接受任何形式的 `delete` 入参）

3. **【39.2】** **Given** 计划含 `createDirectory` 项
   **When** 执行该动作
   **Then** 创建目标目录（含中间目录，`withIntermediateDirectories: true`）
   **And** 目录已存在视为成功（幂等，`succeeded`），不报错

4. **【39.2】** **Given** 执行任何副作用前
   **When** `execute_storage_plan` 被调用
   **Then** **先写入 manifest 草稿**（`status = planned`），再逐项执行、逐项更新，最后置 `completed` / `partiallyFailed` / `cancelled`
   **And** 即使执行中断，磁盘上的 manifest 仍保留可审计信息（草稿 + 已完成项）

5. **【39.2】** **Given** `execute_storage_plan` 收到的 `source` 由 Agent 提供（可能编造 / 越界 / 已变化）
   **When** executor 执行前
   **Then** 对每项**重新校验**（与 `StoragePlanBuilder` 同口径的纵深防御）：(1) 落在某个 `scan_roots` 之下；(2) 未被 `StorageExclusions` 排除；(3) 路径存在；(4) 非 symlink 目标；(5) `action ∈ {move, trash, createDirectory, scanOnly}`——**拒绝 `uninstallApp`（属 39.3）与任何 `delete`**
   **And** 违规项丢弃并记入 `errors` / `excludedNotes`，**不执行**

6. **【39.2】** **Given** 某项执行失败（目标已存在 / 跨卷错误 / 权限不足 / 废纸篓不可用）
   **When** 其余项可成功
   **Then** 失败项记 `failed` + `reason`，其余项正常执行
   **And** manifest `status = partiallyFailed`，执行摘要列出 succeeded / skipped / failed 计数

7. **【39.2】** **Given** `move` 的 `targetPath` 已存在且与源不同
   **When** 执行该 move
   **Then** 该项 `failed`，`reason = target_exists`，**绝不覆盖**（无数据丢失）

8. **【39.2】** **Given** 操作已执行并生成 manifest
   **When** 用户请求撤销（`undo_storage_op`，可省略 `operation_id` 取最近一次可撤销操作）
   **Then** 按 manifest 逆向恢复：
   - `move` → 从 `targetPath` 移回 `sourcePath`（当 source 不存在、target 存在时）
   - `trash` → 从 `trashResultPath` 移回 `sourcePath`（仅当该路径仍在废纸篓）
   - `createDirectory` → 仅当目录为空时移除（避免删用户后续放入的内容）
   **And** 对无法恢复的项给出明确 `reason`（`source_already_exists` / `target_missing` / `item_no_longer_in_trash` / `directory_not_empty` 等）
   **And** 撤销结果写回 manifest（`undoneAt` + 每项 `undoResult`），可审计

9. **【39.2】** **Given** manifest 中某 `trash` 项已被用户清空废纸篓
   **When** 撤销
   **Then** 该项记 `notRestored` + `reason = item_no_longer_in_trash`，**不影响**其余可恢复项

10. **【39.2，非本 Story 范围，仅声明模型兼容】** `uninstallApp` 的执行、App bundle 移废纸篓、support 数据扫描与逐项清理——不在本 Story 实现（39.3）。本 Story 的执行工具若收到 `uninstallApp` 动作必须拒绝。

11. **【39.2，非本 Story 范围，仅声明模型兼容】** `run`/`chat`/`telegram` 的统一审批 UI/语义（结构化 `approvePlan`/`approveItem`/`rejectItem`/`cancel`）不在本 Story 实现（39.4）。本 Story 的 `execute_storage_plan` 入参即「已批准的执行集」。

12. **【39.2】** **Given** `dryrun` 模式
   **When** `AgentBuilder` 构建
   **Then** `execute_storage_plan` 与 `undo_storage_op` **不注册**（与 39.1 扫描工具一致的 `if !dryrun` 门控）
   **And** dryrun 模式永远不产生任何文件副作用

## Tasks / Subtasks

> 模块归属严格遵循 `project-context.md` 的模块边界：模型 → `AxionCore`；执行/manifest/撤销服务与 Agent 工具 → `AxionCLI`；`AxionHelper` 不参与文件系统逻辑（Epic 明确：「AxionHelper 仅在需要 Finder/App UI 操作时使用」）。

- [x] **T1：Manifest 模型（AxionCore）** (AC: #1, #4, #8)
  - [x] T1.1 `Sources/AxionCore/Models/Storage/StorageOpStatus.swift`：`StorageOpStatus`（`planned`/`executing`/`completed`/`partiallyFailed`/`cancelled`）—— manifest 级状态
  - [x] T1.2 `Sources/AxionCore/Models/Storage/StorageItemOutcome.swift`：`StorageItemOutcome`（`succeeded`/`failed`/`skipped`）—— 单项执行结果；`StorageUndoOutcome`（`restored`/`notRestored`/`skipped`）—— 单项撤销结果
  - [x] T1.3 `Sources/AxionCore/Models/Storage/StorageManifestItem.swift`：单条执行记录，字段：`action`、`sourcePath`、`targetPath?`、`trashResultPath?`、`sizeBytes`、`outcome`、`reason?`（失败/跳过原因）、`evidence?`（透传计划项证据）、`approvedAt?`（ISO8601）
  - [x] T1.4 `Sources/AxionCore/Models/Storage/StorageUndoResult.swift`：单条撤销记录，字段：`sourcePath`、`action`、`outcome`、`reason?`
  - [x] T1.5 `Sources/AxionCore/Models/Storage/StorageManifest.swift`：manifest 主体，字段对齐 Epic「Manifest 字段」表：`operationId`、`createdAt`、`completedAt?`、`surface`、`userRequest?`、`approvedByUser?`（审批摘要字符串，如 `"3 items approved via run"`）、`items: [StorageManifestItem]`、`status: StorageOpStatus`、`errors: [String]`、`summary?`；**撤销扩展（向前兼容）**：`undoneAt?`、`undoResults: [StorageUndoResult]?`
  - [x] T1.6 全部 `Codable + Equatable + Sendable`；**显式 snake_case `CodingKeys`**（工具/入口/远程面向契约，与 39.1 的 `StoragePlan` 一致）；`init(from:)` 用 `decodeIfPresent` + 默认值回退（向前兼容，39.3/39.4 会新增字段）

- [x] **T2：执行服务（AxionCLI，Protocol + 实现）** (AC: #1, #2, #3, #5, #6, #7)
  - [x] T2.1 `Sources/AxionCLI/Services/Storage/StorageExecuting.swift`（Protocol，测试注入用）：`func execute(_ request: ExecuteRequest) async -> ExecuteResult`；定义 `ExecutionItem`（`action`、`source`、`target?`、`reason?`、`evidence?`）、`ExecuteRequest`（`operationId`、`surface`、`scanRoots: [URL]`、`userRequest: String?`、`items: [ExecutionItem]`、`homeDirectory`、`storageOpsDir`）、`ExecuteResult`（`manifest: StorageManifest`、`succeeded/skipped/failed` 计数）
  - [x] T2.2 `Sources/AxionCLI/Services/Storage/StorageExecutor.swift`（实现，`final class ... : StorageExecuting, Sendable`）：
    - 注入 `StorageManifestStore`（草稿→补全）与 `StorageExclusions`（复用纯函数校验）
    - **草稿先行**：调用方传入 `operationId`/`createdAt`，executor 先写 `status = planned` 的 manifest 草稿到 `<storageOpsDir>/<operationId>.json`
    - **逐项重新校验**（纵深防御，镜像 `StoragePlanBuilder` 口径但独立实现）：scan_roots 前缀、exclusions `evaluate(path:)`、`FileManager.fileExists`、非 symlink 目标（`URLResourceValues.isSymbolicLink`）；`action` 白名单只含 `move`/`trash`/`createDirectory`/`scanOnly`，遇 `uninstallApp` 或任何 `delete` → 丢弃 + `errors`
    - **scanOnly**：不执行副作用，记 `skipped`
    - **createDirectory**：`FileManager.createDirectory(at:withIntermediateDirectories:true)`；已存在 → `succeeded`（幂等）；失败 → `failed` + reason
    - **move**：若 `targetPath == sourcePath` → `skipped`（`noop_source_is_target`）；若 target 已存在且 ≠ source → `failed`（`target_exists`，**不覆盖**）；否则 `FileManager.moveItem(at:to:)`（自动含中间目录创建：执行前 `createDirectory` 目标的父目录）；跨卷由 `moveItem` 自动处理；失败 → `failed` + `localizedDescription`
    - **trash**：`FileManager.trashItem(at:resultingItemURL:)`，捕获 `resultingItemURL` 存入 `trashResultPath`；废纸篓不可用（某些网络卷）→ `failed` + reason
    - **逐项写盘**：每完成一项即更新 manifest（`status = executing`）并原子覆写；全部完成后按 succeeded/failed 计数置 `completed`（无 failed）或 `partiallyFailed`（有 failed），回填 `completedAt`、`summary`
    - 状态机：`planned` → `executing` → `completed`/`partiallyFailed`（`cancelled` 由调用方/中断路径设置，本 Story executor 主体不主动 cancel）
  - [x] T2.3 executor 为 `final class`（持 `StorageManifestStore` 引用）或无状态 `struct` + 注入 store；**不**调用真实 Helper、不发起网络、不依赖 SDK Agent 循环

- [x] **T3：Manifest 存储（AxionCLI）** (AC: #4, #8)
  - [x] T3.1 `Sources/AxionCLI/Services/Storage/StorageManifestStore.swift`（`final class StorageManifestStore: Sendable`）：
    - `init(storageOpsDir: String, homeDirectory: String = NSHomeDirectory())`：路径用 `StorageExclusions.standardize(storageOpsDir, home:)` 展开 `~`
    - `func save(_ manifest: StorageManifest) throws`：确保目录存在（`createDirectory(withIntermediateDirectories:true)`），原子覆写 `<dir>/<operationId>.json`（`data.write(to:options:.atomic)`，复用 `axionSortedEncoder`；与 `AxionFileIO.persistRunRecord` 同模式）
    - `func load(operationId: String) -> StorageManifest?`：复用 `loadDecodableFile`（`AxionFileIO.swift`），缺失/解码失败返回 nil
    - `func listRecent(limit: Int = 20) -> [StorageManifest]`：列 `.json` 文件，按 `modificationDate` 降序解码返回（供「撤销最近一次」）
    - `func mostRecentUndoable() -> StorageManifest?`：`listRecent` 中取首个 `status ∈ {completed, partiallyFailed}` 且 `undoneAt == nil` 的
    - 测试用临时目录注入 `storageOpsDir`（镜像 `MemoryToolTests` 的 `makeTempDir()`/`cleanup()` 模式）

- [x] **T4：撤销服务（AxionCLI，Protocol + 实现）** (AC: #8, #9)
  - [x] T4.1 `Sources/AxionCLI/Services/Storage/StorageUndoing.swift`（Protocol）：`func undo(_ request: UndoRequest) async -> UndoResult`；`UndoRequest`（`operationId?`（nil=最近可撤销）、`storageOpsDir`、`homeDirectory`）；`UndoResult`（`manifest: StorageManifest`、`restored/notRestored/skipped` 计数）
  - [x] T4.2 `Sources/AxionCLI/Services/Storage/StorageUndoService.swift`（实现）：
    - 经 `StorageManifestStore` 加载 manifest（`operationId` 缺省走 `mostRecentUndoable()`；找不到 → 返回带 `errors = ["no_undoable_manifest"]` 的结果）
    - **逆序**遍历 `items`（后执行的先还原），对每项：
      - `move`：若 `sourcePath` 已存在 → `notRestored`（`source_already_exists`，不覆盖）；若 `targetPath` 不存在 → `notRestored`（`target_missing`）；否则 `FileManager.moveItem(target→source)`
      - `trash`：若 `sourcePath` 已存在 → `notRestored`（`source_already_exists`）；若 `trashResultPath` 不存在 → `notRestored`（`item_no_longer_in_trash`，AC #9）；否则 `FileManager.moveItem(trashResultPath→sourcePath)`
      - `createDirectory`：仅当目录**为空**（`contentsOfDirectory` 为空）时 `FileManager.removeItem`，否则 `notRestored`（`directory_not_empty`）
      - `scanOnly`/已 `failed`/`skipped` 的原项 → 撤销 `skipped`（无可恢复对象）
    - 写回 manifest：`undoneAt = nowISO8601`，`undoResults` 逐项记录，原子覆写
    - 失败的恢复项**不回滚**已成功恢复项（best-effort，逐项独立）

- [x] **T5：`execute_storage_plan` Agent 工具（AxionCLI，有副作用）** (AC: #1–#7, #12)
  - [x] T5.1 `Sources/AxionCLI/Tools/ExecuteStoragePlanTool.swift`：`final class ExecuteStoragePlanTool: ToolProtocol, Sendable`，`name = "execute_storage_plan"`，**`isReadOnly = false`**（首个有副作用的 storage 工具）
  - [x] T5.2 `description`（中文）：明确「执行用户**已确认**的整理项；只接受 move/trash/create_directory/scan_only；永不 delete；uninstall_app 属另一工具（39.3）；执行前写 manifest 草稿，可经 undo_storage_op 撤销」
  - [x] T5.3 `inputSchema`（`ToolInputSchema` 字典，snake_case）：
    - `operation_id`（string，required）
    - `scan_roots`（string[]，required，用于重新校验 source 范围）
    - `items`（array，required）：每项 `{action(enum: scan_only/move/trash/create_directory), source, target?, size_bytes?, reason?, evidence?}`
    - `surface`（enum: run/chat，默认 run）
    - `user_request`（string，可选，原任务，写入 manifest）
  - [x] T5.4 `call(input:context:)`：用 `ToolResultHelper` 校验入参（`params` 为对象、`operation_id`/`scan_roots`/`items` 必填且非空）→ 构造 `ExecuteRequest`（`operationId` 透传，`storageOpsDir` 取 `config.storageOpsDir`，`homeDirectory = NSHomeDirectory()`）→ 调注入的 `StorageExecuting` → 用 `ToolResultHelper.encodeResult`（共享 `axionSortedEncoder`）返回 manifest（含状态 + succeeded/skipped/failed + errors + 摘要）
  - [x] T5.5 注入 executor 构造（`init(executor: StorageExecuting = StorageExecutor(...), config: StorageConfig = .default)`），便于单测注入 `MockStorageExecutor`
  - [x] T5.6 executor 内部生成 `createdAt`（`ISO8601DateFormatter`）与 `approvedByUser` 摘要；`operationId` 由调用方（Agent 透传自 `propose_storage_plan`）提供，保持与计划链路一致

- [x] **T6：`undo_storage_op` Agent 工具（AxionCLI，有副作用）** (AC: #8, #9, #12)
  - [x] T6.1 `Sources/AxionCLI/Tools/UndoStorageOpTool.swift`：`final class UndoStorageOpTool: ToolProtocol, Sendable`，`name = "undo_storage_op"`，**`isReadOnly = false`**
  - [x] T6.2 `description`（中文）：明确「按 manifest 逆向恢复上一次整理（move 移回、trash 从废纸篓移回、空目录移除）；无法恢复项给出原因；省略 operation_id 时撤销最近一次可撤销操作」
  - [x] T6.3 `inputSchema`：`operation_id`（string，**可选**，省略取最近）、`surface`（默认 run）
  - [x] T6.4 `call(input:context:)`：校验入参 → 构造 `UndoRequest` → 调注入 `StorageUndoing` → 返回 manifest（含 `undoneAt` + restored/notRestored/skipped 计数 + 不可恢复原因）；无可撤销 → 返回 `ToolResultHelper.errorResult(error: "no_undoable_manifest", ...)`
  - [x] T6.5 注入 undo service 构造，便于单测注入 Mock

- [x] **T7：AgentBuilder 注册（AxionCLI）** (AC: #12)
  - [x] T7.1 在 `Sources/AxionCLI/Services/AgentBuilder.swift`（约 L166–L173，39.1 的 `if !dryrun` storage 注册块）**追加**注册：
    ```swift
    // Storage execution + undo (Story 39.2) — side-effect tools, gated under !dryrun.
    // Execution only runs the items the user explicitly approved (approval resolved by
    // the surface before calling the tool); never permanent delete; undo via manifest.
    if !dryrun {
        let manifestStore = StorageManifestStore(storageOpsDir: config.storage?.storageOpsDir ?? StorageConfig.default.storageOpsDir)
        agentTools.append(ExecuteStoragePlanTool(
            executor: StorageExecutor(manifestStore: manifestStore),
            config: config.storage ?? .default
        ))
        agentTools.append(UndoStorageOpTool(undoer: StorageUndoService(manifestStore: manifestStore)))
    }
    ```
  - [x] T7.2 **不修改** `Sources/AxionCore/Constants/ToolNames.swift`（那是 Helper MCP 工具表；`execute_storage_plan`/`undo_storage_op` 是 CLI 端 Agent 工具，bare name，与 `MemoryTool`/`StorageScanTool` 一致）

- [x] **T8：单元测试（Swift Testing，禁止真实外部依赖）** (AC: 全部)
  - [x] T8.1 `Tests/AxionCoreTests/Models/Storage/StorageManifestTests.swift`：`StorageManifest`、`StorageManifestItem`、`StorageUndoResult`、`StorageOpStatus`/`StorageItemOutcome`/`StorageUndoOutcome` 的 Codable round-trip + 缺失字段默认回退（含 `undoneAt`/`undoResults`/`trashResultPath` 可选字段向前兼容）
  - [x] T8.2 `Tests/AxionCLITests/Storage/StorageExecutorTests.swift`：用**临时目录**造源/目标树（镜像 `MemoryToolTests` 的 `makeTempDir()`/`cleanup()` + `defer`），注入 `StorageManifestStore(tempDir)`：
    - move 成功（含自动创建中间目录）、move `target_exists` 不覆盖、move `noop_source_is_target` 跳过
    - trash 成功并记录 `trashResultPath`（断言文件移入 `~/.Trash` 或临时卷的废纸篓；测试用临时 home 可控）
    - createDirectory 幂等（已存在 → succeeded）
    - scanOnly → skipped（无副作用）
    - 违规 source（scan_roots 外、被 exclusions 排除、不存在、symlink 目标、`uninstallApp`/`delete` 动作）→ 丢弃 + errors，不执行
    - 部分失败 → `partiallyFailed` + 计数；草稿先行（断言执行前 manifest 已落盘 status=planned）
  - [x] T8.3 `Tests/AxionCLITests/Storage/StorageManifestStoreTests.swift`：save/load round-trip、`listRecent` 排序、`mostRecentUndoable` 过滤（跳过 `undoneAt != nil` 与非终态）、临时目录隔离
  - [x] T8.4 `Tests/AxionCLITests/Storage/StorageUndoServiceTests.swift`（临时目录 + 真实 `moveItem`/`trashItem`/`removeItem`，属可接受的真实文件系统测试，非「真实外部依赖」禁项）：
    - move 撤销（target→source）、source 已存在不覆盖、target 缺失 notRestored
    - trash 模拟：先 trashItem 取 `trashResultPath`，再 undo 移回；手动删 `trashResultPath` 模拟清空废纸篓 → `item_no_longer_in_trash`
    - createDirectory 非空目录不删除（`directory_not_empty`）、空目录移除
    - 省略 `operationId` → 取 `mostRecentUndoable`；无可撤销 → 错误结果
    - undo 写回 manifest（`undoneAt` + `undoResults`）可重新加载验证
  - [x] T8.5 `Tests/AxionCLITests/Storage/ExecuteStoragePlanToolTests.swift`：注入 `MockStorageExecutor: StorageExecuting`（返回预设 `ExecuteResult`），验证入参校验（缺 operation_id/scan_roots/items → errorResult）、`action` 白名单、`ToolResult` JSON 形状（含 status/计数/errors）、错误走 `ToolResultHelper`
  - [x] T8.6 `Tests/AxionCLITests/Storage/UndoStorageOpToolTests.swift`：注入 `MockStorageUndoer: StorageUndoing`，验证省略/指定 operation_id 路径、无可撤销 errorResult、返回 JSON 形状
  - [x] T8.7 运行：`swift test --filter "AxionCoreTests" --filter "AxionCLITests"`（开发完成后只跑单元测试，不跑 Integration/E2E）。若子环境 SwiftPM sandbox 拒绝 `~/.axion` 或模块缓存写入，参考 39.1 调试日志用 `CLANG_MODULE_CACHE_PATH=/private/tmp/axion-clang-module-cache swift test --disable-sandbox --filter "Storage"` 诊断（主编排环境 `make test` 为准）

## Dev Notes

### 关键架构约束（必须遵循）

- **模块边界（硬性）**：`AxionCore`（纯模型，零外部依赖，禁止 `import OpenAgentSDK`）← `AxionCLI`（服务/工具/命令）。执行引擎、manifest 存储、撤销服务、Agent 工具全部在 **`AxionCLI`**；manifest 模型在 **`AxionCore/Models/Storage/`**。**`AxionHelper` 不承担任何文件系统逻辑**（Epic 明确：「AxionHelper 仅在需要 Finder/App UI 操作时使用」）。**禁止 `AxionCLI` import `AxionHelper`**（两者仅 MCP stdio 通信）。
- **Agent 工具 ≠ Helper MCP 工具**：`execute_storage_plan` / `undo_storage_op` 是 **CLI 端 Agent 工具**（`ToolProtocol`，bare name），在 `AgentBuilder.swift` 注册，**不要**加入 `Sources/AxionCore/Constants/ToolNames.swift`（那是 Helper MCP 工具表，工具名带 `mcp__axion-helper__` 前缀）。参考 `MemoryTool.swift`、`StorageScanTool.swift`：它们都不在 `ToolNames.swift`。
- **首个有副作用的 storage 工具**：`isReadOnly = false`（与 39.1 的 `storage_scan`/`propose_storage_plan` 的 `true` 区分）。注册门控 `if !dryrun`（与 39.1 一致），确保 dryrun 永不副作用（AC #12）。
- **工具命名**：snake_case，正则 `^[a-z][a-z0-9_]*$`（`execute_storage_plan`、`undo_storage_op`）。入参字段同样 snake_case（`operation_id`、`scan_roots`、`target`、`size_bytes`）。
- **错误处理**：统一用 `AxionError` 枚举 + `MCPErrorPayload`（`error`/`message`/`suggestion`），**不新建错误类型体系**。工具结果 JSON 用 `ToolResultHelper.encodeResult()`/`errorResult()`（共享 `axionSortedEncoder`，`.sortedKeys`）。单项失败**不**抛异常中断整批——记入 manifest `errors` + item `reason`，继续其余项（AC #6）。
- **输出**：**禁止 `print()`**（反模式 #3）。Agent 流式输出走 `SDKTerminalOutputHandler`/`SDKJSONOutputHandler`；交互模式走 `ChatOutputFormatter`。本 Story 的 manifest 摘要可复用 `StoragePlanFormatter.formatBytes`（39.1 已提为 internal 共享）渲染字节数；结构化结果走工具结果 JSON。
- **JSON 字段命名**：manifest 及其 item/undoResult 是**工具/入口/远程面向契约**，按 Epic「结构化模型、不绑定终端文本」要求用 **显式 snake_case `CodingKeys`**（对齐 39.1 的 `StoragePlan`/`StoragePlanItem` 与 MCP 参数 snake_case、未来 Telegram 字段）。
- **ID/时间戳**：运行时 Swift 可正常用 `UUID()` / `ISO8601DateFormatter` / `Date()`。`operationId` 由 Agent 从 `propose_storage_plan` 的计划透传（保持与计划链路一致，便于审计关联）；executor 生成 `createdAt`/`completedAt`/`undoneAt`。**注意：BMAD 编排脚本里禁用 `Date.now()`/`Math.random()`，但那是脚本限制，不影响你写的 Swift 运行时代码**（39.1 已注明）。

### 安全核心：永不永久删除 + 纵深防御重校验

- **不存在 `delete` 动作**：`StorageAction` 枚举无 `delete`（39.1 已确认）。本 Story executor 的 `action` 白名单只含 `move`/`trash`/`createDirectory`/`scanOnly`；任何其他值（含 `uninstallApp`——属 39.3——和任何形似 delete 的入参）一律丢弃 + 记 `errors`，**绝不**调用 `FileManager.removeItem` 做永久删除。`removeItem` **仅**用于撤销 `createDirectory` 的空目录，且先断言目录为空（AC #8）。
- **trash = 系统废纸篓（可恢复）**：用 `FileManager.trashItem(at:resultingItemURL:)`，**必须**捕获 `resultingItemURL` 存入 manifest `trashResultPath`（撤销依赖它）。某些网络卷无废纸篓 → `trashItem` 抛错 → item `failed` + reason，不退化为删除。
- **执行前重校验**（AC #5，纵深防御）：`execute_storage_plan` 的入参来自 Agent（不可信）。即使 39.1 的 `StoragePlanBuilder` 已校验过，executor 必须**独立**再校验每项 source：(1) `scan_roots` 前缀包含；(2) `StorageExclusions.evaluate(path:)` 返回 included；(3) `FileManager.fileExists`；(4) `URLResourceValues.isSymbolicLink == false`（不跟随 symlink 目标，与 39.1 AC #2 一致）。复用 `StorageExclusions`（纯函数），不要新写排除逻辑。
- **草稿先行**（AC #4，Epic「manifest 必须在执行前创建草稿」）：executor 第一件事是写 `status = planned` 的 manifest 到磁盘，再开始任何 `moveItem`/`trashItem`。逐项执行后更新为 `executing` 并原子覆写。这样进程中断也留审计线索。
- **不覆盖**（AC #7）：`move` 遇 `target_exists`（target 存在且 ≠ source）→ `failed`，**不**调用 `moveItem`（`moveItem` 默认会抛错而非覆盖，但显式前置检查给出清晰 reason 更好）。

### 复用现有代码（避免重复造轮子）

- **`Sources/AxionCLI/Tools/ToolResultHelper.swift`**：入参校验 + `ToolResult` 编码 helper（`requireStringParam`、`errorResult`、`encodeResult`）。`execute_storage_plan`/`undo_storage_op` 的入参校验与结果编码走这里，**不要新写**。
- **`Sources/AxionCLI/AxionFileIO.swift`**：`sanitizeFileName()`、`loadDecodableFile()`（manifest load 直接用）、原子写模式（参考 `persistRunRecord` 的 `data.write(to:options:.atomic)`）。manifest 存储的 save/load 照此办理。
- **`Sources/AxionCLI/Services/Storage/StorageExclusions.swift`**：`evaluate(path:)`（纯函数排除判定）+ `standardize(_:home:)`（展开 `~`、标准化路径）。executor 重校验与 manifest store 路径展开**直接复用**，不要重复实现排除/路径逻辑。
- **`Sources/AxionCLI/Services/Storage/StoragePlanFormatter.swift`**：`formatBytes(_:)`（39.1 已提为 internal 共享）—— manifest 摘要字节数渲染复用，不要重复。
- **`Sources/AxionCLI/Tools/ProposeStoragePlanTool.swift` / `StorageScanTool.swift`**：CLI Agent 工具的完整范本——`ToolProtocol` + `inputSchema` 字典（snake_case）+ `call(input:context:) async -> ToolResult` + `ToolContext(cwd:toolUseId:)` + `ToolResultHelper` 用法。`execute_storage_plan` 照此结构，仅 `isReadOnly = false`、`action` 白名单不同。
- **`Sources/AxionCLI/Services/AgentBuilder.swift:166-173`**：39.1 的 storage 工具注册块——T7 在此**追加**，不要新开注册点。
- **`StoragePlanItem` / `StoragePlan`（AxionCore，39.1 已建）**：manifest item 字段与 `StoragePlanItem` 高度同构（action/source/target/sizeBytes/evidence）。可复用 `StorageAction`/`RiskLevel`/`StorageEvidence` 枚举/结构，但 manifest item 是**独立模型**（额外含 `outcome`/`trashResultPath`/`approvedAt`），不要把执行结果字段塞回 `StoragePlanItem`（污染计划模型）。
- **临时目录测试模式**：`Tests/AxionCLITests/Memory/MemoryToolTests.swift` 的 `makeTempDir()`/`cleanup()` + `defer`——executor/store/undo 测试直接照搬（39.1 的 `StorageScanServiceTests`/`StorageFeatureTests` 已用此模式，属可接受的真实文件系统测试，非禁止的「真实外部依赖」）。

### 执行语义细节（防坑）

- **`move` 中间目录**：`FileManager.moveItem` 不自动创建目标的**父目录**。executor 执行 move 前必须 `createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)`（失败则 item failed）。这也顺带满足 Epic「创建目标目录」范围。
- **`move` 跨卷**：`moveItem` 自动处理跨卷（copy+delete）。撤销时 `moveItem(target→source)` 同样自动处理。无需特殊代码。
- **`move` 幂等/无操作**：`targetPath == sourcePath`（标准化后）→ `skipped`（`noop_source_is_target`），不报错。
- **`trashItem` 的 `resultingItemURL`**：废纸篓可能因重名加后缀（如 `foo (1).txt`），**必须**用 `resultingItemURL.path` 而非原文件名推断 `trashResultPath`。`trashItem` 签名是 `trashItem(at:resultingItemURL:)`，传入 `var result: NSURL?` 出参（Swift 中用 `var resultingURL: NSURL?` + `try fm.trashItem(at: url, resultingItemURL: &resultingURL)`）。
- **`createDirectory` 幂等**：目录已存在时 `createDirectory(withIntermediateDirectories:true)` **不抛错**（视为成功）。但若路径存在且是**文件**（非目录）→ 抛错 → item `failed` + reason。
- **`status` 状态机**：`planned`（草稿落盘）→ `executing`（首项开始）→ `completed`（全部 succeeded/skipped，0 failed）/ `partiallyFailed`（≥1 failed）。`cancelled` 预留给未来中断路径（本 Story executor 主体不主动置 cancelled，但模型必须支持）。撤销不改变 `status`，只追加 `undoneAt`/`undoResults`。
- **manifest 原子覆写**：每次更新（逐项、完成、撤销）都 `data.write(to:options:.atomic)` 整文件覆写（与 `persistRunRecord` 一致）。不用追加写——manifest 是整体 JSON。
- **`scanOnly` 执行**：作为「已批准但无副作用」项，executor 记 `skipped`（outcome），不写 `targetPath`/`trashResultPath`。撤销时也 `skipped`（无可恢复对象）。

### 测试标准（CLAUDE.md 强制）

- **全部用 Swift Testing**（`import Testing`、`@Suite`、`@Test`、`#expect`），**禁止 XCTest**。
- **单元测试禁止真实外部依赖**：`AgentBuilder.build()`、`RunOrchestrator.execute()`、MCP 连接、Helper 进程、osascript 通知等必须 Mock。executor/store/undo 用**临时目录**（`MemoryToolTests`/39.1 `StorageFeatureTests` 既有模式，属可接受的真实文件系统测试）；工具测试注入 `MockStorageExecutor`/`MockStorageUndoer`（实现 `StorageExecuting`/`StorageUndoing` 协议）。
- **用 Protocol 抽象 + Mock**：`StorageExecuting` + `MockStorageExecutor`；`StorageUndoing` + `MockStorageUndoer`。executor/undo service 的真实 `FileManager` 操作用临时目录隔离（可控、确定、可并行）。
- **Codable round-trip**：所有 AxionCore manifest 模型必须有（参考项目既有 `test_xxx_roundTrip` + 39.1 `StorageModelsTests` 模式），含可选字段缺失向前兼容。
- **禁止 bogus 测试**：测试必须调用被测方法/真实 `FileManager` 操作，不允许纯字面量断言（反模式 #10）。
- 测试目录镜像源结构：`Tests/AxionCoreTests/Models/Storage/`（manifest 模型）、`Tests/AxionCLITests/Storage/`（executor/store/undo/工具，与 39.1 的 `StorageFeatureTests.swift` 同目录）。
- 运行命令（只跑单元测试）：`swift test --filter "AxionCoreTests" --filter "AxionCLITests"`。子环境 sandbox 写入受限时参考 39.1 调试手法（见 T8.7），主编排环境 `make test` 为最终判据。

### Project Structure Notes

- 新增目录与文件归属（对齐四目标结构与命名规范，目录名 PascalCase 复数）：
  ```
  Sources/AxionCore/Models/Storage/         # 纯模型（零依赖）
  ├── StorageOpStatus.swift                 # manifest 级状态枚举
  ├── StorageItemOutcome.swift              # 单项执行/撤销结果枚举
  ├── StorageManifestItem.swift             # 单条执行记录
  ├── StorageUndoResult.swift               # 单条撤销记录
  └── StorageManifest.swift                 # manifest 主体（含 undo 扩展字段）

  Sources/AxionCLI/Services/Storage/        # 执行/存储/撤销服务
  ├── StorageExecuting.swift                # Protocol + ExecuteRequest/Result（DI 用）
  ├── StorageExecutor.swift                 # 执行实现（move/trash/createDirectory + 草稿先行）
  ├── StorageManifestStore.swift            # manifest save/load/listRecent/mostRecentUndoable
  ├── StorageUndoing.swift                  # Protocol + UndoRequest/Result（DI 用）
  └── StorageUndoService.swift              # 撤销实现（逆向恢复）

  Sources/AxionCLI/Tools/
  ├── ExecuteStoragePlanTool.swift          # 有副作用执行工具（ToolProtocol, isReadOnly=false）
  └── UndoStorageOpTool.swift               # 有副作用撤销工具（ToolProtocol, isReadOnly=false）

  Tests/AxionCoreTests/Models/Storage/      # manifest 模型 round-trip
  ├── StorageModelsTests.swift              # (39.1 已存在，追加 manifest 用例或新建文件)
  └── StorageManifestTests.swift            # manifest/item/undoResult round-trip + 向前兼容

  Tests/AxionCLITests/Storage/              # executor/store/undo/工具测试（与 39.1 同目录）
  ├── StorageExecutorTests.swift
  ├── StorageManifestStoreTests.swift
  ├── StorageUndoServiceTests.swift
  ├── ExecuteStoragePlanToolTests.swift
  └── UndoStorageOpToolTests.swift
  ```
- **不修改 `ToolNames.swift`**（Helper MCP 工具表，与 CLI Agent 工具无关）。
- **不修改 `AxionHelper`**（文件执行不属于 Helper 职责；Epic 明确 Helper 仅在需要 Finder/App UI 操作时使用，本 Story 的 move/trash 是纯文件系统操作，走 `FileManager` 即可）。
- **不修改 39.1 的只读工具**（`StorageScanTool`/`ProposeStoragePlanTool` 保持只读；本 Story 只新增执行/撤销工具）。
- **可选接线（不阻塞 AC）**：39.1 review follow-up 提到 `StoragePlanFormatter` 在 `Sources/` 内无生产调用方（仅测试）。本 Story 的 manifest 摘要可顺手调用 `StoragePlanFormatter.formatBytes`（让 formatter 拥有真实调用方），但**接线到 `SDKTerminalOutputHandler`/`SDKJSONOutputHandler` 非本 Story 必须**（工具返回结构化 JSON + SDK 渲染已满足可观测性）。
- 已检测冲突/差异：无。`architecture.md` 尚未包含 Epic 39 章节（39.1 grep 确认）；本 Story 在 39.1 奠定的 `Storage*` 模型/服务基础上扩展，严格遵守 `project-context.md` 全局约束。`StorageAction` 枚举已含 `move`/`trash`/`createDirectory`（39.1 声明、39.2 实现），无需新增动作枚举。

### Previous Story Intelligence

- 本 Story 紧接 **Story 39.1**（`39-1-safe-file-scan-plan-model`，已 `done`）。39.1 已交付：`StoragePlan`/`StoragePlanItem`/`StorageAction`/`RiskLevel`/`StorageEvidence`/`DataRisk`/`StorageConfig`（AxionCore 模型）、`StorageScanService`/`StorageExclusions`/`StoragePlanBuilder`/`StoragePlanFormatter`（AxionCLI 服务）、`storage_scan`/`propose_storage_plan` 只读工具、`AgentBuilder` 注册（`if !dryrun`）、`AxionConfig.storage` 扩展。
- **直接复用 39.1 成果**：
  - `StorageAction` 枚举（`move`/`trash`/`createDirectory`/`uninstallApp`/`scanOnly`）—— 本 Story 实现 `move`/`trash`/`createDirectory`/`scanOnly` 的执行，`uninstallApp` 留给 39.3。
  - `StorageExclusions.evaluate(path:)` + `standardize(_:home:)` —— executor 重校验与路径展开直接复用。
  - `StorageConfig.storageOpsDir`（默认 `~/.axion/storage-ops/`）—— 39.1 仅定义，本 Story 真正使用为 manifest 存储目录。
  - `ToolResultHelper` / `ToolProtocol` / `inputSchema` 工具范式 —— 执行/撤销工具照搬。
  - `StoragePlanFormatter.formatBytes` —— manifest 摘要复用。
- **39.1 review follow-ups（与本 Story 相关，留意但不强制）**：
  - [LOW] AC #5 输出管线未接线 → 本 Story 可顺手让 formatter 有真实调用方（见上文「可选接线」），非必须。
  - [LOW] bundle 体积口径（`totalFileSize` 对目录可能 nil）→ 本 Story 不依赖 bundle 体积做执行决策（执行按路径），不受影响；若需展示可沿用 39.1 口径。
- **可借鉴的最近代码模式**（39.1 调试日志）：
  - 子环境 SwiftPM sandbox 会拒绝 `~/.axion` 与模块缓存写入（`Operation not permitted`）→ manifest 测试用**注入临时目录**而非真实 `~/.axion`，规避 sandbox；主编排环境 `make test` 为最终判据。
  - `CLANG_MODULE_CACHE_PATH=/private/tmp/axion-clang-module-cache swift test --disable-sandbox --filter "Storage"` 是子环境诊断手法。

### Git Intelligence Summary

最近提交（39.1 刚合入，与本 Story 直接相关）：
- `294fddd feat(story-39.1): 安全文件扫描与计划模型`（本 Story 的直接前置，提供全部模型与服务基础）
- `34b7ce9 docs(epic-39): add Mac storage/file/app management epic and update sprint status`（Epic 立项）
- `b83908b chore: ignore .bak backup files` / `374be9b chore(automator): upgrade bmad-story-automator skill core` / `cfb7507 docs: add CHANGELOG and Codex workspace config`（工具链/文档，无代码影响）
- `54dbaee deps: bump open-agent-sdk-swift to 0.8.2`（SDK 依赖，`ToolProtocol`/`ToolInputSchema`/`ToolResult`/`ToolContext` 来自 `import OpenAgentSDK`，与 39.1 一致）
- 可借鉴结论：SDK 为本地 path 依赖（`../open-agent-sdk-swift`）；storage 工具链已建立范式，本 Story 沿用。

### Latest Tech Information

- **`FileManager.trashItem(at:resultingItemURL:)`**：macOS 10.8+，移入系统废纸篓（`.Trash` 或 APFS 废纸篓），**可恢复**。`resultingItemURL` 出参返回实际落位路径（可能因重名加后缀）。网络卷无废纸篓时抛 `NSFileNoSuchFileError` 或 `NSFileWriteUnsupportedSchemeError` → 必须 catch。本 Story **唯一**允许的「删除」语义就是 trash（可恢复），**永不** `removeItem` 做永久删除。
- **`FileManager.moveItem(at:to:)`**：同卷为 rename（瞬时），跨卷为 copy+delete（自动）。目标**父目录**不存在时抛错 → executor 须先 `createDirectory` 父目录。目标**自身**存在时抛 `NSFileWriteFileExistsError` → 前置检查给 `target_exists` reason。
- **`FileManager.createDirectory(at:withIntermediateDirectories:attributes:)`**：`withIntermediateDirectories: true` 等价 `mkdir -p`。目录已存在**不抛错**（幂等）；路径存在且是文件则抛错。
- **`FileManager.removeItem(at:)`**：永久删除。本 Story **仅**用于撤销 `createDirectory` 的**空**目录（先 `contentsOfDirectory(atPath:)` 断言为空），**禁止**用于其他场景。
- **原子写**：`Data.write(to:options:.atomic)` 先写临时文件再 rename，避免半写。manifest 每次更新都用此（与 `AxionFileIO.persistRunRecord` 一致）。
- **`URLResourceValues.isSymbolicLink`**：检测 symlink，executor 重校验拒绝 symlink 目标（与 39.1 AC #2 一致，不跟随）。
- 无需引入任何新第三方依赖；纯 Foundation + OpenAgentSDK + AxionCore。

### Project Context Reference

- 完整项目约束见 `_bmad-output/project-context.md`（持久化事实），重点：技术栈（Swift 6.1+ / macOS 14+ / SPM / OpenAgentSDK 本地依赖）、命名三套规则、import 顺序、模块边界（AxionCore ← AxionCLI，Helper 不参与文件系统逻辑）、MCP 工具规则（CLI Agent 工具 bare name，不进 `ToolNames.swift`）、错误处理（`AxionError` + `ToolResultHelper`）、测试规则（Swift Testing 强制、只跑单元测试、Protocol+Mock、临时目录可接受）、反模式清单（#3 禁 print、#4 MCP 字段 snake_case、#9 不新建错误类型、#10 禁 bogus 测试、#20 Chat/ 纯函数）。
- Epic 全文与 manifest 字段表见 `docs/epics/epic-39-mac-storage-file-app-management.md`（§4 安全确认与回滚 / Manifest 字段表 / Manifest 存储）。
- 39.1 交付细节见 `_bmad-output/implementation-artifacts/39-1-safe-file-scan-plan-model.md`。

### References

- [Source: docs/epics/epic-39-mac-storage-file-app-management.md#Story 拆分建议 — Story 39.2]（范围与 As-a/I-want/So-that）
- [Source: docs/epics/epic-39-mac-storage-file-app-management.md#1. 按内容整理文件或目录]（「用户批准整理计划 → 执行移动 → 可撤销 manifest → 成功/跳过/失败摘要」AC）
- [Source: docs/epics/epic-39-mac-storage-file-app-management.md#2. 查找和处理大文件]（「默认移动到废纸篓 / 不执行永久删除」AC）
- [Source: docs/epics/epic-39-mac-storage-file-app-management.md#4. 安全确认与回滚]（计划字段 / 操作项字段 / Manifest 字段 / Manifest 存储 / 撤销 AC → 模型与执行 schema 来源）
- [Source: docs/epics/epic-39-mac-storage-file-app-management.md#安全边界]（排除路径清单、高风险确认策略 → executor 重校验）
- [Source: docs/epics/epic-39-mac-storage-file-app-management.md#建议实现分层]（AxionCLI 服务层负责执行/manifest/回滚；AxionHelper 不承担核心文件系统逻辑）
- [Source: _bmad-output/project-context.md#架构规则 — 模块依赖]（AxionCore ← AxionCLI，Helper 不参与）
- [Source: _bmad-output/project-context.md#MCP 工具规则 / 关键反模式]（工具注册、命名、错误处理、禁 print、snake_case 字段、不新建错误类型）
- [Source: _bmad-output/implementation-artifacts/39-1-safe-file-scan-plan-model.md]（前置 Story：模型/服务/工具范式、StorageAction/StorageExclusions/StorageConfig 复用、调试手法）
- [Source: Sources/AxionCore/Models/Storage/StorageEnums.swift]（`StorageAction`/`RiskLevel`/`StorageEvidence`/`DataRisk` 复用）
- [Source: Sources/AxionCore/Models/Storage/StorageConfig.swift]（`storageOpsDir` 默认 `~/.axion/storage-ops/`）
- [Source: Sources/AxionCLI/Services/Storage/StorageExclusions.swift]（`evaluate(path:)` + `standardize(_:home:)` 复用）
- [Source: Sources/AxionCLI/Services/Storage/StoragePlanBuilder.swift]（重校验口径参考：scan_roots/exclusions/exists/symlink）
- [Source: Sources/AxionCLI/Tools/ProposeStoragePlanTool.swift]（CLI Agent 工具 + `ToolResultHelper` 范本）
- [Source: Sources/AxionCLI/Tools/StorageScanTool.swift]（`ToolInputSchema` snake_case + `ScanResponse` 范本）
- [Source: Sources/AxionCLI/Tools/ToolResultHelper.swift]（入参校验 + `encodeResult`/`errorResult`）
- [Source: Sources/AxionCLI/AxionFileIO.swift]（`loadDecodableFile`/原子写/`sanitizeFileName` 复用）
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift:166-173]（39.1 storage 注册块，T7 追加点）
- [Source: Tests/AxionCLITests/Storage/StorageFeatureTests.swift]（39.1 临时目录 + Mock 测试范本）
- [Source: CLAUDE.md#测试框架 / 测试执行规则 / 单元测试必须 Mock]（Swift Testing 强制、只跑单元测试、Protocol+Mock、临时目录可接受）

## Dev Agent Record

### Agent Model Used

GLM-5.1（环境声明模型）

### Debug Log References

- 子环境构建诊断：`swift build --target AxionCore`（首次创建 5 个 AxionCore manifest 模型后刷新模块索引，消除 SourceKit「Cannot find type 'StorageManifest'」stale 诊断）；`swift build --target AxionCLI` 验证服务/工具/注册全量编译。
- 修复两处编译错误：(1) `StorageUndoService` 的 `undoResults` 由 `[StorageUndoResult?]` 改为逆序执行后正向重组的 `[StorageUndoResult]`（消除 optional 不匹配）；(2) `StorageManifestStore.listRecent` 的 `loadDecodableFile(path)` 补显式 `as: StorageManifest.self`（消除泛型推断歧义）。
- 测试运行：`swift test --filter "AxionCoreTests" --filter "AxionCLITests"` → 3348 tests，仅 7 个 `DesktopNotifierTests` 失败（tmux/OSC9 转义包裹环境产物，与本 Story 无关）；storage 专项 `swift test --filter "Storage"` → 78 tests / 8 suites 全过。

### Completion Notes List

- T1–T8 全部完成，所有 AC（#1–#9、#12）由实现 + 测试覆盖；#10/#11 为模型兼容性声明（`uninstallApp` 透传至 executor 审计拒绝；统一审批语义留待 39.4），无代码缺口。
- **安全红线全部落实**：(1) 无 `delete` 动作——`StorageAction` 枚举无此 case，工具解析阶段即丢弃「delete」入参；(2) executor `action` 白名单 `{move, trash, createDirectory, scanOnly}`，`uninstallApp` 收到即拒绝 + 记 `errors`；(3) `removeItem` **仅**用于撤销 `createDirectory` 的空目录（先 `contentsOfDirectory` 断言为空）；(4) `trash` 走 `trashItem(at:resultingItemURL:)` 并捕获 `trashResultPath`（撤销依赖）。
- **草稿先行**（AC #4）：executor 第一件事写 `status = planned` manifest 到 `<storageOpsDir>/<operationId>.json`，逐项更新为 `executing`，终态 `completed`/`partiallyFailed` 并回填 `completedAt`/`summary`。
- **纵深防御重校验**（AC #5）：即使 39.1 `StoragePlanBuilder` 已校验，executor 独立再校验每项 source（scan_roots 前缀 / `StorageExclusions.evaluate` / 存在性 / 非 symlink 目标 / action 白名单），违规项丢弃 + 记 `errors`，不执行。
- **逐项独立**（AC #6）/ **不覆盖**（AC #7）：单项失败记 `failed` + reason 不中断整批；`move` 遇 `target_exists` → `failed`，不调用 `moveItem`。
- **撤销**（AC #8/#9）：逆序 best-effort 恢复，`move`/`trash`/`createDirectory` 各有明确 notRestored 原因（`source_already_exists`/`target_missing`/`item_no_longer_in_trash`/`directory_not_empty`）；结果写回 manifest（`undoneAt` + 逐项 `undoResults`）。
- **dryrun 门控**（AC #12）：`execute_storage_plan`/`undo_storage_op` 注册在 `AgentBuilder` 的 `if !dryrun` storage 块（与 39.1 一致），dryrun 永不副作用。
- 模块边界遵守：模型在 `AxionCore`，服务/工具在 `AxionCLI`，未改 `AxionHelper`、未改 `ToolNames.swift`（CLI Agent 工具 bare name）。
- 模型解码默认值向前兼容：所有 manifest 模型 `init(from:)` 用 `decodeIfPresent` + 回退，39.3/39.4 新增字段不破坏旧 manifest。

### File List

**新增（AxionCore 纯模型）**
- `Sources/AxionCore/Models/Storage/StorageOpStatus.swift` — manifest 级状态枚举（planned/executing/completed/partiallyFailed/cancelled）
- `Sources/AxionCore/Models/Storage/StorageItemOutcome.swift` — StorageItemOutcome + StorageUndoOutcome
- `Sources/AxionCore/Models/Storage/StorageManifestItem.swift` — 单条执行记录
- `Sources/AxionCore/Models/Storage/StorageUndoResult.swift` — 单条撤销记录
- `Sources/AxionCore/Models/Storage/StorageManifest.swift` — manifest 主体（含 undo 扩展字段）

**新增（AxionCLI 服务）**
- `Sources/AxionCLI/Services/Storage/StorageExecuting.swift` — Protocol + ExecutionItem/ExecuteRequest/ExecuteResult
- `Sources/AxionCLI/Services/Storage/StorageExecutor.swift` — 执行实现（move/trash/createDirectory + 草稿先行 + 重校验）
- `Sources/AxionCLI/Services/Storage/StorageManifestStore.swift` — save/load/listRecent/mostRecentUndoable
- `Sources/AxionCLI/Services/Storage/StorageUndoing.swift` — Protocol + UndoRequest/UndoResult
- `Sources/AxionCLI/Services/Storage/StorageUndoService.swift` — 逆序恢复实现

**新增（AxionCLI Agent 工具）**
- `Sources/AxionCLI/Tools/ExecuteStoragePlanTool.swift` — `execute_storage_plan`（isReadOnly=false）
- `Sources/AxionCLI/Tools/UndoStorageOpTool.swift` — `undo_storage_op`（isReadOnly=false）

**修改**
- `Sources/AxionCLI/Services/AgentBuilder.swift` — 在 39.1 的 `if !dryrun` storage 注册块追加 manifestStore + execute/undo 工具注册（T7）

**新增（测试，Swift Testing）**
- `Tests/AxionCoreTests/Models/Storage/StorageManifestTests.swift` — manifest/item/undoResult/opStatus/outcome Codable round-trip + 缺失字段默认
- `Tests/AxionCLITests/Storage/StorageExecutorTests.swift` — move/trash/createDirectory/scanOnly 成功路径 + 重校验拒绝（uninstallApp/outside/excluded/missing/symlink）+ 不覆盖 + 逐项独立失败 + 草稿落盘
- `Tests/AxionCLITests/Storage/StorageManifestStoreTests.swift` — save/load round-trip + listRecent 排序 + mostRecentUndoable 过滤 + trySave 失败
- `Tests/AxionCLITests/Storage/StorageUndoServiceTests.swift` — move/trash/createDirectory 撤销 + 各 notRestored 原因 + scanOnly/failed 跳过 + 无可撤销 nil
- `Tests/AxionCLITests/Storage/ExecuteStoragePlanToolTests.swift` — 入参校验 + action 白名单（delete 丢弃 / uninstallApp 透传）+ surface 默认 + Mock executor
- `Tests/AxionCLITests/Storage/UndoStorageOpToolTests.swift` — 成功返回 manifest + no_undoable_manifest + operation_id 透传/省略 + Mock undoer

### Change Log

- 实现 Story 39.2「整理目录执行与撤销」：执行已批准计划项（move/trash/createDirectory/scanOnly）、manifest 草稿→补全生命周期、按 manifest 逆向撤销。
- 新增 2 个有副作用 Agent 工具（`execute_storage_plan`、`undo_storage_op`），在 `AgentBuilder` `if !dryrun` 块注册。
- 安全：永不永久删除（无 `delete` 动作；`removeItem` 仅用于撤销空目录）；`trash` 走系统废纸篓（可恢复）；executor 执行前独立重校验每项 source。
- 测试：6 个新测试文件，storage 专项 78 tests / 8 suites 全过；未引入新第三方依赖（纯 Foundation + OpenAgentSDK + AxionCore）。
- 未改 `ToolNames.swift`、未改 `AxionHelper`、未改 39.1 只读工具——严格遵守模块边界。
- **[AI Review 2026-06-12]** 修复 2 个 MEDIUM：(1) 执行器状态机——被纵深防御丢弃的项计入 `errors` 时，终态由误报 `completed` 改为 `partiallyFailed`（对齐 Dev Notes「completed = 全部 succeeded/skipped」状态机定义）；(2) `UndoStorageOpTool` 注入 `StorageConfig` 并透传 `config.storageOpsDir`（原先硬编码 `.default`，与 `ExecuteStoragePlanTool` 不对称且对未来 undo 服务潜在隐患）。同步更新 `StorageExecutorTests` 断言与 `AgentBuilder` 注册点；storage 专项 78 tests / 8 suites 全过。新增 LOW 观察项见 Senior Developer Review。

## Senior Developer Review (AI)

**Reviewer:** story-automator-review（对抗式代码审查） · **Date:** 2026-06-12 · **Outcome:** ✅ Approve（0 CRITICAL / 0 HIGH；2 MEDIUM 已自动修复；3 LOW 记录为观察项）

### 审查范围

逐文件核验 story 声称的所有变更（5 个 AxionCore 模型、5 个 AxionCLI 服务、2 个 Agent 工具、AgentBuilder 注册、6 个测试文件），对照 git 实际改动（`git status`/`git diff`）与 12 条 AC。File List 与 git 一致，无差异文件。

### AC 验证结论

| AC | 结论 | 证据 |
|----|------|------|
| #1 move + 中间目录 + manifest | ✅ IMPLEMENTED | `StorageExecutor.perform` `.move` 分支：先 `createDirectory(target.deletingLastPathComponent)` 再 `moveItem`；manifest item 记 source/target/size/outcome |
| #2 trash 可恢复 + trashResultPath | ✅ IMPLEMENTED | `.trash` 分支用 `trashItem(at:resultingItemURL:)` 并捕获 `resultingURL?.path`；无 `delete` 动作 |
| #3 createDirectory 幂等 | ✅ IMPLEMENTED | `createDirectory(withIntermediateDirectories:true)`；已存在不抛错 → `succeeded`（`executeCreateDirectorySucceedsAndIsIdempotent` 覆盖二次执行） |
| #4 草稿先行 | ✅ IMPLEMENTED | `execute()` 第一件事 `manifestStore.trySave(.planned)`；逐项更新 `.executing`；终态覆写 |
| #5 纵深防御重校验 | ✅ IMPLEMENTED | `validate()`：action 白名单 / scan_roots 前缀 / `exclusions.evaluate` / 存在性 / 非 symlink；违规项 → `errors` |
| #6 逐项独立失败 | ✅ IMPLEMENTED | 单项失败记 `failed`+reason 不中断；`executeContinuesAfterPerItemFailure` 覆盖 |
| #7 move 不覆盖 | ✅ IMPLEMENTED | `target_exists` 前置检查 → `failed`，不调 `moveItem` |
| #8 撤销逆向恢复 | ✅ IMPLEMENTED | `StorageUndoService` 逆序遍历；move/trash/createDirectory 各有 notRestored 原因；写回 `undoneAt`+`undoResults` |
| #9 清空废纸篓场景 | ✅ IMPLEMENTED | `item_no_longer_in_trash`（`undoTrashItemNoLongerInTrash` 覆盖） |
| #10/#11 模型兼容声明 | ✅ N/A（非本 Story） | `uninstallApp` 收到即拒绝；统一审批语义留 39.4 |
| #12 dryrun 门控 | ✅ IMPLEMENTED | execute/undo 注册在 `AgentBuilder` `if !dryrun` 块 |

### 安全红线核验（逐条）

- ✅ 无 `delete` 动作：`StorageAction` 枚举无此 case；工具 `parseAction` 对未知 action 返回 nil（解析阶段丢弃）；executor 白名单 `{move,trash,createDirectory,scanOnly}`。
- ✅ `removeItem` **仅**用于撤销空目录：`StorageUndoService.undoCreateDirectory` 先 `contentsOfDirectory` 断言空再 `removeItem`；executor 全程不调 `removeItem`。
- ✅ trash 走 `trashItem(at:resultingItemURL:)`（可恢复），捕获落位路径。
- ✅ 不覆盖：`move` 的 `target_exists` 前置检查。

### 🔴 CRITICAL / HIGH
无。无任务误标 [x]、无 AC 缺失、无数据丢失路径、无安全漏洞。

### 🟡 MEDIUM（已自动修复）

**[M1] 执行器状态机：被丢弃项误报 `completed`** — `Sources/AxionCLI/Services/StorageExecutor.swift:81`
- 问题：`validate()` 拒绝的项进 `manifest.errors`（不计入 `failed`），原逻辑 `status = failed == 0 ? .completed : .partiallyFailed` 导致「全部项被拒绝」的操作误报 `completed`（`items` 空、`errors` 满）。按 status 判定的调用方会被误导；且违反 Dev Notes 自身状态机定义「completed = 全部 succeeded/skipped」。
- 修复：`(failed == 0 && manifest.errors.isEmpty) ? .completed : .partiallyFailed`；summary 文案同步。`StorageExecutorTests.executeRejectsUninstallAppAndRecordsError` 断言由 `completed` 改为 `partiallyFailed`。

**[M2] `UndoStorageOpTool` 硬编码 `StorageConfig.default.storageOpsDir`** — `Sources/AxionCLI/Tools/UndoStorageOpTool.swift:48`
- 问题：与 `ExecuteStoragePlanTool`（注入 config、透传 `config.storageOpsDir`）不对称；当前因 `StorageUndoService` 用注入的 `manifestStore`（忽略 `request.storageOpsDir`）而无功能影响，但属潜在地雷——若 undo 服务将来改为读 `request.storageOpsDir`，非默认配置下 undo 会静默找不到 manifest。
- 修复：`UndoStorageOpTool` 注入 `config: StorageConfig = .default`，`call()` 传 `config.storageOpsDir`；`AgentBuilder` 注册点显式传 `config: config.storage`。

### 🟢 LOW（记录为观察项，未改——需产品决策或属更大重构）

- **[L1] move / createDirectory 的 target 路径未做白名单校验。** AC #5 仅要求校验 source（已严格落实）。target 可指向 scan_roots 之外（合法：如整理到 ~/Documents），故不能简单限制回 scan_roots；但「target 落入敏感/排除区」缺少策略。当前不会覆盖（`target_exists` 拦截）、不会删除，但可被用于向任意可写位置投放文件。**未自动修复**：target 安全域定义是产品决策，需 Epic 层补「目标路径策略」AC，不宜在 review 中臆造策略。
- **[L2] `ExecuteRequest.storageOpsDir` / `UndoRequest.storageOpsDir`+`homeDirectory` 为未使用字段。** 两服务均用注入的 `manifestStore`，从不读 request 上的目录字段。Story 规范 T2.1/T4.1 显式定义了这些字段，属「设计纳入但未接线」的 vestigial API 面。M2 已让 undo 工具至少透传正确值；彻底删除字段会改动规范化的 request 契约，超出 review 边界，留待团队决定。
- **[L3] `approvedAt` 取执行开始时间（`createdAt`）而非真实审批时间。** 本 Story 不持有结构化审批时间（统一审批语义在 39.4），用执行开始时间作代理已由模型注释说明。功能正确，仅命名略显宽泛。

### 验证

`swift test --disable-sandbox --filter "Storage"` → **78 tests / 8 suites passed**（含修复后断言）。无新第三方依赖；未改 `ToolNames.swift`/`AxionHelper`/39.1 只读工具；模块边界（AxionCore 模型 ↔ AxionCLI 服务/工具）保持。

_Reviewer: story-automator-review on 2026-06-12_
