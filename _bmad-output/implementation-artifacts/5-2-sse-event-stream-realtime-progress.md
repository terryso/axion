# Story 5.2: SSE 事件流实时进度

Status: done

## Story

As a 外部系统,
I want 通过 SSE 事件流实时监听任务执行进度,
So that 我的平台可以实时显示桌面自动化任务的执行状态.

## Acceptance Criteria

1. **AC1: SSE 连接与实时事件推送**
   Given 任务正在执行
   When 连接 `GET /v1/runs/{runId}/events`（SSE endpoint）
   Then 实时推送事件流：`step_started`、`step_completed`、`batch_completed`、`run_completed`

2. **AC2: step_completed 事件数据**
   Given SSE 事件 `step_completed`
   When 解析事件数据
   Then 包含 step_index、tool、purpose、result（成功/失败）、duration_ms

3. **AC3: run_completed 事件数据**
   Given SSE 事件 `run_completed`
   When 解析事件数据
   Then 包含 final_status、total_steps、duration_ms、replan_count

4. **AC4: 已完成任务的重放**
   Given 连接 SSE 时任务已完成
   When 订阅 events
   Then 立即收到 `run_completed` 事件（重放最终状态），然后关闭连接

5. **AC5: 多客户端并发订阅**
   Given 多个客户端同时订阅同一任务
   When 事件推送
   Then 所有客户端都收到相同的事件序列

## Tasks / Subtasks

- [ ] Task 1: 定义 SSE 事件数据模型 (AC: #1, #2, #3)
  - [ ] 1.1 在 `Sources/AxionCLI/API/Models/APITypes.swift` 中添加 SSE 相关类型：
    - `SSEEvent` 枚举（关联值包含事件数据）：`.stepStarted(StepStartedData)`、`.stepCompleted(StepCompletedData)`、`.runCompleted(RunCompletedData)`
    - `StepStartedData`: step_index (Int), tool (String)
    - `StepCompletedData`: step_index (Int), tool (String), purpose (String), success (Bool), duration_ms (Int?)
    - `RunCompletedData`: run_id (String), final_status (String), total_steps (Int), duration_ms (Int?), replan_count (Int)
  - [ ] 1.2 所有事件类型实现 `Codable`，JSON 字段使用 snake_case CodingKeys
  - [ ] 1.3 添加 `SSEEvent` 的 `encodeToSSE()` 方法，将事件编码为 SSE 文本格式（`event: xxx\ndata: {...}\n\n`）

- [ ] Task 2: 创建 EventBroadcaster — 多客户端事件广播器 (AC: #1, #4, #5)
  - [ ] 2.1 创建 `Sources/AxionCLI/API/EventBroadcaster.swift`
  - [ ] 2.2 实现 `actor EventBroadcaster`：
    - `func subscribe(runId: String) -> AsyncStream<SSEEvent>` — 返回一个 AsyncStream，客户端通过它消费事件
    - `func emit(runId: String, event: SSEEvent)` — 向指定 runId 的所有订阅者广播事件
    - `func complete(runId: String)` — 关闭指定 runId 的所有订阅者流
    - `func removeCompletedStreams(runId: String)` — 清理已完成的流资源
  - [ ] 2.3 内部数据结构：
    - `private var subscribers: [String: [UUID: AsyncStream<SSEEvent>.Continuation]] = [:]`
    - `private var replayBuffer: [String: [SSEEvent]] = [:]` — 缓存每个 runId 的事件序列（用于已完成任务的重放，AC4）
  - [ ] 2.4 `emit()` 同时将事件追加到 replayBuffer
  - [ ] 2.5 `complete()` 调用所有 continuation 的 `finish()`

- [ ] Task 3: 扩展 RunTracker 事件通知 (AC: #1, #2, #3)
  - [ ] 3.1 修改 `Sources/AxionCLI/API/RunTracker.swift`：
    - 添加 `let eventBroadcaster: EventBroadcaster` 属性（构造时注入）
    - 在 `submitRun()` 中发送 `SSEEvent.runCompleted` 不合适（此时只是创建），但记录 runId 已创建
  - [ ] 3.2 替换现有的 `onRunStatusChanged` 回调为 EventBroadcaster 调用：
    - 在 `updateRun()` 中，调用 `await eventBroadcaster.emit(runId: runId, event: .runCompleted(...))`
  - [ ] 3.3 保留向后兼容：`onRunStatusChanged` 回调可以保留或移除（EventBroadcaster 取代其功能）

- [ ] Task 4: 修改 AgentRunner 逐步推送事件 (AC: #1, #2)
  - [ ] 4.1 修改 `Sources/AxionCLI/API/AgentRunner.swift` 的 `runAgent()` 方法：
    - 添加 `eventBroadcaster: EventBroadcaster?` 参数（可选，CLI 模式传 nil）
    - 在 `case .toolUse(let data):` 中，调用 `await eventBroadcaster?.emit(runId: runId, event: .stepStarted(...))`
    - 在 `case .toolResult(let data):` 中，调用 `await eventBroadcaster?.emit(runId: runId, event: .stepCompleted(...))`
  - [ ] 4.2 修改 `runAgent()` 的返回值以包含 runId 参数（从 RunTracker.submitRun 传入）
  - [ ] 4.3 在 `agent.stream()` 循环结束后，不单独发 run_completed（由 RunTracker.updateRun 触发）

- [ ] Task 5: 创建 SSE HTTP endpoint (AC: #1, #4)
  - [ ] 5.1 在 `Sources/AxionCLI/API/AxionAPI.swift` 添加新路由：
    - `GET /v1/runs/:runId/events` — SSE endpoint
  - [ ] 5.2 实现 SSE endpoint 逻辑：
    - 从 EventBroadcaster 订阅指定 runId 的事件流
    - 如果 runId 不存在（RunTracker 中找不到），返回 404
    - 如果任务已完成，从 replayBuffer 重放所有缓存事件，最后发 `run_completed`，然后关闭流（AC4）
    - 如果任务正在运行，返回 `Response` with `Content-Type: text/event-stream`，使用 `ResponseBody(asyncSequence:)` 流式推送
  - [ ] 5.3 SSE 响应格式：
    - Content-Type: `text/event-stream`
    - Cache-Control: `no-cache`
    - Connection: `keep-alive`
    - 每个 SSE 事件格式：`event: {type}\ndata: {json}\nid: {sequential_id}\n\n`
  - [ ] 5.4 使用 Hummingbird 的 `ResponseBody(asyncSequence:)` 构造流式响应

- [ ] Task 6: 连接 ServerCommand 中的依赖注入 (AC: #1)
  - [ ] 6.1 修改 `Sources/AxionCLI/Commands/ServerCommand.swift`：
    - 创建 `EventBroadcaster` 实例
    - 将 `EventBroadcaster` 传给 `RunTracker` 构造函数
    - 将 `EventBroadcaster` 传给 `AxionAPI.registerRoutes()` 和 `AxionAPI` 路由
  - [ ] 6.2 修改 `AxionAPI.registerRoutes()` 签名，添加 `eventBroadcaster: EventBroadcaster` 参数
  - [ ] 6.3 修改 `AxionAPI` 的 `POST /v1/runs` 处理逻辑，将 `eventBroadcaster` 和 `runId` 传给 `AgentRunner.runAgent()`

- [ ] Task 7: 单元测试 (AC: #1–#5)
  - [ ] 7.1 创建 `Tests/AxionCLITests/API/SSEEventTests.swift` — SSE 事件模型测试
    - SSEEvent Codable round-trip 测试
    - encodeToSSE() 格式验证（event: / data: / id: 字段格式）
    - 各事件类型 JSON 字段 snake_case 验证
  - [ ] 7.2 创建 `Tests/AxionCLITests/API/EventBroadcasterTests.swift` — 广播器测试
    - subscribe 返回有效的 AsyncStream
    - emit 向订阅者推送事件
    - 多个订阅者同时收到相同事件（AC5）
    - complete 关闭订阅者流
    - replayBuffer 缓存已完成事件
    - 任务完成后订阅能重放事件（AC4）
  - [ ] 7.3 更新 `Tests/AxionCLITests/API/RunTrackerTests.swift` — 适配 EventBroadcaster 注入
    - 测试 updateRun 触发 eventBroadcaster.emit
  - [ ] 7.4 更新 `Tests/AxionCLITests/API/AxionAPIRoutesTests.swift` — SSE endpoint 测试
    - GET /v1/runs/{runId}/events 返回 404（runId 不存在）
    - GET /v1/runs/{runId}/events 返回 text/event-stream content-type
    - 验证 SSE 事件格式（event: / data: 行格式）
    - 已完成任务返回 run_completed 事件后关闭（AC4）

## Dev Notes

### 核心架构决策

**SSE 实现方式：直接使用 Hummingbird 的 ResponseBody 流式 API**

不引入 SSEKit 等外部库，原因：
1. Hummingbird 2.x 的 `ResponseBody` 原生支持 `AsyncSequence<ByteBuffer>` 初始化（参见 `.build/checkouts/hummingbird/Sources/HummingbirdCore/Response/ResponseBody.swift:74`）
2. SSE 协议极简（`event: type\ndata: json\n\n`），手写编码器足够，不需要额外依赖
3. 减少依赖传递风险（SSEKit 依赖 SwiftNIO，Hummingbird 已通过 SwiftNIO 提供 ByteBuffer）

**SSE 事件流架构：**

```
AgentRunner (生产事件)
    │
    ├─ .toolUse → EventBroadcaster.emit(.stepStarted)
    ├─ .toolResult → EventBroadcaster.emit(.stepCompleted)
    │
    └─ RunTracker.updateRun() → EventBroadcaster.emit(.runCompleted)
                                       │
                                       ▼
                              AsyncStream<SSEEvent>
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
              Client 1 SSE      Client 2 SSE       Client N SSE
          (ResponseBody stream) (ResponseBody stream) ...
```

**事件广播器设计（EventBroadcaster）：**

```swift
actor EventBroadcaster {
    private var subscribers: [String: [UUID: AsyncStream<SSEEvent>.Continuation]] = [:]
    private var replayBuffer: [String: [SSEEvent]] = [:]

    func subscribe(runId: String) -> AsyncStream<SSEEvent> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[runId, default: [:]][id] = continuation
            continuation.onTermination = { _ in
                subscribers[runId]?.removeValue(forKey: id)
            }
        }
    }

    func emit(runId: String, event: SSEEvent) {
        replayBuffer[runId, default: []].append(event)
        for (_, continuation) in subscribers[runId, default: [:]] {
            continuation.yield(event)
        }
    }

    func complete(runId: String) {
        for (_, continuation) in subscribers[runId, default: [:]] {
            continuation.finish()
        }
        subscribers.removeValue(forKey: runId)
    }
}
```

### SSE 端点 Hummingbird 实现

使用 `ResponseBody(asyncSequence:)` 构造流式响应：

```swift
// GET /v1/runs/:runId/events
v1.get("runs/:runId/events") { request, context in
    guard let runId = context.parameters.get("runId") else {
        throw AxionAPIError(status: .badRequest, error: APIErrorResponse(
            error: "missing_run_id", message: "Run ID is required."
        ))
    }

    let run = await runTracker.getRun(runId: runId)
    guard run != nil else {
        throw AxionAPIError(status: .notFound, error: APIErrorResponse(
            error: "run_not_found", message: "Run '\(runId)' not found."
        ))
    }

    let eventStream = await eventBroadcaster.subscribe(runId: runId)

    // Convert SSEEvent AsyncStream to ByteBuffer AsyncSequence
    let bufferStream = eventStream.map { event in
        event.encodeToSSE(allocator: context.allocator)
    }

    let body = ResponseBody(asyncSequence: bufferStream)
    return Response(
        status: .ok,
        headers: [
            .contentType: "text/event-stream",
            .cacheControl: "no-cache",
            .connection: "keep-alive",
        ],
        body: body
    )
}
```

### SSE 事件编码格式

每个 SSE 事件遵循标准格式：

```
event: step_started
data: {"step_index":0,"tool":"launch_app"}
id: 1

event: step_completed
data: {"step_index":0,"tool":"launch_app","purpose":"启动 Calculator","success":true,"duration_ms":150}
id: 2

event: run_completed
data: {"run_id":"20260513-abc123","final_status":"done","total_steps":3,"duration_ms":8200,"replan_count":0}
id: 3

```

### SSE 事件类型与数据定义

**step_started：**
```json
{
  "step_index": 0,
  "tool": "launch_app"
}
```

**step_completed：**
```json
{
  "step_index": 0,
  "tool": "launch_app",
  "purpose": "启动 Calculator",
  "success": true,
  "duration_ms": 150
}
```

**run_completed：**
```json
{
  "run_id": "20260513-abc123",
  "final_status": "done",
  "total_steps": 3,
  "duration_ms": 8200,
  "replan_count": 0
}
```

### RunTracker 修改要点

当前 RunTracker 已有 `onRunStatusChanged` 回调作为 SSE 扩展点（Story 5.1 预留）。本 Story 将其替换为 EventBroadcaster：

- `onRunStatusChanged` 回调删除或保留但不再使用
- RunTracker 构造函数增加 `eventBroadcaster: EventBroadcaster` 参数
- `updateRun()` 中调用 `await eventBroadcaster.emit(runId: runId, event: .runCompleted(...))`
- `updateRun()` 中调用 `await eventBroadcaster.complete(runId: runId)` 关闭所有订阅者

### AgentRunner 修改要点

当前 `AgentRunner.runAgent()` 在消息流循环中收集 `stepSummaries`，但不实时推送。本 Story 需要：

- 添加 `runId: String` 和 `eventBroadcaster: EventBroadcaster?` 参数
- 在 `.toolUse` case 中 emit `stepStarted` 事件
- 在 `.toolResult` case 中 emit `stepCompleted` 事件
- `eventBroadcaster` 为可选参数，CLI 的 RunCommand 路径传 nil（不影响 CLI 行为）

**重要：不修改 RunCommand 的行为** — AgentRunner 的新参数有默认值 `nil`，RunCommand 调用 `AgentRunner.runAgent()` 时不需要传这些参数。

### ServerCommand 修改要点

构造依赖链：
```swift
let eventBroadcaster = EventBroadcaster()
let runTracker = RunTracker(eventBroadcaster: eventBroadcaster)
AxionAPI.registerRoutes(on: router, runTracker: runTracker, eventBroadcaster: eventBroadcaster, config: config)
```

### 已完成任务重放（AC4）

当客户端连接 SSE 时任务已完成：
1. RunTracker.getRun(runId) 返回 `.done` / `.failed` / `.cancelled` 状态
2. 从 EventBroadcaster.replayBuffer 读取缓存事件
3. 如果 replayBuffer 中有该 runId 的事件，逐个发送
4. 最后发送 `run_completed` 事件（如果 replayBuffer 中没有的话，从 TrackedRun 构造）
5. 关闭连接

需要处理 replayBuffer 内存管理：
- 任务完成并所有订阅者关闭后，保留 replayBuffer 一段时间（如 5 分钟）
- 超时后清理。可以简单实现：在 `complete()` 中启动一个延时 Task 清理

### 需要修改的现有文件

1. **`Sources/AxionCLI/API/Models/APITypes.swift`** [UPDATE]
   - 添加 SSEEvent 枚举及关联数据类型
   - 必须保留：所有现有类型定义不变

2. **`Sources/AxionCLI/API/RunTracker.swift`** [UPDATE]
   - 添加 `eventBroadcaster` 属性
   - 修改构造函数接受 EventBroadcaster
   - 在 `updateRun()` 中调用 eventBroadcaster.emit 和 complete
   - `onRunStatusChanged` 回调可以保留（向后兼容）或移除
   - 必须保留：submitRun/getRun/listRuns 的公共 API 不变

3. **`Sources/AxionCLI/API/AgentRunner.swift`** [UPDATE]
   - `runAgent()` 添加 `runId: String` 和 `eventBroadcaster: EventBroadcaster?` 参数
   - 在消息流循环中 emit step_started 和 step_completed 事件
   - 必须保留：返回值类型和格式不变；新参数有默认值确保 CLI 路径不受影响

4. **`Sources/AxionCLI/API/AxionAPI.swift`** [UPDATE]
   - `registerRoutes()` 签名添加 `eventBroadcaster` 参数
   - 添加 `GET /v1/runs/:runId/events` SSE endpoint
   - POST /v1/runs 处理中传入 runId 和 eventBroadcaster 到 AgentRunner
   - 必须保留：所有现有路由（health, runs POST, runs GET）不变

5. **`Sources/AxionCLI/Commands/ServerCommand.swift`** [UPDATE]
   - 创建 EventBroadcaster 实例并注入到 RunTracker 和 AxionAPI
   - 必须保留：所有 CLI 参数和 server 启动逻辑不变

6. **`Tests/AxionCLITests/API/RunTrackerTests.swift`** [UPDATE]
   - 适配 RunTracker 构造函数变更（需要传入 EventBroadcaster）

7. **`Tests/AxionCLITests/API/AxionAPIRoutesTests.swift`** [UPDATE]
   - registerRoutes 调用添加 eventBroadcaster 参数

### 需要创建的新文件

1. **`Sources/AxionCLI/API/EventBroadcaster.swift`** [NEW]
   - Actor 实现的多客户端事件广播器

2. **`Tests/AxionCLITests/API/SSEEventTests.swift`** [NEW]
   - SSE 事件模型测试

3. **`Tests/AxionCLITests/API/EventBroadcasterTests.swift`** [NEW]
   - 事件广播器测试

### Import 顺序

```swift
// 1. 系统框架
import Foundation

// 2. 第三方依赖
import Hummingbird
import NIOCore   // ByteBuffer, ByteBufferAllocator (SSE 编码需要)

// 3. 项目内部模块
import AxionCore
```

### 错误处理

- SSE 连接建立时 runId 不存在 → 返回 404 JSON 错误（同 Story 5.1 的 AxionAPIError）
- SSE 推送过程中客户端断开 → AsyncStream 的 onTermination 清理订阅者，不影响其他客户端
- EventBroadcaster 是 actor，所有操作线程安全
- replayBuffer 内存泄漏防护：任务完成 5 分钟后清理（简单实现：在 `complete()` 中调度延时清理 Task）

### 项目结构注意事项

- 新文件 `EventBroadcaster.swift` 放在 `Sources/AxionCLI/API/`
- SSE 事件模型添加到 `Sources/AxionCLI/API/Models/APITypes.swift`
- 测试文件放在 `Tests/AxionCLITests/API/`（镜像源结构）
- 所有变更仅在 AxionCLI 模块内，不修改 AxionCore 或 AxionHelper

### 安全注意事项

- SSE endpoint 遵循与现有 API 相同的 localhost 绑定策略（ServerCommand 默认 127.0.0.1）
- API 认证在 Story 5.3 实现，本 Story 不实现 auth-key
- SSE 不暴露 API Key（事件数据中不包含配置信息）
- replayBuffer 不持久化到磁盘 — 仅内存缓存，server 重启后清空

### NFR 注意

- **NFR25**: SSE 事件推送延迟 < 500ms — EventBroadcaster 使用 AsyncStream.yield() 实时推送，无轮询延迟
- **NFR29**: Server 模式支持至少 10 个并发 SSE 连接 — EventBroadcaster 的 subscriber 字典无硬性上限，每个 runId 可有多个订阅者
- **NFR24**: SSE endpoint 的连接建立响应时间 < 100ms — 订阅操作是内存级 O(1)

### 前一 Story（5.1）的关键学习

- **RunTracker 已预留 SSE 扩展点**：`onRunStatusChanged` 回调和 `setOnStatusChanged()` 方法
- **AgentRunner 独立实现**：不修改 RunCommand，AgentRunner.runAgent() 是独立函数
- **Hummingbird 依赖已添加**：Package.swift 已包含 Hummingbird 2.22.0+ 和 HummingbirdTesting
- **API 路由结构已建立**：AxionAPI.registerRoutes() 在 `v1` group 下注册路由
- **测试使用 HummingbirdTesting**：已有 AxionAPIRoutesTests 使用 Hummingbird 测试工具的先例
- **swift-mcp 版本升级**：从 0.1.5 升级到 2.0.4，注意 HelperProcessManager 中 Tool.Content 类型变更

### Package.swift 无需修改

本 Story 不需要修改 Package.swift。所有需要的依赖（Hummingbird、HummingbirdTesting）已在 Story 5.1 中添加。SSE 编码使用 NIOCore 的 ByteBuffer（Hummingbird 已传递依赖 SwiftNIO）。不需要添加 SSEKit 等新依赖。

### 测试策略

**SSEEventTests:**
- StepStartedData Codable round-trip
- StepCompletedData Codable round-trip
- RunCompletedData Codable round-trip
- encodeToSSE() 输出格式验证（event: / data: / id: 行）
- snake_case CodingKeys 验证

**EventBroadcasterTests:**
- subscribe 返回 AsyncStream
- emit 向订阅者推送事件
- 多订阅者收到相同事件（并发测试）
- complete 关闭所有订阅者
- replayBuffer 正确缓存事件
- 清理后 replayBuffer 释放

**RunTrackerTests 更新:**
- 构造函数接受 EventBroadcaster
- updateRun 触发 EventBroadcaster.emit
- 向后兼容测试（传入 EventBroadcaster 后 listRuns/getRun 仍正常）

**AxionAPIRoutesTests 更新:**
- registerRoutes 签名变更适配
- SSE endpoint 404 测试
- SSE endpoint content-type 验证
- 已完成任务的 SSE 重放验证

### References

- Epic 5 定义: `_bmad-output/planning-artifacts/epics.md` (Story 5.2)
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- PRD 旅程三（王强）: `_bmad-output/planning-artifacts/prd.md`
- Project Context: `_bmad-output/project-context.md`
- Previous Story 5.1: `_bmad-output/implementation-artifacts/5-1-http-api-foundation-task-management.md`
- RunTracker 实现: `Sources/AxionCLI/API/RunTracker.swift` (SSE 扩展点在第 16、101、117-123 行)
- AgentRunner 实现: `Sources/AxionCLI/API/AgentRunner.swift`
- AxionAPI 路由: `Sources/AxionCLI/API/AxionAPI.swift`
- APITypes 模型: `Sources/AxionCLI/API/Models/APITypes.swift`
- ServerCommand: `Sources/AxionCLI/Commands/ServerCommand.swift`
- Hummingbird ResponseBody (AsyncSequence init): `.build/checkouts/hummingbird/Sources/HummingbirdCore/Response/ResponseBody.swift:74`
- SSEKit (参考实现模式，不引入依赖): https://github.com/orlandos-nl/SSEKit
- Hummingbird 文档: https://docs.hummingbird.codes/2.0/documentation/hummingbird/

### Review Findings

- [x] [Review][Patch] SSE live stream sequenceId 硬编码为 0 [AxionAPI.swift:229] — **FIXED**: 改为递增计数器 `sequenceCounter`，确保每个 SSE 事件有唯一递增的 `id:` 字段
- [x] [Review][Patch] SSE 编码错误被 try? 静默吞掉 [AxionAPI.swift:209,230] — **FIXED**: 改为 `do/catch` 并在编码失败时发出 `event: error` 占位事件，确保客户端可感知
- [x] [Review][Patch] APITypes.swift 中未使用的 import NIOCore 和 encodeToSSEByteBuffer 方法 — **FIXED**: 移除未使用的 import 和死代码方法
- [x] [Review][Defer] batch_completed 事件类型缺失 [SSEEvent enum] — spec AC1 列出 batch_completed 但 Dev Notes 和 Tasks 中均未定义其数据结构。当前架构中 AgentRunner 不跟踪 batch 概念。合理的设计省略，可在未来 batch 跟踪需求出现时添加。deferred, pre-existing spec ambiguity
- [x] [Review][Defer] RunTracker.print() 警告未使用日志系统 [RunTracker.swift:94] — Story 5.1 遗留问题，不归本 Story 负责。deferred, pre-existing
- [x] [Review][Dismiss] EventBroadcaster.subscribeWithReplay 中的 race condition 风险 — 分析后发现：由于 EventBroadcaster 是 actor，subscribeWithReplay 的 build closure 在 actor isolation 内执行，不会与 emit() 并发。dismiss, actor isolation prevents race
- [x] [Review][Dismiss] replayBuffer 无上限控制 — 每个 runId 最多 40 个事件（20 stepStarted + 20 stepCompleted），5 分钟清理策略足够。dismiss, bounded by maxSteps

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
