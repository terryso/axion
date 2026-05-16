# SDK 边界文档 — OpenAgentSDK vs Axion 应用层

_文档版本: 2.0 | 日期: 2026-05-15 | 更新: Phase 2-3 SDK 集成_

---

## 1. 概述

### Axion 与 OpenAgentSDK 的关系

Axion 是一个 macOS 桌面自动化 CLI 工具，使用 OpenAgentSDK 作为 Agent 编排核心。SDK 提供 Agent 循环、MCP 协议、工具发现、Hooks 和流式消息等通用能力；Axion 负责桌面操作、规划策略、验证逻辑等应用特有功能。

### 文档目的

1. 明确每个模块的归属（SDK / 应用层）和理由
2. 列出当前使用的 SDK 公共 API
3. 记录发现的 SDK 短板和改进建议
4. 与 PRD 边界表对照确认一致性

---

## 2. SDK vs 应用层边界表

| 模块 | 归属 | 理由 |
|------|------|------|
| Agent 循环（turn 管理、tool_use 分发） | **SDK** | 通用 Agent 能力，LLM 交互的标准化编排 |
| MCP Client（连接、工具发现、调用） | **SDK** | 通用 MCP 协议实现，跨进程通信标准 |
| 工具注册（ToolProtocol、defineTool） | **SDK** | 通用工具定义框架（Helper 端使用 mcp-swift-sdk） |
| Hooks 系统（生命周期拦截） | **SDK** | 通用安全/策略框架，可复用的拦截点 |
| 流式消息（AsyncStream&lt;SDKMessage&gt;） | **SDK** | 通用消息管道，LLM 响应的标准流式接口 |
| Session 管理（保存/恢复对话） | **SDK** | 通用会话持久化能力 |
| Planner（LLM 规划） | **应用层** | 规划策略因应用而异（Axion 使用 system prompt 引导 LLM 自主规划） |
| Executor（步骤执行、占位符解析） | **应用层** | 执行策略因应用而异（Axion 通过 SDK Agent loop 间接执行） |
| Verifier（截图/AX 验证） | **应用层** | 验证逻辑与具体任务强相关 |
| AxionHelper（AX 操作、截图） | **应用层** | macOS 桌面操作是 Axion 特有的 |
| 配置管理 | **应用层** | 配置格式因应用而异（分层配置 + Keychain） |
| Trace 记录 | **应用层** | trace 格式因应用而异（JSONL 事件流） |

**PRD 一致性验证：** 上表与 PRD「SDK vs 应用层边界」完全一致。

---

## 3. SDK API 使用清单

### 当前使用的 SDK 公共 API

| SDK API | 使用位置 | 用途 |
|---------|---------|------|
| `createAgent(options:)` | `RunCommand.swift:103` | 创建 Agent 实例（FR36） |
| `AgentOptions` | `RunCommand.swift:89-100` | 配置 Agent 参数 |
| `Agent.stream(task)` | `RunCommand.swift:121` | 启动流式执行，返回 `AsyncStream<SDKMessage>`（FR40） |
| `McpStdioConfig(command:)` | `RunCommand.swift:79` | 配置 Helper 作为 MCP stdio server（FR37） |
| `McpServerConfig.stdio(...)` | `RunCommand.swift:78` | 注册 MCP server 到 Agent |
| `AgentOptions.mcpServers` | `RunCommand.swift:97` | SDK 自动发现 Helper 工具（FR38） |
| `HookRegistry` | `RunCommand.swift:167` | 安全检查 Hook 注册 |
| `HookDefinition` | `RunCommand.swift:171` | 定义 preToolUse hook |
| `HookOutput` | `RunCommand.swift:175,180` | Hook 返回值（approve/block） |
| `HookRegistry.register(.preToolUse)` | `RunCommand.swift:183` | 注册安全检查（FR39） |
| `agent.interrupt()` | `RunCommand.swift:129` | 取消传播（Ctrl-C） |
| `agent.close()` | `RunCommand.swift:136` | 清理资源 |
| `SDKMessage` 枚举 | `RunCommand.swift:190-220` | 消费流式消息 |
| `SDKMessage.assistant` | `RunCommand.swift:193` | 处理 LLM 文本响应 |
| `SDKMessage.toolUse` | `RunCommand.swift:199` | 处理工具调用事件 |
| `SDKMessage.toolResult` | `RunCommand.swift:204` | 处理工具结果事件 |
| `SDKMessage.result` | `RunCommand.swift:210` | 处理最终结果 |
| `SDKMessage.partialMessage` | `RunCommand.swift:217` | 处理流式部分消息 |
| `PermissionMode.bypassPermissions` | `RunCommand.swift:96` | Agent 权限模式 |
| `MCPStdioTransport` | `HelperProcessManager.swift:28` | Helper 进程管理（legacy RunEngine 路径） |
| `MCPClient` | `HelperProcessManager.swift:68` | MCP 客户端（legacy RunEngine 路径） |

### SDK 使用方式总结

RunCommand 的核心流程：

```
1. ConfigManager.load()           → 应用层：加载配置
2. HelperPathResolver.resolve()   → 应用层：定位 Helper
3. PromptBuilder.load()           → 应用层：加载 system prompt
4. McpStdioConfig(command:)       → SDK：配置 MCP server
5. HookRegistry + preToolUse      → SDK：注册安全 Hook
6. AgentOptions(...)              → SDK：配置 Agent
7. createAgent(options:)          → SDK：创建 Agent
8. agent.stream(task)             → SDK：启动流式执行
9. for await message in stream    → SDK：消费 AsyncStream<SDKMessage>
10. agent.interrupt() / close()   → SDK：生命周期管理
```

---

## 4. SDK 短板与改进建议

### 4.1 RunEngine 状态机保留但未使用

- **问题描述：** Story 3-7 选择了方案 A（SDK Agent Loop 作为编排核心），`RunEngine`（plan-execute-verify 状态机）仍保留在代码中但未被 `RunCommand` 调用
- **理想 SDK 能力：** SDK 的 Agent Loop 应支持更细粒度的编排控制（如 plan-verify 循环），或者应明确文档化 SDK Agent Loop 是唯一的编排模式
- **当前变通方案：** RunEngine 保留在代码库中作为潜在的未来批次级别编排保留。当前 Agent Loop 通过 system prompt 引导 LLM 自主完成 plan-execute-verify 循环
- **改进建议：** 如果确认 SDK Agent Loop 满足所有需求，应在后续迭代中移除 RunEngine 或将其重构为 SDK 扩展

### 4.2 HelperProcessManager 角色变化

- **问题描述：** SDK 通过 `AgentOptions.mcpServers` 接管了 Helper 进程管理后，`HelperProcessManager` 仍使用 SDK 的 `MCPStdioTransport` 和 `MCPClient`，但不再被 `RunCommand` 直接调用
- **理想 SDK 能力：** SDK 应完全封装 MCP 进程生命周期，应用层无需感知进程管理细节
- **当前变通方案：** `HelperProcessManager` 为 RunEngine 路径保留，`RunCommand` 的 SDK 路径通过 `mcpServers` 配置让 SDK 管理进程
- **改进建议：** 评估 RunEngine 是否仍然需要，如果不需要则移除 `HelperProcessManager` 对 SDK transport/client 的直接使用

### 4.3 SafetyChecker 逻辑分散

- **问题描述：** 原本的 `SafetyChecker.swift` 模块存在，但 Story 3-7 将安全逻辑移到了 `HookRegistry` + `preToolUse` hook 中
- **理想 SDK 能力：** SDK 的 Hook 系统应完全替代应用层的安全检查逻辑
- **当前变通方案：** `SafetyChecker.swift` 仍存在但不在 SDK 路径中使用；安全检查通过 Hook 实现
- **改进建议：** 移除 `SafetyChecker.swift` 或标记为 deprecated，统一使用 Hook 系统

### 4.4 TraceRecorder 独立实现

- **问题描述：** Axion 使用自建的 `TraceRecorder`（JSONL 事件流），SDK 有自己的日志机制
- **理想 SDK 能力：** SDK 应提供结构化事件流的可扩展接口，允许应用层注入自定义 trace 逻辑
- **当前变通方案：** `RunCommand` 在消费 `SDKMessage` 流时，手动提取事件并调用 `TraceRecorder`
- **改进建议：** 这是正确的边界决策 — trace 格式因应用而异，应用层自行实现是合理的。SDK 可考虑提供 `onEvent` hook 作为扩展点

### 4.5 Config/Keychain 独立实现

- **状态：** 非短板，正确的边界决策
- **理由：** 配置格式和存储方式因应用而异，SDK 不应提供此能力

### 4.6 PromptBuilder 独立实现

- **状态：** 非短板，正确的边界决策
- **理由：** 加载外部 Markdown prompt 文件、变量替换是应用特有逻辑

### 4.7 SDK 能力使用状态

| 能力 | 说明 | 当前状态 |
|------|------|---------|
| Session 管理 | 保存/恢复对话上下文 | SDK 提供 API 但 Axion 未使用（单次运行模式） |
| Memory | 跨运行记忆 | ✅ SDK MemoryStore 已在 Epic 4 集成（`FileBasedMemoryStore`） |
| AgentMCPServer | Agent 作为 MCP Server | ✅ 已在 Epic 6 集成（`MCPServerRunner`） |
| Pause Protocol | 用户接管机制 | ✅ 已在 Epic 7 集成（`PauseForHumanTool`） |
| 多模型切换 | 运行时切换 LLM 模型 | 通过配置实现，不需要 SDK 支持 |
| 批量操作 | 并行执行多个任务 | Axion 当前是单任务模式 |

---

## 5.5. Phase 2 SDK 集成（Epic 4-7）

### Memory 集成（Epic 4）

| SDK API | 使用位置 | 用途 |
|---------|---------|------|
| `MemoryStoreProtocol` | `MemoryContextProvider.swift` | 跨任务记忆存储接口 |
| `FileBasedMemoryStore(memoryDir:)` | `RunCommand.swift` | 基于文件系统的 Memory 持久化 |
| `ToolContext.memoryStore` | 工具执行上下文 | 工具内访问 Memory |
| `memoryStore.save(domain:knowledge:)` | `AppMemoryExtractor.swift` | 保存 App 操作模式 |
| `memoryStore.query(domain:)` | `MemoryContextProvider.swift` | 读取历史操作经验 |

**边界决策：** Memory 存储属于 SDK，但"提取什么经验"和"如何利用经验"属于应用层。

### AgentMCPServer — Agent 作为 MCP Server（Epic 6）

| SDK API | 使用位置 | 用途 |
|---------|---------|------|
| `AgentMCPServer(name:tools:)` | `MCPServerRunner.swift` | 将 Axion 暴露为 MCP stdio server |
| `McpServer.run()` | `MCPServerRunner.swift` | 启动 MCP server 监听 stdin |

**边界决策：** MCP Server 框架属于 SDK，但 Axion 暴露的具体工具（`run_task`、`query_task_status`）属于应用层。

### Pause Protocol — 用户接管（Epic 7）

| SDK API | 使用位置 | 用途 |
|---------|---------|------|
| `PauseForHumanTool` | `RunCommand.swift` | SDK 内置的暂停工具 |
| `Agent.pause(reason:)` | 概念上通过 SDK Agent Loop | 暂停 Agent 执行 |
| `Agent.resume(context:)` | 概念上通过 SDK Agent Loop | 恢复 Agent 执行 |

**边界决策：** 暂停协议属于 SDK，但"如何向用户展示暂停提示"和"用户输入如何传递回 Agent"属于应用层。

---

## 5.6. Phase 3 SDK 集成（Epic 8-11）

### 技能系统（Epic 9）

技能系统是纯应用层实现，使用 SDK 的标准 Agent Loop 和 MCP 工具调用通道执行技能。

| 应用层组件 | 说明 |
|-----------|------|
| `SkillExecutor` | 技能执行引擎，通过 MCP 调用 Helper 执行技能步骤 |
| `SkillCompiler` | 录制 → 技能编译管道 |
| `OperationRecorder` | CGEvent Tap 录制引擎 |

**边界决策：** 技能格式（JSON）、录制引擎、编译管道全是应用层。SDK 不感知技能概念。

### AxionBar 菜单栏 App（Epic 10）

AxionBar 是独立 macOS App，通过 HTTP API（非 SDK）与 Axion CLI 后端通信。

**关键边界：**
- AxionBar 不 import `OpenAgentSDK`（不需要）
- AxionBar 仅 import `AxionCore`（共享模型）
- 通信通过 HTTP API（`localhost:4242`），不走 MCP stdio

### SDK 生态 — ScaffoldCLI（Epic 11）

| SDK 组件 | 位置 | 说明 |
|---------|------|------|
| `ScaffoldCLI` | OpenAgentSDK 仓库 | 独立可执行目标，生成 Agent 项目模板 |
| `defineTool()` | SDK `ToolBuilder.swift` | 4 种重载覆盖所有工具定义场景 |
| `ToolProtocol` | SDK `ToolTypes.swift` | 工具协议，所有工具的统一类型 |
| `HookRegistry` | SDK `HookRegistry.swift` | 22 个生命周期事件拦截 |
| `assembleToolPool()` | SDK `ToolRegistry.swift` | 工具池组装（base → custom → MCP，同名去重） |
| `McpServerConfig` | SDK MCP 模块 | MCP server 配置（stdio/sse/http/sdk） |

**ScaffoldCLI 生成的模板覆盖：**
- basic: 最小 Agent 骨架（`createAgent` + `defineTool` + `agent.prompt`）
- mcp-integration: 集成 Axion 桌面操作（`McpStdioConfig` + `axion mcp`）

**边界决策：** ScaffoldCLI 属于 SDK 仓库，模板代码只使用 SDK 公共 API，不引用 Axion 特有模块。

---

## 5. 模块依赖审计结果

### 5.1 Import 审计

| 检查项 | 结果 | 说明 |
|--------|------|------|
| AxionCore 无 `import OpenAgentSDK` | PASS | Core 是纯模型层 |
| AxionHelper 无 `import OpenAgentSDK` | PASS | Helper 只做 AX 操作 |
| AxionCLI 无 `import AxionHelper` | PASS | 两者仅通过 MCP stdio 通信 |
| 无直接 `import Anthropic` | PASS | 所有 LLM 调用通过 SDK |
| 无直接 HTTP 调用 Anthropic API | PASS | SDK 封装了所有 API 交互 |

### 5.2 API 使用审计

| 检查项 | 结果 | 说明 |
|--------|------|------|
| RunCommand 使用 `createAgent()` | PASS | 标准 SDK 入口 |
| RunCommand 使用 `AgentOptions` | PASS | 标准 SDK 配置 |
| RunCommand 使用 `Agent.stream()` | PASS | 标准流式执行 |
| MCP 配置使用 `McpStdioConfig` | PASS | 标准 MCP 配置 |
| 工具发现通过 SDK 自动 | PASS | `mcpServers` 配置即可 |
| Hook 使用 `HookRegistry` | PASS | 标准 Hook API |
| 消息消费 `SDKMessage` 枚举 | PASS | 标准消息类型 |

### 5.3 边界一致性

| PRD 边界规则 | 实际代码 | 一致性 |
|-------------|---------|--------|
| Agent 循环 → SDK | `createAgent` + `Agent.stream` | 一致 |
| MCP Client → SDK | `McpStdioConfig` + `mcpServers` | 一致 |
| Hooks → SDK | `HookRegistry` + `preToolUse` | 一致 |
| 流式消息 → SDK | `AsyncStream<SDKMessage>` | 一致 |
| Planner → 应用层 | `PromptBuilder` + `planner-system.md` | 一致 |
| Executor → 应用层 | SDK Agent loop 间接执行 | 一致（方案 A） |
| Verifier → 应用层 | LLM 自主验证（通过 system prompt） | 一致 |
| AxionHelper → 应用层 | mcp-swift-sdk 工具注册 | 一致 |
| Config → 应用层 | `ConfigManager` + Keychain | 一致 |
| Trace → 应用层 | `TraceRecorder` (JSONL) | 一致 |

---

## 6. 端到端验证结果

> **验证日期：** 2026-05-10 | **测试人：** nick | **macOS 15.7.3**

### Calculator 场景 — PASS

- **命令：** `axion run "打开计算器，计算 17 乘以 23"`
- **运行 ID：** 20260510-z6880l
- **结果：** Calculator 显示 391（正确）
- **工具链：** launch_app → screenshot → click×10 → screenshot → hotkey → press_key → type_text → screenshot → 最终确认 391
- **trace 事件：** 90 个
- **Agent 表现：** 自纠错成功（先尝试 click 失败，切换策略后成功）

### TextEdit 场景 — PASS

- **命令：** `axion run "打开 TextEdit，输入 Hello World"`
- **运行 ID：** 20260510-ex5r79
- **结果：** TextEdit 新文档包含 "Hello World"
- **工具链：** launch_app → screenshot → list_windows → get_accessibility_tree → hotkey(cmd+n) → screenshot → list_windows → get_accessibility_tree → click → type_text → screenshot
- **trace 事件：** 40 个
- **Agent 表现：** 正确使用 AX tree 定位 AXTextArea 并输入

### Finder 场景 — PASS

- **命令：** `axion run "打开 Finder，进入下载目录"`
- **运行 ID：** 20260510-7ej9wi
- **结果：** Finder 导航到下载目录（窗口标题 "下载"）
- **工具链：** screenshot → hotkey(cmd+space) → type_text("Finder") → press_key(return) → screenshot → hotkey(cmd+shift+g) → type_text("~/Downloads") → press_key(return) → screenshot → list_windows
- **trace 事件：** 43 个
- **Agent 表现：** 使用 Spotlight + "前往文件夹" 快捷键，策略智能

### 浏览器场景 — PASS

- **命令：** `axion run "打开 Safari，访问 example.com"`
- **运行 ID：** 20260510-2655ra
- **结果：** Safari 打开 https://example.com
- **工具链：** launch_app → open_url
- **trace 事件：** 10 个
- **Agent 表现：** 最简操作，2 步完成

### 验证修复记录

端到端验证前发现并修复了一个关键问题：

- **系统 prompt 不兼容 SDK Agent Loop**：原 `planner-system.md` 指导 LLM 输出 JSON 计划文本而非调用 MCP 工具，与 SDK Agent Loop 架构不兼容。已重写 prompt 为直接工具调用模式。

---

## 7. 未来 SDK 改进方向

基于当前审计，建议 SDK 在以下方向改进：

1. **结构化输出控制** — 提供 `onTurnComplete` 或 `onPlanGenerated` hook，允许应用层在 Agent turn 之间注入自定义逻辑
2. **Trace 扩展点** — 提供标准化的 `EventEmitter` 接口，应用层可注入自定义 trace 逻辑而无需手动解析 `SDKMessage`
3. **多 MCP Server 编排** — 当前 `mcpServers` 是扁平字典，未来可能需要支持 server 优先级、分组等
4. **流式消息增强** — `SDKMessage` 可考虑增加 `planGenerated`、`stepCompleted` 等更细粒度的消息类型
5. **Agent 中间件** — 类似 Hook 但更通用，允许应用层在 Agent loop 中注入自定义处理逻辑
