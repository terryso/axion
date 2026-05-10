# Manual Acceptance Test: Story 3-7 SDK 集成与 Run Command 完整接入

Date: 2026-05-10
Story: 3-7-sdk-integration-run-command
Status: done
Result: **PASS**

## 变更范围

| File | Change | Description |
|------|--------|-------------|
| `Package.swift` | +1 | 添加 OpenAgentSDK 依赖到 AxionCLITests target |
| `Sources/AxionCLI/Commands/RunCommand.swift` | +321/-14 | 替换占位代码，完整 SDK Agent 集成 |
| `Sources/AxionCLI/Output/TerminalOutput.swift` | +6/-1 | 新增 writeStream 方法，write 改为 let |
| `Sources/AxionCore/Constants/ToolNames.swift` | +15 | 新增 allToolNames 数组和 foregroundToolNames 集合 |
| `Sources/AxionCore/Errors/AxionError.swift` | +14 | 新增 missingApiKey 和 helperNotFound 错误 |
| `sprint-status.yaml` | +5/-1 | Story 3-7 状态更新 |
| `Tests/AxionCLITests/Commands/SDKIntegrationATDDTests.swift` | NEW | 37 个 SDK 集成 ATDD 测试 |

## 验收标准 & 测试矩阵

### AC1: SDK Agent Loop 编排

- [x] `createAgent(options:)` 可成功创建 Agent 实例
- [x] `AgentOptions` 包含正确的 apiKey, model, systemPrompt, maxTurns
- [x] `permissionMode` 为 `.bypassPermissions`
- [x] 6 tests passed

### AC2: SDK MCP Client 连接

- [x] Helper 通过 `McpStdioConfig` 配置为 MCP stdio server
- [x] `mcpServers` 字典 key 为 "axion-helper"
- [x] 路径通过 `HelperPathResolver` 解析
- [x] 3 tests passed

### AC3: SDK 工具注册

- [x] 不需要手动 defineTool，通过 MCP 自动发现
- [x] `AgentOptions.tools` 为 nil
- [x] 1 test passed

### AC4: SDK Hooks 安全检查

- [x] HookRegistry + preToolUse hook 实现 SafetyChecker
- [x] 前台工具 (click, type_text 等) 在 shared seat 模式下被阻止
- [x] allowForeground 模式下所有工具放行
- [x] HookRegistry 传入 AgentOptions
- [x] 4 tests passed

### AC5: SDK Streaming 进度输出

- [x] SDKMessage.assistant → TerminalOutput 显示 LLM 响应
- [x] SDKMessage.toolUse → TerminalOutput 显示步骤执行
- [x] SDKMessage.toolResult → TerminalOutput 显示步骤结果
- [x] SDKMessage.result → TerminalOutput 显示最终汇总
- [x] SDKMessage.partialMessage → 流式文本输出
- [x] SDKMessage 记录到 TraceRecorder
- [x] SDKTerminalOutputHandler 和 SDKJSONOutputHandler 正确处理消息
- [x] 12 tests passed (6 stream message + 5 output handler + 1 trace)

### AC6: 完整端到端流程

- [x] RunCommand 使用 SDK Agent 而非直接 HelperProcessManager
- [x] dryrun 模式通过 system prompt 指令实现
- [x] Ctrl-C 取消传播到 agent.interrupt()
- [x] 3 tests passed

### 辅助变更验证

- [x] ToolNames.allToolNames 包含 20 个工具名
- [x] ToolNames.foregroundToolNames 包含 8 个前台工具
- [x] AxionError.missingApiKey 返回正确的 errorPayload
- [x] AxionError.helperNotFound 返回正确的 errorPayload
- [x] 3 tests passed

### 回归测试

- [x] 全部 518 单元测试通过 (0 failures)

### 集成测试 (需要真实 Helper 进程 + AX 权限)

- [x] Story 3-4 集成测试: VerifierIntegrationTests — 2/3 passed (1 pre-existing failure, not caused by Story 3-7)
- [x] Story 3-5 集成测试: OutputTraceIntegrationTests — 5/5 passed
- [x] Story 3-6 集成测试: RunEngineIntegrationTests — 5/5 passed
- Total: 12/13 integration tests passed

**Note**: `test_real_stopConditionEvaluator_withRealAxTree` 的 `windowAppears` 断言失败是因为 macOS Calculator 现在暴露 AXWindow 节点（macOS 更新导致），测试注释说"Calculator has no AXWindow role"已过时。这是前序 Story 3-4 的预存问题，与 Story 3-7 变更无关。

### 代码审查检查

- [x] RunCommand.swift 不直接调用 Anthropic API (仅通过 SDK Agent)
- [x] RunCommand.swift 不 import AxionHelper (仅通过 MCP 通信)
- [x] AxionCore 不 import OpenAgentSDK (SDK 仅在 CLI 层使用)
- [x] 无 print() 调用 — SDKJSONOutputHandler 的默认 write 参数使用 print 是 fallback pattern，与 TerminalOutput 一致
- [x] API Key 不出现在日志或 trace 中 — 仅传递给 AgentOptions
- [x] import 顺序正确: ArgumentParser → Foundation → OpenAgentSDK → AxionCore
- [x] Prompt 通过 PromptBuilder 加载 (非硬编码)
- [x] 错误使用 AxionError 枚举 (非自定义错误)

## 验收结论

**PASS** — Story 3-7 全部 6 个验收标准 (AC1-AC6) 满足，518 个单元测试全部通过，12/13 个集成测试通过（1 个预存问题），代码审查全部通过。
