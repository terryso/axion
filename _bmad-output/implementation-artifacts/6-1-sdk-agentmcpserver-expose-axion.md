# Story 6.1: 通过 SDK AgentMCPServer 暴露 Axion

Status: done

## Story

As a 外部 Agent（如 Claude Code）,
I want 通过 MCP stdio 协议调用 Axion 的桌面操作能力,
So that 我的 Agent 可以操控 macOS 桌面而不需要了解 Axion 的内部架构.

## Acceptance Criteria

1. **AC1: MCP initialize 响应**
   Given 运行 `axion mcp`
   When 通过 stdin 发送 MCP initialize 请求
   Then 返回正确的 initialize 响应，声明 Axion 作为 MCP server 的能力

2. **AC2: tools/list 返回工具列表**
   Given MCP 连接已建立
   When 发送 tools/list
   Then 返回 Axion 暴露的工具列表（run_task、query_task_status、list_apps 等）

3. **AC3: run_task 异步执行**
   Given 外部 Agent 发送 tool_call `run_task`
   When 参数包含 `{"task": "打开计算器，计算 1+1"}`
   Then Axion 启动任务执行，返回 runId

4. **AC4: query_task_status 状态查询**
   Given 外部 Agent 发送 tool_call `query_task_status`
   When 参数包含 runId
   Then 返回任务当前状态和已执行步骤摘要

5. **AC5: 优雅退出**
   Given Axion MCP server 运行中
   When stdin 收到 EOF
   Then 等待运行中的任务完成后优雅退出

## Tasks / Subtasks

- [x] Task 1: 创建 McpCommand CLI 子命令 (AC: #1)
  - [x] 1.1 创建 `Sources/AxionCLI/Commands/McpCommand.swift`
  - [x] 1.2 添加 `@Flag(name: .long, help: "详细输出") var verbose: Bool = false`
  - [x] 1.3 在 `run()` 方法中：加载配置、创建 MCPServerRunner、启动 MCP server
  - [x] 1.4 日志输出到 stderr（stdout 仅用于 MCP 协议通信）
  - [x] 1.5 在 `Sources/AxionCLI/AxionCLI.swift` 中注册 McpCommand 子命令

- [x] Task 2: 创建 MCPServerRunner 编排器 (AC: #1, #2, #5)
  - [x] 2.1 创建 `Sources/AxionCLI/MCP/MCPServerRunner.swift`
  - [x] 2.2 实现 `MCPServerRunner` struct：
    - `init(config:AxionConfig, verbose:Bool)`
    - `func run() async throws` — 主入口
  - [x] 2.3 `run()` 方法流程：
    - 创建 AgentOptions（复用 AgentRunner 的配置逻辑：API key、Helper path、prompt、memory、safety hooks）
    - 创建 Agent（`createAgent(options:)`）
    - 调用 `agent.assembleFullToolPool()` 获取 Helper 工具列表
    - 创建 RunTracker 实例（用于 async 任务追踪）
    - 创建自定义工具：RunTaskTool、QueryTaskStatusTool
    - 合并所有工具：Helper 工具 + 自定义工具
    - 创建 `AgentMCPServer(name:"axion", version:version, tools:allTools)`
    - 调用 `server.run(agent:agent)` — 阻塞直到 stdin EOF
  - [x] 2.4 在 `server.run()` 返回后执行清理（关闭 Agent、等待运行中任务）

- [x] Task 3: 创建 RunTaskTool 自定义工具 (AC: #3)
  - [x] 3.1 创建 `Sources/AxionCLI/MCP/RunTaskTool.swift`
  - [x] 3.2 实现 `ToolProtocol`：
    - `name = "run_task"`
    - `description = "Submit a desktop automation task for execution. Returns a run ID for tracking."`
    - `inputSchema` = `{"type":"object","properties":{"task":{"type":"string","description":"Task description"}},"required":["task"]}`
    - `isReadOnly = false`
  - [x] 3.3 `call(input:context:)` 实现：
    - 解析 `task` 参数
    - 通过 RunTracker 生成 runId 并 submitRun
    - 在后台 Task 中执行 agent.prompt(task)（使用 MCPServerRunner 持有的 Agent）
    - 立即返回 `{"run_id":"...","status":"running"}` JSON
    - 执行完成后调用 runTracker.updateRun() 更新状态
  - [x] 3.4 使用 actor `TaskQueue` 序列化并发 run_task 请求（同一 Agent 同时只能处理一个 prompt）

- [x] Task 4: 创建 QueryTaskStatusTool 自定义工具 (AC: #4)
  - [x] 4.1 创建 `Sources/AxionCLI/MCP/QueryTaskStatusTool.swift`
  - [x] 4.2 实现 `ToolProtocol`：
    - `name = "query_task_status"`
    - `description = "Query the status of a previously submitted task."`
    - `inputSchema` = `{"type":"object","properties":{"run_id":{"type":"string","description":"Run ID returned by run_task"}},"required":["run_id"]}`
    - `isReadOnly = true`
  - [x] 4.3 `call(input:context:)` 实现：
    - 解析 `run_id` 参数
    - 从 RunTracker 获取任务状态
    - 返回 JSON：`{"run_id":"...","status":"running|done|failed","steps":[...],"duration_ms":...}`
    - runId 不存在时返回错误 JSON

- [x] Task 5: 单元测试 (AC: #1–#5)
  - [x] 5.1 创建 `Tests/AxionCLITests/MCP/RunTaskToolTests.swift`
    - ToolProtocol 属性验证（name、description、inputSchema）
    - call() 返回包含 run_id 的 JSON
    - 缺少 task 参数返回错误
  - [x] 5.2 创建 `Tests/AxionCLITests/MCP/QueryTaskStatusToolTests.swift`
    - 查询已知 runId 返回正确状态
    - 查询未知 runId 返回错误
  - [x] 5.3 创建 `Tests/AxionCLITests/Commands/McpCommandTests.swift`
    - McpCommand 注册到 AxionCLI
    - --help 输出包含 MCP server 说明
  - [x] 5.4 创建 `Tests/AxionCLITests/MCP/TaskQueueTests.swift`
    - 串行执行验证
    - 并发请求排队验证

## Dev Notes

### 核心架构决策

**SDK AgentMCPServer 集成模式**

使用 SDK 的 `AgentMCPServer` 类暴露 Axion 的能力。SDK 自动处理：
- MCP stdio 传输层（stdin/stdout JSON-RPC）
- 工具注册和发现（tools/list）
- 工具调用路由（tool_call → ToolProtocol.call()）
- `agent_prompt` 特殊工具（同步全自主执行）

```swift
// SDK AgentMCPServer API (已存在于 SDK)
let server = AgentMCPServer(name: "axion", version: "1.0.0", tools: allTools)
try await server.run(agent: agent)  // 阻塞直到 stdin EOF
```

AgentMCPServer 位于 `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/MCP/AgentMCPServer.swift`。

**工具暴露策略**

暴露两类工具：
1. **Helper 工具**（来自 Agent 的 tool pool）：`list_apps`、`launch_app`、`click`、`type_text` 等所有 AxionHelper 工具。外部 Agent 可直接调用这些原子操作。
2. **自定义业务工具**：`run_task`（异步任务提交）和 `query_task_status`（状态查询）。用于需要完整 Agent 自主执行的场景。

加上 SDK 自动注册的 `agent_prompt`（同步任务执行），外部 Agent 共有三类使用模式。

**Helper 进程与并发约束**

关键约束：AxionHelper 是单进程 stdio MCP server，同一时间只能服务一个 MCP 客户端连接。

- MCP server 的 Agent 连接到 Helper → 支持直接工具调用（list_apps 等）
- `run_task` 使用同一个 Agent 的 `agent.prompt(task)` → 需要串行化
- 使用 actor `TaskQueue` 确保同一时间只有一个 run_task 在执行
- `agent_prompt`（SDK 自动注册）也是同步的，同样通过 Agent 执行

**run_task 异步执行设计**

```
外部 Agent → MCP tool_call "run_task" {"task":"..."}
    │
    ├── RunTaskTool.call()
    │   ├── RunTracker.submitRun() → 生成 runId
    │   ├── TaskQueue.enqueue(runId, task) → 排队执行
    │   └── 立即返回 {"run_id":"...","status":"running"}
    │
    └── 后台 Task（串行执行）
        ├── agent.prompt(task) → 使用已连接 Helper 的 Agent
        ├── RunTracker.updateRun(status:done/failed, ...)
        └── 完成
```

外部 Agent 可通过 `query_task_status` 轮询结果，或在 `agent_prompt`（同步）和 `run_task`（异步）之间选择。

### 需要修改的现有文件

1. **`Sources/AxionCLI/AxionCLI.swift`** [UPDATE]
   - 在 `subcommands` 数组中添加 `McpCommand.self`
   - 必须保留：所有现有子命令注册

### 需要创建的新文件

1. **`Sources/AxionCLI/Commands/McpCommand.swift`** [NEW]
   - `axion mcp` CLI 子命令，ArgumentParser 集成

2. **`Sources/AxionCLI/MCP/MCPServerRunner.swift`** [NEW]
   - 编排器：创建 Agent、组装工具、启动 AgentMCPServer

3. **`Sources/AxionCLI/MCP/RunTaskTool.swift`** [NEW]
   - `run_task` ToolProtocol 实现

4. **`Sources/AxionCLI/MCP/QueryTaskStatusTool.swift`** [NEW]
   - `query_task_status` ToolProtocol 实现

5. **`Sources/AxionCLI/MCP/TaskQueue.swift`** [NEW]
   - Actor，串行化 agent.prompt 调用

6. **`Tests/AxionCLITests/MCP/RunTaskToolTests.swift`** [NEW]

7. **`Tests/AxionCLITests/MCP/QueryTaskStatusToolTests.swift`** [NEW]

8. **`Tests/AxionCLITests/MCP/TaskQueueTests.swift`** [NEW]

9. **`Tests/AxionCLITests/Commands/McpCommandTests.swift`** [NEW]

### Package.swift 无需修改

AxionCLI 已依赖 `OpenAgentSDK`（包含 AgentMCPServer）和 `MCP`（swift-mcp）。无需新增依赖。

### Import 顺序

```swift
// McpCommand.swift
import ArgumentParser
import Foundation

import AxionCore

// MCPServerRunner.swift
import Foundation
import OpenAgentSDK

import AxionCore

// RunTaskTool.swift / QueryTaskStatusTool.swift
import Foundation
import OpenAgentSDK

import AxionCore
```

### MCPServerRunner 核心实现参考

```swift
struct MCPServerRunner {
    let config: AxionConfig
    let verbose: Bool

    func run() async throws {
        // 1. 复用 AgentRunner 的配置逻辑
        let apiKey = config.apiKey
            ?? ProcessInfo.processInfo.environment["AXION_API_KEY"]
        guard let apiKey, !apiKey.isEmpty else {
            fputs("Error: API key not configured. Run `axion setup`.\n", stderr)
            return
        }

        guard let helperPath = HelperPathResolver.resolveHelperPath() else {
            fputs("Error: AxionHelper not found.\n", stderr)
            return
        }

        // 2. 配置 MCP server for Helper
        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        // 3. 构建系统 prompt（复用 AgentRunner 逻辑）
        // ... load prompt, inject memory context ...

        // 4. 创建 Agent
        let agentOptions = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: config.maxSteps,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers,
            memoryStore: memoryStore,
            hookRegistry: hookRegistry,
            logLevel: verbose ? .debug : .info
        )
        let agent = createAgent(options: agentOptions)

        // 5. 组装工具池（连接 Helper、发现工具）
        let (helperTools, _) = await agent.assembleFullToolPool()

        // 6. 创建 RunTracker 和自定义工具
        let runTracker = RunTracker()
        let taskQueue = TaskQueue()
        let runTaskTool = RunTaskTool(agent: agent, runTracker: runTracker, taskQueue: taskQueue)
        let queryTool = QueryTaskStatusTool(runTracker: runTracker)

        // 7. 合并所有工具
        var allTools = helperTools
        allTools.append(runTaskTool)
        allTools.append(queryTool)

        // 8. 创建并运行 MCP server
        let version = AxionVersion.current
        let server = AgentMCPServer(name: "axion", version: version, tools: allTools)

        fputs("Axion MCP server running (version \(version))\n", stderr)
        try await server.run(agent: agent)

        // 9. 清理
        try? await agent.close()
        fputs("Axion MCP server stopped.\n", stderr)
    }
}
```

### RunTaskTool 实现参考

```swift
struct RunTaskTool: ToolProtocol {
    let name = "run_task"
    let description = "Submit a desktop automation task for async execution. Returns a run ID for tracking status."
    let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": ["task": ["type": "string", "description": "Task description"]],
        "required": ["task"]
    ]
    let isReadOnly = false

    private let agent: Agent
    private let runTracker: RunTracker
    private let taskQueue: TaskQueue

    func call(input: Any, context: ToolContext) async -> ToolResult {
        guard let params = input as? [String: Any],
              let task = params["task"] as? String else {
            return ToolResult(toolUseId: context.toolUseId, content: "{\"error\":\"missing_task\",\"message\":\"Missing required 'task' parameter\"}", isError: true)
        }

        let runId = await runTracker.submitRun(task: task, options: RunOptions(task: task))

        // 在后台串行执行
        await taskQueue.enqueue {
            let result = await self.agent.prompt(task)
            let status: APIRunStatus = result.status == .success ? .done : .failed
            await self.runTracker.updateRun(
                runId: runId, status: status, steps: [], durationMs: nil, replanCount: 0
            )
        }

        let response = "{\"run_id\":\"\(runId)\",\"status\":\"running\"}"
        return ToolResult(toolUseId: context.toolUseId, content: response, isError: false)
    }
}
```

### 错误处理

- API Key 未配置 → stderr 输出错误信息，不启动 server
- Helper 未找到 → stderr 输出错误信息，不启动 server
- run_task 缺少 task 参数 → 返回 MCP isError=true + 错误 JSON
- query_task_status 未知 runId → 返回错误 JSON（非 MCP error）
- Agent 执行失败 → 更新 RunTracker 状态为 failed

### NFR 注意

- **NFR26**: MCP server 工具调用响应时间 < 200ms（不含任务执行时间）— run_task 立即返回 runId，满足要求
- **NFR3**: 单个 AX 操作 < 200ms — Helper 工具直接通过 Agent 的 MCP 客户端调用，延迟与 RunCommand 一致
- **stdout 纯净**: MCP 协议通信仅通过 stdout，所有日志和诊断信息输出到 stderr

### 项目结构注意事项

- 新建 `Sources/AxionCLI/MCP/` 目录存放 MCP server 相关代码
- 新建 `Tests/AxionCLITests/MCP/` 目录存放对应测试
- 所有变更仅在 AxionCLI 模块内，不修改 AxionCore 或 AxionHelper

### 前一 Epic 的关键学习

- **AgentRunner 模式**：Epic 5 的 AgentRunner 封装了完整的 Agent 创建和执行逻辑，MCP server 复用相同模式
- **RunTracker 复用**：Epic 5 的 RunTracker 直接用于 MCP 模式的任务追踪
- **ConfigManager 复用**：配置加载逻辑与 ServerCommand 一致
- **HelperPathResolver**：Helper 路径解析已封装
- **EventBroadcaster 可选**：MCP 模式不需要 SSE 事件推送
- **swift-mcp 2.0.4**：注意 Tool.Content 类型变更
- **AxionVersion.current**：版本号常量已存在

### SDK AgentMCPServer 测试模式

SDK 提供 `createSession()` 用于 in-process 测试，无需真实 stdio：

```swift
let server = AgentMCPServer(name: "axion", version: "1.0.0", tools: [myTool])
let (mcpServer, transport) = try await server.createSession()
let client = Client(name: "test-client", version: "1.0.0")
try await client.connect(transport: transport)
```

单元测试可使用此模式验证 MCP 协议行为（initialize、tools/list、tool_call）。

### References

- Epic 6 定义: `_bmad-output/planning-artifacts/epics.md` (Story 6.1)
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Project Context: `_bmad-output/project-context.md`
- Previous Story 5.3: `_bmad-output/implementation-artifacts/5-3-server-command-api-authentication.md`
- SDK AgentMCPServer: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/MCP/AgentMCPServer.swift`
- SDK ToolProtocol: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/ToolTypes.swift`
- SDK Agent: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift`
- AgentRunner: `Sources/AxionCLI/API/AgentRunner.swift`
- RunTracker: `Sources/AxionCLI/API/RunTracker.swift`
- ServerCommand: `Sources/AxionCLI/Commands/ServerCommand.swift`
- AxionCLI main: `Sources/AxionCLI/AxionCLI.swift`
- ToolNames: `Sources/AxionCore/Constants/ToolNames.swift`
- API Types: `Sources/AxionCLI/API/Models/APITypes.swift`

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- TaskQueue actor 需要正确的 isRunning 状态管理，不能用 currentTask 引用方式
- SDK assembleFullToolPool() 需要从 internal 改为 public 以便外部模块调用
- Swift 6 Sendable 检查：inputSchema [String:Any] 需要 nonisolated(unsafe) 标注

### Completion Notes List

- McpCommand 注册到 AxionCLI，支持 --verbose flag
- MCPServerRunner 复用 AgentRunner 的配置逻辑（API key、Helper path、prompt、memory、safety hooks）
- RunTaskTool 实现异步任务提交，立即返回 runId
- QueryTaskStatusTool 查询任务状态，支持 known/unknown runId
- TaskQueue actor 串行化 agent.prompt() 调用
- SDK 变更：Agent.assembleFullToolPool() 从 internal 改为 public
- 26 个新单元测试全部通过，265 个总测试零回归

### File List

#### New Files
- Sources/AxionCLI/Commands/McpCommand.swift
- Sources/AxionCLI/MCP/MCPServerRunner.swift
- Sources/AxionCLI/MCP/RunTaskTool.swift
- Sources/AxionCLI/MCP/QueryTaskStatusTool.swift
- Sources/AxionCLI/MCP/TaskQueue.swift
- Tests/AxionCLITests/MCP/RunTaskToolTests.swift
- Tests/AxionCLITests/MCP/QueryTaskStatusToolTests.swift
- Tests/AxionCLITests/MCP/TaskQueueTests.swift
- Tests/AxionCLITests/Commands/McpCommandTests.swift

#### Modified Files
- Sources/AxionCLI/AxionCLI.swift (added McpCommand to subcommands)
- ../open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift (assembleFullToolPool made public)

## Senior Developer Review (AI)

**Reviewer:** Claude (adversarial review) on 2026-05-14
**Outcome:** Approved with fixes applied

### Issues Found and Fixed

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| H1 | HIGH | TaskQueue 无 graceful shutdown — AC5 要求等待运行中任务完成后退出 | 添加 `gracefulShutdown()` 方法，等待当前任务完成，取消排队任务 |
| H2 | HIGH | MCPServerRunner cleanup 直接 agent.close() 不等待 TaskQueue | 添加 `await taskQueue.gracefulShutdown()` 在 agent.close() 之前 |
| M1 | MEDIUM | QueryTaskStatusTool 手动 JSON 拼接不转义特殊字符 | 改用 JSONEncoder + Codable response struct |
| M2 | MEDIUM | 错误响应缺少 suggestion 字段（项目规范要求 3 字段） | 补充 suggestion 字段 |
| M3 | MEDIUM | RunTaskTool 手动 JSON 拼接 | 改用 JSONEncoder + Codable response struct |
| L1 | LOW | TaskQueue.swift 导入未使用的 AxionCore | 移除未使用 import |

### Test Results After Fixes
- 28 Story 6.1 tests: 0 failures
- 844 total unit tests: 0 failures (zero regression)

### Change Log
- 2026-05-14: Review completed — 2 HIGH + 3 MEDIUM + 1 LOW fixed, all auto-applied
