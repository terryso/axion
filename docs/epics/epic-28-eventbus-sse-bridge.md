# Runtime Event Layer — Epic 28: EventBus → SSE Bridge

> **状态：待开发**
> **优先级：P1**
> **依赖：** Epic 27（Agent Event Emitter）
> **Roadmap：** `docs/runtime-event-layer-roadmap.md` → S4 + S5

## 背景与动机

SDK 的 `EventBroadcaster`（SSE）目前由 `ApiRunner` 在 stream loop 中手动 emit。这导致 HTTP API 路径里有大量 event 构造代码。

本 Epic 将 `EventBroadcaster` 改造为 `EventBus` 的一个 subscriber，让 SSE event 自动从 EventBus 流出，消除手动 emit 的重复代码。

---

### Story 28.1: AgentEvent → SSE Event 映射

As a SDK 开发者,
I want 将 AgentEvent 转换为 SSE event 格式,
So that EventBus 的事件可以透传到 HTTP SSE 客户端.

**实施：**
- 创建 `Sources/OpenAgentSDK/Utils/AgentEventSSEMapping.swift`
- 定义 `AgentEvent → AgentSSEEvent?` 映射函数
- 映射规则：
  - `AgentStartedEvent` → `run_started`（或等效 SSE event）
  - `ToolStartedEvent` → `step_started`
  - `ToolCompletedEvent` → `step_completed`
  - `AgentCompletedEvent` → `run_completed`
  - `LLMCostEvent` → `cost_update`（新增 SSE event type）
  - 其他 event → 暂不映射（返回 nil）

**Acceptance Criteria:**

**Given** `ToolStartedEvent(toolName: "bash", toolUseId: "xxx")`
**When** 转换为 SSE event
**Then** 得到 `step_started` event，含 `tool: "bash"`

**Given** `AgentStartedEvent`
**When** 转换为 SSE event
**Then** 得到 `run_started` event

**Given** `LLMCostEvent`
**When** 转换为 SSE event
**Then** 得到 `cost_update` event（含 token 和 cost 数据）

---

### Story 28.2: EventBus → EventBroadcaster 桥接

As a SDK 开发者,
I want EventBroadcaster 自动消费 EventBus 的事件,
So that SSE 推送不再需要在 ApiRunner 中手动 emit.

**实施：**
- 修改 `AgentHTTPServer` 或 `RunTracker`
- 在 session 创建时：
  1. 创建 EventBus（或获取共享实例）
  2. Subscribe EventBus
  3. 将收到的 AgentEvent 转换为 SSE event
  4. 通过 EventBroadcaster 推送到 SSE 客户端
- 逐步移除 ApiRunner 中的手动 SSE emit 代码

**Acceptance Criteria:**

**Given** HTTP API 收到一个 run 请求
**When** agent 执行
**Then** SSE 客户端收到的事件与当前行为一致（step_started、step_completed、run_completed）

**Given** agent 执行了 5 个 tool 调用
**When** 检查 SSE 推送的事件
**Then** 收到 5 个 `step_started` + 5 个 `step_completed`

---

### Story 28.3: Token Streaming Event（可选）

As a TUI 开发者,
I want agent 在 LLM 流式输出时 emit token chunk 事件,
So that TUI 可以实时渲染 AI 输出，不需要等 agent 完整 response.

**实施：**
- 在 `AgentOptions` 新增 `emitTokenStream: Bool = false`（默认关闭）
- 当 `emitTokenStream == true` 且 `eventBus != nil` 时：
  - 在 LLM streaming response 每个 chunk 时 emit `LLMTokenStreamEvent`
- payload：`sessionId`、`chunk: String`

**注意：** 大量高频 event。只在 TUI 场景开启。CLI 输出和 SSE 不需要。

**Acceptance Criteria:**

**Given** `emitTokenStream == true` 且 EventBus 已配置
**When** LLM 返回流式 response
**Then** EventBus 收到多个 `LLMTokenStreamEvent`，每个包含一个 chunk

**Given** `emitTokenStream == false`（默认）
**When** LLM 返回流式 response
**Then** EventBus 不收到 `LLMTokenStreamEvent`

---

## Story 间的依赖关系

```
28.1 AgentEvent → SSE 映射 (P0)
  │
  └──► 28.2 EventBus → EventBroadcaster 桥接 (P0)
        │
        └──► 28.3 Token Streaming (P2) — 可选，独立功能
```

---

## 实现优先级

| Story | 优先级 | 理由 |
|-------|--------|------|
| 28.1 Event → SSE 映射 | P0 | 桥接的前提 |
| 28.2 EventBus → EventBroadcaster | P0 | 消除 SSE 手动 emit 代码 |
| 28.3 Token Streaming | P2 | TUI 增强功能，可后置 |

---

## 关键设计约束

- **SSE 行为不变** — HTTP API 的 SSE 推送内容必须与当前一致
- **渐进式迁移** — 可以先让 EventBus 和手动 emit 并行运行，验证一致后再移除手动代码
- **Token streaming 默认关闭** — 避免高频 event 影响性能

## 现有 SSE Event 类型参考

当前 `AgentSSEEvent`（`Sources/OpenAgentSDK/HTTP/APITypes.swift:215`）有 3 个 case：

```swift
public enum AgentSSEEvent: Equatable, Sendable {
    case stepStarted(StepStartedData)      // { stepIndex: Int, tool: String }
    case stepCompleted(StepCompletedData)  // { stepIndex: Int, tool: String, success: Bool, durationMs: Int? }
    case runCompleted(RunCompletedData)    // { runId: String, finalStatus: String, totalSteps: Int, durationMs: Int? }
}
```

Epic 28 的映射需要将 AgentEvent 转换为这些现有 SSE event 类型。`runId` 在 SSE 中对应 `sessionId`（概念相同，命名不同）。

## EventBus 归属

- **创建时机：** 在 `AgentHTTPServer` 中，每个 run 请求创建一个 `EventBus` 实例
- **生命周期：** per-session。一个 session 对应一个 EventBus。
- **共享：** 同一个 EventBus 实例可能被多个 subscriber 消费（SSE bridge、trace handler 等）
- **不与 AgentOptions.eventBus 混淆：** `AgentHTTPServer` 创建 EventBus 后注入到 `AgentOptions.eventBus`，再传给 `Agent`

## 现有手动 SSE emit 代码位置

当前 SSE event 手动 emit 在 Axion 项目中（不在 SDK 中）：
- `Sources/AxionCLI/API/ApiRunner.swift` — `processStreamFromAsyncStream()` 方法中的 `eventBroadcaster.emit()` 调用

本 Epic（SDK 侧）只做 AgentEvent → SSE 的映射函数和桥接逻辑。Axion 侧的迁移在 Axion Epic 3（A5）中完成。
