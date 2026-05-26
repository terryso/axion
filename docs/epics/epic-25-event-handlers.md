# Axion Epic 25: EventHandler 体系

> **状态：待开发**
> **优先级：P0**
> **前置依赖：Axion Epic 24（AxionRuntime Core）**
> **Roadmap：** `docs/agent-runtime-roadmap.md` → A3

## 背景与动机

`RunOrchestrator` 有 ~350 行横切关注点代码写在 stream loop 的 switch-case 里：
- Visual delta 追踪（screenshot 对比）
- Seat activity 监控（helper tool 活动检测）
- Cost 统计（run 完成时汇总）
- Memory 处理（run 结束后处理记忆）
- Review + Curator（代码审查与策展）
- Desktop notification（完成通知）
- Trace 记录（事件追踪）

将它们提取为独立的 event handler 后：
1. 每个 handler 订阅特定 `AgentEvent` 类型
2. handler 独立可测试
3. CLI 和 API 可以注册不同的 handler 组合

**数据来源设计：**

每个 handler 明确声明数据来源。AxionRuntime 的 `EventHandlerContext` 提供三种数据通道：

| 通道 | 内容 | 何时可用 |
|------|------|---------|
| `AgentEvent` payload | 单次事件的数据（token、output、toolName 等） | 每个事件到达时 |
| `RunCompleteContext` | SDK 聚合数据（toolPairs、usage、durationMs） | terminal event 时（`onRunComplete` 回调已触发） |
| `SessionStore.load()` | 完整对话历史（`[SDKMessage]`） | agent 完成后可调用 |

| Handler | AgentEvent | RunCompleteContext | SessionStore | AxionRunState |
|---------|-----------|-------------------|-------------|---------------|
| CostEventHandler | terminal event（触发） | ✅ totalCostUsd, usage | ❌ | ❌ |
| VisualDeltaHandler | `ToolCompletedEvent.output` | ❌ | ❌ | ❌ |
| SeatMonitorHandler | `ToolStartedEvent` | ❌ | ❌ | ✅ 设置 externallyModified |
| NotificationHandler | terminal event（触发） | ✅ totalCostUsd, durationMs | ❌ | ❌ |
| TraceEventHandler | all AgentEvent | ❌ | ❌ | ❌ |
| MemoryProcessingHandler | terminal event（触发） | ✅ toolPairs | ❌ | ✅ externallyModified, takeoverEvent |
| ReviewHandler | terminal event（触发） | ❌ | ✅ collectedMessages | ❌ |

---

### Story 25.1: EventHandler Protocol 与注册机制

As a Axion 开发者,
I want 定义 EventHandler protocol 和注册/生命周期管理,
So that handler 可以独立开发、组合注册、统一管理.

**实施：**

1. 在 `Sources/AxionCore/Runtime/` 创建 `EventHandler.swift`

```swift
/// 事件处理器协议。每个 handler 订阅特定类型的 AgentEvent。
///
/// **实现要求：所有 handler 必须实现为 actor。**
/// AxionRuntime 在独立 Task 中分发事件，多个事件可能并发到达。
/// actor isolation 保证 handler 的可变状态线程安全。
public protocol EventHandler: Actor {
    /// handler 的唯一标识，用于日志和调试。
    var identifier: String { get }

    /// handler 订阅的事件类型列表。
    /// 空数组表示订阅所有事件（用于 trace handler 等）。
    var subscribedEventTypes: [any AgentEvent.Type] { get }

    /// 收到事件后的处理逻辑。
    /// - Parameters:
    ///   - event: 触发的 AgentEvent
    ///   - context: 包含 sessionId、config、axionState、runCompleteContext、sessionStore
    func handle(_ event: any AgentEvent, context: EventHandlerContext) async
}

/// handler 执行时的上下文信息。
public struct EventHandlerContext: Sendable {
    public let sessionId: String?
    public let config: AxionConfig
    /// Axion 特有运行时状态（externallyModified、takeoverEvent）
    public let axionState: AxionRunState
    /// SDK 聚合数据。仅在 terminal event（AgentCompleted/Failed/Interrupted）时非 nil。
    /// 由 AxionRuntime 从 onRunComplete 回调捕获。
    /// 包含 toolPairs、usage、totalCostUsd、durationMs、numTurns、costBreakdown。
    public let runCompleteContext: RunCompleteContext?
    /// SDK SessionStore。handler 可用于加载完整对话历史。
    public let sessionStore: SessionStore
}
```

> **为什么 EventHandler 继承 Actor 而非 Sendable：**
> AxionRuntime 的 `dispatchToHandlers()` 在独立 Task 中执行，多个事件可能并发到达同一个 handler。
> 继承 Actor 强制所有实现使用 actor isolation，保证可变状态线程安全。
> 例如 CostEventHandler 的累积计数器、VisualDeltaHandler 的 checked/skipped 计数等。

2. 在 `AxionRuntime` 中添加 handler 注册和分发：

```swift
public actor AxionRuntime {
    private var handlers: [any EventHandler] = []

    public func registerHandler(_ handler: any EventHandler) {
        handlers.append(handler)
    }

    /// 内部方法：AgentEvent 到达时分发给匹配的 handler
    private func dispatchToHandlers(_ event: any AgentEvent, runCompleteContext: RunCompleteContext?) async {
        let context = EventHandlerContext(
            sessionId: currentSessionId,
            config: currentConfig,
            axionState: axionState,
            runCompleteContext: runCompleteContext,
            sessionStore: sessionStore
        )
        for handler in handlers {
            if shouldDispatch(event: event, to: handler) {
                await handler.handle(event, context: context)
            }
        }
    }

    private func shouldDispatch(event: any AgentEvent, to handler: any EventHandler) -> Bool {
        let types = handler.subscribedEventTypes
        if types.isEmpty { return true }  // 空数组 = 订阅所有
        return types.contains { type(of: event) == $0 }
    }
}
```

3. 分发机制：
   - AxionRuntime 订阅 EventBus，每个事件分发给匹配的 handler
   - 分发在独立 Task 中执行（不阻塞 agent stream loop）
   - **串行分发**：同一 handler 的事件串行执行（actor isolation 保证），不同 handler 之间并行执行
   - **错误隔离**：单个 handler 的异常不传播到其他 handler 或 agent 执行。用 `do/catch` 包裹每个 handler 的 `handle()` 调用，异常记录日志后继续
   - **cancel 传播**：AxionRuntime 的 cancel 会取消分发 Task，但不影响 agent 执行

**Handler 生命周期：**
- Handler 注册在 AxionRuntime 上，**不是 per-session**
- Daemon 模式下，handler 在多个 session 间复用
- **Handler 负责在 terminal event 时重置自己的累积状态**（CostEventHandler 在 AgentCompletedEvent 时输出汇总后重置计数器）

**Acceptance Criteria：**

**Given** 注册了一个订阅 `ToolCompletedEvent` 的 handler
**When** EventBus 收到 `ToolCompletedEvent`
**Then** handler 的 `handle()` 被调用

**Given** 注册了一个订阅 `ToolCompletedEvent` 的 handler
**When** EventBus 收到 `AgentStartedEvent`
**Then** handler 的 `handle()` 不被调用

**Given** 注册了 3 个 handler
**When** EventBus 收到一个事件
**Then** 所有匹配的 handler 都收到事件

**Given** 一个 handler 在 `handle()` 中抛出异常
**When** EventBus 收到事件
**Then** 其他 handler 仍然正常执行，异常被记录到日志

---

### Story 25.2: CostEventHandler

As a Axion 开发者,
I want 追踪每次 LLM 调用的 token 和成本,
So that run 结束时可以汇总成本数据.

**数据来源：RunCompleteContext（terminal event 时由 AxionRuntime 从 onRunComplete 捕获）**

**实施：**

1. 在 `Sources/AxionCLI/Runtime/Handlers/` 创建 `CostEventHandler.swift`
2. 订阅 terminal events（`AgentCompletedEvent` / `AgentFailedEvent` / `AgentInterruptedEvent`）
3. 从 `context.runCompleteContext` 读取 `totalCostUsd`、`usage`、`costBreakdown`
4. 不需要自行累积 `LLMCostEvent`（SDK 已在 `onRunComplete` 中聚合）

```swift
actor CostEventHandler: EventHandler {
    let identifier = "cost"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        AgentCompletedEvent.self, AgentFailedEvent.self, AgentInterruptedEvent.self
    ]

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        // runCompleteContext 在 terminal event 时由 AxionRuntime 保证可用
        guard let runCtx = context.runCompleteContext else { return }

        let totalTokens = runCtx.usage.inputTokens + runCtx.usage.outputTokens
        fputs("[axion] LLM 调用: \(runCtx.numTurns)轮, Tokens: \(totalTokens), 预估成本: $\(String(format: "%.2f", runCtx.totalCostUsd))\n", stderr)
    }
}
```

**为什么不用 LLMCostEvent 累积：**
- SDK 的 `RunCompleteContext` 已在 `onRunComplete` 中聚合了 `totalCostUsd`、`usage`、`costBreakdown`
- 自行累积需要处理线程安全（可变状态）、daemon 多 session 并发时状态混淆
- 直接用 RunCompleteContext 零状态、零线程风险

**从 RunOrchestrator 迁移的代码：**
- RunOrchestrator ~232-238 行的 cost 汇总输出

**Acceptance Criteria：**

**Given** CostEventHandler 注册到 AxionRuntime
**When** agent 执行完成
**Then** handler 从 `runCompleteContext` 读取总成本并输出汇总（格式与当前一致）

**Given** agent 执行完成（含 3 次 tool 调用）
**When** handler 收到 `AgentCompletedEvent`
**Then** 输出包含正确的 totalTokens、totalCostUsd

**Given** daemon 模式下两个 session 并发执行
**When** 各自完成
**Then** 两个 session 的成本数据互不干扰（handler 无状态）

---

### Story 25.3: VisualDeltaHandler

As a Axion 开发者,
I want 在 screenshot tool 完成时检查视觉变化,
So that 可以自动跳过无变化的验证截图.

**数据来源：纯 AgentEvent（从 `ToolCompletedEvent.output` 获取 screenshot base64）**

**实施：**

1. 在 `Sources/AxionCLI/Runtime/Handlers/` 创建 `VisualDeltaHandler.swift`
2. 订阅 `ToolCompletedEvent`（过滤 toolName 包含 "screenshot" 的）
3. 从 `event.output` 提取 base64 数据
4. 复用现有 `VisualDeltaTracker` actor

```swift
actor VisualDeltaHandler: EventHandler {
    let identifier = "visual-delta"
    let subscribedEventTypes: [any AgentEvent.Type] = [ToolCompletedEvent.self]

    private let tracker: VisualDeltaTracker?
    private var checked = 0
    private var skipped = 0

    init(noVisualDelta: Bool) {
        self.tracker = noVisualDelta ? nil : VisualDeltaTracker()
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard let e = event as? ToolCompletedEvent,
              e.toolName.contains("screenshot"),
              !e.isError,
              let tracker,
              let base64 = e.output else { return }

        let result = await tracker.processScreenshot(base64: base64)
        checked += 1
        if result.shouldSkipVerifier { skipped += 1 }
    }
}
```

**从 RunOrchestrator 迁移的代码：**
- `visualDeltaTracker` 变量（~104 行）
- stream loop 中的 visual delta 检查逻辑（~162-171 行）
- run 结束时的 visual delta 汇总输出（~228-230 行）

**关键改进**：之前需要从 `SDKMessage.toolResult.content` 手动解析 base64，现在 `ToolCompletedEvent.output` 直接提供。

**Acceptance Criteria：**

**Given** VisualDeltaHandler 注册且 config.noVisualDelta == false
**When** screenshot tool 完成执行
**Then** handler 从 `ToolCompletedEvent.output` 获取 base64，执行视觉增量检查

**Given** config.noVisualDelta == true
**When** handler 被创建
**Then** handler 的 tracker 为 nil，不执行任何检查逻辑

---

### Story 25.4: SeatMonitorHandler

As a Axion 开发者,
I want 在 helper tool 执行时监控用户座位活动,
So that 可以检测是否有人在电脑前操作.

**数据来源：纯 AgentEvent + AxionRunState（设置 externallyModified）**

**实施：**

1. 在 `Sources/AxionCLI/Runtime/Handlers/` 创建 `SeatMonitorHandler.swift`
2. 订阅 `ToolStartedEvent`（过滤 toolName 以 `mcp__axion-helper__` 开头的）
3. 复用现有 `SeatActivityMonitor` actor
4. 懒初始化 monitor（第一个 helper tool 调用时创建）
5. 检测到外部操作时设置 `context.axionState.externallyModified = true`

```swift
actor SeatMonitorHandler: EventHandler {
    let identifier = "seat-monitor"
    let subscribedEventTypes: [any AgentEvent.Type] = [ToolStartedEvent.self]

    private let enabled: Bool
    private var monitor: SeatActivityMonitor?

    init(sharedSeatMode: Bool) {
        self.enabled = sharedSeatMode
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard enabled,
              let e = event as? ToolStartedEvent,
              e.toolName.hasPrefix("mcp__axion-helper__") else { return }

        if monitor == nil {
            monitor = await SeatActivityMonitor.create()
        }
        guard let monitor else { return }

        let isActive = await monitor.check()
        if isActive {
            await context.axionState.setExternallyModified()
        }
    }
}
```

**从 RunOrchestrator 迁移的代码：**
- `seatMonitor` 变量（~107 行）
- stream loop 中的 seat monitor 创建和检查逻辑（~133-135 行、~213-216 行）

**Acceptance Criteria：**

**Given** SeatMonitorHandler 注册且 config.sharedSeatMode == true
**When** helper tool 开始执行（toolName 以 `mcp__axion-helper__` 开头）
**Then** handler 检查座位活动状态

**Given** 检测到用户活动
**When** handler 执行检查
**Then** `axionState.externallyModified` 被设为 true

**Given** config.sharedSeatMode == false
**When** handler 被创建
**Then** handler 不执行任何监控逻辑

---

### Story 25.5: MemoryProcessingHandler

As a Axion 开发者,
I want 在 agent 完成后处理 run 的记忆数据,
So that 记忆系统可以跨 run 积累知识.

**数据来源：AgentEvent（触发）+ RunCompleteContext（toolPairs）+ AxionRunState（externallyModified, takeoverEvent）**

**实施：**

1. 在 `Sources/AxionCLI/Runtime/Handlers/` 创建 `MemoryProcessingHandler.swift`
2. 订阅 terminal events（`AgentCompletedEvent` / `AgentFailedEvent` / `AgentInterruptedEvent`）作为触发器
3. 从 `context.runCompleteContext` 获取 `toolPairs`（**不从 RunState 自建**）
4. 从 `context.axionState` 获取 `externallyModified` 和 `takeoverEvent`
5. 调用现有 `RunMemoryProcessor.processRunResult()` — 参数映射：

```swift
actor MemoryProcessingHandler: EventHandler {
    let identifier = "memory-processing"
    let subscribedEventTypes: [any AgentEvent.Type] = [AgentCompletedEvent.self, AgentFailedEvent.self, AgentInterruptedEvent.self]

    private let memoryStore: FileBasedMemoryStore
    private let memoryDir: String

    init(memoryStore: FileBasedMemoryStore, memoryDir: String) {
        self.memoryStore = memoryStore
        self.memoryDir = memoryDir
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard context.config.noMemory == false else { return }
        guard let runCtx = context.runCompleteContext else {
            // runCompleteContext 在 terminal event 时应该已可用
            return
        }

        let takeover = await context.axionState.takeoverEvent
        let externallyModified = await context.axionState.externallyModified

        await RunMemoryProcessor.processRunResult(
            toolPairs: runCtx.toolPairs,           // ← 来自 onRunComplete，不是自建
            task: context.config.task,
            runId: context.sessionId ?? "",
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            noMemory: false,
            externallyModified: externallyModified, // ← 来自 AxionRunState
            takeoverEvent: takeover.map {           // ← 来自 AxionRunState
                RunMemoryProcessor.TakeoverEventContext(
                    issue: $0.issue,
                    summary: $0.summary,
                    feedback: $0.feedback,
                    reason: $0.reason,
                    duration: $0.duration
                )
            },
            runSucceeded: runCtx.status == .success,
            runCompleted: true
        )
    }
}
```

**为什么不需要 RunState 的 collectedMessages：**
- `RunMemoryProcessor.processRunResult()` 的参数是 `toolPairs`（不是 messages）
- `toolPairs` 直接来自 `RunCompleteContext.toolPairs`，不需要从 SDKMessage 自建

**从 RunOrchestrator 迁移的代码：**
- `RunMemoryProcessor.preRunCleanup()` 调用（~83 行）→ 移到 AxionRuntime 的 createSession
- `RunMemoryProcessor.processRunResult()` 调用（~252-263 行）
- takeover event context 构建（~243-250 行）→ 由 AxionRunState 维护

**Acceptance Criteria：**

**Given** MemoryProcessingHandler 注册且 config.noMemory == false
**When** agent 完成执行
**Then** handler 从 `runCompleteContext.toolPairs` 获取 toolPairs，调用 processRunResult

**Given** config.noMemory == true
**When** handler 收到 terminal event
**Then** handler 跳过所有 memory processing

**Given** externallyModified == true
**When** handler 收到 terminal event
**Then** handler 跳过 memory processing（外部操作不记录经验）

---

### Story 25.6: ReviewHandler + NotificationHandler

As a Axion 开发者,
I want 在 agent 完成后触发代码审查和桌面通知,
So that 可以自动 review 代码变更并通知用户.

**ReviewHandler 数据来源：AgentEvent（触发）+ Agent 引用（注入）+ SessionStore.load()（messages）**

**NotificationHandler 数据来源：AgentEvent（触发）+ RunCompleteContext（totalCostUsd, durationMs）**

**实施：**

1. **ReviewHandler**（`Sources/AxionCLI/Runtime/Handlers/ReviewHandler.swift`）
   - 订阅 `AgentCompletedEvent` 作为触发器
   - 条件：`!dryrun && !noMemory && !noReview`
   - **Agent 引用**：通过 `EventHandlerContext` 传递（AxionRuntime 在构建 agent 后将引用放入 context）
   - **collectedMessages**：从 `context.sessionStore.load(sessionId:)` 获取（**不从 RunState 获取**，不在内存中维护）
   - 复用现有 `ReviewOrchestrator.executeReview(parentAgent:messages:config:)` 逻辑

```swift
actor ReviewHandler: EventHandler {
    let identifier = "review"
    let subscribedEventTypes: [any AgentEvent.Type] = [AgentCompletedEvent.self]

    private let reviewOrchestrator: ReviewOrchestrator?

    init(reviewOrchestrator: ReviewOrchestrator?) {
        self.reviewOrchestrator = reviewOrchestrator
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard let orchestrator = reviewOrchestrator,
              !context.config.dryrun,
              !context.config.noMemory,
              !context.config.noReview,
              case _ = event as AgentCompletedEvent else { return }

        // 从 SessionStore 加载完整对话历史（agent 已完成，数据已持久化）
        guard let sessionData = try? context.sessionStore.load(sessionId: context.sessionId ?? "") else {
            return
        }

        // 转换 [[String: Any]] → [SDKMessage]
        // SDK 的 SessionData.messages 是 [[String: Any]]（JSON 反序列化的原始格式）
        // Axion 提供 MessageConverter 工具方法完成转换
        let messages = MessageConverter.fromDictionaries(sessionData.messages)

        let reviewConfig = ReviewAgentConfig()
        let (doMemory, doSkill) = orchestrator.shouldReview(
            sessionId: context.sessionId ?? "",
            messageCount: messages.count,
            config: reviewConfig
        )

        if doMemory || doSkill {
            let tunedConfig = ReviewAgentConfig(reviewMemory: doMemory, reviewSkills: doSkill)
            let result = await orchestrator.executeReview(
                parentAgent: context.parentAgent,
                messages: messages,
                config: tunedConfig
            )
            // ... 处理 review 结果（日志、trace、usageStore 更新）
        }
    }
}
```

**消息转换工具（`Sources/AxionCore/Utils/MessageConverter.swift`）：**

SDK 的 `SessionData.messages` 是 `[[String: Any]]`（JSON 原始字典）。Axion 需要将其转换为 `[SDKMessage]`。

```swift
/// 将 SessionStore 的原始消息字典转换为 SDKMessage 数组。
/// SDK 的 SessionData.messages 是 JSON 反序列化的 [[String: Any]]，
/// 此工具方法通过 JSONEncoder → JSONDecoder 桥接完成类型安全转换。
enum MessageConverter {
    static func fromDictionaries(_ dicts: [[String: Any]]) -> [SDKMessage] {
        dicts.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? JSONDecoder().decode(SDKMessage.self, from: data)
        }
    }
}
```

**ReviewHandler 的 Agent 引用方案：**

ReviewHandler 不再使用 `setParentAgent()`。改为在 `EventHandlerContext` 中增加 `parentAgent` 字段：

```swift
public struct EventHandlerContext: Sendable {
    // ... 原有字段 ...
    /// 父 agent 引用。AxionRuntime 在构建 agent 后设置。
    /// 用于 ReviewHandler 创建 sub-agent。
    public let parentAgent: Agent?
}
```

AxionRuntime 在 `start()` 内部构建 agent 后，将 agent 引用存入状态，分发事件时通过 context 传递。
Handler 不持有可变的 agent 引用，避免时序依赖和线程安全问题。

2. **NotificationHandler**（`Sources/AxionCLI/Runtime/Handlers/NotificationHandler.swift`）
   - 订阅 terminal events（`AgentCompletedEvent` / `AgentFailedEvent` / `AgentInterruptedEvent`）
   - 从事件本身获取 status
   - 从 `context.runCompleteContext` 获取 cost 汇总（`totalCostUsd`、`durationMs`）
   - 复用 `sendDesktopNotification()` 和 `activateTerminal()` 逻辑

```swift
actor NotificationHandler: EventHandler {
    let identifier = "notification"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        AgentCompletedEvent.self, AgentFailedEvent.self, AgentInterruptedEvent.self
    ]

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        let status: String
        let steps: Int
        let durationMs: Int

        switch event {
        case let e as AgentCompletedEvent:
            status = "completed"
            steps = e.totalSteps
            durationMs = e.durationMs
        case let e as AgentFailedEvent:
            status = "failed"
            steps = e.stepsCompleted
            durationMs = 0
        case let e as AgentInterruptedEvent:
            status = "interrupted"
            steps = e.stepsCompleted
            durationMs = 0
        default:
            return
        }

        let costStr = context.runCompleteContext.map {
            String(format: "$%.2f", $0.totalCostUsd)
        } ?? "N/A"

        sendDesktopNotification(
            title: "Axion \(status)",
            body: "Steps: \(steps), Duration: \(durationMs / 1000)s, Cost: \(costStr)"
        )
    }
}
```

**成本数据来源**：直接从 `context.runCompleteContext.totalCostUsd` 获取，不自行累积。

**从 RunOrchestrator 迁移的代码：**
- Review + Curator 逻辑（~266-357 行）
- Desktop notification 发送（~364-377 行）
- Terminal 激活（~375 行）

**Acceptance Criteria：**

**Given** ReviewHandler 注册且条件满足
**When** agent 完成执行
**Then** handler 从 `sessionStore.load()` 获取 collectedMessages，触发 review + curator 流程

**Given** NotificationHandler 注册
**When** agent 完成执行
**Then** handler 发送桌面通知（含状态、耗时、成本摘要）

**Given** SessionStore 尚未完成持久化（极端时序）
**When** ReviewHandler 尝试加载 messages
**Then** handler 优雅处理（日志记录，不 crash）

---

### Story 25.7: TraceEventHandler

As a Axion 开发者,
I want 记录所有 runtime 事件到 trace 系统,
So that 可以追踪和调试 agent 执行过程.

**数据来源：纯 AgentEvent（不需要 RunState/RunCompleteContext）**

**实施：**

1. 在 `Sources/AxionCLI/Runtime/Handlers/` 创建 `TraceEventHandler.swift`
2. 订阅所有事件（`subscribedEventTypes = []`）
3. 将 AgentEvent 映射为 trace record，复用现有 `TraceRecorder`

```swift
actor TraceEventHandler: EventHandler {
    let identifier = "trace"
    let subscribedEventTypes: [any AgentEvent.Type] = []  // 空数组 = 订阅所有

    private let traceRecorder: TraceRecorder?

    init(traceDir: String?) {
        self.traceRecorder = traceDir.map { TraceRecorder(traceDir: $0) }
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard let recorder = traceRecorder else { return }

        // 每种 AgentEvent 映射为对应的 TraceRecord
        let record = mapToTraceRecord(event, sessionId: context.sessionId)
        recorder.append(record)
    }

    private func mapToTraceRecord(_ event: any AgentEvent, sessionId: String?) -> TraceRecord {
        let base = TraceRecord(
            timestamp: event.timestamp,
            sessionId: sessionId,
            eventType: String(describing: type(of: event))
        )

        switch event {
        case let e as AgentStartedEvent:
            return base.withDetail("agent_started", data: ["task": e.task])
        case let e as AgentCompletedEvent:
            return base.withDetail("agent_completed", data: [
                "totalSteps": e.totalSteps,
                "durationMs": e.durationMs
            ])
        case let e as ToolStartedEvent:
            return base.withDetail("tool_started", data: ["toolName": e.toolName])
        case let e as ToolCompletedEvent:
            return base.withDetail("tool_completed", data: [
                "toolName": e.toolName,
                "durationMs": e.durationMs,
                "isError": e.isError
            ])
        case let e as LLMCostEvent:
            return base.withDetail("llm_cost", data: [
                "model": e.model,
                "inputTokens": e.inputTokens,
                "outputTokens": e.outputTokens,
                "estimatedCostUsd": e.estimatedCostUsd
            ])
        case is AgentFailedEvent, is AgentInterruptedEvent, is SessionCreatedEvent,
             is SessionClosedEvent, is ToolFailedEvent, is LLMRequestStartedEvent,
             is LLMResponseReceivedEvent:
            // 其他事件类型只记录基本信息
            return base
        default:
            return base
        }
    }
}
```

**AgentEvent → TraceRecord 映射规则：**

| AgentEvent | trace record type | 记录的关键数据 |
|------------|------------------|--------------|
| `AgentStartedEvent` | agent_started | task |
| `AgentCompletedEvent` | agent_completed | totalSteps, durationMs |
| `AgentFailedEvent` | agent_failed | error, stepsCompleted |
| `AgentInterruptedEvent` | agent_interrupted | stepsCompleted |
| `ToolStartedEvent` | tool_started | toolName, toolUseId |
| `ToolCompletedEvent` | tool_completed | toolName, durationMs, isError |
| `ToolFailedEvent` | tool_failed | toolName, error |
| `LLMCostEvent` | llm_cost | model, inputTokens, outputTokens, estimatedCostUsd |
| `LLMRequestStartedEvent` | llm_request_started | model |
| `LLMResponseReceivedEvent` | llm_response_received | model, durationMs |
| `SessionCreatedEvent` | session_created | sessionId |
| `SessionClosedEvent` | session_closed | finalStatus |

**Acceptance Criteria：**

**Given** TraceEventHandler 注册且 traceDir 已配置
**When** 任何 AgentEvent 被 emit
**Then** handler 记录到 trace 系统，包含事件类型和关键数据

**Given** agent 完成一次执行（3 个 tool 调用）
**When** 检查 trace 文件
**Then** 包含 agent_started → 3 组 tool_started/tool_completed → agent_completed 的完整序列

---

## Story 间的依赖关系

```
25.1 EventHandler Protocol + 注册机制 (P0)
  │
  ├──► 25.2 CostEventHandler (P0) — RunCompleteContext
  ├──► 25.3 VisualDeltaHandler (P0) — AgentEvent (ToolCompletedEvent.output)
  ├──► 25.4 SeatMonitorHandler (P0) — AgentEvent + AxionRunState
  ├──► 25.5 MemoryProcessingHandler (P0) — RunCompleteContext + AxionRunState
  ├──► 25.6 ReviewHandler + NotificationHandler (P1) — Review: SessionStore + Agent 引用, Notification: RunCompleteContext
  └──► 25.7 TraceEventHandler (P1) — 纯 AgentEvent
```

25.1 必须最先。25.2-25.7 可并行但建议按优先级顺序。

---

## 实现优先级

| Story | 优先级 | 数据来源 | 理由 |
|-------|--------|---------|------|
| 25.1 EventHandler Protocol | P0 | — | 所有 handler 的基础 |
| 25.2 CostEventHandler | P0 | RunCompleteContext | 核心功能，零状态，直接从 runCompleteContext 获取 |
| 25.3 VisualDeltaHandler | P0 | 纯 AgentEvent (output) | 桌面自动化的核心功能 |
| 25.4 SeatMonitorHandler | P0 | AgentEvent + AxionRunState | 多人场景的必要功能 |
| 25.5 MemoryProcessingHandler | P0 | RunCompleteContext + AxionRunState | 自进化系统的基础 |
| 25.6 ReviewHandler + NotificationHandler | P1 | SessionStore + Agent 引用 | 增强功能 |
| 25.7 TraceEventHandler | P1 | 纯 AgentEvent | 调试增强 |

---

## 关键设计约束

- **每个 handler 独立** — 不依赖其他 handler 的状态
- **handler 不阻塞 agent 执行** — `handle()` 在独立 Task 中执行
- **错误隔离** — 单个 handler 异常不影响其他 handler 和 agent 执行
- **可组合** — CLI 注册全套 handler，API 只注册部分（如 cost + trace）
- **渐进式迁移** — 先让 handler 和 RunOrchestrator 并行运行，验证一致后再移除旧代码
- **不改 SDK** — handler 只消费 SDK 的 AgentEvent + RunCompleteContext，不修改 SDK
- **Handler 无状态优先** — 优先从 RunCompleteContext / SessionStore 获取数据，避免自行累积状态
- **不从 SDKMessage 自建数据** — toolPairs 用 RunCompleteContext，messages 用 SessionStore.load() + MessageConverter
- **所有 handler 是 actor** — actor isolation 保证可变状态线程安全（daemon 多 session 并发）

## RunOrchestrator 横切关注点到 Handler 的映射

| 现有代码位置（行号参考） | 提取为 | 数据来源 |
|----------------------|--------|---------|
| `RunOrchestrator` ~232-238 cost 汇总 | CostEventHandler | `RunCompleteContext` |
| `RunOrchestrator` ~98-170 visualDeltaTracker | VisualDeltaHandler | `ToolCompletedEvent.output` |
| `RunOrchestrator` ~107-213 seatMonitor | SeatMonitorHandler | `ToolStartedEvent` + `AxionRunState` |
| `RunOrchestrator` ~243-263 RunMemoryProcessor | MemoryProcessingHandler | `RunCompleteContext.toolPairs` + `AxionRunState` |
| `RunOrchestrator` ~266-357 reviewOrchestrator + curator | ReviewHandler | `SessionStore.load()` + Agent 引用 |
| `RunOrchestrator` ~364-377 sendDesktopNotification | NotificationHandler | AgentEvent + RunCompleteContext |
| TraceRecorder 调用 | TraceEventHandler | 纯 AgentEvent |

## 文件位置

| 文件 | 目录 |
|------|------|
| EventHandler.swift | `Sources/AxionCore/Runtime/EventHandler.swift` |
| CostEventHandler.swift | `Sources/AxionCLI/Runtime/Handlers/CostEventHandler.swift` |
| VisualDeltaHandler.swift | `Sources/AxionCLI/Runtime/Handlers/VisualDeltaHandler.swift` |
| SeatMonitorHandler.swift | `Sources/AxionCLI/Runtime/Handlers/SeatMonitorHandler.swift` |
| MemoryProcessingHandler.swift | `Sources/AxionCLI/Runtime/Handlers/MemoryProcessingHandler.swift` |
| ReviewHandler.swift | `Sources/AxionCLI/Runtime/Handlers/ReviewHandler.swift` |
| NotificationHandler.swift | `Sources/AxionCLI/Runtime/Handlers/NotificationHandler.swift` |
| TraceEventHandler.swift | `Sources/AxionCLI/Runtime/Handlers/TraceEventHandler.swift` |

## 测试策略

- **纯 EventBus handler 测试**：不需要 LLM。构造 AgentEvent，验证 handler 的 handle() 行为。
- **RunCompleteContext 依赖 handler 测试**：构造预填充的 RunCompleteContext，验证 handler 获取正确数据。
- **SessionStore 依赖 handler 测试**：使用内存 SessionStore（自定义 sessionsDir 临时目录），验证 handler 加载正确 messages。
- **每个 handler 独立测试**：不需要集成到 AxionRuntime。
