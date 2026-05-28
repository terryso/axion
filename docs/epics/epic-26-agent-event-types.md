# Runtime Event Layer — Epic 26: AgentEvent Protocol 与 EventBus

> **状态：已完成（Epic 26 全部 6 个 Story 已交付）**
> **优先级：P0**
> **依赖：** 无（新增类型，不依赖现有 Epic）
> **Roadmap：** `docs/runtime-event-layer-roadmap.md` → S1 + S2

## 背景与动机

SDK 当前只有 `SDKMessage` 作为 agent 输出模型（assistant、toolUse、toolResult、result、system）。这是 LLM 消息级的抽象。

上层（Axion）需要的是 **Runtime 级别** 的事件：session lifecycle、agent lifecycle、tool lifecycle、LLM cost、memory changes。目前 Axion 被迫在 `for await message in agent.stream()` 的 switch-case 里手动提取这些信息（RunOrchestrator ~350 行横切逻辑）。

本 Epic 在 SDK 中引入：
1. `AgentEvent` protocol + 具体事件类型（统一 event 模型）
2. `EventBus` actor（进程内 event bus，多 subscriber 支持）

**不改 `SDKMessage`，不改 `Agent.stream()` 返回类型。** 这是纯新增。

---

### Story 26.1: AgentEvent Protocol 与 Base Event 类型

As a SDK 开发者,
I want 定义统一的 AgentEvent protocol 和事件分类,
So that 所有 runtime 事件有统一的类型约束和命名规范.

**实施：**
- 创建 `Sources/OpenAgentSDK/Types/AgentEventTypes.swift`
- 定义 `AgentEvent` protocol：`id: String`、`timestamp: Date`
- 定义事件分类枚举 `AgentEventCategory`：session / agent / tool / llm / memory / subAgent
- 定义 `BaseAgentEvent` struct 提供 `id`（UUID）和 `timestamp`（Date.now）的默认实现

**Acceptance Criteria:**

**Given** `AgentEvent` protocol 被定义
**When** 一个 struct 遵循 `AgentEvent`
**Then** 必须提供 `id: String` 和 `timestamp: Date`

**Given** `BaseAgentEvent` 被创建
**When** 检查其属性
**Then** `id` 是自动生成的 UUID
**And** `timestamp` 是初始化时的 `Date()`

---

### Story 26.2: Session Lifecycle Events

As a SDK 开发者,
I want 定义 session 生命周期事件,
So that 上层可以监听 session 创建、恢复、关闭等状态变化.

**实施：**
- 在 `AgentEventTypes.swift` 中定义：
  - `SessionCreatedEvent`：`sessionId`、`task`、`model`
  - `SessionRestoredEvent`：`sessionId`、`messageCount`、`originalCreatedAt`
  - `SessionClosedEvent`：`sessionId`、`finalStatus`（completed/failed/interrupted）
  - `SessionAutoSavedEvent`：`sessionId`、`messageCount`

**Acceptance Criteria:**

**Given** `SessionCreatedEvent` 被构造
**When** 检查其 payload
**Then** 包含 `sessionId`、`task`、`model`

**Given** `SessionClosedEvent` 被构造
**When** 检查其 `finalStatus`
**Then** 值为 `completed`、`failed` 或 `interrupted` 之一

---

### Story 26.3: Agent Lifecycle Events

As a SDK 开发者,
I want 定义 agent 生命周期事件,
So that 上层可以追踪 agent 启动、完成、中断、恢复.

**实施：**
- 在 `AgentEventTypes.swift` 中定义：
  - `AgentStartedEvent`：`sessionId`、`task`
  - `AgentCompletedEvent`：`sessionId`、`totalSteps`、`durationMs`、`resultText`
  - `AgentFailedEvent`：`sessionId`、`error`、`stepsCompleted`
  - `AgentInterruptedEvent`：`sessionId`、`stepsCompleted`
  - `AgentResumedEvent`：`sessionId`、`resumeContext`

**Acceptance Criteria:**

**Given** `AgentCompletedEvent` 被构造
**When** 检查其 payload
**Then** 包含 `sessionId`、`totalSteps`、`durationMs`

**Given** `AgentFailedEvent` 被构造
**When** 检查其 payload
**Then** 包含 `error: String` 和 `stepsCompleted: Int`

---

### Story 26.4: Tool Lifecycle Events

As a SDK 开发者,
I want 定义 tool 执行生命周期事件,
So that 上层可以追踪每个 tool 调用的开始、输出、完成、失败.

**实施：**
- 在 `AgentEventTypes.swift` 中定义：
  - `ToolStartedEvent`：`sessionId`、`toolName`、`toolUseId`、`input`（可选，可能敏感）
  - `ToolStreamingEvent`：`sessionId`、`toolUseId`、`chunk`
  - `ToolCompletedEvent`：`sessionId`、`toolUseId`、`toolName`、`durationMs`、`isError`
  - `ToolFailedEvent`：`sessionId`、`toolUseId`、`toolName`、`error`

**Acceptance Criteria:**

**Given** `ToolStartedEvent` 被构造
**When** 检查其 payload
**Then** 包含 `toolName`、`toolUseId`

**Given** `ToolCompletedEvent` 被构造
**When** `isError == true`
**Then** 这是一个失败完成，上层可据此区分成功和失败的 tool 调用

---

### Story 26.5: LLM Cost Events

As a SDK 开发者,
I want 定义 LLM 调用成本事件,
So that 上层可以实时追踪 token 消耗和成本.

**实施：**
- 在 `AgentEventTypes.swift` 中定义：
  - `LLMRequestStartedEvent`：`sessionId`、`model`
  - `LLMResponseReceivedEvent`：`sessionId`、`model`、`durationMs`
  - `LLMCostEvent`：`sessionId`、`model`、`inputTokens`、`outputTokens`、`cacheCreationInputTokens`、`cacheReadInputTokens`、`estimatedCostUsd`

**Acceptance Criteria:**

**Given** `LLMCostEvent` 被构造
**When** 检查其 payload
**Then** 包含 `inputTokens`、`outputTokens`、`estimatedCostUsd`
**And** token 数为非负整数

---

### Story 26.6: EventBus — 进程内 Event Bus

As a SDK 开发者,
I want 一个进程内的 EventBus actor 支持多 subscriber,
So that 多个 consumer（CLI output、SSE push、trace、TUI）可以同时消费同一个 event stream.

**实施：**
- 创建 `Sources/OpenAgentSDK/Core/EventBus.swift`
- `EventBus` actor：
  - `publish(_ event: any AgentEvent)` — 广播 event 到所有 subscriber
  - `subscribe() -> AsyncStream<any AgentEvent>` — 订阅所有 event
  - `subscribe<T: AgentEvent>(_ type: T.Type) -> AsyncStream<T>` — 类型过滤订阅
  - `unsubscribe(_ id: UUID)` — 取消订阅
- 内部用 `[UUID: AsyncStream<any AgentEvent>.Continuation]` 管理 subscriber
- Buffer 策略：`AsyncStream.init(bufferingPolicy: .bufferingNewest(100))`，避免慢 consumer 阻塞
- 当 subscriber 的 buffer 满时，丢弃最老的 event（不阻塞 publisher）

**Acceptance Criteria:**

**Given** EventBus 有 3 个 subscriber
**When** publish 一个 `AgentStartedEvent`
**Then** 3 个 subscriber 都收到这个 event

**Given** EventBus 有 1 个慢 subscriber（不消费）
**When** 连续 publish 200 个 event
**Then** 慢 subscriber 的 buffer 只保留最新 100 个，publish 不被阻塞

**Given** subscriber 调用 `subscribe(ToolStartedEvent.self)`
**When** publish 一个 `AgentStartedEvent` 再 publish 一个 `ToolStartedEvent`
**Then** subscriber 只收到 `ToolStartedEvent`

**Given** subscriber 取消订阅
**When** publish 一个 event
**Then** 该 subscriber 不再收到 event，无内存泄漏

**Given** EventBus 的 subscriber 全部取消
**When** publish 一个 event
**Then** 不报错，event 被丢弃

---

## Story 间的依赖关系

```
26.1 AgentEvent Protocol (P0) — 基础类型
  │
  ├──► 26.2 Session Events (P0)
  ├──► 26.3 Agent Events (P0)
  ├──► 26.4 Tool Events (P0)
  ├──► 26.5 LLM Cost Events (P0)
  │
  └──► 26.6 EventBus (P0) — 依赖 26.1 的 AgentEvent protocol
```

26.1 必须最先完成。26.2-26.5 可并行。26.6 依赖 26.1 但不依赖具体 event 类型。

---

## 实现优先级

| Story | 优先级 | 理由 |
|-------|--------|------|
| 26.1 AgentEvent Protocol | P0 | 所有后续依赖 |
| 26.2 Session Events | P0 | session lifecycle 是 runtime 的核心 |
| 26.3 Agent Events | P0 | agent lifecycle 是 runtime 的核心 |
| 26.4 Tool Events | P0 | tool lifecycle 是 observability 的基础 |
| 26.5 LLM Cost Events | P0 | cost tracking 需要独立事件 |
| 26.6 EventBus | P0 | 事件分发基础设施 |

全部 P0，建议一次性交付。

---

## 关键设计约束

- **所有 event 类型为 struct**（value type，Sendable by default）
- **所有 event 类型遵循 Codable** — 未来需要 JSON 序列化（Axion event log）和 SQLite 存储。所有 payload 字段必须是 Codable 类型。
- **sessionId 为 `String?`** — 不是所有 agent 都有 sessionId（例如 skill agent 不配置 SessionStore）。所有 event 的 `sessionId` 字段类型为 `String?`。emit 时从 `options.sessionId` 获取，可能为 nil。
- **不携带敏感数据** — `ToolStartedEvent.input` 为可选，由 emit 方决定是否包含
- **EventBus 为 actor** — 线程安全
- **EventBus 不持久化** — 持久化由 SessionStore 负责
- **向后兼容** — 不改任何现有 API，纯新增
- **零开销** — 不注入 EventBus 时，agent 行为与现在完全一致

## 与现有类型的关系

- **`SDKMessage`**（`Sources/OpenAgentSDK/Types/SDKMessage.swift`）：LLM 消息级抽象（assistant、toolUse、toolResult、result、system）。AgentEvent 是更高层的 runtime 级抽象。两者共存，互不替代。
- **`AgentSSEEvent`**（`Sources/OpenAgentSDK/HTTP/APITypes.swift:215`）：SSE 推送用的 HTTP event 枚举（stepStarted、stepCompleted、runCompleted）。AgentEvent 是 SSE event 的上游数据源，Epic 28 会建立映射。
- **`SDKMessageOutputHandler`**（`Sources/OpenAgentSDK/Types/SDKMessageOutputHandler.swift`）：CLI 输出的 handler 协议。EventBus 是不同的输出通道，不替代 OutputHandler。

## EventBus 类型过滤 subscribe 的实现提示

`subscribe<T: AgentEvent>(_ type: T.Type)` 的实现需要运行时类型检查。推荐方式：

```swift
// 在 EventBus 内部
func subscribe<T: AgentEvent>(_ type: T.Type) -> AsyncStream<T> {
    AsyncStream { continuation in
        let fullStream = subscribeAll()
        // 在 fullStream 的 consumer Task 中做类型过滤
        // if let typed = event as? T { continuation.yield(typed) }
    }
}
```

注意：`subscribe<T>` 需要为每个类型过滤 subscriber 创建一个独立的消费 Task，该 Task 从全量 stream 读取并过滤。当外层 `AsyncStream<T>` 被 deinit 时，消费 Task 应自动取消。

## 测试策略

- Event 类型：纯 struct 构造测试，不需要 LLM
- EventBus：actor 并发测试（publish/subscribe/unsubscribe），不需要 LLM
- 使用 XCTest 框架（`XCTestCase`），与项目现有测试模式一致
- 测试文件放在 `Tests/OpenAgentSDKTests/` 目录
