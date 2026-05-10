# Story 3.8: SDK 边界文档与端到端验证

Status: done

## Story

As a SDK 开发者和用户,
I want 有一份清晰的 SDK vs 应用层边界文档，并验证核心场景端到端可用,
so that 后续 SDK 和 Axion 的开发有明确的指导.

## Acceptance Criteria

1. **AC1: SDK 集成点审查**
   - Given 所有模块已实现
   - When 审查代码
   - Then 每个 SDK 集成点使用 SDK 公共 API，不绕过 SDK 直接调用底层实现

2. **AC2: SDK 边界文档**
   - Given SDK 边界文档已编写
   - When 阅读文档
   - Then 每个模块的归属（SDK / 应用层）有明确的理由说明，与 PRD 的 SDK vs 应用层边界表一致

3. **AC3: SDK 短板记录**
   - Given SDK 短板发现
   - When 记录到边界文档
   - Then 包含问题描述、为什么应该是 SDK 能力、当前的临时变通方案

4. **AC4: Calculator 端到端验证**
   - Given Calculator 场景
   - When 运行 `axion run "打开计算器，计算 17 乘以 23"`
   - Then 成功完成，Calculator 显示 391

5. **AC5: TextEdit 端到端验证**
   - Given TextEdit 场景
   - When 运行 `axion run "打开 TextEdit，输入 Hello World"`
   - Then 成功完成，TextEdit 中包含 Hello World

6. **AC6: Finder 端到端验证**
   - Given Finder 场景
   - When 运行 `axion run "打开 Finder，进入下载目录"`
   - Then 成功完成，Finder 导航到下载目录

7. **AC7: 浏览器端到端验证**
   - Given 浏览器场景
   - When 运行 `axion run "打开 Safari，访问 example.com"`
   - Then 成功完成，Safari 打开 example.com

## Tasks / Subtasks

- [x] Task 1: 审查代码中所有 SDK 集成点 (AC: #1)
  - [x] 1.1 审查 `Sources/AxionCLI/Commands/RunCommand.swift` — 确认使用 `createAgent()` + `Agent.stream()` 公共 API
  - [x] 1.2 审查 MCP 连接 — 确认通过 `AgentOptions.mcpServers` + `McpStdioConfig` 配置（非手动 HelperProcessManager）
  - [x] 1.3 审查工具注册 — 确认通过 MCP 自动发现（`tools/list`），非手动注册
  - [x] 1.4 审查 Hooks — 确认使用 `HookRegistry` + `preToolUse` hook（非直接方法调用）
  - [x] 1.5 审查流式输出 — 确认消费 `AsyncStream<SDKMessage>`（非自行解析 LLM 响应）
  - [x] 1.6 审查无绕过 — 确认代码中没有 `import Anthropic` 或直接 HTTP 调用 Anthropic API
  - [x] 1.7 审查模块边界 — 确认 AxionCore 无 `import OpenAgentSDK`，AxionHelper 无 `import OpenAgentSDK`，AxionCLI 无 `import AxionHelper`

- [x] Task 2: 编写 SDK 边界文档 (AC: #2)
  - [x] 2.1 创建 `docs/sdk-boundary.md` — SDK vs 应用层边界文档
  - [x] 2.2 为每个模块明确归属（SDK / 应用层）和理由
  - [x] 2.3 对照 PRD 表「SDK vs 应用层边界」验证一致性
  - [x] 2.4 包含当前实际的 SDK API 使用清单（createAgent, AgentOptions, Agent.stream, HookRegistry, McpStdioConfig 等）

- [x] Task 3: 记录 SDK 短板和改进建议 (AC: #3)
  - [x] 3.1 检查 Axion 代码中是否有变通方案（workaround）或跳过 SDK 的地方
  - [x] 3.2 记录每个短板：问题描述、理想 SDK 能力、当前变通方案
  - [x] 3.3 记录 SDK 缺失但 Axion 当前不需要的能力（如 Session 管理、Memory）
  - [x] 3.4 将短板记录写入 `docs/sdk-boundary.md` 的「SDK 短板与改进建议」章节

- [x] Task 4: Calculator 端到端验证 (AC: #4) — 需要真实 macOS 桌面环境手动验证
  - [x] 4.1 确保 Helper 进程可用（`axion doctor` 检查通过）
  - [x] 4.2 运行 `axion run "打开计算器，计算 17 乘以 23"` 并验证 Calculator 显示 391
  - [x] 4.3 检查终端输出包含步骤信息和完成汇总
  - [x] 4.4 检查 trace 文件（`~/.axion/runs/{runId}/trace.jsonl`）完整记录
  - [x] 4.5 编写手动验收脚本或文档记录测试结果

- [x] Task 5: TextEdit 端到端验证 (AC: #5) — 需要真实 macOS 桌面环境手动验证
  - [x] 5.1 运行 `axion run "打开 TextEdit，输入 Hello World"`
  - [x] 5.2 验证 TextEdit 打开且包含 "Hello World" 文本
  - [x] 5.3 检查 trace 文件完整性

- [x] Task 6: Finder 端到端验证 (AC: #6) — 需要真实 macOS 桌面环境手动验证
  - [x] 6.1 运行 `axion run "打开 Finder，进入下载目录"`
  - [x] 6.2 验证 Finder 导航到下载目录
  - [x] 6.3 检查 trace 文件完整性

- [x] Task 7: 浏览器端到端验证 (AC: #7) — 需要真实 macOS 桌面环境手动验证
  - [x] 7.1 运行 `axion run "打开 Safari，访问 example.com"`
  - [x] 7.2 验证 Safari 打开并导航到 example.com
  - [x] 7.3 检查 trace 文件完整性

- [x] Task 8: 编写单元测试 (无独立 AC，质量保障)
  - [x] 8.1 创建 `Tests/AxionCLITests/Commands/SDKBoundaryAuditTests.swift` — 审计测试
  - [x] 8.2 测试：确认 AxionCore 无 `import OpenAgentSDK`（扫描源文件）
  - [x] 8.3 测试：确认 AxionHelper 无 `import OpenAgentSDK`（扫描源文件）
  - [x] 8.4 测试：确认 RunCommand 使用 SDK 公共 API（结构检查）
  - [x] 8.5 运行全部单元测试确认无回归

- [x] Task 9: 更新 sprint 状态和最终验证
  - [x] 9.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认全部通过
  - [x] 9.2 更新 sprint-status.yaml

## Dev Notes

### 核心目标

本 Story 是 Epic 3 的最后一个 Story，也是整个 Axion MVP 的收尾工作。核心目标是：

1. **文档化** — 编写 SDK vs 应用层的边界文档，明确每个模块的归属和理由
2. **审计** — 审查代码确保所有 SDK 集成点使用公共 API，没有绕过 SDK 的地方
3. **验证** — 端到端运行 4 个核心场景，确认 Axion MVP 功能完整

### 架构定位

本 Story 覆盖的 FR：
- **FR41**: 产出的 SDK 边界文档明确记录每个模块的归属（SDK / 应用层）和理由
- **FR36-FR40** 的验证：确认这些 SDK 集成点确实使用了 SDK 公共 API

### PRD SDK vs 应用层边界表（必须与文档一致）

| 模块 | 归属 | 理由 |
|------|------|------|
| Agent 循环（turn 管理、tool_use 分发） | **SDK** | 通用 Agent 能力 |
| MCP Client（连接、工具发现、调用） | **SDK** | 通用 MCP 协议实现 |
| 工具注册（ToolProtocol、defineTool） | **SDK** | 通用工具定义框架 |
| Hooks 系统（生命周期拦截） | **SDK** | 通用安全/策略框架 |
| 流式消息（AsyncStream<SDKMessage>） | **SDK** | 通用消息管道 |
| Session 管理（保存/恢复对话） | **SDK** | 通用会话持久化 |
| Planner（LLM 规划） | **应用层** | 规划策略因应用而异 |
| Executor（步骤执行、占位符解析） | **应用层** | 执行策略因应用而异 |
| Verifier（截图/AX 验证） | **应用层** | 验证逻辑与具体任务强相关 |
| AxionHelper（AX 操作、截图） | **应用层** | macOS 桌面操作是 Axion 特有的 |
| 配置管理 | **应用层** | 配置格式因应用而异 |
| Trace 记录 | **应用层** | trace 格式因应用而异 |

### 当前 SDK API 使用清单（Story 3-7 已实现的集成点）

RunCommand.swift 中的 SDK 集成点：

1. **`createAgent(options:)`** — 创建 Agent 实例（FR36）
2. **`AgentOptions`** — 配置 Agent 参数（apiKey, model, systemPrompt, maxTurns, mcpServers, hookRegistry, permissionMode）
3. **`Agent.stream(task)`** — 启动流式执行，返回 `AsyncStream<SDKMessage>`（FR40）
4. **`McpStdioConfig(command:)`** — 配置 Helper 作为 MCP stdio server（FR37）
5. **`AgentOptions.mcpServers`** — 注册 MCP server，SDK 自动发现工具（FR38）
6. **`HookRegistry` + `register(.preToolUse)`** — 安全检查 Hook（FR39）
7. **`HookDefinition` + `HookOutput`** — Hook 定义和返回值
8. **`agent.interrupt()`** — 取消传播
9. **`agent.close()`** — 清理资源
10. **`SDKMessage` 枚举** — 消费流式消息（.assistant, .toolUse, .toolResult, .result, .partialMessage）

### SDK 短板检查方向

审查时关注以下可能的短板：

1. **RunEngine 状态机保留但未使用** — Story 3-7 选择了方案 A（SDK Agent Loop 作为编排核心），RunEngine 仍保留在代码中但未被 RunCommand 调用。这是否需要清理？RunEngine 可能为未来的批次级别编排保留。
2. **SafetyChecker 逻辑分散** — 原本的 SafetyChecker.swift 和新的 HookRegistry 是否有重叠？
3. **HelperProcessManager 角色变化** — SDK 接管了 Helper 进程管理后，HelperProcessManager 是否还有必要？
4. **TraceRecorder 独立实现** — SDK 有自己的 trace/log 机制，Axion 使用自建的 TraceRecorder 是否是短板？
5. **Config/Keychain 独立实现** — 这些是应用层逻辑，SDK 不应提供。确认这不是短板而是正确的边界。
6. **PromptBuilder 独立实现** — 加载外部 Markdown prompt 文件是应用层逻辑。确认正确。

### 端到端验证注意事项

**这些是手动测试**，需要：
- 真实 macOS 桌面环境
- Helper 已编译且可用
- Anthropic API Key 已配置
- Accessibility 和屏幕录制权限已授予
- Calculator、TextEdit、Finder、Safari 应用可用

**每个场景的验证清单：**
1. CLI 启动正常（无崩溃）
2. Helper 进程启动并建立 MCP 连接
3. LLM 生成合理的执行计划
4. 步骤按计划执行
5. 终端输出实时更新
6. 任务成功完成
7. trace 文件记录完整
8. Helper 进程正确退出

**注意：** 端到端测试受 LLM 响应不确定性影响。相同 prompt 可能产生不同计划。验证重点是「系统端到端可运行」而非「每次结果完全一致」。

### 现有代码状态

**已完成模块（全部在 Sources/ 中）：**

AxionCore（共享模型）：
- `Models/`: Plan, Step, StopCondition, RunState, RunContext, ExecutedStep, AxionConfig, VerificationResult
- `Protocols/`: PlannerProtocol, ExecutorProtocol, VerifierProtocol, MCPClientProtocol, OutputProtocol
- `Constants/`: ToolNames, ConfigKeys
- `Errors/`: AxionError

AxionCLI（CLI 主程序）：
- `Commands/`: RunCommand（SDK Agent 集成）, SetupCommand, DoctorCommand
- `Engine/`: RunEngine（保留但未在 SDK 路径中使用）
- `Planner/`: LLMPlanner, PlanParser, PromptBuilder
- `Executor/`: StepExecutor, PlaceholderResolver, SafetyChecker
- `Verifier/`: TaskVerifier, StopConditionEvaluator
- `Helper/`: HelperProcessManager, HelperPathResolver
- `Output/`: TerminalOutput, JSONOutput
- `Trace/`: TraceRecorder
- `Config/`: ConfigManager

AxionHelper（Helper App）：
- `MCP/`: HelperMCPServer, ToolRegistrar
- `Services/`: AccessibilityEngine, AppLauncher, InputSimulationService, ScreenshotService, URLOpenerService, ServiceContainer
- `Models/`: AppInfo, AXElement, WindowInfo, WindowState

**测试（Tests/ 中）：**
- 518 个单元测试全部通过
- 集成测试需要真实 Helper + AX 权限（CI 不运行）

### SDK 边界文档结构建议

```
# SDK 边界文档

## 1. 概述
   - Axion 与 OpenAgentSDK 的关系
   - 文档目的

## 2. SDK vs 应用层边界表
   - 每个模块的归属和理由
   - 与 PRD 边界表对照

## 3. SDK API 使用清单
   - 当前使用的 SDK 公共 API
   - 每个 API 的使用位置和方式

## 4. SDK 短板与改进建议
   - 发现的问题
   - 理想的 SDK 能力
   - 当前的变通方案

## 5. 端到端验证结果
   - Calculator 场景
   - TextEdit 场景
   - Finder 场景
   - 浏览器场景

## 6. 未来 SDK 改进方向
```

### 关键文件（UPDATE vs NEW）

**UPDATE（审查并可能修改）：** 无。本 Story 主要是文档编写和手动验证，不修改现有源代码。

**NEW（新建）：**
- `docs/sdk-boundary.md` — SDK 边界文档

**可能 UPDATE：**
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — 更新 story 状态

### 审计测试策略

SDKBoundaryAuditTests 测试内容：
1. **import 审计** — 扫描 AxionCore 和 AxionHelper 源文件，确认无 `import OpenAgentSDK`
2. **API 使用审计** — 确认 RunCommand 使用 `createAgent`、`Agent.stream`、`HookRegistry` 等公共 API
3. **边界一致性** — 确认实际代码与 PRD 边界表一致

注意：审计测试不是功能测试，是代码结构合规性检查。

### 禁止事项（反模式）

- **不得绕过 SDK 直接调用 Anthropic API** — 已由 Story 3-7 确保
- **不得在 AxionCore 中 import OpenAgentSDK** — Core 是纯模型层
- **不得在 AxionHelper 中 import OpenAgentSDK** — Helper 只做 AX 操作
- **RunCommand 不得直接 import AxionHelper** — 两者仅通过 MCP 通信
- **不得使用 print() 输出** — 通过 TerminalOutput/JSONOutput 输出
- **API Key 不得出现在日志或文档中** — NFR9
- **端到端测试代码不得混入单元测试** — 手动验收，不放 CI

### import 顺序（如需修改任何 Swift 文件）

```swift
// 1. 系统框架
import Foundation

// 2. 第三方依赖
import OpenAgentSDK

// 3. 项目内部模块
import AxionCore
```

### 目录结构

```
docs/
  sdk-boundary.md                   # NEW: SDK 边界文档

Tests/AxionCLITests/Commands/
  SDKBoundaryAuditTests.swift       # NEW: SDK 边界审计测试

_bmad-output/implementation-artifacts/
  stories/3-8-sdk-boundary-doc-e2e-verification.md   # 本文件
  sprint-status.yaml                # UPDATE: 更新 story 3-8 状态
```

### 前序 Story 关键信息

**Story 3-7 完成记录：**
- 实现了 SDK Agent Loop 方案 A：RunCommand 使用 `createAgent()` + `Agent.stream()` 作为核心编排
- SDK 管理 Helper 进程生命周期（通过 `mcpServers` 配置）
- SafetyChecker 通过 `HookRegistry` + `preToolUse` hook 实现
- 创建了 `SDKTerminalOutputHandler` 和 `SDKJSONOutputHandler` 消费 `AsyncStream<SDKMessage>`
- RunEngine 状态机保留但未在 SDK 路径中使用
- 518 个单元测试全部通过

**关键决策：** 方案 A（完全 SDK Agent Loop）意味着：
- LLM 自主决定 plan/execute/verify 循环（通过 system prompt 引导）
- RunEngine 的 plan-execute-verify 状态机被 SDK Agent 的 turn 循环替代
- 不需要单独的 Planner/Executor/Verifier 模块被 RunCommand 直接调用

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.8] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/prd.md#SDK vs 应用层边界] SDK 边界表
- [Source: _bmad-output/planning-artifacts/prd.md#成功标准] SDK 边界打磨的成功标准
- [Source: _bmad-output/planning-artifacts/architecture.md#模块依赖规则] import 限制
- [Source: _bmad-output/planning-artifacts/architecture.md#进程边界] 进程边界定义
- [Source: _bmad-output/project-context.md#模块依赖（硬性边界）] 模块依赖规则
- [Source: _bmad-output/project-context.md#关键反模式] 反模式清单
- [Source: _bmad-output/implementation-artifacts/stories/3-7-sdk-integration-run-command.md] 前序 Story — SDK 集成完整实现
- [Source: Sources/AxionCLI/Commands/RunCommand.swift] 当前 RunCommand SDK 集成代码
- [Source: Sources/AxionCore/Constants/ToolNames.swift] 工具名常量（20 个工具）
- [Source: Sources/AxionCLI/Engine/RunEngine.swift] RunEngine 状态机（保留但未使用）

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

- 532 unit tests passed, 0 failures, 0 regressions
- 14 SDK boundary audit tests all passed
- All import boundary checks passed (AxionCore, AxionHelper, AxionCLI)

### Completion Notes List

- Task 1: SDK 集成点审查完成。RunCommand 使用 createAgent + Agent.stream + AgentOptions + McpStdioConfig + HookRegistry 全套 SDK 公共 API。无绕过 SDK 的直接 Anthropic 调用。模块边界全部合规（AxionCore 无 OpenAgentSDK import，AxionHelper 无 OpenAgentSDK import，AxionCLI 无 AxionHelper import）。
- Task 2: SDK 边界文档已创建（docs/sdk-boundary.md），包含边界表、API 使用清单、与 PRD 对照。
- Task 3: SDK 短板已记录：RunEngine 保留但未使用、HelperProcessManager 角色变化、SafetyChecker 逻辑分散、TraceRecorder 独立实现（合理）、Config/Prompt 独立实现（合理）。文档化 SDK 缺失但 Axion 不需要的能力。
- Task 4-7: 端到端验证全部通过。Calculator (391 正确, 90 events), TextEdit ("Hello World" 成功, 40 events), Finder (下载目录成功, 43 events), Safari (example.com 成功, 10 events)。修复了 planner-system.md 系统prompt 不兼容 SDK Agent Loop 的问题。
- Task 8: SDKBoundaryAuditTests 14 个审计测试全部启用并通过，包括 import 审计、API 使用审计、文档存在性和内容验证、ToolNames 审计。
- Task 9: 全部 532 单元测试通过，sprint-status.yaml 已更新。

### File List

- `docs/sdk-boundary.md` — NEW: SDK 边界文档（边界表、API 清单、短板记录）
- `Tests/AxionCLITests/Commands/SDKBoundaryAuditTests.swift` — UPDATE: 启用 ATDD 开关（审计完成）
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATE: story 3-8 status → in-progress → review
- `_bmad-output/implementation-artifacts/stories/3-8-sdk-boundary-doc-e2e-verification.md` — UPDATE: 任务复选框、状态、Dev Agent Record
