# Open Agent SDK — Runtime Event Layer Roadmap

版本：0.1
日期：2026-05-25
目标：为 SDK 增加 Runtime-level Event 体系，使上层（Axion）可以构建统一的 Agent Runtime

---

# 1. 背景

SDK 当前已有完整的 Agent 执行能力：
- `Agent.stream()` → `AsyncStream<SDKMessage>`（消息级事件流）
- `SessionStore`（session 持久化、fork、restore）
- `EventBroadcaster`（SSE 推送，为 HTTP API 设计）
- `SubAgentSpawner` / `TeamStore` / `TaskStore`（多 agent 编排）
- `MemoryStore` / `FactStore` / `ReviewOrchestrator`（自进化系统）
- `HookRegistry` / `ShellHookExecutor`（hook 系统）

**缺少什么：**

SDK 的 `SDKMessage` 是 LLM 消息级的抽象（assistant、toolUse、toolResult、result）。
上层需要的是 **Runtime 级别** 的事件：session lifecycle、agent lifecycle、workflow progress、memory changes、cost tracking。

当前上层（Axion）被迫在 `for await message in agent.stream()` 循环里手动处理所有横切关注点（visual delta、seat monitoring、cost tracking、memory processing、review），这是因为 SDK 没有提供更高层的 event 模型。

---

# 2. 目标

在 SDK 中增加 **Runtime Event Layer**，让上层可以：

1. 通过统一的 `EventBus` 订阅所有 runtime 事件
2. 不再需要手动解析 `SDKMessage` 来提取状态变化
3. CLI / TUI / HTTP API / macOS App 都消费同一个 event stream

**不改什么：**
- `Agent.stream()` 和 `Agent.prompt()` 保持不变（向后兼容）
- `SDKMessage` 保持不变
- `EventBroadcaster`（SSE）保持不变，成为 EventBus 的一个 consumer

---

# 3. 改动项

按依赖顺序排列。

---

## S1. AgentEvent Protocol + Event 类型 ✅ 已完成（Epic 26）

**优先级：P0（所有后续工作的基础）**

### 改动

在 `Sources/OpenAgentSDK/Types/` 新增 `AgentEventTypes.swift`：

```swift
/// Runtime-level event protocol.
/// All events emitted by the SDK runtime layer conform to this protocol.
public protocol AgentEvent: Sendable {
    var id: String { get }
    var timestamp: Date { get }
}

/// Base event with common fields.
public struct BaseAgentEvent: AgentEvent {
    public let id: String
    public let timestamp: Date
}
```

### Event 分类

| 类别 | Event | 描述 |
|------|-------|------|
| **Session** | `SessionCreatedEvent` | session 创建 |
| | `SessionRestoredEvent` | session 从持久化恢复 |
| | `SessionClosedEvent` | session 关闭 |
| | `SessionAutoSavedEvent` | session 自动保存 |
| **Agent** | `AgentStartedEvent` | agent 开始执行 |
| | `AgentCompletedEvent` | agent 执行完成 |
| | `AgentFailedEvent` | agent 执行失败 |
| | `AgentInterruptedEvent` | agent 被中断 |
| | `AgentResumedEvent` | agent 恢复执行 |
| **Tool** | `ToolStartedEvent` | tool 开始执行（含 tool name, input） |
| | `ToolStreamingEvent` | tool 输出流式数据 |
| | `ToolCompletedEvent` | tool 执行完成（含 output, duration） |
| | `ToolFailedEvent` | tool 执行失败（含 error） |
| **LLM** | `LLMRequestStartedEvent` | LLM API 调用开始 |
| | `LLMResponseReceivedEvent` | LLM 响应接收完成 |
| | `LLMTokenStreamEvent` | token 流式输出（可选，用于 TUI 实时渲染） |
| | `LLMCostEvent` | 单次 LLM 调用成本（input/output tokens, cost） |
| **Memory** | `MemoryUpdatedEvent` | memory 条目更新 |
| | `MemoryCompressedEvent` | memory 压缩 |
| **SubAgent** | `SubAgentSpawnedEvent` | 子 agent 生成 |
| | `SubAgentCompletedEvent` | 子 agent 完成 |

### 验收标准

- 所有 event 类型定义在 SDK 中
- 每个 event 携带足够的 payload 信息（上层不需要回头查 SDKMessage）
- 全部 Sendable
- 有对应的单元测试

---

## S2. EventBus（进程内 Event Bus） ✅ 已完成（Epic 26）

**优先级：P0**
**依赖：S1**

### 改动

在 `Sources/OpenAgentSDK/Core/` 新增 `EventBus.swift`：

```swift
/// In-process event bus using AsyncStream.
/// Supports multiple subscribers. Events are broadcast to all subscribers.
public actor EventBus {
    public func publish(_ event: any AgentEvent)
    public func subscribe() -> AsyncStream<any AgentEvent>
    public func subscribe<T: AgentEvent>(_ type: T.Type) -> AsyncStream<T>
}
```

### 设计要点

- 基于 `AsyncStream<any AgentEvent>` 实现（bufferingPolicy: .bufferingNewest(100)）
- 支持类型过滤 subscribe（只订阅特定 event 类型）
- 支持多个 subscriber（CLI + SSE + trace，同时消费）
- Buffer 策略：bufferingLatest(100)，避免慢 consumer 阻塞 agent 执行
- 不持久化（持久化由 SessionStore 负责）

### 验收标准

- publish 后所有 subscriber 都能收到 event
- 慢 subscriber 不阻塞 agent 执行
- subscriber 取消后不 leak
- 有单元测试

---

## S3. Agent Event Emitter

**优先级：P0**
**依赖：S1, S2**

### 改动

修改 `Agent.swift` 内部的 `promptImpl` / `stream` 方法，在关键节点 emit AgentEvent 到 EventBus：

**emit 点：**

| 位置 | Event |
|------|-------|
| agent.stream() 开始 | `AgentStartedEvent` |
| LLM API 调用前 | `LLMRequestStartedEvent` |
| LLM 流式 token | `LLMTokenStreamEvent`（可选，可配置开关） |
| LLM 响应完成 | `LLMResponseReceivedEvent` + `LLMCostEvent` |
| tool 执行前 | `ToolStartedEvent` |
| tool 执行后 | `ToolCompletedEvent` / `ToolFailedEvent` |
| agent 执行结束 | `AgentCompletedEvent` / `AgentFailedEvent` |
| interrupt() 调用 | `AgentInterruptedEvent` |
| resume() 调用 | `AgentResumedEvent` |
| session auto-save | `SessionAutoSavedEvent` |
| sub-agent spawn | `SubAgentSpawnedEvent` |

### 向后兼容

- `AgentOptions` 新增 `eventBus: EventBus? = nil`
- 不传 EventBus → 行为与现在完全一致（零开销）
- 传了 EventBus → 在执行过程中 emit events

### 验收标准

- Agent.stream() 在无 EventBus 时行为不变
- Agent.stream() 在有 EventBus 时，所有关键节点都 emit event
- Event payload 信息完整（tool name, input/output, duration, tokens, cost）
- 现有 E2E 测试全部通过

---

## S4. EventBus → EventBroadcaster 桥接

**优先级：P1**
**依赖：S3**

### 改动

将现有的 `EventBroadcaster`（SSE）改造为 `EventBus` 的一个 subscriber：

```swift
// 在 AgentHTTPServer 中
let eventBus = EventBus()
eventBus.subscribe().map { event in
    // 将 AgentEvent 转换为 AgentSSEEvent
}.sink { sseEvent in
    broadcaster.emit(sseEvent)
}
```

### 目的

- SSE 推送不再需要单独在 ApiRunner 里手动 emit
- HTTP API 消费的是同一个 EventBus
- 减少代码重复

### 验收标准

- HTTP SSE 行为不变
- SSE event 的信息不丢失

---

## S5. Token Streaming Event（可选）

**优先级：P2**
**依赖：S3**

### 改动

在 LLM streaming 响应时，emit `LLMTokenStreamEvent`，包含每个 token chunk。

### 设计决策

- 需要一个开关 `AgentOptions.emitTokenStream: Bool = false`
- 默认关闭（大量 event 会影响性能）
- TUI 场景打开（用于实时渲染 AI 输出）

### 验收标准

- 开启时，TUI 可以实时渲染 AI 输出
- 关闭时，无额外开销

---

# 4. 依赖关系图

```
S1 (AgentEvent types)
    ↓
S2 (EventBus)
    ↓
S3 (Agent Event Emitter)  ← 核心，改 Agent.swift
    ↓
S4 (EventBus → SSE bridge)    P1
S5 (Token Streaming)          P2
```

---

# 5. 不做的事

| 不做 | 原因 |
|------|------|
| Workflow DAG engine | 不是 SDK 的职责，由 Axion 上层编排 |
| EventBus 持久化 | SDK 有 SessionStore，EventBus 是瞬时通道 |
| 跨进程 EventBus | v1 只做进程内，跨进程由 Axion 的 daemon 处理 |
| 修改 SDKMessage | 完全向后兼容，SDKMessage 不变 |
| Remote runtime | 未来方向，v1 不做 |

---

# 6. 风险

| 风险 | 缓解 |
|------|------|
| Agent.swift 改动面大 | EventBus 是可选注入，不改核心逻辑，只在关键节点加 emit |
| Event payload 设计不当 | 先实现 S1 的类型定义，Axion 侧 review 后再改 Agent |
| 性能影响 | EventBus 默认 nil，不传就不执行任何 event 代码 |
| 向后兼容 | 现有 E2E 测试（882 个）必须全部通过 |

---

# 7. 建议的 Epic 拆分

**SDK Epic 1: AgentEvent + EventBus（S1 + S2）**
- 定义 event protocol 和所有 event 类型
- 实现 EventBus actor
- 单元测试

**SDK Epic 2: Agent Event Emitter（S3）**
- 修改 AgentOptions 增加 eventBus
- 在 Agent.stream() / promptImpl 关键节点 emit events
- E2E 测试验证

**SDK Epic 3: SSE Bridge + Token Stream（S4 + S5）**
- EventBus → EventBroadcaster 桥接
- Token streaming event（可选）
- 集成测试
