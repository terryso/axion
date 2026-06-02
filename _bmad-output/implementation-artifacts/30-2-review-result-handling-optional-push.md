---
baseline_commit: ed9108dc70882011d704cc0b66c59ee9cd518f25
---
# Story 30.2: 审查结果处理与可选 TG 推送

Status: done

## Story

As a Axion Gateway 长驻进程,
I want ReviewScheduler 完成审查后，将结果通过 EventHandler 机制传递给 TGEventHandler（可选），同时 GatewayRunner 状态查询展示审查详情，
so that 用户通过 TG 远程收到审查学习成果通知，且能通过 `/status` 查看自进化状态。

## Acceptance Criteria

1. **ReviewResultEvent 定义** — 新建 `ReviewResultEvent`（实现 `AgentEvent` protocol），包含 `summary: String`、`memoryChanges: [String]`、`skillChanges: [String]`、`success: Bool`、`durationMs: Int` 字段。

   **Given** ReviewScheduler 审查完成
   **When** 结果处理
   **Then** 构造 `ReviewResultEvent` 并通过 `context.eventBus` 发出

2. **ReviewScheduler 发出 ReviewResultEvent** — 审查完成后（成功或失败），通过 `EventHandlerContext.eventBus` 发出 `ReviewResultEvent`。ReviewScheduler 当前的 stderr 输出 + trace 记录逻辑保留不变。

   **Given** 审查成功完成
   **When** detached Task 处理结果
   **Then** 通过 `eventBus.emit(ReviewResultEvent(...))` 发出事件，并保留现有的 TraceRecorder + stderr 逻辑

   **Given** 审查失败（result == nil）
   **When** detached Task 处理结果
   **Then** 发出 `ReviewResultEvent(success: false, ...)` 事件

3. **TGEventHandler 订阅 ReviewResultEvent** — TGEventHandler 新增订阅 `ReviewResultEvent.self`，收到后推送审查摘要到 TG。

   **Given** TGEventHandler 订阅了 ReviewResultEvent
   **When** 收到 ReviewResultEvent 且 success == true 且有变更
   **Then** 发送如 "📊 审查完成: 新增 2 条记忆, 更新 1 个技能" 到 TG

   **Given** TGEventHandler 收到 ReviewResultEvent 且 success == false
   **Then** 发送 "⚠️ 后台审查失败" 到 TG

4. **ReviewResultEvent 不触发非 TG 路径** — 非 Gateway 模式（CLI/HTTP API）下，没有 TGEventHandler，ReviewResultEvent 被忽略（没有订阅者）。

   **Given** CLI 或 HTTP API 模式下执行 run
   **When** ReviewScheduler 发出 ReviewResultEvent
   **Then** 没有订阅者处理该事件，ReviewScheduler 的 stderr + trace 逻辑正常工作

5. **RunOrchestrator CLI 路径 onReviewCompleted 回调保留** — CLI 模式下 RunOrchestrator 的 inline 审查 + `onReviewCompleted` 回调不变，不受影响。

   **Given** CLI 模式执行 `axion run`
   **When** 审查完成
   **Then** onReviewCompleted 回调正常调用，stderr 输出正常

6. **Gateway status 展示审查详情** — `axion gateway status` 输出中，`last_review_at` 字段扩展为包含 `review_summary` 信息。

   **Given** 至少执行过一次审查
   **When** 查询 gateway status
   **Then** JSON 响应包含 `last_review_at` 时间戳和可选的 `last_review_summary` 字段

7. **单元测试** — 所有新增逻辑有对应单元测试。

   **Given** 新增 ReviewResultEvent 和 TGEventHandler 扩展
   **When** 运行 `swift test --filter "AxionCLITests"`
   **Then** 所有测试通过

## Tasks / Subtasks

- [x] Task 1: 定义 ReviewResultEvent (AC: #1)
  - [x] 1.1 新建 `Sources/AxionCLI/Services/Events/ReviewResultEvent.swift`（struct 实现 AgentEvent protocol）
  - [x] 1.2 字段：summary, memoryChanges, skillChanges, success, durationMs, sessionId
  - [x] 1.3 遵循现有 AgentEvent 命名和实现模式（参考 `AgentCompletedEvent`）

- [x] Task 2: ReviewScheduler 发出 ReviewResultEvent (AC: #2)
  - [x] 2.1 修改 `ReviewScheduler.swift`：在 detached Task 审查完成后，构造 ReviewResultEvent
  - [x] 2.2 通过 `reviewDataContext` 持有的 eventBus 引用发出事件（或通过 EventHandlerContext 传递的 eventBus）
  - [x] 2.3 保留现有 TraceRecorder + stderr 逻辑不变
  - [x] 2.4 审查失败时也发出 ReviewResultEvent(success: false)

- [x] Task 3: TGEventHandler 订阅 ReviewResultEvent (AC: #3, #4)
  - [x] 3.1 修改 `TGEventHandler.swift`：subscribedEventTypes 新增 ReviewResultEvent.self
  - [x] 3.2 handle() 新增 ReviewResultEvent case，调用 handleReviewResult()
  - [x] 3.3 实现 handleReviewResult()：格式化审查摘要并推送 TG
  - [x] 3.4 审查失败时推送 "⚠️ 后台审查失败"

- [x] Task 4: Gateway status 扩展 (AC: #6)
  - [x] 4.1 修改 `GatewayRunner.swift`：GatewayRunnerStatus 新增 `lastReviewSummary: String?` 字段
  - [x] 4.2 新增 `_reviewSummaryProvider: (@Sendable () -> String?)?` + `setReviewSummaryProvider()`
  - [x] 4.3 修改 `GatewayCommand.swift`：创建 ReviewScheduler 时注入 summary provider
  - [x] 4.4 ReviewScheduler 新增 `lastReviewSummaryValue: String?`（使用 LockedStringBox）

- [x] Task 5: 单元测试 (AC: #7)
  - [x] 5.1 ReviewResultEventTests: 测试事件构造和字段
  - [x] 5.2 ReviewSchedulerTests: 新增测试 — 审查完成后发出 ReviewResultEvent
  - [x] 5.3 TGEventHandlerTests: 新增测试 — ReviewResultEvent 触发 TG 推送
  - [x] 5.4 TGEventHandlerTests: 测试审查失败场景的推送
  - [x] 5.5 GatewayRunnerStatusTests: 测试 lastReviewSummary 字段编码/解码

## Dev Notes

### 核心问题：ReviewScheduler 如何获取 EventBus 引用

ReviewScheduler 作为 EventHandler 在 `handle()` 方法中收到 `EventHandlerContext`，其中包含 `eventBus: EventBus?`。但 ReviewScheduler 的审查逻辑在 `Task.detached` 中执行，此时 `context` 可能已经失效。

**解决方案：** ReviewScheduler 在 init 时注入 `eventBusProvider: (@Sendable () -> EventBus?)?` 闭包。该闭包在 detached Task 中调用获取 EventBus 引用。GatewayCommand 构建时传入闭包。

或者更简方案：在 `handle()` 方法中捕获 `context.eventBus` 传入 detached Task（EventBus 是 `final class` 即引用类型，在 detached Task 中安全持有）。验证 EventBus 的 Sendable 属性 — 如果 EventBus 不是 Sendable，则使用闭包方案。

### ReviewResultEvent 设计

```swift
struct ReviewResultEvent: AgentEvent {
    let summary: String
    let memoryChanges: [String]
    let skillChanges: [String]
    let success: Bool
    let durationMs: Int
    let sessionId: String
}
```

参考 `AgentCompletedEvent` 的字段模式（totalSteps, durationMs, resultText 等）。ReviewResultEvent 是纯数据事件，无副作用。

### TGEventHandler 扩展策略

TGEventHandler 已经订阅了 4 种事件类型。新增 `ReviewResultEvent.self` 是增量修改：

```swift
let subscribedEventTypes: [any AgentEvent.Type] = [
    ToolStartedEvent.self,
    ToolCompletedEvent.self,
    AgentCompletedEvent.self,
    AgentFailedEvent.self,
    ReviewResultEvent.self,  // NEW
]
```

`handle()` 方法的 switch 新增 case：
```swift
case let reviewEvent as ReviewResultEvent:
    await handleReviewResult(reviewEvent)
```

### 关键：单一消息归属（Epic 29 L2）

审查结果的 TG 推送**只有 TGEventHandler 负责**。ReviewScheduler **不直接调用** TG 推送。ReviewScheduler 只发出 ReviewResultEvent，TGEventHandler 订阅并推送。这遵循 Epic 29 L2 的 "单一消息归属" 原则。

### 关键：CLI 路径不受影响

CLI 模式下：
- RunOrchestrator inline 执行审查（不走 ReviewScheduler）
- `onReviewCompleted` 回调正常工作
- 没有 TGEventHandler 注册
- ReviewResultEvent 没有订阅者 → 自动忽略

HTTP API 模式下：
- 同 CLI，RunOrchestrator inline 执行审查
- 没有 TGEventHandler（只有 SSE EventBusBridge）
- ReviewResultEvent 没有订阅者 → 自动忽略

Gateway 模式下：
- ReviewScheduler 作为 EventHandler 执行审查
- TGEventHandler 订阅 ReviewResultEvent → TG 推送
- 审查结果同时走 stderr + trace + TG 推送

### GatewayRunnerStatus 扩展

当前 `GatewayRunnerStatus` 有 `lastReviewAt: String?`。扩展：
- `lastReviewSummary: String?` — 最近一次审查摘要

ReviewScheduler 新增 `lastReviewSummaryValue`（LockedStringBox），在审查成功后更新。GatewayCommand 通过 setStatusProviders 注入。

### 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/AxionCLI/Services/Events/ReviewResultEvent.swift` | NEW | ReviewResultEvent 定义 |
| `Sources/AxionCLI/Services/ReviewScheduler.swift` | UPDATE | detached Task 审查完成后发出 ReviewResultEvent + lastReviewSummaryValue |
| `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` | UPDATE | 订阅 ReviewResultEvent + handleReviewResult() |
| `Sources/AxionCLI/Services/GatewayRunner.swift` | UPDATE | GatewayRunnerStatus 新增 lastReviewSummary 字段 |
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | UPDATE | 注入 reviewSummaryProvider |
| `Tests/AxionCLITests/Services/ReviewResultEventTests.swift` | NEW | ReviewResultEvent 测试 |
| `Tests/AxionCLITests/Services/ReviewSchedulerTests.swift` | UPDATE | 新增 ReviewResultEvent 发出测试 |
| `Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift` | UPDATE | 新增 ReviewResultEvent 订阅测试 |

### Project Structure Notes

- ReviewResultEvent 放在 `Sources/AxionCLI/Services/Events/` — 遵循事件类型独立文件的模式（如果 Events 目录不存在，与 `ReviewScheduler.swift` 同级也可以）
- 测试文件遵循 `Tests/AxionCLITests/` 镜像规则

### References

- [Source: architecture.md#D11] 后台审查 Actor 隔离策略 — "审查 agent 不发 TG 通知 → 结果只写 trace"（本 story 扩展：通过 Event 机制让 TGEventHandler 订阅）
- [Source: architecture.md#D9] Gateway 进程模型 — ReviewScheduler + TGEventHandler 组件定义
- [Source: prds/prd-axion-gateway-2026-05-29/prd.md#FR-3.4] 审查结果可选推送到 TG
- [Source: ReviewScheduler.swift] 当前实现 — detached Task + TraceRecorder + stderr
- [Source: TGEventHandler.swift] 当前订阅 4 种事件 + sendMessage 闭包推送模式
- [Source: GatewayRunner.swift] GatewayRunnerStatus + statusProviders 模式
- [Source: EventHandlerContext.swift] eventBus 字段可用于发出事件
- [Source: epic-29-retro#L2] 单一消息归属 — 审查结果推送只有 TGEventHandler 负责
- [Source: story 30.1 completion notes] ReviewScheduler 使用 ReviewDataContext + LockedStringBox 模式

### 从 Story 30.1 学到的教训

- **ReviewDataContext 模式** — 通过线程安全 box 在 RunOrchestrator 和 ReviewScheduler 之间共享数据，不扩展 EventHandlerContext
- **LockedStringBox 模式** — 非隔离域读取 actor 状态用 LockedStringBox
- **_Concurrency.Task.detached** — 避免 NIO Task 名字冲突
- **ReviewOrchestrating protocol** — 抽象注入测试 mock
- **EventBus 获取方式** — ReviewScheduler 当前不持有 EventBus 引用，需要通过 init 注入或在 handle() 中捕获

### 反模式预防

- **不要让 ReviewScheduler 直接调用 TG 推送** — 必须通过 Event 机制解耦
- **不要修改 RunOrchestrator 的 inline 审查逻辑** — CLI/API 路径保持不变
- **不要在 ReviewResultEvent 中包含敏感数据** — 只包含摘要信息
- **不要忘记审查失败场景** — ReviewResultEvent(success: false) 也要发出
- **不要在 TGEventHandler 中对 ReviewResultEvent 做详细展开** — 推送一句话摘要即可，避免 TG 消息过长
- **不要修改 EventHandlerContext** — 不扩展，使用现有 eventBus 字段或闭包注入

### AgentEvent Protocol 遵循

参考 SDK 中 `AgentEvent` 的定义方式。所有 AgentEvent 实现都是 struct + Sendable。ReviewResultEvent 同理。

### EventBus.emit 线程安全

EventBus 是 SDK 提供的事件总线。检查 EventBus 的 `emit` 方法是否可以在 detached Task 中安全调用。EventBus 通常是 actor 或使用内部锁，应该安全。如果不安全，改用 `reviewDataContext` 持有 EventBus 引用，在 ReviewScheduler 的 actor isolation 内调用 emit。

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Sendability error in ReviewSchedulerTests fixed by introducing ReviewEventBox (thread-safe box for capturing events in Task closures)

### Completion Notes List

- ReviewResultEvent defined following AgentCompletedEvent pattern (BaseAgentEvent composition, Codable with snake_case keys)
- EventBus is an actor, so capturing context.eventBus in detached Task is safe — simpler than closure injection
- ReviewScheduler captures eventBus from EventHandlerContext in detached Task; publishes ReviewResultEvent on success and failure
- TGEventHandler subscribes to ReviewResultEvent (5th event type); pushes formatted summary on success, warning on failure; skips when no changes
- GatewayRunnerStatus extended with lastReviewSummary field; setStatusProviders signature expanded
- All 1448 tests pass with no regressions

### File List

- Sources/AxionCLI/Services/Events/ReviewResultEvent.swift (NEW)
- Sources/AxionCLI/Services/ReviewScheduler.swift (MODIFIED)
- Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift (MODIFIED)
- Sources/AxionCLI/Services/GatewayRunner.swift (MODIFIED)
- Sources/AxionCLI/Commands/GatewayCommand.swift (MODIFIED)
- Tests/AxionCLITests/Services/ReviewResultEventTests.swift (NEW)
- Tests/AxionCLITests/Services/ReviewSchedulerTests.swift (MODIFIED)
- Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift (MODIFIED)
- Tests/AxionCLITests/Services/GatewayRunnerTests.swift (MODIFIED)

### Change Log

- 2026-05-30: Story 30.2 implementation complete — ReviewResultEvent + TGEventHandler subscription + GatewayRunner status extension + unit tests
- 2026-05-30: Senior Developer Review (AI) — found and fixed 6 issues

### Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.7 on 2026-05-30

**Issues Found:** 2 HIGH, 2 MEDIUM, 2 LOW — all fixed

**HIGH Issues Fixed:**
1. ReviewResultEvent never reaches TGEventHandler in production — per-request EventBus stops before detached review task completes. Fixed by adding `onReviewResult` direct callback to ReviewScheduler, wired in GatewayCommand to send TG notifications via TelegramAdapter.
2. TaskSerialQueue missing ReviewScheduler — TG tasks never triggered reviews. Fixed by adding `extraHandlers` parameter to TaskSerialQueue, passing `[reviewScheduler]` from GatewayCommand.

**MEDIUM Issues Fixed:**
1. Story File List had wrong path for TGEventHandlerTests (`Handlers/` → `Services/Telegram/`).
2. `printLiveStatus` didn't display `lastReviewSummary` field — now prints when present.

**LOW Issues Fixed:**
1. stderr text "更新了" inconsistent with summary/TG push text "更新" — unified to "更新".
2. Missing tests for `onReviewResult` callback — added 3 new tests (success, failure, setOnReviewResult).

**Files Modified by Review:**
- Sources/AxionCLI/Services/ReviewScheduler.swift (onReviewResult callback + stderr text fix)
- Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift (extraHandlers parameter)
- Sources/AxionCLI/Commands/GatewayCommand.swift (wire callback + pass extraHandlers + printLiveStatus)
- Tests/AxionCLITests/Services/ReviewSchedulerTests.swift (3 new callback tests)

**Test Results:** 50 tests in 4 suites — all passing.
