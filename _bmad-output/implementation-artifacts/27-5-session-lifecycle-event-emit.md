# Story 27.5: Session Lifecycle Event Emit

Status: done

## Story

As a SDK 开发者,
I want agent 在 session 关键节点 emit 事件,
So that 上层可以追踪 session 的创建、保存、关闭.

## Acceptance Criteria

1. **AC1: SessionCreatedEvent 在 stream() 开始时 emit（当 sessionStore 已配置）**
   - Given Agent 配置了 EventBus + SessionStore
   - When `agent.stream("task")` 被调用
   - Then EventBus 收到 `SessionCreatedEvent`（含 sessionId、task、model）

2. **AC2: SessionCreatedEvent 在 promptImpl 开始时 emit（当 sessionStore 已配置）**
   - Given Agent 配置了 EventBus + SessionStore
   - When `agent.prompt("task")` 被调用
   - Then EventBus 收到 `SessionCreatedEvent`（含 sessionId、task、model）

3. **AC3: SessionAutoSavedEvent 在 session auto-save 时 emit**
   - Given Agent 配置了 EventBus + SessionStore + persistSession
   - When stream/prompt 过程中 session auto-save 触发
   - Then EventBus 收到 `SessionAutoSavedEvent`（含 sessionId、messageCount）

4. **AC4: SessionClosedEvent 在 agent.close() 时 emit**
   - Given Agent 配置了 EventBus
   - When `agent.close()` 被调用
   - Then EventBus 收到 `SessionClosedEvent`（含 sessionId、finalStatus）

5. **AC5: 无 EventBus 时零开销**
   - Given Agent 未配置 EventBus（eventBus == nil）
   - When 执行 stream/prompt/close
   - Then 行为与当前完全一致，不创建 event struct，不发 publish

6. **AC6: promptImpl 的 error 路径也 emit SessionAutoSavedEvent**
   - Given Agent 配置了 EventBus + SessionStore + persistSession
   - When promptImpl 因 error 退出并触发 session auto-save
   - Then EventBus 收到 `SessionAutoSavedEvent`

7. **AC7: 现有测试全部通过**
   - Given 不注入 EventBus
   - When 运行全部现有测试
   - Then 全部通过，无回归

## Tasks / Subtasks

- [x] Task 1: 在 promptImpl 的 session 解析完成后 emit SessionCreatedEvent (AC: #2, #5)
  - [x] 1.1 在 promptImpl 的 session 解析完成之后、`AgentStartedEvent` emit 之前（~行 1404），添加 `SessionCreatedEvent` emit
  - [x] 1.2 仅当 `sessionStore != nil` 时 emit（因为 session 是 sessionStore 管理的）
  - [x] 1.3 使用 inline `if let eventBus = options.eventBus` guard，nil 时零开销
  - [x] 1.4 emit 内容：`SessionCreatedEvent(sessionId: resolvedSessionId, task: text, model: model)`

- [x] Task 2: 在 stream() 的 session 解析完成后 emit SessionCreatedEvent (AC: #1, #5)
  - [x] 2.1 在 stream() 的 session 解析完成后、`AgentStartedEvent` emit 之前（~行 2156），添加 `SessionCreatedEvent` emit
  - [x] 2.2 仅当 `capturedSessionStore != nil` 时 emit
  - [x] 2.3 使用 inline `if let eventBus = capturedEventBus` guard
  - [x] 2.4 emit 内容：`SessionCreatedEvent(sessionId: resolvedSessionId, task: text, model: capturedModel)`

- [x] Task 3: 在 promptImpl 的 session auto-save 处 emit SessionAutoSavedEvent (AC: #3, #5, #6)
  - [x] 3.1 在 promptImpl 正常结束路径的 `sessionStore.save()` 之后（~行 1869），添加 `SessionAutoSavedEvent` emit
  - [x] 3.2 在 promptImpl error 路径的 `sessionStore.save()` 之后（~行 1570），添加 `SessionAutoSavedEvent` emit
  - [x] 3.3 emit 内容：`SessionAutoSavedEvent(sessionId: resolvedSessionId, messageCount: deserializedMessages.count)`
  - [x] 3.4 使用 inline `if let eventBus = options.eventBus` guard

- [x] Task 4: 在 stream() 的 session auto-save 处 emit SessionAutoSavedEvent (AC: #3, #5)
  - [x] 4.1 在 stream() 正常结束路径的 `sessionStore.save()` 之后（~行 2956），添加 `SessionAutoSavedEvent` emit
  - [x] 4.2 emit 内容：`SessionAutoSavedEvent(sessionId: resolvedSessionId, messageCount: deserializedMessages.count)`
  - [x] 4.3 使用 inline `if let eventBus = capturedEventBus` guard

- [x] Task 5: 在 Agent.close() 中 emit SessionClosedEvent (AC: #4, #5)
  - [x] 5.1 在 `close()` 方法中，在 interrupt() 之后、sessionStore save 之前（~行 750），添加 `SessionClosedEvent` emit
  - [x] 5.2 使用 inline `if let eventBus = options.eventBus` guard
  - [x] 5.3 emit 内容：`SessionClosedEvent(sessionId: options.sessionId, finalStatus: .completed)` — close 是主动关闭，视为 completed
  - [x] 5.4 注意：close() 是 `async throws` 方法，可以直接 `await eventBus.publish()`

- [x] Task 6: 编写单元测试 (AC: #1-#7)
  - [x] 6.1 在 `Tests/OpenAgentSDKTests/Core/EventBusTests.swift` 追加 session lifecycle emit 测试
  - [x] 6.2 测试 AC2: promptImpl + EventBus + SessionStore → SessionCreatedEvent（含 sessionId、task、model）
  - [x] 6.3 测试 AC3: promptImpl + EventBus + SessionStore + persistSession → auto-save → SessionAutoSavedEvent（含 messageCount）
  - [x] 6.4 测试 AC4: close() + EventBus → SessionClosedEvent
  - [x] 6.5 测试 AC5: eventBus == nil → 无事件 emit（零开销）
  - [x] 6.6 测试 AC6: promptImpl error 路径 → SessionAutoSavedEvent

- [x] Task 7: 编写 E2E 测试 (AC: #1, #2, #4, #7)
  - [x] 7.1 在 `Sources/E2ETest/SessionLifecycleEmitE2ETests.swift` 创建 session lifecycle emit E2E 测试
  - [x] 7.2 E2E 测试：创建 Agent + EventBus → stream("task") → 验证收到 SessionCreatedEvent
  - [x] 7.3 E2E 测试：创建 Agent + EventBus → prompt("task") → 验证收到 SessionCreatedEvent
  - [x] 7.4 E2E 测试：创建 Agent + EventBus → close() → 验证收到 SessionClosedEvent
  - [x] 7.5 注册到 `Sources/E2ETest/main.swift`

- [x] Task 8: 验证构建与回归测试 (AC: #7)
  - [x] 8.1 `swift build` 确认编译通过
  - [x] 8.2 `swift test` 确认所有现有测试通过

## Dev Notes

### Architecture Context

本 Story 是 Epic 27 的 Session 生命周期事件 emit——在 Agent.swift 的 session 相关操作中注入 EventBus publish 调用。与 Story 27.2/27.3/27.4 的模式完全一致。

**关键设计决策：Session 事件仅在 sessionStore 已配置时 emit**

SessionCreatedEvent 和 SessionAutoSavedEvent 仅在 `sessionStore != nil` 时才有意义——没有 sessionStore 就没有 session。SessionClosedEvent 则不需要 sessionStore 条件（close 是 agent 级别操作）。

### Event Types (已定义在 AgentEventTypes.swift)

```swift
// line 64
public struct SessionCreatedEvent: AgentEvent, Equatable {
    public let base: BaseAgentEvent
    public let sessionId: String?
    public let task: String
    public let model: String
}

// line 153
public struct SessionClosedEvent: AgentEvent, Equatable {
    public let base: BaseAgentEvent
    public let sessionId: String?
    public let finalStatus: SessionFinalStatus  // .completed | .failed | .interrupted
}

// line 193
public struct SessionAutoSavedEvent: AgentEvent, Equatable {
    public let base: BaseAgentEvent
    public let sessionId: String?
    public let messageCount: Int
}
```

### Emit 位置与代码模式

#### Emit Point 1: promptImpl — SessionCreatedEvent (~行 1404 之前)

```swift
// 在 session 解析完成后、AgentStartedEvent emit 之前
// 仅当 sessionStore 存在时 emit（没有 sessionStore 就没有 session）
if let sessionStore = options.sessionStore, let eventBus = options.eventBus {
    await eventBus.publish(SessionCreatedEvent(
        sessionId: resolvedSessionId,
        task: text,
        model: model
    ))
}
```

#### Emit Point 2: stream() — SessionCreatedEvent (~行 2156 之前)

```swift
if let sessionStore = capturedSessionStore, let eventBus = capturedEventBus {
    await eventBus.publish(SessionCreatedEvent(
        sessionId: resolvedSessionId,
        task: text,
        model: capturedModel
    ))
}
```

#### Emit Point 3: promptImpl 正常结束 — SessionAutoSavedEvent (~行 1869 之后)

```swift
// 在 sessionStore.save() 成功之后
if let eventBus = options.eventBus {
    await eventBus.publish(SessionAutoSavedEvent(
        sessionId: resolvedSessionId,
        messageCount: deserializedMessages.count
    ))
}
```

#### Emit Point 4: promptImpl error 路径 — SessionAutoSavedEvent (~行 1570 之后)

```swift
// 在 error 路径的 sessionStore.save() 之后
if let eventBus = options.eventBus {
    await eventBus.publish(SessionAutoSavedEvent(
        sessionId: resolvedSessionId,
        messageCount: deserializedMessages.count
    ))
}
```

#### Emit Point 5: stream() 正常结束 — SessionAutoSavedEvent (~行 2956 之后)

```swift
if let eventBus = capturedEventBus {
    await eventBus.publish(SessionAutoSavedEvent(
        sessionId: resolvedSessionId,
        messageCount: deserializedMessages.count
    ))
}
```

#### Emit Point 6: close() — SessionClosedEvent (~行 750)

```swift
// 在 interrupt() 之后、sessionStore.save 之前
if let eventBus = options.eventBus {
    await eventBus.publish(SessionClosedEvent(
        sessionId: options.sessionId,
        finalStatus: .completed
    ))
}
```

**注意：** close() 中 emit SessionClosedEvent 使用 `options.sessionId`（非 resolvedSessionId），因为 close 不在 promptImpl/stream 的作用域内。

### SessionAutoSavedEvent 的 messageCount

session auto-save 使用 `deserializedMessages`（deep copy for Sendable）。messageCount 应使用 `deserializedMessages.count`：
- promptImpl 正常路径：`deserializedMessages` 已在 save 调用中构造
- promptImpl error 路径：同上
- stream 正常路径：同上

### close() 中的 SessionClosedEvent.finalStatus

`close()` 是用户主动关闭 agent，使用 `.completed` 状态。不同于 stream/prompt 中因 error 或 interrupt 退出的情况——那些场景的 finalStatus 已在 AgentCompletedEvent/AgentFailedEvent/AgentInterruptedEvent 中表达。

### Files to Modify

- **UPDATE**: `Sources/OpenAgentSDK/Core/Agent.swift` — 在 6 个位置添加 session lifecycle event emit
- **UPDATE**: `Tests/OpenAgentSDKTests/Core/EventBusTests.swift` — 追加 session lifecycle emit 单元测试
- **CREATE**: `Sources/E2ETest/SessionLifecycleEmitE2ETests.swift` — session lifecycle E2E 测试
- **UPDATE**: `Sources/E2ETest/main.swift` — 注册 E2E 测试

### 零开销保证

每个 emit 点使用 inline guard：
```swift
if let sessionStore = options.sessionStore, let eventBus = options.eventBus {
    await eventBus.publish(...)
}
```
当 `eventBus == nil` 时，不构造 event struct，不调用 publish。

### sessionId 来源

| 执行路径 | sessionId 变量 |
|---------|---------------|
| promptImpl | `resolvedSessionId`（局部变量） |
| stream() | `resolvedSessionId`（Task 闭包内局部变量） |
| close() | `options.sessionId`（直接属性） |

### Testing Strategy

**单元测试**（`Tests/OpenAgentSDKTests/Core/EventBusTests.swift`）:
- 创建 Agent + 注入 EventBus + MockSessionStore → subscribe → 调用 prompt → 验证 SessionCreatedEvent
- 创建 Agent + 注入 EventBus + MockSessionStore + persistSession → 调用 prompt → 验证 SessionAutoSavedEvent（含 messageCount）
- 创建 Agent + 注入 EventBus → 调用 close() → 验证 SessionClosedEvent
- 验证 eventBus == nil 时无事件 emit

**E2E 测试**（`Sources/E2ETest/SessionLifecycleEmitE2ETests.swift`）:
- 真实 LLM 调用 + EventBus → stream → 验证 SessionCreatedEvent
- 真实 LLM 调用 + EventBus → prompt → 验证 SessionCreatedEvent
- EventBus → close() → 验证 SessionClosedEvent
- 遵循 project convention：不使用 mock

### Scope Boundaries

**本 Story 只做：**
- 在 Agent.swift 的 session 相关位置 emit SessionCreatedEvent、SessionAutoSavedEvent、SessionClosedEvent
- 单元测试 + E2E 测试

**不做（后续 Epic）：**
- 修改 SessionStore 协议
- 添加 session restore 事件（SessionRestoredEvent 已定义但不在本 Story 范围内）
- 修改现有 session 逻辑（EventBus 是额外输出通道，不替代 sessionStore）

### Previous Story Intelligence (27.4)

Story 27.4 在 Agent.swift 的 4 个 usage 解析位置实现了 LLMCostEvent emit：
- 使用 inline `if let eventBus = options.eventBus` / `capturedEventBus` guard+publish 模式
- 零开销：eventBus == nil 时不构造 event struct
- 6 个单元测试 + 3 个 E2E 测试，全部通过
- 所有 5949 tests pass

**与 Story 27.4 的区别**：27.4 在 LLM response usage 解析处 emit，而 27.5 在 session 操作处 emit。27.5 额外需要检查 `sessionStore != nil` 条件（SessionCreatedEvent、SessionAutoSavedEvent），因为这两个事件仅在 session 管理存在时有意义。

### Project Structure Notes

- `Agent.swift` 位于 `Sources/OpenAgentSDK/Core/`，是 Agent 的主实现文件
- `SessionCreatedEvent` 定义在 `Sources/OpenAgentSDK/Types/AgentEventTypes.swift:64`
- `SessionClosedEvent` 定义在 `Sources/OpenAgentSDK/Types/AgentEventTypes.swift:153`
- `SessionAutoSavedEvent` 定义在 `Sources/OpenAgentSDK/Types/AgentEventTypes.swift:193`
- `SessionFinalStatus` 定义在 `Sources/OpenAgentSDK/Types/AgentEventTypes.swift:57`
- EventBus 是 `public actor`，通过 `AgentOptions.eventBus` 注入
- E2E 测试文件放在 `Sources/E2ETest/`，在 `main.swift` 注册

### References

- [Source: docs/epics/epic-27-agent-event-emitter.md#Story 27.5]
- [Source: Sources/OpenAgentSDK/Types/AgentEventTypes.swift — SessionCreatedEvent line 64, SessionClosedEvent line 153, SessionAutoSavedEvent line 193]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift — promptImpl session resolve line 1340, stream session resolve line 2090]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift — promptImpl auto-save line 1869, error auto-save line 1570]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift — stream auto-save line 2956]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift — close() line 738]
- [Source: _bmad-output/implementation-artifacts/27-4-llm-cost-event-emit.md — previous story]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4.6

### Debug Log References

### Completion Notes List

- All 6 emit points implemented in Agent.swift following existing Story 27.2-27.4 patterns
- Refactored EventBusTests to use timeout-protected collection helpers (collectEventsWithTimeout, collectFirstMatching, etc.)
- 6 unit tests + 5 E2E tests added, all passing
- All 5955 tests pass with 0 failures

### File List

- **UPDATED**: `Sources/OpenAgentSDK/Core/Agent.swift` — Added 6 session lifecycle event emit points (SessionCreatedEvent x2, SessionAutoSavedEvent x3, SessionClosedEvent x1)
- **UPDATED**: `Tests/OpenAgentSDKTests/Core/EventBusTests.swift` — Added 6 session lifecycle unit tests + refactored all existing tests to use timeout-protected helpers
- **CREATED**: `Sources/E2ETest/SessionLifecycleEmitE2ETests.swift` — 5 E2E tests for session lifecycle events (tests 153-157)
- **UPDATED**: `Sources/E2ETest/main.swift` — Registered SessionLifecycleEmitE2ETests

## Change Log

- 2026-05-26: Story implementation completed. All 8 tasks done. 6 emit points in Agent.swift, 6 unit tests, 5 E2E tests. All 5955 tests pass.
- 2026-05-26: Code review completed. Fixed E2E test comment (Tests 153-155 → 153-157). Updated story metadata.
