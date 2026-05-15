# Story 11.2: 插件化工具注册与自定义 Agent 扩展

Status: done

## Story

As a 第三方开发者,
I want 为我的 Agent 注册自定义工具并扩展 Agent 能力,
So that 我的 Agent 可以执行特定领域的操作，同时复用 Axion 的桌面自动化能力.

## Acceptance Criteria

1. **AC1: `defineTool` 工厂函数支持自定义工具注册**
   Given SDK 的工具注册 API（`defineTool` 工厂函数）
   When 开发者创建自定义工具
   Then 通过 `defineTool` + Codable Input 类型定义工具签名和 `inputSchema`，实现 `execute` 闭包返回 `String` 或 `ToolExecuteResult`，无需理解 MCP 协议细节

2. **AC2: 多工具注册后 LLM 可发现和使用**
   Given 开发者注册了多个自定义工具到 `AgentOptions.tools` 数组
   When Agent 运行（`agent.stream()` 或 `agent.prompt()`）
   Then LLM 在规划时自动发现所有已注册工具，工具调用走 SDK 标准 `ToolProtocol.call()` 通道，`assembleToolPool` 负责去重（自定义工具可覆盖同名 base 工具）

3. **AC3: 通过 `axion mcp` 复用 Axion 桌面操作能力**
   Given Axion 的 MCP Server 模式（Epic 6 已实现 `axion mcp` 子命令）
   When 第三方开发者想使用 Axion 的桌面操作能力
   Then 通过 `AgentOptions.mcpServers` 配置 `axion mcp` 作为 MCP stdio server，SDK 自动发现 Axion 的 20+ 桌面操作工具（`launch_app`、`click`、`type_text` 等），在自己的 Agent 中直接调用

4. **AC4: 自定义 Helper App 架构参考**
   Given 第三方 Agent 需要特定的 macOS 操作（如模拟器控制）
   When 开发者实现自定义 Helper
   Then 参考 AxionHelper 架构（MCP Server + AX Service 分离），使用 `mcp-swift-sdk` 的 `@Tool` 宏和 `@Parameter` 创建自己的 Helper App，通过 MCP stdio 与 Agent 通信

5. **AC5: Hooks 机制实现安全策略**
   Given SDK 的 Hooks 机制（`HookRegistry` + `HookDefinition`）
   When 开发者需要添加安全策略
   Then 通过 `HookRegistry.register(.preToolUse)` 注册 hook，使用 `matcher` 正则过滤特定工具，`handler` 闭包返回 `HookOutput` 拦截或放行工具调用，实现自定义的权限检查和审计逻辑

6. **AC6: 插件化工具注册示例文档**
   Given Story 11.1 脚手架生成的项目模板
   When 开发者查看 `Tools/` 目录和 README
   Then 包含多个自定义工具注册示例：Codable Input 工具、Raw Dictionary 工具、No-Input 工具、Hooks 注册示例、MCP Server 集成示例

## Tasks / Subtasks

- [x] Task 1: 扩展脚手架模板的工具示例 (AC: #1, #6)
  - [x] 1.1 在 `ToolTemplates.swift` 中新增 `CalculatorTool`（Codable Input + ToolExecuteResult 返回）和 `SystemInfoTool`（No-Input 便捷模式）
  - [x] 1.2 更新 `createExampleTools()` 返回包含所有示例工具的数组
  - [x] 1.3 在模板 `main.swift` 中展示多种工具注册模式（Codable、No-Input、Raw Dictionary）

- [x] Task 2: 编写 MCP Server 集成示例 (AC: #3)
  - [x] 2.1 在 `BasicMainTemplate.swift` 的 `mcp-integration` 模板中补充 `axion mcp` 作为 MCP server 的配置示例
  - [x] 2.2 展示 `McpServerConfig.stdio(McpStdioConfig(command:))` 配置方式
  - [x] 2.3 说明工具命名空间规则（`mcp__axion-helper__click`）

- [x] Task 3: 编写 Hooks 安全策略示例 (AC: #5)
  - [x] 3.1 在脚手架模板中添加 `Hooks/` 目录和 `SafetyHooks.swift` 示例文件
  - [x] 3.2 展示 `HookRegistry.register(.preToolUse)` + `matcher` + `handler` 模式
  - [x] 3.3 展示 `HookOutput` 返回 `approve` / `block` 的用法
  - [x] 3.4 展示 `HookRegistry.registerFromConfig()` 批量注册方式

- [x] Task 4: 编写自定义 Helper App 架构指南 (AC: #4)
  - [x] 4.1 在 README 模板中添加「自定义 Helper App」章节
  - [x] 4.2 说明 AxionHelper 架构模式：MCP Server（`@Tool` 宏）+ AX Service 分离
  - [x] 4.3 说明 MCP stdio 通信流程：Agent 启动 Helper → stdio JSON-RPC → 工具调用
  - [x] 4.4 提供 Helper App 的最小 `Package.swift` 和 `main.swift` 骨架代码

- [x] Task 5: 更新脚手架模板 README 文档 (AC: #6)
  - [x] 5.1 添加「工具开发指南」章节（`defineTool` 三种模式对比表）
  - [x] 5.2 添加「Hooks 安全策略」章节（pre/post hook 注册示例）
  - [x] 5.3 添加「MCP Server 集成」章节（复用 Axion 或自定义 Helper）
  - [x] 5.4 添加「工具池组装」章节（`assembleToolPool` 去重和过滤机制说明）
  - [x] 5.5 添加「权限模式」章节（`PermissionMode` 和 `canUseTool` 回调）

- [x] Task 6: 单元测试 (AC: #1-#6)
  - [x] 6.1 测试脚手架生成包含新的工具示例文件
  - [x] 6.2 测试生成项目能 `swift build` 通过（验证新增模板代码编译正确）
  - [x] 6.3 测试 README 模板包含新增章节内容
  - [x] 6.4 测试 Hooks 示例模板格式正确

## Dev Notes

### Epic 11 与前序 Story 关系

Epic 11「第三方 SDK 生态」的核心目标是让第三方开发者能基于 OpenAgentSDK 构建自己的 macOS 桌面 Agent 应用。

- **Story 11.1（已完成）**：脚手架 CLI + 项目模板 → 开发者能快速创建项目骨架
- **Story 11.2（本 Story）**：插件化工具注册 + Agent 扩展 → 开发者能为 Agent 添加自定义能力
- **Story 11.3**：开发者文档与示例库 → 完整的文档和示例

Story 11.2 建立在 11.1 的脚手架模板之上，扩展模板内容以覆盖更多 SDK 能力。

### SDK 工具注册体系（核心 API 清单）

SDK 已提供完整的工具注册基础设施，本 Story 无需修改 SDK，只需扩展脚手架模板以充分展示这些 API。

**`ToolProtocol`（SDK 核心 protocol）：**
```swift
// Sources/OpenAgentSDK/Types/ToolTypes.swift:127
public protocol ToolProtocol: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: ToolInputSchema { get }  // typealias [String: Any]
    var isReadOnly: Bool { get }
    var annotations: ToolAnnotations? { get } // 可选
    func call(input: Any, context: ToolContext) async -> ToolResult
}
```

**`defineTool` 工厂函数（4 种重载）：**

| 重载 | Input 类型 | 返回类型 | 用途 |
|------|-----------|---------|------|
| `defineTool<Input: Codable>(...execute: (Input, ToolContext) -> String)` | Codable | String | 最常用：类型安全输入 |
| `defineTool<Input: Codable>(...execute: (Input, ToolContext) -> ToolExecuteResult)` | Codable | ToolExecuteResult | 需要显式标记错误 |
| `defineTool(...execute: (ToolContext) -> String)` | 无 | String | 简单工具，无需输入 |
| `defineTool(...execute: ([String: Any], ToolContext) -> ToolExecuteResult)` | Raw Dict | ToolExecuteResult | 动态类型输入 |

来源: `Sources/OpenAgentSDK/Tools/ToolBuilder.swift`

**`assembleToolPool` 工具池组装：**
```swift
// Sources/OpenAgentSDK/Tools/ToolRegistry.swift:150
public func assembleToolPool(
    baseTools: [ToolProtocol],    // SDK 内置工具
    customTools: [ToolProtocol]?, // AgentOptions.tools
    mcpTools: [ToolProtocol]?,    // MCP server 发现的工具
    allowed: [String]?,           // 白名单
    disallowed: [String]?         // 黑名单
) -> [ToolProtocol]
```
- 合并顺序：base → custom → MCP，后者覆盖前者（同名去重）
- 开发者通过 `AgentOptions.tools` 注册自定义工具，SDK 自动完成组装

**`ToolContext`（工具执行上下文）：**
```swift
// Sources/OpenAgentSDK/Types/ToolTypes.swift:269
public struct ToolContext: Sendable {
    public let cwd: String
    public let toolUseId: String
    public let memoryStore: MemoryStoreProtocol?  // 跨任务记忆
    public let hookRegistry: HookRegistry?        // Hook 注册表
    public let skillRegistry: SkillRegistry?      // 技能注册表
    // ... 更多可选注入
}
```

### SDK Hooks 体系

SDK 已提供完整的 Hook 系统，支持 22 个生命周期事件拦截。

**核心 API：**
```swift
// 注册 hook
await registry.register(.preToolUse, definition: HookDefinition(
    matcher: "click|type_text",  // 正则匹配工具名
    handler: { input in
        // 安全检查逻辑
        return HookOutput(block: true, message: "操作被拦截")
        // 或 return nil 表示放行
    }
))

// 批量注册
await registry.registerFromConfig([
    "preToolUse": [def1, def2],
    "postToolUse": [def3]
])
```

**HookEvent 枚举（22 个事件）：**
- 工具相关：`preToolUse`, `postToolUse`, `postToolUseFailure`
- 会话相关：`sessionStart`, `sessionEnd`, `stop`
- Agent 相关：`subagentStart`, `subagentStop`
- 权限相关：`permissionRequest`, `permissionDenied`
- 任务相关：`taskCreated`, `taskCompleted`
- 其他：`configChange`, `cwdChanged`, `fileChanged`, `notification`, `preCompact`, `postCompact` 等

来源: `Sources/OpenAgentSDK/Types/HookTypes.swift`

### MCP Server 集成模式

Axion 通过 `axion mcp` 子命令暴露为 MCP stdio server，第三方 Agent 可直接复用。

**Axion 的 MCP Server 实现：**
- 入口：`Sources/AxionCLI/MCP/MCPServerRunner.swift`
- 通过 `AgentMCPServer(name:"axion", tools:)` 暴露工具
- 工具包括 `run_task`（执行桌面自动化任务）和 `query_task_status`

**第三方 Agent 集成 Axion 的方式：**
```swift
let mcpServers: [String: McpServerConfig] = [
    "axion-helper": .stdio(McpStdioConfig(command: "axion mcp"))
]

let options = AgentOptions(
    apiKey: apiKey,
    tools: [myCustomTool],     // 自定义工具
    mcpServers: mcpServers     // Axion 桌面操作工具
)
```

SDK 的 `MCPToolDefinition` 自动将 MCP server 工具包装为 `ToolProtocol`，命名空间为 `mcp__{serverName}__{toolName}`。

来源: `Sources/OpenAgentSDK/Tools/MCP/MCPToolDefinition.swift`

### AxionHelper 参考架构（自定义 Helper 模板）

AxionHelper 的架构是第三方创建自定义 Helper 的参考蓝本：

```
AxionHelper/
├── main.swift                    # MCPServer.run() 入口
├── MCP/
│   └── ToolRegistrar.swift       # @Tool struct 集中注册
└── Services/
    ├── AXService.swift           # AX 操作服务
    ├── ScreenshotService.swift   # 截图服务
    └── WindowService.swift       # 窗口管理服务
```

**关键模式：**
1. 使用 `mcp-swift-sdk` 的 `@Tool` 宏定义工具（不是 SDK 的 `defineTool`）
2. `ToolRegistrar.registerAll(to:)` 集中注册所有工具
3. Helper 仅通过 stdio JSON-RPC 通信，不监听网络端口
4. 每个工具是独立的 `@Tool struct`，包含 `static let name`、`@Parameter` 属性和 `perform()` 方法

来源: `Sources/AxionHelper/MCP/ToolRegistrar.swift`

### 脚手架模板修改位置（OpenAgentSDK 仓库）

所有模板文件位于 OpenAgentSDK 仓库的 `Sources/ScaffoldCLI/Templates/` 目录：

| 文件 | 修改内容 |
|------|---------|
| `ToolTemplates.swift` | 新增 CalculatorTool、SystemInfoTool 模板 |
| `BasicMainTemplate.swift` | 更新工具注册代码，展示多种模式 |
| `ReadmeTemplate.swift` | 新增工具开发、Hooks、MCP 集成章节 |
| `PromptTemplates.swift` | 可能需要更新 system prompt 中的工具描述 |

新增文件：
| 文件 | 内容 |
|------|------|
| `HookTemplates.swift` | Hooks 安全策略示例模板 |
| `HelperAppTemplates.swift`（可选） | 自定义 Helper App 骨架模板 |

### 与 Axion 仓库的关系

本 Story 主要修改 OpenAgentSDK 仓库的脚手架模板代码。Axion 仓库仅更新 sprint-status.yaml。

Axion 仓库中开发者应参考的关键文件：

| 文件 | 参考价值 |
|------|---------|
| `Sources/AxionCLI/Commands/RunCommand.swift` | 完整的 Agent 创建和配置示例（MCP server + Hooks + tools） |
| `Sources/AxionHelper/MCP/ToolRegistrar.swift` | 20+ 个 `@Tool` struct 注册参考 |
| `Sources/AxionCLI/MCP/MCPServerRunner.swift` | Agent-as-MCP-Server 模式参考 |
| `docs/sdk-boundary.md` | SDK vs 应用层边界说明 |

### Story 11.1 的关键经验

Story 11.1 实现中遇到的教训（来自 Dev Agent Record）：

1. **`AnyTool` 类型不存在** → 必须使用 `ToolProtocol`（CRITICAL 修复）
2. **`defineTool` 中的 `inputSchema` 必须与 Codable Input 类型一致** → schema 声明的字段名和类型必须匹配 Swift struct
3. **`createExampleTools()` 返回 `[ToolProtocol]`** → 所有工具都走统一协议
4. **模板字符串中的 Swift 插值需要双重转义** → `\\()` 在模板源码中 → `\()` 在生成输出中
5. **模板内容嵌入为 Swift String 常量** → 不依赖外部模板引擎

### NFR 约束

- **编译时间**：生成的项目 `swift build` 应在 60 秒内完成
- **模板大小**：所有模板文件总大小 < 30KB（新增 Hooks 和工具示例后略有增加）
- **零外部依赖**：模板项目仅依赖 OpenAgentSDK，不引入其他第三方库

### Project Structure Notes

- 修改发生在 OpenAgentSDK 仓库（`/Users/nick/CascadeProjects/open-agent-sdk-swift/`）
- 脚手架工具路径：`Sources/ScaffoldCLI/`
- 模板文件路径：`Sources/ScaffoldCLI/Templates/`
- 测试路径：`Tests/ScaffoldCLITests/`
- Axion 仓库仅更新 `_bmad-output/implementation-artifacts/sprint-status.yaml`

### 测试策略

- **单元测试**：验证脚手架生成的新文件存在且内容正确
- **编译验证**：生成项目能 `swift build` 通过（在 CI 环境可能需要跳过）
- **已有测试回归**：确保 11.1 的 18 个测试仍然通过

### References

- SDK ToolProtocol: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/ToolTypes.swift]
- SDK defineTool 工厂函数: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/ToolBuilder.swift]
- SDK ToolRegistry (assembleToolPool): [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/ToolRegistry.swift]
- SDK HookRegistry: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Hooks/HookRegistry.swift]
- SDK HookTypes (HookEvent, HookDefinition, HookInput, HookOutput): [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/HookTypes.swift]
- SDK MCPToolDefinition: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/MCP/MCPToolDefinition.swift]
- SDK ToolContext: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/ToolTypes.swift:269]
- SDK AgentOptions: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/AgentTypes.swift]
- SDK API 入口: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/OpenAgentSDK.swift]
- Axion ToolRegistrar: [Source: Sources/AxionHelper/MCP/ToolRegistrar.swift]
- Axion RunCommand (Agent 创建): [Source: Sources/AxionCLI/Commands/RunCommand.swift]
- Axion MCPServerRunner: [Source: Sources/AxionCLI/MCP/MCPServerRunner.swift]
- SDK 边界文档: [Source: docs/sdk-boundary.md]
- Story 11.1 (前序 Story): [Source: _bmad-output/implementation-artifacts/11-1-agent-project-template-scaffold-cli.md]
- Project Context: [Source: _bmad-output/project-context.md]
- Epics (Epic 11): [Source: _bmad-output/planning-artifacts/epics.md]
- Architecture: [Source: _bmad-output/planning-artifacts/architecture.md]

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m] (via Claude Code)

### Debug Log References

- 嵌套多行字符串字面量冲突：模板内容中 `"""` 与外层模板的 `"""` 冲突 → 改用字符串拼接（`\n`）
- 已有测试断言检查 "Adding Custom Tools" 章节名 → 更新为匹配新的 "Tool Development Guide" 名称

### Completion Notes List

- ✅ Task 1: 扩展 ToolTemplates.swift 新增 CalculatorTool（Codable+ToolExecuteResult）、SystemInfoTool（No-Input）、ConfigTool（Raw Dictionary），更新 createExampleTools() 返回 5 个工具
- ✅ Task 2: 更新 mcp-integration 模板，展示完整的 `axion mcp` MCP server 配置、McpStdioConfig 用法、命名空间规则
- ✅ Task 3: 新建 HookTemplates.swift，展示 register(.preToolUse) + matcher + handler 模式、HookOutput approve/block、registerFromConfig 批量注册
- ✅ Task 4: README 新增「Custom Helper App Architecture」章节，含最小 Package.swift 和 main.swift 骨架代码
- ✅ Task 5: README 新增工具开发指南（4 种模式对比表）、Hooks 安全策略、MCP 集成、工具池组装、权限模式共 5 个新章节
- ✅ Task 6: 新增 11 个单元测试（CalculatorTool、SystemInfoTool、ConfigTool、Hooks 文件/目录、MCP 集成、README 各章节），全部 29 个测试通过

### File List

**OpenAgentSDK 仓库（修改）：**
- Sources/ScaffoldCLI/Templates/ToolTemplates.swift — 新增 CalculatorTool、SystemInfoTool、ConfigTool 模板
- Sources/ScaffoldCLI/Templates/BasicMainTemplate.swift — 更新 basic 和 mcp-integration main.swift 模板
- Sources/ScaffoldCLI/Templates/ReadmeTemplate.swift — 新增 5 个章节（工具开发、Hooks、MCP、工具池、权限）
- Sources/ScaffoldCLI/Templates/PromptTemplates.swift — 更新 system prompt 工具列表
- Sources/ScaffoldCLI/Templates/HookTemplates.swift — 新增 Hooks 安全策略示例模板
- Sources/ScaffoldCLI/TemplateGenerator.swift — 新增 generateSafetyHooks()、Hooks 目录
- Tests/ScaffoldCLITests/ScaffoldCLITests.swift — 新增 11 个测试，更新已有测试

**Axion 仓库（修改）：**
- _bmad-output/implementation-artifacts/11-2-plugin-tool-registration-agent-extension.md — Story 文件更新
- _bmad-output/implementation-artifacts/sprint-status.yaml — 状态更新

## Change Log

- 2026-05-15: Story 11.2 实现完成 — 扩展脚手架模板覆盖 defineTool 4 种模式、Hooks 安全策略、MCP Server 集成、自定义 Helper App 架构、工具池组装和权限模式。29 个测试全部通过。
- 2026-05-15: Senior Developer Review (AI) — 发现并自动修复 3 个 HIGH + 2 个 MEDIUM 问题：(H1) README canUseTool 回调签名错误，从 `(String, Any) -> Bool` 修正为 `(ToolProtocol, Any, ToolContext) -> CanUseToolResult?`；(H3) README 工具池章节引用 AgentOptions 不存在的 `allowed`/`disallowed` 字段，修正为 `allowedTools`/`disallowedTools`；(M1) Permission Modes 表从 3 种补全到全部 6 种（增加 .acceptEdits、.dontAsk、.auto）；(M2) 测试新增对 allowedTools/disallowedTools 字段名和 CanUseToolResult 类型的验证。29 个测试全部通过。

### Senior Developer Review (AI)

**Reviewer:** Nick (GLM-5.1[1m] via Claude Code)
**Date:** 2026-05-15
**Outcome:** Approve (after auto-fix)

**Issues Found and Fixed:**
- H1: README `canUseTool` callback had wrong signature `(String, Any) -> Bool` → fixed to `(ToolProtocol, Any, ToolContext) async -> CanUseToolResult?` with `.allow()`/`.deny()` examples
- H3: README "Tool Pool Assembly" referenced non-existent `allowed`/`disallowed` fields → fixed to `allowedTools`/`disallowedTools`
- M1: Permission Modes table only showed 3/6 modes → added `.acceptEdits`, `.dontAsk`, `.auto`
- M2: Test `test_generate_readme_containsToolPoolAndPermissions` enhanced with field name and API type assertions

**LOW (not fixed, cosmetic):**
- L1: `HelloWorldTool.swift` file name is misleading for a file containing 5 tools (no functional impact)

**Post-fix verification:** 29/29 tests pass.
