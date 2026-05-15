# Story 11.3: 开发者文档与示例库

Status: ready-for-dev

## Story

As a 第三方开发者,
I want 有完整的开发文档和示例代码,
So that 我可以快速上手并避免踩坑.

## Acceptance Criteria

1. **AC1: 完整的开发指南文档**
   Given OpenAgentSDK 仓库的 `docs/` 目录
   When 浏览文档
   Then 包含以下指南：快速开始（5 分钟跑通第一个 Agent）、工具开发指南、MCP 集成指南、Agent 自定义指南、Session 和 Memory 使用指南

2. **AC2: 至少 5 个完整示例**
   Given SDK `Examples/` 目录
   When 查看示例
   Then 包含至少 5 个完整可运行示例：基础 Agent、自定义工具、MCP 集成、Session 管理、Memory 使用（注：已有 30+ Examples，需确认覆盖这 5 个核心场景，如有缺失则补充）

3. **AC3: Axion 关键模块内联文档**
   Given Axion 作为参考实现
   When 开发者阅读 Axion 源码
   Then 关键模块（Planner、Executor、Memory、MCP Server）有清晰的内联文档说明设计决策

4. **AC4: SDK API 文档完善**
   Given SDK 的 API 文档（README 和 docs/）
   When 查看 `createAgent` 等 API
   Then 包含参数说明、使用场景、返回类型和常见错误处理模式

5. **AC5: 打包和分发指南**
   Given 开发者完成自己的 Agent
   When 准备分发
   Then 文档提供打包和分发指南（SPM package 结构、Helper App 签名、Homebrew formula）

## Tasks / Subtasks

- [ ] Task 1: 创建 `docs/getting-started.md` 快速开始指南 (AC: #1)
  - [ ] 1.1 5 分钟快速开始教程：从安装到运行第一个 Agent
  - [ ] 1.2 API Key 配置说明（环境变量 vs 代码配置）
  - [ ] 1.3 第一个 Agent 代码示例（最小可运行代码）
  - [ ] 1.4 常见问题排查（编译错误、API 连接问题、权限问题）

- [ ] Task 2: 创建 `docs/tool-development-guide.md` 工具开发指南 (AC: #1, #4)
  - [ ] 2.1 `defineTool` 4 种重载详解（Codable+String, Codable+Result, No-Input, Raw Dict）
  - [ ] 2.2 `ToolProtocol` 接口说明（name, description, inputSchema, isReadOnly, annotations）
  - [ ] 2.3 `ToolContext` 可用字段和用途（cwd, toolUseId, memoryStore, hookRegistry）
  - [ ] 2.4 `ToolResult` 和 `ToolExecuteResult` 返回类型
  - [ ] 2.5 工具命名最佳实践和 inputSchema JSON Schema 编写指南

- [ ] Task 3: 创建 `docs/mcp-integration-guide.md` MCP 集成指南 (AC: #1)
  - [ ] 3.1 MCP 协议概念介绍（stdio, SSE, HTTP 传输模式）
  - [ ] 3.2 `McpServerConfig` 配置说明（stdio/sse/http/sdk 四种类型）
  - [ ] 3.3 集成 Axion 的 `axion mcp` 作为桌面操作工具源
  - [ ] 3.4 工具命名空间规则（`mcp__{serverName}__{toolName}`）
  - [ ] 3.5 自定义 MCP Server 开发（基于 swift-mcp 的 `@Tool` 宏）
  - [ ] 3.6 InProcessMCPServer 直接集成模式

- [ ] Task 4: 创建 `docs/agent-customization-guide.md` Agent 自定义指南 (AC: #1, #4)
  - [ ] 4.1 `AgentOptions` 所有参数详解
  - [ ] 4.2 `createAgent` API 说明（返回类型、使用场景）
  - [ ] 4.3 System Prompt 设计指南和最佳实践
  - [ ] 4.4 `PermissionMode` 6 种模式详解
  - [ ] 4.5 Hook 系统详解（22 个生命周期事件、注册方式、matcher 正则）
  - [ ] 4.6 错误处理模式（常见错误类型和处理策略）

- [ ] Task 5: 创建 `docs/session-memory-guide.md` Session 和 Memory 使用指南 (AC: #1)
  - [ ] 5.1 Session 持久化：`agent.stream()` 和 `agent.prompt()` 消息流
  - [ ] 5.2 `MemoryStoreProtocol` 接口和 `FileBasedMemoryStore` 实现
  - [ ] 5.3 跨任务记忆的读写和使用模式
  - [ ] 5.4 Session 管理（save/load/fork/list/delete）

- [ ] Task 6: 创建 `docs/packaging-distribution-guide.md` 打包和分发指南 (AC: #5)
  - [ ] 6.1 SPM package 结构最佳实践
  - [ ] 6.2 Helper App 打包和代码签名流程
  - [ ] 6.3 Homebrew formula 编写指南（参考 Axion 的 Homebrew 分发模式）
  - [ ] 6.4 CI/CD 集成建议

- [ ] Task 7: 确认和补充 Examples 核心示例 (AC: #2)
  - [ ] 7.1 检查现有 30+ Examples 是否覆盖 5 个核心场景
  - [ ] 7.2 更新 Examples/README.md 添加核心场景索引和推荐学习路径
  - [ ] 7.3 如有缺失场景，补充示例代码

- [ ] Task 8: Axion 关键模块内联文档 (AC: #3)
  - [ ] 8.1 RunCommand.swift（Planner/执行入口）添加设计决策注释
  - [ ] 8.2 MCPServerRunner.swift（MCP Server 模式）添加架构说明注释
  - [ ] 8.3 MemoryContextProvider.swift（Memory 系统）添加设计决策注释
  - [ ] 8.4 AgentRunner.swift（API Agent 执行）添加架构说明注释

- [ ] Task 9: 单元测试 (AC: #1-#5)
  - [ ] 9.1 测试所有文档文件存在且内容完整
  - [ ] 9.2 测试文档中的代码示例能编译通过（可选，CI 环境验证）
  - [ ] 9.3 测试 Examples/README 更新包含核心场景索引

## Dev Notes

### Epic 11 与前序 Story 关系

- **Story 11.1（已完成）**：脚手架 CLI + 项目模板 → 开发者能快速创建项目骨架
- **Story 11.2（已完成）**：插件化工具注册 + Agent 扩展 → 脚手架模板已包含工具开发、Hooks、MCP 集成章节
- **Story 11.3（本 Story）**：开发者文档与示例库 → 独立的、更深入的开发者指南

Story 11.3 与 11.2 的 README 模板不同：11.2 的 README 是脚手架生成的项目级 README，11.3 是 SDK 仓库级别的开发者文档。

### 现有文档资产（可直接复用）

**OpenAgentSDK 仓库已有：**

| 资产 | 位置 | 内容 |
|------|------|------|
| README.md | 仓库根 | 471 行，包含 Quick Start、Highlights、Streaming、Tools、Sessions、MCP 等 |
| README_CN.md | 仓库根 | 中文版 README |
| Examples/ | 30+ 示例 | BasicAgent, CustomTools, MCPIntegration, MemoryStoreExample, SessionsAndHooks 等 |
| Examples/README.md | Examples 目录 | 教程式指南，含 Quick Start 和所有示例说明 |
| docs/product-plan.md | docs 目录 | 产品计划（416 行） |
| Sources/ScaffoldCLI/Templates/ | 脚手架模板 | 11.2 已包含工具开发、Hooks、MCP 集成的模板章节 |

**Axion 仓库已有：**

| 资产 | 位置 | 内容 |
|------|------|------|
| docs/sdk-boundary.md | docs 目录 | SDK vs 应用层边界说明 |
| CLAUDE.md | 仓库根 | AI 编码规则（测试执行规则等） |

### 关键发现：现有 Examples 已覆盖大部分核心场景

检查 Examples 目录，已有的核心场景覆盖：

| 核心场景 | 已有示例 | 状态 |
|----------|---------|------|
| 基础 Agent | `BasicAgent/` | ✅ 已有 |
| 自定义工具 | `CustomTools/`, `MultiToolExample/` | ✅ 已有 |
| MCP 集成 | `MCPIntegration/`, `AdvancedMCPExample/`, `AgentMCPServerExample/` | ✅ 已有 |
| Session 管理 | `CompatSessions/`, `SessionsAndHooks/` | ✅ 已有 |
| Memory 使用 | `MemoryStoreExample/` | ✅ 已有 |

**结论：** 核心示例已充分覆盖，Task 7 主要工作是更新 Examples/README.md 添加学习路径索引，而非新增示例。

### 文档创建策略

本 Story 的核心工作是**组织和完善**，而非从零开始：

1. **从 README 提取并扩展** — README 已有 Quick Start 和各功能概述，文档指南应更深入
2. **从 Story 11.2 模板提取** — 脚手架 README 已有工具开发、Hooks、MCP 的详细章节，可复用为文档基础
3. **从 Examples 提取代码** — 文档中的代码示例应引用已有 Examples 中的实际代码

### SDK 核心 API 速查（文档需覆盖）

**Agent 创建：**
```swift
// Sources/OpenAgentSDK/Core/Agent.swift
public func createAgent(options: AgentOptions) -> Agent
```

**Agent 运行：**
```swift
agent.prompt("task") -> PromptResult          // 单次调用
agent.stream("task") -> AsyncStream<SDKMessage> // 流式调用
agent.close() async -> Void                    // 清理
```

**AgentOptions 关键参数（Sources/OpenAgentSDK/Types/AgentTypes.swift）：**
- `apiKey: String` — API 密钥
- `model: String` — 模型名称（如 "claude-sonnet-4-6"）
- `baseURL: String?` — 自定义 API 端点
- `systemPrompt: String` — 系统提示
- `maxTurns: Int` — 最大循环轮数
- `maxTokens: Int` — 最大输出 token 数
- `permissionMode: PermissionMode` — 6 种权限模式
- `tools: [ToolProtocol]?` — 自定义工具数组
- `mcpServers: [String: McpServerConfig]?` — MCP 服务器配置
- `memoryStore: MemoryStoreProtocol?` — 跨任务记忆存储
- `hookRegistry: HookRegistry?` — Hook 注册表
- `allowedTools: [String]?` — 工具白名单
- `disallowedTools: [String]?` — 工具黑名单
- `canUseTool: CanUseToolCallback?` — 自定义权限回调
- `logLevel: LogLevel?` — 日志级别

### Story 11.2 的关键经验

1. **`AnyTool` 类型不存在** → 必须使用 `ToolProtocol`
2. **`defineTool` 的 `inputSchema` 必须与 Codable Input 类型一致**
3. **模板字符串中的 Swift 插值需要双重转义** → `\\()` 在模板源码中
4. **SDK API 名称要准确** → 11.2 review 中发现 `allowed`/`disallowed` 应为 `allowedTools`/`disallowedTools`

### 修改位置

**OpenAgentSDK 仓库（主要修改）：**

| 文件 | 操作 |
|------|------|
| `docs/getting-started.md` | 新建 |
| `docs/tool-development-guide.md` | 新建 |
| `docs/mcp-integration-guide.md` | 新建 |
| `docs/agent-customization-guide.md` | 新建 |
| `docs/session-memory-guide.md` | 新建 |
| `docs/packaging-distribution-guide.md` | 新建 |
| `Examples/README.md` | 更新（添加学习路径索引） |
| `README.md` | 可能小幅更新（添加 docs/ 目录链接） |

**Axion 仓库（辅助修改）：**

| 文件 | 操作 |
|------|------|
| `Sources/AxionCLI/Commands/RunCommand.swift` | 添加设计决策注释 |
| `Sources/AxionCLI/MCP/MCPServerRunner.swift` | 添加架构说明注释 |
| `Sources/AxionCLI/Memory/MemoryContextProvider.swift` | 添加设计决策注释 |
| `Sources/AxionCLI/API/AgentRunner.swift` | 添加架构说明注释 |
| `_bmad-output/implementation-artifacts/sprint-status.yaml` | 状态更新 |

### 测试策略

- **文档存在性测试**：验证所有 6 个文档文件存在且非空
- **文档内容测试**：验证文档包含关键章节标题和代码示例
- **Examples README 测试**：验证学习路径索引包含 5 个核心场景

### NFR 约束

- 文档中的代码示例必须是可编译的（不需要实际运行）
- 文档总大小不宜超过 50KB（6 个文档合计）
- 文档格式统一使用 Markdown，代码块标注 `swift` 语言

### References

- SDK README: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/README.md]
- SDK Examples README: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Examples/README.md]
- SDK AgentOptions: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/AgentTypes.swift]
- SDK createAgent: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift]
- SDK defineTool: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/ToolBuilder.swift]
- SDK ToolProtocol: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/ToolTypes.swift]
- SDK HookRegistry: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Hooks/HookRegistry.swift]
- SDK HookTypes: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/HookTypes.swift]
- SDK MCPToolDefinition: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/MCP/MCPToolDefinition.swift]
- SDK MemoryStore: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Memory/]
- Axion RunCommand: [Source: Sources/AxionCLI/Commands/RunCommand.swift]
- Axion MCPServerRunner: [Source: Sources/AxionCLI/MCP/MCPServerRunner.swift]
- Axion MemoryContextProvider: [Source: Sources/AxionCLI/Memory/MemoryContextProvider.swift]
- Axion AgentRunner: [Source: Sources/AxionCLI/API/AgentRunner.swift]
- Story 11.2 (前序 Story): [Source: _bmad-output/implementation-artifacts/11-2-plugin-tool-registration-agent-extension.md]
- Story 11.1: [Source: _bmad-output/implementation-artifacts/11-1-agent-project-template-scaffold-cli.md]
- Epics (Epic 11): [Source: _bmad-output/planning-artifacts/epics.md]
