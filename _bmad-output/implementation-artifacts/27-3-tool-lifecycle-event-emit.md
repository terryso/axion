# Story 27.3: Tool Lifecycle Event Emit

Status: done

## Story

As a SDK 开发者,
I want agent 在 tool 执行前后 emit 事件,
So that 上层可以追踪每个 tool 的执行时间和结果.

## Acceptance Criteria

1. **AC1: ToolStartedEvent 在 tool 执行前 emit**
   - Given Agent 配置了 EventBus
   - When agent 调用 BashTool
   - Then EventBus 收到 `ToolStartedEvent`（toolName="bash", toolUseId, input）

2. **AC2: ToolCompletedEvent 在 tool 成功执行后 emit**
   - Given Agent 配置了 EventBus
   - When tool 执行成功完成
   - Then EventBus 收到 `ToolCompletedEvent`（toolName, toolUseId, durationMs, isError=false）

3. **AC3: ToolFailedEvent 在 tool 失败时 emit**
   - Given Agent 配置了 EventBus
   - When tool 执行失败（返回 isError=true 的 ToolResult）
   - Then EventBus 收到 `ToolFailedEvent`（toolName, toolUseId, error）

4. **AC4: 每个 tool 都有独立的 Started/Completed 事件**
   - Given Agent 配置了 EventBus 且 LLM 返回 2 个 tool_use blocks
   - When tools 执行（可能并发或串行）
   - Then EventBus 收到 2 个 ToolStartedEvent 和 2 个 ToolCompletedEvent（或 ToolFailedEvent）

5. **AC5: durationMs 反映每个 tool 的实际执行时间**
   - Given Agent 配置了 EventBus
   - When tool 执行完成
   - Then ToolCompletedEvent 的 durationMs 是该 tool 的实际执行耗时（非整批时间）

6. **AC6: 无 EventBus 时零开销**
   - Given Agent 未配置 EventBus（eventBus == nil）
   - When tool 执行
   - Then 行为与当前完全一致，不创建 event struct，不发 publish

7. **AC7: promptImpl 和 stream 两个路径都 emit tool 事件**
   - Given Agent 配置了 EventBus
   - When 通过 prompt("task") 或 stream("task") 触发 tool 执行
   - Then 两个路径都 emit ToolStartedEvent + ToolCompletedEvent/ToolFailedEvent

8. **AC8: 现有测试全部通过**
   - Given 不注入 EventBus
   - When 运行全部现有测试
   - Then 全部通过，无回归

## Tasks / Subtasks

- [x] Task 1: 在 ToolContext 中添加 eventBus 和 sessionId 字段 (AC: #6)
  - [x] 1.1 在 `ToolTypes.swift` 的 `ToolContext` 中添加 `public let eventBus: EventBus?` 字段
  - [x] 1.2 在 `ToolContext` 中添加 `public let sessionId: String?` 字段
  - [x] 1.3 更新 `ToolContext.init()` 的所有参数列表（含默认值 `eventBus: EventBus? = nil, sessionId: String? = nil`）
  - [x] 1.4 更新 `withToolUseId()` 工厂方法，保留 eventBus 和 sessionId

- [x] Task 2: 在 ToolExecutor.executeSingleTool() 中 emit tool lifecycle events (AC: #1-#6)
  - [x] 2.1 在 `executeSingleTool()` 的 "Execute tool" 区块（行 ~410）之前，emit `ToolStartedEvent`
  - [x] 2.2 在 tool 执行成功（`result.isError == false`）后，emit `ToolCompletedEvent`（含 durationMs）
  - [x] 2.3 在 tool 执行失败（`result.isError == true`）后，emit `ToolFailedEvent`（含 error message）
  - [x] 2.4 确保 eventBus == nil 时全部走 guard early return，零开销
  - [x] 2.5 注意：`executeSingleTool()` 有两个执行路径（canUseTool allow path ~行 358 和 normal path ~行 410），两个路径都需要 emit
  - [x] 2.6 canUseTool block/deny 路径也视为 tool failed — emit ToolFailedEvent

- [x] Task 3: 在 Agent.swift 的 ToolContext 构建处传入 eventBus 和 sessionId (AC: #7)
  - [x] 3.1 在 promptImpl 的 `ToolContext(...)` 构建（行 ~1725-1748）中添加 `eventBus: options.eventBus, sessionId: resolvedSessionId`
  - [x] 3.2 在 stream 的 `ToolContext(...)` 构建（行 ~2707-2730）中添加 `eventBus: capturedEventBus, sessionId: resolvedSessionId`

- [x] Task 4: 编写单元测试 (AC: #1-#8)
  - [x] 4.1 在 `Tests/OpenAgentSDKTests/Core/EventBusTests.swift` 追加 tool lifecycle emit 测试
  - [x] 4.2 测试 AC1: 注入 EventBus → tool 执行 → 收到 ToolStartedEvent
  - [x] 4.3 测试 AC2: tool 成功完成 → ToolCompletedEvent 含 toolName、durationMs、isError=false
  - [x] 4.4 测试 AC3: tool 失败 → ToolFailedEvent 含 error
  - [x] 4.5 测试 AC4: 多 tool 执行 → 每个 tool 都有独立的 Started/Completed 事件
  - [x] 4.6 测试 AC6: eventBus == nil → 行为一致（现有测试覆盖）

- [x] Task 5: 编写 E2E 测试 (AC: #1, #2, #8)
  - [x] 5.1 在 `Sources/E2ETest/ToolLifecycleEmitE2ETests.swift` 创建 tool lifecycle emit E2E 测试
  - [x] 5.2 E2E 测试：创建 Agent + EventBus → stream("use a tool") → 验证收到 ToolStartedEvent + ToolCompletedEvent
  - [x] 5.3 注册到 `Sources/E2ETest/main.swift`

- [x] Task 6: 验证构建与回归测试 (AC: #8)
  - [x] 6.1 `swift build` 确认编译通过
  - [x] 6.2 `swift test` 确认所有现有测试通过

## Dev Notes

### Architecture Context

本 Story 是 Epic 27 的 Tool 层事件 emit——在 `ToolExecutor.executeSingleTool()` 中注入 EventBus emit 调用。

**关键设计决策：通过 ToolContext 注入 EventBus**

Epic 文档建议"在 Agent.swift 中调用 `ToolExecutor.executeTools()` 的前后 emit"。但这个方案有缺陷：
- `executeTools()` 处理一批 tools（可能并发），无法获取单个 tool 的精确 durationMs
- 丢失了 per-tool 的 started/completed 时序

**推荐方案**：将 `EventBus?` 和 `sessionId: String?` 通过 `ToolContext` 注入到 `executeSingleTool()` 内部。理由：
1. `ToolContext` 已有 17 个可选注入字段（hookRegistry、permissionMode、canUseTool 等），这是既有模式
2. `executeSingleTool()` 已有 `Date()` 计时的 toolDurationMs（行 ~358、~410），可复用
3. 每个 tool 获得精确的 started/completed 事件和 timing
4. 并发执行的 read-only tools 各自有独立的事件序列

### Event Types to Emit (已定义在 AgentEventTypes.swift)

| Event | Fields | Emit 时机 |
|-------|--------|-----------|
| `ToolStartedEvent` | sessionId?, toolName, toolUseId, input? | tool 执行前 |
| `ToolCompletedEvent` | sessionId?, toolUseId, toolName, durationMs, isError | tool 执行成功后 |
| `ToolFailedEvent` | sessionId?, toolUseId, toolName, error | tool 执行失败后 |

**注意**：不 emit `ToolStreamingEvent`（本 Story 不涉及 streaming tool output）。

### Files to Modify

- **UPDATE**: `Sources/OpenAgentSDK/Types/ToolTypes.swift` — 在 ToolContext 中添加 `eventBus: EventBus?` 和 `sessionId: String?` 字段
- **UPDATE**: `Sources/OpenAgentSDK/Core/ToolExecutor.swift` — 在 `executeSingleTool()` 中 emit ToolStartedEvent/ToolCompletedEvent/ToolFailedEvent
- **UPDATE**: `Sources/OpenAgentSDK/Core/Agent.swift` — 在两个 ToolContext 构建处传入 eventBus 和 sessionId
- **UPDATE**: `Tests/OpenAgentSDKTests/Core/EventBusTests.swift` — 追加 tool lifecycle emit 单元测试
- **CREATE**: `Sources/E2ETest/ToolLifecycleEmitE2ETests.swift` — tool lifecycle E2E 测试
- **UPDATE**: `Sources/E2ETest/main.swift` — 注册 E2E 测试

### ToolExecutor.executeSingleTool() 关键位置与 Emit 注入点

```
executeSingleTool(block: ToolUseBlock, tool: ToolProtocol?, context: ToolContext)  [line 301]
  ├─ Unknown tool handling → return error result  [line 307-313]
  │   >>> EMIT: ToolFailedEvent(sessionId, toolUseId, toolName, error) if eventBus
  ├─ PreToolUse hook check → blocked/denied → return error result  [line 317-334]
  │   >>> EMIT: ToolFailedEvent(sessionId, toolUseId, toolName, blockMessage) if eventBus
  ├─ canUseTool callback path:  [line 347]
  │   ├─ deny → return error result  [line 349-355]
  │   │   >>> EMIT: ToolFailedEvent(sessionId, toolUseId, toolName, denyMessage) if eventBus
  │   ├─ allow path:  [line 357]
  │   │   >>> EMIT: ToolStartedEvent(sessionId, toolName, toolUseId, input) if eventBus
  │   │   ├─ let toolStart = Date()  [line 358]
  │   │   ├─ tool.call()  [line 359]
  │   │   ├─ let toolDurationMs = ...  [line 360]
  │   │   ├─ if result.isError:
  │   │   │   >>> EMIT: ToolFailedEvent(sessionId, toolUseId, toolName, content) if eventBus
  │   │   └─ if !result.isError:
  │   │       >>> EMIT: ToolCompletedEvent(sessionId, toolUseId, toolName, durationMs, isError: false) if eventBus
  │   └─ nil (fall through to permissionMode check)
  ├─ Permission mode check: block/deny → return error result  [line 389-407]
  │   >>> EMIT: ToolFailedEvent for block/deny cases if eventBus
  ├─ Normal execution path:  [line 410]
  │   >>> EMIT: ToolStartedEvent(sessionId, toolName, toolUseId, input) if eventBus
  │   ├─ let toolStart = Date()  [line 410]
  │   ├─ tool.call()  [line 411]
  │   ├─ let toolDurationMs = ...  [line 412]
  │   ├─ if result.isError:
  │   │   >>> EMIT: ToolFailedEvent(sessionId, toolUseId, toolName, content) if eventBus
  │   └─ if !result.isError:
  │       >>> EMIT: ToolCompletedEvent(sessionId, toolUseId, toolName, durationMs, isError: false) if eventBus
  └─ return ToolResult  [line 430]
```

### Implementation Details

#### emitEvent in executeSingleTool()

`executeSingleTool()` 是 `static func`，不能访问 `self`。通过 `context.eventBus` 和 `context.sessionId` 获取 EventBus 和 sessionId。

```swift
// 在 executeSingleTool() 中的 emit 模式
guard let eventBus = context.eventBus else { /* proceed without emit */ }

// Before tool execution
let inputStr: String? = ...
await eventBus.publish(ToolStartedEvent(
    sessionId: context.sessionId,
    toolName: block.name,
    toolUseId: block.id,
    input: inputStr
))

// After tool execution (success)
await eventBus.publish(ToolCompletedEvent(
    sessionId: context.sessionId,
    toolUseId: block.id,
    toolName: block.name,
    durationMs: Int(toolDurationMs),
    isError: false
))

// After tool execution (failure)
await eventBus.publish(ToolFailedEvent(
    sessionId: context.sessionId,
    toolUseId: block.id,
    toolName: block.name,
    error: result.content
))
```

**注意**：使用 inline guard 而非 helper method，保证 eventBus == nil 时零开销（不构造 event struct）。

#### 零开销关键

在 `executeSingleTool()` 中，每个 emit 点使用：
```swift
if let eventBus = context.eventBus {
    await eventBus.publish(...)
}
```
当 `context.eventBus == nil` 时，不执行任何 publish 也不构造 event struct。

#### input 字段序列化

`ToolStartedEvent.input` 是 `String?`。`block.input` 是 `Any`（raw JSON dict）。需要序列化：
```swift
let inputStr: String?
if let dict = block.input as? [String: Any],
   let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
   let str = String(data: data, encoding: .utf8) {
    inputStr = str
} else {
    inputStr = nil
}
```

**注意**：仅在 eventBus != nil 时才做序列化，避免 nil 时的序列化开销。

#### Failed 路径的 error message 提取

各个 failed 路径的 error message 来源：
- Unknown tool: `"Error: Unknown tool \"\(block.name)\""`
- Hook blocked: `blockMessage`（from hookResults）
- Permission denied: `result.message ?? "Permission denied for tool \"\(block.name)\""`
- Permission blocked: `message`（from shouldBlockTool）
- Tool execution error: `result.content`（when isError=true）

#### ToolContext.withToolUseId() 更新

现有的 `withToolUseId()` 方法（用于设置 context.toolUseId）需要保留 eventBus 和 sessionId：
```swift
func withToolUseId(_ id: String) -> ToolContext {
    ToolContext(
        // ... all existing fields ...
        eventBus: eventBus,
        sessionId: sessionId
    )
}
```

### SessionId 来源

| 执行路径 | sessionId 传入 ToolContext 的方式 |
|---------|-------------------------------|
| promptImpl | `resolvedSessionId` 局部变量（行 ~1321） |
| stream | `resolvedSessionId` 局部变量（行 ~2020） |

### Testing Strategy

**单元测试**（`Tests/OpenAgentSDKTests/Core/EventBusTests.swift`）:
- 直接测试 `ToolExecutor.executeSingleTool()`，传入带 EventBus 的 ToolContext
- 验证 ToolStartedEvent 在执行前 emit
- 验证 ToolCompletedEvent 在成功后 emit（含 durationMs）
- 验证 ToolFailedEvent 在失败后 emit（含 error）
- 验证 eventBus == nil 时无事件 emit

**E2E 测试**（`Sources/E2ETest/ToolLifecycleEmitE2ETests.swift`）:
- 真实 LLM 调用 + EventBus → 验证 ToolStartedEvent + ToolCompletedEvent
- 遵循 project convention：不使用 mock

### Scope Boundaries

**本 Story 只做：**
- 在 ToolContext 中添加 eventBus 和 sessionId
- 在 ToolExecutor.executeSingleTool() 中 emit tool lifecycle events
- 在 Agent.swift 的两个 ToolContext 构建处传入 eventBus 和 sessionId
- 单元测试 + E2E 测试

**不做（后续 Story）：**
- LLM cost event emit（→ 27.4）
- Session lifecycle event emit（→ 27.5）
- ToolStreamingEvent emit（未来，需要 streaming tool output 支持）
- Sub-agent event 继承（sub-agent 默认 eventBus: nil，不继承 parent 的 EventBus）

### Previous Story Intelligence (27.2)

Story 27.2 在 Agent.swift 中实现了 agent lifecycle event emit：
- 使用 inline `if let eventBus = options.eventBus` / `capturedEventBus` guard+publish 模式
- 不使用 helper method，保证零开销
- promptImpl 中 `resolvedSessionId` 在行 ~1321 确定
- stream 中通过 `capturedEventBus = options.eventBus` 捕获
- resume 使用 fire-and-forget Task 模式（不改同步签名）
- 10 个单元测试 + 2 个 E2E 测试，全部通过
- emit 位置在 session 解析之后、while loop 之前

### Project Structure Notes

- `ToolTypes.swift` 位于 `Sources/OpenAgentSDK/Types/`，ToolContext 是 `public struct: Sendable`
- `ToolExecutor.swift` 位于 `Sources/OpenAgentSDK/Core/`，ToolExecutor 是 `enum`（static namespace）
- `AgentEventTypes.swift` 位于 `Sources/OpenAgentSDK/Types/`，包含 ToolStartedEvent/ToolCompletedEvent/ToolFailedEvent
- `EventBus` 是 `public actor`（隐式 Sendable），可以作为 ToolContext 的可选字段
- 模块边界：Types/ 无出站依赖，Core/ 依赖 Types/ + API/ + Utils/
- ToolContext 已有 17 个可选注入字段，添加 eventBus + sessionId 符合既有模式

### References

- [Source: docs/epics/epic-27-agent-event-emitter.md#Story 27.3]
- [Source: docs/runtime-event-layer-roadmap.md#S3 — Agent Event Emitter]
- [Source: Sources/OpenAgentSDK/Core/ToolExecutor.swift — executeSingleTool() line 301]
- [Source: Sources/OpenAgentSDK/Types/ToolTypes.swift — ToolContext line 269]
- [Source: Sources/OpenAgentSDK/Types/AgentEventTypes.swift — ToolStartedEvent line 451, ToolCompletedEvent line 546, ToolFailedEvent line 601]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift — promptImpl ToolContext line 1725, stream ToolContext line 2707]
- [Source: _bmad-output/implementation-artifacts/27-2-agent-startup-completion-event-emit.md — previous story]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7

### Debug Log References

### Completion Notes List

- Added `eventBus: EventBus?` and `sessionId: String?` fields to ToolContext (following existing 17-field optional injection pattern)
- Updated `ToolContext.init()`, `withToolUseId()`, and `withSkillContext()` to carry the new fields
- Emit ToolStartedEvent before tool execution and ToolCompletedEvent/ToolFailedEvent after in both canUseTool allow path and normal execution path
- All error/permission deny paths emit ToolFailedEvent: unknown tool, hook blocked, canUseTool deny, permission block/deny, tool execution error
- Event bus nil check uses inline `if let eventBus = context.eventBus` — zero overhead when nil
- Input serialization uses `JSONSerialization.data(withJSONObject:options:[.sortedKeys])` only when eventBus != nil
- Passed eventBus and sessionId through both promptImpl and stream ToolContext construction points
- 10 new unit tests: ToolStartedEvent, ToolCompletedEvent, ToolFailedEvent, multi-tool independent events, nil EventBus, unknown tool, permission denied, hook blocked, canUseTool deny, canUseTool allow
- 4 new E2E tests: stream + prompt tool execution with real LLM, failing tool, sessionId verification
- All 5943 tests pass, 0 failures, 0 regressions

### File List

- **UPDATE**: `Sources/OpenAgentSDK/Types/ToolTypes.swift` — Added eventBus + sessionId fields to ToolContext
- **UPDATE**: `Sources/OpenAgentSDK/Core/ToolExecutor.swift` — Emit tool lifecycle events in executeSingleTool()
- **UPDATE**: `Sources/OpenAgentSDK/Core/Agent.swift` — Pass eventBus + sessionId to ToolContext in promptImpl and stream paths
- **UPDATE**: `Tests/OpenAgentSDKTests/Core/EventBusTests.swift` — Added 10 tool lifecycle emit unit tests
- **CREATE**: `Sources/E2ETest/ToolLifecycleEmitE2ETests.swift` — E2E tests for tool lifecycle event emit
- **UPDATE**: `Sources/E2ETest/main.swift` — Registered ToolLifecycleEmitE2ETests

## Senior Developer Review (AI)

**Reviewer:** Nick (via AI Review) on 2026-05-26
**Model:** Claude Opus 4.7

### Findings

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| 1 | HIGH | durationMs computed after firePostToolHook(), inflating reported tool duration with hook execution time (AC5 violation) | **Fixed** |
| 2 | MEDIUM | Completion Notes claimed "7 unit tests" but implementation has 10 | **Fixed** (doc updated) |
| 3 | MEDIUM | Completion Notes claimed "2 E2E tests" but implementation has 4 | **Fixed** (doc updated) |

### Fix Applied

- **Finding 1**: Moved `durationMs` computation to immediately after `tool.call()` in both `canUseTool` allow path and normal execution path, before `firePostToolHook()`. This ensures `durationMs` reflects pure tool execution time per AC5.

### Change Log

- 2026-05-26: Review completed. 1 HIGH fix applied (durationMs timing). Story status → done.
