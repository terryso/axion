# Story 4.2: App Profile 自动积累

Status: done

## Story

As a 系统,
I want 每次任务执行后自动提取 App 操作模式（AX tree 结构特征、selector 路径、操作序列频率、失败经验标记）,
so that 后续同 App 任务可以利用积累的经验，减少试错和重规划次数.

## Acceptance Criteria

1. **AC1: 成功操作后提取 AX tree 结构特征**
   Given Calculator 任务成功完成
   When 提取操作模式
   Then 记录：Calculator 的 AX tree 结构特征、常用按钮的 selector 路径、成功操作序列

2. **AC2: 识别高频操作路径**
   Given 同一 App 积累了多次操作记录（通过 SDK MemoryStore query 查询历史）
   When 分析操作模式
   Then 识别高频操作路径（如「打开 Finder → Cmd+Shift+G → 输入路径」是导航到指定目录的可靠路径）

3. **AC3: 标记失败经验**
   Given 操作失败后被重规划修正
   When 记录失败经验
   Then 标记失败的 selector/坐标为不可靠，记录修正后的成功路径

4. **AC4: 自动标记已熟悉 App**
   Given Memory 中某 App 积累了 3 次以上成功操作
   When 新任务涉及该 App
   Then 自动在该 App 的 Memory 中标记为「已熟悉」（添加 "familiar" tag）

## Tasks / Subtasks

- [x] Task 1: 创建 AppProfileAnalyzer 服务 (AC: #1, #2, #3)
  - [x] 1.1 创建 `Sources/AxionCLI/Memory/AppProfileAnalyzer.swift`
  - [x] 1.2 实现 `analyze(domain:history:current:) -> AppProfile` 方法，从历史 KnowledgeEntry 列表 + 本次运行结果中提取操作模式
  - [x] 1.3 模式提取内容：AX tree 结构特征摘要、成功 selector 路径、工具调用序列频率
  - [x] 1.4 失败经验标记：识别带 "failure" tag 的历史条目，提取失败原因和修正路径

- [x] Task 2: 增强 AppMemoryExtractor，支持 AX tree 和失败路径信息 (AC: #1, #3)
  - [x] 2.1 修改 `extract(from:task:runId:)` 方法的 ToolPair 处理逻辑
  - [x] 2.2 从 get_window_state / get_ax_tree 工具结果中提取 AX tree 结构特征（控件角色、标题、层级深度）
  - [x] 2.3 从重规划上下文中提取失败标记（如果 toolResult.isError == true，记录失败的工具和参数）
  - [x] 2.4 更新 KnowledgeEntry 的 content 格式，增加 AX tree 摘要和失败标记字段

- [x] Task 3: 创建 FamiliarityTracker 服务 (AC: #4)
  - [x] 3.1 创建 `Sources/AxionCLI/Memory/FamiliarityTracker.swift`
  - [x] 3.2 实现 `checkAndUpdateFamiliarity(domain:store:) async throws` 方法
  - [x] 3.3 查询 domain 下所有成功记录，若 >= 3 条则添加/更新 "familiar" 标记
  - [x] 3.4 使用 SDK `query(domain:filter:)` 过滤 tags 包含 "success" 的条目来统计成功次数

- [x] Task 4: 在 RunCommand 中集成 Profile 分析流程 (AC: #1–#4)
  - [x] 4.1 在 `RunCommand.run()` 的 Memory 提取阶段（已有的 `do { ... } catch { ... }` 块中），增强逻辑
  - [x] 4.2 提取完成后，查询该 domain 的历史记录
  - [x] 4.3 调用 AppProfileAnalyzer 分析并生成 AppProfile
  - [x] 4.4 将 AppProfile 作为新的 KnowledgeEntry 保存（tag 包含 "profile"）
  - [x] 4.5 调用 FamiliarityTracker 检查并更新熟悉度标记
  - [x] 4.6 所有 Memory 操作失败不阻塞任务完成（保留现有 do/catch 防护模式）

- [x] Task 5: 单元测试 (AC: #1–#4)
  - [x] 5.1 `Tests/AxionCLITests/Memory/AppProfileAnalyzerTests.swift` — 测试模式提取、高频路径识别、失败经验标记
  - [x] 5.2 `Tests/AxionCLITests/Memory/FamiliarityTrackerTests.swift` — 测试熟悉度阈值（<3 不标记，>=3 标记 familiar）
  - [x] 5.3 更新 `Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift` — 验证增强的 content 格式（AX tree 摘要、失败标记）

## Dev Notes

### 核心架构决策

**AppProfileAnalyzer 定位：** 纯计算服务（struct），无副作用。接收历史 KnowledgeEntry 列表和本次运行结果，返回结构化的 AppProfile。不直接操作 MemoryStore — 由 RunCommand 负责保存。

**FamiliarityTracker 定位：** 轻量服务（struct），仅负责读取 domain 的成功记录计数并决定是否标记熟悉度。调用方负责实际的 MemoryStore 写入。

**与 Story 4.1 的关系：** 本 Story 在 Story 4.1 创建的 `AppMemoryExtractor` 基础上增强，同时新增两个独立服务。不修改 `MemoryCleanupService` 或 `DoctorCommand`。

### SDK MemoryStore API 使用方式

查询历史记录：
```swift
let history = try await memoryStore.query(
    domain: domain,
    filter: KnowledgeQueryFilter(tags: ["success"])
)
// history: [KnowledgeEntry] — 所有带 "success" tag 的历史条目
```

保存 Profile 条目：
```swift
let profileEntry = KnowledgeEntry(
    id: UUID().uuidString,
    content: profileContent,  // 结构化文本
    tags: ["app:\(domain)", "profile"],
    createdAt: Date(),
    sourceRunId: nil  // Profile 是聚合结果，不关联单次运行
)
try await memoryStore.save(domain: domain, knowledge: profileEntry)
```

### KnowledgeEntry content 格式增强

Story 4.1 的 content 格式：
```
App: Calculator (com.apple.calculator)
任务: 打开计算器，计算 17 乘以 23
结果: success
工具序列: launch_app -> click -> click -> click -> click
步骤数: 5
```

本 Story 增强后的 content 格式（新增 AX tree 摘要和失败标记）：
```
App: Calculator (com.apple.calculator)
任务: 打开计算器，计算 17 乘以 23
结果: success
工具序列: launch_app -> click("17") -> click("*") -> click("23") -> click("=")
步骤数: 5
AX特征: 窗口包含 AXButton 角色控件，按钮标题与数字对应
关键控件: AXButton[title="17"], AXButton[title="*"], AXButton[title="="]
失败标记: (无)
```

失败场景的 content 格式：
```
App: Calculator (com.apple.calculator)
任务: 打开计算器，计算 17 乘以 23
结果: failure (后修正为 success)
工具序列: launch_app -> click(x:150,y:200) -> click(x:300,y:400) -> click(x:150,y:200) -> click(x:350,y:400)
步骤数: 4
AX特征: 窗口包含 AXButton 角色控件
失败标记: click(x:300,y:400) 坐标不可靠（未命中目标按钮）
修正路径: 使用 AX selector AXButton[title="*"] 代替坐标点击
```

### AppProfile 结构

AppProfileAnalyzer 输出的 AppProfile 应包含：
```swift
struct AppProfile {
    let domain: String              // App domain
    let totalRuns: Int              // 总运行次数
    let successfulRuns: Int         // 成功次数
    let failedRuns: Int             // 失败次数
    let commonPatterns: [OperationPattern]  // 高频操作路径
    let knownFailures: [FailurePattern]     // 已知失败模式
    let axCharacteristics: [String]         // AX tree 结构特征
    let isFamiliar: Bool            // 是否已熟悉（>=3 次成功）
}

struct OperationPattern {
    let sequence: [String]          // 工具序列（如 ["launch_app", "hotkey", "type_text"]）
    let frequency: Int              // 出现频率
    let successRate: Double         // 成功率
    let description: String         // 人类可读描述
}

struct FailurePattern {
    let failedAction: String        // 失败的操作描述
    let reason: String              // 失败原因
    let workaround: String?         // 修正路径
}
```

注意：这些是应用层内部类型，放在 `AxionCLI/Memory/` 目录，不放在 AxionCore。不需要 Codable — 它们只在运行时计算，不持久化。持久化通过 KnowledgeEntry.content 的文本格式完成。

### 从 ToolPair 中提取 AX tree 信息

ToolPair 中 get_window_state 或 get_ax_tree 工具的 toolResult.content 包含 AX tree JSON。提取策略：

1. 遍历所有 ToolPair，找到 `toolName` 包含 `get_window_state` 或 `get_ax_tree` 的配对
2. 解析 toolResult.content JSON，提取关键信息：
   - 控件角色类型（AXButton, AXTextField, AXStaticText 等）
   - 控件标题/值
   - 层级深度（简化为浅/中/深）
3. 生成结构化摘要文本，写入 KnowledgeEntry 的 content 中

AX tree JSON 的结构参考 `AxionHelper/Services/AccessibilityEngine.swift` 的输出格式。AX 节点包含 `role`、`title`、`value`、`bounds`、`children` 字段。

### 从 ToolPair 中提取失败信息

失败判断：`toolResult.isError == true` 的 ToolPair 即为失败操作。

提取内容：
- 失败的工具名和输入参数
- 失败的错误信息（toolResult.content 中的 error/message）
- 如果后续有成功的 ToolPair 完成了类似操作，则推断为「修正路径」

修正路径推断逻辑（简化版）：
- 如果一个 domain 内先失败后成功（连续的 toolUse/toolResult 中 isError 交替），将成功步骤记录为修正路径
- 不需要复杂的语义匹配 — 仅记录「失败的工具 → 后续成功的工具」序列

### 高频操作路径识别算法

```swift
// 简化版高频路径识别：
// 1. 从历史 entries 中提取每次运行的工具序列
// 2. 将连续的工具子序列作为 pattern
// 3. 统计 pattern 出现频率
// 4. 过滤 frequency >= 2 的 pattern 为「高频路径」
```

实现要点：
- 使用滑动窗口提取 2-4 步的子序列
- 统计完全匹配的子序列出现次数
- 只统计 "success" tag 的条目中的序列（失败序列不算高频）
- frequency 阈值：>= 2（至少出现 2 次才算高频）

### 需要修改的现有文件

1. **`Sources/AxionCLI/Memory/AppMemoryExtractor.swift`** [UPDATE]
   - 当前状态：从 ToolPair 提取基础操作摘要（App、任务、结果、工具序列、步骤数）
   - 本次修改：
     - 增强 content 格式，增加 AX tree 特征摘要和关键控件信息
     - 增加失败标记提取（从 isError=true 的 ToolPair 中提取失败描述）
     - 增加修正路径推断（失败后有成功的同类操作）
     - 增加工具参数摘要（从 toolUse.input 中提取关键参数如坐标、文本）
   - 必须保留：现有 extract 方法签名（保持向后兼容）、ToolPair typealias、groupByAppDomain 逻辑、tag 构建逻辑

2. **`Sources/AxionCLI/Commands/RunCommand.swift`** [UPDATE]
   - 当前状态：Memory 提取阶段在运行结束后，包含 AppMemoryExtractor 调用和 save 循环
   - 本次修改：
     - 在现有 Memory 提取和保存之后，增加 Profile 分析流程
     - 查询各 domain 的历史记录
     - 调用 AppProfileAnalyzer 分析
     - 保存 Profile KnowledgeEntry
     - 调用 FamiliarityTracker 更新熟悉度
   - 必须保留：所有现有功能（Agent 创建、流式输出、SafetyHook、Trace、Memory 提取和保存）

### 需要创建的新文件

1. **`Sources/AxionCLI/Memory/AppProfileAnalyzer.swift`** [NEW]
   - 纯计算 struct，无 MemoryStore 依赖
   - 输入：历史 `[KnowledgeEntry]` + 本次运行结果
   - 输出：`AppProfile` 结构

2. **`Sources/AxionCLI/Memory/FamiliarityTracker.swift`** [NEW]
   - 轻量 struct，接收 MemoryStoreProtocol
   - 查询成功记录数，>= 3 时保存 familiar 标记

### 测试策略

- **AppProfileAnalyzerTests**: 构造历史 KnowledgeEntry 数组测试模式提取逻辑
  - 测试空历史返回空 Profile
  - 测试单次运行提取基本特征
  - 测试多次运行识别高频路径
  - 测试混合成功/失败提取失败经验
  - 测试 >= 3 次成功标记 familiar

- **FamiliarityTrackerTests**: 使用 SDK InMemoryStore 测试
  - 测试 < 3 次成功不标记
  - 测试 >= 3 次成功标记 familiar
  - 测试已有 familiar 标记不重复添加

- **AppMemoryExtractorTests（更新）**: 验证增强的 content 格式
  - 测试包含 AX tree 工具时提取 AX 特征
  - 测试失败 ToolPair 提取失败标记
  - 测试失败后有成功操作时推断修正路径

### Import 顺序

```swift
// 1. 系统框架
import Foundation

// 2. 第三方依赖
import OpenAgentSDK

// 3. 项目内部模块
import AxionCore
```

### 错误处理

- 保持 Story 4.1 的错误处理模式：Memory 操作失败不阻塞任务完成
- AppProfileAnalyzer 是纯计算，不抛出错误（返回空结果而非抛异常）
- FamiliarityTracker 的 MemoryStore 操作用 do/catch 包裹，失败时 warning 日志

### 项目结构注意事项

- 新文件放在 `Sources/AxionCLI/Memory/` 目录（与 AppMemoryExtractor 同级）
- 测试文件放在 `Tests/AxionCLITests/Memory/` 镜像源结构
- AppProfile / OperationPattern / FailurePattern 是应用层内部类型，不放在 AxionCore
- 使用 SDK 提供的 KnowledgeEntry 和 MemoryStoreProtocol，不在 AxionCore 中创建新模型

### 与 Story 4.3 的关系

- **Story 4.3（Memory 增强规划）** 将使用本 Story 保存的 Profile KnowledgeEntry（tag: "profile"）和 familiar 标记
- Planner 将通过 `query(domain:filter: KnowledgeQueryFilter(tags: ["profile"]))` 读取 Profile
- 熟悉度标记 "familiar" tag 决定 Planner 使用紧凑还是详细规划策略
- 本 Story 的 Profile content 格式设计应考虑 Story 4.3 的 Planner 消费需求

### Story 4.1 的经验教训

- `AppMemoryExtractor` 已使用 `stripMcpPrefix` 处理 `mcp__axion-helper__` 前缀的工具名 — 新代码应使用相同方法
- Domain 从 tag `app:xxx` 中提取 — 保持一致
- KnowledgeEntry 的 content 使用中文标签描述（如 "任务:"、"结果:"）— 但 success/failure 用英文标签（Story 4.1 的 debug log 记录了中英文混用导致测试失败的问题）
- ToolPair 的匹配通过 `toolUseId` 完成 — 已在 RunCommand 中正确实现
- SDK AgentOptions init 参数顺序：`memoryStore` 必须在 `hookRegistry` 之前

### NFR 注意

- **NFR27**: Memory 存储占用磁盘空间 < 10MB — Profile 条目是聚合结果（每个 domain 一条），不会显著增加存储
- Memory 操作不应显著增加任务执行延迟 — Profile 分析放在运行结束后异步执行，与现有 Memory 提取在同一阶段
- **NFR28**: 不适用（NFR28 是 --fast 模式的 LLM 调用减少指标）

### Project Structure Notes

- 遵循现有 `Sources/AxionCLI/Memory/` 目录结构
- 新文件命名：`AppProfileAnalyzer.swift`、`FamiliarityTracker.swift`
- 测试文件命名镜像：`AppProfileAnalyzerTests.swift`、`FamiliarityTrackerTests.swift`
- Memory 功能仅涉及 AxionCLI 模块，不修改 AxionCore 或 AxionHelper

### References

- Story 4.1 实现文件: `Sources/AxionCLI/Memory/AppMemoryExtractor.swift`
- Story 4.1 实现文件: `Sources/AxionCLI/Memory/MemoryCleanupService.swift`
- RunCommand Memory 集成: `Sources/AxionCLI/Commands/RunCommand.swift` (lines 92-188)
- SDK MemoryStoreProtocol: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/MemoryTypes.swift`
- SDK FileBasedMemoryStore: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Stores/MemoryStore.swift`
- SDK KnowledgeEntry: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/MemoryTypes.swift`
- SDK KnowledgeQueryFilter: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/MemoryTypes.swift` (lines 35-56)
- Helper AX tree 输出: `Sources/AxionHelper/Services/AccessibilityEngine.swift`
- Epic 4 定义: `_bmad-output/planning-artifacts/epics.md` (Story 4.2)
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Project Context: `_bmad-output/project-context.md`
- Previous Story 4.1 file: `_bmad-output/implementation-artifacts/4-1-sdk-memorystore-app-memory-extraction.md`

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Fixed ATDD test compilation: `makeSuccessfulEntry`/`makeFailureEntry` helper methods needed `id:` parameter added to match call sites
- Fixed argument ordering in Swift: parameter labels must appear in declaration order
- Fixed sliding window range bounds crash: `2...min(4, seq.count)` causes `Range requires lowerBound <= upperBound` when seq.count < 2
- Fixed AX tree JSON parsing: `get_ax_tree` response uses `"root"` wrapper key instead of direct children
- Fixed high-frequency pattern test: `makeSuccessfulEntry` calls for Finder domain needed explicit `domain:` parameter

### Completion Notes List

- Created AppProfileAnalyzer (pure computation struct) with sliding window pattern recognition (2-4 step sub-sequences, frequency >= 2)
- Created FamiliarityTracker with threshold of 3 successful runs, uses SDK InMemoryStore for testing
- Enhanced AppMemoryExtractor to parse AX tree JSON from get_window_state/get_ax_tree results, extracting roles and titled controls
- Added failure marker extraction from isError=true ToolPairs and workaround inference from subsequent successful operations
- Added tool parameter summaries (click coordinates, type_text content, hotkey combos) in tool sequence display
- Integrated profile analysis flow in RunCommand after existing memory extraction, with do/catch protection for non-blocking operation
- All 54 new/updated unit tests pass (24 AppProfileAnalyzer + 10 FamiliarityTracker + 20 AppMemoryExtractor)
- Full regression suite: 928 tests pass with 0 failures

### File List

- Sources/AxionCLI/Memory/AppProfileAnalyzer.swift [NEW]
- Sources/AxionCLI/Memory/FamiliarityTracker.swift [NEW]
- Sources/AxionCLI/Memory/AppMemoryExtractor.swift [MODIFIED]
- Sources/AxionCLI/Commands/RunCommand.swift [MODIFIED]
- Tests/AxionCLITests/Memory/AppProfileAnalyzerTests.swift [NEW]
- Tests/AxionCLITests/Memory/FamiliarityTrackerTests.swift [NEW]
- Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift [MODIFIED]
- Tests/AxionCLITests/Commands/RunCommandProfileContentTests.swift [NEW]
- _bmad-output/implementation-artifacts/sprint-status.yaml [MODIFIED]

## Change Log

- 2026-05-13: Story 4.2 implementation complete — AppProfile auto-accumulation with AX tree extraction, failure markers, familiarity tracking
- 2026-05-13: Code review — 4 patches applied, 2 deferred, 1 dismissed
- 2026-05-14: Automated review — 3 patches applied (buildProfileContent tests, extractWorkaround same-type preference, File List correction)

### Review Findings

- [x] [Review][Patch] totalRuns counts profile and familiar metadata entries as runs [AppProfileAnalyzer.swift:66-68] — fixed: filter to entries with success/failure tags only
- [x] [Review][Patch] Parameterized tool names break pattern matching [AppProfileAnalyzer.swift:225-241] — fixed: strip parenthesized params in extractToolSequence
- [x] [Review][Patch] Redundant "失败标记: (无)" in success entries [AppMemoryExtractor.swift:85-87,145-147] — fixed: removed redundant output
- [x] [Review][Patch] Profile entries accumulate without cleanup [RunCommand.swift:200-209] — noted: SDK lacks tag-based delete; mitigated by totalRuns fix
- [x] [Review][Defer] Brittle keyword matching for failure reason classification [AppProfileAnalyzer.swift:254-263] — deferred, functional but fragile
- [x] [Review][Defer] Unbounded recursion in AX tree traversal [AppMemoryExtractor.swift:357-376] — deferred, defensive concern only
- [x] [Auto-Review][Patch] buildProfileContent untested [RunCommand.swift:383] — fixed: made static internal, added 11 tests in RunCommandProfileContentTests.swift
- [x] [Auto-Review][Patch] extractWorkaround picks unrelated tool type [AppMemoryExtractor.swift:409-437] — fixed: prefer same tool type match, fallback to first success
- [x] [Auto-Review][Patch] File List incomplete — corrected: added FamiliarityTrackerTests.swift, fixed AppProfileAnalyzerTests [NEW] label, added RunCommandProfileContentTests.swift
