---
baseline_commit: 2b4d817
---

# Story 29.2: Task Serial Execution Queue

Status: done

## Story

As a Axion 用户,
I want 通过 Telegram 发送的任务能串行排队执行，执行中和排队状态可见,
So that 多个任务不会冲突抢占桌面，我知道每个任务的处理进度.

## Acceptance Criteria

1. **Given** Gateway 正在运行且无任务执行 **When** TelegramAdapter 收到白名单用户的文本消息 **Then** 任务通过 AxionRuntime 提交执行，TG 回复"任务开始执行: {task preview}"

2. **Given** Gateway 有一个任务正在执行 **When** TelegramAdapter 收到新的文本消息任务 **Then** 新任务加入串行队列，TG 回复"任务已排队 (队列: {count})"

3. **Given** 排队任务等待中 **When** 前一个任务完成 **Then** 自动取出队列中下一个任务开始执行，TG 通知"任务开始执行: {task preview}"

4. **Given** 任务执行完成（成功或失败）**When** 结果产生 **Then** 通过 TG 推送最终结果摘要（截断至 500 字符，长结果标注"...(完整结果 {total} 字符)"）

5. **Given** 任务执行超时（超过 `gatewayTaskTimeoutMinutes`，默认 10 分钟）**When** 超时触发 **Then** 任务被取消，TG 通知"任务超时已取消 ({timeout} 分钟)"

6. **Given** GatewayRunner 正在运行 **When** `getStatus()` 被调用 **Then** `activeTaskCount` 包含 TG 提交的正在执行的任务数

7. **Given** GatewayRunner stop() 被调用 **When** 有排队或执行中的任务 **Then** 等待当前任务完成（最多 30 秒），丢弃队列中剩余任务，TG 通知被丢弃任务的用户"Gateway 正在关闭，任务已取消"

8. **Given** TelegramAdapter 收到消息 **When** 消息为空文本或非文本（sticker/voice 等，图片除外）**Then** 静默忽略，不提交任务

## Tasks / Subtasks

- [x] Task 1: 创建 TaskSerialQueue (AC: #1, #2, #3, #5, #7)
  - [x] 1.1 创建 `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift`
  - [x] 1.2 实现 `enqueue(task:chatId:)` — 串行排队 + 状态通知
  - [x] 1.3 实现 `startProcessing()` — 启动消费循环
  - [x] 1.4 实现 `processNext()` — 取任务 + 执行 + 回调
  - [x] 1.5 实现超时取消 — `Task.sleep` + cancellation
  - [x] 1.6 实现 `cancelAll()` — 优雅关闭时丢弃排队任务
  - [x] 1.7 提取 `TaskSerialQueueProtocol` 用于测试注入

- [x] Task 2: 修改 TelegramAdapter 接入任务队列 (AC: #1, #2, #8)
  - [x] 2.1 添加 `taskQueue: any TaskSerialQueueProtocol` 依赖注入
  - [x] 2.2 修改 `processMessage` — 有文本时提交到队列而非回复"任务已收到"
  - [x] 2.3 空文本或非文本消息静默忽略

- [x] Task 3: 实现 TG 结果推送 (AC: #4, #5)
  - [x] 3.1 任务成功 → `sendReply` 推送结果摘要（500 字符截断）
  - [x] 3.2 任务失败 → `sendReply` 推送错误信息
  - [x] 3.3 任务超时 → `sendReply` 推送超时通知
  - [x] 3.4 排队通知和开始执行通知

- [x] Task 4: 集成到 GatewayRunner (AC: #6, #7)
  - [x] 4.1 GatewayRunner 添加 `taskSerialQueue` 属性
  - [x] 4.2 在 taskStarted/taskFinished 回调中同步队列状态
  - [x] 4.3 GatewayStartCommand 中创建 TaskSerialQueue 并注入到 TelegramAdapter
  - [x] 4.4 stop() 中调用 cancelAll()

- [x] Task 5: 单元测试 (AC: #1–#8)
  - [x] 5.1 测试 TaskSerialQueue 串行执行（mock executor）
  - [x] 5.2 测试排队 + FIFO 顺序
  - [x] 5.3 测试超时取消
  - [x] 5.4 测试 cancelAll 丢弃排队任务
  - [x] 5.5 测试 TelegramAdapter 提交任务到队列
  - [x] 5.6 测试非文本消息静默忽略
  - [x] 5.7 测试结果摘要截断（500 字符）
  - [x] 5.8 测试 GatewayRunner 集成（activeTaskCount 更新）

## Dev Notes

### 架构约束

**TaskSerialQueue 是 actor** — 串行化任务队列状态（排队数、执行状态）。与现有 `TaskQueue`（`Sources/AxionCLI/MCP/TaskQueue.swift`）模式一致。

**不直接复用 MCP TaskQueue** — MCP TaskQueue 是通用串行执行器（纯 `enqueue(closure)`），不支持：超时取消、chatId 关联、结果回调。TaskSerialQueue 封装了 TG 场景特有的排队/通知/超时逻辑，底层可参考 TaskQueue 的 `waitForCapacity` / `taskCompleted` continuation 模式。

**单用户串行** — PRD FR-5.2：同一时间最多 1 个任务执行。桌面操作不能并行（一个 agent 占用 Helper + 鼠标键盘）。

**每个任务创建独立 AxionRuntime** — D9 决策：避免状态交叉。通过 `DaemonRuntimeManaging.executeRun()` 执行。

### 需要修改的文件

**`Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift`**（112 行）

当前状态：`processMessage` 对文本消息回复"任务已收到"。有 `apiClient`、`allowedUsers`、`sendReply`。

本故事变更：
- init 新增 `taskQueue: any TaskSerialQueueProtocol` 参数
- `processMessage` 改为：有文本 → `taskQueue.enqueue(task: text, chatId: message.chat.id)`
- 无文本消息（sticker/voice 等）静默 return（当前已有 `guard message.text != nil`）
- 移除 MVP 的"任务已收到"硬编码回复

必须保留：pollLoop、isAuthorized、sendReply、splitMessage、statusInfo、start/stop 全部行为。

**`Sources/AxionCLI/Services/GatewayRunner.swift`**（197 行）

当前状态：有 `_activeTaskCount`、`taskStarted()`、`taskFinished()`、`_telegramAdapter`。

本故事变更：
- 添加 `private var _taskSerialQueue: (any TaskSerialQueueProtocol)?` 属性
- 添加 `func setTaskSerialQueue(_ queue: any TaskSerialQueueProtocol)`
- 在 `stop(graceful:)` 中调用 `await _taskSerialQueue?.cancelAll()`（在 adapter.stop 之前）
- taskStarted/taskFinished 已有，由 TaskSerialQueue 在执行前后调用 runner 的方法

必须保留：start/stop/taskStarted/taskFinished/getStatus/setTelegramAdapter/setStatusProviders 全部行为。

**`Sources/AxionCLI/Commands/GatewayCommand.swift`**（418 行）

当前状态：Telegram adapter 在 `GatewayStartCommand.run()` 中条件创建（196-222 行）。

本故事变更：
- 创建 `TaskSerialQueue`，注入 `runner`（用于 taskStarted/taskFinished）和 `runtimeManager`（用于 executeRun）和 `config`（用于超时配置）
- 将 `taskQueue` 注入到 `TelegramAdapter` init
- 调用 `await taskSerialQueue.startProcessing()`

必须保留：HTTP API server 配置、runHandler、signal handlers、status route 全部行为。

### 新增文件

```
Sources/AxionCLI/Services/Gateway/
└── TaskSerialQueue.swift    # Actor：串行任务队列 + 超时 + 通知（~200 行）

Tests/AxionCLITests/Services/Gateway/
└── TaskSerialQueueTests.swift    # 单元测试（~250 行）
```

### TaskSerialQueue 设计

```swift
// TaskSerialQueue.swift

protocol TaskSerialQueueProtocol: Sendable {
    func enqueue(task: String, chatId: Int64) async
    func startProcessing() async
    func cancelAll() async
    var pendingCount: Int { get }
    var isProcessing: Bool { get }
}

actor TaskSerialQueue: TaskSerialQueueProtocol {
    private struct PendingTask: Sendable {
        let task: String
        let chatId: Int64
    }

    private var queue: [PendingTask] = []
    private var isExecuting = false
    private var isShuttingDown = false

    private let runtimeManager: any DaemonRuntimeManaging
    private let config: AxionConfig
    private let runner: GatewayRunner
    private let replyHandler: @Sendable (Int64, String) async -> Void  // chatId, message

    init(
        runtimeManager: any DaemonRuntimeManaging,
        config: AxionConfig,
        runner: GatewayRunner,
        replyHandler: @Sendable @escaping (Int64, String) async -> Void
    ) { ... }

    func enqueue(task: String, chatId: Int64) async {
        guard !isShuttingDown else {
            await replyHandler(chatId, "Gateway 正在关闭，任务已取消")
            return
        }
        let pendingCount = queue.count
        queue.append(PendingTask(task: task, chatId: chatId))
        if isExecuting {
            await replyHandler(chatId, "任务已排队 (队列: \(pendingCount + 1))")
        }
        // If not currently executing, processNext will pick it up
    }

    func startProcessing() async {
        await processNext()
    }

    private func processNext() async {
        guard !queue.isEmpty else {
            isExecuting = false
            return
        }
        isExecuting = true
        let pending = queue.removeFirst()

        await replyHandler(pending.chatId, "任务开始执行: \"\(pending.task.prefix(50))\"")

        await runner.taskStarted()

        do {
            let timeoutMinutes = config.gatewayTaskTimeoutMinutes ?? 10.0
            let result = try await withThrowingTaskGroup(of: AxionRunResult.self) { group in
                group.addTask {
                    let buildConfig = AgentBuilder.BuildConfig.forAPI(
                        config: self.config,
                        task: pending.task,
                        request: nil
                    )
                    return try await self.runtimeManager.executeRun(
                        task: pending.task,
                        buildConfig: buildConfig,
                        eventBus: EventBus(),
                        runOverrides: .default
                    )
                }
                group.addTask {
                    try await _Concurrency.Task.sleep(nanoseconds: UInt64(timeoutMinutes * 60 * 1_000_000_000))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            // Success
            let summary = Self.summarize(result)
            await replyHandler(pending.chatId, summary)
        } catch is CancellationError {
            await replyHandler(pending.chatId, "任务超时已取消 (\(Int(timeoutMinutes)) 分钟)")
        } catch {
            await replyHandler(pending.chatId, "任务执行失败: \(error.localizedDescription)")
        }

        await runner.taskFinished()
        await processNext()
    }

    func cancelAll() async {
        isShuttingDown = true
        for pending in queue {
            await replyHandler(pending.chatId, "Gateway 正在关闭，任务已取消")
        }
        queue.removeAll()
    }

    var pendingCount: Int { queue.count }
    var isProcessing: Bool { isExecuting }

    private static func summarize(_ result: AxionRunResult) -> String {
        let maxLen = 500
        // Build summary from result fields
        var summary = "✅ 任务完成 (\(result.totalSteps) 步, \(result.durationMs / 1000)s)"
        if let error = result.errorMessage {
            summary = "❌ 任务失败: \(error)"
        }
        guard summary.count > maxLen else { return summary }
        return "\(summary.prefix(maxLen))...(完整结果 \(summary.count) 字符)"
    }
}
```

**关键设计决策：**
- `replyHandler` 是注入闭包，内部调用 `TelegramAdapter.sendReply` — 避免队列直接持有 adapter 引用（防止循环依赖）
- `runner.taskStarted()` / `runner.taskFinished()` 在执行前后调用 — 更新 activeTaskCount
- 超时用 `withThrowingTaskGroup` race 模式 — 执行任务 vs sleep，先完成者赢
- `cancelAll` 只丢弃排队任务，不取消执行中任务（由 GatewayRunner.stop 的 30 秒等待处理）

### GatewayStartCommand 集成

在 `GatewayCommand.swift` 的 `GatewayStartCommand.run()` 中（Telegram adapter setup 区域，196 行之后）：

```swift
// 创建 TaskSerialQueue（在 adapter 创建之前或同时）
let taskSerialQueue = TaskSerialQueue(
    runtimeManager: runtimeManager,
    config: config,
    runner: runner,
    replyHandler: { [weak adapter] chatId, message in
        // adapter 可能还没创建，用 guard 处理
        guard let adapter else { return }
        await adapter.sendReply(message, to: chatId)
    }
)

await runner.setTaskSerialQueue(taskSerialQueue)

// 创建 adapter 时注入 queue
let adapter = TelegramAdapter(
    apiClient: tgClient,
    allowedUsers: allowedUsers,
    taskQueue: taskSerialQueue  // 新增参数
)

// 启动队列处理
await taskSerialQueue.startProcessing()
```

**注意循环引用：** `taskSerialQueue` 的 `replyHandler` 闭包捕获 `adapter`（weak），`adapter` 持有 `taskQueue`（protocol，不强引用 queue）。实际上 TelegramAdapter 持有的是 protocol 引用，不是具体 actor，不会循环。但 replyHandler 闭包必须用 `[weak adapter]` 因为 TaskSerialQueue 可能比 TelegramAdapter 活得更久。

### TelegramAdapter 变更

```swift
actor TelegramAdapter {
    private let apiClient: any TGAPIClientProtocol
    private let allowedUsers: Set<String>
    private let taskQueue: (any TaskSerialQueueProtocol)?  // 新增，可选（无 TG 时为 nil）
    // ... 其他不变

    init(
        apiClient: any TGAPIClientProtocol,
        allowedUsers: Set<String>,
        taskQueue: (any TaskSerialQueueProtocol)? = nil  // 新增，默认 nil
    ) {
        self.apiClient = apiClient
        self.allowedUsers = allowedUsers
        self.taskQueue = taskQueue
    }

    private func processMessage(_ message: TGMessage) async {
        guard let userId = message.from?.id else { return }
        guard isAuthorized(userId: userId) else { return }
        guard let text = message.text, !text.isEmpty else { return }  // 空/非文本静默

        if let queue = taskQueue {
            fputs("[axion] Telegram task submitted: \"\(text.prefix(50))\"\n", stderr)
            await queue.enqueue(task: text, chatId: message.chat.id)
        } else {
            // 无队列时回退到 MVP 行为
            await sendReply("任务已收到", to: message.chat.id)
        }
    }
    // ... 其余不变
}
```

### 测试要求

**框架：** Swift Testing（`import Testing`、`@Suite`、`@Test`、`#expect`）
**测试目录：** `Tests/AxionCLITests/Services/Gateway/`

**Mock 策略：**
- `TaskSerialQueueProtocol` — Mock 实现，追踪 enqueue/startProcessing/cancelAll 调用
- `DaemonRuntimeManaging` — Mock 实现，返回预设 AxionRunResult（或延迟后返回）
- `GatewayRunner` — 使用真实 actor（无需 mock）
- replyHandler — 注入闭包，收集 (chatId, message) 对
- TelegramAdapter — 使用 `TGAPIClientProtocol` Mock（已有）

**运行测试：** `swift test --filter "AxionCLITests.Services.Gateway"`

### 前置 Story 经验

- **L1 (Epic 28):** Dev Notes 中识别的反模式需要提供正确实现路径
- **L3 (Epic 28):** AC 指定的行为必须先实现再验证
- **C2 (Epic 28):** runHandler 从 ServerCommand 复制粘贴 — 本故事不涉及 runHandler 修改
- **Story 29.1 review:** `nonisolated(unsafe)` 用于 actor 外同步读取状态 — 如有需要复用此模式
- **Story 29.1 review:** 4xx 错误不重试 — 已在 TGAPIClient 中修复

### 安全规则

- 未授权消息静默丢弃（反模式 #15）— processMessage 的 isAuthorized 检查在 enqueue 之前
- 任务执行结果不包含 API Key（NFR-2）
- 任务超时取消避免资源泄漏

### 项目结构说明

- 新建 `Sources/AxionCLI/Services/Gateway/` 目录（1 个文件）
- 新建 `Tests/AxionCLITests/Services/Gateway/` 目录（测试文件）
- 修改 `TelegramAdapter.swift`（添加 taskQueue 依赖注入 + 修改 processMessage）
- 修改 `GatewayRunner.swift`（添加 taskSerialQueue 持有 + cancelAll in stop）
- 修改 `GatewayCommand.swift`（创建 TaskSerialQueue + 注入）
- 符合 `AxionCLI/Services/` 的服务层组织模式

### References

- [Source: _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md#FR-5.1 — TG 任务通过 AxionRuntime.execute() 执行]
- [Source: _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md#FR-5.2 — 任务并发限制=1]
- [Source: _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md#FR-5.3 — 任务排队 + TG 通知]
- [Source: _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md#FR-5.4 — 任务超时 10 分钟]
- [Source: _bmad-output/planning-artifacts/architecture.md#D9 — Gateway 进程模型 + ConcurrencyLimiter=1]
- [Source: _bmad-output/planning-artifacts/architecture.md#D10 — TelegramAdapter 通信模式]
- [Source: _bmad-output/planning-artifacts/architecture.md#TaskQueue (SDK ConcurrencyLimiter = 1) — 串行执行]
- [Source: _bmad-output/project-context.md#反模式 #14 — TG bot token 不写入 config.json]
- [Source: _bmad-output/project-context.md#反模式 #15 — 未授权 TG 消息静默丢弃]
- [Source: _bmad-output/implementation-artifacts/epic-28-retro-2026-05-29.md#L1 — Dev Notes 反模式警告]
- [Source: _bmad-output/implementation-artifacts/29-1-telegramadapter-core-communication.md — 前置 Story 实现]
- [Source: Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift — 当前 adapter 实现]
- [Source: Sources/AxionCLI/Services/GatewayRunner.swift — 当前 runner 实现]
- [Source: Sources/AxionCLI/Commands/GatewayCommand.swift — 当前 command 实现]
- [Source: Sources/AxionCLI/MCP/TaskQueue.swift — 参考 continuation 模式]
- [Source: Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift — executeRun 接口]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

No blocking issues encountered.

### Completion Notes List

- TaskSerialQueue actor created with protocol abstraction for test injection
- enqueue() queues tasks and sends "queued" notification when busy, "started" notification when first in queue
- processNext() recursively processes queue: execute → reply result → next
- Timeout implemented via withThrowingTaskGroup race pattern (task vs sleep)
- cancelAll() sets shutdown flag, notifies all queued users, clears queue
- summarize() truncates at 500 chars with overflow indicator
- TelegramAdapter updated: optional taskQueue injection, processMessage routes to queue or falls back to MVP reply
- Empty/non-text messages silently ignored (guard let text, !text.isEmpty)
- GatewayRunner: added _taskSerialQueue property, setTaskSerialQueue(), cancelAll() in stop() before adapter.stop()
- GatewayStartCommand: creates TaskSerialQueue with replyHandler closure (weak adapter ref), injects into runner and adapter
- 10 TaskSerialQueue tests: serial execution, queuing, FIFO, timeout, cancelAll, shutdown rejection, start/complete notifications, result truncation
- 4 TelegramAdapter tests: queue submission, empty text ignored, nil text ignored, MVP fallback
- All 440 unit tests pass (0 regressions)

### Change Log

- 2026-05-29: Implemented TaskSerialQueue + integrated with TelegramAdapter and GatewayRunner. All tasks complete, 14 new tests passing.
- 2026-05-29: **Senior Developer Review (AI)** — 0 CRITICAL, 3 HIGH, 3 MEDIUM, 1 LOW. Fixed: (1) recursive processNext → while loop (HIGH), (2) summarize() private → internal + removed duplicated test helper (HIGH), (3) duplicate timeoutMinutes read eliminated (MEDIUM), (4) File List updated with deleted/modified test files (HIGH). Noted: timeout cooperative cancellation limitation (MEDIUM-2). All 28 tests pass post-fix.

### File List

- Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift (new)
- Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift (modified)
- Sources/AxionCLI/Services/GatewayRunner.swift (modified)
- Sources/AxionCLI/Commands/GatewayCommand.swift (modified)
- Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift (new)
- Tests/AxionCLITests/Services/Telegram/TelegramAdapterTests.swift (modified)
- Tests/AxionCLITests/Services/Telegram/GatewayTelegramIntegrationTests.swift (deleted — tests migrated to TaskSerialQueueTests)
- Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift (modified — MockTGAPIClient busy-loop fix)
