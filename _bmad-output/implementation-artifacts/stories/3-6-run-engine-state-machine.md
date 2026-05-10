# Story 3.6: Run Engine 执行循环状态机

Status: done

## Story

As a 系统,
I want 通过状态机编排 plan -> execute -> verify -> replan 的完整循环,
so that 自然语言任务可以被完整执行和验证.

## Acceptance Criteria

1. **AC1: 状态机启动**
   - Given 运行 `axion run "打开计算器"`
   - When RunEngine 启动
   - Then 依次进入 planning -> executing -> verifying 状态

2. **AC2: 任务完成终态**
   - Given 验证结果为 .done
   - When 状态机转换
   - Then 进入 .done 终态，显示完成汇总

3. **AC3: 重规划循环**
   - Given 验证结果为 .blocked
   - When 状态机转换
   - Then 进入 replanning 状态，携带失败上下文重新调用 Planner

4. **AC4: 重规划后继续执行**
   - Given 重规划成功生成新 Plan
   - When 状态机继续
   - Then 回到 executing 状态执行新计划

5. **AC5: 最大重规划次数**
   - Given 重规划次数达到 maxReplanRetries（默认 3）
   - When 状态机判断
   - Then 进入 .failed 终态

6. **AC6: Ctrl-C 中断**
   - Given 用户按下 Ctrl-C
   - When 取消信号传播
   - Then 状态机进入 .cancelled，正确清理 Helper 进程

7. **AC7: 步数和批次限制**
   - Given 运行 `axion run "任务" --max-steps 5 --max-batches 3`
   - When 执行
   - Then 最多执行 5 个步骤和 3 个批次，超出则终止

8. **AC8: 干跑模式**
   - Given 运行 `axion run "任务" --dryrun`
   - When RunEngine 执行
   - Then Planner 生成计划后输出到终端，不调用 Helper 执行

9. **AC9: 前台模式**
   - Given 运行 `axion run "任务" --allow-foreground`
   - When SafetyChecker 检查
   - Then 允许前台/全局操作（click, type_text 等）

10. **AC10: needsClarification 处理**
    - Given 验证结果为 .needsClarification
    - When 状态机转换
    - Then 进入 .needsClarification 终态，携带澄清问题

11. **AC11: 不可恢复错误**
    - Given 发生不可恢复错误（如 API Key 无效、config 损坏）
    - When 状态机捕获
    - Then 进入 .failed 终态，显示用户友好的错误信息

12. **AC12: 步骤执行失败触发重规划**
    - Given 某个步骤执行失败
    - When StepExecutor 返回失败的 ExecutedStep
    - Then 跳过后续步骤和验证，直接进入 replanning 状态

## Tasks / Subtasks

- [ ] Task 1: 实现 RunEngine 状态机核心 (AC: #1-#5, #10-#12)
  - [ ] 1.1 创建 `Sources/AxionCLI/Engine/RunEngine.swift`
  - [ ] 1.2 定义 `RunEngine` struct，持有 planner/executor/verifier/output/trace 依赖
  - [ ] 1.3 实现 `func run(task:config:options:) async throws -> RunContext` — 主入口
  - [ ] 1.4 实现批次循环：planning -> executing -> verifying -> (done|blocked|replanning)
  - [ ] 1.5 实现状态转换逻辑：每个转换点调用 output.displayStateChange + trace.recordStateChange
  - [ ] 1.6 实现重规划逻辑：blocked -> replanning -> planning -> executing 循环，受 maxReplanRetries 控制
  - [ ] 1.7 实现批次计数和步数预算检查（maxBatches, maxSteps）
  - [ ] 1.8 实现 RunContext 的初始化和贯穿整个循环的状态更新

- [ ] Task 2: 实现 RunEngineOptions (AC: #7-#9)
  - [ ] 2.1 定义 `RunEngineOptions` struct：dryrun, allowForeground, maxSteps, maxBatches, verbose
  - [ ] 2.2 实现 RunEngineOptions 从 RunCommand 参数构建的工厂方法

- [ ] Task 3: 实现 RunId 生成 (AC: #1)
  - [ ] 3.1 在 AxionCore/Models/ 或 RunEngine 中实现 RunId 生成器
  - [ ] 3.2 格式：`YYYYMMDD-{6位随机小写字母数字}`

- [ ] Task 4: 集成到 RunCommand (AC: #1-#12)
  - [ ] 4.1 修改 `Sources/AxionCLI/Commands/RunCommand.swift` — 替换占位代码，调用 RunEngine
  - [ ] 4.2 在 RunCommand.run() 中加载配置（ConfigManager）、解析参数到 RunEngineOptions
  - [ ] 4.3 创建所有依赖实例：LLMPlanner, StepExecutor, TaskVerifier, Output（Terminal 或 JSON）, TraceRecorder
  - [ ] 4.4 将 HelperProcessManager 的 MCP 客户端传递给 planner/executor/verifier
  - [ ] 4.5 实现取消传播：withTaskCancellationHandler 包装 RunEngine.run()

- [ ] Task 5: 干跑模式实现 (AC: #8)
  - [ ] 5.1 在 RunEngine 中检查 dryrun 标志
  - [ ] 5.2 干跑模式：调用 Planner 生成 Plan 后，通过 output 显示计划，然后直接进入 .done
  - [ ] 5.3 干跑模式不启动 Helper、不执行步骤、不验证

- [ ] Task 6: 编写单元测试
  - [ ] 6.1 创建 `Tests/AxionCLITests/Engine/RunEngineTests.swift`
  - [ ] 6.2 Mock 所有 Protocol 依赖（PlannerProtocol, ExecutorProtocol, VerifierProtocol, OutputProtocol, MCPClientProtocol）
  - [ ] 6.3 测试：planning -> executing -> verifying -> done（正常完成路径）
  - [ ] 6.4 测试：planning -> executing -> verifying -> blocked -> replanning -> executing -> done（重规划成功路径）
  - [ ] 6.5 测试：maxReplanRetries 耗尽进入 .failed
  - [ ] 6.6 测试：maxBatches 限制
  - [ ] 6.7 测试：maxSteps 步数预算限制
  - [ ] 6.8 测试：步骤执行失败触发重规划
  - [ ] 6.9 测试：needsClarification 终态
  - [ ] 6.10 测试：dryrun 模式
  - [ ] 6.11 测试：不可恢复错误进入 .failed
  - [ ] 6.12 测试：RunId 格式和唯一性

- [ ] Task 7: 运行全部单元测试确认无回归
  - [ ] 7.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认全部通过

## Dev Notes

### 核心目标

实现 Axion 的「大脑」：RunEngine 状态机编排 plan -> execute -> verify -> replan 的完整循环。这是整个系统的核心编排模块，将前五个 Story 实现的组件（HelperProcessManager, LLMPlanner, StepExecutor, TaskVerifier, TerminalOutput/JSONOutput/TraceRecorder）串成一个完整的执行循环。

### 架构定位

RunEngine 是 CLI 层的顶层编排器，位于 `Sources/AxionCLI/Engine/RunEngine.swift`（架构文档项目结构中已定义）。

**依赖关系：**
```
RunCommand -> RunEngine -> { LLMPlanner, StepExecutor, TaskVerifier, Output, TraceRecorder }
```

RunEngine 通过 Protocol 持有所有依赖（PlannerProtocol, ExecutorProtocol, VerifierProtocol, OutputProtocol, TraceRecorder），使其完全可测试。

### 关键设计决策

#### 1. RunEngine 不是 Actor

RunEngine 本身是一个普通 struct，不使用 Actor 隔离。原因：
- RunEngine.run() 是一次性调用，内部状态只在单个 async 调用中修改
- 并发安全由内部的 Actor（TraceRecorder）和 MCPConnection 保证
- RunEngine 不需要跨 Task 共享状态

#### 2. 状态机是隐式的（不是显式 enum 驱动）

虽然 RunState enum 定义了 9 个状态，但状态机不需要一个显式的状态变量来驱动转换。实际实现使用结构化的 while 循环：

```swift
func run(task: String, config: AxionConfig, options: RunEngineOptions) async throws -> RunContext {
    var context = RunContext(...)
    var replanCount = 0
    var batchesUsed = 0

    // 外层批次循环
    while batchesUsed < config.maxBatches {
        // 1. Planning
        context.currentState = .planning
        let plan = try await planner.createPlan(for: task, context: context)

        if options.dryrun {
            output.displayPlan(plan)
            context.currentState = .done
            return context
        }

        batchesUsed++

        // 2. Executing
        context.currentState = .executing
        let (executedSteps, updatedContext) = try await executor.executePlan(plan, context: context)
        context = updatedContext

        // 检查步骤失败（ExecutedStep 中有失败的）
        let hasFailure = executedSteps.contains { !$0.success }

        if hasFailure {
            // 步骤失败 -> replanning
            replanCount++
            if replanCount > config.maxReplanRetries {
                context.currentState = .failed
                return context
            }
            context.currentState = .replanning
            // 重新循环（generatePlan 会传入 replanContext）
            continue
        }

        // 3. Verifying
        context.currentState = .verifying
        let verification = try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)

        switch verification.state {
        case .done:
            context.currentState = .done
            return context
        case .needsClarification:
            context.currentState = .needsClarification
            return context
        case .blocked:
            replanCount++
            if replanCount > config.maxReplanRetries {
                context.currentState = .failed
                return context
            }
            context.currentState = .replanning
            // 使用 planner.replan() 而非 createPlan()
            let newPlan = try await planner.replan(from: plan, executedSteps: executedSteps, failureReason: verification.reason ?? "blocked", context: context)
            // 继续 executing...
        default:
            context.currentState = .failed
            return context
        }
    }

    // 批次耗尽
    context.currentState = .failed
    return context
}
```

**关键：** 重规划逻辑需要区分「第一次规划」和「重规划」。第一次用 `planner.createPlan()`，后续用 `planner.replan()` 携带失败上下文。

#### 3. 步数预算检查

每个批次（plan）有自己的 steps 数组。RunEngine 需要跟踪累计执行的步骤数：

```swift
var totalStepsExecuted = 0

// 在执行每个 plan 后
totalStepsExecuted += executedSteps.count

if totalStepsExecuted >= config.maxSteps {
    // 步数预算耗尽
    break
}
```

**注意：** maxSteps 是累计限制（跨所有批次），不是单批次限制。单批次步数限制由 Planner prompt 控制（maxStepsPerPlan 参数）。

#### 4. RunId 生成策略

Run ID 格式：`YYYYMMDD-{6位随机小写字母数字}`。

建议将 RunId 生成放在 `RunEngine.swift` 内作为私有工具方法，或者在 AxionCore 中添加一个 `RunId.swift` 工具文件。保持简单：

```swift
private static func generateRunId() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let datePart = formatter.string(from: Date())
    let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    let randomPart = String((0..<6).map { _ in chars.randomElement()! })
    return "\(datePart)-\(randomPart)"
}
```

#### 5. Output 和 Trace 的调用时机

RunEngine 是 OutputProtocol 和 TraceRecorder 的主要消费者。在循环的每个关键点调用：

| 时机 | Output 调用 | Trace 调用 |
|------|-------------|------------|
| 运行启动 | `displayRunStart(runId, task, mode)` | `recordRunStart(runId, task, mode)` |
| Plan 生成 | `displayPlan(plan)` | `recordPlanCreated(steps, stopWhenCount)` |
| 步骤执行前 | （通过 executor.onStepStart 回调） | `recordStepStart(index, tool, purpose)` |
| 步骤执行后 | （通过 executor.onStepDone 回调） | `recordStepDone(index, tool, success, result)` |
| 状态转换 | `displayStateChange(from, to)` | `recordStateChange(from, to)` |
| 重规划触发 | `displayReplan(attempt, maxRetries, reason)` | `recordReplan(attempt, maxRetries, reason)` |
| 验证完成 | `displayVerificationResult(result)` | `recordVerificationResult(state, reason)` |
| 运行完成 | `displaySummary(context)` | `recordRunDone(totalSteps, durationMs, replanCount)` |
| 错误 | `displayError(error)` | `recordError(error, message)` |

**注意：** StepExecutor 已有 `onStepStart` 和 `onStepDone` 回调。RunEngine 应在创建 StepExecutor 后设置这些回调，将事件转发到 output 和 trace。

#### 6. RunCommand 的修改

当前 RunCommand 已有基础结构：
- `task: String` 参数
- `dryrun`, `maxSteps`, `maxBatches`, `allowForeground`, `verbose`, `json` 标志
- `HelperProcessManager` 的启动和取消传播

需要替换 `throw CleanExit.message(...)` 占位代码，改为：
1. 加载配置：`ConfigManager.load()` + CLI 参数覆盖
2. 创建 LLMClient（需要实现 Anthropic API 调用）
3. 创建 MCPClient（从 HelperProcessManager 获取）
4. 创建 Output 实例（json ? JSONOutput : TerminalOutput）
5. 创建 TraceRecorder（使用 runId 和 config）
6. 创建 LLMPlanner, StepExecutor, TaskVerifier
7. 创建 RunEngine 并调用 run()

**LLMClient 问题：** 当前代码中有 `LLMClientProtocol`（在 LLMPlanner.swift 中定义），但还没有实际的 Anthropic API 调用实现。RunCommand 需要创建一个真实的 LLMClient 实例。

**方案 A（推荐）：** 创建一个 `AnthropicClient` struct 实现 `LLMClientProtocol`，使用 URLSession 调用 Anthropic API。这个实现应该放在 `Sources/AxionCLI/Planner/AnthropicClient.swift`。

**方案 B：** 如果 OpenAgentSDK 已经提供 LLM 调用能力，直接使用 SDK。但根据架构文档，SDK 的 Agent Loop 是 Story 3-7 的内容。本 Story 先实现一个独立的 AnthropicClient。

#### 7. MCPClient 的获取

HelperProcessManager 管理 Helper 进程，但当前没有暴露 MCPClientProtocol 给外部使用。

RunCommand 需要：
```swift
let manager = HelperProcessManager()
try await manager.start()
let mcpClient = manager  // HelperProcessManager 应该实现 MCPClientProtocol
```

检查 HelperProcessManager 是否已实现 MCPClientProtocol。如果没有，需要在本 Story 中添加。

### 重规划循环的精确逻辑

重规划有两种触发场景：

**场景 A：步骤执行失败**
1. StepExecutor.executePlan() 返回 executedSteps（含失败步骤）
2. RunEngine 检查 `hasFailure = executedSteps.contains { !$0.success }`
3. 如果有失败，replanCount++
4. 如果超过 maxReplanRetries，进入 .failed
5. 否则进入 .replanning，调用 `planner.replan()`
6. 用新 Plan 继续执行

**场景 B：验证结果为 .blocked**
1. 所有步骤执行成功
2. TaskVerifier.verify() 返回 .blocked
3. replanCount++
4. 如果超过 maxReplanRetries，进入 .failed
5. 否则进入 .replanning，调用 `planner.replan()`
6. 用新 Plan 继续执行

**关键区别：** 场景 A 跳过验证（因为步骤已经失败了），场景 B 步骤都成功但任务未完成。

### 与前后 Story 的关系

- **Story 3-1（已完成）**：HelperProcessManager 管理 Helper 进程和 MCP 连接。RunCommand 使用它获取 MCPClient。
- **Story 3-2（已完成）**：LLMPlanner 实现 PlannerProtocol（createPlan + replan）。RunEngine 调用这两个方法。
- **Story 3-3（已完成）**：StepExecutor 实现 ExecutorProtocol（executeStep + executePlan）。RunEngine 调用 executePlan。
- **Story 3-4（已完成）**：TaskVerifier 实现 VerifierProtocol（verify）。RunEngine 调用 verify。
- **Story 3-5（已完成）**：TerminalOutput/JSONOutput 实现 OutputProtocol，TraceRecorder 实现 trace 记录。RunEngine 在每个关键点调用它们。
- **Story 3-7（下一个）**：SDK 集成将 RunEngine 的编排改为使用 SDK Agent Loop。本 Story 实现独立的状态机，Story 3-7 重构为 SDK 调用。

### OpenClick 参考映射

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `RunEngine.swift` | `src/run.ts:257-500`（runTaskFast 函数） | 批次循环结构：plan -> execute -> verify -> replan 的编排流程 |
| `RunEngine.swift` | `src/run.ts:54-98`（RunOptions 接口） | 运行参数模型：maxSteps, maxBatches, maxReplans, allowForeground, dryRun |
| `RunEngine.swift` | `src/run.ts:644-830`（主 while 循环） | 循环控制：批次计数、步数预算、中断处理、重规划触发条件 |
| `RunEngine.swift` | `src/run.ts:940-1060`（验证失败重规划） | 验证失败后的重规划上下文构建和下一批次规划 |
| `RunEngine.swift` | `src/run.ts:1196-1260`（action retry 循环） | 步骤失败重试：重规划次数限制、失败上下文传递 |

**关键参考点：**

OpenClick 的 `runTaskFast` 函数（第 257-500 行）是最直接的参考。其主循环结构为：
1. 生成 Plan（`generatePlan`）
2. 检查 plan.status（done/blocked/needs_clarification/has steps）
3. 执行 Plan（`executePlan`）
4. 验证 stopWhen（`budgetedVerifyStopWhen`）
5. 如果未通过验证，构建 replanContext，回到步骤 1

**OpenClick 的中断处理模式（参考但不照搬）：**
- SIGINT 设置 `aborted` 标志
- 循环顶部检查 `aborted`
- 第二次 SIGINT 强制退出
- Axion 使用 Swift 的 `withTaskCancellationHandler` + `Task.isCancelled`，不需要手动处理信号

### 现有代码状态（直接复用）

**已完成的依赖（可直接使用）：**
- `RunState`（AxionCore/Models/） — 9 个状态枚举
- `RunContext`（AxionCore/Models/） — planId, currentState, currentStepIndex, executedSteps, replanCount, config
- `AxionConfig`（AxionCore/Models/） — 所有配置参数含默认值
- `Plan` / `Step`（AxionCore/Models/） — Plan 结构和步骤模型
- `ExecutedStep`（AxionCore/Models/） — 步骤执行结果
- `StopCondition`（AxionCore/Models/） — 停止条件
- `VerificationResult`（AxionCore/Models/） — 验证结果
- `AxionError`（AxionCore/Errors/） — 统一错误类型
- `ToolNames`（AxionCore/Constants/） — MCP 工具名常量
- `PlannerProtocol`（AxionCore/Protocols/） — createPlan + replan
- `ExecutorProtocol`（AxionCore/Protocols/） — executeStep + executePlan（StepExecutor 已实现）
- `VerifierProtocol`（AxionCore/Protocols/） — verify
- `MCPClientProtocol`（AxionCore/Protocols/） — callTool + listTools
- `OutputProtocol`（AxionCore/Protocols/） — 8 个方法（5 原始 + 3 新增）
- `LLMPlanner`（AxionCLI/Planner/） — 完整实现，含 onPlanCreated 回调
- `StepExecutor`（AxionCLI/Executor/） — 完整实现，含 executePlan + onStepStart/onStepDone 回调
- `TaskVerifier`（AxionCLI/Verifier/） — 完整实现，含 onVerificationResult 回调
- `TerminalOutput`（AxionCLI/Output/） — 完整实现
- `JSONOutput`（AxionCLI/Output/） — 完整实现
- `TraceRecorder`（AxionCLI/Trace/） — Actor，完整实现
- `HelperProcessManager`（AxionCLI/Helper/） — Helper 进程管理
- `RunCommand`（AxionCLI/Commands/） — 已有 CLI 参数解析和 Helper 启动

**需要新建的文件：**
- `Sources/AxionCLI/Engine/RunEngine.swift` — 状态机核心
- `Tests/AxionCLITests/Engine/RunEngineTests.swift` — 单元测试

**需要修改的文件：**
- `Sources/AxionCLI/Commands/RunCommand.swift` — 替换占位代码，调用 RunEngine

**可能需要创建的文件：**
- `Sources/AxionCLI/Planner/AnthropicClient.swift` — Anthropic API 调用实现（如果 LLMClientProtocol 还没有真实实现）
- `Sources/AxionCLI/Config/ConfigManager.swift` — 可能已存在，需要确认 load() 方法是否可用

### LLMClient 实现注意事项

当前 `LLMClientProtocol` 定义在 `LLMPlanner.swift` 中：
```swift
protocol LLMClientProtocol {
    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String
}
```

需要创建 `AnthropicClient` 实现这个 Protocol。使用 URLSession 调用 Anthropic Messages API：

```swift
struct AnthropicClient: LLMClientProtocol {
    let apiKey: String
    let model: String
    let baseURL: String?

    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String] = []) async throws -> String {
        // POST https://api.anthropic.com/v1/messages
        // Headers: x-api-key, anthropic-version, content-type
        // Body: { model, max_tokens, system, messages: [{role: "user", content}] }
    }
}
```

**API Key 获取：** 从 ConfigManager 加载（优先环境变量 AXION_API_KEY，然后 config.json）。

**重要：** 这是临时实现。Story 3-7 将通过 SDK Agent Loop 替代直接的 API 调用。

### 模块依赖规则

```
RunEngine.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — 所有 Protocol, Model, Error)

禁止 import:
  - AxionHelper (进程隔离)
  - OpenAgentSDK (本 Story 不使用 SDK Agent Loop，那是 Story 3-7 的职责)
  - MCP (不直接使用 MCP 底层 API)
  - ArgumentParser (RunCommand 负责参数解析，不传给 RunEngine)
```

### import 顺序

```swift
// RunEngine.swift
import Foundation

import AxionCore
```

### 目录结构

```
Sources/AxionCLI/Engine/
  RunEngine.swift                    # 新建：状态机核心

Sources/AxionCLI/Planner/
  AnthropicClient.swift              # 新建（如需要）：Anthropic API 调用

Sources/AxionCLI/Commands/
  RunCommand.swift                   # 修改：替换占位代码

Tests/AxionCLITests/Engine/
  RunEngineTests.swift               # 新建：状态机测试
```

### 测试策略

**RunEngine 测试的关键：Mock 所有依赖**

通过 Protocol 注入，RunEngine 的所有外部交互都可以 Mock：

```swift
struct MockPlanner: PlannerProtocol {
    var plansToReturn: [Plan]  // 预设的 Plan 序列
    var callCount = 0

    func createPlan(for task: String, context: RunContext) async throws -> Plan {
        defer { callCount++ }
        return plansToReturn[callCount]
    }

    func replan(...) async throws -> Plan {
        defer { callCount++ }
        return plansToReturn[min(callCount, plansToReturn.count - 1)]
    }
}
```

类似地为 ExecutorProtocol, VerifierProtocol, OutputProtocol 创建 Mock。

**关键测试场景：**

| 测试名 | 场景 | Mock 设置 | 预期结果 |
|--------|------|-----------|----------|
| test_happyPath_planExecuteVerifyDone | 正常完成 | Planner 返回 1 个 Plan, Executor 全成功, Verifier 返回 .done | .done |
| test_replanAfterBlocked_verifyBlockedThenReplan | 验证失败重规划 | Planner 返回 2 个 Plan, 第一次 Verifier 返回 .blocked, 第二次 .done | .done, replanCount=1 |
| test_replanAfterStepFailure | 步骤失败重规划 | Executor 返回失败步骤, Planner 第二个 Plan 成功 | .done |
| test_maxReplanRetriesExceeded | 重规划耗尽 | Verifier 连续返回 .blocked, 超过 maxReplanRetries | .failed |
| test_maxBatchesExceeded | 批次耗尽 | Verifier 连续返回 .blocked, 超过 maxBatches | .failed |
| test_maxStepsExceeded | 步数耗尽 | Executor 执行步数超过 maxSteps | .failed |
| test_needsClarification | 需要澄清 | Verifier 返回 .needsClarification | .needsClarification |
| test_dryrunMode | 干跑 | dryrun=true | .done, 无 execute/verify 调用 |
| test_irrecoverableError_planning | 规划失败 | Planner 抛出 AxionError.planningFailed | .failed |
| test_cancelPropagation | 取消传播 | Task cancellation | .cancelled |

**测试注意事项：**
- RunEngine 是 struct，不需要 `await` 创建实例
- Mock 中可以用闭包灵活控制返回值序列
- 测试 TraceRecorder 时可以使用内存 Mock（不写文件）
- OutputProtocol 的 Mock 只需记录调用，不验证输出格式（输出格式由 TerminalOutputTests 覆盖）

### 禁止事项（反模式）

- **不得创建新的错误类型** — 使用 `AxionError` 枚举
- **RunEngine 不得直接调用 MCP 工具** — 通过 StepExecutor 间接调用
- **RunEngine 不得 import OpenAgentSDK** — SDK 集成是 Story 3-7 的职责
- **RunEngine 不得使用 print() 输出** — 通过 OutputProtocol 输出
- **RunEngine 不得硬编码 prompt 文本** — prompt 由 PromptBuilder 加载
- **不得修改 RunState/RunContext 的现有定义** — 如需扩展，用 extension
- **不得修改 PlannerProtocol/ExecutorProtocol/VerifierProtocol 的现有签名** — 已有实现依赖这些签名
- **RunEngine 测试不得依赖真实 LLM/Helper** — 必须通过 Mock 隔离

### 检查清单合规

- [x] 故事声明：As a / I want / so that 格式
- [x] 验收标准：Given/When/Then BDD 格式
- [x] 任务分解：可执行的子任务，关联 AC
- [x] 开发者注记：架构决策、模式约束、反模式
- [x] 项目结构注记：文件位置、依赖规则、import 顺序
- [x] 参考：所有源文档引用
- [x] 测试策略：Mock 方式、关键测试用例

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.6] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D3] 执行循环状态机设计（RunState + RunContext + 状态转换图）
- [Source: _bmad-output/planning-artifacts/architecture.md#D5] 并发模型（async/await + Actor）
- [Source: _bmad-output/planning-artifacts/architecture.md#D8] Helper 进程生命周期
- [Source: _bmad-output/planning-artifacts/architecture.md#数据流] 完整数据流链路（RunEngine.run() 是核心编排）
- [Source: _bmad-output/planning-artifacts/architecture.md#FR6-FR10] 任务执行功能需求
- [Source: _bmad-output/planning-artifacts/architecture.md#FR13] 失败重规划
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR6] LLM API 调用重试
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR8] Ctrl-C 正确清理
- [Source: _bmad-output/project-context.md#执行循环状态机] 状态机图和 RunContext 说明
- [Source: _bmad-output/project-context.md#数据流] 完整链路图（RunEngine 编排）
- [Source: _bmad-output/project-context.md#配置系统] AxionConfig 默认值（maxSteps=20, maxBatches=6, maxReplanRetries=3）
- [Source: _bmad-output/project-context.md#Trace记录] JSONL trace 格式、Run ID 格式
- [Source: _bmad-output/implementation-artifacts/stories/3-5-output-trace-progress-display.md] 前序 Story — OutputProtocol、TraceRecorder、TerminalOutput、JSONOutput 的完整实现细节
- [Source: Sources/AxionCore/Models/RunState.swift] RunState 枚举（9 个状态）
- [Source: Sources/AxionCore/Models/RunContext.swift] RunContext 结构体
- [Source: Sources/AxionCore/Models/AxionConfig.swift] AxionConfig 配置模型（含默认值）
- [Source: Sources/AxionCore/Models/Plan.swift] Plan 结构体
- [Source: Sources/AxionCore/Models/VerificationResult.swift] VerificationResult（.done/.blocked/.needsClarification 工厂方法）
- [Source: Sources/AxionCore/Models/ExecutedStep.swift] ExecutedStep 结构体
- [Source: Sources/AxionCore/Protocols/PlannerProtocol.swift] createPlan + replan 接口
- [Source: Sources/AxionCore/Protocols/ExecutorProtocol.swift] executeStep 接口
- [Source: Sources/AxionCore/Protocols/VerifierProtocol.swift] verify 接口
- [Source: Sources/AxionCore/Protocols/OutputProtocol.swift] 8 个输出方法
- [Source: Sources/AxionCore/Protocols/MCPClientProtocol.swift] callTool + listTools
- [Source: Sources/AxionCore/Errors/AxionError.swift] 统一错误类型
- [Source: Sources/AxionCLI/Commands/RunCommand.swift] 当前 RunCommand 实现（需替换占位代码）
- [Source: Sources/AxionCLI/Planner/LLMPlanner.swift] LLMPlanner 完整实现（含 LLMClientProtocol 定义）
- [Source: Sources/AxionCLI/Executor/StepExecutor.swift] StepExecutor 完整实现（含 executePlan + 回调）
- [Source: Sources/AxionCLI/Verifier/TaskVerifier.swift] TaskVerifier 完整实现（含回调）
- [Source: Sources/AxionCLI/Output/TerminalOutput.swift] TerminalOutput 实现
- [Source: Sources/AxionCLI/Output/JSONOutput.swift] JSONOutput 实现
- [Source: Sources/AxionCLI/Trace/TraceRecorder.swift] TraceRecorder Actor 实现
- [Source: Sources/AxionCLI/Helper/HelperProcessManager.swift] Helper 进程管理
- [Source: /Users/nick/CascadeProjects/openclick/src/run.ts:257-500] OpenClick runTaskFast — 批次循环参考
- [Source: /Users/nick/CascadeProjects/openclick/src/run.ts:644-830] OpenClick 主 while 循环 — 编排逻辑参考
- [Source: /Users/nick/CascadeProjects/openclick/src/run.ts:1196-1260] OpenClick action retry — 重规划逻辑参考

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
