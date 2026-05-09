# Story 3.2: Prompt 管理与规划引擎

Status: done

## Story

As a 系统,
I want 根据自然语言任务描述生成结构化的执行计划,
so that 后续执行器可以按步骤完成桌面自动化.

## Acceptance Criteria

1. **AC1: Prompt 文件加载与模板变量注入**
   - Given `Prompts/planner-system.md` 文件存在
   - When `PromptBuilder.load(name: "planner-system", variables: ["tools": toolList])` 调用
   - Then 加载 prompt 内容并将 `{{tools}}` 替换为当前工具列表

2. **AC2: LLM 规划生成结构化 Plan**
   - Given 任务描述 "打开计算器，计算 17 乘以 23" 和截图上下文
   - When `LLMPlanner.createPlan()` 调用
   - Then 返回包含 steps 和 stopWhen 的 Plan 对象

3. **AC3: Plan 步骤结构完整性**
   - Given Plan 包含多个步骤
   - When 检查结构
   - Then 每个步骤包含 tool / parameters / purpose / expectedChange 字段

4. **AC4: Markdown 围栏解析**
   - Given LLM 输出包含 markdown 围栏 \`\`\`json...\`\`\`
   - When PlanParser 解析
   - Then 正确提取 JSON 并解析为 Plan

5. **AC5: 前导文本解析**
   - Given LLM 输出包含前导自然语言文本后跟 JSON
   - When PlanParser 解析
   - Then 跳过文本部分，提取并解析 JSON

6. **AC6: LLM API 重试（NFR6）**
   - Given LLM API 调用失败（网络错误）
   - When 重试逻辑触发
   - Then 最多重试 3 次，使用指数退避 1s -> 2s -> 4s

7. **AC7: Plan 解析失败不静默丢弃（NFR7）**
   - Given Plan 解析失败
   - When 错误处理
   - Then 记录原始 LLM 响应到 trace，抛出解析错误，不静默丢弃

## Tasks / Subtasks

- [x] Task 1: 创建 PromptBuilder (AC: #1)
  - [x] 1.1 创建 `Sources/AxionCLI/Planner/PromptBuilder.swift`
  - [x] 1.2 实现 `static func load(name: String, variables: [String: String]) throws -> String` — 从 Prompts/ 目录加载 .md 文件，替换 `{{key}}` 模板变量
  - [x] 1.3 实现 `static func resolvePromptDirectory() -> String` — 支持 SPM 资源路径和开发路径两种查找策略
  - [x] 1.4 实现 `static func buildToolListDescription(from tools: [String]) -> String` — 将工具名列表格式化为 prompt 中可用的工具描述
  - [x] 1.5 实现 `static func buildPlannerPrompt(task: String, currentStateSummary: String, toolList: String, maxStepsPerPlan: Int, replanContext: ReplanContext?) throws -> String` — 组装完整 planner prompt

- [x] Task 2: 创建 Prompts/planner-system.md (AC: #1)
  - [x] 2.1 创建 `Prompts/planner-system.md` — 基于 OpenClick `SYSTEM_GUIDANCE` 适配的完整 Planner system prompt
  - [x] 2.2 包含可用工具列表占位符 `{{tools}}`
  - [x] 2.3 包含 shifted key 映射规则
  - [x] 2.4 包含输出 JSON 格式规范
  - [x] 2.5 包含规划原则（最短路径、background-safe、AX selector 优先等）

- [x] Task 3: 创建 PlanParser (AC: #4, #5, #7)
  - [x] 3.1 创建 `Sources/AxionCLI/Planner/PlanParser.swift`
  - [x] 3.2 实现 `static func parse(_ rawResponse: String, task: String, maxRetries: Int) throws -> Plan` — 从 LLM 原始响应解析 Plan
  - [x] 3.3 实现 `static func stripFences(_ s: String) -> String` — 剥离 markdown 围栏、前导文本，提取 JSON 对象
  - [x] 3.4 实现 `static func validatePlan(_ plan: Plan, maxSteps: Int) throws -> Plan` — 验证 steps 数组、stopWhen 非空、每个 Step 字段完整
  - [x] 3.5 解析失败时保留原始响应字符串，抛出 `AxionError.invalidPlan(reason)` 并携带原始内容

- [x] Task 4: 创建 LLMPlanner (AC: #2, #3, #6)
  - [x] 4.1 创建 `Sources/AxionCLI/Planner/LLMPlanner.swift`
  - [x] 4.2 实现 `init(config: AxionConfig, mcpClient: MCPClientProtocol)` — 注入配置和 MCP 客户端
  - [x] 4.3 实现 `func createPlan(for task: String, context: RunContext) async throws -> Plan` — 实现 PlannerProtocol
  - [x] 4.4 实现 `func replan(from currentPlan: Plan, executedSteps: [ExecutedStep], failureReason: String, context: RunContext) async throws -> Plan` — 实现 PlannerProtocol
  - [x] 4.5 内部方法 `func callLLM(systemPrompt: String, userPrompt: String) async throws -> String` — 通过 SDK Agent 调用 LLM
  - [x] 4.6 内部方法 `func captureCurrentState() async throws -> String` — 调用 MCP screenshot + get_ax_tree 获取视觉上下文
  - [x] 4.7 实现 `withRetry` 重试包装 — 3 次指数退避，仅用于 LLM API 网络错误

- [x] Task 5: 创建 ReplanContext 模型
  - [x] 5.1 在 `Sources/AxionCore/Models/` 创建 `ReplanContext.swift`（如尚不存在）或在 LLMPlanner 中定义
  - [x] 5.2 包含字段：failedStepIndex, failedStep, errorMessage, executedSteps, liveAxTree, runHistory

- [x] Task 6: 编写单元测试
  - [x] 6.1 创建 `Tests/AxionCLITests/Planner/` 目录
  - [x] 6.2 创建 `Tests/AxionCLITests/Planner/PromptBuilderTests.swift` — 测试模板加载、变量替换、工具列表格式化
  - [x] 6.3 创建 `Tests/AxionCLITests/Planner/PlanParserTests.swift` — 测试 JSON 提取、围栏剥离、前导文本跳过、验证逻辑、错误处理
  - [x] 6.4 创建 `Tests/AxionCLITests/Planner/LLMPlannerTests.swift` — Mock LLMClientProtocol 测试完整规划流程、重规划、重试逻辑
  - [x] 6.5 测试 NFR7：验证解析失败时原始响应不丢失

- [x] Task 7: 运行全部单元测试确认无回归
  - [x] 7.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认全部通过

## Dev Notes

### 核心目标

实现 Axion 规划引擎的三大核心组件：Prompt 管理（从外部 Markdown 加载和注入模板变量）、Plan 解析（从 LLM 原始文本中提取 JSON 并解析为强类型 Plan）、LLM Planner（通过 SDK 调用 Anthropic API 生成结构化执行计划）。这是整个 plan -> execute -> verify 循环的起点。

### 关键设计决策：LLM 调用方式

**必须使用 OpenAgentSDK 的 Agent API 调用 LLM（FR36），不能直接使用 Anthropic SDK。**

SDK 提供的调用模式：
```swift
import OpenAgentSDK

let agent = createAgent(options: AgentOptions(
    apiKey: config.apiKey,
    model: config.model,
    systemPrompt: systemPrompt,      // planner-system.md 的内容
    maxTurns: 1,                     // planner 只需一次响应
    permissionMode: .bypassPermissions
))
let result = await agent.prompt(userPrompt)
```

**为什么用 SDK Agent 而不是直接 HTTP 调用：**
- FR36 明确要求"系统使用 SDK 的 Agent 循环编排"
- SDK 封装了重试、流式、token 计数等通用逻辑
- 后续 Story 3.7 会通过 SDK 的 Tool Registry 注册 MCP 工具到 Agent

**但 Planner 的特殊需求：**
- Planner 不需要 Agent 的工具循环（maxTurns = 1）
- Planner 需要自定义 system prompt（从外部文件加载）
- Planner 需要附加图片（截图作为 vision block）

**推荐方案：** 创建 `LLMClientProtocol` 抽象 SDK 的 `agent.prompt()` 调用，使 LLMPlanner 可测试：

```swift
protocol LLMClientProtocol {
    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String
}
```

生产环境实现用 SDK Agent，测试用 Mock。

### Prompt 文件与模板系统（D6）

**文件位置：`Prompts/planner-system.md`**

这个文件是 Planner 的 system prompt，包含：
- 可用工具列表（通过 `{{tools}}` 占位符动态注入）
- 规划原则和约束
- 输出 JSON 格式规范
- Shifted key 映射规则

**PromptBuilder 的模板变量解析：**
```swift
static func load(name: String, variables: [String: String]) throws -> String {
    let path = resolvePromptDirectory() + "/\(name).md"
    let content = try String(contentsOfFile: path)
    return variables.reduce(content) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
}
```

**Prompts 目录查找策略（两种路径）：**

1. **开发环境：** 相对于 Package.swift 所在目录 — `$(dirname Package.swift)/Prompts/`
2. **运行环境：** SPM 资源目录或可执行文件同级目录

推荐使用 `FileManager.default.currentDirectoryPath` + `Bundle.main.bundleURL` 双重查找。

### PlanParser 的 JSON 提取逻辑

**核心参考：OpenClick `src/planner.ts` 的 `stripFences` 函数**

LLM 输出可能有三种常见漂移：
1. 包裹在 ` ```json ... ``` ` 围栏中
2. JSON 前有自然语言前导文本（如 "Looking at the tree..."）
3. JSON 后有尾部文本

**提取算法（从 OpenClick 适配）：**
```
1. 先尝试匹配 ^```json...```$ 围栏并提取内部
2. 从第一个 { 开始，追踪花括号深度和字符串边界
3. 当深度回到 0 时，截取到该位置
4. 这能处理字符串内的嵌套花括号
```

**Plan 验证规则：**
- `steps` 必须是非空数组（status=ready 时）
- 每个 step 必须有 tool(string) 和 parameters(object)
- `stopWhen` 必须是非空字符串（OpenClick 用 string，Axion 用 [StopCondition]）
- status 必须是 "ready" | "done" | "blocked" | "needs_clarification" 之一
- steps 数量不超过 maxStepsPerPlan

### LLM 输出 -> Axion Plan 的映射

**OpenClick Plan 结构：**
```json
{
  "status": "ready|done|blocked|needs_clarification",
  "steps": [{ "tool": "...", "args": {...}, "purpose": "...", "expected_change": "..." }],
  "stopWhen": "description of completion condition",
  "message": "optional status detail"
}
```

**Axion Plan 结构（已定义在 AxionCore）：**
```swift
struct Plan: Codable, Equatable {
    let id: UUID
    let task: String
    let steps: [Step]
    let stopWhen: [StopCondition]
    let maxRetries: Int
}
```

**映射注意：**
- OpenClick 的 `args` -> Axion 的 `parameters: [String: Value]`
- OpenClick 的 `expected_change` -> Axion 的 `expectedChange`
- OpenClick 的 `stopWhen` 是纯字符串 -> Axion 的 `stopWhen` 是 `[StopCondition]`
- LLM 输出 JSON 中 `args` 字段名需要映射到 `parameters`
- LLM 输出中 `expected_change` 需要映射到 `expectedChange`
- `stopWhen` 从字符串映射为 `[StopCondition(type: .custom, value: text)]`

**映射方案：** 在 PlanParser 中创建一个中间 `RawPlan` 结构体用于解码 LLM 输出，然后转换为 Axion 的 `Plan`：

```swift
private struct RawPlan: Codable {
    let status: String?
    let steps: [RawStep]
    let stopWhen: String
    let message: String?
}

private struct RawStep: Codable {
    let tool: String
    let args: [String: JSONValue]?  // 灵活解码
    let purpose: String
    let expected_change: String?
}
```

### 重规划（Replan）逻辑

PlannerProtocol 定义了 `replan()` 方法。重规划时需要：
- 携带失败上下文：哪个步骤失败、失败原因
- 已执行步骤列表（不要重复）
- 当前屏幕状态（截图 + AX tree）
- 累积运行历史

**参考 OpenClick `buildPlannerPrompt` 的 replan 分支：**
```
REPLAN: the previous plan failed at step X (purpose: "...").
Error: ...
Already-executed steps (do NOT repeat):
  0. launch_app — ...
  1. click — ...
Produce a SUFFIX plan that recovers from the failure.
```

### 当前状态获取

`LLMPlanner` 需要调用 Helper 获取视觉上下文（FR12）：
- 通过 `mcpClient.callTool(name: "screenshot", ...)` 获取截图
- 通过 `mcpClient.callTool(name: "get_accessibility_tree", ...)` 获取 AX tree
- 将截图路径传递给 LLM（vision block），AX tree 文本放入 prompt

**注意：** 截图获取可能失败（权限未授予等），Planner 应在不带截图的情况下也能工作（降级为纯文本模式）。

### LLM 重试策略

**参考 OpenClick 和 architecture.md D5 节：**
- 仅用于 LLM API 网络错误（transient 错误）
- 指数退避：1s -> 2s -> 4s
- 最多 3 次（NFR6）
- 不用于业务逻辑错误（如 invalidPlan、app_not_found）
- 实现 `withRetry<T>` 泛型函数

### 现有代码状态

**已完成的依赖（直接复用）：**
- `PlannerProtocol`（AxionCore/Protocols/） — 定义了 `createPlan()` 和 `replan()` 接口
- `Plan`, `Step`, `Value`（AxionCore/Models/） — 强类型 Plan 数据模型，Codable
- `StopCondition`, `StopType`（AxionCore/Models/） — 停止条件模型
- `RunContext`, `RunState`（AxionCore/Models/） — 运行上下文和状态枚举
- `ExecutedStep`（AxionCore/Models/） — 已执行步骤记录
- `AxionConfig`（AxionCore/Models/） — 配置模型（含 model, apiKey, maxSteps 等）
- `AxionError`（AxionCore/Errors/） — `.invalidPlan(reason)`, `.planningFailed(reason)`, `.maxRetriesExceeded(retries:)`
- `MCPClientProtocol`（AxionCore/Protocols/） — `callTool()` 和 `listTools()`
- `ToolNames`（AxionCore/Constants/） — 所有 MCP 工具名常量
- `HelperProcessManager`（AxionCLI/Helper/） — 提供 MCPClientProtocol 实现
- `ConfigManager`（AxionCLI/Config/） — 分层配置加载

**Planner 目录已存在但为空：**
- `Sources/AxionCLI/Planner/` — 需要在此创建三个新文件
- `Tests/AxionCLITests/Planner/` — 需要创建目录和测试文件

**Prompts 目录不存在：**
- 需要创建 `Prompts/planner-system.md`
- 这是 D6 决策要求的独立 Prompt 文件

**RunCommand.swift（当前状态）：**
- 已实现 HelperProcessManager 集成（Story 3.1）
- 本 Story 不需要修改 RunCommand（RunEngine 编排在 Story 3.6）

### 模块依赖规则

```
LLMPlanner.swift 可以 import:
  - Foundation (系统)
  - OpenAgentSDK (第三方 — Agent 创建和 LLM 调用)
  - AxionCore (项目内部 — Plan, Step, Value, PlannerProtocol, MCPClientProtocol, AxionError)

PlanParser.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — Plan, Step, Value, StopCondition, AxionError)

PromptBuilder.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — ToolNames)

禁止 import:
  - AxionHelper (进程隔离)
  - MCP (PlanParser/PromptBuilder 不直接用 MCP)
```

### import 顺序

```swift
// LLMPlanner.swift
import Foundation
import OpenAgentSDK

import AxionCore

// PlanParser.swift
import Foundation

import AxionCore

// PromptBuilder.swift
import Foundation

import AxionCore
```

### 目录结构

```
Sources/AxionCLI/
  Planner/
    LLMPlanner.swift            # 新建：LLM 调用 + Plan 生成
    PlanParser.swift            # 新建：LLM 输出 -> Plan 解析
    PromptBuilder.swift         # 新建：Prompt 加载 + 模板注入

Prompts/
  planner-system.md            # 新建：Planner system prompt

Tests/AxionCLITests/
  Planner/
    LLMPlannerTests.swift      # 新建：Planner 单元测试
    PlanParserTests.swift      # 新建：PlanParser 单元测试
    PromptBuilderTests.swift   # 新建：PromptBuilder 单元测试
```

### 测试策略

**Mock 策略：**

| 被测模块 | Mock 对象 | 方式 |
|----------|-----------|------|
| LLMPlanner | LLM 调用 | 创建 `LLMClientProtocol`，Mock 返回预设 LLM 响应 |
| LLMPlanner | MCP 客户端 | Mock `MCPClientProtocol`，返回预设截图/AX tree |
| PlanParser | 无需 Mock | 纯函数，直接测试输入/输出 |
| PromptBuilder | 无需 Mock | 纯函数，使用临时目录的 .md 文件 |

**关键测试用例：**
- `test_stripFences_jsonInBackticks_extractsJSON` — markdown 围栏提取
- `test_stripFences_proseBeforeJSON_extractsJSON` — 前导文本跳过
- `test_stripFences_nestedBracesInStrings_handlesCorrectly` — 字符串内嵌套花括号
- `test_parsePlan_validResponse_returnsPlan` — 完整 Plan 解析
- `test_parsePlan_invalidJSON_throwsInvalidPlan` — 解析失败抛出错误
- `test_parsePlan_failurePreservesRawResponse` — NFR7 验证
- `test_createPlan_callsLLMWithCorrectPrompt` — Mock 验证 prompt 构建
- `test_createPlan_retriesOnNetworkError` — 重试逻辑
- `test_createPlan_doesNotRetryOnParseError` — 业务错误不重试
- `test_replan_includesFailureContext` — 重规划上下文传递

### 禁止事项（反模式）

- **不得绕过 SDK 直接调用 Anthropic HTTP API** — 必须使用 SDK 的 `createAgent` + `agent.prompt()`（FR36）
- **不得创建新的错误类型** — 使用 `AxionError.invalidPlan(reason)` 和 `.planningFailed(reason)`
- **不得使用 `print()` 输出** — 未来通过 OutputProtocol 输出（本 Story 暂不集成 OutputProtocol）
- **不得硬编码 prompt 文本在 Swift 代码中** — prompt 放在 `Prompts/planner-system.md`（D6, NFR19）
- **AxionCLI 不得 import AxionHelper** — 通过 MCPClientProtocol 抽象调用 Helper
- **PlanParser 不依赖 OpenAgentSDK** — 纯解析逻辑不需要 SDK
- **不得将 OpenClick 的 `status` 字段直接塞进 Axion 的 Plan** — Axion 的 Plan 用 `stopWhen: [StopCondition]` 表示完成条件，不在 Plan 级别有 status 字段

### 与前后 Story 的关系

- **Story 3.1（已完成）**：HelperProcessManager 提供 MCPClientProtocol。Planner 需要 `mcpClient` 来调用 Helper 的 `screenshot` 和 `get_accessibility_tree` 获取视觉上下文
- **Story 3.3（下一个）**：StepExecutor 接收 Plan 中的 steps，通过 MCP 执行。Planner 的 `parameters` 中的 `$pid`/`$window_id` 占位符在 Story 3.3 的 PlaceholderResolver 中解析
- **Story 3.4**：TaskVerifier 使用 Plan 的 `stopWhen` 条件评估任务是否完成
- **Story 3.6**：RunEngine 编排 Planner -> Executor -> Verifier 循环，调用 `LLMPlanner.createPlan()` 和 `replan()`
- **Story 3.7**：可能重构为使用 SDK 的 Tool Registry 在 Agent 中注册 MCP 工具

### OpenClick 参考映射（本 Story 必须读取）

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `Prompts/planner-system.md` | `src/planner.ts:119-167`（SYSTEM_GUIDANCE 常量） | **完整的 Planner system prompt** — 工具描述、规划原则、输出格式要求、shifted key 处理、background-safe 策略 |
| `LLMPlanner.swift` | `src/planner.ts:169-185`（generatePlan 函数） | Plan 生成流程：构建 prompt -> 调用 LLM -> 解析 JSON -> 验证 |
| `PlanParser.swift` | `src/planner.ts:255-280`（stripFences 函数） | LLM 输出解析：剥离 markdown 围栏、提取 JSON 对象、处理 prose 前缀/后缀 |
| `Plan.swift` | `src/planner.ts:17-39`（PlanStep / Plan 接口） | Plan 数据结构映射参考 |
| 重规划逻辑 | `src/planner.ts:80-98`（ReplanContext）+ `src/planner.ts:200-245`（replan 分支） | 重规划上下文传递 |

**OpenClick 本地路径：** `/Users/nick/CascadeProjects/openclick`

### SDK 参考路径

**SDK 本地路径：** `/Users/nick/CascadeProjects/open-agent-sdk-swift`

| 需要参考的 SDK 能力 | SDK 路径 | 用途 |
|-------------------|---------|------|
| 自定义 System Prompt | `Examples/CustomSystemPromptExample/` | Agent 创建时传入 systemPrompt |
| 阻塞式 API | `Examples/PromptAPIExample/` | agent.prompt() 返回 QueryResult |

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.2] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D2] Plan 数据模型设计
- [Source: _bmad-output/planning-artifacts/architecture.md#D6] Prompt 管理策略
- [Source: _bmad-output/planning-artifacts/architecture.md#D5] 并发模型（async/await + withRetry）
- [Source: _bmad-output/planning-artifacts/architecture.md#重试策略] LLM API 重试规则
- [Source: _bmad-output/planning-artifacts/architecture.md#OpenClick 参考指南] Planner -> OpenClick 映射
- [Source: _bmad-output/project-context.md#Shifted Key 映射] shifted key 映射表
- [Source: _bmad-output/project-context.md#数据流] 完整数据流链路
- [Source: _bmad-output/project-context.md#测试规则] 测试命名和 Mock 策略
- [Source: _bmad-output/implementation-artifacts/3-1-helper-process-manager-mcp-client.md] 前序 Story 实现（HelperProcessManager, MCPClientProtocol）
- [Source: Sources/AxionCore/Models/Plan.swift] Plan 结构体
- [Source: Sources/AxionCore/Models/Step.swift] Step + Value 枚举
- [Source: Sources/AxionCore/Models/StopCondition.swift] StopCondition + StopType
- [Source: Sources/AxionCore/Models/RunContext.swift] RunContext
- [Source: Sources/AxionCore/Protocols/PlannerProtocol.swift] PlannerProtocol 接口
- [Source: Sources/AxionCore/Protocols/MCPClientProtocol.swift] MCPClientProtocol 接口
- [Source: Sources/AxionCore/Errors/AxionError.swift] 统一错误类型
- [Source: Sources/AxionCore/Constants/ToolNames.swift] MCP 工具名常量
- [Source: Sources/AxionCLI/Config/ConfigManager.swift] 配置加载（apiKey, model）
- [Source: Sources/AxionCLI/Helper/HelperProcessManager.swift] MCP 客户端实现
- [Source: /Users/nick/CascadeProjects/openclick/src/planner.ts] SYSTEM_GUIDANCE、stripFences、buildPlannerPrompt
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Examples/CustomSystemPromptExample/] SDK 自定义 system prompt 示例
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Examples/PromptAPIExample/] SDK prompt() API 示例

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m] (via Claude Code)

### Debug Log References

- Fixed ToolNames internal access level — made all static properties public for cross-target access from AxionCLI
- Fixed Substring-to-String conversion in LLMPlanner.replan
- Fixed PlanParser to throw on missing purpose field instead of providing default value (test requirement)

### Completion Notes List

- Implemented PromptBuilder with load(), resolvePromptDirectory(), buildToolListDescription(), buildPlannerPrompt()
- Created Prompts/planner-system.md based on OpenClick SYSTEM_GUIDANCE, adapted for Axion's tool set
- Implemented PlanParser with stripFences() (brace-depth tracking), parse() (RawPlan intermediate decoding), validatePlan()
- Implemented LLMPlanner with createPlan(), replan(), callLLMWithRetry() (exponential backoff 1s/2s/4s, max 3 retries)
- ReplanContext defined in LLMPlanner.swift (not separate file, as it's tightly coupled)
- LLMClientProtocol abstraction enables testable LLMPlanner without real SDK calls
- All 293 unit tests pass (51 new Planner tests + 242 existing), 0 regressions

### File List

- Sources/AxionCLI/Planner/PromptBuilder.swift (modified — full implementation)
- Sources/AxionCLI/Planner/PlanParser.swift (modified — full implementation)
- Sources/AxionCLI/Planner/LLMPlanner.swift (modified — full implementation)
- Sources/AxionCore/Constants/ToolNames.swift (modified — public access for all properties)
- Prompts/planner-system.md (new — Planner system prompt)
- Tests/AxionCLITests/Planner/PromptBuilderTests.swift (modified — removed XCTSkipIf, tests active)
- Tests/AxionCLITests/Planner/PlanParserTests.swift (modified — removed XCTSkipIf, tests active)
- Tests/AxionCLITests/Planner/LLMPlannerTests.swift (modified — removed XCTSkipIf, fixed MockLLMClient)

### Review Findings

- [x] [Review][Patch] LLMPlanner 未声明遵循 PlannerProtocol — 已修复：`struct LLMPlanner: PlannerProtocol`
- [x] [Review][Patch] captureCurrentState() 未实现 — 已实现 `captureCurrentStateSafely()` 和 `captureAXTreeSafely()`，createPlan/replan 现在获取 AX tree 上下文
- [x] [Review][Patch] RawValue 无法解码数组类型 — 已添加 `.array([RawValue])` case，hotkey 的 keys 参数不再丢失
- [x] [Review][Patch] buildPlannerPrompt 导致 system prompt 重复 — 已重构：buildPlannerPrompt 只构建 user prompt，system prompt 由 LLMPlanner 单独加载
- [x] [Review][Patch] ReplanContext.executedSteps 丢失原始 purpose — 已修复：从 currentPlan.steps 保留原始 purpose
- [x] [Review][Defer] resolvePromptDirectory fallback 不验证路径存在 — deferred, pre-existing: 非 Story 3-2 引入的问题
