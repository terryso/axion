---
stepsCompleted: ['step-01-preflight-and-context', 'step-02-generation-mode', 'step-03-test-strategy', 'step-04c-aggregate']
lastStep: 'step-04c-aggregate'
lastSaved: '2026-05-10'
storyId: '3.7'
storyKey: '3-7-sdk-integration-run-command'
storyFile: '_bmad-output/implementation-artifacts/stories/3-7-sdk-integration-run-command.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-3-7-sdk-integration-run-command.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/Commands/SDKIntegrationATDDTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/stories/3-7-sdk-integration-run-command.md'
  - '_bmad-output/project-context.md'
  - 'Sources/AxionCLI/Commands/RunCommand.swift'
  - 'Sources/AxionCLI/Engine/RunEngine.swift'
  - 'Tests/AxionCLITests/Commands/RunCommandATDDTests.swift'
  - 'Tests/AxionCLITests/Engine/RunEngineTests.swift'
  - 'Tests/AxionCLITests/Executor/SafetyCheckerTests.swift'
---

# ATDD Checklist: Story 3-7 SDK 集成与 Run Command 完整接入

## TDD Red Phase (Current)

测试脚手架已生成，所有测试在实现前会跳过（使用 `throw XCTSkip()`）。

- **Unit/Integration Tests**: 26 个测试 (全部通过 XCTSkip 跳过)

## 验收标准覆盖

| AC | 描述 | 优先级 | 测试覆盖 | 测试方法 |
|----|------|--------|---------|---------|
| AC1 | SDK Agent Loop 编排 | P0 | 6 tests | `test_runCommand_createsSDKAgent`, `test_runCommand_agentOptions_containsApiKey`, `test_runCommand_agentOptions_containsModel`, `test_runCommand_agentOptions_containsSystemPrompt`, `test_runCommand_agentOptions_maxTurns_fromConfig`, `test_runCommand_agentOptions_permissionMode_autoAccept` |
| AC2 | SDK MCP Client 连接 | P0 | 3 tests | `test_runCommand_configuresHelperAsMCPServer`, `test_runCommand_mcpConfig_usesHelperPathResolver`, `test_runCommand_mcpServers_autoDiscovery` |
| AC3 | SDK 工具注册 | P0 | 1 test | `test_runCommand_toolsRegisteredViaMCPAutoDiscovery` |
| AC4 | SDK Hooks 安全检查 | P0 | 4 tests | `test_safetyChecker_registeredAsPreToolUseHook`, `test_preToolUseHook_blocksForegroundOpsInSharedSeatMode`, `test_preToolUseHook_allowsAllOpsWhenForegroundAllowed`, `test_hookRegistry_passedToAgentOptions` |
| AC5 | SDK Streaming 进度输出 | P0 | 6 tests | `test_streamMessage_assistant_forwardedToOutput`, `test_streamMessage_toolUse_forwardedToOutput`, `test_streamMessage_toolResult_forwardedToOutput`, `test_streamMessage_result_finalResult`, `test_streamMessage_partialMessage_streamingText`, `test_streamMessages_recordedToTrace` |
| AC6 | 完整端到端流程 | P0 | 3 tests | `test_runCommand_usesSDKAgentInsteadOfDirectHelperManager`, `test_runCommand_dryrunMode_skipsToolExecution`, `test_runCommand_cancel_propagatesToAgentInterrupt` |
| -- | 配置加载 | P1 | 3 tests | `test_runCommand_loadsConfigFromConfigManager`, `test_runCommand_apiKeyFromKeychainOrEnv`, `test_runCommand_cliArgsOverrideConfig` |
| -- | 反模式验证 | P1 | 2 tests | `test_runCommand_doesNotBypassSDKAgent`, `test_runCommand_doesNotImportAxionHelper` |

## 测试文件

| 文件 | 测试数 | 状态 |
|------|--------|------|
| `Tests/AxionCLITests/Commands/SDKIntegrationATDDTests.swift` | 26 | RED (XCTSkip) |

## ATDD 开关控制

测试文件使用 5 个布尔开关控制不同 AC 的激活：

| 开关 | 默认值 | 覆盖 AC | 激活时机 |
|------|--------|---------|---------|
| `SDK_AGENT_INTEGRATED` | `false` | AC1 | createAgent + AgentOptions 构建完成 |
| `SDK_MCP_CONFIGURED` | `false` | AC2 | mcpServers 配置 Helper 连接完成 |
| `SDK_HOOKS_CONFIGURED` | `false` | AC4 | HookRegistry + preToolUse hook 实现完成 |
| `SDK_STREAMING_CONFIGURED` | `false` | AC5 | SDKMessage 消费和输出转发完成 |
| `SDK_E2E_FLOW_CONFIGURED` | `false` | AC6 | 完整端到端流程可用 |

## 实现顺序建议

1. **Task 1 + 2**: 重构 RunCommand 集成 SDK Agent → 激活 `SDK_AGENT_INTEGRATED`
2. **Task 2**: SDK MCP Client 连接 → 激活 `SDK_MCP_CONFIGURED`
3. **Task 3**: SDK Hooks 安全检查 → 激活 `SDK_HOOKS_CONFIGURED`
4. **Task 4**: SDK Streaming 消息消费 → 激活 `SDK_STREAMING_CONFIGURED`
5. **Task 5**: 编排策略确定 + 完整端到端 → 激活 `SDK_E2E_FLOW_CONFIGURED`

## Next Steps (Task-by-Task Activation)

实现每个任务时:

1. 将对应的 ATDD 开关从 `false` 改为 `true`
2. 运行测试: `swift test --filter "AxionCLITests.Commands.SDKIntegrationATDDTests"`
3. 验证激活的测试先失败，实现后通过 (green phase)
4. 如果激活的测试仍然意外失败:
   - 要么修复实现 (功能 bug)
   - 要么修复测试 (测试 bug)
5. 提交通过的测试

## 实现指导

### 需要实现的关键组件:

- `RunCommand.swift` — 替换占位代码，集成 SDK createAgent + stream/prompt
- `SafetyChecker` Hook — 通过 SDK HookRegistry + preToolUse hook 实现
- `SDKMessage` 消费者 — 遍历 AsyncStream<SDKMessage>，转发到 OutputProtocol
- 配置桥接 — ConfigManager/KeychainStore → AgentOptions

### 需要修改的文件:

- `Sources/AxionCLI/Commands/RunCommand.swift` — 替换占位代码
- 可能简化或移除: `HelperProcessManager.swift` (SDK 接管 MCP 连接)
- 可能修改: `RunEngine.swift` (根据编排策略决定)

### 禁止事项:

- 不得绕过 SDK 直接调用 Anthropic API
- 不得在 AxionCore 中 import OpenAgentSDK
- RunCommand 不得 import AxionHelper
- 不得使用 print() 输出
- 不得硬编码 prompt 文本
- API Key 不得出现在日志或 trace 中

## 依赖的 SDK 类型

| SDK 类型 | 用途 | 测试引用 |
|----------|------|---------|
| `createAgent()` | Agent 工厂 | AC1 |
| `AgentOptions` | Agent 配置 | AC1, AC2 |
| `Agent.stream()` / `Agent.prompt()` | 执行方法 | AC1, AC6 |
| `McpServerConfig.stdio()` | MCP stdio 配置 | AC2 |
| `McpStdioConfig` | Helper 进程配置 | AC2 |
| `HookRegistry` | Hook 注册器 | AC4 |
| `HookDefinition` | Hook 定义 | AC4 |
| `HookOutput` / `HookDecision` | Hook 返回 | AC4 |
| `SDKMessage` | 流式消息类型 | AC5 |
| `PermissionMode.autoAccept` | 权限模式 | AC1 |
