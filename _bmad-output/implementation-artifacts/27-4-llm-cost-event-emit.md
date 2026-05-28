# Story 27.4: LLM Cost Event Emit

Status: review

## Story

As a SDK 开发者,
I want agent 在每次 LLM API 调用后 emit 成本事件,
So that 上层可以实时追踪 token 消耗和成本，无需等 agent 执行完成.

## Acceptance Criteria

1. **AC1: LLMCostEvent 在 promptImpl 每次 LLM 响应后 emit**
   - Given Agent 配置了 EventBus
   - When promptImpl 收到 LLM response（含 usage 数据）
   - Then EventBus 收到 `LLMCostEvent`（含 model, inputTokens, outputTokens, estimatedCostUsd）

2. **AC2: LLMCostEvent 在 stream() 每次 LLM 响应后 emit**
   - Given Agent 配置了 EventBus
   - When stream() 收到 messageDelta（含 usage 数据）
   - Then EventBus 收到 `LLMCostEvent`（含 model, inputTokens, outputTokens, estimatedCostUsd）

3. **AC3: 每次 LLM 调用产生独立的 LLMCostEvent**
   - Given Agent 配置了 EventBus 且执行了 3 次 LLM 调用
   - When 检查 EventBus 收到的事件
   - Then 有 3 个 `LLMCostEvent`，每个反映该次调用的 token 数据

4. **AC4: LLMCostEvent 包含 cacheCreationInputTokens 和 cacheReadInputTokens（如果 API 返回）**
   - Given Agent 配置了 EventBus 且 LLM response 包含 cache token 数据
   - When emit LLMCostEvent
   - Then cacheCreationInputTokens 和 cacheReadInputTokens 非 nil 且值正确

5. **AC5: estimatedCostUsd 使用现有 estimateCost() 函数计算**
   - Given Agent 配置了 EventBus
   - When LLMCostEvent 被 emit
   - Then estimatedCostUsd 值与 `estimateCost(model:usage:)` 的计算结果一致

6. **AC6: promptImpl 的 fallback 路径也 emit LLMCostEvent**
   - Given Agent 配置了 EventBus 且主 LLM 调用失败触发 fallback
   - When fallback LLM 调用成功返回
   - Then EventBus 收到 LLMCostEvent（model 为 fallback model）

7. **AC7: 无 EventBus 时零开销**
   - Given Agent 未配置 EventBus（eventBus == nil）
   - When LLM 调用
   - Then 行为与当前完全一致，不创建 event struct，不发 publish

8. **AC8: promptImpl 和 stream 两个路径都 emit LLM cost 事件**
   - Given Agent 配置了 EventBus
   - When 通过 prompt("task") 或 stream("task") 触发 LLM 调用
   - Then 两个路径都 emit LLMCostEvent

9. **AC9: 现有测试全部通过**
   - Given 不注入 EventBus
   - When 运行全部现有测试
   - Then 全部通过，无回归

## Tasks / Subtasks

- [x] Task 1: 在 promptImpl 的 LLM response usage 解析处 emit LLMCostEvent (AC: #1, #5, #7)
  - [x] 1.1 在 promptImpl 主循环的 `// Parse usage from response` 区块（~行 1616-1647）中，在 `costTracker.recordUsage()` 之后添加 EventBus emit
  - [x] 1.2 提取 cache token 数据：`usage["cache_creation_input_tokens"] as? Int` 和 `usage["cache_read_input_tokens"] as? Int`
  - [x] 1.3 构建 TokenUsage（含 cache tokens）并用 `estimateCost()` 计算 cost
  - [x] 1.4 emit `LLMCostEvent`（含 model, inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens, estimatedCostUsd）
  - [x] 1.5 使用 inline `if let eventBus = options.eventBus` guard，nil 时零开销

- [x] Task 2: 在 promptImpl 的 fallback response 路径 emit LLMCostEvent (AC: #6, #7)
  - [x] 2.1 在 fallback response usage 解析区块（~行 1488-1504）中，在 `costTracker.recordUsage()` 之后添加 EventBus emit
  - [x] 2.2 emit `LLMCostEvent`（model 为 fallbackModel，含 token 数据和 cost）

- [x] Task 3: 在 stream() 的 messageDelta 处理处 emit LLMCostEvent (AC: #2, #5, #7)
  - [x] 3.1 在 stream() 的 `.messageDelta(let delta, let usage)` case（~行 2414-2442）中，在 `streamCostTracker.recordUsage()` 之后添加 EventBus emit
  - [x] 3.2 提取 cache token 数据
  - [x] 3.3 emit `LLMCostEvent`（含 currentModel, token 数据, estimatedCostUsd）
  - [x] 3.4 使用 inline `if let eventBus = capturedEventBus` guard，nil 时零开销

- [x] Task 4: 在 stream() 的 messageStart 处理处 emit LLMCostEvent（如包含 usage） (AC: #2, #7)
  - [x] 4.1 检查 stream() 的 `.messageStart` case（~行 2278-2310），该路径已有 usage 解析和 cost tracking
  - [x] 4.2 在 `streamCostTracker.recordUsage()` 之后添加 EventBus emit
  - [x] 4.3 emit `LLMCostEvent`（outputTokens=0，因为 messageStart 只有 input tokens）

- [x] Task 5: 编写单元测试 (AC: #1-#9)
  - [x] 5.1 在 `Tests/OpenAgentSDKTests/Core/EventBusTests.swift` 追加 LLM cost emit 测试
  - [x] 5.2 测试 AC1: promptImpl 路径 → LLM response 含 usage → 收到 LLMCostEvent
  - [x] 5.3 测试 AC3: 多次 LLM 调用 → 多个独立 LLMCostEvent
  - [x] 5.4 测试 AC5: estimatedCostUsd 与 estimateCost() 结果一致
  - [x] 5.5 测试 AC7: eventBus == nil → 无事件 emit（零开销）

- [x] Task 6: 编写 E2E 测试 (AC: #1, #2, #8, #9)
  - [x] 6.1 在 `Sources/E2ETest/LLMCostEmitE2ETests.swift` 创建 LLM cost emit E2E 测试
  - [x] 6.2 E2E 测试：创建 Agent + EventBus → prompt("task") → 验证收到 LLMCostEvent（含 inputTokens > 0, outputTokens > 0, estimatedCostUsd > 0）
  - [x] 6.3 E2E 测试：创建 Agent + EventBus → stream("task") → 验证收到 LLMCostEvent
  - [x] 6.4 注册到 `Sources/E2ETest/main.swift`

- [x] Task 7: 验证构建与回归测试 (AC: #9)
  - [x] 7.1 `swift build` 确认编译通过
  - [x] 7.2 `swift test` 确认所有现有测试通过

## Dev Notes

### Architecture Context

本 Story 是 Epic 27 的 LLM 成本事件 emit——在 Agent.swift 的 LLM response 处理中注入 EventBus publish 调用。与 Story 27.2/27.3 的模式完全一致。

**关键设计决策：直接在 usage 解析处 emit**

Agent.swift 已有 4 个位置解析 LLM response 的 usage 数据并计算 cost：
1. promptImpl 主循环（~行 1616-1624）
2. promptImpl fallback 路径（~行 1488-1496）
3. stream() messageStart（~行 2281-2290）
4. stream() messageDelta（~行 2414-2421）

这些位置已有 `turnUsage` 和 `turnCost` 变量，只需在 `costTracker.recordUsage()` 之后 emit LLMCostEvent。

### Event Type (已定义在 AgentEventTypes.swift:737-799)

```swift
public struct LLMCostEvent: AgentEvent, Equatable {
    public let base: BaseAgentEvent
    public let sessionId: String?
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationInputTokens: Int?
    public let cacheReadInputTokens: Int?
    public let estimatedCostUsd: Double
}
```

### Cost Calculation — 复用现有 `estimateCost()`

`estimateCost(model:usage:)` 定义在 `Sources/OpenAgentSDK/Utils/Tokens.swift:34`。
当前 Agent.swift 中的 4 个 usage 解析位置都已经在调用 `estimateCost()`，变量名是 `turnCost`。

**emit 时直接复用已有的 `turnCost` 值，不重复计算。**

### Cache Token 提取

当前代码只提取 `input_tokens` 和 `output_tokens`：
```swift
let turnUsage = TokenUsage(
    inputTokens: usage["input_tokens"] as? Int ?? 0,
    outputTokens: usage["output_tokens"] as? Int ?? 0
)
```

LLMCostEvent 需要 `cacheCreationInputTokens` 和 `cacheReadInputTokens`。这些字段在 API response 的 `usage` dict 中可能存在。需要在 emit 处提取：
```swift
let cacheCreation = usage["cache_creation_input_tokens"] as? Int
let cacheRead = usage["cache_read_input_tokens"] as? Int
```

### Files to Modify

- **UPDATE**: `Sources/OpenAgentSDK/Core/Agent.swift` — 在 4 个 usage 解析位置添加 LLMCostEvent emit
- **UPDATE**: `Tests/OpenAgentSDKTests/Core/EventBusTests.swift` — 追加 LLM cost emit 单元测试
- **CREATE**: `Sources/E2ETest/LLMCostEmitE2ETests.swift` — LLM cost E2E 测试
- **UPDATE**: `Sources/E2ETest/main.swift` — 注册 E2E 测试

### Emit 位置与代码模式

#### Emit Point 1: promptImpl 主循环（~行 1624 之后）

```swift
// 现有代码：
let turnCost = estimateCost(model: model, usage: turnUsage)
totalCostUsd += turnCost
costTracker.recordUsage(model: model, usage: turnUsage)

// 新增 emit（紧接在 costTracker.recordUsage 之后）：
if let eventBus = options.eventBus {
    let cacheCreation = usage["cache_creation_input_tokens"] as? Int
    let cacheRead = usage["cache_read_input_tokens"] as? Int
    await eventBus.publish(LLMCostEvent(
        sessionId: resolvedSessionId,
        model: model,
        inputTokens: turnUsage.inputTokens,
        outputTokens: turnUsage.outputTokens,
        cacheCreationInputTokens: cacheCreation,
        cacheReadInputTokens: cacheRead,
        estimatedCostUsd: turnCost
    ))
}
```

#### Emit Point 2: promptImpl fallback 路径（~行 1496 之后）

```swift
// 现有代码：
let turnCost = estimateCost(model: fallbackModel, usage: turnUsage)
totalCostUsd += turnCost
costTracker.recordUsage(model: fallbackModel, usage: turnUsage)

// 新增 emit：
if let eventBus = options.eventBus {
    let cacheCreation = usage["cache_creation_input_tokens"] as? Int
    let cacheRead = usage["cache_read_input_tokens"] as? Int
    await eventBus.publish(LLMCostEvent(
        sessionId: resolvedSessionId,
        model: fallbackModel,
        inputTokens: turnUsage.inputTokens,
        outputTokens: turnUsage.outputTokens,
        cacheCreationInputTokens: cacheCreation,
        cacheReadInputTokens: cacheRead,
        estimatedCostUsd: turnCost
    ))
}
```

#### Emit Point 3: stream() messageDelta（~行 2423 之后）

```swift
// 现有代码：
let turnCost = estimateCost(model: currentModel, usage: turnUsage)
totalCostUsd += turnCost
streamCostTracker.recordUsage(model: currentModel, usage: turnUsage)

// 新增 emit：
if let eventBus = capturedEventBus {
    let cacheCreation = usage["cache_creation_input_tokens"] as? Int
    let cacheRead = usage["cache_read_input_tokens"] as? Int
    await eventBus.publish(LLMCostEvent(
        sessionId: resolvedSessionId,
        model: currentModel,
        inputTokens: turnUsage.inputTokens,
        outputTokens: turnUsage.outputTokens,
        cacheCreationInputTokens: cacheCreation,
        cacheReadInputTokens: cacheRead,
        estimatedCostUsd: turnCost
    ))
}
```

#### Emit Point 4: stream() messageStart（~行 2290 之后）

```swift
// 现有代码（行 2288-2290）：
let turnCost = estimateCost(model: currentModel, usage: TokenUsage(inputTokens: inputTokens, outputTokens: 0))
totalCostUsd += turnCost
streamCostTracker.recordUsage(model: currentModel, usage: TokenUsage(inputTokens: inputTokens, outputTokens: 0))

// 新增 emit：
if let eventBus = capturedEventBus {
    await eventBus.publish(LLMCostEvent(
        sessionId: resolvedSessionId,
        model: currentModel,
        inputTokens: inputTokens,
        outputTokens: 0,
        cacheCreationInputTokens: nil,
        cacheReadInputTokens: nil,
        estimatedCostUsd: turnCost
    ))
}
```

**注意**：messageStart 的 `usage` 来自 `message["usage"]` 而非 `usage` 变量。可能也需要提取 cache tokens，但需要检查 API response 结构。messageStart 只有 input_tokens，无 output_tokens 和 cache tokens。

### 零开销保证

每个 emit 点使用 inline guard：
```swift
if let eventBus = options.eventBus { // 或 capturedEventBus
    await eventBus.publish(...)
}
```
当 `eventBus == nil` 时，不构造 event struct，不调用 publish。

### sessionId 来源

| 执行路径 | sessionId 变量 |
|---------|---------------|
| promptImpl | `resolvedSessionId`（~行 1321） |
| stream() | `resolvedSessionId`（在 Task 闭包内确定） |

### Testing Strategy

**单元测试**（`Tests/OpenAgentSDKTests/Core/EventBusTests.swift`）:
- 直接测试 Agent 的 promptImpl 路径，注入 EventBus，验证 LLMCostEvent emit
- 验证 inputTokens、outputTokens、estimatedCostUsd 值正确
- 验证 eventBus == nil 时无事件 emit

**E2E 测试**（`Sources/E2ETest/LLMCostEmitE2ETests.swift`）:
- 真实 LLM 调用 + EventBus → prompt → 验证 LLMCostEvent（inputTokens > 0, outputTokens > 0, cost > 0）
- 真实 LLM 调用 + EventBus → stream → 验证 LLMCostEvent
- 遵循 project convention：不使用 mock

### Scope Boundaries

**本 Story 只做：**
- 在 Agent.swift 的 4 个 usage 解析位置 emit LLMCostEvent
- 提取 cache token 数据（如果 API 返回）
- 单元测试 + E2E 测试

**不做（后续 Story）：**
- Session lifecycle event emit（→ 27.5）
- 修改 TokenUsage 类型（已有 cache token 字段，无需修改）
- 修改 estimateCost() 函数（直接复用）
- 改变现有 cost tracking 逻辑（LLMCostEvent 是额外输出通道，不替代 costTracker）

### Previous Story Intelligence (27.3)

Story 27.3 在 ToolExecutor.executeSingleTool() 中实现了 tool lifecycle event emit：
- 通过 ToolContext 注入 EventBus 和 sessionId
- 使用 inline `if let eventBus = context.eventBus` guard+publish 模式
- 零开销：eventBus == nil 时不构造 event struct
- 10 个单元测试 + 4 个 E2E 测试，全部通过
- 所有 5943 tests pass

**与 Story 27.3 的区别**：27.3 是在 ToolExecutor 中通过 ToolContext 注入 EventBus，而 27.4 直接在 Agent.swift 中使用 `options.eventBus` / `capturedEventBus`，与 27.2 的模式一致。

### Project Structure Notes

- `Agent.swift` 位于 `Sources/OpenAgentSDK/Core/`，是 Agent 的主实现文件
- `LLMCostEvent` 定义在 `Sources/OpenAgentSDK/Types/AgentEventTypes.swift:737-799`
- `estimateCost()` 定义在 `Sources/OpenAgentSDK/Utils/Tokens.swift:34`
- `TokenUsage` 定义在 `Sources/OpenAgentSDK/Types/TokenUsage.swift`
- `CostTracker` 定义在 `Sources/OpenAgentSDK/Utils/CostTracker.swift`
- EventBus 是 `public actor`，通过 `AgentOptions.eventBus` 注入
- E2E 测试文件放在 `Sources/E2ETest/`，在 `main.swift` 注册

### References

- [Source: docs/epics/epic-27-agent-event-emitter.md#Story 27.4]
- [Source: Sources/OpenAgentSDK/Types/AgentEventTypes.swift — LLMCostEvent line 737]
- [Source: Sources/OpenAgentSDK/Utils/Tokens.swift — estimateCost() line 34]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift — promptImpl usage parse line 1616, fallback line 1488]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift — stream messageDelta line 2414, messageStart line 2278]
- [Source: _bmad-output/implementation-artifacts/27-3-tool-lifecycle-event-emit.md — previous story]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- Implemented LLMCostEvent emit at 4 usage parsing locations in Agent.swift
- Emit Point 1: promptImpl main loop (after costTracker.recordUsage)
- Emit Point 2: promptImpl fallback path (after costTracker.recordUsage)
- Emit Point 3: stream() messageDelta (after streamCostTracker.recordUsage)
- Emit Point 4: stream() messageStart (after streamCostTracker.recordUsage)
- All emit points use inline `if let eventBus = ...` guard for zero-overhead when eventBus is nil
- Reuses existing `turnCost` from `estimateCost()` — no double calculation
- Extracts cache token data from usage dict when available
- Updated existing Story 27.2 lifecycle tests to account for LLMCostEvent between Started and Completed events
- Added 6 new unit tests + 3 E2E tests
- All 5949 tests pass with 0 failures

### File List

- **UPDATE**: `Sources/OpenAgentSDK/Core/Agent.swift` — Added LLMCostEvent emit at 4 usage parsing locations
- **UPDATE**: `Tests/OpenAgentSDKTests/Core/EventBusTests.swift` — Added 6 LLM cost unit tests, updated 4 existing lifecycle tests for new event ordering
- **CREATE**: `Sources/E2ETest/LLMCostEmitE2ETests.swift` — 3 E2E tests for LLM cost event emit
- **UPDATE**: `Sources/E2ETest/main.swift` — Registered LLMCostEmitE2ETests (SECTION 150-152)

## Change Log

- 2026-05-26: Story 27.4 implementation complete — LLMCostEvent emit at all 4 usage parsing locations, 6 unit tests + 3 E2E tests, all 5949 tests pass
