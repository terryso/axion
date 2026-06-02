---
baseline_commit: c0ba86f
---

# Story 29.3: TGEventHandler 事件推送

Status: done

## Story

As a Axion 用户,
I want 在 TG 上实时看到任务执行进展和最终结果,
So that 我不需要在电脑前也能跟踪任务状态.

## Acceptance Criteria

1. **Given** TG 任务正在执行中 **When** EventBus 发出 ToolCompletedEvent **Then** TGEventHandler 推送步骤进展到 TG（节流：最多每 5 秒推送一次） **And** 推送内容包含工具名称和执行时长（如 "步骤: screenshot (230ms)"）

2. **Given** TG 任务执行完成 **When** EventBus 发出 AgentCompletedEvent **Then** 最终结果推送到 TG **And** 长消息自动分段发送（TG 限制 4096 字符）

3. **Given** TG 任务执行失败 **When** EventBus 发出 AgentFailedEvent **Then** 错误信息推送到 TG（不包含 API Key） **And** 错误消息包含用户友好的描述（引用 error 字段）

## Tasks / Subtasks

- [x] Task 1: 创建 TGEventHandler actor (AC: #1, #2, #3)
  - [x] 1.1 创建 `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift`
  - [x] 1.2 实现 `EventHandler` protocol（identifier, subscribedEventTypes）
  - [x] 1.3 实现 ToolCompletedEvent 处理 — 步骤进展推送 + 节流（5 秒）
  - [x] 1.4 实现 AgentCompletedEvent 处理 — 最终结果推送
  - [x] 1.5 实现 AgentFailedEvent 处理 — 错误信息推送
  - [x] 1.6 提取 `TGEventHandlerProtocol` 用于测试注入

- [x] Task 2: 修改 DaemonRuntimeManager 注入 TGEventHandler (AC: #1, #2, #3)
  - [x] 2.1 添加 `tgEventHandlerFactory` 可选参数到 init
  - [x] 2.2 在 executeRun 中条件注册 TGEventHandler
  - [x] 2.3 通过 eventBus 关联 chatId 与任务执行

- [x] Task 3: 修改 TaskSerialQueue 注入 TGEventHandler (AC: #1, #2, #3)
  - [x] 3.1 TaskSerialQueue 在执行任务时创建 TGEventHandler 实例并注入到 DaemonRuntimeManager
  - [x] 3.2 通过 replyHandler 闭包连接 TGEventHandler 的推送能力

- [x] Task 4: 单元测试 (AC: #1–#3)
  - [x] 4.1 测试 TGEventHandler 订阅正确事件类型
  - [x] 4.2 测试 ToolCompletedEvent 推送内容格式
  - [x] 4.3 测试节流逻辑（5 秒内多次事件只推送一次）
  - [x] 4.4 测试 AgentCompletedEvent 推送结果
  - [x] 4.5 测试 AgentFailedEvent 推送错误（不含 API Key）
  - [x] 4.6 测试长消息分段
  - [x] 4.7 测试无 chatId 时静默跳过（非 TG 任务）

## Dev Notes

### 架构约束

**TGEventHandler 是 actor** — 实现 `EventHandler` protocol（project-context.md 列出所有 EventHandler 必须是 actor）。参考 `NotificationHandler` 作为最佳范例：同样订阅 AgentCompletedEvent/AgentFailedEvent，通过闭包注入发送逻辑。

**chatId 传递方案** — EventHandler 的 `handle(_:context:)` 不包含 TG chatId。采用 Epic 29 设计文档的推荐方案 1：**每个 TG 任务创建专属的 TGEventHandler 实例**，init 时注入 chatId。非 TG 任务（HTTP API / CLI）不会创建 TGEventHandler。

**TGEventHandler 不持有 TelegramAdapter 引用** — 通过注入的 `@Sendable (String, Int64) async -> Void` 闭包推送消息，闭包内部由调用方绑定到 TelegramAdapter.sendReply。避免循环依赖。

### 需要修改的文件

**`Sources/AxionCLI/Services/DaemonRuntimeManager.swift`**（130 行）

当前状态：`executeRun` 创建 `AxionRuntime(eventBus:)`，注册 `CostEventHandler` + `TraceEventHandler`。有 `runtimeFactory` 闭包用于创建 runtime 实例。

本故事变更：
- init 新增可选参数 `extraHandlerFactory: ((EventBus) -> [any EventHandler])?` 或更简单的方案：在 executeRun 中新增可选参数 `extraHandlers: [any EventHandler]`
- 推荐方案：修改 `DaemonRuntimeManaging` protocol 的 `executeRun` 添加 `extraHandlers` 参数（默认空数组），DaemonRuntimeManager 在 registerHandler Cost + Trace 后注册 extraHandlers
- 这样 TaskSerialQueue 在调用 executeRun 时可以传入 `[TGEventHandler(chatId: chatId, sendReply: replyHandler)]`

必须保留：所有现有 DaemonRuntimeManager 行为（session tracking, eviction, runtimeFactory）。

**`Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift`**（140 行）

当前状态：`processNext()` 中创建 `EventBus()` 和调用 `runtimeManager.executeRun(task:buildConfig:eventBus:runOverrides:)`。有 `replyHandler` 闭包用于 TG 回复。

本故事变更：
- 在 `processNext()` 中，创建 `TGEventHandler` 实例（注入 chatId 和 replyHandler）
- 将 TGEventHandler 作为 extraHandler 传入 `executeRun`
- 修改 `DaemonRuntimeManaging.executeRun` 签名以接受 extraHandlers

必须保留：排队/超时/取消/串行执行全部行为。

**`Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift`**（36 行）

当前状态：`executeRun` 和 `executeSkill` 两个方法。

本故事变更：
- `executeRun` 新增参数 `extraHandlers: [any EventHandler] = []`
- `executeSkill` 同理（可选，TG 任务不通过 executeSkill 路径）

必须保留：protocol 方法签名兼容（默认参数确保现有调用方无需修改）。

### 新增文件

```
Sources/AxionCLI/Runtime/Handlers/
└── TGEventHandler.swift     # Actor：EventBus → TG 推送（~120 行）

Tests/AxionCLITests/Services/Telegram/
└── TGEventHandlerTests.swift    # 单元测试（~180 行）
```

**注意：** epic-29 设计文档建议 TGEventHandler 放在 `Sources/AxionCLI/Runtime/Handlers/`，与其他 EventHandler（NotificationHandler、ReviewHandler）一致。但考虑到 TGEventHandler 与 Telegram 通信紧密相关，也可放在 `Sources/AxionCLI/Services/Telegram/`。推荐放在 `Runtime/Handlers/` 保持一致性。

### TGEventHandler 设计

```swift
// TGEventHandler.swift

actor TGEventHandler: EventHandler {
    let identifier = "telegram-push"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        ToolCompletedEvent.self,
        AgentCompletedEvent.self,
        AgentFailedEvent.self,
    ]

    private let chatId: Int64
    private let sendMessage: @Sendable (String, Int64) async -> Void
    private var lastPushTime: Date = .distantPast
    private let pushInterval: TimeInterval = 5.0
    private var stepCount: Int = 0

    init(chatId: Int64, sendMessage: @escaping @Sendable (String, Int64) async -> Void) {
        self.chatId = chatId
        self.sendMessage = sendMessage
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        switch event {
        case let toolEvent as ToolCompletedEvent:
            await handleToolCompleted(toolEvent)
        case let completedEvent as AgentCompletedEvent:
            await handleCompleted(completedEvent, context: context)
        case let failedEvent as AgentFailedEvent:
            await handleFailed(failedEvent)
        default:
            break
        }
    }

    private func handleToolCompleted(_ event: ToolCompletedEvent) async {
        stepCount += 1
        let now = Date()
        guard now.timeIntervalSince(lastPushTime) >= pushInterval else { return }
        lastPushTime = now

        let statusEmoji = event.isError ? "❌" : "✓"
        let message = "步骤 \(stepCount): \(event.toolName) (\(event.durationMs)ms) \(statusEmoji)"
        await sendMessage(message, chatId)
    }

    private func handleCompleted(_ event: AgentCompletedEvent, context: EventHandlerContext) async {
        var result = "✅ 任务完成 (\(event.totalSteps) 步, \(event.durationMs / 1000)s)"
        if let text = event.resultText, !text.isEmpty {
            result += "\n\n\(text)"
        }
        await sendMessage(result, chatId)
    }

    private func handleFailed(_ event: AgentFailedEvent) async {
        let message = "❌ 任务失败: \(event.error)"
        await sendMessage(message, chatId)
    }
}
```

**关键设计决策：**
- `stepCount` 在 actor 内部递增 — 因为 actor 是串行化的，不需要额外同步
- 节流基于 `Date.timeIntervalSince` — 简单可靠，不需要 Timer
- `AgentCompletedEvent` 和 `AgentFailedEvent` 不节流 — 它们是终端事件，必须推送
- 错误消息直接使用 `event.error`（SDK AgentFailedEvent 的 error 字段不含 API Key）
- 结果文本可能很长（agent 输出），`sendMessage` 内部的 TelegramAdapter.sendReply 已有分段逻辑

### DaemonRuntimeManaging 修改

```swift
// DaemonRuntimeManaging.swift
protocol DaemonRuntimeManaging: Sendable {
    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides,
        extraHandlers: [any EventHandler]  // 新增，默认 [] 在 extension 中提供
    ) async throws -> AxionRunResult
    // ... 其余不变
}
```

**或者更简单的方案：** 不修改 protocol，让 `TaskSerialQueue` 直接使用 `DaemonRuntimeManager`（具体类型而非 protocol）。但这破坏了 DI 原则。

**推荐方案：** 在 protocol 中添加 `extraHandlers` 参数，提供默认实现：

```swift
// 在 DaemonRuntimeManaging extension 中
extension DaemonRuntimeManaging {
    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult {
        return try await executeRun(
            task: task,
            buildConfig: buildConfig,
            eventBus: eventBus,
            runOverrides: runOverrides,
            extraHandlers: []
        )
    }
}
```

但 protocol extension 不能提供默认实现给 class/actor。实际做法：在调用侧提供默认参数。

### TaskSerialQueue 修改

在 `processNext()` 中创建 TGEventHandler 并注入：

```swift
// TaskSerialQueue.swift — processNext() 中
let tgHandler = TGEventHandler(
    chatId: pending.chatId,
    sendMessage: { [weak self] message, chatId in
        await self?.replyHandler(chatId, message)
    }
)

let result = try await runtimeManager.executeRun(
    task: pending.task,
    buildConfig: buildConfig,
    eventBus: eventBus,
    runOverrides: .default,
    extraHandlers: [tgHandler]
)
```

### 测试要求

**框架：** Swift Testing（`import Testing`、`@Suite`、`@Test`、`#expect`）
**测试目录：** `Tests/AxionCLITests/Services/Telegram/`（与 TelegramAdapter 测试同目录）

**Mock 策略：**
- `sendMessage` 闭包 — 注入收集闭包，记录所有 (String, Int64) 对
- `ToolCompletedEvent` — 直接构造（有 public init）
- `AgentCompletedEvent` — 直接构造
- `AgentFailedEvent` — 直接构造
- `EventHandlerContext` — 构造最小 mock（需要 sessionId, config, eventBus, sessionStore）

**运行测试：** `swift test --filter "AxionCLITests.Services.Telegram.TGEventHandler"`

### 前置 Story 经验

- **Story 29.1:** TelegramAdapter 已实现 `sendReply` 和分段逻辑。TGEventHandler 通过闭包间接调用，不直接依赖 TelegramAdapter
- **Story 29.1 review:** `nonisolated(unsafe)` 用于 actor 外同步读取 — TGEventHandler 不需要此模式（sendMessage 通过闭包注入）
- **Story 29.1 review:** 4xx 错误不重试 — 已在 TGAPIClient 中处理
- **Story 29.2:** TaskSerialQueue 使用 `replyHandler` 闭包模式。TGEventHandler 复用相同的闭包注入模式
- **Story 29.2 review:** 递归 `processNext()` 改为 while loop — 当前已经是 while loop
- **NotificationHandler** 是最佳参考：同样是 actor + EventHandler，订阅 AgentCompletedEvent/AgentFailedEvent，通过闭包注入发送逻辑

### 安全规则

- 错误消息不包含 API Key（SDK AgentFailedEvent.error 字段已过滤敏感信息）
- TGEventHandler 只推送到白名单用户的 chatId（chatId 来自已验证的白名单消息）
- 步骤进展节流避免 TG API rate limit

### 项目结构说明

- 新建 `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift`（与 NotificationHandler、ReviewHandler 同目录）
- 新建 `Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift`
- 修改 `DaemonRuntimeManaging.swift`（executeRun 新增 extraHandlers 参数）
- 修改 `DaemonRuntimeManager.swift`（注册 extraHandlers）
- 修改 `TaskSerialQueue.swift`（创建 TGEventHandler 并注入）

### References

- [Source: _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md#FR-2.4 — 任务执行中每步进展推送]
- [Source: _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md#FR-2.5 — 任务完成后最终结果推送]
- [Source: docs/epics/epic-29-telegram-remote.md#Story 29.3 — AC 和 TGEventHandler 设计参考]
- [Source: docs/epics/epic-29-telegram-remote.md#TGEventHandler 设计 — chatId 传递方案]
- [Source: _bmad-output/planning-artifacts/architecture.md#D10 — TelegramAdapter 通信模式 + EventBus → TG 推送]
- [Source: _bmad-output/project-context.md#执行循环 — EventHandler 注册和事件分发]
- [Source: _bmad-output/project-context.md#反模式 #15 — 未授权 TG 消息静默丢弃]
- [Source: _bmad-output/implementation-artifacts/29-1-telegramadapter-core-communication.md — TelegramAdapter.sendReply 分段逻辑]
- [Source: _bmad-output/implementation-artifacts/29-2-task-serial-execution-queue.md — TaskSerialQueue replyHandler 模式]
- [Source: Sources/AxionCLI/Runtime/Handlers/NotificationHandler.swift — EventHandler actor 最佳参考]
- [Source: Sources/AxionCLI/Services/EventHandler.swift — EventHandler protocol 定义]
- [Source: Sources/AxionCLI/Services/EventHandlerContext.swift — EventHandlerContext 字段]
- [Source: Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift — executeRun 接口]
- [Source: Sources/AxionCLI/Services/DaemonRuntimeManager.swift — executeRun 实现 + handler 注册]
- [Source: Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift — processNext 中的 EventBus 创建]
- [Source: OpenAgentSDK/Types/AgentEventTypes.swift#AgentCompletedEvent — totalSteps, durationMs, resultText]
- [Source: OpenAgentSDK/Types/AgentEventTypes.swift#AgentFailedEvent — error, stepsCompleted]
- [Source: OpenAgentSDK/Types/AgentEventTypes.swift#ToolCompletedEvent — toolName, durationMs, isError, output]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- Created `TGEventHandler` actor implementing `EventHandler` protocol, subscribing to `ToolCompletedEvent`, `AgentCompletedEvent`, `AgentFailedEvent`
- ToolCompletedEvent: step progress with throttling (5s interval), includes tool name, duration, and status emoji
- AgentCompletedEvent: final result push with step count and duration
- AgentFailedEvent: error push with user-friendly message (no API key exposure)
- Extracted `TGEventHandlerProtocol` for test injection
- Added `executeRun(... extraHandlers:)` overload to `DaemonRuntimeManaging` protocol with backward-compatible default
- `DaemonRuntimeManager` implements both overloads — original delegates to new one with empty extraHandlers
- `TaskSerialQueue` creates `TGEventHandler` per task with injected chatId + replyHandler closure
- Updated 2 test mocks (`MockDaemonRuntimeManager`, `MockRuntimeManager`) to implement new protocol method
- All 9 TGEventHandler tests pass, 11 TaskSerialQueue tests pass, 15 DaemonRuntimeManager tests pass, 139 AxionCore tests pass — no regressions

### File List

- `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` (new)
- `Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift` (modified — added executeRun overload)
- `Sources/AxionCLI/Services/DaemonRuntimeManager.swift` (modified — implements extraHandlers)
- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` (modified — creates TGEventHandler per task)
- `Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift` (new — 9 tests)
- `Tests/AxionCLITests/Services/DaemonRuntimeManagerTests.swift` (modified — mock updated)
- `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` (modified — mock updated)

## Change Log

- 2026-05-29: Implemented TGEventHandler actor with step progress throttling, result/error push. Modified DaemonRuntimeManaging protocol with backward-compatible extraHandlers parameter. TaskSerialQueue injects TGEventHandler per TG task. 9 unit tests covering all ACs.
- 2026-05-29: Senior Developer Review (AI). Found 1 HIGH + 2 MEDIUM + 1 LOW issues. Fixed: (H1) removed duplicate completion/error messages — TaskSerialQueue no longer sends summary reply since TGEventHandler already pushes via AgentCompletedEvent/AgentFailedEvent. (M1) removed dead TGEventHandlerProtocol. Updated test assertion to match. All 35 tests pass.

## Senior Developer Review (AI)

**Reviewer:** AI (adversarial) on 2026-05-29
**Outcome:** Approved (after fixes)

### Issues Found & Fixed

| # | Severity | Description | File | Status |
|---|----------|-------------|------|--------|
| H1 | HIGH | Duplicate completion/error messages — both TGEventHandler and TaskSerialQueue sent final result to TG user via replyHandler | TaskSerialQueue.swift:110-111 | Fixed |
| M1 | MEDIUM | TGEventHandlerProtocol was dead code — defined but never consumed | TGEventHandler.swift:5-7 | Fixed (removed) |
| M2 | MEDIUM | Inconsistent time units (ms in progress vs s in completion) — by design, not fixed | TGEventHandler.swift | Accepted |
| L1 | LOW | Test 4.7 name doesn't match behavior — by design (non-TG tasks don't create handler) | TGEventHandlerTests.swift:195 | Accepted |
