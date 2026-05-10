# Story 3.3: 步骤执行与占位符解析

Status: done

## Story

As a 系统,
I want 按顺序执行 Plan 中的步骤并通过 MCP 调用 Helper，解析步骤参数中的占位符,
so that 自然语言指令被转化为实际的桌面操作，后续步骤可以引用前序步骤的动态结果.

## Acceptance Criteria

1. **AC1: MCP 工具调用执行步骤**
   - Given Plan 包含 `launch_app(Calculator)` 步骤
   - When StepExecutor 执行该步骤
   - Then 通过 MCP 调用 Helper 的 `launch_app` 工具，返回 pid

2. **AC2: `$pid` 占位符解析**
   - Given 后续步骤参数包含 `$pid`
   - When PlaceholderResolver 解析
   - Then 替换为前序步骤返回的 pid 值

3. **AC3: `$window_id` 占位符解析**
   - Given 后续步骤参数包含 `$window_id`
   - When PlaceholderResolver 解析
   - Then 替换为前序步骤返回的 window_id

4. **AC4: AX 定位前自动刷新窗口状态（FR18）**
   - Given 步骤需要 AX 定位操作（click, type_text 等）
   - When 执行前
   - Then 自动调用 `get_window_state` 刷新窗口状态，避免使用过期元素索引

5. **AC5: 步骤执行失败处理（FR19）**
   - Given 步骤执行失败（如应用未找到）
   - When StepExecutor 处理
   - Then 记录失败位置和原因，返回失败结果以触发重规划

6. **AC6: 共享座椅安全检查（FR20）**
   - Given 共享座椅模式启用，步骤为前台操作（click, type_text）
   - When SafetyChecker 检查
   - Then 阻止执行并返回安全策略错误

7. **AC7: `--allow-foreground` 模式放行**
   - Given `--allow-foreground` 模式（sharedSeatMode = false）
   - When SafetyChecker 检查前台操作
   - Then 允许执行

## Tasks / Subtasks

- [ ] Task 1: 创建 PlaceholderResolver (AC: #2, #3)
  - [ ] 1.1 创建 `Sources/AxionCLI/Executor/PlaceholderResolver.swift`
  - [ ] 1.2 定义 `ExecutionContext` 结构体 — 跟踪最近一次 pid 和 window_id（参考 OpenClick `ExecutorContext`，简化版：仅保留 pid, windowId, axIndex）
  - [ ] 1.3 实现 `func resolve(step: Step, context: ExecutionContext) -> Step` — 遍历 step.parameters，将 `.placeholder("$pid")` 替换为 context.pid，`.placeholder("$window_id")` 替换为 context.windowId
  - [ ] 1.4 实现 `func absorbResult(tool: String, result: String, context: inout ExecutionContext)` — 从 MCP 工具返回结果中提取 pid/window_id 更新 context（参考 OpenClick `absorbContext`）

- [ ] Task 2: 创建 SafetyChecker (AC: #6, #7)
  - [ ] 2.1 创建 `Sources/AxionCLI/Executor/SafetyChecker.swift`
  - [ ] 2.2 定义 `ToolSafetyCategory` 枚举 — `.backgroundSafe`, `.foregroundRequired`, `.unsupported`
  - [ ] 2.3 定义 Axion 的 `backgroundSafeTools` 集合 — 参考架构和 Helper 注册的 15 个工具，确定哪些是 background-safe（参考 OpenClick `BACKGROUND_SAFE_TOOLS`，但 Axion 的工具集不同）
  - [ ] 2.4 实现 `func check(tool: String, sharedSeatMode: Bool) -> SafetyCheckResult` — sharedSeatMode=true 时阻止 foregroundRequired 工具；sharedSeatMode=false 时放行所有工具
  - [ ] 2.5 实现 `func classifyTool(_ tool: String) -> ToolSafetyCategory` — 根据工具名返回安全分类

- [ ] Task 3: 创建 StepExecutor (AC: #1, #4, #5)
  - [ ] 3.1 创建 `Sources/AxionCLI/Executor/StepExecutor.swift`
  - [ ] 3.2 实现 `struct StepExecutor: ExecutorProtocol` — 遵循已有 `ExecutorProtocol` 接口
  - [ ] 3.3 实现 `init(mcpClient: MCPClientProtocol, config: AxionConfig)` — 注入 MCP 客户端和配置
  - [ ] 3.4 实现 `func executeStep(_ step: Step, context: RunContext) async throws -> ExecutedStep` — 主执行方法
  - [ ] 3.5 内部方法 `func executePlan(_ plan: Plan, context: RunContext) async throws -> (executedSteps: [ExecutedStep], context: RunContext)` — 逐步执行 Plan 中的所有步骤，每步都经过 PlaceholderResolver -> SafetyChecker -> MCP 调用 -> absorbResult
  - [ ] 3.6 内部方法 `func shouldRefreshBeforeAXOp(_ tool: String) -> Bool` — click, double_click, right_click, type_text 等 AX 定位操作前返回 true
  - [ ] 3.7 内部方法 `func refreshWindowState(context: inout ExecutionContext) async` — 调用 `get_window_state` 刷新 AX 状态（参考 OpenClick 的 `refreshBeforeAxClick` 逻辑）

- [ ] Task 4: 编写单元测试
  - [ ] 4.1 创建 `Tests/AxionCLITests/Executor/` 目录
  - [ ] 4.2 创建 `Tests/AxionCLITests/Executor/PlaceholderResolverTests.swift` — 测试 `$pid` 替换、`$window_id` 替换、多占位符混合、未解析占位符保留、absorbResult 提取 pid/windowId
  - [ ] 4.3 创建 `Tests/AxionCLITests/Executor/SafetyCheckerTests.swift` — 测试 background-safe 工具分类、foreground-required 工具分类、sharedSeatMode=true 阻止、sharedSeatMode=false 放行
  - [ ] 4.4 创建 `Tests/AxionCLITests/Executor/StepExecutorTests.swift` — Mock `MCPClientProtocol`，测试单步执行成功、占位符解析后执行、AX 刷新前执行、步骤失败返回失败结果、安全检查阻止
  - [ ] 4.5 测试 absorbResult 从 `launch_app` JSON 结果中提取 pid
  - [ ] 4.6 测试 absorbResult 从 `list_windows` JSON 结果中提取 window_id

- [ ] Task 5: 运行全部单元测试确认无回归
  - [ ] 5.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认全部通过

## Dev Notes

### 核心目标

实现 Axion 执行引擎的三大组件：PlaceholderResolver（从已执行步骤结果中解析 `$pid`/`$window_id` 占位符填充后续步骤参数）、SafetyChecker（共享座椅模式下阻止前台操作的安全策略）、StepExecutor（按顺序执行 Plan 步骤并通过 MCP 调用 Helper）。这是 plan -> execute -> verify 循环中的执行阶段。

### 关键架构决策：Executor 不使用 OpenAgentSDK Agent Loop

**StepExecutor 直接通过 MCPClientProtocol 调用 Helper，不通过 SDK Agent。**

原因：
- Executor 执行的是 Planner 已生成好的步骤序列，不需要 LLM 循环
- SDK Agent Loop 的价值在于编排 "LLM 思考 -> 工具调用 -> LLM 思考" 的循环
- Executor 是纯粹的 "执行步骤列表" 组件
- SDK Agent Loop 在 RunEngine 层（Story 3.6）使用，编排 Planner/Executor/Verifier 的外层循环

### 现有代码状态（直接复用）

**已完成的依赖：**
- `ExecutorProtocol`（AxionCore/Protocols/） — 定义了 `executeStep(_ step: Step, context: RunContext) async throws -> ExecutedStep` 接口
- `Plan`, `Step`, `Value`（AxionCore/Models/） — 强类型数据模型，Value.placeholder("$pid") 支持 `$pid`/`$window_id`
- `ExecutedStep`（AxionCore/Models/） — 已执行步骤记录，含 stepIndex, tool, parameters, result, success, timestamp
- `RunContext`（AxionCore/Models/） — 运行上下文，含 executedSteps, config 等
- `MCPClientProtocol`（AxionCore/Protocols/） — `callTool(name:arguments:)` 和 `listTools()`
- `ToolNames`（AxionCore/Constants/） — 20 个 MCP 工具名常量
- `AxionError`（AxionCore/Errors/） — `.executionFailed(step:reason:)`, `.mcpError(tool:reason:)`, `.cancelled` 等
- `AxionConfig`（AxionCore/Models/） — `sharedSeatMode: Bool` 控制安全策略

**Executor 目录已存在但为空：**
- `Sources/AxionCLI/Executor/` — 需要在此创建三个新文件
- `Tests/AxionCLITests/Executor/` — 需要创建目录和测试文件

**Story 3-2 的实现模式（延续）：**
- LLMPlanner 使用 Protocol 注入（LLMClientProtocol, MCPClientProtocol）使其可测试
- StepExecutor 应遵循相同模式，通过 MCPClientProtocol 注入而非直接使用 HelperProcessManager
- 测试使用 Mock MCPClientProtocol，返回预设的 JSON 字符串

### ExecutionContext 设计（参考 OpenClick 简化）

OpenClick 的 `ExecutorContext` 非常复杂（20+ 字段，含浏览器 tab、windowUid、actionability 检查等）。Axion MVP 阶段简化为：

```swift
struct ExecutionContext {
    var pid: Int?
    var windowId: Int?
    // AX index 暂不实现（Story 3.3 MVP 不需要 selector 解析，
    // planner-system.md 已指示 LLM 直接输出坐标而非 AX selector）
}
```

**为什么不需要 AX index：**
- OpenClick 的 AX index + selector 解析是为了在 cua-driver 后台模式下精确定位元素
- Axion 的 planner prompt 已指导 LLM 使用坐标（x, y）定位，不需要 element_index
- AX index 可以在后续 Story 中按需添加（预留 absorbResult 扩展点）

### PlaceholderResolver 的占位符解析逻辑

**核心参考：OpenClick `substitutePlaceholders` 函数**

Axion 简化版：
```swift
func resolve(step: Step, context: ExecutionContext) -> Step {
    var resolvedParams: [String: Value] = [:]
    for (key, value) in step.parameters {
        switch value {
        case .placeholder(let name) where name == "$pid" && context.pid != nil:
            resolvedParams[key] = .int(context.pid!)
        case .placeholder(let name) where name == "$window_id" && context.windowId != nil:
            resolvedParams[key] = .int(context.windowId!)
        default:
            resolvedParams[key] = value
        }
    }
    return Step(index: step.index, tool: step.tool, parameters: resolvedParams,
                purpose: step.purpose, expectedChange: step.expectedChange)
}
```

**占位符解析时机：** 在每步执行前解析，使用累积到当前步骤的 ExecutionContext。

### absorbResult — 从 MCP 返回结果提取上下文

**参考 OpenClick `absorbContext` 函数，简化版：**

MCP 工具返回 JSON 字符串。需要从返回结果中提取 pid 和 window_id：
- `launch_app` 返回 `{"pid": 1234, ...}` -> context.pid = 1234
- `list_windows` 返回 `{"windows": [{"window_id": 42, "pid": 1234, ...}]}` -> context.windowId = 42（取第一个可用窗口）
- `get_window_state` 返回 `{"window_id": 42, ...}` -> context.windowId = 42

实现方式：
```swift
func absorbResult(tool: String, result: String, context: inout ExecutionContext) {
    // 仅处理会产生 pid/window_id 的工具
    guard [.launchApp, .listWindows, .getWindowState].contains(tool) else { return }
    // 尝试 JSON 解析，提取 pid / window_id
    guard let data = result.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    if let pid = json["pid"] as? Int { context.pid = pid }
    if let windowId = json["window_id"] as? Int { context.windowId = windowId }
    // list_windows: 取 windows 数组的第一个窗口
    if let windows = json["windows"] as? [[String: Any]], let first = windows.first {
        if let pid = first["pid"] as? Int { context.pid = pid }
        if let windowId = first["window_id"] as? Int { context.windowId = windowId }
    }
}
```

### SafetyChecker 的工具安全分类

**参考 OpenClick `classifyToolSafety` 和 `BACKGROUND_SAFE_TOOLS`，适配 Axion 工具集。**

Axion 的工具安全分类（基于 Helper 注册的 20 个工具）：

**background-safe（不抢焦点、不移动光标、只读或指定窗口操作）：**
- launch_app, list_apps, quit_app, activate_window, list_windows, get_window_state, move_window, resize_window, screenshot, get_accessibility_tree, open_url, get_file_info
- click, double_click, right_click, type_text, press_key, hotkey, scroll, drag

**注意：** OpenClick 中区分 background-safe 和 foreground-required 的关键在于 cua-driver 的实现（agent cursor vs real cursor）。Axion 的 Helper 使用 AX API 操作（CGEvent 合成事件），在共享座椅模式下**所有这些操作都可能影响用户桌面**。因此 Axion 的安全策略需要更保守：

- **MVP 策略（简单可行）：** 当 `sharedSeatMode=true` 时，阻止所有可能影响前台的交互操作（click, double_click, right_click, type_text, press_key, hotkey, scroll, drag），仅允许只读操作（list_apps, list_windows, get_window_state, screenshot, get_accessibility_tree, open_url, launch_app, get_file_info）
- **未来增强：** 引入类似 OpenClick 的 cua-driver 后台模式，区分真正的后台安全操作

```swift
enum ToolSafetyCategory {
    case readOnly          // list_apps, list_windows, screenshot, get_ax_tree, get_file_info
    case backgroundSafe    // launch_app, open_url, get_window_state, move_window, resize_window
    case foregroundRequired // click, double_click, right_click, type_text, press_key, hotkey, scroll, drag
}
```

### StepExecutor 执行流程

**完整执行循环（单个 Plan）：**

```
对 Plan 中的每个 Step:
  1. PlaceholderResolver.resolve(step, context) — 替换 $pid/$window_id
  2. if shouldRefreshBeforeAXOp(tool):
       refreshWindowState(&context) — 调用 get_window_state
  3. SafetyChecker.check(tool, sharedSeatMode) — 检查安全策略
     - 如果被阻止 → 返回 ExecutedStep(success: false)
  4. mcpClient.callTool(name, arguments) — MCP JSON-RPC 调用
  5. absorbResult(tool, result, &context) — 更新执行上下文
  6. 构建 ExecutedStep 并记录到 RunContext
```

**参考 OpenClick `executePlan` 函数的关键模式：**
- 顺序执行（非并行）
- 每步失败立即停止，返回 failedStepIndex 和 error
- auto-refresh AX 在 AX 定位操作前
- absorbContext 在每步执行后从结果中提取上下文

### MCP 调用参数转换

Step.parameters 是 `[String: Value]`，但 MCPClientProtocol.callTool 接受 `[String: Value]`。需要将解析后的参数直接传递（Value 类型已在 AxionCore 中定义）。

**MCP 工具参数示例（snake_case）：**
```swift
// launch_app
["app_name": .string("Calculator")]

// click（占位符解析后）
["pid": .int(1234), "window_id": .int(42), "x": .int(100), "y": .int(200)]

// type_text（占位符解析后）
["pid": .int(1234), "window_id": .int(42), "text": .string("17*23=")]
```

### 模块依赖规则

```
StepExecutor.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — Step, Value, ExecutedStep, RunContext, Plan, MCPClientProtocol, AxionError, ToolNames, AxionConfig)

PlaceholderResolver.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — Step, Value, AxionError)

SafetyChecker.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — ToolNames, AxionError)

禁止 import:
  - AxionHelper (进程隔离)
  - OpenAgentSDK (Executor 不需要 SDK Agent)
  - MCP (不直接使用 MCP 底层 API)
```

### import 顺序

```swift
// StepExecutor.swift
import Foundation

import AxionCore

// PlaceholderResolver.swift
import Foundation

import AxionCore

// SafetyChecker.swift
import Foundation

import AxionCore
```

### 目录结构

```
Sources/AxionCLI/
  Executor/
    StepExecutor.swift          # 新建：步骤执行主逻辑
    PlaceholderResolver.swift   # 新建：$pid/$window_id 占位符解析
    SafetyChecker.swift         # 新建：共享座椅安全策略

Tests/AxionCLITests/
  Executor/
    StepExecutorTests.swift     # 新建：StepExecutor 单元测试
    PlaceholderResolverTests.swift  # 新建：PlaceholderResolver 单元测试
    SafetyCheckerTests.swift    # 新建：SafetyChecker 单元测试
```

### 测试策略

**Mock 策略：**

| 被测模块 | Mock 对象 | 方式 |
|----------|-----------|------|
| StepExecutor | MCP 客户端 | Mock `MCPClientProtocol`，返回预设 JSON 字符串 |
| PlaceholderResolver | 无需 Mock | 纯函数，直接测试输入/输出 |
| SafetyChecker | 无需 Mock | 纯函数，直接测试工具名 + 模式 |

**Mock MCPClientProtocol 示例：**
```swift
struct MockMCPClient: MCPClientProtocol {
    var callToolResult: String
    var listToolsResult: [String]

    func callTool(name: String, arguments: [String: Value]) async throws -> String {
        return callToolResult
    }
    func listTools() async throws -> [String] {
        return listToolsResult
    }
}
```

**关键测试用例：**
- `test_resolve_$pidPlaceholder_replacesWithPid` — `$pid` 替换
- `test_resolve_$windowIdPlaceholder_replacesWithWindowId` — `$window_id` 替换
- `test_resolve_unknownPlaceholder_preservesOriginal` — 未知占位符保持不变
- `test_resolve_noPlaceholder_preservesAllParams` — 无占位符不改变参数
- `test_absorbResult_launchApp_extractsPid` — 从 launch_app 结果提取 pid
- `test_absorbResult_listWindows_extractsWindowId` — 从 list_windows 结果提取 window_id
- `test_absorbResult_nonContextTool_doesNothing` — 非 pid/window_id 产出工具不改变 context
- `test_classifyTool_readOnlyTools_correctCategory` — 只读工具分类
- `test_classifyTool_foregroundTools_correctCategory` — 前台工具分类
- `test_check_sharedSeatMode_blocksForegroundTool` — 共享座椅模式阻止前台操作
- `test_check_allowForeground_allowsAllTools` — allow-foreground 模式放行
- `test_executeStep_launchApp_callsMCPAndReturnsSuccess` — 单步执行成功
- `test_executeStep_stepFailure_returnsFailedExecutedStep` — 步骤失败
- `test_executeStep_safetyBlocked_returnsSafetyError` — 安全检查阻止
- `test_executePlan_multipleSteps_resolvesPlaceholders` — 多步骤占位符链式解析

### 禁止事项（反模式）

- **不得创建新的错误类型** — 使用 `AxionError.executionFailed(step:reason:)` 和 `.mcpError(tool:reason:)`
- **不得使用 `print()` 输出** — 未来通过 OutputProtocol 输出（本 Story 暂不集成 OutputProtocol）
- **AxionCLI 不得 import AxionHelper** — 通过 MCPClientProtocol 抽象调用 Helper
- **Executor 不得 import OpenAgentSDK** — Executor 直接通过 MCPClientProtocol 调用，不经过 SDK Agent
- **不得实现 AX selector 解析（resolveSelector）** — MVP 阶段 planner prompt 使用坐标定位，不需要 AX selector
- **不得实现 window lease 验证** — OpenClick 的窗口租约验证（validate_window, revalidateWindowLease）过于复杂，MVP 不需要
- **不得实现 `__title` / `__ax_id` / `__selector` 替换** — Axion MVP 使用坐标定位，这些 selector 机制留给后续增强

### 与前后 Story 的关系

- **Story 3.1（已完成）**：HelperProcessManager 提供 MCPClientProtocol。Executor 需要 `mcpClient` 来调用 Helper 的工具
- **Story 3.2（已完成）**：LLMPlanner 生成 Plan（含 steps 和 stopWhen）。Executor 接收 Plan 中的 steps 执行。LLMPlanner 的 parameters 中的 `$pid`/`$window_id` 占位符在本 Story 的 PlaceholderResolver 中解析。Planner 已在 LLMClientProtocol 中定义了 Protocol 注入模式，Executor 应遵循
- **Story 3.4（下一个）**：TaskVerifier 接收 ExecutedStep[] 验证任务完成状态。StepExecutor 的 `executePlan` 返回 executedSteps 供 Verifier 使用
- **Story 3.5**：OutputProtocol 和 TraceRecorder 在执行过程中显示进度和记录 trace。本 Story 暂不集成，但 executePlan 的设计应预留 output/trace 回调点
- **Story 3.6**：RunEngine 编排 Planner -> Executor -> Verifier 循环，调用 `stepExecutor.executePlan()`

### OpenClick 参考映射（本 Story 必须读取）

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `PlaceholderResolver.swift` | `src/executor.ts:1548-1621`（substitutePlaceholders 函数） | 占位符解析：`$pid`/`$window_id` 替换、AX selector 机制（Axion MVP 不实现但需理解） |
| `PlaceholderResolver.swift` | `src/executor.ts:2026-2124`（absorbContext 函数） | 从工具返回结果中提取 pid/window_id 的上下文更新逻辑 |
| `StepExecutor.swift` | `src/executor.ts:400-645`（executePlan 函数） | 步骤执行主循环：顺序执行、失败即停、auto-refresh AX、安全检查、context 更新 |
| `StepExecutor.swift` | `src/executor.ts:12-18`（StepResult 接口） | 步骤执行结果模型（Axion 使用 ExecutedStep） |
| `SafetyChecker.swift` | `src/executor.ts:147-230`（classifyToolSafety / BACKGROUND_SAFE_TOOLS） | 工具安全分类逻辑、background vs foreground 策略 |
| `StepExecutor.swift` | `src/executor.ts:647-654`（AX_TARGETED_TOOLS） | AX 定位操作前刷新窗口的工具列表 |

**OpenClick 本地路径：** `/Users/nick/CascadeProjects/openclick`

**Axion 适配要点：**
- OpenClick 通过 `spawnSync` 调用 cua-driver 子进程执行每个步骤，Axion 通过 MCP stdio JSON-RPC 调用 AxionHelper — 通信机制完全不同
- OpenClick 的 ExecutorContext 有 20+ 字段（含浏览器 tab、windowUid 等），Axion MVP 简化为仅 pid + windowId
- OpenClick 的安全分类依赖 cua-driver 的后台模式能力，Axion 的 Helper 使用 AX API（CGEvent），需要更保守的策略
- OpenClick 的 `__title`/`__ax_id`/`__selector` AX selector 机制在 Axion MVP 中不实现

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.3] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D2] Plan 数据模型设计
- [Source: _bmad-output/planning-artifacts/architecture.md#D3] 执行循环状态机
- [Source: _bmad-output/planning-artifacts/architecture.md#D5] 并发模型（async/await）
- [Source: _bmad-output/planning-artifacts/architecture.md#D8] Helper 进程生命周期
- [Source: _bmad-output/planning-artifacts/architecture.md#FR16-FR20] 步骤执行功能需求
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR10] 共享座椅安全模式
- [Source: _bmad-output/planning-artifacts/architecture.md#OpenClick 参考指南#Executor] Executor -> OpenClick 映射
- [Source: _bmad-output/project-context.md#数据流] 完整数据流链路
- [Source: _bmad-output/project-context.md#测试规则] 测试命名和 Mock 策略
- [Source: _bmad-output/project-context.md#关键反模式] 必须避免的反模式
- [Source: _bmad-output/implementation-artifacts/3-2-prompt-management-planning-engine.md] 前序 Story（Planner 实现）
- [Source: Sources/AxionCore/Protocols/ExecutorProtocol.swift] ExecutorProtocol 接口
- [Source: Sources/AxionCore/Models/Step.swift] Step + Value 枚举（含 .placeholder）
- [Source: Sources/AxionCore/Models/ExecutedStep.swift] ExecutedStep 结构体
- [Source: Sources/AxionCore/Models/RunContext.swift] RunContext 结构体
- [Source: Sources/AxionCore/Protocols/MCPClientProtocol.swift] MCPClientProtocol 接口
- [Source: Sources/AxionCore/Constants/ToolNames.swift] MCP 工具名常量
- [Source: Sources/AxionCore/Errors/AxionError.swift] 统一错误类型
- [Source: Sources/AxionCore/Models/AxionConfig.swift] 配置模型（sharedSeatMode）
- [Source: /Users/nick/CascadeProjects/openclick/src/executor.ts] substitutePlaceholders, absorbContext, executePlan, classifyToolSafety

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
