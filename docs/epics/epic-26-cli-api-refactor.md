# Axion Epic 26: CLI + API 改造

> **状态：待开发**
> **优先级：P0**
> **前置依赖：Epic 24（AxionRuntime Core）+ Epic 25（EventHandler 体系）**
> **Roadmap：** `docs/agent-runtime-roadmap.md` → A4 + A5

## 背景与动机

Epic 24 创建了 `AxionRuntime` actor（统一入口、RunState、Session 持久化），Epic 25 提取了 7 个 `EventHandler`。本 Epic 将 CLI 和 API 的执行路径改为通过 `AxionRuntime`，让它们成为 EventBus 的 subscriber。

改造后：
- `RunCommand` 不再直接调用 `AgentBuilder` + `RunOrchestrator`
- `ApiRunner` 不再手动 emit SSE event
- 两者都通过 `AxionRuntime` 执行 agent，通过 EventBus 消费事件

---

### Story 26.1: RunCommand 改造为通过 AxionRuntime 执行

As a CLI 用户,
I want `axion run "task"` 仍然正常工作,
So that CLI 功能不变但底层通过 Runtime 执行.

**实施：**

1. 修改 `Sources/AxionCLI/Commands/RunCommand.swift`

```swift
// 改造前
let buildResult = try await AgentBuilder.build(buildConfig)
try await RunOrchestrator.execute(buildResult: buildResult, runConfig: ...)

// 改造后
let runtime = AxionRuntime()
// 注册 CLI 需要的 handlers
runtime.registerHandler(CostEventHandler())
runtime.registerHandler(VisualDeltaHandler(noVisualDelta: config.noVisualDelta))
runtime.registerHandler(SeatMonitorHandler(seatMode: config.sharedSeatMode))
runtime.registerHandler(MemoryProcessingHandler(memoryStore: memoryStore, memoryDir: memoryDir))
runtime.registerHandler(ReviewHandler(reviewOrchestrator: reviewOrchestrator, config: config))
runtime.registerHandler(NotificationHandler())
runtime.registerHandler(TraceEventHandler())

let sessionId = try await runtime.createSession(task: task, config: config)
let (_, eventStream) = await runtime.subscribe()

// CLI 消费 event stream 进行渲染
for await event in eventStream {
    outputHandler.render(event)
}

try await runtime.start(sessionId: sessionId)
```

2. 新增 `EventOutputHandler`（或扩展现有 `SDKMessageOutputHandler`），将 `AgentEvent` 映射为 CLI 渲染输出

**AgentEvent → CLI 输出映射规则：**

| AgentEvent | CLI 输出行为 | 说明 |
|------------|------------|------|
| `AgentStartedEvent` | 无输出 | agent 开始，静默 |
| `AgentCompletedEvent` | 输出 `resultText`（如有） | agent 最终回答 |
| `AgentFailedEvent` | 输出 `error` 到 stderr | 错误信息 |
| `AgentInterruptedEvent` | 输出 "\n[interrupted]" 到 stderr | 中断提示 |
| `ToolStartedEvent` | 输出 tool 指示符 | 根据工具类型显示 spinner 或名称 |
| `ToolCompletedEvent` | 更新 tool 输出 | 显示结果摘要（文件路径、搜索结果数等） |
| `ToolFailedEvent` | 输出 error 到 stderr | 工具执行失败 |
| `LLMCostEvent` | 无输出（CostEventHandler 处理） | 成本在结束时统一输出 |
| `SessionCreatedEvent` | 无输出 | 内部事件 |
| `SessionClosedEvent` | 无输出 | 内部事件 |

**注意**：过渡期（Phase A/B），CLI 同时消费 SDKMessage（现有输出逻辑）和 EventBus（新逻辑）。EventOutputHandler 在 Phase C（移除旧代码后）才成为唯一的渲染路径。

3. 保持 SIGINT 处理、lock 管理、dryrun 等现有行为

**过渡策略（关键）：**

不一次切换。采用 **并行验证** 策略：
1. **Phase A**：RunCommand 仍然使用现有路径（AgentBuilder + RunOrchestrator），但同时创建 AxionRuntime 并行运行。对比两者的 event 输出是否一致。
2. **Phase B**：验证一致后，切换到 AxionRuntime 路径，但保留旧路径作为 fallback。
3. **Phase C**：确认稳定后，移除 RunOrchestrator 中的横切关注点代码。

**Acceptance Criteria：**

**Given** `axion run "echo hello"` 被执行
**When** agent 完成
**Then** CLI 输出与改造前完全一致

**Given** `axion run "task"` 被执行
**When** SIGINT 被发送
**Then** agent 被 interrupt，EventBus 收到 `AgentInterruptedEvent`

**Given** `axion run --json "task"` 被执行
**When** agent 执行
**Then** JSON 输出格式与改造前一致

**Given** `axion run --dryrun "task"` 被执行
**When** agent 执行
**Then** dryrun 行为与改造前一致

---

### Story 26.2: ApiRunner 改造为通过 AxionRuntime 执行

As a API 用户,
I want HTTP API 的 SSE 推送行为不变,
So that API 消费者不需要做任何改动.

**实施：**

1. 修改 `Sources/AxionCLI/Commands/ServerCommand.swift` 中的 `server.runHandler` 闭包
2. 修改 `Sources/AxionCLI/API/ApiRunner.swift`

**当前架构：**
```
ServerCommand → server.runHandler 闭包 → ApiRunner → AgentBuilder → agent.stream()
                                                       ↓ 手动 emit SSE
                                                 eventBroadcaster.emit()
```

**改造后架构：**
```
ServerCommand → server.runHandler 闭包 → AxionRuntime → AgentBuilder → agent.stream()
                                              ↓                              ↓ EventBus
                                        EventBusBridge ──→ eventBroadcaster ──→ SSE
```

3. 关键点：Axion 的 `ServerCommand` 已经通过 `server.runHandler` **覆盖了** SDK 的默认 run handler。改造只需要在 `runHandler` 闭包内部使用 AxionRuntime 替代直接调用 ApiRunner。

```swift
// ServerCommand.runHandler 改造后
server.runHandler = { task, runId, eventBroadcaster in
    let runtime = AxionRuntime()
    let sessionId = try await runtime.createSession(task: task, config: config)

    // SSE 通过 EventBusBridge 自动推送
    let bridge = EventBusBridge(
        eventBus: runtime.eventBus,
        broadcaster: eventBroadcaster,
        runId: runId
    )
    await bridge.start(onComplete: { /* 更新 RunCoordinator 状态 */ })

    // 注册 API 需要的 handlers（cost + trace，不需要 visual delta / seat monitor）
    runtime.registerHandler(CostEventHandler())
    runtime.registerHandler(TraceEventHandler())

    // 启动 agent
    try await runtime.start(sessionId: sessionId)
}
```

4. 从 `ApiRunner` 移除 `processStream()` 中的手动 SSE emit 代码（~232-238 行、~252-259 行）

**从 ApiRunner 迁移的代码：**
- `eventBroadcaster.emit(runId:event:)` 调用（~234、253 行）→ 由 `EventBusBridge` 自动处理
- `processStream()` 方法可以大幅简化或移除
- `processStreamFromAsyncStream()` 方法同样简化

**API 与 CLI 注册不同的 handler 组合：**
- **CLI**：注册全套 7 个 handler（cost、visual delta、seat monitor、memory、review、notification、trace）
- **API**：只注册 cost + trace（无桌面环境，不需要 visual delta、seat monitor、notification 等）

**Acceptance Criteria：**

**Given** HTTP POST `/runs` 创建一个 run
**When** agent 执行
**Then** SSE 客户端收到与改造前一致的事件序列（step_started、step_completed、run_completed）

**Given** agent 执行了 3 个 tool 调用
**When** 检查 SSE 推送的事件
**Then** 收到 3 个 `step_started` + 3 个 `step_completed`

**Given** SSE 客户端断开连接
**When** agent 仍在执行
**Then** agent 不受影响，继续执行（EventBusBridge 使用 `bufferingNewest(100)` 缓冲）

---

### Story 26.3: 移除旧代码并清理

As a Axion 开发者,
I want 在验证一致性后移除 RunOrchestrator 中的横切关注点代码,
So that 代码库更简洁、维护更容易.

**实施：**

1. 从 `RunOrchestrator` 移除已迁移到 EventHandler 的代码：
   - Visual delta tracking 代码（~98-170 行）
   - Seat monitoring 代码（~107-213 行）
   - Cost tracking 代码（~232-238 行）
   - Memory processing 代码（~243-263 行）
   - Review + Curator 代码（~266-357 行）
   - Notification + activateTerminal 代码（~364-377 行）
2. `RunOrchestrator` 保留的职责（如果还存在）：
   - Lock 管理
   - SIGINT 处理
   - Output handler 创建
   - Dryrun 模式
3. 或者：如果 RunOrchestrator 只剩下薄包装，考虑直接移除，让 RunCommand 直接调用 AxionRuntime

4. 从 `ApiRunner` 移除手动 SSE emit 代码，只保留 HTTP API 特有的逻辑（RunCoordinator、status mapping）

**Acceptance Criteria：**

**Given** 旧代码已移除
**When** 运行现有测试套件
**Then** 所有测试通过

**Given** `axion run "task"` 被执行
**When** agent 完成
**Then** 行为与改造前一致

---

## Story 间的依赖关系

```
26.1 RunCommand 改造 (P0)
  │
  └──► 26.2 ApiRunner 改造 (P0)
        │
        └──► 26.3 移除旧代码 (P0)
```

建议按顺序执行：26.1 先行（CLI 更容易测试），验证一致后做 26.2（API），最后 26.3 清理。

---

## 实现优先级

| Story | 优先级 | 理由 |
|-------|--------|------|
| 26.1 RunCommand 改造 | P0 | CLI 是主要入口，改造风险可控 |
| 26.2 ApiRunner 改造 | P0 | API 是对外接口，需要保持兼容 |
| 26.3 移除旧代码 | P0 | 减少代码重复，降低维护成本 |

---

## 关键设计约束

- **功能不变** — `axion run` 和 HTTP API 的行为必须与改造前完全一致
- **渐进式** — 先并行验证，再切换
- **不改 SDK** — SDK 的 EventBus + EventBusBridge 不需要修改
- **保留 AgentBuilder** — AxionRuntime 内部调用 AgentBuilder，builder 本身不变
- **EventBusBridge 复用** — ApiRunner 的 SSE 推送直接使用 SDK 的 `EventBusBridge` actor
- **Handler 组合差异** — CLI 注册全套 7 个 handler，API 只注册 cost + trace（无桌面环境）

## 现有代码参考

| 文件 | 行数 | 改造后 |
|------|------|--------|
| `RunCommand.swift` | 120 行 | 改为调用 AxionRuntime |
| `RunOrchestrator.swift` | 669 行 | 大幅简化或移除 |
| `ApiRunner.swift` | 342 行 | 简化，移除手动 SSE emit |
| `ServerCommand.swift` | ~59-93 行 | runHandler 内使用 AxionRuntime |
| `AgentBuilder.swift` | 492 行 | 不变 |

## 测试策略

- **Story 26.1 验证**：对比改造前后的 CLI 输出（包括 stdout、stderr）
- **Story 26.2 验证**：对比改造前后的 SSE event 序列
- **回归测试**：现有单元测试 + 集成测试全部通过
- **手动测试**：`axion run` 的各种参数组合（--json、--dryrun、--fast、--noMemory 等）
