# Story 3.1: Helper 进程管理器与 MCP 客户端连接

Status: ready-for-dev

## Story

As a CLI 进程,
I want 自动启动 Helper 并建立 MCP 连接,
so that CLI 可以无缝调用 Helper 的桌面操作工具.

## Acceptance Criteria

1. **AC1: 启动 Helper 并建立 MCP 连接**
   - Given CLI 首次需要 Helper
   - When `HelperProcessManager.start()` 调用
   - Then 启动 AxionHelper.app 进程并通过 stdio 建立 MCP 连接

2. **AC2: MCP 连接就绪确认**
   - Given Helper 已启动
   - When 检查连接状态
   - Then MCP 连接就绪，可以发送工具调用请求

3. **AC3: 正常退出清理**
   - Given CLI 正常退出
   - When `HelperProcessManager.stop()` 调用
   - Then 关闭 stdin 管道发送 EOF，Helper 在 3 秒内优雅退出；超时则 SIGKILL

4. **AC4: 强制终止回退**
   - Given Helper 无响应
   - When `stop()` 等待超过 3 秒
   - Then 发送 SIGKILL 强制终止

5. **AC5: Ctrl-C 信号传播（NFR8）**
   - Given 用户按下 Ctrl-C
   - When 信号处理触发
   - Then Helper 进程被正确清理，不留僵尸进程

6. **AC6: Helper 崩溃检测与重启**
   - Given Helper 意外崩溃
   - When 进程监控检测到
   - Then 尝试重启一次 Helper 并重建 MCP 连接

## Tasks / Subtasks

- [ ] Task 1: 创建 HelperProcessManager actor (AC: #1–#6)
  - [ ] 1.1 创建 `Sources/AxionCLI/Helper/HelperProcessManager.swift`
  - [ ] 1.2 定义 actor 结构，含私有状态：`mcpClient`、`transport`、`hasRestarted`、`monitorTask`
  - [ ] 1.3 实现 `start() async throws`：解析 Helper 路径 → 创建 MCPStdioTransport → 创建 MCPClient → 连接 → 启动崩溃监控
  - [ ] 1.4 实现 `stop() async`：关闭 MCP 连接 → 关闭 stdin EOF → 等 3 秒 → 超时 SIGKILL
  - [ ] 1.5 实现 `isRunning() -> Bool`
  - [ ] 1.6 实现 `callTool(name:arguments:) async throws -> String`（AxionCore.Value → MCP.Value 转换）
  - [ ] 1.7 实现 `listTools() async throws -> [String]`
  - [ ] 1.8 实现崩溃监控：DispatchGroup 追踪 Process 存活 → 检测意外退出 → 自动重启一次
  - [ ] 1.9 实现 `setupSignalHandling()`：注册 SIGINT handler，Ctrl-C 时调用 stop()

- [ ] Task 2: 集成到 RunCommand (AC: #1)
  - [ ] 2.1 修改 `Sources/AxionCLI/Commands/RunCommand.swift`：在 `run()` 中创建 HelperProcessManager 并 start
  - [ ] 2.2 添加 defer 块确保退出时调用 stop()
  - [ ] 2.3 添加 try/await 支持（将 run() 改为 async）

- [ ] Task 3: 编写单元测试 (AC: #1–#6)
  - [ ] 3.1 创建 `Tests/AxionCLITests/Helper/HelperProcessManagerTests.swift`
  - [ ] 3.2 测试 `test_start_throwsWhenHelperPathNotFound` — Helper 路径未找到时抛出 helperNotRunning 错误
  - [ ] 3.3 测试 `test_start_connectsMCPClient` — Mock transport 验证 MCP 连接建立
  - [ ] 3.4 测试 `test_stop_closesMCPClientAndTransport` — stop 关闭连接
  - [ ] 3.5 测试 `test_callTool_convertsValueTypes` — AxionCore.Value 正确转换为 MCP.Value
  - [ ] 3.6 测试 `test_callTool_extractsTextFromResult` — MCP ToolResult 正确提取文本
  - [ ] 3.7 测试 `test_listTools_returnsToolNames` — 工具列表获取
  - [ ] 3.8 测试 `test_crashMonitor_restartsOnce` — 崩溃后重启一次
  - [ ] 3.9 测试 `test_crashMonitor_doesNotRestartTwice` — 二次崩溃不再重启
  - [ ] 3.10 测试 `test_stop_gracefulShutdown_closesStdinFirst` — 先关 stdin 再 terminate
  - [ ] 3.11 测试 `test_start_throwsHelperConnectionFailed_onMCPError` — MCP 握手失败时抛出 helperConnectionFailed

- [ ] Task 4: 运行全部单元测试确认无回归
  - [ ] 4.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认全部通过

## Dev Notes

### 核心目标

Epic 3 的第一个 Story。Epic 1（AxionHelper 桌面操作引擎）和 Epic 2（CLI 安装配置）已完成。本 Story 实现 CLI 到 Helper 的连接桥梁：自动启动 Helper 进程、建立 MCP stdio 连接、管理进程生命周期（启动、停止、崩溃恢复、Ctrl-C 清理）。

### 关键设计决策：使用 SDK 的 MCP 客户端

**必须使用 OpenAgentSDK 提供的 MCP 客户端组件（FR37），不能自己实现 JSON-RPC 通信。**

SDK 提供三个关键组件：

| 组件 | 用途 | 来源 |
|------|------|------|
| `MCPStdioTransport` (actor) | 启动子进程、管理 stdin/stdout 管道、JSON-RPC 消息帧 | `OpenAgentSDK/Tools/MCP/` |
| `MCPClient` | MCP 握手（initialize）、工具发现（listTools）、工具调用（callTool） | `mcp-swift-sdk` (import MCP) |
| `McpStdioConfig` | 配置子进程路径和参数 | `OpenAgentSDK/Types/MCPConfig.swift` |

**连接流程：**
```swift
let config = McpStdioConfig(command: helperPath)
let transport = MCPStdioTransport(config: config)
try await transport.connect()           // 启动 Helper 进程
let client = MCPClient(name: "AxionCLI", version: "1.0.0")
try await client.connect { transport }  // MCP 握手
let tools = try await client.listTools() // 工具发现
```

**为什么不直接用 `MCPClientManager`：**
- SDK 的 `MCPClientManager` 已封装上述流程，但它的 `disconnect()` 直接调用 `process.terminate()`（SIGKILL），不支持优雅关闭
- Axion 需要先关 stdin EOF → 等 3 秒 → 超时才 SIGKILL 的优雅关闭流程
- Axion 需要崩溃检测和单次重启逻辑
- Axion 需要 Ctrl-C 信号传播

因此 `HelperProcessManager` 直接使用 `MCPClient` + `MCPStdioTransport`，在它们之上添加 Axion 特有的生命周期管理。

### AxionCore.Value → MCP.Value 转换

`MCPClientProtocol.callTool(name:arguments:)` 使用 AxionCore 的 `Value` 枚举，但 SDK 的 `MCPClient.callTool()` 需要 `[String: MCP.Value]?`。必须实现双向转换：

```swift
// AxionCore.Value → MCP.Value
private func toMCPValue(_ value: AxionCore.Value) -> MCP.Value {
    switch value {
    case .string(let s): return .string(s)
    case .int(let i): return .int(i)
    case .bool(let b): return .bool(b)
    case .placeholder(let p): return .string(p) // 已被 PlaceholderResolver 替换
    }
}
```

### MCP ToolResult → String 提取

SDK 的 `MCPClient.callTool()` 返回 `CallTool.Result`（含 `content: [Content]` 和 `isError: Bool?`）。Axion 的 `MCPClientProtocol` 需要 `String` 返回。提取逻辑（参考 SDK 的 `MCPClientWrapper`）：

```swift
let textParts = result.content.compactMap { content -> String? in
    if case .text(let text, _, _) = content { return text }
    return nil
}
return textParts.joined(separator: "\n")
```

### 优雅关闭流程

SDK 的 `MCPStdioTransport.disconnect()` 直接调用 `process.terminate()`。Axion 需要更精细的关闭流程：

```
stop() 调用:
1. await mcpClient.disconnect()      // 断开 MCP 会话
2. 关闭 stdin pipe (发送 EOF)        // Helper 收到 EOF 后优雅退出（已验证）
3. 等待最多 3 秒 process.isRunning == false
4. 如果超时 → process.terminate()    // SIGTERM（macOS Process.terminate 是 SIGTERM）
5. 再等 1 秒 → 如果仍然运行 → force terminate
6. 清理 transport 和 file descriptors
```

**注意：** macOS 的 `Process.terminate()` 发送的是 SIGTERM，不是 SIGKILL。如果 Helper 不处理 SIGTERM，需要进一步处理。但 Helper 已经实现了 EOF 优雅退出（HelperProcessSmokeTests 验证），所以关闭 stdin 是首选方案。

由于 `MCPStdioTransport` 的 stdin pipe 是私有的（`outputFd: FileDescriptor?`），我们无法直接关闭它。替代方案：
- 调用 `transport.disconnect()` 后检查进程状态
- 或在 `HelperProcessManager` 中单独持有 stdin pipe 的引用

**推荐方案：** 让 `HelperProcessManager` 额外持有 stdin pipe 的写端引用。在 `start()` 时，创建 Pipe 并传给 MCPStdioTransport（通过 `McpStdioConfig` 或直接设置 Process 的 standardInput）。

实际上 `MCPStdioTransport` 在内部创建 Pipe 并管理。我们没有直接访问 stdin 写端的途径。

**最终方案：** 调用 `transport.disconnect()`（它会 terminate 进程并关闭所有管道），然后在 `HelperProcessManager` 层面添加等待逻辑。具体来说：
1. 调用 `await client.disconnect()` 断开 MCP 会话
2. 调用 `await transport.disconnect()` — 这会 terminate 进程
3. 等待进程退出（DispatchGroup 或轮询 isRunning）
4. 如果 Helper 在 disconnect 之前已经自己处理了 EOF 退出，那就是最理想的路径

对于 MVP，使用 `transport.disconnect()` 的 SIGTERM 行为 + 等待确认退出即可。Helper 本身已有 EOF 处理，当 MCPClient 断开时会关闭连接，transport 关闭管道，Helper 自然退出。

### 崩溃监控与重启

```swift
private func startCrashMonitoring() {
    monitorTask = Task { [weak self = self] in
        // 监控 transport 的连接状态
        // 当检测到意外断开且非主动 stop：
        //   if !hasRestarted {
        //     hasRestarted = true
        //     try? await start() // 重启
        //   }
    }
}
```

具体实现：`MCPStdioTransport` 有 `isRunning` 属性。在 `start()` 后启动一个后台 Task 定期检查 transport 连接状态。当 `isRunning` 变为 `false` 且不是主动调用 `stop()` 导致的，触发重启。

用 `@Sendable` 闭包捕获 `self` 时注意 actor 隔离。

### 信号处理（Ctrl-C）

```swift
func setupSignalHandling() {
    signal(SIGINT) { [weak self] sig in
        Task { await self?.stop() }
    }
}
```

**注意：** Swift 6 严格并发模式下，signal handler 必须是 `@Sendable` 且不能直接捕获 actor-isolated 状态。使用 `Task` 桥接到 async 上下文。实际实现可能需要用 `nonisolated(unsafe)` 或其他方式处理。

### 现有代码状态

**HelperPathResolver.swift（已完成 — 直接复用）：**
- `resolveHelperPath() -> String?` 三策略路径解析
- 本 Story 通过 `HelperPathResolver.resolveHelperPath()` 获取 Helper 可执行文件路径

**MCPClientProtocol.swift（已定义 — 实现目标接口）：**
```swift
protocol MCPClientProtocol {
    func callTool(name: String, arguments: [String: Value]) async throws -> String
    func listTools() async throws -> [String]
}
```
- `HelperProcessManager` 不直接实现此协议（它是 actor，协议方法是同步的）
- `HelperProcessManager` 提供同名方法供 `StepExecutor` 调用
- 未来 Story 可以通过协议注入方式解耦

**AxionError.swift（已完成 — 错误类型）：**
- `.helperNotRunning` — Helper 未运行
- `.helperConnectionFailed(reason: String)` — 连接失败
- 直接使用这些错误 case，不创建新错误类型

**RunCommand.swift（当前 placeholder — 需修改）：**
```swift
func run() throws {
    throw CleanExit.message("Run command not yet implemented (Epic 3)")
}
```
- 需要将 `run()` 改为 `async throws`（ArgumentParser 支持 `AsynchronousParsableCommand`）
- 在其中创建 `HelperProcessManager`、调用 start、添加 defer stop

### 模块依赖规则

```
HelperProcessManager.swift 可以 import:
  - Foundation (系统)
  - ArgumentParser (第三方)
  - OpenAgentSDK (第三方 — MCPStdioTransport, McpStdioConfig)
  - MCP (第三方 — MCPClient, CallTool.Result, MCP.Value)
  - AxionCore (项目内部 — MCPClientProtocol, AxionError, Value)

禁止 import:
  - AxionHelper (进程隔离 — 仅通过 MCP stdio 通信)
```

### import 顺序

```swift
// HelperProcessManager.swift
import Foundation
import MCP
import OpenAgentSDK

import AxionCore
```

### 目录结构

```
Sources/AxionCLI/
  Helper/
    HelperPathResolver.swift          # 已存在（复用）
    HelperProcessManager.swift        # 新建：进程管理器 + MCP 客户端
  Commands/
    RunCommand.swift                  # 修改：集成 HelperProcessManager

Tests/AxionCLITests/
  Helper/
    HelperPathResolverTests.swift     # 已存在
    HelperProcessManagerTests.swift   # 新建：单元测试
```

### 测试策略

**Mock 策略：**
- Mock `MCPStdioTransport`：因为 `MCPStdioTransport` 是 actor 且依赖真实 Process，需要通过协议抽象注入
- 实际上 SDK 的 `MCPStdioTransport` 不是 protocol 而是 concrete actor，不能直接 Mock
- **方案 A（推荐）：** 创建 `HelperTransportProtocol` 抽象 transport 的 connect/disconnect/isRunning，生产环境用 `MCPStdioTransport`，测试用 MockTransport
- **方案 B：** 仅测试非 Process 依赖的逻辑（Value 转换、状态管理），Process 级别的测试留给集成测试

**测试隔离：**
- 不启动真实 Helper 进程（属于集成测试范围）
- 通过协议注入 Mock MCPClient 和 Mock Transport
- 测试 HelperProcessManager 的状态管理和逻辑

### 禁止事项（反模式）

- **不得绕过 SDK 直接实现 JSON-RPC** — 必须使用 SDK 的 MCPClient + MCPStdioTransport（FR37）
- **不得创建新的错误类型** — 使用 `AxionError.helperNotRunning` 和 `.helperConnectionFailed(reason:)`
- **不得使用 `print()` 输出** — 未来通过 OutputProtocol 输出（本 Story 暂不集成 OutputProtocol）
- **不得在 HelperProcessManager 中做 LLM 调用** — 只负责 MCP 连接管理
- **AxionCLI 不得 import AxionHelper** — 两者仅通过 MCP stdio 通信

### 与前后 Story 的关系

- **Epic 1（已完成）**：Helper MCPServer + 所有桌面操作工具已实现。Helper 通过 stdin EOF 优雅退出（已在 HelperProcessSmokeTests 中验证）
- **Story 2.5（已完成）**：Homebrew 安装布局和 HelperPathResolver。Helper 安装路径为 `libexec/axion/AxionHelper.app`
- **Story 3.2（下一个）**：Prompt 管理与规划引擎。Planner 需要 HelperProcessManager 提供 MCPClientProtocol 来调用 Helper 的 screenshot/get_ax_tree 获取视觉上下文
- **Story 3.3**：步骤执行。StepExecutor 通过 HelperProcessManager 的 MCPClientProtocol 调用 Helper 工具
- **Story 3.7**：SDK 集成。可能重构 HelperProcessManager 为使用 SDK 的 Agent + MCPClientManager 方式

### RunCommand 改造注意事项

ArgumentParser 支持 async 命令。将 `RunCommand` 从 `ParsableCommand` 改为遵循 `AsyncParsableCommand`：

```swift
struct RunCommand: AsyncParsableCommand {
    // ... 现有属性不变 ...

    mutating func run() async throws {
        let manager = HelperProcessManager()
        defer { Task { await manager.stop() } }

        try await manager.start()
        // 后续 Story 在此处添加 RunEngine 编排
        throw CleanExit.message("Run command partially implemented (Story 3.1)")
    }
}
```

**注意 `mutating`：** `AsyncParsableCommand.run()` 是 `mutating func`。且 `defer` 中的 `Task` 是异步的，可能在 `run()` 返回后执行。更安全的方式是使用 `withTaskCancellationHandler`。

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.1] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D8] Helper 进程生命周期管理决策
- [Source: _bmad-output/planning-artifacts/architecture.md#Actor 隔离边界] Actor 隔离规则
- [Source: _bmad-output/planning-artifacts/architecture.md#Task 取消传播] 取消传播模式
- [Source: _bmad-output/planning-artifacts/architecture.md#MCP 通信规则] MCP 通信超时和重试规则
- [Source: _bmad-output/project-context.md#Helper 进程生命周期] 生命周期管理概述
- [Source: _bmad-output/project-context.md#模块依赖] AxionCLI 依赖规则
- [Source: _bmad-output/project-context.md#NFR 性能指标] NFR1/NFR2/NFR8 性能要求
- [Source: Sources/AxionCLI/Helper/HelperPathResolver.swift] Helper 路径解析（复用）
- [Source: Sources/AxionCore/Protocols/MCPClientProtocol.swift] MCP 客户端协议（目标接口）
- [Source: Sources/AxionCore/Errors/AxionError.swift] 统一错误类型（.helperNotRunning, .helperConnectionFailed）
- [Source: Sources/AxionCore/Models/Step.swift] Value 枚举（参数类型转换源）
- [Source: Sources/AxionCLI/Commands/RunCommand.swift] RunCommand（需修改为 async）
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/MCP/MCPClientManager.swift] SDK MCP 客户端管理器（参考连接模式）
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/MCP/MCPStdioTransport.swift] SDK stdio 传输层（参考 Process 管理）
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/MCPConfig.swift] McpStdioConfig 定义
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Examples/MCPIntegration/main.swift] SDK MCP 集成示例
- [Source: Tests/AxionHelperTests/MCP/HelperProcessSmokeTests.swift] Helper 进程级测试模式参考

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
