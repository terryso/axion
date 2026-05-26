# Axion — Agent Runtime Roadmap

版本：0.2
日期：2026-05-27
前置依赖：open-agent-sdk-swift SDK Epic 26-28 已全部完成 ✅
目标：在 Axion 中构建 Runtime 层，使 CLI / API / TUI / App 统一消费 event stream

---

# 1. 背景

## 1.1 现状

Axion 当前架构：

```
RunCommand (CLI) ──→ AgentBuilder ──→ Agent.stream() ──→ SDKMessageOutputHandler
                                              ↓
ApiRunner (HTTP) ──→ AgentBuilder ──→ Agent.stream() ──→ EventBroadcaster (SSE)
```

问题：
- CLI 和 API 是两条独立的执行路径，各自手动处理 `SDKMessage`
- `RunOrchestrator` 里 ~350 行代码处理横切关注点（visual delta、seat monitoring、cost tracking、takeover、memory、review、curator）
- 这些横切关注点应该是 **event handler**，而不是 stream loop 里的 switch-case

## 1.2 目标架构

```
RunCommand (CLI) ──→ AxionRuntime ──→ AgentBuilder ──→ Agent.stream()
                          ↓                              ↓
ApiRunner (HTTP) ──→ AxionRuntime                EventBus (from SDK)
                          ↓                              ↓
                    EventBus.subscribe()          AgentEvents
                          ↓
               ┌──────────┼──────────┐
               ↓          ↓          ↓
          CLI Output   SSE Push   TUI / App
```

核心变化：
1. **AxionRuntime actor** 成为唯一执行入口
2. **EventBus**（来自 SDK）成为唯一事件通道
3. **横切关注点** 变成 event handler，不再写在 stream loop 里
4. **CLI / API / TUI** 都是 EventBus 的 subscriber

---

# 2. 目标

### Phase 1（v1）：Runtime 基础
- AxionRuntime actor：session lifecycle + agent execution
- 统一 event 消费：CLI 和 API 不再各自处理 SDKMessage
- Session resume：基于 SDK 的 SessionStore

### Phase 2：TUI / Observability
- Timeline-first TUI（消费 EventBus）
- Execution timeline 可视化
- Cost dashboard

### Phase 3：Workflow / Multi-Agent
- Workflow 定义（YAML-based）
- Multi-agent 编排（利用 SDK 的 SubAgent + Team）

---

# 3. Phase 1 改动项

按依赖顺序排列。

---

## A1. 引入 SDK EventBus

**优先级：P0**
**前置依赖：SDK Epic 1 完成**

### 改动

- 更新 `Package.swift` 的 SDK 依赖版本
- 在 AxionCore 或 AxionCLI 中创建共享的 `EventBus` 实例

### 位置

- `Sources/AxionCore/Runtime/EventBusProvider.swift`（新建）

### 验收标准

- SDK 的 `EventBus` 类型可以在 Axion 中 import 使用
- 编译通过

---

## A2. AxionRuntime Actor

**优先级：P0**
**前置依赖：A1**

### 改动

在 AxionCore 新建 `AxionRuntime` actor，作为 agent execution 的唯一入口。

```swift
// Sources/AxionCore/Runtime/AxionRuntime.swift

public actor AxionRuntime {
    private let eventBus: EventBus
    private let sessionStore: SessionStore

    // Session lifecycle
    public func createSession(task: String, config: AxionConfig) async throws -> String
    public func resumeSession(_ sessionId: String) async throws
    public func pauseSession(_ sessionId: String) async
    public func closeSession(_ sessionId: String) async throws

    // Execution
    public func start(sessionId: String) async throws
    public func sendMessage(sessionId: String, content: String) async throws

    // Query
    public func listSessions() async throws -> [SessionMetadata]
    public func getSession(_ sessionId: String) async throws -> SessionData?
}
```

### 设计要点

- 每个方法内部：创建 Agent → 设置 EventBus → 执行 → emit events
- `createSession` 不执行，只准备状态
- `start` 真正触发 agent 执行
- Session state machine：CREATED → RUNNING → PAUSED / COMPLETED / FAILED

### 关键：与现有 AgentBuilder 的关系

`AxionRuntime` 内部调用 `AgentBuilder.build()`，但：
- 在 `AgentOptions` 中注入 `eventBus`
- 不再由 RunCommand / ApiRunner 各自 build agent

### 验收标准

- `AxionRuntime.createSession()` 返回 session ID
- `AxionRuntime.start()` 触发 agent 执行
- Events 通过 EventBus emit
- Session 状态持久化到 SessionStore

---

## A3. EventHandler 体系

**优先级：P0**
**前置依赖：A2**

### 改动

将 `RunOrchestrator` 中的横切关注点提取为独立的 event handler：

```swift
// Sources/AxionCLI/Runtime/Handlers/

/// Cost tracking handler — subscribes to LLMCostEvent
class CostEventHandler { ... }

/// Visual delta handler — subscribes to ToolCompletedEvent (screenshot)
class VisualDeltaHandler { ... }

/// Seat monitor handler — subscribes to ToolStartedEvent (helper tools)
class SeatMonitorHandler { ... }

/// Memory processing handler — subscribes to AgentCompletedEvent
class MemoryProcessingHandler { ... }

/// Review handler — subscribes to AgentCompletedEvent
class ReviewHandler { ... }

/// Notification handler — subscribes to AgentCompletedEvent
class NotificationHandler { ... }

/// Trace handler — subscribes to all events
class TraceEventHandler { ... }
```

每个 handler 订阅特定 event 类型，收到 event 后执行自己的逻辑。

### 与现有代码的映射

| 现有代码位置 | 提取为 |
|-------------|--------|
| RunOrchestrator 里 cost 计算 | CostEventHandler |
| RunOrchestrator 里 visualDeltaTracker | VisualDeltaHandler |
| RunOrchestrator 里 seatMonitor | SeatMonitorHandler |
| RunOrchestrator 里 RunMemoryProcessor | MemoryProcessingHandler |
| RunOrchestrator 里 reviewOrchestrator | ReviewHandler |
| RunOrchestrator 里 sendDesktopNotification | NotificationHandler |
| RunOrchestrator 里 activateTerminal | NotificationHandler |
| TraceRecorder | TraceEventHandler |

### 验收标准

- 每个 handler 独立可测试
- handler 可以组合注册（CLI 注册全套，API 注册部分）
- RunOrchestrator 的 stream loop 被大幅简化

---

## A4. 改造 RunCommand

**优先级：P0**
**前置依赖：A2, A3**

### 改动

`RunCommand.run()` 从直接调 `AgentBuilder + RunOrchestrator` 改为：

```swift
// 改造前
let buildResult = try await AgentBuilder.build(buildConfig)
try await RunOrchestrator.execute(buildResult: buildResult, runConfig: ...)

// 改造后
let runtime = AxionRuntime.shared
let sessionId = try await runtime.createSession(task: task, config: config)
let eventStream = await runtime.eventBus.subscribe()
try await runtime.start(sessionId: sessionId)

// CLI 只做 event 渲染
for await event in eventStream {
    outputHandler.render(event)
}
```

### 过渡策略

不一次切换。先让 AxionRuntime 内部仍然使用 AgentBuilder + stream loop，只是：
1. 注入 EventBus
2. 在 stream loop 关键节点 emit events
3. CLI 同时消费 SDKMessage（现有逻辑）和 EventBus（新逻辑）

然后逐步将横切逻辑迁移到 EventHandler。

### 验收标准

- `axion run "task"` 功能不变
- CLI 输出同时通过 EventBus 可获取
- 现有单元测试 + 集成测试通过

---

## A5. 改造 ApiRunner

**优先级：P1**
**前置依赖：A4**

### 改动

与 RunCommand 类似，ApiRunner 改为通过 AxionRuntime：

```swift
// 改造后
let sessionId = try await runtime.createSession(task: task, config: config)
Task.detached {
    try await runtime.start(sessionId: sessionId)
}
// SSE 通过 EventBus → EventBroadcaster bridge 推送
```

### 验收标准

- HTTP API 行为不变
- SSE event 来源统一为 EventBus
- RunCoordinator 的职责逐步迁移到 AxionRuntime

---

## A6. Session Resume CLI

**优先级：P1**
**前置依赖：A2**

### 改动

新增 CLI 命令：

```bash
axion sessions              # 列出所有 session
axion resume <session-id>   # 恢复一个 session
```

### 依赖 SDK 能力

- `SessionStore.list()` — 列出 sessions
- `SessionStore.load()` — 加载 session messages
- `AgentOptions.sessionId` + `sessionStore` — agent 自动恢复对话历史

### 验收标准

- `axion sessions` 返回 session 列表
- `axion resume <id>` 恢复对话，agent 可以继续之前的上下文
- 跨进程 resume 可工作（先 CLI 退出，再 `axion resume`）

---

## A7. Skill / Daemon 集成

**优先级：P2**
**前置依赖：A2**

### 改动

- Skill 执行也通过 AxionRuntime
- Daemon 模式下 AxionRuntime 持续运行
- 新 session 可以通过 HTTP API 或 Unix socket 创建

### 验收标准

- `axion run "/skill-name task"` 通过 Runtime 执行
- Daemon 模式可以接受多个 session
- 现有 daemon 功能不变

---

# 4. 依赖关系图

```
SDK Epic 1 (AgentEvent + EventBus)
    ↓
A1 (引入 SDK EventBus)
    ↓
A2 (AxionRuntime Actor) ←── 核心
    ↓
A3 (EventHandler 体系)  ←── 拆解 RunOrchestrator
    ↓
A4 (改造 RunCommand)     P0  ──→ 功能不变，底层换 Runtime
A5 (改造 ApiRunner)      P1
A6 (Session Resume)      P1
A7 (Skill/Daemon 集成)   P2
```

---

# 5. 不做的事（Phase 1）

| 不做 | 原因 |
|------|------|
| TUI | Phase 2 |
| Workflow DAG | Phase 3，SDK 没有对应支持 |
| Multi-agent 编排 | Phase 3 |
| Replay | 需要 event 持久化，Phase 2 |
| macOS App | Phase 2 |
| Token streaming event | SDK P2，非阻塞 |

---

# 6. Phase 2 展望

完成 Phase 1 后，可以做：

### A8. Timeline-first TUI
- 基于 SwiftTUI 或纯 terminal escape code
- 消费 EventBus，渲染 execution timeline
- 不是 chat UI，是 timeline：
  ```
  [14:32:01] Agent Started — "refactor this repo"
  [14:32:03] Tool: GlobTool → 23 files matched
  [14:32:05] Tool: FileRead → Sources/AxionCore/Runtime.swift
  [14:32:08] Tool: FileEdit → modified
  [14:32:10] Agent Completed — 3 steps, 12s, $0.04
  ```

### A9. Event Log + Replay
- 将 EventBus events append-only 写入 SQLite
- `axion replay <session-id>` 重放 event log
- TUI 可以回放任意 session 的 execution timeline

### A10. Cost Dashboard
- 按日/周/月聚合 LLMCostEvent
- `axion stats` 显示成本分析

---

# 7. Phase 3 展望

### A11. Workflow Definition
- YAML 定义 workflow：planner → researcher → implementer → reviewer
- AxionRuntime 解析并按序执行

### A12. Multi-Agent Orchestration
- 利用 SDK 的 SubAgent + Team
- 通过 EventBus 观测所有 sub-agent 状态
- Timeline 可视化 agent tree

---

# 8. 风险

| 风险 | 缓解 |
|------|------|
| ~~SDK Epic 1 未完成~~ | ✅ SDK Epic 26-28 已完成 |
| RunOrchestrator 改造影响现有功能 | 渐进式：先并行（新旧同时运行），再切换 |
| Session resume 依赖 SDK 的 SessionStore 正确性 | 需要验证 SDK 的 session restore E2E test |
| 过度设计 | Phase 1 只做 A1-A4，后续按需启动 |

---

# 9. 建议的 Epic 拆分

**Axion Epic 24: AxionRuntime Core（A1 + A2）** → `docs/epics/epic-24-axion-runtime-core.md`
- 引入 SDK EventBus
- 实现 AxionRuntime actor（session lifecycle）
- Session state machine
- 单元测试

**Axion Epic 25: EventHandler 体系（A3）** → `docs/epics/epic-25-event-handlers.md`
- 从 RunOrchestrator 提取 event handler
- Cost / Memory / Review / Notification handler
- 单元测试

**Axion Epic 26: CLI + API 改造（A4 + A5）** → `docs/epics/epic-26-cli-api-refactor.md`
- RunCommand 改为通过 Runtime
- ApiRunner 改为通过 Runtime
- 渐进式切换（先并行，再替换）
- 验收：现有功能不变

**Axion Epic 27: Session Resume + Daemon（A6 + A7）** → `docs/epics/epic-27-session-resume-daemon.md`
- `axion sessions` / `axion resume`
- Daemon 模式集成 Runtime
- E2E 测试

---

# 10. 与 SDK 的交付节奏

```
Week 1-2:  SDK Epic 1 (AgentEvent + EventBus)
Week 2-3:  SDK Epic 2 (Agent Event Emitter)
    ↓ 同时（用 mock EventBus）
Week 1-3:  Axion Epic 1 (AxionRuntime Core)
Week 3-4:  Axion Epic 2 (EventHandler 体系)
Week 4-5:  Axion Epic 3 (CLI + API 改造)
Week 5-6:  Axion Epic 4 (Session Resume)
```

SDK Epic 1 和 Axion Epic 1 可以 **并行**，Axion 侧先用 mock EventBus 开发。
SDK Epic 2 完成后，Axion 替换 mock 为真实 EventBus。
