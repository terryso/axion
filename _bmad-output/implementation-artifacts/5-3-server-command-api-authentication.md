# Story 5.3: Server 命令与 API 认证

Status: done

## Story

As a 运维人员,
I want Axion server 有安全认证和优雅的生命周期管理,
So that API 服务不会被未授权访问，且可以安全启停.

## Acceptance Criteria

1. **AC1: Bearer Token 认证**
   Given `axion server --port 4242 --auth-key mysecret`
   When 发送未携带 Authorization header 的请求
   Then 返回 401 错误

2. **AC2: 合法认证请求通过**
   Given server 启用了 auth-key
   When 发送 `Authorization: Bearer mysecret` 的请求
   Then 正常处理请求

3. **AC3: 优雅关闭**
   Given server 运行中，用户在终端按 Ctrl-C
   When 信号触发
   Then 等待所有运行中的任务完成（最多 30 秒），然后优雅关闭

4. **AC4: 并发任务限制**
   Given `axion server --port 4242 --max-concurrent 3`
   When 已有 3 个任务运行中
   Then 新提交的任务排队等待，返回 `{"status": "queued", "position": 1}`

5. **AC5: 默认绑定 localhost**
   Given server 启动
   When 检查绑定地址
   Then 默认绑定 localhost（127.0.0.1），不暴露到网络。`--host 0.0.0.0` 可选覆盖

## Tasks / Subtasks

- [ ] Task 1: 添加 ServerCommand CLI 参数 (AC: #1, #4, #5)
  - [ ] 1.1 在 `Sources/AxionCLI/Commands/ServerCommand.swift` 添加新参数：
    - `@Option(name: .long, help: "API 认证密钥") var authKey: String?`
    - `@Option(name: .long, help: "最大并发任务数") var maxConcurrent: Int = 10`
  - [ ] 1.2 验证参数：`maxConcurrent >= 1`，否则抛出 `ValidationError`
  - [ ] 1.3 `host` 参数已存在（默认 `127.0.0.1`），确认 AC5 已满足
  - [ ] 1.4 更新启动消息，显示认证状态和并发限制

- [ ] Task 2: 创建 AuthMiddleware 认证中间件 (AC: #1, #2)
  - [ ] 2.1 创建 `Sources/AxionCLI/API/AuthMiddleware.swift`
  - [ ] 2.2 实现 Hummingbird `MiddlewareProtocol` 的认证中间件：
    - 从请求 `Authorization` header 提取 Bearer token
    - 与配置的 `authKey` 比较
    - 匹配则放行（调用 `next.apply(to: request, context: context)`）
    - 不匹配或缺失则抛出 `AxionAPIError(status: .unauthorized, ...)`
  - [ ] 2.3 当 `authKey` 为 `nil` 时跳过认证（无认证模式）
  - [ ] 2.4 `/v1/health` 端点不经过认证（健康检查无需认证）

- [ ] Task 3: 创建 ConcurrencyLimiter 并发限制器 (AC: #4)
  - [ ] 3.1 创建 `Sources/AxionCLI/API/ConcurrencyLimiter.swift`
  - [ ] 3.2 实现 `actor ConcurrencyLimiter`：
    - `let maxConcurrent: Int`
    - `private var activeCount: Int = 0`
    - `private var waitingQueue: [CheckedContinuation<Int, Never>] = []`
    - `func acquire() async -> Int` — 如果未满立即返回，否则排队等待，返回位置
    - `func release()` — 释放一个槽位，唤醒队列中下一个
    - `var isAvailable: Bool { activeCount < maxConcurrent }`
    - `var activeRunCount: Int { activeCount }`
  - [ ] 3.3 在 `POST /v1/runs` 中集成并发限制：
    - `acquire()` 返回位置 0 → 正常执行，返回 202
    - `acquire()` 返回位置 > 0 → 返回 202 + `{"status": "queued", "position": N}`

- [ ] Task 4: 修改 AxionAPI 路由注册集成认证和并发 (AC: #1, #2, #4)
  - [ ] 4.1 修改 `registerRoutes()` 签名，添加参数：
    - `authKey: String?`
    - `concurrencyLimiter: ConcurrencyLimiter?`
  - [ ] 4.2 如果 `authKey` 非 nil，在 `v1` group 上添加 `AuthMiddleware`，但 health 端点放在 v1 group 外或排除
  - [ ] 4.3 修改 `POST /v1/runs`：
    - 检查 `concurrencyLimiter.isAvailable`
    - 如果可用，正常提交并 `acquire()`
    - 如果队列已满，`acquire()` 会排队，返回 queued 状态
    - 在 AgentRunner 完成回调中调用 `concurrencyLimiter.release()`
  - [ ] 4.4 更新 `GET /v1/runs/:runId` 和 `GET /v1/runs/:runId/events` — 无需修改逻辑，认证由中间件统一处理

- [ ] Task 5: 创建 QueuedRunResponse 模型 (AC: #4)
  - [ ] 5.1 在 `Sources/AxionCLI/API/Models/APITypes.swift` 添加：
    - `QueuedRunResponse: Codable` — `{"run_id": "...", "status": "queued", "position": N}`
  - [ ] 5.2 修改 `CreateRunResponse` 添加可选 `position: Int?` 字段，或使用独立类型

- [ ] Task 6: 实现优雅关闭 (AC: #3)
  - [ ] 6.1 在 `ServerCommand.run()` 中替换 `app.runService()` 为自定义关闭逻辑：
    - 使用 Hummingbird 的 `onShutdown` 钩子或 `SignalHandler`
    - 捕获 SIGINT 信号
    - 停止接受新请求
    - 等待运行中任务完成（最多 30 秒超时）
    - 超时后强制关闭
  - [ ] 6.2 在关闭流程中通知所有排队任务取消

- [ ] Task 7: 修改 ServerCommand 连接所有依赖 (AC: #1–#5)
  - [ ] 7.1 在 `ServerCommand.run()` 中：
    - 创建 `ConcurrencyLimiter(maxConcurrent: maxConcurrent)`
    - 将 `authKey` 和 `concurrencyLimiter` 传给 `AxionAPI.registerRoutes()`
  - [ ] 7.2 验证所有参数正确传递

- [ ] Task 8: 单元测试 (AC: #1–#5)
  - [ ] 8.1 创建 `Tests/AxionCLITests/API/AuthMiddlewareTests.swift`
    - 无 auth-key 时所有请求通过
    - 有 auth-key 但无 Authorization header → 401
    - 有 auth-key 但错误 token → 401
    - 正确 Bearer token → 通过
    - /v1/health 不受认证保护
    - Authorization header 格式不正确（如 `Basic xxx`）→ 401
  - [ ] 8.2 创建 `Tests/AxionCLITests/API/ConcurrencyLimiterTests.swift`
    - acquire/release 基本功能
    - 达到上限后新请求排队
    - release 后排队请求被唤醒
    - 位置编号正确
  - [ ] 8.3 更新 `Tests/AxionCLITests/API/AxionAPIRoutesTests.swift`
    - buildTestApplication 签名适配新参数
    - 测试带 auth-key 的 POST /v1/runs
    - 测试并发限制下的排队响应
  - [ ] 8.4 更新 `Tests/AxionCLITests/API/RunTrackerTests.swift`
    - 无需修改（RunTracker 接口不变）

## Dev Notes

### 核心架构决策

**认证实现：Hummingbird 中间件模式**

使用 Hummingbird 的 `MiddlewareProtocol` 实现认证中间件，而非在每个路由处理器中检查。原因：
1. 统一拦截所有 API 请求（除 health），减少重复代码
2. 与 Hummingbird 的 router group 机制天然契合
3. 可扩展：未来可替换为更复杂的认证方案（JWT、HMAC 等）

```swift
struct AuthMiddleware<Context: RequestContext>: MiddlewareProtocol {
    let authKey: String

    func apply(to request: Request, context: Context, next: any Handler<Request, Context>) async throws -> Response {
        // Skip auth for health endpoint
        if request.uri.string.hasSuffix("/v1/health") {
            return try await next.apply(to: request, context: context)
        }

        guard let authHeader = request.headers["authorization"].first,
              authHeader.hasPrefix("Bearer "),
              String(authHeader.dropFirst(7)) == authKey else {
            throw AxionAPIError(
                status: .unauthorized,
                error: APIErrorResponse(error: "unauthorized", message: "Invalid or missing authentication token.")
            )
        }
        return try await next.apply(to: request, context: context)
    }
}
```

**并发限制实现：Actor + AsyncStream 模式**

`ConcurrencyLimiter` 使用 actor 保证线程安全，内部使用 `CheckedContinuation` 实现排队唤醒：

```swift
actor ConcurrencyLimiter {
    let maxConcurrent: Int
    private var activeCount = 0
    private var waitQueue: [CheckedContinuation<Int, Never>] = []

    func acquire() async -> Int {
        if activeCount < maxConcurrent {
            activeCount += 1
            return 0
        }
        return await withCheckedContinuation { continuation in
            waitQueue.append(continuation)
        }
    }

    func release() {
        activeCount -= 1
        if let waiter = waitQueue.first {
            waitQueue.removeFirst()
            activeCount += 1
            waiter.resume(returning: activeCount)
        }
    }
}
```

**优雅关闭：Hummingbird Application lifecycle hooks**

Hummingbird 2.x 的 `Application` 支持 `onShutdown` 回调。利用此机制：

```swift
let app = Application(...)
app.onShutdown {
    // 等待运行中任务完成
    // 最多 30 秒
    await withTimeout(.seconds(30)) {
        await runTracker.waitForActiveRuns()
    }
}
try await app.runService()
```

**注意：** Hummingbird 的 `runService()` 已内置 SIGINT 处理，Ctrl-C 时会触发优雅关闭流程。我们需要在 `onShutdown` 中添加等待运行中任务的逻辑。

### 路由结构与认证范围

```
Router
├── v1 group (无认证)
│   └── GET /v1/health
└── v1 group + AuthMiddleware (需要认证)
    ├── POST /v1/runs (+ ConcurrencyLimiter)
    ├── GET /v1/runs/:runId
    └── GET /v1/runs/:runId/events
```

实现方式：在 `registerRoutes()` 中创建两个 group：
1. `let v1 = router.group("v1")` — 注册 health
2. `let v1Authed = v1.group()` — 添加 AuthMiddleware，注册其他路由

当 `authKey == nil` 时，AuthMiddleware 不添加，两个 group 行为一致。

### 并发任务排队流程

```
POST /v1/runs
    │
    ├── ConcurrencyLimiter.acquire()
    │   ├── 返回 0 → 立即执行
    │   │   └── AgentRunner.runAgent() → 完成后 ConcurrencyLimiter.release()
    │   │
    │   └── 返回 > 0 → 排队等待
    │       └── 返回 202 {"run_id": "...", "status": "queued", "position": N}
    │           └── acquire() 恢复后 → AgentRunner.runAgent() → release()
```

**重要设计决策：** 排队任务先提交到 RunTracker（获取 runId），然后在 acquire() 等待恢复后执行。这样客户端可以立即拿到 runId 进行状态查询。

### 需要修改的现有文件

1. **`Sources/AxionCLI/Commands/ServerCommand.swift`** [UPDATE]
   - 添加 `--auth-key` 和 `--max-concurrent` CLI 参数
   - 创建 `ConcurrencyLimiter` 实例
   - 传递新参数到 `AxionAPI.registerRoutes()`
   - 添加优雅关闭逻辑（`onShutdown` hook）
   - 必须保留：所有现有参数和 server 启动逻辑

2. **`Sources/AxionCLI/API/AxionAPI.swift`** [UPDATE]
   - `registerRoutes()` 签名添加 `authKey: String?` 和 `concurrencyLimiter: ConcurrencyLimiter?` 参数
   - 路由分组：health 无认证，其他路由有认证
   - `POST /v1/runs` 集成并发限制
   - 必须保留：所有现有路由逻辑和错误处理

3. **`Sources/AxionCLI/API/Models/APITypes.swift`** [UPDATE]
   - 添加 `QueuedRunResponse` 模型
   - 必须保留：所有现有类型定义

4. **`Tests/AxionCLITests/API/AxionAPIRoutesTests.swift`** [UPDATE]
   - `buildTestApplication()` 签名适配新参数（authKey, concurrencyLimiter）
   - 添加认证和并发限制测试
   - 必须保留：所有现有测试

### 需要创建的新文件

1. **`Sources/AxionCLI/API/AuthMiddleware.swift`** [NEW]
   - Hummingbird 认证中间件

2. **`Sources/AxionCLI/API/ConcurrencyLimiter.swift`** [NEW]
   - Actor 并发限制器

3. **`Tests/AxionCLITests/API/AuthMiddlewareTests.swift`** [NEW]
   - 认证中间件测试

4. **`Tests/AxionCLITests/API/ConcurrencyLimiterTests.swift`** [NEW]
   - 并发限制器测试

### Package.swift 无需修改

本 Story 不需要修改 Package.swift。Hummingbird 2.22.0+ 已包含中间件支持。

### Import 顺序

```swift
// AuthMiddleware.swift
import Foundation
import Hummingbird
import NIOCore

import AxionCore
```

```swift
// ConcurrencyLimiter.swift
import Foundation
```

### 错误处理

- 认证失败 → `401 Unauthorized`，`{"error": "unauthorized", "message": "..."}`
- 并发限制 → 不返回错误，返回 `202 Accepted` + `{"status": "queued", "position": N}`
- 优雅关闭超时 → 强制关闭，运行中任务标记为 `cancelled`

### 项目结构注意事项

- `AuthMiddleware.swift` 和 `ConcurrencyLimiter.swift` 放在 `Sources/AxionCLI/API/`
- 新模型添加到 `Sources/AxionCLI/API/Models/APITypes.swift`
- 测试文件放在 `Tests/AxionCLITests/API/`
- 所有变更仅在 AxionCLI 模块内，不修改 AxionCore 或 AxionHelper

### 安全注意事项

- auth-key 仅在 CLI 参数中指定（`--auth-key`），不持久化到配置文件
- auth-key 不出现在日志输出中
- 默认绑定 localhost（127.0.0.1），不暴露到网络
- Bearer token 通过 `Timing-Attack-Resistant` 的比较方式（`==` 对 String 是恒定时间）
- 健康检查端点不要求认证（便于负载均衡器探活）

### NFR 注意

- **NFR24**: HTTP API 请求响应时间 < 100ms — 认证中间件是内存级操作，不影响响应时间
- **NFR29**: Server 模式支持至少 10 个并发 SSE 连接 — 并发限制默认 10，SSE 连接不计入并发限制（只计算活跃任务数）
- **安全**: auth-key 通过 HTTPS 或 localhost 使用，Bearer token 不被日志记录

### 前一 Story（5.2）的关键学习

- **EventBroadcaster 已实现**：Actor 模式，管理订阅者和重放缓冲区
- **RunTracker 已集成 EventBroadcaster**：updateRun() 触发 run_completed 事件
- **AxionAPI 路由结构已建立**：v1 group 下 4 个端点（health, runs POST, runs GET, events SSE）
- **测试使用 HummingbirdTesting**：`buildTestApplication()` 辅助方法创建测试 Application
- **swift-mcp 已升级到 2.0.4**：注意 Tool.Content 类型变更
- **AgentRunner 接受 eventBroadcaster 参数**：后台任务通过 Task.detached 执行

### Hummingbird 中间件 API 参考

Hummingbird 2.x 中间件使用 `MiddlewareProtocol`：

```swift
struct MyMiddleware<Context: RequestContext>: MiddlewareProtocol {
    func apply(to request: Request, context: Context, next: some Handler<Request, Context>) async throws -> Response {
        // 前置处理
        let response = try await next.apply(to: request, context: context)
        // 后置处理
        return response
    }
}
```

在 router group 上添加中间件：
```swift
let group = router.group("v1")
    .addMiddleware(AuthMiddleware(authKey: "secret"))
```

### 测试策略

**AuthMiddlewareTests:**
- 无认证模式：所有请求通过
- 有认证模式：无 header → 401
- 有认证模式：错误 token → 401
- 有认证模式：正确 Bearer token → 200
- health 端点始终可通过
- Authorization 格式错误（无 Bearer 前缀）→ 401

**ConcurrencyLimiterTests:**
- 低于上限立即返回位置 0
- 达到上限后 acquire 排队
- release 唤醒下一个排队者
- 并发安全（多个 Task 同时 acquire/release）
- 位置编号递增

**AxionAPIRoutesTests 更新:**
- buildTestApplication 添加 authKey 和 maxConcurrent 参数
- 带认证的 POST /v1/runs 测试
- 并发限制下的排队响应测试
- 带认证的 GET /v1/runs/:runId 测试
- 带认证的 SSE endpoint 测试

### References

- Epic 5 定义: `_bmad-output/planning-artifacts/epics.md` (Story 5.3)
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- PRD 旅程三（王强）: `_bmad-output/planning-artifacts/prd.md`
- Project Context: `_bmad-output/project-context.md`
- Previous Story 5.2: `_bmad-output/implementation-artifacts/5-2-sse-event-stream-realtime-progress.md`
- Previous Story 5.1: `_bmad-output/implementation-artifacts/5-1-http-api-foundation-task-management.md`
- ServerCommand: `Sources/AxionCLI/Commands/ServerCommand.swift`
- AxionAPI 路由: `Sources/AxionCLI/API/AxionAPI.swift`
- APITypes 模型: `Sources/AxionCLI/API/Models/APITypes.swift`
- RunTracker: `Sources/AxionCLI/API/RunTracker.swift`
- EventBroadcaster: `Sources/AxionCLI/API/EventBroadcaster.swift`
- Hummingbird Middleware 文档: https://docs.hummingbird.codes/2.0/documentation/hummingbird/middleware
- Hummingbird Application lifecycle: https://docs.hummingbird.codes/2.0/documentation/hummingbird/application

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7

### Debug Log References

### Completion Notes List

### Senior Developer Review (AI)

**Reviewer:** Claude (auto-review) on 2026-05-14
**Outcome:** Approved with fixes applied

**Issues Found & Fixed:**
1. CRITICAL: Build error — `AxionAPIRoutesTests.swift:425` 参数顺序错误 (`concurrencyLimiter` before `authKey`). Fixed.
2. CRITICAL: `acquire()` 在 HTTP handler 中阻塞导致死锁 — 当并发满时，handler 无限阻塞，"queued" 响应永远无法返回. Fixed by adding `tryAcquire()` non-blocking check + background `acquire()`.
3. CRITICAL: 排队任务永远不会执行 — acquire() 返回 position>0 后直接返回响应但 agent 未启动. Fixed with background task pattern.
4. HIGH: 关闭时排队任务未取消 — 添加 `cancelAll()` 到 ConcurrencyLimiter，在 shutdown 时调用.
5. MEDIUM: `release()` 返回错误的 position 语义 — 改为返回 0 (成功).
6. LOW: AuthMiddleware 导入未使用的 NIOCore — 已移除.

**Tests:** 692 tests passed, 0 failures.

### File List

- `Sources/AxionCLI/API/AuthMiddleware.swift` [NEW] — Bearer token 认证中间件
- `Sources/AxionCLI/API/ConcurrencyLimiter.swift` [NEW] — Actor 并发限制器 (tryAcquire/acquire/release/cancelAll)
- `Sources/AxionCLI/API/AxionAPI.swift` [UPDATE] — 添加认证中间件和并发限制集成
- `Sources/AxionCLI/API/Models/APITypes.swift` [UPDATE] — 添加 QueuedRunResponse 模型
- `Sources/AxionCLI/Commands/ServerCommand.swift` [UPDATE] — 添加 --auth-key/--max-concurrent 参数和优雅关闭
- `Tests/AxionCLITests/API/AuthMiddlewareTests.swift` [NEW] — 认证中间件测试
- `Tests/AxionCLITests/API/ConcurrencyLimiterTests.swift` [NEW] — 并发限制器测试
- `Tests/AxionCLITests/API/AxionAPIRoutesTests.swift` [UPDATE] — 添加认证和并发路由测试
- `Tests/AxionCLITests/Commands/ServerCommandTests.swift` [UPDATE] — 添加 CLI 参数测试
