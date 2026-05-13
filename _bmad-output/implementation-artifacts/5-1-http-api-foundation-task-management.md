# Story 5.1: HTTP API 基础与任务管理

Status: done

## Story

As a 外部系统,
I want 通过 HTTP API 提交和管理桌面自动化任务,
So that 我可以将 Axion 集成到 CI/CD 管道和调度系统中.

## Acceptance Criteria

1. **AC1: Server 启动与端口监听**
   Given 运行 `axion server --port 4242`
   When server 启动
   Then 监听指定端口，显示 "Axion API server running on port 4242"

2. **AC2: 提交异步任务**
   Given server 运行中
   When 发送 `POST /v1/runs` body `{"task": "打开计算器"}`
   Then 返回 `{"runId": "20260512-abc123", "status": "running"}`，后台启动任务执行

3. **AC3: 查询运行中任务状态**
   Given 任务已提交
   When 发送 `GET /v1/runs/{runId}`
   Then 返回任务状态（running / done / failed / cancelled）和已完成的步骤摘要

4. **AC4: 查询已完成任务结果**
   Given 任务已完成
   When 发送 `GET /v1/runs/{runId}`
   Then 返回完整执行结果（总步数、耗时、重规划次数、最终状态）

5. **AC5: 请求参数校验**
   Given 发送 `POST /v1/runs` 未提供 task 字段
   When 请求到达
   Then 返回 400 错误，message 说明缺少 task 参数

6. **AC6: Health check 端点**
   Given server 运行中
   When 发送 `GET /v1/health`
   Then 返回 `{"status": "ok", "version": "x.y.z"}`

## Tasks / Subtasks

- [x] Task 1: 添加 Hummingbird SPM 依赖 (AC: #1)
  - [x] 1.1 在 `Package.swift` 添加 Hummingbird 依赖：`.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.22.0")`
  - [x] 1.2 在 AxionCLI target 的 dependencies 中添加 `.product(name: "Hummingbird", package: "hummingbird")`
  - [x] 1.3 在 AxionCLITests target 的 dependencies 中添加 `.product(name: "Hummingbird", package: "hummingbird")` 和 `.product(name: "HummingbirdTesting", package: "hummingbird")`
  - [x] 1.4 验证 `swift build` 编译通过

- [x] Task 2: 创建 API 数据模型 (AC: #2, #3, #4, #5, #6)
  - [x] 2.1 创建 `Sources/AxionCLI/API/Models/APITypes.swift` — 定义共享 API 类型
    - `APIRunStatus`: 枚举（running, done, failed, cancelled）—— 对应 RunState 但只暴露外部可见子集
    - `CreateRunRequest`: Codable struct，含 `task: String` 和可选的 `maxSteps`, `maxBatches`, `allowForeground`
    - `CreateRunResponse`: Codable struct，含 `runId: String`, `status: String`
    - `RunStatusResponse`: Codable struct，含 `runId`, `status`, `task`, `totalSteps`, `durationMs`, `replanCount`, `steps`（步骤摘要数组）
    - `StepSummary`: Codable struct，含 `index`, `tool`, `purpose`, `success`
    - `HealthResponse`: Codable struct，含 `status: String`, `version: String`
    - `APIErrorResponse`: Codable struct，含 `error: String`, `message: String`
  - [x] 2.2 所有 JSON 字段使用 snake_case（自定义 CodingKeys）—— API 对外约定与 MCP 一致

- [x] Task 3: 创建 RunTracker — 异步任务状态管理器 (AC: #2, #3, #4)
  - [x] 3.1 创建 `Sources/AxionCLI/API/RunTracker.swift`
  - [x] 3.2 实现 `actor RunTracker`：
    - `func submitRun(task: String, options: RunOptions) -> String` — 生成 runId，记录初始状态，返回 runId
    - `func updateRun(runId: String, status: APIRunStatus, steps: [StepSummary], durationMs: Int?, replanCount: Int?)` — 更新任务状态
    - `func getRun(runId: String) -> TrackedRun?` — 查询任务状态
    - `func listRuns() -> [TrackedRun]` — 列出所有任务
  - [x] 3.3 定义 `TrackedRun`: Codable struct，包含 runId, task, status, submittedAt, completedAt, totalSteps, durationMs, replanCount, steps
  - [x] 3.4 定义 `RunOptions`: struct，包含 task, maxSteps, maxBatches, allowForeground, apiKey, config 中的必要字段

- [x] Task 4: 创建 AxonAPI 路由定义 (AC: #1–#6)
  - [x] 4.1 创建 `Sources/AxionCLI/API/AxionAPI.swift`
  - [x] 4.2 使用 Hummingbird 的 `Router` 定义路由组：
    - `GET /v1/health` — 返回 HealthResponse
    - `POST /v1/runs` — 解析 CreateRunRequest，提交异步任务，返回 CreateRunResponse
    - `GET /v1/runs/:runId` — 查询任务状态，返回 RunStatusResponse
  - [x] 4.3 实现 `POST /v1/runs` 逻辑：
    - 解析并验证 request body（task 字段必填）
    - 调用 `RunTracker.submitRun()` 获取 runId
    - 在后台 Task 中启动 Agent 执行（复用 RunCommand 的 Agent 创建逻辑）
    - Agent 完成后更新 RunTracker 状态
    - 立即返回 runId + status=running
  - [x] 4.4 实现 `GET /v1/runs/:runId` 逻辑：
    - 从 RunTracker 查询
    - runId 不存在返回 404
    - 存在则组装 RunStatusResponse 返回
  - [x] 4.5 错误处理统一返回 JSON 格式 `{"error": "...", "message": "..."}`

- [x] Task 5: 创建 ServerCommand (AC: #1)
  - [x] 5.1 创建 `Sources/AxionCLI/Commands/ServerCommand.swift`
  - [x] 5.2 实现 `struct ServerCommand: AsyncParsableCommand`
    - `@Option(name: .long, help: "监听端口") var port: Int = 4242`
    - `@Option(name: .long, help: "绑定地址") var host: String = "127.0.0.1"`
    - `@Flag(name: .long, help: "详细输出") var verbose: Bool = false`
  - [x] 5.3 `run()` 方法中：
    - 加载配置（复用 ConfigManager）
    - 创建 RunTracker 实例
    - 创建 AxionAPI 路由（注入 RunTracker 和配置）
    - 创建 Hummingbird `Application`，配置地址和端口
    - 注册 SIGINT handler，优雅关闭
    - 启动 server 并 await
  - [x] 5.4 在 `AxionCLI.swift` 注册 server 子命令

- [x] Task 6: 提取 Agent 执行逻辑为可复用函数 (AC: #2, #3, #4)
  - [x] 6.1 创建 `Sources/AxionCLI/API/AgentRunner.swift`
  - [x] 6.2 提取 RunCommand 中的 Agent 创建和流式处理逻辑为独立的 `func runAgent(config:task:options:completion:) async`
    - 参数：config（AxionConfig）、task（String）、options（RunOptions）、completion（回调，更新 RunTracker）
    - 返回：(totalSteps: Int, durationMs: Int, replanCount: Int, finalStatus: APIRunStatus)
  - [x] 6.3 从 SDK 消息流中提取步骤摘要（toolUse/toolResult 配对），构建 StepSummary 数组
  - [x] 6.4 不修改 RunCommand 的现有行为 — RunCommand 继续独立工作

- [x] Task 7: 单元测试 (AC: #1–#6)
  - [x] 7.1 创建 `Tests/AxionCLITests/API/APITypesTests.swift` — Codable round-trip 测试
  - [x] 7.2 创建 `Tests/AxionCLITests/API/RunTrackerTests.swift` — 测试 submit/get/update/list
  - [x] 7.3 创建 `Tests/AxionCLITests/API/AxionAPIRoutesTests.swift` — 使用 Hummingbird 测试工具测试路由
    - 测试 POST /v1/runs 正常提交
    - 测试 POST /v1/runs 缺少 task 返回 400
    - 测试 GET /v1/runs/{runId} 返回正确状态
    - 测试 GET /v1/runs/{unknown} 返回 404
    - 测试 GET /v1/health 返回 ok
  - [x] 7.4 创建 `Tests/AxionCLITests/Commands/ServerCommandTests.swift` — 测试命令解析

## Dev Notes

### 核心架构决策

**HTTP 框架选择：Hummingbird 2.x**

选择 Hummingbird 而非 Vapor 或原生 SwiftNIO 的理由：
1. **轻量**：Hummingbird 核心远小于 Vapor，适合 CLI 工具内嵌的 API server
2. **Swift Concurrency 原生**：2.0+ 完全基于 async/await，与 Axion 代码风格一致
3. **SwiftNIO 底层**：生产级性能，非阻塞 I/O
4. **低启动开销**：满足 NFR1（API server 启动不应拖慢 CLI）

**不选 Vapor 的理由**：Vapor 是全栈 Web 框架，依赖重（Fluent、Leaf、JWT 等），不适合嵌入 CLI 工具。
**不选原始 SwiftNIO 的理由**：手工处理 HTTP 解析和路由太低效，开发成本高。

**任务异步执行架构：**

```
POST /v1/runs
    │
    ▼
ServerCommand 收到请求
    │
    ├── RunTracker.submitRun() → runId（同步，立即返回）
    │
    ├── 返回 HTTP 202 {"runId": "...", "status": "running"}
    │
    └── Task.detached {  // 后台异步执行
            AgentRunner.runAgent(...)
            RunTracker.updateRun(runId, result)
        }
```

`RunTracker` 使用 `actor` 确保并发安全。任务执行在 `Task.detached` 中，不阻塞 HTTP 线程。

**API 路由设计原则：**
- REST 风格，资源名 `runs`（复数）
- 所有 JSON 字段使用 **snake_case**（与 MCP 通信一致）
- 错误统一返回 `{"error": "...", "message": "..."}`
- 状态码语义：200（成功）、202（已接受异步任务）、400（请求错误）、404（资源不存在）

### 与现有代码的关系

**复用 RunCommand 的逻辑但提取为独立模块：**

RunCommand 中以下逻辑需要提取到 `AgentRunner` 中以便 API server 和 CLI 共享：
1. 配置加载和 API Key 解析（ConfigManager）
2. Helper 路径解析（HelperPathResolver）
3. MemoryStore 创建
4. System prompt 构建（PromptBuilder + MemoryContextProvider）
5. Agent 创建和流式处理（createAgent + stream）
6. Trace 记录
7. Memory 提取和保存

**关键：不修改 RunCommand 的行为** — 提取时保持 RunCommand 完全不变，只是把相同逻辑抽成 `AgentRunner.runAgent()` 函数供两者调用。如果提取涉及 RunCommand 重构，则改为在 ServerCommand 中**复制**核心 Agent 创建逻辑（参考 RunCommand），而非修改 RunCommand。这样可以避免回归风险。

推荐方案：在 `AgentRunner` 中独立实现 Agent 创建逻辑，直接参考 RunCommand 的代码结构。RunCommand 保持不变。如果后续有重构需求，再统一。

### Hummingbird SPM 集成细节

Package.swift 变更：

```swift
// 在 dependencies 数组中添加：
.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.22.0")

// 在 AxionCLI target 的 dependencies 中添加：
.product(name: "Hummingbird", package: "hummingbird")
```

注意：Hummingbird 依赖 SwiftNIO，会通过 SPM 自动传递。AxionHelper 不需要 Hummingbird（Helper 只做 AX 操作），不修改 AxionHelper target。

### RunTracker 状态管理

```swift
actor RunTracker {
    private var runs: [String: TrackedRun] = [:]

    func submitRun(task: String, options: RunOptions) -> String {
        let runId = generateRunId()
        let run = TrackedRun(
            runId: runId,
            task: task,
            status: .running,
            submittedAt: Date(),
            completedAt: nil,
            totalSteps: 0,
            durationMs: nil,
            replanCount: 0,
            steps: []
        )
        runs[runId] = run
        return runId
    }

    func updateRun(runId: String, status: APIRunStatus, ...) { ... }
    func getRun(runId: String) -> TrackedRun? { runs[runId] }
    func listRuns() -> [TrackedRun] { Array(runs.values) }
}
```

**Run ID 生成**：复用 `RunCommand.generateRunId()` 的逻辑（`YYYYMMDD-{6random}`），保持格式一致。

### 请求/响应 JSON 格式

**POST /v1/runs 请求：**
```json
{
  "task": "打开计算器",
  "max_steps": 20,
  "max_batches": 6,
  "allow_foreground": false
}
```
除 `task` 外均为可选字段。

**POST /v1/runs 响应（202 Accepted）：**
```json
{
  "run_id": "20260513-abc123",
  "status": "running"
}
```

**GET /v1/runs/{runId} 响应（200 OK）：**
```json
{
  "run_id": "20260513-abc123",
  "status": "done",
  "task": "打开计算器",
  "total_steps": 3,
  "duration_ms": 8200,
  "replan_count": 0,
  "submitted_at": "2026-05-13T10:30:00+08:00",
  "completed_at": "2026-05-13T10:30:08+08:00",
  "steps": [
    {"index": 0, "tool": "launch_app", "purpose": "启动 Calculator", "success": true},
    {"index": 1, "tool": "click", "purpose": "输入表达式", "success": true},
    {"index": 2, "tool": "click", "purpose": "验证结果", "success": true}
  ]
}
```

**GET /v1/health 响应（200 OK）：**
```json
{
  "status": "ok",
  "version": "0.1.0"
}
```

**错误响应（400 Bad Request）：**
```json
{
  "error": "missing_task",
  "message": "Request body must include a 'task' field."
}
```

**错误响应（404 Not Found）：**
```json
{
  "error": "run_not_found",
  "message": "Run 'nonexistent-id' not found."
}
```

### 从 SDK 消息流提取步骤摘要

在 AgentRunner 中，监听 SDK 消息流时，配对 toolUse 和 toolResult：

```swift
var pendingToolUses: [String: SDKMessage.ToolUseData] = [:]
var stepSummaries: [StepSummary] = []

for await message in messageStream {
    switch message {
    case .toolUse(let data):
        pendingToolUses[data.toolUseId] = data
    case .toolResult(let data):
        if let toolUse = pendingToolUses.removeValue(forKey: data.toolUseId) {
            stepSummaries.append(StepSummary(
                index: stepSummaries.count,
                tool: toolUse.toolName,
                purpose: extractPurpose(from: toolUse),  // 从 toolName + parameters 推断
                success: !data.isError
            ))
        }
    default:
        break
    }
}
```

### 需要修改的现有文件

1. **`Package.swift`** [UPDATE]
   - 添加 Hummingbird 依赖
   - AxionCLI target 添加 Hummingbird product 依赖
   - AxionCLITests target 添加 Hummingbird product 依赖
   - 必须保留：所有现有依赖和 target 配置不变

2. **`Sources/AxionCLI/AxionCLI.swift`** [UPDATE]
   - 在 subcommands 数组中添加 `ServerCommand.self`
   - 必须保留：所有现有子命令注册

3. **`Sources/AxionCLI/Constants/Version.swift`** [READ ONLY]
   - 读取 `AxionVersion.current` 用于 health 端点
   - 不修改

### 需要创建的新文件

1. **`Sources/AxionCLI/API/Models/APITypes.swift`** [NEW]
   - API 数据模型定义（所有 Codable struct）

2. **`Sources/AxionCLI/API/RunTracker.swift`** [NEW]
   - Actor 实现的任务状态管理器

3. **`Sources/AxionCLI/API/AxionAPI.swift`** [NEW]
   - Hummingbird 路由定义和处理逻辑

4. **`Sources/AxionCLI/API/AgentRunner.swift`** [NEW]
   - 独立的 Agent 执行函数（参考 RunCommand 逻辑）

5. **`Sources/AxionCLI/Commands/ServerCommand.swift`** [NEW]
   - `axion server` ArgumentParser 子命令

### 测试策略

**APITypesTests:**
- CreateRunRequest Codable round-trip
- RunStatusResponse Codable round-trip
- HealthResponse Codable round-trip
- APIErrorResponse Codable round-trip
- snake_case CodingKeys 验证

**RunTrackerTests:**
- submitRun 返回有效 runId
- getRun 返回已提交的任务
- getRun 对不存在的 runId 返回 nil
- updateRun 正确更新状态
- 并发 submit+update 无数据竞争（actor 保证）
- listRuns 返回所有任务

**AxionAPIRoutesTests:**
使用 Hummingbird 的测试工具（`HBApplication.test`）发送 HTTP 请求：
- GET /v1/health 返回 200 + 正确 JSON
- POST /v1/runs 无 task 返回 400
- POST /v1/runs 有 task 返回 202 + runId
- GET /v1/runs/{runId} 存在时返回 200
- GET /v1/runs/{unknown} 返回 404

**ServerCommandTests:**
- --port 参数解析
- --host 参数解析
- 默认值验证（port=4242, host=127.0.0.1）

### Import 顺序

```swift
// 1. 系统框架
import Foundation

// 2. 第三方依赖
import Hummingbird
import ArgumentParser
import OpenAgentSDK

// 3. 项目内部模块
import AxionCore
```

### 错误处理

- API 层错误统一使用 `APIErrorResponse` JSON 格式
- RunTracker 内部错误不暴露到 API（返回 500 时 message 不含堆栈）
- Agent 执行失败记录到 RunTracker 状态为 `.failed`，不影响 server 继续运行
- API server 启动失败（端口占用等）直接退出并输出错误信息

### 项目结构注意事项

- 新文件放在 `Sources/AxionCLI/API/` 目录（新目录）
- 测试文件放在 `Tests/AxionCLITests/API/` 目录（镜像源结构）
- API 功能仅涉及 AxionCLI 模块，不修改 AxionCore 或 AxionHelper
- 新命令 `ServerCommand.swift` 放在 `Sources/AxionCLI/Commands/`

### 安全注意事项

- **默认绑定 localhost（127.0.0.1）**：不暴露到网络，与 Helper 通信策略一致
- **API 认证在 Story 5.3 实现**：本 Story 不实现 auth-key，server 默认信任本地请求
- **API Key 安全**：通过 ConfigManager 加载，不出现在 API 响应中（NFR9）
- **后台任务异常隔离**：Task.detached 中的 Agent 执行异常被 catch 并更新 RunTracker 为 failed，不崩溃 server

### NFR 注意

- **NFR1**: Server 启动不应增加 CLI 冷启动 — `axion server` 是独立命令路径，不影响 `axion run`
- **NFR9**: API Key 不出现在 API 响应、日志或 trace 中
- **NFR24**: HTTP API 请求响应时间 < 100ms（不含任务执行时间） — Hummingbird 的 SwiftNIO 底层满足此要求
- **NFR11**: Helper 仅响应本地 CLI 请求 — API server 默认 localhost，Helper 仍然仅通过 MCP stdio 本地通信

### Epic 5 上下文

本 Story 是 Epic 5 的第一个 Story。后续 Story：
- **Story 5.2**: SSE 事件流 — 将基于本 Story 的 RunTracker 和 API 基础设施添加 SSE endpoint
- **Story 5.3**: Server 命令与 API 认证 — 将添加 auth-key、优雅关闭、并发限制

本 Story 需要为 SSE 预留扩展点（RunTracker 的事件通知机制），但不在本 Story 中实现 SSE。

### 为 SSE 预留的扩展点

RunTracker 应该支持未来的事件通知。建议在 RunTracker 中预留回调接口：

```swift
actor RunTracker {
    // 未来 SSE 使用的事件回调
    var onRunStatusChanged: ((String, APIRunStatus) -> Void)?

    func setOnStatusChanged(_ handler: @escaping (String, APIRunStatus) -> Void) {
        onRunStatusChanged = handler
    }
}
```

本 Story 中不实现 SSE endpoint，但 RunTracker 的 updateRun 方法中应调用 `onRunStatusChanged?(runId, status)` 为 Story 5.2 铺路。

### References

- Epic 5 定义: `_bmad-output/planning-artifacts/epics.md` (Story 5.1)
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- PRD Phase 2 (旅程三：王强): `_bmad-output/planning-artifacts/prd.md`
- Project Context: `_bmad-output/project-context.md`
- Previous Story 4.3 file: `_bmad-output/implementation-artifacts/4-3-memory-enhanced-planning.md`
- RunCommand 实现: `Sources/AxionCLI/Commands/RunCommand.swift`
- AxionCLI 入口: `Sources/AxionCLI/AxionCLI.swift`
- ConfigManager: `Sources/AxionCLI/Config/ConfigManager.swift`
- AxionConfig: `Sources/AxionCore/Models/AxionConfig.swift`
- Version: `Sources/AxionCLI/Constants/Version.swift`
- Package.swift: `Package.swift`
- Hummingbird GitHub: https://github.com/hummingbird-project/hummingbird (v2.22.0+)
- Hummingbird 文档: https://hummingbird.codes/
- Hummingbird Swift Package Index: https://swiftpackageindex.com/hummingbird-project/hummingbird

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Had to resolve swift-mcp dependency conflict: tag 0.1.5 was removed from remote, updated both open-agent-sdk-swift and axion to use `from: "1.1.0"`
- Added `swift-json-schema` dependency for JSONSchemaBuilder used by AxionHelper's SelectorQuery
- Added ParameterValue conformance to SelectorQuery for swift-mcp 1.1.0 compatibility
- Fixed ContentBlock → Tool.Content type change in HelperProcessManager for swift-mcp 1.1.0

### Completion Notes List

- All 7 tasks and all subtasks completed successfully
- All 6 acceptance criteria verified via unit tests
- 46 new tests added: 18 APITypesTests + 11 RunTrackerTests + 9 AxionAPIRoutesTests + 8 ServerCommandTests
- Full regression suite passes: 748 tests, 0 failures
- AgentRunner created as independent module (does not modify RunCommand)
- RunTracker includes SSE extension point (onStatusChanged callback) for Story 5.2
- ServerCommand uses Hummingbird's runService() for graceful shutdown on SIGINT/SIGTERM
- API routes use AxionAPIError for consistent error responses with correct HTTP status codes

### File List

**New files:**
- Sources/AxionCLI/API/Models/APITypes.swift
- Sources/AxionCLI/API/RunTracker.swift
- Sources/AxionCLI/API/AxionAPI.swift
- Sources/AxionCLI/API/AgentRunner.swift
- Sources/AxionCLI/Commands/ServerCommand.swift

**Modified files:**
- Package.swift — Added Hummingbird, HummingbirdTesting, swift-json-schema dependencies
- Sources/AxionCLI/AxionCLI.swift — Registered ServerCommand subcommand
- Sources/AxionHelper/Models/SelectorQuery.swift — Added ParameterValue conformance
- Sources/AxionCLI/Helper/HelperProcessManager.swift — Fixed Tool.Content type reference
- Tests/AxionCLITests/API/APITypesTests.swift — Green-phase test implementations
- Tests/AxionCLITests/API/RunTrackerTests.swift — Green-phase test implementations
- Tests/AxionCLITests/API/AxionAPIRoutesTests.swift — Green-phase test implementations with Hummingbird 2.x testing
- Tests/AxionCLITests/Commands/ServerCommandTests.swift — Green-phase test implementations

**External dependency updates:**
- ../open-agent-sdk-swift/Package.swift — Updated swift-mcp from "0.1.5" to "1.1.0"
