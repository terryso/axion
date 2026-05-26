# Axion Epic 24: AxionRuntime Core

> **状态：待开发**
> **优先级：P0**
> **前置依赖：SDK Epic 26-28 已完成（AgentEvent + EventBus + Agent Event Emitter + SSE Bridge）**
> **Roadmap：** `docs/agent-runtime-roadmap.md` → A1 + A2
> **Epic 编号说明：** Axion 已有 Epic 1-23，本 Epic 从 24 开始

## 背景与动机

Axion 当前有两条独立的 agent 执行路径：
- **CLI**：`RunCommand` → `AgentBuilder` → `RunOrchestrator.execute()` → 手动消费 `SDKMessage`
- **HTTP API**：`AxionAPI` → `ApiRunner` → `AgentBuilder` → 手动 emit SSE event

两条路径各自处理横切关注点（cost tracking、visual delta、seat monitoring 等），代码重复且难以扩展。

SDK 已完成 EventBus 体系（Epic 26-28），提供了：
- `EventBus` actor（多 subscriber、类型过滤、bufferingNewest(100)）
- 12 种 `AgentEvent` 类型（agent/tool/LLM/session lifecycle）
- `AgentOptions.eventBus` 注入点（零开销可选）
- `ToolCompletedEvent.output: String?` — tool 执行结果（Axion 补充字段）
- `onRunComplete` 回调 → `RunCompleteContext`（含 toolPairs、usage、totalCostUsd、durationMs、numTurns）
- `SessionStore(sessionsDir:)` — 可自定义存储目录（Axion 传 `~/.axion/sessions`）

本 Epic 在 Axion 中引入 `AxionRuntime` actor，作为 agent 执行的统一入口。

### 核心数据流设计

AxionRuntime 消费**三个数据源**，各有明确职责：

```
AxionRuntime 数据来源：

1. AgentEvent 流（EventBus subscribe）
   → 实时渲染（EventOutputHandler）
   → EventHandler 分发（cost、visual delta、seat monitor 等）

2. onRunComplete 回调（RunCompleteContext）
   → toolPairs、usage、totalCostUsd、durationMs、numTurns
   → 传给 terminal event handler（Memory、Review）

3. SessionStore.load()
   → collectedMessages（完整对话历史，ReviewHandler 需要）
   → 在 agent 完成后从磁盘加载，不需要实时维护
```

**关键设计原则：AxionRuntime 不从 SDKMessage 重新构建 SDK 已有的数据。**

| 数据 | 来源 | 不自建的理由 |
|------|------|------------|
| toolPairs | `RunCompleteContext.toolPairs` | SDK 已在内部匹配 tool_use/tool_result |
| collectedMessages | `SessionStore.load(sessionId:)` | SDK 已持久化完整对话 |
| cost 数据 | `LLMCostEvent` | SDK 已 emit 每次调用的 token/cost |
| screenshot base64 | `ToolCompletedEvent.output` | SDK 已携带 tool 输出 |
| totalSteps / durationMs | `AgentCompletedEvent` | SDK 已 emit 汇总数据 |
| externallyModified | Axion 特有（SeatMonitorHandler 设置） | 需要 Axion 层维护 |
| takeoverEvent | Axion 特有（从 SDKMessage pause/resume 构建） | 需要 Axion 层维护 |

---

### Story 24.1: AxionRuntime 骨架

As a Axion 开发者,
I want 创建 AxionRuntime actor 作为 agent 执行的统一入口,
So that CLI 和 API 不再各自直接构建和执行 agent.

**实施：**

1. SDK 依赖使用本地路径（`Package.swift` 使用 `.package(path:)`），EventBus 可用
2. 在 `Sources/AxionCore/Runtime/` 创建 `AxionRuntime.swift`

```swift
public actor AxionRuntime {
    private let eventBus: EventBus
    private var handlers: [any EventHandler] = []
    private let sessionStore: SessionStore

    /// Axion 特有运行时状态（只存 SDK 不提供的数据）
    private var axionState: AxionRunState?

    public init(eventBus: EventBus = EventBus()) {
        self.eventBus = eventBus
        // Axion 使用自己的目录，不是 SDK 默认的 ~/.open-agent-sdk/sessions
        self.sessionStore = SessionStore(sessionsDir: AxionPaths.sessionsDirectory)
    }

    /// 创建一个 session（不执行 agent）
    public func createSession(task: String, config: AxionConfig) async throws -> String

    /// 启动 agent 执行（阻塞直到完成）
    public func start(sessionId: String) async throws

    /// 注册 event handler
    public func registerHandler(_ handler: any EventHandler)

    /// 获取共享 EventBus 的订阅流
    public func subscribe() async -> (UUID, AsyncStream<any AgentEvent>)

    /// 类型过滤订阅
    public func subscribe<T: AgentEvent>(_ type: T.Type) async -> AsyncStream<T>
}
```

3. Session state machine：

```
CREATED → RUNNING → COMPLETED
                  → FAILED
                  → INTERRUPTED
```

**AxionConfig 定义：**

```swift
/// AxionRuntime 的配置。封装 CLI/API 共用的运行时参数。
public struct AxionConfig: Sendable {
    public let task: String
    public let model: String
    public let cwd: String
    public let dryrun: Bool
    public let noMemory: Bool
    public let noReview: Bool
    public let noVisualDelta: Bool
    public let sharedSeatMode: Bool
    public let fast: Bool
    public let jsonOutput: Bool
    public let maxTurns: Int?
    public let maxTokens: Int?
    public let maxBudgetUsd: Double?
    public let maxModelCalls: Int?
    public let systemPrompt: String?
    public let thinkingBudget: Int?
    public let permissionMode: PermissionMode
    public let mcpServers: [String: McpServerConfig]?
    public let skillDirectories: [String]?
    public let skillNames: [String]?
    public let baseURL: String?
    public let provider: LLMProvider
}
```

**AxionRunState（Axion 特有状态）：**

```swift
/// Axion 特有的运行时状态。
/// 只存储 SDK 不提供的、Axion 层面需要维护的数据。
public struct AxionRunState: Sendable {
    public var externallyModified: Bool = false
    public var takeoverEvent: TakeoverEventContext?
}
```

**AxionRuntime 的职责边界：**
- **做**：Session lifecycle、EventBus 创建、Agent 构建与执行、分发给 EventHandler、维护 AxionRunState
- **不做**：CLI 输出渲染、SSE 推送、重复构建 SDK 已有的数据

**Acceptance Criteria：**

**Given** Axion 的 SDK 依赖使用本地路径
**When** 编译 Axion 项目
**Then** 编译通过，`EventBus` 和 `AgentEvent` 类型可用

**Given** `AxionRuntime` 被创建
**When** 调用 `subscribe()` 获取 event stream
**Then** 返回一个有效的 `AsyncStream<any AgentEvent>`

---

### Story 24.2: AxionRuntime 的 Agent 构建与执行

As a Axion 开发者,
I want AxionRuntime 内部调用 AgentBuilder 并注入 EventBus,
So that agent 执行时自动通过 EventBus emit events.

**实施：**

1. `AxionRuntime` 内部调用 `AgentBuilder.build()`（复用现有 builder）
2. 在构建的 `AgentOptions` 中注入 `eventBus: self.eventBus`
3. 配置 `sessionStore` + `persistSession: true` — SDK 自动保存对话，Axion 通过 `sessionStore.load()` 获取
4. 拦截 `onRunComplete` 回调，捕获 `RunCompleteContext`
5. 实现 `start(sessionId:)`：内部调用 `agent.stream()` 并消费 SDKMessage

**SDKMessage 消费的职责范围：**

AxionRuntime 消费 `agent.stream()` 的 SDKMessage 流，但**只做三件事**：
1. **驱动 agent 执行** — 必须消费 SDKMessage stream，agent 才会运行
2. **构建 takeoverEvent** — 解析 `.paused` / `.resumed` SDKMessage 构建 TakeoverEventContext
3. **转发给 outputHandler** — 如果有 SDKMessage 级别的渲染需求（过渡期）

**不从 SDKMessage 构建：** toolPairs（用 onRunComplete）、collectedMessages（用 SessionStore.load）、cost（用 LLMCostEvent）

**关键设计：与现有 AgentBuilder 的关系**

```
RunCommand ──→ AxionRuntime ──→ AgentBuilder.build() ──→ Agent.stream()
                    ↓                                      ↓
              EventBus.subscribe()               EventBus.publish(AgentEvent)
              SDKMessage stream (驱动执行 + takeoverEvent)
              onRunComplete → RunCompleteContext (toolPairs 等)
```

**`onRunComplete` 回调的拦截：**

```swift
// AxionRuntime.start() 内部
var capturedRunCompleteContext: RunCompleteContext?
let buildConfig = BuildConfig.forCLI(/* ... */)
// 在 buildConfig 中注入 onRunComplete
var runConfig = /* ... */
runConfig.onRunComplete = { context in
    capturedRunCompleteContext = context
}
```

`RunCompleteContext` 在 terminal event handler 触发时通过 `EventHandlerContext` 传递。

**SIGINT 处理：**

```swift
// AxionRuntime.start() 内部
let sigintHandler = { @Sendable in
    Task { await runtime.cancelSession(sessionId) }
}
// signal(SIGINT, sigintHandler)
// agent.interrupt()
// SDK 会 emit AgentInterruptedEvent 到 EventBus
```

**EventBus 所有权：**
- **CLI 模式**：每个 `axion run` 创建一个 AxionRuntime + 一个 EventBus（per-run）
- **Daemon 模式**：一个长期存活的 AxionRuntime + 一个共享 EventBus（所有 session 共用）
- Handler 注册在 AxionRuntime 上，不是 per-session

**Acceptance Criteria：**

**Given** `AxionRuntime.createSession()` 返回 sessionId
**When** 调用 `AxionRuntime.start(sessionId:)`
**Then** agent 开始执行，EventBus 收到 `AgentStartedEvent`

**Given** agent 执行完成
**When** 检查 EventBus 的事件
**Then** 收到 `AgentCompletedEvent`，含 `totalSteps`、`durationMs`

**Given** agent 执行 3 个 tool 调用
**When** 检查 EventBus 的事件
**Then** 收到 3 个 `ToolStartedEvent` + 3 个 `ToolCompletedEvent`（含 `output` 字段）

**Given** agent 执行完成
**When** 检查 `onRunComplete` 回调
**Then** `RunCompleteContext.toolPairs` 包含所有 tool 配对数据

**Given** SIGINT 被发送
**When** agent 正在执行
**Then** agent 被 interrupt，EventBus 收到 `AgentInterruptedEvent`

---

### Story 24.3: AxionRunState + Session 元数据

As a Axion 开发者,
I want AxionRuntime 维护 Axion 特有的运行时状态和 session 元数据,
So that EventHandler 可以访问 SDK 不提供的 Axion 层面数据.

**实施：**

1. 在 `Sources/AxionCore/Runtime/` 创建 `AxionRunState.swift`

```swift
/// Axion 特有的运行时状态。
/// 只存储 SDK AgentEvent / RunCompleteContext 不提供的数据。
public actor AxionRunState {
    public var externallyModified: Bool = false
    public var takeoverEvent: TakeoverEventContext?

    public func setExternallyModified() {
        externallyModified = true
    }

    public func setTakeoverEvent(_ event: TakeoverEventContext) {
        takeoverEvent = event
    }

    public func reset() {
        externallyModified = false
        takeoverEvent = nil
    }
}
```

2. `EventHandlerContext` 包含所有 handler 需要的数据：

```swift
public struct EventHandlerContext: Sendable {
    public let sessionId: String?
    public let config: AxionConfig
    public let axionState: AxionRunState          // Axion 特有状态
    public let runCompleteContext: RunCompleteContext?  // SDK 聚合数据（terminal event 时非 nil）
    public let sessionStore: SessionStore          // 用于加载 collectedMessages
    public let parentAgent: Agent?                 // 父 agent 引用（ReviewHandler 创建 sub-agent 用）
}
```

3. **Session 元数据使用 SDK SessionStore** — 不创建独立持久化：
   - AxionRuntime 初始化时创建 `SessionStore(sessionsDir: "~/.axion/sessions")`
   - `createSession()` 时 SDK 的 `AgentOptions.sessionStore` + `persistSession: true` 自动保存对话
   - `listSessions()` 底层调用 `sessionStore.list()` 获取 SDK 的 `SessionMetadata`
   - Axion 特有的 status/totalSteps/durationMs 存储在 session 目录下的 `axion-state.json`（轻量 overlay）
   - **两个数据源在同一目录下**：`~/.axion/sessions/{id}/transcript.json`（SDK）+ `axion-state.json`（Axion）

4. 新增查询方法：

```swift
public func listSessions() async throws -> [SessionInfo]
public func getSession(_ sessionId: String) async throws -> SessionInfo?
```

**SessionInfo = SDK SessionMetadata + Axion overlay：**

```swift
public struct SessionInfo: Sendable {
    public let metadata: SessionMetadata   // 来自 SDK SessionStore
    public let status: SessionStatus       // 来自 axion-state.json
    public let totalSteps: Int             // 来自 axion-state.json
    public let durationMs: Int?            // 来自 axion-state.json
}
```

**axion-state.json 格式：**

```json
{
  "status": "COMPLETED",
  "totalSteps": 12,
  "durationMs": 34000,
  "updatedAt": "2026-05-27T14:32:00Z"
}
```

**Acceptance Criteria：**

**Given** AxionRuntime 执行一个 agent run
**When** agent 完成 3 个 tool 调用
**Then** `RunCompleteContext.toolPairs` 包含 3 个 tool 配对（不从 SDKMessage 自建）

**Given** AxionRuntime 创建了一个 session
**When** 调用 `listSessions()`
**Then** 返回的列表包含新创建的 session（底层调用 `SessionStore.list()`）

**Given** session 执行完成
**When** 调用 `getSession(sessionId)`
**Then** 返回 `SessionInfo`，含 SDK 的 `SessionMetadata` + Axion 的 status/totalSteps/durationMs

**Given** AxionRuntime 执行 agent 时设置了 `persistSession: true`
**When** 调用 `sessionStore.load(sessionId:)`
**Then** 返回完整对话历史（`SessionData.messages`），ReviewHandler 可使用

---

### Story 24.4: Session 状态持久化

As a Axion 开发者,
I want AxionRuntime 持久化 session 的 Axion 特有状态,
So that session 状态可以在进程重启后恢复.

**实施：**

1. Axion 特有状态持久化为 `axion-state.json`，存储在 SDK session 目录下
   - 路径：`~/.axion/sessions/{sessionId}/axion-state.json`
   - SDK 的 `transcript.json` 也在同一目录（`SessionStore(sessionsDir: "~/.axion/sessions")` 管理）
2. `createSession()` 写入初始状态（status=CREATED）
3. `start()` 更新状态为 RUNNING
4. 执行完成后更新为 COMPLETED / FAILED / INTERRUPTED（写入 totalSteps、durationMs）
5. 写入时机：terminal event 到达时

**为什么不用 SDK 的 `SessionStore.save()` 的 metadata：**
- SDK 的 `PartialSessionMetadata` 不支持 `status`（CREATED/RUNNING/COMPLETED）和 `totalSteps`
- 这些是 Axion 运行时层面的概念，SDK 不应感知
- `axion-state.json` 是轻量 overlay，不重复 SDK 已有的数据

**Acceptance Criteria：**

**Given** `AxionRuntime.createSession()` 被调用
**When** 检查 `~/.axion/sessions/{id}/axion-state.json`
**Then** status 为 CREATED

**Given** session 执行完成
**When** 检查 `axion-state.json`
**Then** status 为 COMPLETED，含 totalSteps 和 durationMs

**Given** 两个 session 已完成
**When** 调用 `listSessions()`
**Then** 返回 2 个 `SessionInfo`，每个包含 SDK metadata + Axion status

---

## Story 间的依赖关系

```
24.1 AxionRuntime 骨架 (P0)
  │
  └──► 24.2 Agent 构建与执行 (P0)
        │
        └──► 24.3 AxionRunState + Session 元数据 (P0)
              │
              └──► 24.4 Session 状态持久化 (P0)
```

24.3 和 24.4 可并行，但都依赖 24.2。

---

## 实现优先级

| Story | 优先级 | 理由 |
|-------|--------|------|
| 24.1 AxionRuntime 骨架 | P0 | 所有后续工作的基础 |
| 24.2 Agent 构建与执行 | P0 | 核心功能：EventBus 集成 |
| 24.3 AxionRunState + Session 元数据 | P0 | EventHandler 需要的数据 |
| 24.4 Session 持久化 | P0 | Session resume 的前提 |

---

## 关键设计约束

- **不改 AgentBuilder** — AxionRuntime 包装 AgentBuilder，不替代它
- **不改 SDK** — SDK 已完成（含 `ToolCompletedEvent.output`、`SessionStore(sessionsDir:)`），Axion 只消费 SDK 的 API
- **不从 SDKMessage 重建 SDK 已有的数据** — toolPairs 来自 `onRunComplete`，collectedMessages 来自 `SessionStore.load()`，cost 来自 `LLMCostEvent`
- **向后兼容** — 在 AxionRuntime 稳定之前，RunCommand 和 ApiRunner 仍然使用现有路径
- **渐进式** — 先让 AxionRuntime 和现有代码共存，验证一致后再切换
- **EventBus 所有权** — CLI 模式 per-run，daemon 模式 per-runtime（共享）
- **Session 目录** — Axion 使用 `~/.axion/sessions/`（通过 SDK 的 `SessionStore(sessionsDir:)` 设置），不使用 SDK 默认的 `~/.open-agent-sdk/sessions/`

## SDK API 表面（Axion 需要使用的）

```swift
// EventBus — 创建与订阅
let eventBus = EventBus()
let (id, stream) = await eventBus.subscribe()  // → (UUID, AsyncStream<any AgentEvent>)
let toolStream = await eventBus.subscribe(ToolCompletedEvent.self)  // → AsyncStream<ToolCompletedEvent>
await eventBus.unsubscribe(id)

// AgentOptions — 注入 EventBus + SessionStore
var options = AgentOptions(...)
options.eventBus = eventBus
options.sessionStore = SessionStore(sessionsDir: "~/.axion/sessions")
options.persistSession = true
options.sessionId = sessionId

// onRunComplete — 捕获聚合数据
options.onRunComplete = { context in
    // context.toolPairs, context.usage, context.totalCostUsd, context.durationMs, context.numTurns
}

// SessionStore — 自定义目录
let store = SessionStore(sessionsDir: "/Users/nick/.axion/sessions")
let sessions = try store.list()
let data = try store.load(sessionId: id)  // SessionData(metadata:, messages:)

// Agent Events（全部 Codable + Sendable + Equatable）
SessionCreatedEvent(sessionId: String?, task: String, model: String)
AgentStartedEvent(sessionId: String?, task: String)
AgentCompletedEvent(sessionId: String?, totalSteps: Int, durationMs: Int, resultText: String?)
AgentFailedEvent(sessionId: String?, error: String, stepsCompleted: Int)
AgentInterruptedEvent(sessionId: String?, stepsCompleted: Int)
ToolStartedEvent(sessionId: String?, toolName: String, toolUseId: String, input: String?)
ToolCompletedEvent(sessionId: String?, toolUseId: String, toolName: String, durationMs: Int, isError: Bool, output: String?)
ToolFailedEvent(sessionId: String?, toolUseId: String, toolName: String, error: String)
LLMCostEvent(sessionId: String?, model: String, inputTokens: Int, outputTokens: Int, ...)

// RunCompleteContext（onRunComplete 回调参数）
RunCompleteContext(toolPairs: [SDKMessage.ToolExecutionPair], task: String, runId: String?, status: QueryStatus, usage: TokenUsage, totalCostUsd: Double, durationMs: Int, numTurns: Int, costBreakdown: [CostBreakdownEntry])
```

## 文件位置

| 文件 | 目录 |
|------|------|
| AxionRuntime.swift | `Sources/AxionCore/Runtime/AxionRuntime.swift` |
| AxionRunState.swift | `Sources/AxionCore/Runtime/AxionRunState.swift` |
| AxionConfig.swift | `Sources/AxionCore/Models/AxionConfig.swift` |
| SessionInfo.swift | `Sources/AxionCore/Models/SessionInfo.swift` |
| 单元测试 | `Tests/AxionCoreTests/Runtime/AxionRuntimeTests.swift` |

## 现有代码参考

| 当前文件 | 职责 | 本 Epic 后的变化 |
|---------|------|---------------|
| `Sources/AxionCLI/Services/AgentBuilder.swift`（492 行） | 构建 Agent + 配置 | 不变，被 AxionRuntime 内部调用 |
| `Sources/AxionCLI/Services/RunOrchestrator.swift`（669 行） | CLI 执行编排 + 横切关注点 | 不变（Epic 26 迁移） |
| `Sources/AxionCLI/API/ApiRunner.swift`（342 行） | HTTP API 执行 + SSE emit | 不变（Epic 26 迁移） |
| `Sources/AxionCLI/Commands/RunCommand.swift`（120 行） | CLI 入口 | 不变（Epic 26 改造） |

## 测试策略

- **AxionRunState 测试**：不需要 LLM。验证 externallyModified 和 takeoverEvent 的设置/重置。
- **AxionRuntime 基础测试**：不需要 LLM。验证 session lifecycle、handler 注册、EventBus 订阅。
- **AxionRuntime 执行测试**：需要 E2E（真实 LLM）。验证 EventBus 收到完整事件序列、onRunComplete 捕获正确数据。
- **Session 持久化测试**：不需要 LLM。验证 axion-state.json 的读写、SessionStore.list() 集成。
