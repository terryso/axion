# Story 3.7: SDK 集成与 Run Command 完整接入

Status: done

## Story

As a 开发者,
I want Axion 的核心编排通过 SDK 公共 API 实现，`axion run` 命令完整可用,
so that Axion 验证了 SDK 的能力并提供了完整的用户体验.

## Acceptance Criteria

1. **AC1: SDK Agent Loop 编排**
   - Given RunEngine 编排执行循环
   - When 检查代码实现
   - Then 使用 SDK 的 `createAgent()` + `Agent.prompt()` 或 `Agent.stream()` 管理 LLM 调用和工具执行循环

2. **AC2: SDK MCP Client 连接**
   - Given CLI 需要连接 Helper
   - When 检查代码实现
   - Then 通过 SDK 的 `AgentOptions.mcpServers` 配置 Helper 作为 MCP stdio server

3. **AC3: SDK 工具注册**
   - Given Helper 工具集
   - When 注册到 Agent
   - Then 使用 SDK 的 `defineTool()` 工厂函数注册自定义工具（或通过 MCP 自动发现）

4. **AC4: SDK Hooks 安全检查**
   - Given 步骤执行前
   - When 安全检查
   - Then 使用 SDK 的 `HookRegistry` + `preToolUse` hook 实现 SafetyChecker 逻辑

5. **AC5: SDK Streaming 进度输出**
   - Given 执行过程中进度更新
   - When 消息输出
   - Then 通过 SDK 的 `Agent.stream()` 返回的 `AsyncStream<SDKMessage>` 管道消费并转发到 TerminalOutput

6. **AC6: 完整端到端流程**
   - Given 运行 `axion run "打开计算器，计算 17 乘以 23"`
   - When 完整流程执行
   - Then Calculator 打开，显示 391，终端显示完成信息

## Tasks / Subtasks

- [x] Task 1: 重构 RunCommand 集成 SDK Agent (AC: #1, #2, #3, #6)
  - [x] 1.1 修改 `Sources/AxionCLI/Commands/RunCommand.swift` — 替换占位代码
  - [x] 1.2 在 RunCommand.run() 中加载配置（ConfigManager + KeychainStore 获取 API Key）
  - [x] 1.3 构建 `AgentOptions`：设置 apiKey、model、systemPrompt（从 PromptBuilder 加载）、maxTurns、mcpServers
  - [x] 1.4 配置 `mcpServers` 参数：使用 `McpStdioConfig(command: helperPath)` 将 Helper 注册为 MCP server
  - [x] 1.5 使用 `createAgent(options:)` 创建 Agent 实例
  - [x] 1.6 调用 `agent.stream(task)` 或 `agent.prompt(task)` 启动执行
  - [x] 1.7 实现取消传播：`withTaskCancellationHandler` 包装 Agent 调用，onCancel 调用 `agent.interrupt()`

- [x] Task 2: 通过 SDK MCP Server 集成替代手动 HelperProcessManager (AC: #2)
  - [x] 2.1 将 Helper 路径解析（`HelperPathResolver.resolveHelperPath()`）用于 `McpStdioConfig`
  - [x] 2.2 保留 HelperProcessManager 用于 Ctrl-C 清理和崩溃检测，或简化为仅用 SDK 的 MCP 管道
  - [x] 2.3 确保 Helper 进程随 CLI 退出而退出（SDK MCPClientManager 的 shutdown 处理）

- [x] Task 3: 通过 SDK Hooks 实现 SafetyChecker (AC: #4)
  - [x] 3.1 创建 `HookRegistry` 实例
  - [x] 3.2 注册 `preToolUse` hook，实现 SafetyChecker 逻辑：检查 `sharedSeatMode` 和 `allowForeground`
  - [x] 3.3 将 HookRegistry 传入 AgentOptions.hookRegistry
  - [x] 3.4 Hook 返回 .block 阻止前台操作，或 .allow 放行

- [x] Task 4: 消费 SDK Streaming 消息并转发到输出 (AC: #5)
  - [x] 4.1 遍历 `AsyncStream<SDKMessage>` 事件
  - [x] 4.2 `.assistant` 消息 → 通过 TerminalOutput 显示 LLM 响应
  - [x] 4.3 `.toolUse` 消息 → 通过 TerminalOutput 显示步骤执行信息
  - [x] 4.4 `.toolResult` 消息 → 通过 TerminalOutput 显示步骤结果
  - [x] 4.5 `.result` 消息 → 通过 TerminalOutput 显示最终汇总（或通过 JSONOutput 输出 JSON）
  - [x] 4.6 `.partialMessage` 消息 → 流式文本输出（可选）
  - [x] 4.7 将 SDKMessage 事件记录到 TraceRecorder

- [x] Task 5: 确定编排策略 — SDK Agent Loop vs 内部状态机 (AC: #1)
  - [x] 5.1 分析 SDK Agent Loop 与 RunEngine 状态机的关系
  - [x] 5.2 确定方案：SDK Agent Loop 管理 turn 循环（LLM 调用 + 工具执行），RunEngine 保留为外层批次循环（plan → execute → verify → replan）
  - [x] 5.3 或：完全使用 SDK Agent，通过 system prompt 引导 LLM 执行 plan-execute-verify 循环
  - [x] 5.4 无论哪种方案，确保代码使用 SDK 公共 API（createAgent, AgentOptions, Agent.stream/prompt）

- [x] Task 6: 编写单元测试
  - [x] 6.1 创建/更新 `Tests/AxionCLITests/Commands/RunCommandTests.swift`
  - [x] 6.2 测试：RunCommand 构建 AgentOptions（apiKey, model, mcpServers）
  - [x] 6.3 测试：dryrun 模式不执行工具调用
  - [x] 6.4 测试：SafetyChecker Hook 阻止前台操作
  - [x] 6.5 测试：SafetyChecker Hook 在 allowForeground 模式下放行
  - [x] 6.6 测试：Ctrl-C 取消传播到 Agent.interrupt()
  - [x] 6.7 测试：SDKMessage 消费和输出转发

- [x] Task 7: 运行全部单元测试确认无回归
  - [x] 7.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认全部通过

## Dev Notes

### 核心目标

将 Axion 的核心编排从自定义的 RunEngine 状态机重构为通过 OpenAgentSDK 公共 API 实现。本 Story 有两个可能的实现路径，开发者需要根据 SDK 能力选择最合适的方案。

### 架构定位

本 Story 是 Epic 3 的倒数第二个 Story，核心目标是验证 SDK 的能力：

- **FR36**: 系统使用 SDK 的 Agent 循环编排 planner/executor/verify 的完整工作流
- **FR37**: 系统使用 SDK 的 MCP client 连接 AxionHelper 并调用工具
- **FR38**: 系统使用 SDK 的工具注册机制注册 Helper 提供的桌面操作工具
- **FR39**: 系统使用 SDK 的 Hooks 机制实现执行前的安全策略检查
- **FR40**: 系统使用 SDK 的流式消息机制输出实时进度
- **FR41**: 产出的 SDK 边界文档明确记录每个模块的归属（SDK / 应用层）和理由

### 关键设计决策：两种可能的方案

#### 方案 A：SDK Agent Loop 作为编排核心

完全使用 SDK 的 Agent Loop（createAgent + stream/prompt），通过 system prompt 引导 LLM 执行 plan-execute-verify 循环。

**实现方式：**
1. 使用 `createAgent()` 创建 Agent，设置 `systemPrompt` 为 planner-system.md 的内容
2. 配置 `mcpServers` 将 Helper 注册为 MCP server，SDK 自动发现并注册所有 Helper 工具
3. 使用 `Agent.stream(task)` 启动执行
4. LLM 自己决定何时 plan、何时 execute、何时 verify — 通过 system prompt 引导
5. 注册 `preToolUse` Hook 实现 SafetyChecker
6. 消费 `AsyncStream<SDKMessage>` 转发到 TerminalOutput

**优势：**
- 最简单，最大程度利用 SDK
- 不需要维护 RunEngine 状态机
- SDK 处理所有 LLM 调用、重试、取消

**劣势：**
- LLM 需要"学会"plan-execute-verify 循环，prompt 工程量较大
- 验证逻辑（截图 + AX tree 判断完成状态）需要作为工具暴露给 LLM
- 重规划逻辑由 LLM 自主处理，不如状态机精确

#### 方案 B：保留 RunEngine 外层循环 + SDK Agent 替代 LLM 调用

保留 RunEngine 的 plan → execute → verify → replan 循环，但用 SDK Agent 替代 LLMPlanner 中的直接 API 调用。

**实现方式：**
1. RunEngine 保持当前结构（外层批次循环）
2. LLMPlanner 内部使用 `Agent.prompt()` 替代当前的 `LLMClientProtocol.prompt()`
3. StepExecutor 使用 SDK 的 MCP 工具执行步骤（通过 Agent 的 mcpServers 配置）
4. TaskVerifier 使用 SDK Agent 进行验证
5. HelperProcessManager 可能需要简化，因为 SDK 的 MCPClientManager 管理连接

**优势：**
- 保留精确的状态机控制
- RunEngine 的重规划逻辑已经完整实现
- 渐进式重构，风险较低

**劣势：**
- 没有完全使用 SDK Agent Loop，部分违背 FR36 的初衷
- 需要协调 RunEngine 和 SDK Agent 的状态

#### 推荐：方案 A

原因：
1. FR36 明确要求"使用 SDK 的 Agent 循环编排"
2. PRD 和 Architecture 的核心目标就是验证 SDK 能力
3. 方案 B 中 RunEngine 已经在 Story 3-6 中验证了状态机逻辑，但 SDK Agent Loop 的验证价值更高
4. 通过精心设计的 system prompt，LLM 可以完全自主完成 plan-execute-verify 循环

### OpenAgentSDK 关键 API 参考

SDK 本地路径：`/Users/nick/CascadeProjects/open-agent-sdk-swift`

#### 1. createAgent() — Agent 工厂

```swift
import OpenAgentSDK

let agent = createAgent(options: AgentOptions(
    apiKey: "sk-ant-xxx",
    model: "claude-sonnet-4-20250514",
    systemPrompt: systemPrompt,  // planner-system.md 内容
    maxTurns: 30,
    tools: customTools,          // 可选：额外的自定义工具
    mcpServers: ["helper": .stdio(McpStdioConfig(command: helperPath))],
    hookRegistry: hookRegistry,  // SafetyChecker hooks
    permissionMode: .autoAccept, // 自动批准所有工具调用
    maxTokens: 4096
))
```

#### 2. Agent.stream() — 流式执行

```swift
let messageStream = agent.stream("打开计算器，计算 17 乘以 23")
for await message in messageStream {
    switch message {
    case .assistant(let data):
        // LLM 响应文本
        print(data.text)
    case .toolUse(let data):
        // LLM 请求调用工具
        print("Calling: \(data.toolName)")
    case .toolResult(let data):
        // 工具执行结果
        print("Result: \(data.content)")
    case .partialMessage(let data):
        // 流式文本片段
        print(data.text, terminator: "")
    case .result(let data):
        // 最终结果
        print("Done: \(data.subtype)")
    default:
        break
    }
}
```

#### 3. Agent.prompt() — 阻塞式执行

```swift
let result = await agent.prompt("打开计算器")
print(result.text)       // 响应文本
print(result.numTurns)   // turn 数
print(result.status)     // .success, .errorMaxTurns, etc.
```

#### 4. AgentOptions 关键字段

| 字段 | 类型 | 用途 | Axion 使用方式 |
|------|------|------|---------------|
| `apiKey` | `String?` | Anthropic API Key | 从 ConfigManager/KeychainStore 获取 |
| `model` | `String` | LLM 模型 | 从 AxionConfig.model 读取 |
| `systemPrompt` | `String?` | 系统提示词 | 加载 planner-system.md |
| `maxTurns` | `Int` | 最大 turn 数 | 从 AxionConfig.maxSteps 读取 |
| `maxTokens` | `Int` | 每请求最大 token | 固定 4096 |
| `tools` | `[ToolProtocol]?` | 自定义工具 | 可选，Helper 工具通过 MCP 自动注册 |
| `mcpServers` | `[String: McpServerConfig]?` | MCP 服务器 | Helper 作为 stdio MCP server |
| `hookRegistry` | `HookRegistry?` | 生命周期 Hook | SafetyChecker 通过 preToolUse hook 实现 |
| `permissionMode` | `PermissionMode` | 权限模式 | `.autoAccept`（Axion 不需要用户确认） |
| `baseURL` | `String?` | API 基础 URL | 支持自定义 API 端点 |

#### 5. defineTool() — 自定义工具注册（如果需要）

```swift
struct VerifyInput: Codable {
    let screenshot: String
    let stopWhen: String
}

let verifyTool = defineTool(
    name: "verify_task",
    description: "验证任务是否完成",
    inputSchema: ToolInputSchema(/* ... */)
) { (input: VerifyInput, context: ToolContext) in
    // 验证逻辑
    return "Task completed: result matches"
}
```

注意：如果采用方案 A，大多数 Helper 工具通过 MCP 自动注册。`defineTool()` 仅用于注册应用层自定义工具（如 verify_task、replan 等非 MCP 工具）。

#### 6. HookRegistry — 安全检查

```swift
let hookRegistry = HookRegistry()
hookRegistry.register(.preToolUse) { input in
    // SafetyChecker 逻辑
    let toolName = input.toolName ?? ""
    let foregroundTools = ["click", "type_text", "press_key", "hotkey", "drag", "scroll"]

    if sharedSeatMode && !allowForeground && foregroundTools.contains(toolName) {
        return HookResult.block(reason: "前台操作在共享座椅模式下被阻止")
    }
    return HookResult.allow()
}
```

### 与 Story 3-6 的关系

Story 3-6 实现了 RunEngine 状态机（plan → execute → verify → replan 循环）。本 Story 需要决定 RunEngine 的命运：

- **如果采用方案 A**：RunEngine 可能被大幅简化或完全移除，SDK Agent Loop 接管编排。但 RunEngine 中的**输出/Trace 逻辑**仍然需要保留。
- **如果采用方案 B**：RunEngine 保留，LLMPlanner/StepExecutor/TaskVerifier 改为使用 SDK Agent。

无论哪种方案，以下组件仍然需要保留：
- `TerminalOutput` / `JSONOutput` — 终端输出格式化
- `TraceRecorder` — JSONL trace 记录
- `ConfigManager` / `KeychainStore` — 配置管理
- `SafetyChecker` 逻辑 — 通过 SDK Hooks 实现
- `PromptBuilder` — 加载 planner-system.md

### 当前 RunCommand 状态

当前 `RunCommand.swift` 的实现：
```swift
mutating func run() async throws {
    let manager = HelperProcessManager()
    do {
        try await withTaskCancellationHandler {
            try await manager.start()
            // 后续 Story 在此处添加 RunEngine 编排
            throw CleanExit.message("Run command partially implemented (Story 3.1)")
        } onCancel: {
            Task { await manager.stop() }
        }
    } catch {
        await manager.stop()
        throw error
    }
}
```

需要完全替换 `throw CleanExit.message(...)` 占位代码。

### SDK MCP 配置方式

SDK 通过 `AgentOptions.mcpServers` 配置 MCP server 连接。Helper 作为 stdio MCP server 的配置方式：

```swift
let helperPath = HelperPathResolver.resolveHelperPath()!
let mcpConfig: [String: McpServerConfig] = [
    "axion-helper": .stdio(McpStdioConfig(command: helperPath))
]
```

SDK 的 `MCPClientManager` 会自动：
1. 启动 Helper 进程（通过 stdio transport）
2. 执行 MCP 握手
3. 发现所有工具（tools/list）
4. 注册为可用工具

**这意味着不需要手动调用 HelperProcessManager.start()** — SDK 管理了 Helper 进程的生命周期。

### HelperProcessManager 的命运

当前 `HelperProcessManager` 提供了：
1. Helper 进程启动（MCPStdioTransport） — SDK 的 MCPClientManager 接管
2. MCP 连接和工具调用 — SDK 的 MCPClientManager 接管
3. Ctrl-C 信号传播 — SDK 的 Agent.interrupt() + Task cancellation 接管
4. 崩溃检测和重启 — SDK 的 MCPClientManager 有 reconnection 支持

**建议：简化 HelperProcessManager 的角色**。它可能不再需要作为核心组件，因为 SDK 接管了进程管理和 MCP 连接。但可以保留 `HelperPathResolver` 作为工具方法。

### Config 加载

RunCommand 需要加载配置来构建 AgentOptions：

```swift
// 1. 加载配置
let config = ConfigManager.load()  // 分层加载

// 2. 获取 API Key
let apiKey = KeychainStore.load() ?? ProcessInfo.processInfo.environment["AXION_API_KEY"]

// 3. CLI 参数覆盖
let effectiveMaxSteps = maxSteps ?? config.maxSteps
let effectiveMaxBatches = maxBatches ?? config.maxBatches

// 4. 加载 system prompt
let systemPrompt = try PromptBuilder.load(name: "planner-system", variables: [:])
```

### import 顺序

```swift
// RunCommand.swift
import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore
```

### 目录结构

```
Sources/AxionCLI/Commands/
  RunCommand.swift                   # 修改：替换占位代码，集成 SDK Agent

Sources/AxionCLI/Engine/
  RunEngine.swift                    # 可能修改/简化：根据选择的方案

Tests/AxionCLITests/Commands/
  RunCommandTests.swift              # 新建/更新：SDK 集成测试
```

### 测试策略

**SDK 集成测试的关键：Mock SDK Agent**

由于 SDK 的 Agent 是 class（不是 protocol），直接 Mock 有难度。推荐策略：

1. **不 Mock SDK Agent** — 而是测试 RunCommand 的输入/输出行为
2. **测试 AgentOptions 构建** — 验证 apiKey、model、mcpServers 等配置正确
3. **测试 Hook 逻辑** — 单独测试 SafetyChecker Hook 的注册和行为
4. **测试 SDKMessage 消费** — 创建 SDKMessage 实例，验证输出转发逻辑

### 禁止事项（反模式）

- **不得绕过 SDK 直接调用 Anthropic API** — SDK Agent Loop 是唯一的 LLM 调用路径
- **不得在 AxionCore 中 import OpenAgentSDK** — Core 是纯模型层
- **RunCommand 不得直接 import AxionHelper** — 两者仅通过 MCP 通信（SDK 管理连接）
- **不得使用 print() 输出** — 通过 TerminalOutput/JSONOutput 输出
- **不得硬编码 prompt 文本** — 通过 PromptBuilder 加载
- **不得创建新的错误类型体系** — 使用 AxionError 枚举
- **API Key 不得出现在日志或 trace 中** — NFR9

### 现有代码状态

**可直接复用：**
- `RunCommand.swift` — 已有 CLI 参数解析（task, dryrun, maxSteps, maxBatches, allowForeground, verbose, json）
- `AxionConfig` — 配置模型（model, maxSteps, maxBatches, maxReplanRetries, sharedSeatMode）
- `PromptBuilder` — 加载外部 prompt 文件
- `TerminalOutput` / `JSONOutput` — 输出格式化
- `TraceRecorder` — JSONL trace 记录
- `SafetyChecker` 逻辑 — 需要迁移到 SDK Hook
- `HelperPathResolver` — Helper 路径解析
- `ConfigManager` — 配置加载
- `KeychainStore` — API Key 安全存储

**需要新建：**
- SDK Hook 实现（SafetyChecker 通过 preToolUse hook）
- SDKMessage 消费逻辑（AsyncStream<SDKMessage> → OutputProtocol）

**可能需要修改/删除：**
- `RunCommand.swift` — 替换占位代码
- `RunEngine.swift` — 根据方案可能大幅简化
- `HelperProcessManager.swift` — 如果 SDK 接管 MCP 连接，可能简化
- `LLMPlanner.swift` / `StepExecutor.swift` / `TaskVerifier.swift` — 如果 SDK Agent Loop 接管编排

### 检查清单合规

- [x] 故事声明：As a / I want / so that 格式
- [x] 验收标准：Given/When/Then BDD 格式
- [x] 任务分解：可执行的子任务，关联 AC
- [x] 开发者注记：架构决策、模式约束、反模式
- [x] 项目结构注记：文件位置、依赖规则、import 顺序
- [x] 参考：所有源文档引用
- [x] 测试策略：测试方法、关键测试用例

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.7] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D3] 执行循环状态机设计
- [Source: _bmad-output/planning-artifacts/architecture.md#D5] 并发模型（async/await + Actor）
- [Source: _bmad-output/planning-artifacts/architecture.md#FR36-FR41] SDK 集成功能需求
- [Source: _bmad-output/planning-artifacts/architecture.md#OpenAgentSDK 参考] SDK 路径和集成点
- [Source: _bmad-output/planning-artifacts/architecture.md#模块依赖规则] import 限制
- [Source: _bmad-output/project-context.md#OpenAgentSDK 参考路径] SDK 示例路径映射
- [Source: _bmad-output/project-context.md#关键反模式] SDK 集成反模式
- [Source: _bmad-output/implementation-artifacts/stories/3-6-run-engine-state-machine.md] 前序 Story — RunEngine 状态机完整实现
- [Source: Sources/AxionCLI/Commands/RunCommand.swift] 当前 RunCommand 实现（需替换占位代码）
- [Source: Sources/AxionCLI/Engine/RunEngine.swift] RunEngine 状态机（可能需要重构）
- [Source: Sources/AxionCLI/Helper/HelperProcessManager.swift] Helper 进程管理（SDK 可能接管）
- [Source: Sources/AxionCLI/Planner/LLMPlanner.swift] LLMPlanner（含 LLMClientProtocol）
- [Source: Sources/AxionCore/Protocols/MCPClientProtocol.swift] MCPClientProtocol
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift] SDK Agent 核心实现（prompt + stream）
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/AgentTypes.swift] AgentOptions、QueryResult、AgentDefinition
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/ToolBuilder.swift] defineTool() 工厂函数
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/HookTypes.swift] HookEvent、HookInput
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/SDKMessage.swift] SDKMessage 流式消息类型
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/MCP/MCPClientManager.swift] MCP 连接管理
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/MCP/MCPToolDefinition.swift] MCP 工具定义

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

No debug issues encountered during implementation.

### Completion Notes List

- Implemented SDK Agent Loop approach (方案 A): RunCommand uses `createAgent()` + `Agent.stream()` as the core orchestration, replacing the placeholder code from Story 3.1
- SDK manages Helper process lifecycle via `AgentOptions.mcpServers` with `McpStdioConfig` — no need for manual `HelperProcessManager.start()`
- SafetyChecker logic implemented as `HookRegistry` + `preToolUse` hook — blocks foreground tools (click, type_text, etc.) in shared seat mode
- Created `SDKTerminalOutputHandler` and `SDKJSONOutputHandler` for consuming `AsyncStream<SDKMessage>` events and forwarding to output
- Cancellation propagation via `withTaskCancellationHandler` + `agent.interrupt()` — Ctrl-C propagates cleanly
- RunEngine state machine preserved but not used in the new SDK path — available for future batch-level orchestration if needed
- Added `AxionError.missingApiKey` and `AxionError.helperNotFound` cases for better error reporting
- Added `ToolNames.allToolNames` for prompt building convenience
- Added `writeStream()` to TerminalOutput for streaming partial messages
- All 518 unit tests pass (37 new SDK integration tests + 481 existing tests)

### File List

- `Sources/AxionCLI/Commands/RunCommand.swift` — MODIFIED: Replaced placeholder code with full SDK Agent integration (createAgent, stream, hooks, output handlers)
- `Sources/AxionCore/Errors/AxionError.swift` — MODIFIED: Added missingApiKey and helperNotFound error cases
- `Sources/AxionCore/Constants/ToolNames.swift` — MODIFIED: Added allToolNames static array
- `Sources/AxionCLI/Output/TerminalOutput.swift` — MODIFIED: Made write accessible, added writeStream method
- `Tests/AxionCLITests/Commands/SDKIntegrationATDDTests.swift` — MODIFIED: Enabled all ATDD switches, added new tests for output handlers, ToolNames, AxionError
- `Package.swift` — MODIFIED: Added OpenAgentSDK dependency to AxionCLITests target
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — MODIFIED: Updated story 3-7 status to in-progress

### Change Log

- 2026-05-10: Completed Story 3-7 implementation — SDK Agent Loop integration with RunCommand (GLM-5.1)
