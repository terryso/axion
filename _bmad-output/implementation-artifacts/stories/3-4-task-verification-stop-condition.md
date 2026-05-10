# Story 3.4: 任务验证与停止条件评估

Status: review

## Story

As a 系统,
I want 在步骤执行完成后通过截图和 AX tree 验证任务是否完成,并结合 Plan 的 stopWhen 条件评估任务状态,
so that 系统可以判断是继续执行、重规划还是宣告完成.

## Acceptance Criteria

1. **AC1: 批次执行后获取验证上下文**
   - Given 批次步骤全部执行成功
   - When TaskVerifier 验证
   - Then 通过 MCP 调用 `screenshot` 和 `get_accessibility_tree` 获取当前屏幕状态作为验证上下文

2. **AC2: StopCondition 评估（LLM 辅助）**
   - Given Plan 定义 stopWhen 条件（如 `textAppears("391")`）
   - When StopConditionEvaluator 评估
   - Then 结合截图/AX tree 判断是否满足完成条件

3. **AC3: 任务完成状态 .done**
   - Given 验证通过，任务完成
   - When 评估结果返回
   - Then 状态为 `.done`

4. **AC4: 任务受阻状态 .blocked**
   - Given 验证发现任务受阻（如应用崩溃、元素不存在）
   - When 评估结果返回
   - Then 状态为 `.blocked`，携带阻塞原因

5. **AC5: 需要澄清状态 .needsClarification**
   - Given 任务描述不清晰或需要用户输入
   - When 评估结果返回
   - Then 状态为 `.needsClarification`，携带澄清问题

## Tasks / Subtasks

- [x] Task 1: 更新 VerifierProtocol (AC: #1-#5)
  - [x] 1.1 修改 `Sources/AxionCore/Protocols/VerifierProtocol.swift` — 将现有签名 `func verify(step:expectedChange:context:) -> Bool` 替换为新的签名，接收 Plan + ExecutedStep[]，返回 VerificationResult
  - [x] 1.2 定义 `VerificationResult` 结构体 — 包含 state: RunState, reason: String?, screenshot: String?, axTree: String?

- [x] Task 2: 创建 VerificationResult 模型 (AC: #3-#5)
  - [x] 2.1 创建 `Sources/AxionCore/Models/VerificationResult.swift`
  - [x] 2.2 定义 `VerificationResult: Codable, Equatable` — 字段: state (RunState), reason (String?), screenshotBase64 (String?), axTreeSnapshot (String?)
  - [x] 2.3 添加便捷工厂方法 `.done(reason:)`, `.blocked(reason:)`, `.needsClarification(reason:)`

- [x] Task 3: 创建 StopConditionEvaluator (AC: #2)
  - [x] 3.1 创建 `Sources/AxionCLI/Verifier/StopConditionEvaluator.swift`
  - [x] 3.2 实现 `func evaluate(stopConditions: [StopCondition], screenshot: String?, axTree: String?, executedSteps: [ExecutedStep]) -> StopEvaluationResult`
  - [x] 3.3 实现内置条件评估器: `windowAppears`, `windowDisappears`, `textAppears`, `processExits`, `maxStepsReached` — 对 AX tree / executed steps 进行本地匹配
  - [x] 3.4 实现 `custom` 类型条件 — 当内置评估器无法确定时，返回 `.uncertain`，由 TaskVerifier 调用 LLM 评估

- [x] Task 4: 创建 TaskVerifier (AC: #1, #2, #3, #4, #5)
  - [x] 4.1 创建 `Sources/AxionCLI/Verifier/TaskVerifier.swift`
  - [x] 4.2 实现 `struct TaskVerifier: VerifierProtocol` — 遵循更新后的 `VerifierProtocol`
  - [x] 4.3 实现 `init(mcpClient: MCPClientProtocol, llmClient: LLMClientProtocol, config: AxionConfig)` — 注入 MCP 和 LLM 客户端
  - [x] 4.4 实现 `func verify(plan: Plan, executedSteps: [ExecutedStep], context: RunContext) async throws -> VerificationResult` — 主验证方法
  - [x] 4.5 内部方法 `func captureVerificationContext(pid: Int?, windowId: Int?) async -> (screenshot: String?, axTree: String?)` — 调用 MCP screenshot + get_accessibility_tree
  - [x] 4.6 内部方法 `func evaluateWithLLM(task: String, stopConditions: [StopCondition], screenshot: String?, axTree: String?, executedSteps: [ExecutedStep]) async throws -> VerificationResult` — 将上下文发送给 LLM 判断任务状态

- [x] Task 5: 创建 Verifier Prompt (AC: #2)
  - [x] 5.1 创建 `Prompts/verifier-system.md` — Verifier 专用的 LLM system prompt，指导 LLM 判断任务是否完成
  - [x] 5.2 prompt 内容: 输入截图/AX tree/任务描述/stopWhen 条件，要求 LLM 输出 JSON `{"status": "done|blocked|needs_clarification", "reason": "..."}`

- [x] Task 6: 编写单元测试
  - [x] 6.1 创建 `Tests/AxionCLITests/Verifier/` 目录
  - [x] 6.2 创建 `Tests/AxionCLITests/Verifier/StopConditionEvaluatorTests.swift` — 测试 windowAppears/windowDisappears/textAppears/processExits/maxStepsReached 的本地匹配逻辑
  - [x] 6.3 创建 `Tests/AxionCLITests/Verifier/TaskVerifierTests.swift` — Mock MCPClientProtocol + LLMClientProtocol，测试: 截图+AX tree 获取、done/blocked/needsClarification 状态返回、MCP 调用失败降级处理、LLM 调用失败降级处理
  - [x] 6.4 创建 `Tests/AxionCoreTests/VerificationResultTests.swift` — Codable round-trip、工厂方法

- [x] Task 7: 运行全部单元测试确认无回归
  - [x] 7.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认全部通过

## Dev Notes

### 核心目标

实现 Axion 执行循环的验证阶段：TaskVerifier 在 StepExecutor 完成一批步骤后，获取当前屏幕状态（截图 + AX tree），结合 Plan 的 stopWhen 条件评估任务是否完成。这是 plan -> execute -> verify -> replan 循环中 "verify" 阶段的核心组件。

### 关键架构决策：Verifier 使用 LLM 辅助验证

与 Executor（纯机械执行、不涉及 LLM）不同，Verifier 需要 LLM 来判断任务是否真正完成。原因：
- stopWhen 条件是自然语言描述（如 "Calculator 显示 391"），无法纯规则匹配
- 截图和 AX tree 是非结构化数据，需要 LLM 理解语义
- LLM 判断更灵活，能处理各种意外状态（blocked, needs_clarification）

**但 LLM 不是唯一路径：** StopConditionEvaluator 先做本地规则匹配（textAppears 可在 AX tree 中搜索文本），只有无法确定时才调用 LLM。这是一种降级策略：
1. 内置规则匹配 → 确定 → 返回结果
2. 内置规则匹配 → 不确定 → LLM 评估 → 返回结果
3. LLM 评估失败 → 默认返回 .blocked（安全降级）

### Verifier 不使用 OpenAgentSDK Agent Loop

与 StepExecutor 相同理由：Verifier 的 LLM 调用是单次请求-响应（不是多轮对话），不需要 Agent Loop 的 turn 循环。直接使用 LLMClientProtocol 调用即可。SDK Agent Loop 在 RunEngine 层（Story 3-6）使用。

### 现有代码状态（直接复用）

**已完成的依赖：**
- `VerifierProtocol`（AxionCore/Protocols/） — 当前签名过于简单（只验证单步），需要扩展为验证整个批次
- `StopCondition` / `StopType`（AxionCore/Models/） — 已定义 7 种停止条件类型（windowAppears, windowDisappears, fileExists, textAppears, processExits, maxStepsReached, custom）
- `RunState`（AxionCore/Models/） — 包含 .done, .blocked, .needsClarification 等终态
- `ExecutedStep`（AxionCore/Models/） — 已执行步骤记录
- `RunContext`（AxionCore/Models/） — 运行上下文
- `MCPClientProtocol`（AxionCore/Protocols/） — `callTool(name:arguments:)`
- `ToolNames`（AxionCore/Constants/） — screenshot, getAccessibilityTree 等工具名
- `AxionError`（AxionCore/Errors/） — `.verificationFailed(step:reason:)` 已存在
- `LLMClientProtocol`（AxionCLI/Planner/LLMPlanner.swift 中定义） — `prompt(systemPrompt:userMessage:imagePaths:)` 协议
- `PromptBuilder`（AxionCLI/Planner/） — 已有 `load(name:variables:fromDirectory:)` 加载 prompt 文件

**Verifier 目录已存在但为空：**
- `Sources/AxionCLI/Verifier/` — 空目录，需要在此创建两个新文件
- `Tests/AxionCLITests/Verifier/` — 需要创建目录和测试文件

**Story 3-3 的实现模式（延续）：**
- StepExecutor 使用 Protocol 注入（MCPClientProtocol），使其可测试
- TaskVerifier 应遵循相同模式，通过 MCPClientProtocol + LLMClientProtocol 注入
- 测试使用 Mock MCPClientProtocol 和 Mock LLMClientProtocol

### VerifierProtocol 更新

**当前签名（过于简单，需要替换）：**
```swift
protocol VerifierProtocol {
    func verify(step: ExecutedStep, expectedChange: String, context: RunContext) async throws -> Bool
}
```

**新签名：**
```swift
public protocol VerifierProtocol {
    func verify(plan: Plan, executedSteps: [ExecutedStep], context: RunContext) async throws -> VerificationResult
}
```

**理由：** Verifier 需要整个 Plan 的 stopWhen 条件和所有已执行步骤的累积结果来做出判断，不是验证单个步骤。这是一个 breaking change，但由于 VerifierProtocol 目前没有实现者（Verifier 目录为空），修改无影响。

### VerificationResult 模型设计

```swift
public struct VerificationResult: Codable, Equatable {
    public let state: RunState       // .done, .blocked, .needsClarification
    public let reason: String?       // 人类可读的原因描述
    public let screenshotBase64: String?   // 验证时截取的截图（可选，用于 trace）
    public let axTreeSnapshot: String?     // 验证时的 AX tree 快照（可选，用于 trace）

    // 便捷工厂方法
    public static func done(reason: String? = nil) -> VerificationResult
    public static func blocked(reason: String) -> VerificationResult
    public static func needsClarification(reason: String) -> VerificationResult
}
```

**文件位置：** `Sources/AxionCore/Models/VerificationResult.swift` — 放在 AxionCore 因为 RunEngine（Story 3-6）和 Verifier 都需要使用。

### StopConditionEvaluator 设计

```swift
enum StopEvaluationResult {
    case satisfied           // 条件满足
    case notSatisfied        // 条件不满足
    case uncertain           // 无法确定，需要 LLM 评估
}

struct StopConditionEvaluator {
    func evaluate(
        stopConditions: [StopCondition],
        screenshot: String?,
        axTree: String?,
        executedSteps: [ExecutedStep]
    ) -> StopEvaluationResult
}
```

**内置条件评估逻辑：**

| StopType | 评估方式 | 数据源 |
|----------|----------|--------|
| `windowAppears` | 检查 AX tree 中是否出现匹配 value 的窗口标题 | axTree |
| `windowDisappears` | 检查 AX tree 中是否不再有匹配 value 的窗口 | axTree |
| `textAppears` | 在 AX tree 文本节点中搜索 value 字符串 | axTree |
| `processExits` | 检查 executedSteps 最后一个 list_apps 结果中是否不再有目标 pid | executedSteps |
| `maxStepsReached` | 检查 executedSteps.count >= config.maxSteps | executedSteps + config |
| `fileExists` | 需要调用 MCP get_file_info（暂不实现，返回 .uncertain） | MCP |
| `custom` | 无法规则匹配，返回 .uncertain，交给 LLM | LLM |

**AX tree 文本搜索实现要点：**
- `textAppears` 需要在 AX tree JSON 中搜索 `value` / `title` 字段
- AX tree 是 JSON 字符串，使用 JSONSerialization 解析后递归搜索
- 匹配策略：子字符串包含（大小写不敏感），而非精确匹配

### TaskVerifier 执行流程

```
TaskVerifier.verify(plan, executedSteps, context):
  1. 从 executedSteps / context 重建 ExecutionContext 获取 pid/windowId
  2. captureVerificationContext(pid, windowId):
     - 调用 mcpClient.callTool("screenshot", ...) → screenshotBase64
     - 调用 mcpClient.callTool("get_accessibility_tree", ...) → axTree
  3. stopConditionEvaluator.evaluate(plan.stopWhen, screenshot, axTree, executedSteps):
     - 如果 .satisfied → return VerificationResult.done(reason: ...)
     - 如果 .notSatisfied → return VerificationResult.blocked(reason: "条件未满足")
     - 如果 .uncertain → 调用 LLM 评估
  4. evaluateWithLLM(task, stopWhen, screenshot, axTree, executedSteps):
     - 加载 Prompts/verifier-system.md
     - 构建 userMessage（任务描述 + stopWhen + AX tree 摘要 + 已执行步骤摘要）
     - 调用 llmClient.prompt(systemPrompt, userMessage, imagePaths: [截图路径或空])
     - 解析 LLM JSON 响应 → VerificationResult
     - 解析失败 → 默认返回 .blocked(reason: "LLM 评估结果解析失败")
```

### verifier-system.md Prompt 设计

Verifier prompt 是一个新文件，指导 LLM 根据上下文判断任务状态。

```
你是一个任务验证器。你的任务是判断一个 macOS 桌面自动化任务是否完成。

输入：
- 用户任务描述
- stopWhen 完成条件
- 当前 AX tree（可访问性树）
- 已执行步骤摘要

输出 ONLY JSON: {"status": "done|blocked|needs_clarification", "reason": "..."}

判断标准：
- done: 所有 stopWhen 条件满足，任务已成功完成
- blocked: 任务无法继续（应用崩溃、元素不存在、操作失败）
- needs_clarification: 需要用户提供更多信息才能继续

OUTPUT FORMAT IS STRICT: emit ONLY the JSON object.
```

**文件位置：** `Prompts/verifier-system.md`

### LLM 调用与截图处理

**关键设计决策：Verifier 的 LLM 调用是否传入截图？**

MVP 决策：**不传截图给 LLM，只传 AX tree 文本。** 原因：
1. LLMClientProtocol 的 imagePaths 参数接受文件路径，但截图是 base64 内存数据，需要先写临时文件
2. Vision 模型调用成本远高于纯文本调用
3. AX tree 已经包含丰富的 UI 状态信息（文本内容、元素角色、层级关系）
4. 未来增强：当需要视觉验证时（如颜色、布局），可以启用截图传递

**降级策略：**
- screenshot 获取失败 → 仅用 AX tree 验证
- AX tree 获取失败 → 无法本地评估，直接 LLM 评估（无视觉上下文）
- LLM 评估失败 → 默认返回 .blocked（安全降级，触发重规划而非继续执行）

### ExecutionContext 复用

TaskVerifier 需要 pid 和 windowId 来调用 screenshot 和 get_accessibility_tree。这些信息需要从 executedSteps 中重建，复用 Story 3-3 的 PlaceholderResolver.absorbResult 逻辑：

```swift
// 从 executedSteps 重建 ExecutionContext（复用 StepExecutor 的逻辑）
private func buildExecutionContext(from executedSteps: [ExecutedStep]) -> ExecutionContext {
    var context = ExecutionContext()
    let resolver = PlaceholderResolver()
    for step in executedSteps where step.success {
        resolver.absorbResult(tool: step.tool, result: step.result, context: &context)
    }
    return context
}
```

PlaceholderResolver 是 `public struct`，可以直接在 TaskVerifier 中使用。

### MCP 调用参数

**screenshot 调用：**
```swift
// 有 windowId 时截取指定窗口
mcpClient.callTool(name: ToolNames.screenshot, arguments: ["window_id": .int(windowId)])
// 无 windowId 时截取全屏
mcpClient.callTool(name: ToolNames.screenshot, arguments: [:])
```

**get_accessibility_tree 调用：**
```swift
// 有 pid 和 windowId 时获取指定窗口的 AX tree
mcpClient.callTool(name: ToolNames.getAccessibilityTree, arguments: ["pid": .int(pid), "window_id": .int(windowId)])
// 仅有 pid 时获取该进程的 AX tree
mcpClient.callTool(name: ToolNames.getAccessibilityTree, arguments: ["pid": .int(pid)])
```

### 模块依赖规则

```
TaskVerifier.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — Plan, StopCondition, RunState, ExecutedStep, RunContext, MCPClientProtocol, ToolNames, AxionError, AxionConfig)

StopConditionEvaluator.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — StopCondition, StopType, ExecutedStep)

VerificationResult.swift (AxionCore):
  - Foundation (系统)

禁止 import:
  - AxionHelper (进程隔离)
  - OpenAgentSDK (Verifier 不需要 SDK Agent)
  - MCP (不直接使用 MCP 底层 API)
```

### import 顺序

```swift
// TaskVerifier.swift
import Foundation

import AxionCore

// StopConditionEvaluator.swift
import Foundation

import AxionCore

// VerificationResult.swift (AxionCore)
import Foundation
```

### 目录结构

```
Sources/AxionCore/Models/
  VerificationResult.swift           # 新建：验证结果模型

Sources/AxionCLI/Verifier/
  TaskVerifier.swift                 # 新建：任务验证主逻辑
  StopConditionEvaluator.swift       # 新建：stopWhen 条件评估

Sources/AxionCore/Protocols/
  VerifierProtocol.swift             # 修改：更新签名

Prompts/
  verifier-system.md                 # 新建：Verifier LLM prompt

Tests/AxionCoreTests/
  VerificationResultTests.swift      # 新建：VerificationResult 单元测试

Tests/AxionCLITests/Verifier/
  TaskVerifierTests.swift            # 新建：TaskVerifier 单元测试
  StopConditionEvaluatorTests.swift  # 新建：StopConditionEvaluator 单元测试
```

### 测试策略

**Mock 策略：**

| 被测模块 | Mock 对象 | 方式 |
|----------|-----------|------|
| TaskVerifier | MCP 客户端 | Mock `MCPClientProtocol`，返回预设的 screenshot/AX tree JSON |
| TaskVerifier | LLM 客户端 | Mock `LLMClientProtocol`，返回预设的验证结果 JSON |
| StopConditionEvaluator | 无需 Mock | 纯函数，直接测试输入/输出 |
| VerificationResult | 无需 Mock | 纯数据模型，Codable round-trip |

**Mock LLMClientProtocol 示例：**
```swift
struct MockLLMClient: LLMClientProtocol {
    var promptResult: String
    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String {
        return promptResult
    }
}
```

**关键测试用例：**
- `test_evaluate_textAppears_textFoundInAxTree_returnsSatisfied` — AX tree 中包含目标文本
- `test_evaluate_textAppears_textNotFound_returnsNotSatisfied` — AX tree 中不包含目标文本
- `test_evaluate_windowAppears_windowTitleFound_returnsSatisfied` — 窗口标题匹配
- `test_evaluate_maxStepsReached_stepsEqualMax_returnsSatisfied` — 步数达到上限
- `test_evaluate_customType_returnsUncertain` — custom 类型需要 LLM
- `test_verify_screenshotAndAxTreeCaptured_returnsDone` — 完整验证流程返回 done
- `test_verify_stopConditionNotMet_returnsBlocked` — 条件未满足返回 blocked
- `test_verify_llmReturnsNeedsClarification_returnsNeedsClarification` — LLM 返回 needs_clarification
- `test_verify_mcpFailure_degradesGracefully` — MCP 调用失败降级处理
- `test_verify_llmFailure_returnsBlocked` — LLM 调用失败安全降级
- `test_verificationResult_doneRoundTrip` — VerificationResult Codable round-trip
- `test_verificationResult_factoryMethods_correctState` — 工厂方法正确设置状态

### 禁止事项（反模式）

- **不得创建新的错误类型** — 使用 `AxionError.verificationFailed(step:reason:)`
- **不得使用 `print()` 输出** — 未来通过 OutputProtocol 输出（本 Story 暂不集成）
- **AxionCLI 不得 import AxionHelper** — 通过 MCPClientProtocol 抽象调用 Helper
- **Verifier 不得 import OpenAgentSDK** — Verifier 直接通过 LLMClientProtocol 调用 LLM，不经过 SDK Agent
- **不得将截图 base64 直接传给 LLM** — MVP 只传 AX tree 文本给 LLM，不传图片
- **不得在 TaskVerifier 中实现复杂的 AX tree 解析** — 简单的文本搜索即可满足 textAppears/windowAppears 条件，复杂解析留给 LLM
- **StopConditionEvaluator 不得调用 MCP** — 它是纯函数，只处理已获取的数据。MCP 调用由 TaskVerifier 负责

### 与前后 Story 的关系

- **Story 3.2（已完成）**：LLMPlanner 生成 Plan 的 stopWhen 字段。Verifier 消费 stopWhen 来判断任务是否完成。LLMPlanner 中定义的 LLMClientProtocol 将被 TaskVerifier 复用。PromptBuilder.load 方法将被 TaskVerifier 复用来加载 verifier-system.md。
- **Story 3.3（已完成）**：StepExecutor.executePlan 返回 (executedSteps, context)。TaskVerifier 接收 executedSteps 和 context 来验证。PlaceholderResolver 将被 TaskVerifier 复用来重建 ExecutionContext（获取 pid/windowId）。
- **Story 3.5（下一个）**：OutputProtocol 和 TraceRecorder 在验证过程中显示进度和记录 trace。本 Story 暂不集成，但 TaskVerifier 的设计应预留 output/trace 回调点。
- **Story 3.6**：RunEngine 编排 Planner -> Executor -> Verifier 循环。RunEngine 调用 `taskVerifier.verify(plan:executedSteps:context:)`，根据返回的 VerificationResult.state 决定下一步（done / replan / failed）。

### OpenClick 参考映射（本 Story 可选参考）

Story 3-4 的 Verifier 是 Axion 的独创设计。OpenClick 的验证逻辑分散在 `src/run.ts` 的主循环中（截图 + LLM 判断是否继续），没有独立的 Verifier 模块。

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `TaskVerifier.swift` | `src/run.ts`（批次循环中的 verify 阶段） | 截图获取后传给 LLM 判断是否继续的模式 |
| `StopConditionEvaluator.swift` | 无直接对应 | Axion 独创 — OpenClick 没有 stopWhen 概念 |
| `verifier-system.md` | `src/planner.ts:119-167`（SYSTEM_GUIDANCE）的验证相关部分 | 参考 prompt 结构和输出格式要求 |

**注意：** 本 Story 的 OpenClick 参考价值较低。Axion 的 Verifier 架构（独立模块 + StopCondition 类型系统 + 内置规则 + LLM 降级）是架构文档的创新设计，不需要照搬 OpenClick。

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.4] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D2] Plan 数据模型设计（含 StopCondition）
- [Source: _bmad-output/planning-artifacts/architecture.md#D3] 执行循环状态机（verify 阶段）
- [Source: _bmad-output/planning-artifacts/architecture.md#D6] Prompt 管理策略（verifier-system.md）
- [Source: _bmad-output/planning-artifacts/architecture.md#FR21-FR23] 任务验证功能需求
- [Source: _bmad-output/project-context.md#数据流] 完整数据流链路（TaskVerifier.verify 阶段）
- [Source: _bmad-output/project-context.md#执行循环状态机] 状态转换图（verifying -> done/blocked/needsClarification）
- [Source: _bmad-output/implementation-artifacts/3-3-step-execution-placeholder-resolution.md] 前序 Story（StepExecutor 实现）
- [Source: Sources/AxionCore/Protocols/VerifierProtocol.swift] 当前 VerifierProtocol 接口（需更新）
- [Source: Sources/AxionCore/Models/StopCondition.swift] StopCondition + StopType 定义
- [Source: Sources/AxionCore/Models/RunState.swift] RunState 枚举（含 .done, .blocked, .needsClarification）
- [Source: Sources/AxionCore/Models/ExecutedStep.swift] ExecutedStep 结构体
- [Source: Sources/AxionCore/Models/RunContext.swift] RunContext 结构体
- [Source: Sources/AxionCore/Protocols/MCPClientProtocol.swift] MCPClientProtocol 接口
- [Source: Sources/AxionCore/Constants/ToolNames.swift] MCP 工具名常量（screenshot, getAccessibilityTree）
- [Source: Sources/AxionCore/Errors/AxionError.swift] 统一错误类型（.verificationFailed）
- [Source: Sources/AxionCLI/Planner/LLMPlanner.swift] LLMClientProtocol 定义和 PromptBuilder 使用模式
- [Source: Sources/AxionCLI/Executor/PlaceholderResolver.swift] ExecutionContext 和 absorbResult（TaskVerifier 复用）
- [Source: Sources/AxionCLI/Executor/StepExecutor.swift] buildExecutionContext 模式（TaskVerifier 复用）

## Dev Agent Record

### Agent Model Used

Claude (GLM-5.1)

### Debug Log References

No blocking issues encountered during implementation.

### Completion Notes List

- Implemented VerificationResult model in AxionCore with Codable, Equatable conformance and factory methods (.done, .blocked, .needsClarification)
- Updated VerifierProtocol to accept Plan + executedSteps and return VerificationResult instead of the old Bool-based single-step signature
- Implemented StopConditionEvaluator as a pure function struct with local rule matching for textAppears, windowAppears, windowDisappears, processExits, maxStepsReached; returns .uncertain for custom and fileExists conditions
- Implemented TaskVerifier with full verification flow: MCP context capture (screenshot + AX tree), local condition evaluation, LLM-assisted evaluation for uncertain cases, and graceful degradation
- Created verifier-system.md prompt for LLM-assisted verification
- AX tree search uses recursive JSON traversal with case-insensitive substring matching on value/title/app_name/text fields
- All 45 new tests pass (9 VerificationResult + 18 StopConditionEvaluator + 18 TaskVerifier)
- Full regression suite: 403 tests pass, 0 failures

### File List

**New files:**
- Sources/AxionCore/Models/VerificationResult.swift
- Sources/AxionCLI/Verifier/StopConditionEvaluator.swift
- Sources/AxionCLI/Verifier/TaskVerifier.swift
- Prompts/verifier-system.md

**Modified files:**
- Sources/AxionCore/Protocols/VerifierProtocol.swift

**Test files (red-phase, pre-existing):**
- Tests/AxionCoreTests/VerificationResultTests.swift
- Tests/AxionCLITests/Verifier/StopConditionEvaluatorTests.swift
- Tests/AxionCLITests/Verifier/TaskVerifierTests.swift

### Change Log

- 2026-05-10: Implemented Story 3-4 — Task Verification & Stop Condition Evaluation (all 7 tasks, 45 tests passing, 0 regressions)
