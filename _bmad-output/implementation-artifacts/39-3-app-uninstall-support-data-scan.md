---
baseline_commit: 574ad25b7a55ca297c577bec421d5cdd141b0f6c
---

# Story 39.3: 卸载 App 与 Support 数据扫描

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->
<!-- 范围：识别 App → 生成卸载计划 → 扫描 support 数据 →（确认后）移 App bundle 入废纸篓 → support 数据逐项确认清理 → manifest + 撤销。本 Story 永不永久删除（不存在 delete 动作）；破坏性动作默认走系统废纸篓（可恢复）。任何模式都不使用 sudo，不把 Full Disk Access 作为前置要求。run/chat/telegram 的统一审批 UI/语义（结构化 approvePlan/approveItem/rejectItem/cancel）属于 39.4——本 Story 的执行工具接收「已确定要执行的项」，审批决策由调用方/入口在调用工具之前完成；requiresTypedConfirmation 作为计划级标志由入口强制（39.4 统一）。 -->

## Story

As a Mac 用户,
I want Axion 卸载 App 并提示相关 support 数据候选,
So that 我能释放空间但不会误删重要数据（重要数据默认不选、高风险逐项确认、可撤销）.

## Acceptance Criteria

> 本 Story 覆盖「App 识别 + 卸载计划 + support 数据扫描 +（确认后）执行 + manifest + 撤销」。统一审批 UI/语义（`run`/`chat`/未来 `telegram` 的结构化 `approvePlan`/`approveItem`/`rejectItem`/`cancel`）属于 39.4；本 Story 的 `execute_app_uninstall` 入参即「已批准的执行集」（app bundle 是否移除 + 哪些 support 数据项已批准），与 39.2 `execute_storage_plan` 同口径。下列 AC 中标注【39.3】为本 Story 必须满足。

1. **【39.3】** **Given** 用户请求卸载某个 App（`scan_app_uninstall`，默认模式 `uninstallWithSupportReview`）
   **When** Axion 找到唯一匹配 App
   **Then** 输出 `AppUninstallPlan`，含 App 的 `displayName` / `bundlePath` / `bundleIdentifier` / `version` / `teamIdentifier?` / `sizeBytes` / `isRunning` / `isSystemProtected` / `matchConfidence`
   **And** 同时扫描并输出 `supportDataItems` 候选摘要（分类、路径、大小、匹配证据、数据风险、是否默认选中）
   **And** 该工具为只读（`isReadOnly = true`），不产生任何副作用；实际移动 App bundle 由 `execute_app_uninstall` 在用户确认后执行

2. **【39.3】** **Given** 用户输入匹配到多个 App 候选（`matchConfidence` 无法收敛到唯一目标）
   **When** Axion 无法确定唯一目标
   **Then** 输出全部候选列表并停止（`AppUninstallPlan` 带多候选 + `blockedReasons` 含 `ambiguous_match`）
   **And** **不自动选择**第一个候选，不在扫描阶段执行任何卸载

3. **【39.3】** **Given** 目标 App 正在运行（`isRunning = true`）
   **When** 用户请求执行卸载（`execute_app_uninstall`）
   **Then** 先尝试正常退出 App（`NSRunningApplication.terminate` / Apple Event quit，**新增**能力，参考 Dev Notes）
   **And** 退出失败（超时 / 被拒绝 / 仍在运行）时 **不移动 App bundle**，该项记 `failed` + `reason = app_still_running`，其余已批准 support 数据项不阻塞、可独立执行
   **And** `AppUninstallPlan` 须在扫描阶段就把 `isRunning` 与「需先退出」提示给入口

4. **【39.3】** **Given** 目标 App 位于系统路径（非 `/Applications`、非 `~/Applications`）或疑似系统/Apple/MDM 管理组件（`isSystemProtected = true`）
   **When** 用户请求卸载
   **Then** **阻止自动卸载**：`AppUninstallPlan.blockedReasons` 记录（如 `system_protected` / `outside_applications_dirs`），`execute_app_uninstall` 即便收到该项也拒绝移动 App bundle
   **And** 给出安全原因和手动处理建议（写入 `reason` / `evidence`，透传给入口展示）

5. **【39.3】** **Given** 用户请求清理 support 数据（`scan_app_uninstall` 模式 `reviewSupportData` 或 `cleanApprovedSupportData`）
   **When** Axion 扫描常见 support 数据目录
   **Then** 输出候选 `supportDataItems` 列表与每项 `matchEvidence` / `matchConfidence` / `dataRisk` / `defaultSelected` / `category`
   **And** 每个进入可执行计划的 support 数据项需逐项或按风险组确认（确认由入口在调用 `execute_app_uninstall` 前完成）
   **And** 执行时默认移动到系统废纸篓（`FileManager.trashItem`），**绝不永久删除**（无 `delete` 动作）

6. **【39.3】** **Given** support 数据候选是 `Application Support` / `Containers` / `Group Containers`（`category ∈ {applicationSupport, container, groupContainer}`）
   **When** Axion 生成计划
   **Then** 标记为高风险用户数据（`dataRisk = high`）
   **And** `defaultSelected = false`（高风险**必须**为 false）
   **And** `requiresExplicitApproval = true`；若 `requiresTypedConfirmation = true`，须由入口要求用户输入 App 名或 bundle id 才能批准（39.4 统一执行，本 Story 实现该计划级标志与字段）

7. **【39.3】** **Given** support 数据候选只有低置信度名称相似证据（`matchConfidence = low`，如仅靠名称相似 / 同 vendor 父目录 / 模糊匹配）
   **When** Axion 生成计划
   **Then** 该项 **只能作为提示展示**（`SupportDataItem` 带 `matchConfidence = low`），**不进入可执行清理计划**（`execute_app_uninstall` 拒绝执行 `matchConfidence = low` 的项，记 `skipped` + `reason = low_confidence_hint_only`）

8. **【39.3】** **Given** support 数据候选命中共享目录（vendor 父目录如 `~/Library/Application Support/Google`、`Group Containers`、iCloud/Dropbox/OneDrive 等云同步目录）
   **When** Axion 生成计划
   **Then** **禁止删除共享目录**：vendor 父目录即使名称匹配也只能处理证据精确指向目标 `bundleIdentifier` 的子项；`Group Containers` 无法证明只归属目标 App 时必须 `scan-only`（`dataRisk` 升至 `high` 且 `defaultSelected = false`）；云同步/Keychain/浏览器扩展类 → `dataRisk = forbidden`，MVP 不处理
   **And** 共享目录命中在 `matchEvidence` 中显式标注 `shared_directory` 信号

9. **【39.3】** **Given** 卸载或 support 数据清理已执行
   **When** 生成 manifest
   **Then** 复用 39.2 的 `StorageManifest` + `StorageManifestItem`：App bundle 移废纸篓记为 `StorageManifestItem(action: .uninstallApp, sourcePath: <bundlePath>, trashResultPath: <废纸篓落位>, sizeBytes, evidence, approvedAt)`；每个 support 数据项移废纸篓记为 `StorageManifestItem(action: .trash, ...)`
   **And** manifest 记录 App 信息（通过 item `evidence.source` / `reason` 透传 bundle id 与 displayName）、每项原路径、废纸篓目标、大小、时间戳、审批摘要与匹配证据
   **And** 通过共享的 `StorageManifestStore`（与 39.2 execute/undo 同一 `~/.axion/storage-ops/`）落盘

10. **【39.3】** **Given** App 卸载已执行并生成 manifest
    **When** 用户请求撤销（复用 39.2 `undo_storage_op`，可省略 `operation_id` 取最近一次可撤销操作）
    **Then** 扩展 `StorageUndoService` 处理 `.uninstallApp` 动作：从 `trashResultPath` 恢复 App bundle 到 `sourcePath`（机制与 `.trash` 撤销一致：source 不存在、trash 路径仍在废纸篓时恢复）
    **And** support 数据 `.trash` 项沿用 39.2 已有撤销逻辑
    **And** 撤销只恢复 manifest 中记录且**仍存在于废纸篓**的项目；已被用户清空废纸篓的项记 `notRestored` + `reason = item_no_longer_in_trash`，不影响其余项

11. **【39.3】** **Given** App 来自 `.pkg` 安装或 Homebrew Cask
    **When** Axion 生成卸载计划
    **Then** 以**只读**方式探测 pkg receipts（`/var/db/receipts/*` / `/Library/Receipts`）或本机 Homebrew cask 元数据 / `zap` 路径，作为 `externalUninstallHints`（read-only）展示
    **And** 探测失败 / 不可访问时**优雅降级**（hint 为空），不阻塞 App bundle 卸载
    **And** **绝不执行** `sudo`、`pkgutil --forget`、vendor uninstaller、`brew uninstall --zap`——任何外部元数据都不能绕过 Axion 的风险分级与确认

12. **【39.3】** **Given** `execute_app_uninstall` 收到的 app bundle 路径 / bundleId 由 Agent 提供（可能编造、越界、已被替换）
    **When** executor 执行前
    **Then** **逐项纵深防御重校验**（与 39.2 executor 同理念）：(1) app bundle 路径 `∈ {/Applications, ~/Applications}` 之下且 `isSystemProtected == false`；(2) 路径存在且确为 `.app` bundle；(3) bundle 的 `CFBundleIdentifier` 与计划 App 的 bundleId 一致；(4) 每个 support 数据项 `matchConfidence != low` 且 `dataRisk != forbidden`；(5) 拒绝任何 `delete` 动作——**违规项丢弃并记入 `errors`，不执行**
    **And** 卸载走**独立的** `AppUninstallExecutor`（**不复用** `StorageExecutor`——后者 `allowedActions` 显式排除 `uninstallApp`，见 Dev Notes「关键约束 #2」）

13. **【39.3】** **Given** support 扫描需触碰 `~/Library` 子路径
    **When** `SupportDataScanService` 探测候选路径
    **Then** **不调用** `StorageExclusions.evaluate()`（该方法对整个 `~/Library` 恒定排除，会误杀所有 support 候选）；改为**精确探测** bundle-id 键控的具体子路径（如 `~/Library/Caches/<bundleId>`），仅复用 `StorageExclusions.standardize(_:home:)` 做路径标准化
    **And** 候选路径由「`<libSubdir>/<bundleId>`（或 `<bundleId>.plist` / `<bundleId>.savedState` 等）」精确推导，不做 `~/Library` 全量递归枚举

14. **【39.3】** **Given** `dryrun` 模式
    **When** `AgentBuilder` 构建
    **Then** `scan_app_uninstall` 与 `execute_app_uninstall` **不注册**（与 39.1/39.2 存储工具一致的 `if !dryrun` 门控）
    **And** dryrun 模式永远不产生任何文件副作用

15. **【39.3】** **Given** 单元测试
    **When** 编写与运行测试
    **Then** 所有依赖 `NSWorkspace` / `Bundle(url:)` / `FileManager.trashItem` 的逻辑**必须**经 Protocol + Mock 注入（`AppDiscovering` + `MockAppDiscoverer`、`SupportDataScanning` + `MockSupportDataScanner`、`AppUninstallExecuting` + `MockAppUninstallExecutor`、`AppQuitting` + `MockAppQuitter`），镜像 39.1 `StorageScanning`/`MockStorageScanner` 与 Helper `AppLaunching`/`MockAppLauncher` 的闭包注入模式
    **And** 文件探测类测试用临时目录注入 `homeDirectory`（`makeTempDir()` + `defer cleanup()`，镜像 `StorageFeatureTests`），禁止写真实 `~/.axion` / 真实 `~/Library`
    **And** **只使用 Swift Testing**（`import Testing` / `@Suite` / `@Test` / `#expect`），禁止 `import XCTest`；只运行单元测试目录（`Tests/**/Tools/`、`Models/`、`Services/`），**不运行**集成测试

## Tasks / Subtasks

- [x] **Task 1：AxionCore 模型（AC: #1, #2, #6, #7, #9）**
  - [x] 1.1 新建 `Sources/AxionCore/Models/Storage/App/AppMatchConfidence.swift`（`public enum AppMatchConfidence: String, Sendable, Equatable, Codable { case high, medium, low }`——注意：与已有 `StorageConfidence` 区分；此处专指「用户输入→候选 App」匹配置信度）
  - [x] 1.2 新建 `Sources/AxionCore/Models/Storage/App/AppCandidate.swift`（`public struct AppCandidate: Codable, Equatable, Sendable`；字段：`displayName, bundleIdentifier, bundlePath, version, teamIdentifier?, sizeBytes: Int64, isRunning: Bool, isSystemProtected: Bool, matchConfidence: AppMatchConfidence`；显式 snake_case `CodingKeys` + `decodeIfPresent` 回退，对齐 `StorageManifest` 风格）
  - [x] 1.3 新建 `Sources/AxionCore/Models/Storage/App/SupportDataCategory.swift`（`public enum SupportDataCategory: String, Sendable, Equatable, Codable`，case：`cache, logs, httpStorage, webKit, preferences, savedState, applicationScripts, applicationSupport, container, groupContainer, launchAgent, forbidden`）
  - [x] 1.4 新建 `Sources/AxionCore/Models/Storage/App/SupportDataItem.swift`（`public struct SupportDataItem: Codable, Equatable, Sendable`；字段：`category: SupportDataCategory, path: String, sizeBytes: Int64, matchEvidence: StorageEvidence（**复用**）, matchConfidence: StorageConfidence（**复用**，high/medium/low）, dataRisk: DataRisk（**复用**）, defaultSelected: Bool, requiresExplicitApproval: Bool`；snake_case `CodingKeys` + `decodeIfPresent`）
  - [x] 1.5 新建 `Sources/AxionCore/Models/Storage/App/AppUninstallMode.swift`（`public enum AppUninstallMode: String, Sendable, Equatable, Codable`，case：`scanOnly, uninstallAppOnly, uninstallWithSupportReview, reviewSupportData, cleanApprovedSupportData`；rawValue 用 snake_case）
  - [x] 1.6 新建 `Sources/AxionCore/Models/Storage/App/DataLossRisk.swift`（`public enum DataLossRisk: String, Sendable, Equatable, Codable { case none, low, medium, high }`）
  - [x] 1.7 新建 `Sources/AxionCore/Models/Storage/App/ExternalUninstallHint.swift`（`public struct ExternalUninstallHint: Codable, Equatable, Sendable`；字段：`source: String`（`pkg_receipt` / `homebrew_cask` / `vendor_uninstaller`）、`detail: String`、`paths: [String]`、`confidence: StorageConfidence`；read-only 提示用）
  - [x] 1.8 新建 `Sources/AxionCore/Models/Storage/App/AppUninstallPlan.swift`（`public struct AppUninstallPlan: Codable, Equatable, Sendable`；字段：`app: AppCandidate, candidates: [AppCandidate]`（多候选时 `app` 取最高置信度、`candidates` 列全部）、`uninstallMode: AppUninstallMode, supportDataItems: [SupportDataItem], hintOnlySupportDataItems: [SupportDataItem]`（低置信度单列，不进可执行集）、`dataLossRisk: DataLossRisk, requiresTypedConfirmation: Bool, blockedReasons: [String], externalUninstallHints: [ExternalUninstallHint]`；snake_case `CodingKeys` + `decodeIfPresent`）
  - [x] 1.9 测试 `Tests/AxionCoreTests/Models/Storage/AppUninstallPlanCodecTests.swift`：Codable 往返（snake_case）、enum rawValue、`decodeIfPresent` 对缺字段的回退（镜像 39.1 `StoragePlanCodecTests`）

- [x] **Task 2：App 发现服务（AC: #1, #2, #4）**
  - [x] 2.1 新建 `Sources/AxionCLI/Services/Storage/App/AppDiscovering.swift`：`protocol AppDiscovering: Sendable { func discover(query: String, searchRoots: [URL]) async -> [AppCandidate] }`（query = 用户输入的 App 名/bundle id/路径）
  - [x] 2.2 新建 `Sources/AxionCLI/Services/Storage/App/AppDiscoveryService.swift`：`final class AppDiscoveryService: AppDiscovering, Sendable`，`import AppKit`
    - [x] 2.2.1 枚举 `searchRoots`（默认 `/Applications` + `~/Applications`）下所有 `*.app`（`FileManager.enumerator` 浅层，仅顶层 bundle，不进嵌套 `.app`）
    - [x] 2.2.2 读 bundle 元数据：`Bundle(url: appURL)` + `object(forInfoDictionaryKey: "CFBundleDisplayName") ?? "CFBundleName"` 取 displayName；`CFBundleIdentifier`；`CFBundleShortVersionString` / `CFBundleVersion`；`teamIdentifier` 读取失败不阻塞（`Bundle` 无 team id API → 读 `Info.plist` 的 `ApplicationIdentifier` 前缀或签名信息，失败置 nil）。**参考** `Sources/AxionHelper/Services/AppLauncher.swift` L168-172 的 Bundle 读取范式（仅参考手法，**不可 import AxionHelper**）
    - [x] 2.2.3 `isRunning`：`NSWorkspace.shared.runningApplications` 过滤 `bundleIdentifier` 相等且 `isTerminated == false`（NSRunningApplication 实际 API 为 `isTerminated`，非 `activationState`；参考 `AppLauncher.swift` L97-106 手法）
    - [x] 2.2.4 `isSystemProtected`：bundle id 命中 Apple 系统 bundle id 前缀（`com.apple.*`）→ true；系统目录（`/System/`、`/Library/`、`/usr/`、`/bin`、`/sbin`、`/private`）→ true。「路径不在 `/Applications`/`~/Applications` 之下」由 builder 作为独立 `outside_applications_dirs` 信号判定
    - [x] 2.2.5 `sizeBytes`：复用 `readSize` 口径（`URL.resourceValues`：`totalFileSize ?? fileSize`，目录走 `totalFileSize`）。注意：app bundle size 可能近似（已知限制，与 39.1 review follow-up 一致，不阻塞）
    - [x] 2.2.6 `matchConfidence`：纯函数 `classifyMatch(query, bundleIdentifier, displayName) -> AppMatchConfidence`——精确 bundle id 相等 = high；displayName 精确相等（忽略大小写）= high；displayName contains / bundle id 前缀 = medium；仅名称相似 / 模糊 = low。**该纯函数独立可测**
  - [x] 2.3 测试 `Tests/AxionCLITests/Services/AppDiscoveryTests.swift`：只测**纯函数** `classifyMatch` + `isSystemProtected` 路径分类逻辑（注入路径字符串，不调 NSWorkspace）；`AppDiscovering` 经 `MockAppDiscoverer`（闭包注入候选数组）在下游测试中使用

- [x] **Task 3：Support 数据扫描（AC: #5, #6, #7, #8, #13）**
  - [x] 3.1 新建 `Sources/AxionCLI/Services/Storage/App/SupportDataScanning.swift`：`protocol SupportDataScanning: Sendable { func scan(for app: AppCandidate, homeDirectory: String) async -> [SupportDataItem] }`
  - [x] 3.2 新建 `Sources/AxionCLI/Services/Storage/App/SupportDataScanService.swift`：`final class SupportDataScanService: SupportDataScanning, Sendable`
    - [x] 3.2.1 维护「候选路径模板表」`[(category, subdirTemplate)]`（对齐 Epic 支持范围 196-207）：`Caches/<bundleId>`、`HTTPStorages/<bundleId>`、`WebKit/<bundleId>`、`Logs/<bundleId>` 与 `Logs/<displayName>`、`Preferences/<bundleId>.plist`、`Preferences/ByHost/<bundleId>.*.plist`、`Saved Application State/<bundleId>.savedState`、`Application Scripts/<bundleId>`、`Containers/<bundleId>`、`Application Support/<bundleId>` 与 `Application Support/<displayName>`、`Group Containers/<bundleId>` 与 `Group Containers/<teamId>.*`、`LaunchAgents/<bundleId>.plist`
    - [x] 3.2.2 **精确探测**：每个模板 → 拼绝对路径 → 仅 `FileManager.fileExists` 判存在 → 存在则读 size（`readSize` 口径）。**禁止**对 `~/Library` 做递归枚举；**禁止**调用 `StorageExclusions.evaluate()`（AC #13）。仅 `StorageExclusions.standardize(<path>, home: homeDirectory)` 做标准化。ByHost plist 与 Group Containers 通过**特定子目录**（`Preferences/ByHost`、`Group Containers`）的键控前缀匹配探测，非 `~/Library` 递归
    - [x] 3.2.3 证据分级（纯函数 `gradeEvidence(path, bundleId, displayName) -> (StorageConfidence, StorageEvidence)`）：路径末段 == bundle id / `<bundleId>.plist` / `<bundleId>.savedState` / `<bundleId>.*.plist`（ByHost）= **high**；末段 == displayName 或含 bundle id 子串 = **medium**；Group Containers 按 team id 命中 / 仅名称相似 = **low**
    - [x] 3.2.4 数据风险映射（纯函数 `categoryToRisk(category) -> DataRisk`）：cache/logs = low；httpStorage/webKit/preferences/savedState/applicationScripts = medium；applicationSupport/container/groupContainer/launchAgent = high；forbidden（云/Keychain）= forbidden
    - [x] 3.2.5 共享目录保护（纯函数 `isSharedDirectory(path, category) -> Bool`）：命中 `Application Support/<vendor>` 父目录（如 `/Google`、`/Microsoft`）、`Group Containers`（非唯一归属）、iCloud/Dropbox/OneDrive 路径 → true；命中则该项 `matchEvidence` 追加 `shared_directory` 信号，且若无法证明只归属目标 App（非 bundle-id 高置信度键控）→ 强制 `dataRisk = high`、`defaultSelected = false`
    - [x] 3.2.6 组装 `SupportDataItem`（`assembleItem` 纯函数）：`defaultSelected = (dataRisk == low) && (matchConfidence != low)`（低风险高/中置信度才默认选；高风险/低置信度恒 false）；`requiresExplicitApproval = (dataRisk == high) || isSharedDirectory`
  - [x] 3.3 测试 `Tests/AxionCLITests/Services/SupportDataScanServiceTests.swift`：注入临时 `homeDirectory`，在临时目录下伪造 `~/Library/Caches/<bundleId>`、`~/Library/Application Support/<bundleId>`、`~/Library/Group Containers/<teamId>.xxx` 等结构，断言：候选发现、证据分级（high/medium/low）、风险映射、共享目录识别、defaultSelected 规则、低置信度（group container）标记为 `.low`（供 builder 单列）。文件探测用真实临时目录（非外部依赖，允许）。**10 个测试全通过**（纯函数 7 + scan 2 + readSize 覆盖）

- [x] **Task 4：卸载计划构建器（AC: #2, #4, #6, #7, #8, #11）**
  - [x] 4.1 新建 `Sources/AxionCLI/Services/Storage/App/AppUninstallPlanBuilder.swift`：`struct AppUninstallPlanBuilder: Sendable`，`init(supportDataScanner: SupportDataScanning, appDiscoverer: AppDiscovering, hintReader: ExternalHintReading)`（**注入**，便于 Mock）
    - [x] 4.1.1 `func build(query: String, mode: AppUninstallMode, homeDirectory: String, searchRoots: [URL]) async -> AppUninstallPlan`
    - [x] 4.1.2 调 `appDiscoverer.discover(...)`；多候选且无 high 置信度唯一解（`candidates.count > 1 && highConfidence.count != 1`）→ `blockedReasons += "ambiguous_match"`，`app` 取最高置信度占位、`candidates` 列全部；候选为空 → `no_match` 占位（AC #2）
    - [x] 4.1.3 `app.isSystemProtected == true` → `blockedReasons += "system_protected"`（AC #4）；bundle 路径不在 searchRoots 之下（纯函数 `isInside` 前缀匹配，含 `~/Applications` 归一）→ `blockedReasons += "outside_applications_dirs"`
    - [x] 4.1.4 调 `supportDataScanner.scan(for: homeDirectory:)`；按 `matchConfidence` 分流：`low` → `hintOnlySupportDataItems`（AC #7），`medium/high` → `supportDataItems`
    - [x] 4.1.5 `dataLossRisk`：纯函数 `aggregateDataLossRisk` 用 `DataLossRisk.max` 聚合可执行项 `dataRisk`（forbidden 归入 high）；空 → `.none`
    - [x] 4.1.6 `requiresTypedConfirmation`：`dataLossRisk == high` 或存在 `defaultSelected == false && requiresExplicitApproval` 的高风险项 → true（AC #6）
    - [x] 4.1.7 `externalUninstallHints`：调 `hintReader.read(for: app)`（pkg receipts / Homebrew cask，**best-effort 只读**，失败返回空）；任何 hint 都不改变风险策略（AC #11）
  - [x] 4.2 新建 `Sources/AxionCLI/Services/Storage/App/ExternalHintReading.swift`：`protocol ExternalHintReading: Sendable { func read(for app: AppCandidate) -> [ExternalUninstallHint] }` + `final class ExternalHintReader: ExternalHintReading, Sendable`（pkg receipts 探测 `/var/db/receipts/` + Homebrew cask 探测 `/opt/homebrew/Caskroom`；探测全部 `try?`，失败返空，**绝不 spawn sudo / brew uninstall**）
  - [x] 4.3 测试 `Tests/AxionCLITests/Services/AppUninstallPlanBuilderTests.swift`（+ 共享 `Tests/AxionCLITests/Services/AppUninstallMocks.swift` 提供 `MockAppDiscoverer` / `MockSupportDataScanner` / `MockExternalHintReader` / `makeSupportItem` / `makeCandidate`，供 Task 7 复用）：断言多候选→`ambiguous_match`、系统保护→`system_protected`、越界→`outside_applications_dirs`、无候选→`no_match`、低置信度分流到 hintOnly、高风险→defaultSelected=false + requiresTypedConfirmation、共享目录衍生项升级风险、dataLossRisk 聚合、外部提示只读不改风险、`isInside` 纯函数。**12 个测试全通过**

- [x] **Task 5：App 退出 + 卸载执行器（AC: #3, #9, #12）**
  - [x] 5.1 新建 `Sources/AxionCLI/Services/Storage/App/AppQuitting.swift`：`protocol AppQuitting: Sendable { func terminate(bundleIdentifier: String) async -> Bool }`（返回是否成功退出）
  - [x] 5.2 新建 `Sources/AxionCLI/Services/Storage/App/AppQuitter.swift`：`final class AppQuitter: AppQuitting, Sendable`，`import AppKit`
    - [x] 5.2.1 取 `NSWorkspace.shared.runningApplications` 中 `bundleIdentifier` 相等的 `NSRunningApplication`（`!isTerminated`）；未运行视为已退出
    - [x] 5.2.2 graceful：`app.terminate()`（发 quit Apple Event，**非** `requestTermination()`——`NSRunningApplication` 无该方法）；轮询 `isTerminated`（**非** `activationState`，见 Task 2 修正）带超时 8s、轮询间隔 0.2s
    - [x] 5.2.3 超时仍未退出 → 返回 false（**不 force-kill**，避免破坏未保存数据）
  - [x] 5.3 新建 `Sources/AxionCLI/Services/Storage/App/AppUninstallExecuting.swift`：`protocol AppUninstallExecuting: Sendable { func execute(_ request: AppUninstallExecuteRequest) async -> AppUninstallExecuteResult }`；定义 `AppUninstallExecuteRequest`（`operationId, surface, app, uninstallBundle, supportDataItems`（已批准集）, `searchRoots`（bundle 校验用）, `userRequest?, homeDirectory, storageOpsDir`（审计字段，持久化走注入的 manifestStore，对齐 `ExecuteRequest`））与 `AppUninstallExecuteResult`（`manifest, succeeded, skipped, failed`）
  - [x] 5.4 新建 `Sources/AxionCLI/Services/Storage/App/AppUninstallExecutor.swift`：`final class AppUninstallExecutor: AppUninstallExecuting, Sendable`，`init(manifestStore: StorageManifestStore, appQuitter: AppQuitting, trashPerformer: TrashPerforming = .system)`（**注入**共享 `StorageManifestStore` + `AppQuitting` + 可注入 `TrashPerforming`）；新增 `struct TrashPerforming: Sendable { perform: @Sendable (URL) throws -> URL }` + `static let system`（真实 `trashItem`）
    - [x] 5.4.1 **草稿先行**：先写 `StorageManifest(..., items: [], status: .planned, errors: [])`，`manifestStore.trySave`
    - [x] 5.4.2 若 `uninstallBundle`：`validateBundle` 纵深校验（AC #12）—— 路径 ∈ searchRoots、非 `isSystemProtected`、存在且为 `.app`、读实际 bundle 的 `CFBundleIdentifier` 与 `app.bundleIdentifier` 比对；任一失败 → app bundle 项记 `failed` + reason 进 errors，**不移动**
    - [x] 5.4.3 校验通过且 `app.isRunning`：`await appQuitter.terminate(...)`；失败 → bundle 项记 `failed` + `app_still_running`，**不移动**（AC #3）
    - [x] 5.4.4 移动 App bundle：`trashPerformer.perform`（生产 = `FileManager.trashItem`），记 `StorageManifestItem(action: .uninstallApp, sourcePath, trashResultPath, sizeBytes, outcome, evidence: rule="app_bundle", source="<bundleId> <displayName>", confidence: .high, approvedAt)`（AC #9）
    - [x] 5.4.5 逐项处理已批准 support 数据：`validateSupportItem` 纵深校验（策略门优先：`matchConfidence == low`→`low_confidence_hint_only`、`forbidden`、共享目录需 `defaultSelected == true`；最后存在性 `source_missing`）；通过则 `trashItem`，记 `.trash` 项；拒绝 → `skipped` + reason 进 errors
    - [x] 5.4.6 逐项 `trySave`（status 首项起 `.executing`）；终态 `(failed == 0 && errors.isEmpty) ? .completed : .partiallyFailed`，回填 `completedAt` + `summary`（对齐 39.2 executor 状态机）
    - [x] 5.4.7 **绝不调用 `FileManager.removeItem`**（永久删除）；只 `trashItem`（可恢复）
  - [x] 5.5 测试 `Tests/AxionCLITests/Services/AppUninstallExecutorTests.swift`：注入临时 `storageOpsDir` + `homeDirectory` + `MockAppQuitter`（闭包返回是否退出成功）+ **注入 `TrashPerforming` Mock**（移到临时 trash 目录，不污染真实废纸篓）；伪造 `.app`（`<name>.app/Contents/Info.plist` 带 CFBundleIdentifier + payload）+ 伪造 support 数据目录；断言：草稿先行落盘、退出失败不移动 bundle（AC #3）、纵深校验拒绝越界/bundleId 不符/缺失（AC #12）、bundle + support 各成 manifest item（AC #9）、运行中退出成功后移动、support 低置信度/共享未批准 skipped、部分失败 → partiallyFailed、全程只 trash 不 delete。**9 个测试全通过**

- [x] **Task 6：扩展 39.2 撤销以支持 uninstallApp（AC: #10）**
  - [x] 6.1 修改 `Sources/AxionCLI/Services/Storage/StorageUndoService.swift` 的 `undoItem`：将 `.uninstallApp` case 从「skipped」改为与 `.trash` 一致的恢复逻辑——抽出共享私有 `restoreFromTrash(_:action:)`，`undoTrash`/`undoUninstallApp` 分别以 `.trash`/`.uninstallApp` 调用（action 标记正确，逻辑 DRY）。从 `item.trashResultPath` 移回 `item.sourcePath`（source 已存在 → `source_already_exists` 不覆盖；trash 路径缺失 → `item_no_longer_in_trash`）。**只动这一个 case 分支 + 抽共享函数**，不破坏 39.2 既有 move/createDirectory/scanOnly 逻辑；文档注释更新 AC #10 语义
  - [x] 6.2 测试 `Tests/AxionCLITests/Storage/StorageUndoServiceTests.swift`（**追加** 4 个 uninstallApp 用例到既有 Suite，未新建重复 Suite）：bundle 可从 trashResultPath 恢复（且 `undoResults.action == .uninstallApp`）、废纸篓已清空 → `notRestored`/`item_no_longer_in_trash`、source 已存在 → `source_already_exists` 不覆盖、与 trash 项同 manifest 共存均恢复。**15 个测试全通过**（11 旧 + 4 新）

- [x] **Task 7：scan_app_uninstall 工具（只读）（AC: #1, #5, #11）**
  - [x] 7.1 新建 `Sources/AxionCLI/Tools/ScanAppUninstallTool.swift`：`final class ScanAppUninstallTool: ToolProtocol, Sendable`，`let isReadOnly = true`，`nonisolated(unsafe) let inputSchema: ToolInputSchema`（dict，snake_case 字段：`query`（必填）、`mode`（可选，默认 `uninstall_with_support_review`）、`search_roots`（可选，默认 `["/Applications", "~/Applications"]`））
    - [x] 7.1.1 `func call(input:context:) async -> ToolResult`：`requireStringParam(params:key:"query"...)` 缺失 → `errorResult`；解析 `mode`/`search_roots`（`search_roots` 经 `StorageExclusions.standardize` 展开 `~`）；调 `AppUninstallPlanBuilder.build(...)` → `ToolResultHelper.encodeResult` 输出 `AppUninstallPlan`（JSON）
    - [x] 7.1.2 工具名 `scan_app_uninstall`（匹配 `^[a-z][a-z0-9_]*$`）；`description` 说明只读、不执行卸载、需配合 `execute_app_uninstall`；`static let defaultSearchRoots`
  - [x] 7.2 测试 `Tests/AxionCLITests/Storage/ScanAppUninstallToolTests.swift`：注入 `CapturingDiscoverer`（捕获 query/searchRoots）+ `MockSupportDataScanner` + `MockExternalHintReader`（经 builder）；断言：缺 query → `missing_query` errorResult、非对象 → `invalid_input`、正常 → 输出 plan JSON（`AppUninstallPlan` 解码）、默认根透传、显式 mode/search_roots 透传、多候选 → `ambiguous_match`。**7 个测试全通过**

- [x] **Task 8：execute_app_uninstall 工具（副作用）（AC: #3, #5, #9, #12, #14）**
  - [x] 8.1 新建 `Sources/AxionCLI/Tools/ExecuteAppUninstallTool.swift`：`final class ExecuteAppUninstallTool: ToolProtocol, Sendable`，`let isReadOnly = false`，`nonisolated(unsafe) let inputSchema`（snake_case：`operation_id`、`app`（含 bundle_path/bundle_identifier/is_system_protected/is_running 等子字段）、`uninstall_bundle`（Bool）、`support_data_items`（数组，每项含 path/category/match_confidence/data_risk/default_selected/requires_explicit_approval/match_evidence）、`search_roots`（必填，bundle 纵深校验范围）、`surface?`、`home_directory?`、`user_request?`）
    - [x] 8.1.1 `parseApp` / `parseSupportItem` / `parseCategory` 静态解析 + 复用 `ExecuteStoragePlanTool.parseEvidence` / `parseSizeBytes`（DRY，镜像 `ExecuteStoragePlanTool` 的 parse*）；额外守卫 `uninstall_bundle || !support_data_items.isEmpty`，否则 `no_action_requested` errorResult（防止空执行集）
    - [x] 8.1.2 调 `AppUninstallExecutor.execute(...)` → `manifestStore` 自动落盘 → `encodeResult` 输出 `StorageManifest`（operationId、status、items、errors，审计摘要已在 executor summary 字段）
    - [x] 8.1.3 工具名 `execute_app_uninstall`（匹配 `^[a-z][a-z0-9_]*$`）；`description` 强调副作用 + 永不永久删除 + 需用户确认 + 可经 `undo_storage_op` 撤销；`search_roots` 必填（与 `ExecuteStoragePlanTool.scan_roots` 同口径，用于 executor bundle 纵深校验）
  - [x] 8.2 测试 `Tests/AxionCLITests/Storage/ExecuteAppUninstallToolTests.swift`（与既有 `ScanAppUninstallToolTests`/`ExecuteStoragePlanToolTests` 同目录，保持 storage 工具测试聚集）：注入 `MockAppUninstallExecutor`（actor 捕获请求 + 据解析结果构造固定 `AppUninstallExecuteResult`）；断言：bundle 卸载入参解析（app 字段端到端）、support 项入参解析（category/data_risk/default_selected/requires_explicit_approval/match_evidence）、非对象 → `invalid_input`、缺 operation_id → `missing_operation_id`、缺/空 search_roots → `missing_search_roots`、缺/无效 app → `missing_or_invalid_app`、空执行集 → `no_action_requested`、未知 category 的 support 项被解析丢弃其余仍执行、surface 默认 run / chat 透传、`isReadOnly == false`。**10 个测试全通过**

- [x] **Task 9：AgentBuilder 注册（AC: #14）**
  - [x] 9.1 修改 `Sources/AxionCLI/Services/AgentBuilder.swift`：在既有 `if !dryrun` 存储块（L169-184，紧跟 `UndoStorageOpTool` 之后）**追加**（保持文件现有变量风格，命名 `appPlanBuilder` 避免与同作用域潜在冲突）：
    - [x] 9.1.1 复用 `AppDiscoveryService()`（无参 init）作为 planBuilder 的发现器
    - [x] 9.1.2 复用 `SupportDataScanService()`（无参 init）作为 planBuilder 的扫描器
    - [x] 9.1.3 `let appPlanBuilder = AppUninstallPlanBuilder(supportDataScanner: SupportDataScanService(), appDiscoverer: AppDiscoveryService(), hintReader: ExternalHintReader())`
    - [x] 9.1.4 `agentTools.append(ScanAppUninstallTool(planBuilder: appPlanBuilder))`
    - [x] 9.1.5 复用**同一** `manifestStore`（L175 已创建）：`agentTools.append(ExecuteAppUninstallTool(executor: AppUninstallExecutor(manifestStore: manifestStore, appQuitter: AppQuitter()), config: config.storage))`（`trashPerformer` 走默认 `.system`）
  - [x] 9.2 确认 dryrun 模式下两个工具**均不注册**（两工具 append 均在 `if !dryrun` 块内，紧跟 `UndoStorageOpTool` 之后、块结束 `}` 之前）

- [x] **Task 10：构建与单元测试（AC: #15）**
  - [x] 10.1 `swift build` 通过（Swift 6.1+ / macOS 14+，无 warning 回归）——`Build complete!`，含 `AgentBuilder.swift` 重新编译注册两个新工具
  - [x] 10.2 运行单元测试（**只**单元测试目录，含 `--filter "AxionCLITests"` 全量）：**3508 测试，7 失败**——7 个失败**全部**位于 `Tests/AxionHelperTests/.../DesktopNotifierTests.swift`（OSC 9 终端转义序列断言）。已用 `git stash` 在 clean baseline（HEAD `574ad25`，本 Story 改动之前）复跑验证：**同样 7 个 DesktopNotifier 失败**，证明为**既有环境问题**（测试 harness 运行于 tmux：`TERM=tmux-256color`/`TMUX=present`，DesktopNotifier 将 OSC 9 包入 tmux passthrough `Ptmux;`，而测试断言原始 `\u{1B}]9;`），与 Story 39.3 无关。本 Story 全部新增/改动测试（SupportDataScanServiceTests 10、AppUninstallPlanBuilderTests 12、AppUninstallExecutorTests 9、ScanAppUninstallToolTests 7、ExecuteAppUninstallToolTests 10、StorageUndoServiceTests 新增 4 uninstallApp 用例）**全通过**（合计 63/63 绿）。
  - [x] 10.3 确认无 `import XCTest` 新增：`grep -rl "import XCTest" Tests/` 为空 ✓
  - [x] 10.4 确认无 `print(` 新增（`Sources/AxionCLI/Services/Storage/App/` + 两个工具文件均为空 ✓）；并确认全代码路径无 `FileManager.removeItem`（仅注释中出现「绝不 removeItem」宣示）、无 `Process`/`sudo`/`pkgutil`/`brew uninstall`（仅注释中出现「禁止 spawn 任何进程」宣示）

## Dev Notes

### 架构与模块边界（HARD，违反即返工）

- **AxionCore 纯模型、零外部依赖**：`Sources/AxionCore/Models/Storage/App/*.swift` 只能 `import Foundation`，**禁止** `import OpenAgentSDK`、`import AppKit`。所有新模型是 `Codable, Equatable, Sendable` 的值类型。
- **AxionCLI 可用 AppKit**：App 发现/退出服务在 AxionCLI，`import AppKit` 直接用 `NSWorkspace` / `NSRunningApplication` / `Bundle`。**参考** `Sources/AxionCLI/Services/SeatActivityMonitor.swift` L1 `import AppKit`（证明 CLI 直接用 AppKit 是既有惯例）。
- **AxionCLI 禁止 import AxionHelper**：`Sources/AxionHelper/Services/AppLauncher.swift` 是 App 元数据读取的**参考范式**（Bundle 读取 L168-172、running 检测 L97-106、URL 解析 L108-150），但**只参考手法，不 import**。Helper 经 MCP stdio 调用，CLI 不直接链接。
- **AxionHelper 不做文件系统逻辑 / LLM**：本 Story 不改 Helper。

### 关键约束（最易踩坑，逐条对照实现）

1. **`~/Library` 恒定排除冲突（AC #13）**：`Sources/AxionCLI/Services/Storage/StorageExclusions.swift` 的 `evaluate(path:)` 对整个 `~/Library` 返回 `included=false`（L70 注释明示「39.3 support 扫描由其入口逐项确认，不走此默认集」）。**SupportDataScanService 严禁调用 `evaluate()`**，否则所有 support 候选被误杀。只允许 `StorageExclusions.standardize(_:home:)` 做标准化。安全由「精确 bundle-id 键控路径探测 + 共享目录保护 + 风险分级 + 确认」保障，而非广域排除集。
2. **卸载走独立 executor（AC #12）**：`Sources/AxionCLI/Services/Storage/StorageExecutor.swift` 的 `allowedActions = [.move, .trash, .createDirectory, .scanOnly]` **显式排除 `.uninstallApp`**（L24），其 `perform()` 的 `.uninstallApp` 分支是防御性兜底（返回 skipped/"action_not_allowed"，L286-297）。**不要改 StorageExecutor 去支持 uninstallApp**——语义差异大（需先退出 App、bundleId 校验、support 数据联动）。新建 `AppUninstallExecutor`。
3. **永不永久删除**：全代码路径**不出现** `FileManager.removeItem`（除非 39.2 `StorageUndoService` 撤销空目录的既有限定场景）。App bundle + support 数据一律 `FileManager.trashItem(at:resultingItemURL:)`（可恢复，撤销依赖 `resultingItemURL`）。**不存在 `delete` 动作**——`StorageAction` 无 `delete` case，工具解析阶段即丢弃任何 delete 入参。
4. **无 sudo / 无 Full Disk Access 前置**：MVP 只覆盖当前用户可读写范围。不可访问的 support 路径（如部分 `~/Library/Containers` 受 SIP 限制）→ 探测失败优雅降级为 hint，不阻塞 App bundle 卸载。**禁止**任何 `Process` 调 `sudo` / `pkgutil --forget` / `brew uninstall --zap` / vendor uninstaller。
5. **多候选不自动执行（AC #2）**：`AppUninstallPlanBuilder` 发现多候选且无 high 唯一解 → `blockedReasons += "ambiguous_match"`，把候选列表返回给入口让用户选；扫描工具绝不自动选第一个执行。
6. **系统/Apple/MDM/运行中默认阻断（AC #3, #4）**：`isSystemProtected == true` → `blockedReasons`；运行中需先 graceful 退出，退出失败不移动 bundle。
7. **共享目录保护（AC #8）**：vendor 父目录（`Application Support/Google` 等）、`Group Containers`（非唯一归属）、云同步目录 → 即使 vendor 名匹配也只处理证据精确指向 bundle id 的子项；无法证明唯一归属的 Group Container → scan-only（high risk, defaultSelected=false）；云/Keychain → forbidden，MVP 不处理。
8. **低置信度不进可执行集（AC #7）**：`matchConfidence == low` 的 support 项 → `hintOnlySupportDataItems`，`execute_app_uninstall` 拒绝执行（skipped + `low_confidence_hint_only`）。

### 复用清单（严禁重复造轮子）

| 复用对象 | 位置 | 用途 |
|---|---|---|
| `StorageAction.uninstallApp` | `StorageEnums.swift` L9 | **已存在**，App bundle manifest item 的 action |
| `DataRisk`（low/medium/high/forbidden） | `StorageEnums.swift` L34 | Support 数据风险，**直接复用** |
| `StorageConfidence`（high/medium/low） | `StorageEnums.swift` L42 | Support 匹配置信度，**直接复用** |
| `StorageEvidence`（rule/source/confidence） | `StorageEnums.swift` L49 | 匹配证据，**直接复用** |
| `RiskLevel.max` | `StorageEnums.swift` L20 | 风险聚合思路（`DataRisk` 含 forbidden 需自实现聚合） |
| `StorageSurface`（run/chat/telegram） | `StorageEnums.swift` L27 | manifest 入口字段 |
| `StorageManifest` + `StorageManifestItem` | `StorageManifest.swift` / `StorageManifestItem.swift` | manifest 落盘结构，**直接复用**，新增字段一律 `decodeIfPresent` |
| `StorageManifestStore` | `StorageManifestStore.swift` | `~/.axion/storage-ops/` 持久化，**共享同一实例**（AgentBuilder L175） |
| `StorageItemOutcome`（succeeded/failed/skipped） | `StorageItemOutcome.swift` | manifest item 结果 |
| `StorageOpStatus`（planned/executing/completed/partially_failed） | `StorageOpStatus.swift` | manifest 状态机 |
| `trashItem(at:resultingItemURL:)` | `StorageExecutor.swift` L256-284 | trash 范式，**直接用 FileManager**（AppUninstallExecutor 内） |
| 草稿先行 + 逐项写盘 + 终态判定 | `StorageExecutor.swift` L41-94 | manifest 生命周期范式，**照搬**到 AppUninstallExecutor |
| `readSize` 口径（totalFileSize ?? fileSize） | `StorageExecutor.swift` L303-315 | App bundle / support 目录体积，**照搬** |
| `ToolResultHelper`（requireStringParam/errorResult/encodeResult/successResult） | `Tools/ToolResultHelper.swift` | 工具入参校验与输出 |
| `ExecuteStoragePlanTool` 结构（isReadOnly/inputSchema/call/parse*） | `Tools/ExecuteStoragePlanTool.swift` | 副作用工具范式，**镜像**到 ExecuteAppUninstallTool |
| Mock 闭包注入模式 | `StorageScanning`/`MockStorageScanner`、Helper `AppLaunching`/`MockAppLauncher` | 单测注入范式 |
| `AxionError` | `Sources/AxionCore/` | **禁止**新建错误类型体系；用既有 `AxionError` |

### 新增能力（本 Story 首创，无既有实现）

- **App graceful 退出**：`AppQuitter`（`NSRunningApplication.requestTermination` + 超时轮询）。`grep -rn "terminate\|requestTermination" Sources/` 当前为空——确认是首创。**不 force-kill**。
- **App 发现 / support 扫描 / 卸载计划 / 卸载执行 / 外部 hint**：`grep -rn "AppCandidate\|SupportDataItem\|AppUninstallPlan" Sources/` 当前为空——确认 clean slate，全部新建。

### 命名规范

- Swift 类型 PascalCase（`AppUninstallExecutor`、`SupportDataItem`）。
- MCP / JSON / 工具入参字段 **snake_case**（`bundle_path`、`bundle_identifier`、`is_system_protected`、`match_confidence`、`data_risk`、`default_selected`、`requires_explicit_approval`、`external_uninstall_hints`、`blocked_reasons`、`uninstall_bundle`、`support_data_items`）。
- 工具名 snake_case 匹配 `^[a-z][a-z0-9_]*$`：`scan_app_uninstall`、`execute_app_uninstall`。
- 模型 `CodingKeys` 显式声明 snake_case + `init(from:)` 用 `decodeIfPresent` 回退（对齐 `StorageManifest`）。

### 反模式（来自 project-context.md，禁止）

- #3 **禁止 `print()`**：用 `ToolResultHelper` + SDK 输出处理器。
- #4 **MCP/JSON 字段必须 snake_case**。
- #5 **Prompt 不硬编码在 Swift**：如需卸载相关 prompt 文本，放 `Sources/AxionCLI/Prompts/*.md`（本 Story 预计无需新 prompt——计划 JSON 自描述，由入口/系统 prompt 解释）。
- #9 **禁止新建错误类型体系**：用 `AxionError`。
- #10 **禁止伪造测试**：Mock 必须真实注入、断言真实行为；文件探测用真实临时目录。
- #20 **Chat/ 纯函数**：本 Story 无 chat 改动。

### 审批与确认语义（与 39.4 边界）

- 本 Story 的 `execute_app_uninstall` 入参即「**已批准的执行集**」——`uninstall_bundle`（Bool）+ 哪些 `support_data_items` 已批准（与 39.2 `execute_storage_plan` 同口径）。**审批决策（终端确认 / 逐项确认 / typed 确认）由入口在调用工具前完成**。
- `requiresTypedConfirmation` 是 `AppUninstallPlan` 的计划级标志（高风险时为 true）；typed 确认的实际强制由入口实现，39.4 统一结构化 `approveItem` 语义。本 Story 只产标志 + 字段，执行器不重复判 typed（信任入参已批准）。
- 工具级纵深防御（AC #12）只做「硬安全校验」（路径/系统/bundleId/forbidden/low-confidence），不做「UI 确认状态」判断。

## Project Structure Notes

新增文件（全部新建，不动既有模型/executor 逻辑——除 Task 6 对 `StorageUndoService` 的单 case 扩展）：

```
Sources/AxionCore/Models/Storage/App/
  AppMatchConfidence.swift          # Task 1.1
  AppCandidate.swift                # Task 1.2
  SupportDataCategory.swift         # Task 1.3
  SupportDataItem.swift             # Task 1.4
  AppUninstallMode.swift            # Task 1.5
  DataLossRisk.swift                # Task 1.6
  ExternalUninstallHint.swift       # Task 1.7
  AppUninstallPlan.swift            # Task 1.8

Sources/AxionCLI/Services/Storage/App/
  AppDiscovering.swift              # Task 2.1（protocol）
  AppDiscoveryService.swift         # Task 2.2（import AppKit）
  SupportDataScanning.swift         # Task 3.1（protocol）
  SupportDataScanService.swift      # Task 3.2
  AppUninstallPlanBuilder.swift     # Task 4.1
  ExternalHintReading.swift         # Task 4.2（protocol + reader）
  AppQuitting.swift                 # Task 5.1（protocol）
  AppQuitter.swift                  # Task 5.2（import AppKit）
  AppUninstallExecuting.swift       # Task 5.3（protocol + request/result）
  AppUninstallExecutor.swift        # Task 5.4

Sources/AxionCLI/Tools/
  ScanAppUninstallTool.swift        # Task 7.1（isReadOnly = true）
  ExecuteAppUninstallTool.swift     # Task 8.1（isReadOnly = false）

Tests/AxionCoreTests/Models/
  AppUninstallPlanCodecTests.swift  # Task 1.9
Tests/AxionCLITests/Services/
  AppDiscoveryTests.swift           # Task 2.3
  SupportDataScanServiceTests.swift # Task 3.3
  AppUninstallPlanBuilderTests.swift# Task 4.3
  AppUninstallExecutorTests.swift   # Task 5.5
Tests/AxionCLITests/Tools/
  ScanAppUninstallToolTests.swift   # Task 7.2
  ExecuteAppUninstallToolTests.swift# Task 8.2
```

修改既有文件（**最小侵入**）：

- `Sources/AxionCLI/Services/Storage/StorageUndoService.swift`：Task 6.1——`undoItem` 的 `.uninstallApp` case 从 skipped 改为恢复逻辑（单 case 分支）。
- `Sources/AxionCLI/Services/AgentBuilder.swift`：Task 9.1——`if !dryrun` 存储块（L169-184）末尾追加 2 个工具注册。

**冲突/方差说明**：

- `AppMatchConfidence` 与既有 `StorageConfidence` 均为 high/medium/low，但语义不同（前者 = 用户输入→候选 App 匹配；后者 = support 证据置信度）。**故意分开**两个 enum，避免语义混淆。`SupportDataItem.matchConfidence` 复用 `StorageConfidence`（support 证据置信度），`AppCandidate.matchConfidence` 用 `AppMatchConfidence`（App 匹配）。
- 新建 `App/` 子目录而非平铺 `Storage/`：39.3 新增约 8 个模型 + 9 个服务 + 2 个工具，子目录保持 `Storage/` 整洁，与 39.1/39.2 平铺文件不冲突。
- `AppUninstallExecutor` 与 `StorageExecutor` 并存：前者处理 App 卸载语义（退出 + bundleId 校验 + support 联动），后者处理通用 move/trash/createDirectory。两者共享 `StorageManifestStore` + `StorageManifest`，不共享执行逻辑。

## References

- [Source: docs/epics/epic-39-mac-storage-file-app-management.md#3-卸载-app-与-support-数据清理]（L176-351）——本 Story 唯一权威需求源：App 识别字段表（L221-234）、support 数据分类表（L237-251）、证据强度表（L255-261）、卸载计划字段表（L265-275）、support 数据项字段表（L277-288）、安装来源策略表（L290-300）、Acceptance Criteria（L302-351）
- [Source: docs/epics/epic-39-mac-storage-file-app-management.md#支持范围]（L191-207）——support 数据候选路径清单（`~/Library/...`）
- [Source: docs/epics/epic-39-mac-storage-file-app-management.md#卸载模式]（L209-219）——5 种模式定义
- [Source: _bmad-output/implementation-artifacts/39-1-safe-file-scan-plan-model.md]——`StoragePlan`/`StoragePlanItem`/`StorageAction`/`RiskLevel`/`StorageEvidence`/`DataRisk`/`StorageConfig` 模型来源；扫描服务 Protocol+Mock 范式
- [Source: _bmad-output/implementation-artifacts/39-2-organize-folder-execute-undo.md]——`StorageManifest`/`StorageManifestItem`/`StorageOpStatus`/`StorageItemOutcome`/`StorageManifestStore`/`StorageExecutor`（草稿先行/逐项写盘/终态判定/`trashItem`）/`StorageUndoService`/`execute_storage_plan`+`undo_storage_op` 工具范式
- [Source: Sources/AxionCore/Models/Storage/StorageEnums.swift]——`StorageAction.uninstallApp`（L9，已存在）、`RiskLevel.max`（L20）、`DataRisk`（L34）、`StorageConfidence`（L42）、`StorageEvidence`（L49）、`StorageSurface`（L27）
- [Source: Sources/AxionCore/Models/Storage/StorageManifest.swift] / [StorageManifestItem.swift]——manifest 复用结构（字段、snake_case CodingKeys、decodeIfPresent）
- [Source: Sources/AxionCLI/Services/Storage/StorageExecutor.swift]——草稿先行（L41-52）、纵深校验（L100-137）、`trashItem`（L256-284）、`readSize`（L303-315）、终态判定（L83）；`.uninstallApp` 防御性兜底（L286-297，证明卸载需独立 executor）
- [Source: Sources/AxionCLI/Services/Storage/StorageExclusions.swift] L70——`~/Library` 恒定排除注释；`standardize(_:home:)` 与 `evaluate(path:)` API（AC #13 关键约束）
- [Source: Sources/AxionCLI/Services/Storage/StorageManifestStore.swift]——`~/.axion/storage-ops/` 持久化 API（save/trySave/load/listRecent/mostRecentUndoable），共享实例来源
- [Source: Sources/AxionCLI/Services/Storage/StorageUndoService.swift] L74-77——`.uninstallApp` 当前 skipped，Task 6.1 扩展点
- [Source: Sources/AxionCLI/Tools/ExecuteStoragePlanTool.swift]——副作用工具范式（isReadOnly/inputSchema/call/parse*），`ExecuteAppUninstallTool` 镜像
- [Source: Sources/AxionCLI/Tools/ToolResultHelper.swift]——入参校验与输出（requireStringParam/errorResult/encodeResult）
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift] L166-184——存储工具注册块（`if !dryrun`），Task 9 追加点
- [Source: Sources/AxionHelper/Services/AppLauncher.swift] L168-172（Bundle 读取）、L97-106（running 检测）、L108-150（URL 解析）——**仅参考手法，不可 import**
- [Source: Sources/AxionCLI/Services/SeatActivityMonitor.swift] L1——证明 AxionCLI 直接 `import AppKit` 是既有惯例
- [Source: CLAUDE.md]——测试规则（Swift Testing only / 单测必须 Mock / 只跑单元测试目录）、Python 路径（本 Story 无关）、中文输出要求
- 外部设计参考（不引入代码/许可依赖）：[Pearcleaner](https://github.com/alienator88/Pearcleaner) 扫描路径/容器发现/搜索敏感度思路；[Homebrew Cask `zap`](https://docs.brew.sh/Cask-Cookbook#stanza-zap) support 分类与 `trash:` 优先策略——均只作只读 hint 候选来源，不绕过 Axion 安全策略

## Dev Agent Record

### Agent Model Used

Claude Code dev-story agent（运行环境声明模型：GLM-5.1；BMAD dev-story 工作流）

### Debug Log References

- `swift build`（全量）：`Build complete!`（含 `AgentBuilder.swift` 重新编译注册两个新工具）。
- 单元测试全量：`3508 tests in 224 suites`，`7 issues`——**7 个全部为 `DesktopNotifierTests.swift`**（OSC 9 序列断言）。
- baseline 验证（`git stash -u` 后于 clean HEAD `574ad25` 复跑 `--filter "DesktopNotifierTests"`）：**同样 7 个失败**，证明为 tmux 环境既有问题（`TERM=tmux-256color` / `TMUX=present` → OSC 9 被包入 `Ptmux;` passthrough，测试断言原始 `\u{1B}]9;`），与本 Story 无关。`git stash pop` 还原全部 39.3 改动。
- 本 Story 6 个测试 suite 复跑：`63 tests in 6 suites passed`（SupportDataScanServiceTests 10、AppUninstallPlanBuilderTests 12、AppUninstallExecutorTests 9、ScanAppUninstallToolTests 7、ExecuteAppUninstallToolTests 10、StorageUndoServiceTests 15）。

### Completion Notes List

- **全部 AC #1–#15 已实现**：识别→计划→扫描→（确认后）执行→manifest→撤销闭环打通；执行工具入参即「已批准执行集」，审批 UI/typed 确认语义留给 39.4。
- **安全红线零违反**：全代码路径无 `FileManager.removeItem`（仅注释中作「绝不 removeItem」宣示）；bundle + support 一律 `trashItem`（可恢复）；无 `Process`/`sudo`/`pkgutil`/`brew uninstall`/vendor uninstaller；`SupportDataScanService` 未调 `evaluate()`（AC #13）；未改 `StorageExecutor`（AC #12，新建独立 `AppUninstallExecutor`）。
- **纵深防御**：`AppUninstallExecutor` 草稿先行 → 逐项校验（bundle：路径∈search_roots/非系统保护/存在且.app/bundleId 比对；support：策略门优先于存在性）→ 运行中先 graceful 退出（失败不移动，AC #3）→ `trashItem` → 终态 manifest。
- **撤销**：`StorageUndoService` 的 `.uninstallApp` case 从 skipped 改为与 `.trash` 一致的恢复逻辑（抽共享 `restoreFromTrash(_:action:)`，action 标记正确），15 测试全通过（11 旧 + 4 新）。
- **Mock 真实注入**：`AppDiscovering`/`SupportDataScanning`/`AppUninstallExecuting`/`AppQuitting`/`ExternalHintReading` 全部 Protocol+Mock 注入；`TrashPerforming` 注入临时目录避免污染真实废纸篓；文件探测用真实临时目录（`makeTempDir` + `defer cleanup`）。
- **Swift Testing only**：无 `import XCTest`；无 `print(`。
- **方差说明（相对 spec）**：
  - 两个工具测试置于 `Tests/AxionCLITests/Storage/`（而非 spec Project Structure 的 `Tests/AxionCLITests/Tools/`），与既有 `ExecuteStoragePlanToolTests`/`ScanAppUninstallToolTests`/`StorageUndoServiceTests` 聚集于 `Storage/` 保持一致（storage 工具测试统一目录）。
  - `ExecuteAppUninstallTool` 复用 `ExecuteStoragePlanTool.parseEvidence`/`parseSizeBytes`（DRY，非各自重写），新增 `parseApp`/`parseSupportItem`/`parseCategory`；增加 `search_roots` 必填 + `no_action_requested` 空集守卫（spec 未显式要求，但与 `ExecuteStoragePlanTool` 同口径并防止空执行）。
  - `AgentBuilder` 中 planBuilder 变量命名 `appPlanBuilder`（spec 示例为 `planBuilder`），仅为避免与同作用域潜在命名冲突，语义一致。

### File List

**新增（AxionCore 模型，8）**
- `Sources/AxionCore/Models/Storage/App/AppMatchConfidence.swift`
- `Sources/AxionCore/Models/Storage/App/AppCandidate.swift`
- `Sources/AxionCore/Models/Storage/App/SupportDataCategory.swift`
- `Sources/AxionCore/Models/Storage/App/SupportDataItem.swift`
- `Sources/AxionCore/Models/Storage/App/AppUninstallMode.swift`
- `Sources/AxionCore/Models/Storage/App/DataLossRisk.swift`
- `Sources/AxionCore/Models/Storage/App/ExternalUninstallHint.swift`
- `Sources/AxionCore/Models/Storage/App/AppUninstallPlan.swift`

**新增（AxionCLI 服务，10）**
- `Sources/AxionCLI/Services/Storage/App/AppDiscovering.swift`（protocol）
- `Sources/AxionCLI/Services/Storage/App/AppDiscoveryService.swift`（import AppKit）
- `Sources/AxionCLI/Services/Storage/App/SupportDataScanning.swift`（protocol）
- `Sources/AxionCLI/Services/Storage/App/SupportDataScanService.swift`
- `Sources/AxionCLI/Services/Storage/App/AppUninstallPlanBuilder.swift`
- `Sources/AxionCLI/Services/Storage/App/ExternalHintReading.swift`（protocol + reader）
- `Sources/AxionCLI/Services/Storage/App/AppQuitting.swift`（protocol）
- `Sources/AxionCLI/Services/Storage/App/AppQuitter.swift`（import AppKit）
- `Sources/AxionCLI/Services/Storage/App/AppUninstallExecuting.swift`（protocol + request/result）
- `Sources/AxionCLI/Services/Storage/App/AppUninstallExecutor.swift`（含 `TrashPerforming`）

**新增（AxionCLI 工具，2）**
- `Sources/AxionCLI/Tools/ScanAppUninstallTool.swift`（`isReadOnly = true`）
- `Sources/AxionCLI/Tools/ExecuteAppUninstallTool.swift`（`isReadOnly = false`）

**修改（AxionCLI，2）**
- `Sources/AxionCLI/Services/Storage/StorageUndoService.swift`（Task 6：`.uninstallApp` case 恢复逻辑 + 抽 `restoreFromTrash`）
- `Sources/AxionCLI/Services/AgentBuilder.swift`（Task 9：`if !dryrun` 块追加 `ScanAppUninstallTool` + `ExecuteAppUninstallTool` 注册）

**新增（测试，8）**
- `Tests/AxionCoreTests/Models/Storage/AppUninstallPlanCodecTests.swift`（Task 1.9）
- `Tests/AxionCLITests/Services/AppDiscoveryTests.swift`（Task 2.3，纯函数）
- `Tests/AxionCLITests/Services/SupportDataScanServiceTests.swift`（Task 3.3，10 测试）
- `Tests/AxionCLITests/Services/AppUninstallMocks.swift`（共享 Mock + helper，Task 4.3）
- `Tests/AxionCLITests/Services/AppUninstallPlanBuilderTests.swift`（Task 4.3，12 测试）
- `Tests/AxionCLITests/Services/AppUninstallExecutorTests.swift`（Task 5.5，9 测试）
- `Tests/AxionCLITests/Storage/ScanAppUninstallToolTests.swift`（Task 7.2，7 测试）
- `Tests/AxionCLITests/Storage/ExecuteAppUninstallToolTests.swift`（Task 8.2，10 测试）

**修改（测试，1）**
- `Tests/AxionCLITests/Storage/StorageUndoServiceTests.swift`（Task 6.2：追加 4 个 uninstallApp 撤销用例，15 测试全通过）

## Change Log

| 日期 | 改动 | 说明 |
|---|---|---|
| 2026-06-12 | Story 39.3 实现完成（Tasks 1–10） | 全部 AC #1–#15 满足；状态 `ready-for-dev` → `review`；63 个本 Story 单元测试全通过；7 个失败为既有 DesktopNotifier tmux 环境问题（baseline 已验证，与本 Story 无关） |
| 2026-06-12 | Code Review（AI，story-automator-review） | 对抗式评审通过：0 CRITICAL / 1 MEDIUM / 2 LOW。MEDIUM（support 路径未限制在 ~/Library）+ LOW（DataLossRisk.rank 死代码）已自动修复并补测；状态 `review` → `done`；82 测试全通过 |

## Senior Developer Review (AI)

**评审人**：story-automator-review（对抗式 code review，fresh context）
**评审日期**：2026-06-12
**结论**：✅ **通过（Changes Applied）** — 0 CRITICAL 遗留，状态置 `done`。

### 评审执行

- **Git vs Story File List 比对**：Story File List（8 模型 + 10 服务 + 2 工具 + 2 改动源文件 + 8 新增测试 + 1 改动测试）与 `git status`/`git diff` 完全一致。`.codex/`、`.gitignore` 改动为 story-automator 自动化配置（非应用源码），按评审规则排除。
- **Tasks [x] 审计**：Task 1–10 逐项核对实现文件，全部真实落地（无「标记完成但未实现」）。
- **AC #1–#15 验证**：逐条在实现中找到证据，全部 IMPLEMENTED。
- **测试质量**：8 个测试 suite 全部为真实断言（文件系统行为、解析、纵深校验、撤销），无占位测试。
- **安全红线 grep**：39.3 源码无 `import XCTest`、无 `print(`；`removeItem`/`sudo`/`pkgutil`/`brew uninstall`/`requestTermination`/`forceTerminate` 仅出现在**注释**（禁止宣示 / API 修正说明），无实际调用；`StorageExecutor.allowedActions` 仍排除 `.uninstallApp`（AC #12 独立 executor 约束保持）。
- **构建与测试**：`swift build` 通过；39.3 相关 suite `82 tests in 8 suites passed`。

### 发现与处置

| # | 严重度 | 发现 | 处置 |
|---|---|---|---|
| 1 | 🟡 MEDIUM | `AppUninstallExecutor.validateSupportItem` 仅校验**标志位**（matchConfidence / dataRisk / requiresExplicitApproval / 存在性），从未校验 support 路径是否在允许的 `~/Library` 区域内。AC #12 声明「与 39.2 executor 同理念」，39.2 对每项 source 做路径校验；39.3 的 bundle 已被 `searchRoots` 约束，但 support 项无路径约束——伪造请求（带低风险标志 + 任意用户可写路径）可把任意文件移入废纸篓。所有合法 support 路径都在 `~/Library`（`SupportDataScanService` 仅键控探测 `~/Library` 子路径）。 | ✅ **已修复**：`validateSupportItem` 新增 `home` 参数 + 「路径必须 ∈ `~/Library`」纵深防御（拒绝原因 `outside_user_library`，置于策略门之后、存在性之前，避免覆盖既有 `low_confidence_hint_only`/`shared_directory_not_approved`/`source_missing` 语义）；更新调用点与类文档；新增测试 `supportItemOutsideLibraryRejected`（伪造低风险项越界 → skipped + 文件不动）；调整 `partialFailureStatus` 的 missing 路径至 `~/Library` 下以保留 `source_missing` 语义。 |
| 2 | 🟢 LOW | `DataLossRisk.rank`（private 计算属性）为死代码——`max` 用数组 `firstIndex` 实现未引用 `rank`。 | ✅ **已修复**：删除 `rank`（`max` 行为不变，codec 测试覆盖）。 |
| 3 | 🟢 LOW | `AppUninstallPlanBuilder.isInside` 用 `FileManager.default.homeDirectoryForCurrentUser` 标准化，而 executor 其余路径用注入的 `homeDirectory`。实际无害（searchRoots 经工具层已展开 `~`/绝对化，二次标准化幂等，测试与生产均正确），仅为一致性瑕疵。 | ⚠️ **记录不改**：修正需贯穿 `validateBundle` 静态签名与全部调用点，属无行为变化的扰动；当前实现正确，留作后续清理。 |

### 修复验证

- `swift build`：`Build complete!`
- 39.3 相关 8 suite：`82 tests in 8 suites passed`（含新增 `supportItemOutsideLibraryRejected`）。
- 未引入 `import XCTest` / `print(` / `removeItem` / `Process` 等禁用项。

### Sprint Status 同步

- `sprint-status.yaml` → `39-3-app-uninstall-support-data-scan: review → done`。
