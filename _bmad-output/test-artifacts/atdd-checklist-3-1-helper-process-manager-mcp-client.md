---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-05-09'
storyId: '3.1'
storyKey: '3-1-helper-process-manager-mcp-client'
storyFile: '_bmad-output/implementation-artifacts/3-1-helper-process-manager-mcp-client.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-3-1-helper-process-manager-mcp-client.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/Helper/HelperProcessManagerTests.swift'
  - 'Tests/AxionCLITests/Commands/RunCommandATDDTests.swift'
---

# ATDD Checklist: Story 3.1 — Helper 进程管理器与 MCP 客户端连接

## TDD Red Phase（当前阶段）

**所有测试已使用 XCTSkip() 标记为红色阶段脚手架。**

- 单元测试: 22 个测试（HelperProcessManagerTests）
- 单元测试: 4 个测试（RunCommandATDDTests）
- 总计: 26 个红色阶段测试

## Acceptance Criteria 覆盖

| AC | 描述 | 测试覆盖 | 优先级 |
|----|------|---------|--------|
| AC1 | 启动 Helper 并建立 MCP 连接 | test_start_connectsMCPClient_isRunningTrue, test_start_throwsWhenHelperPathNotFound, test_start_throwsHelperConnectionFailed_onMCPError, test_start_connectsMCPClient_isRunningTrue, test_runCommand_startsHelperProcessManager | P0 |
| AC2 | MCP 连接就绪确认 | test_listTools_returnsToolNames, test_helperProcessManager_isRunningMethodExists | P0 |
| AC3 | 正常退出清理 | test_stop_closesMCPClientAndTransport, test_stop_whenNotStarted_isNoOp, test_stop_gracefulShutdown_closesConnectionFirst, test_runCommand_stopsHelperOnExit | P0 |
| AC4 | 强制终止回退 | test_stop_forceKillAfterTimeout | P1 |
| AC5 | Ctrl-C 信号传播 | test_setupSignalHandling_registersSIGINTHandler, test_ctrlC_triggersStopAndCleanup | P1 |
| AC6 | Helper 崩溃检测与重启 | test_crashMonitor_restartsOnce, test_crashMonitor_doesNotRestartTwice | P1 |

## Test Strategy

### Stack: Backend (Swift/XCTest)

本 Story 为纯后端 Swift 项目，使用 XCTest 框架。

### Test Levels

- **Unit Tests** (26 tests): HelperProcessManager actor 的状态管理、Value 转换、MCP 交互逻辑
- **Integration Tests** (not included here): 真实 Helper 进程启动，属于 `Tests/**/Integration/` 目录

### Mock Strategy

| 组件 | Mock 方式 | 说明 |
|------|----------|------|
| MCPStdioTransport | HelperTransportProtocol | 抽象 transport 的 connect/disconnect/isRunning |
| MCPClient | MockMCPClient（手动 mock） | 模拟 listTools/callTool 响应 |
| HelperPathResolver | 环境变量控制 | 通过 AXION_HELPER_PATH 覆盖路径解析 |
| Process | MockTransport 中不创建真实进程 | 单元测试不启动真实 Helper |

### Priority Matrix

| Priority | Tests | Description |
|----------|-------|-------------|
| P0 | 12 tests | 类型存在性、启动/停止核心路径、错误处理 |
| P1 | 14 tests | Value 转换、崩溃重启、信号处理、ToolResult 提取 |

## 生成的测试文件

### 1. Tests/AxionCLITests/Helper/HelperProcessManagerTests.swift

- 22 个测试方法
- 覆盖 AC1–AC6
- 按 MARK 分组：类型存在性、启动连接、优雅关闭、强制终止、信号处理、崩溃重启、Value 转换、ToolResult 提取

### 2. Tests/AxionCLITests/Commands/RunCommandATDDTests.swift

- 4 个测试方法
- 覆盖 RunCommand 集成（Task 2）
- AsyncParsableCommand 一致性、start/stop 集成、错误处理

## Red-Green-Refactor 工作流

### RED Phase（当前 — 由 TEA 完成）

1. 所有 26 个测试已生成为红色阶段脚手架（XCTSkip）
2. 测试断言了预期行为（非占位断言）
3. 实现前所有测试被跳过

### GREEN Phase（由 DEV 团队执行）

实现每个 Task 时：

1. 打开 `HelperProcessManagerTests.swift`
2. 找到对应当前 Task 的测试方法
3. 移除 `try skipUntilImplemented()` 行
4. 运行 `swift test --filter "HelperProcessManagerTests"`
5. 确认测试失败（RED）
6. 实现功能代码
7. 确认测试通过（GREEN）
8. 提交通过的测试

### Task-to-Test 映射

| Task | 测试方法 | 验证点 |
|------|---------|--------|
| 1.1-1.2 | test_helperProcessManager_typeExists | actor 类型存在 |
| 1.3 | test_start_throwsWhenHelperPathNotFound, test_start_connectsMCPClient_isRunningTrue, test_start_throwsHelperConnectionFailed_onMCPError | start() 核心逻辑 |
| 1.4 | test_stop_closesMCPClientAndTransport, test_stop_whenNotStarted_isNoOp, test_stop_gracefulShutdown_closesConnectionFirst, test_stop_forceKillAfterTimeout | stop() 核心逻辑 |
| 1.5 | test_helperProcessManager_isRunningMethodExists | isRunning() |
| 1.6 | test_callTool_convertsStringValue, test_callTool_convertsIntValue, test_callTool_convertsBoolValue, test_callTool_convertsPlaceholderAsString, test_callTool_extractsTextFromResult, test_callTool_joinsMultipleContentBlocks, test_callTool_handlesErrorResult, test_callTool_whenNotStarted_throwsError | callTool + Value 转换 |
| 1.7 | test_listTools_returnsToolNames, test_listTools_whenNotStarted_throwsError | listTools() |
| 1.8 | test_crashMonitor_restartsOnce, test_crashMonitor_doesNotRestartTwice | 崩溃监控 |
| 1.9 | test_setupSignalHandling_registersSIGINTHandler | 信号处理 |
| 2.1-2.3 | test_runCommand_startsHelperProcessManager, test_runCommand_stopsHelperOnExit, test_runCommand_handlesHelperStartFailure, test_runCommand_conformsToAsyncParsableCommand | RunCommand 集成 |

### REFACTOR Phase

GREEN 通过后：

1. 检查代码重复
2. 确认 import 顺序正确（Foundation → MCP → OpenAgentSDK → AxionCore）
3. 确认不违反项目反模式
4. 运行全量单元测试确认无回归

## Execution Commands

```bash
# 运行 HelperProcessManager 测试
swift test --filter "AxionCLITests.Helper.HelperProcessManagerTests"

# 运行 RunCommand ATDD 测试
swift test --filter "AxionCLITests.Commands.RunCommandATDDTests"

# 运行全部 AxionCLI 单元测试
swift test --filter "AxionCLITests"
```

## 注意事项与风险

1. **MCPStdioTransport Mock 挑战**: SDK 的 MCPStdioTransport 是 concrete actor，需要创建 HelperTransportProtocol 抽象层才能在单元测试中 mock
2. **Actor 隔离测试**: HelperProcessManager 是 actor，测试中调用其方法需要 `await`，注意 Task 取消传播
3. **信号处理测试**: SIGINT 测试在单元测试中难以完全验证，关键逻辑需在集成测试中补充
4. **并发安全**: stop() 和 start() 的并发调用场景需要仔细测试

## Next Steps

1. 实现 Story 3-1（dev-story workflow）
2. 按 Task 顺序移除 XCTSkip，实现功能
3. 全部 GREEN 后运行 Code Review
4. 完成 Trace Test Coverage（traceability workflow）
