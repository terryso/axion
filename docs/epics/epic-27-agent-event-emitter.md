# Runtime Event Layer — Epic 27: Agent Event Emitter

> **状态：待开发**
> **优先级：P0**
> **依赖：** Epic 26（AgentEvent + EventBus）
> **Roadmap：** `docs/runtime-event-layer-roadmap.md` → S3

## 背景与动机

Epic 26 定义了 `AgentEvent` 类型和 `EventBus`。本 Epic 让 `Agent` 在执行过程中 emit 这些 events。

当前 `Agent.stream()` 的内部循环已经有所有 emit 点需要的信息——LLM 调用、tool 执行、session auto-save。只需要在正确位置加 `eventBus.publish()`。

**核心原则：EventBus 是可选注入的。不传 EventBus → 零开销，行为不变。**

---

### Story 27.1: AgentOptions 新增 eventBus 参数

As a SDK 开发者,
I want AgentOptions 支持注入 EventBus,
So that agent 在执行时可以向 EventBus emit events.

**实施：**
- 修改 `Sources/OpenAgentSDK/Types/SDKConfiguration.swift` 中 `AgentOptions`
- 新增可选字段：`public var eventBus: EventBus? = nil`
- 默认 nil（不传则不 emit 任何 event）

**Acceptance Criteria:**

**Given** `AgentOptions` 被创建时不传 eventBus
**When** 检查 `eventBus` 属性
**Then** 值为 `nil`

**Given** `AgentOptions` 被创建时传入 eventBus
**When** 检查 `eventBus` 属性
**Then** 值为传入的 EventBus 实例

---

### Story 27.2: Agent 启动与完成事件 Emit

As a SDK 开发者,
I want agent 在执行开始和结束时 emit 生命周期事件,
So that 上层可以知道 agent 何时开始、何时完成、是否失败.

**实施：**
- 修改 `Agent.swift` 的 `stream()` 和 `promptImpl()` 方法
- 在 agent 执行开始时：emit `AgentStartedEvent`
- 在 agent 正常结束时：emit `AgentCompletedEvent`（含 totalSteps、durationMs）
- 在 agent 异常结束时：emit `AgentFailedEvent`（含 error）
- 在 agent 被中断时：emit `AgentInterruptedEvent`
- 在 agent resume 时：emit `AgentResumedEvent`

**emit 位置（以 stream() 为例）：**
- `stream()` 内部 Task 开始 → `AgentStartedEvent`
- stream loop 正常结束 → `AgentCompletedEvent`
- stream loop 因 `_interrupted` 退出 → `AgentInterruptedEvent`
- stream loop 因 error 退出 → `AgentFailedEvent`
- `resume(context:)` 被调用 → `AgentResumedEvent`

**Acceptance Criteria:**

**Given** Agent 配置了 EventBus
**When** `agent.stream("task")` 被调用
**Then** EventBus 收到 `AgentStartedEvent`

**Given** agent 正常执行完成
**When** stream 结束
**Then** EventBus 收到 `AgentCompletedEvent`（含 totalSteps、durationMs）

**Given** agent 执行过程中被 interrupt
**When** stream 退出
**Then** EventBus 收到 `AgentInterruptedEvent`

**Given** Agent 未配置 EventBus（eventBus == nil）
**When** 执行 stream
**Then** 行为与当前完全一致，无额外开销

---

### Story 27.3: Tool 生命周期事件 Emit

As a SDK 开发者,
I want agent 在 tool 执行前后 emit 事件,
So that 上层可以追踪每个 tool 的执行时间和结果.

**实施：**
- 修改 `Agent.swift` 或 `ToolExecutor.swift` 中的 tool 执行流程
- tool 执行前：emit `ToolStartedEvent`（toolName、toolUseId）
- tool 执行后（成功）：emit `ToolCompletedEvent`（toolName、durationMs、isError=false）
- tool 执行后（失败）：emit `ToolCompletedEvent`（isError=true）或 `ToolFailedEvent`

**Acceptance Criteria:**

**Given** Agent 配置了 EventBus
**When** agent 调用 BashTool
**Then** EventBus 收到 `ToolStartedEvent`（toolName="bash"）
**Then** tool 完成后收到 `ToolCompletedEvent`（toolName="bash"、durationMs）

**Given** Agent 未配置 EventBus
**When** tool 执行
**Then** 行为不变，无额外开销

---

### Story 27.4: LLM 成本事件 Emit

As a SDK 开发者,
I want agent 在每次 LLM API 调用后 emit 成本事件,
So that 上层可以实时追踪 token 消耗和成本，无需等 agent 执行完成.

**实施：**
- 修改 LLM 调用完成后的处理逻辑（streaming response 解析完成后）
- emit `LLMCostEvent`（model、inputTokens、outputTokens、cacheReadTokens、estimatedCostUsd）
- token 数据来源：API response 的 `usage` 字段
- cost 计算：复用 SDK 现有的 `CostTracker` 逻辑

**Acceptance Criteria:**

**Given** Agent 配置了 EventBus
**When** LLM 返回一个 response（含 usage 数据）
**Then** EventBus 收到 `LLMCostEvent`（含 inputTokens、outputTokens、estimatedCostUsd）

**Given** agent 执行了 3 次 LLM 调用
**When** 检查 EventBus 收到的事件
**Then** 有 3 个 `LLMCostEvent`

**Given** Agent 未配置 EventBus
**When** LLM 调用
**Then** 行为不变

---

### Story 27.5: Session 生命周期事件 Emit

As a SDK 开发者,
I want agent 在 session 关键节点 emit 事件,
So that 上层可以追踪 session 的创建、保存、关闭.

**实施：**
- 在 `Agent.stream()` 开始时：emit `SessionCreatedEvent`（如果 sessionStore 已配置）
- 在 session auto-save 时：emit `SessionAutoSavedEvent`
- 在 `Agent.close()` 时：emit `SessionClosedEvent`

**Acceptance Criteria:**

**Given** Agent 配置了 EventBus + SessionStore
**When** `agent.stream("task")` 被调用
**Then** EventBus 收到 `SessionCreatedEvent`

**Given** Agent 配置了 EventBus + SessionStore + persistSession
**When** stream 过程中 session auto-save 触发
**Then** EventBus 收到 `SessionAutoSavedEvent`（含 messageCount）

**Given** Agent 配置了 EventBus
**When** `agent.close()` 被调用
**Then** EventBus 收到 `SessionClosedEvent`

---

## Story 间的依赖关系

```
27.1 AgentOptions.eventBus (P0) — 注入点
  │
  ├──► 27.2 Agent 启动/完成事件 (P0)
  ├──► 27.3 Tool 生命周期事件 (P0)
  ├──► 27.4 LLM 成本事件 (P0)
  └──► 27.5 Session 生命周期事件 (P1)
```

27.1 必须最先。27.2-27.5 可并行但建议按顺序（27.2 先，因为它是 agent 主循环的框架）。

---

## 实现优先级

| Story | 优先级 | 理由 |
|-------|--------|------|
| 27.1 AgentOptions.eventBus | P0 | 注入点，所有 emit 依赖 |
| 27.2 Agent 启动/完成事件 | P0 | 最核心的 lifecycle event |
| 27.3 Tool 生命周期事件 | P0 | observability 的基础 |
| 27.4 LLM 成本事件 | P0 | 实时成本追踪 |
| 27.5 Session 生命周期事件 | P1 | session 管理增强 |

---

## 关键设计约束

- **可选注入** — `eventBus: EventBus? = nil`，nil 时不执行任何 emit 代码
- **不阻塞 agent 执行** — emit 是 `await eventBus.publish()`，EventBus 的 publish 不等待 subscriber 消费
- **不改 SDKMessage** — SDKMessage 保持不变，event 是额外输出通道
- **不改现有 API 签名** — stream() / prompt() 的签名不变
- **现有 E2E 测试必须全部通过** — 不注入 EventBus 时行为完全一致
- **onRunComplete 与 EventBus 共存** — `onRunComplete` 回调保留不变（Axion 仍在使用）。EventBus 是额外通道，不替代 onRunComplete。未来可考虑 onRunComplete 的信息通过 EventBus 传递，但本 Epic 不做迁移。

## 代码结构提示（Agent.swift 关键位置）

Agent.swift 的核心执行流程在以下方法中：

| 功能 | 方法名 | 行号范围（参考） |
|------|--------|----------------|
| 同步执行入口 | `promptImpl(_ text:)` | ~1301 行 |
| 流式执行入口 | `stream(_ text:)` | ~1868 行 |
| stream 内部循环 | `stream()` 内的 `Task { ... }` 闭包 | ~1900-2850 行 |
| tool 调用 | `ToolExecutor.executeTools()` 调用 | ~1704 行（promptImpl）、~2641 行（stream） |
| session auto-save | `sessionStore.save()` 调用 | ~1541 行（promptImpl）、~2825 行（stream） |
| agent close | `close()` | ~733 行 |
| agent resume | `resume(context:)` | ~434 行 |

**sessionId 获取方式：**
- 在 `promptImpl` 中：用 `resolvedSessionId` 局部变量（~1321 行），它可能是 `options.sessionId` 或从 sessionStore 解析的值
- 在 `stream` 中：用 `capturedSessionId = options.sessionId`（~652 行）
- emit 时用 `options.sessionId`，可能为 nil（skill agent 等场景）

## Tool 执行的位置

tool 执行在 `ToolExecutor.executeTools()`（`Sources/OpenAgentSDK/Core/ToolExecutor.swift:181`）中。
这是一个 `static func`，被 `Agent.swift` 的 `promptImpl` 和 `stream` 调用。

**emit ToolStarted/ToolCompleted 的位置：** 在 `Agent.swift` 中调用 `ToolExecutor.executeTools()` 的前后，不在 ToolExecutor 内部。原因是 Agent 持有 `options.eventBus`，ToolExecutor 不持有。

**sub-agent 与 EventBus：**
- sub-agent 通过 `AgentTool`（`Sources/OpenAgentSDK/Tools/Advanced/AgentTool.swift`）spawn
- sub-agent **不继承** parent 的 EventBus。sub-agent 有自己的 `AgentOptions`，默认 `eventBus: nil`
- 如需 sub-agent emit events，由 spawn 方在创建 sub-agent 时传入 EventBus（本 Epic 不实现，留给未来）
- Parent agent 可通过 `SubAgentSpawnedEvent`（在 AgentTool 执行后由 parent emit）追踪子 agent

## 测试策略

- 需要真实 LLM 调用才能触发 emit 点 → 使用 E2E 测试（`Sources/E2ETest/`）
- 现有 E2E 测试加上 EventBus 注入，验证 event 被正确 emit
- 同时验证不注入 EventBus 时，所有现有 E2E 测试仍然通过
