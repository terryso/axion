# Axion Epic 27: Session Resume + Daemon 集成

> **状态：待开发**
> **优先级：P1**
> **前置依赖：Epic 24（AxionRuntime Core）+ Epic 26（CLI + API 改造）**
> **Roadmap：** `docs/agent-runtime-roadmap.md` → A6 + A7

## 背景与动机

SDK 的 `SessionStore` 已支持 session 持久化（save/load/fork/list）。Axion 的 `AxionRuntime`（Epic 24）通过 `SessionStore(sessionsDir: "~/.axion/sessions")` 配置存储目录，并使用 `axion-state.json` 叠加 Axion 特有的运行时状态。

本 Epic 为 Axion 添加：
1. **Session Resume CLI** — 跨进程恢复之前的 session
2. **Daemon 集成** — AxionRuntime 在 daemon 模式下持续运行

**Session 持久化层次（Epic 24 建立的基础）：**

| 层次 | 文件 | 内容 | 管理者 |
|------|------|------|--------|
| SDK SessionStore | `~/.axion/sessions/{id}/transcript.json` | 对话历史 + SessionMetadata（id, cwd, model, createdAt, messageCount, ...） | SDK 自动（persistSession=true） |
| Axion overlay | `~/.axion/sessions/{id}/axion-state.json` | status, totalSteps, durationMs | AxionRuntime |
| 两者关系 | 同一目录 | 通过 sessionId 关联 | Axion 的 `listSessions()` 调用 SDK 的 `sessionStore.list()` + 读取 overlay |

---

### Story 27.1: Session List CLI 命令

As a CLI 用户,
I want 列出所有历史 session,
So that 可以查看之前的执行记录并选择恢复.

**实施：**

1. 新增 `axion sessions` 命令：

```swift
// Sources/AxionCLI/Commands/SessionsCommand.swift
struct SessionsCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List agent sessions"
    )

    @Flag(name: .shortAndLong, help: "Show only active sessions")
    var active = false

    @Option(name: .shortAndLong, help: "Limit number of results")
    var limit: Int = 20

    func run() async throws {
        let runtime = AxionRuntime()
        let sessions = try await runtime.listSessions()
        let filtered = active ? sessions.filter { $0.status == .running } : sessions
        let limited = Array(filtered.prefix(limit))
        renderSessionTable(limited)
    }
}
```

2. 依赖 `AxionRuntime.listSessions()` → 返回 `[SessionInfo]`
   - 底层调用 SDK 的 `sessionStore.list()` 获取 `[SessionMetadata]`
   - 并行读取每个 session 目录下的 `axion-state.json` 获取 Axion overlay
   - 合并为 `SessionInfo`

3. 输出格式：

```
SESSION_ID                          TASK                    STATUS      STEPS  DURATION  CREATED
a1b2c3d4-...                        "refactor auth module"  COMPLETED   12     34s       2026-05-27 14:32
e5f6g7h8-...                        "fix login bug"         FAILED      5      12s       2026-05-27 13:15
```

**Acceptance Criteria：**

**Given** 有 5 个历史 session（SDK transcript + Axion state 已持久化）
**When** 运行 `axion sessions`
**Then** 显示所有 5 个 session 的摘要信息（task 来自 SDK 的 `firstPrompt`，status/steps 来自 axion-state.json）

**Given** 有 3 个 session，1 个 status=RUNNING
**When** 运行 `axion sessions --active`
**Then** 只显示 1 个 active session

---

### Story 27.2: Session Resume CLI 命令

As a CLI 用户,
I want 恢复一个之前的 session 继续 agent 对话,
So that 不需要重新开始，可以在之前的上下文上继续.

**实施：**

1. 新增 `axion resume` 命令：

```swift
// Sources/AxionCLI/Commands/ResumeCommand.swift
struct ResumeCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume a previous agent session"
    )

    @Argument(help: "Session ID to resume")
    var sessionId: String

    @Flag(name: .shortAndLong, help: "Fast mode")
    var fast: Bool = false

    func run() async throws {
        let runtime = AxionRuntime()
        // 注册 handlers（与 RunCommand 相同的 CLI 全套）
        runtime.registerHandler(CostEventHandler())
        runtime.registerHandler(VisualDeltaHandler(noVisualDelta: config.noVisualDelta))
        // ... 其他 handlers

        let (_, eventStream) = await runtime.subscribe()

        // 恢复 session
        try await runtime.resumeSession(sessionId, config: axionConfig)

        // 消费 event stream（与 RunCommand 相同的渲染逻辑）
        for await event in eventStream {
            eventOutputHandler.render(event)
        }
    }
}
```

2. `AxionRuntime.resumeSession()` 实现：
   - 从 `axion-state.json` 验证 session 存在且状态允许恢复（COMPLETED / FAILED / INTERRUPTED）
   - **SDK session restore 流程**：
     1. `AgentOptions.sessionId = sessionId` — 告诉 SDK 恢复哪个 session
     2. `AgentOptions.sessionStore = self.sessionStore` — SDK 从 `transcript.json` 加载历史 messages
     3. SDK 在 `agent.stream(prompt:)` 时自动带上历史 messages 继续对话
     4. **不需要设置 `resumeSessionAt`** — 此字段是按 message UUID 截断历史用的，不是恢复整个 session
   - 更新 `axion-state.json` 状态为 RUNNING
   - 启动 agent stream 并分发 events

```swift
public actor AxionRuntime {
    public func resumeSession(_ sessionId: String, config: AxionConfig) async throws {
        // 1. 验证 session 存在
        guard let sessionData = try sessionStore.load(sessionId: sessionId) else {
            throw AxionError.sessionNotFound(sessionId)
        }

        // 2. 验证状态允许恢复
        let axionState = try loadAxionState(sessionId: sessionId)
        guard axionState.status != .running else {
            throw AxionError.sessionAlreadyRunning(sessionId)
        }

        // 3. 更新 axion-state.json
        try saveAxionState(sessionId: sessionId, status: .running)

        // 4. 构建带 session 恢复的 agent
        var buildConfig = BuildConfig.forCLI(/* ... */)
        buildConfig.options.sessionId = sessionId       // SDK 从此 session 加载历史
        buildConfig.options.sessionStore = sessionStore  // SDK 自动 load + save
        // 不设置 resumeSessionAt — 它是按 message UUID 截断历史用的
        // eventBus 已注入

        // 5. 执行 agent（与 start() 相同的内部流程）
        let agent = try AgentBuilder.build(buildConfig)
        // ... consume stream, dispatch events
    }
}
```

> **SDK session restore 语义说明：**
> - `sessionId` + `sessionStore`：SDK 在 `agent.stream(prompt:)` 时自动加载历史 messages，并在执行后自动保存
> - `resumeSessionAt`：可选，按 message UUID 截断历史（用于"回退到某一步重试"），恢复整个 session 不需要设置
> - Resume 后的 agent 调用 `agent.stream(prompt: "继续之前的任务")` — 用户通过 CLI 参数提供新的 prompt

**Acceptance Criteria：**

**Given** 之前有一个 COMPLETED 的 session（SDK transcript + axion-state.json 都存在）
**When** 运行 `axion resume <session-id>`
**Then** SDK 加载历史 messages，agent 在之前的上下文上继续对话

**Given** 之前有一个 FAILED 的 session
**When** 运行 `axion resume <session-id>`
**Then** agent 恢复该 session 的对话历史，可以继续

**Given** 一个不存在的 session ID
**When** 运行 `axion resume <invalid-id>`
**Then** 显示错误信息 "Session not found"

**Given** 一个 RUNNING 状态的 session
**When** 运行 `axion resume <running-session-id>`
**Then** 显示错误信息 "Session is already running"

---

### Story 27.3: Daemon 模式 AxionRuntime 集成

As a Axion 开发者,
I want AxionRuntime 在 daemon 模式下持续运行,
So that 可以通过 HTTP API 或 Unix socket 接受新 session.

**实施：**

1. 修改现有 daemon 入口，使用 `AxionRuntime` 替代直接使用 `AgentBuilder`
2. daemon 启动时创建一个长期存活的 `AxionRuntime` 实例（一次性 handler 注册）
3. 新 session 通过 HTTP API 创建（复用 Epic 26 Story 26.2 的 `runHandler` 改造）
4. 多个 session 可以并发执行（每个 session 一个 agent，共享 EventBus）

```swift
// Daemon 启动
let runtime = AxionRuntime()
// 一次性注册 API handler 组合
runtime.registerHandler(CostEventHandler())
runtime.registerHandler(TraceEventHandler())

// server.runHandler 收到 run 请求时
server.runHandler = { task, runId, eventBroadcaster in
    let sessionId = try await runtime.createSession(task: task, config: config)

    let bridge = EventBusBridge(
        eventBus: runtime.eventBus,
        broadcaster: eventBroadcaster,
        runId: runId
    )
    await bridge.start(onComplete: { /* 更新 RunCoordinator 状态 */ })

    // 不需要重新注册 handler（已在 daemon 启动时注册）
    Task.detached {
        try await runtime.start(sessionId: sessionId)
    }
}

let server = AgentHTTPServer()
try await server.start()
```

**与 Epic 26 的关系：**
- Epic 26 Story 26.2 已将 `runHandler` 改为使用 AxionRuntime
- 本 Story 将 daemon 模式的入口也统一到 AxionRuntime
- daemon 的 handler 注册与 Epic 26 一致（API handler 组合：cost + trace）

**Daemon 模式下 AxionRuntime 的生命周期管理：**
- **启动**：创建 AxionRuntime + 注册 handler + 启动 HTTP server
- **运行**：每个 HTTP run 请求 → `createSession()` + `start()`，共享同一组 handler
- **Shutdown**：优雅关闭所有正在执行的 session，等待 handler 完成

**Acceptance Criteria：**

**Given** daemon 模式启动
**When** 通过 HTTP API 创建多个 run
**Then** 每个 run 通过 AxionRuntime 执行，互不干扰

**Given** daemon 运行中
**When** 运行 `axion sessions`
**Then** 可以看到 daemon 中正在执行的 session

---

### Story 27.4: Skill 执行通过 AxionRuntime

As a Axion 开发者,
I want Skill 执行也通过 AxionRuntime,
So that skill 的 event 也统一通过 EventBus 消费.

**实施：**

1. `axion run "/skill-name task"` 的 skill 执行路径改为通过 AxionRuntime
2. Skill agent 与普通 agent 共享同一个 AxionRuntime 实例
3. Skill 的 event 通过 EventBus emit，可以被 trace handler 等记录
4. Skill 使用的 `BuildConfig.forSkillExecution` 仍然由 AgentBuilder 处理，AxionRuntime 包装调用

**Acceptance Criteria：**

**Given** AxionRuntime 已配置
**When** 执行 `axion run "/my-skill do something"`
**Then** skill 通过 AxionRuntime 执行，EventBus 收到 skill 的 agent event

---

## Story 间的依赖关系

```
27.1 Session List CLI (P1)
  │
  └──► 27.2 Session Resume CLI (P1)
        │
        └──► 27.3 Daemon 集成 (P2)
              │
              └──► 27.4 Skill 通过 Runtime (P2)
```

---

## 实现优先级

| Story | 优先级 | 理由 |
|-------|--------|------|
| 27.1 Session List | P1 | resume 的前提 |
| 27.2 Session Resume | P1 | 核心功能 |
| 27.3 Daemon 集成 | P2 | 现有 daemon 功能增强 |
| 27.4 Skill 通过 Runtime | P2 | 统一执行路径 |

---

## 关键设计约束

- **跨进程 resume** — session 数据通过 SDK SessionStore 持久化（`~/.axion/sessions/` 目录），Axion overlay 在同目录下
- **不改 SDK** — session restore 使用 SDK 现有 API（`AgentOptions.sessionId` + `sessionStore` + `resumeSessionAt`）
- **向后兼容** — 现有 `axion run`、`axion daemon`、`axion skill` 不受影响
- **多 session 并发** — daemon 模式下 AxionRuntime 支持多个 session 同时运行
- **Session 目录** — 使用 `~/.axion/sessions/`（通过 SDK `SessionStore(sessionsDir:)` 设置），SDK transcript 和 Axion state 在同一目录下
- **Handler 跨 session 复用** — daemon 模式下 handler 不重新创建，terminal event 时自重置

## 文件位置

| 文件 | 目录 |
|------|------|
| SessionsCommand.swift | `Sources/AxionCLI/Commands/SessionsCommand.swift` |
| ResumeCommand.swift | `Sources/AxionCLI/Commands/ResumeCommand.swift` |
