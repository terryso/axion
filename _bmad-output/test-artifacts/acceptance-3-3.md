# Story 3-3 手工验收文档: 步骤执行与占位符解析

日期: 2026-05-10
验收人: nick

## 验收范围

### 新增文件
| 文件 | 职责 |
|------|------|
| `Sources/AxionCLI/Executor/PlaceholderResolver.swift` | $pid/$window_id 占位符解析 + absorbResult |
| `Sources/AxionCLI/Executor/SafetyChecker.swift` | 共享座椅安全策略 |
| `Sources/AxionCLI/Executor/StepExecutor.swift` | 步骤执行主逻辑 |
| `Tests/AxionCLITests/Executor/PlaceholderResolverTests.swift` | PlaceholderResolver 单元测试 |
| `Tests/AxionCLITests/Executor/SafetyCheckerTests.swift` | SafetyChecker 单元测试 |
| `Tests/AxionCLITests/Executor/StepExecutorTests.swift` | StepExecutor 单元测试 |

### 修改文件
| 文件 | 变更说明 |
|------|---------|
| `Sources/AxionCLI/Helper/HelperProcessManager.swift` | 添加 SIGPIPE 信号忽略，防止 Helper 异常退出时进程崩溃 |
| `Sources/AxionCLI/Planner/LLMPlanner.swift` | 注入 retryDelay 参数提升可测试性 |
| `Sources/AxionCore/Protocols/ExecutorProtocol.swift` | access level 改为 public |
| `Tests/AxionCLITests/Planner/LLMPlannerTests.swift` | 适配 retryDelay 注入 |
| `_bmad-output/implementation-artifacts/sprint-status.yaml` | 更新 Story 3-3 状态为 done |

## 验收项

### V1: 编译检查
- [ ] `swift build` 无错误无警告

### V2: 单元测试通过
- [ ] 所有 AxionCLITests 通过 (含 Executor 目录新测试)
- [ ] 所有 AxionCoreTests 通过 (无回归)
- [ ] 所有 AxionHelperTests 通过 (无回归)

### V3: AC1 — MCP 工具调用执行步骤
- [ ] `StepExecutorTests.test_executeStep_launchApp_callsMCPAndReturnsSuccess` 通过
- [ ] StepExecutor 通过 MCPClientProtocol 调用 MCP 工具
- [ ] 返回 ExecutedStep(success: true)

### V4: AC2 — $pid 占位符解析
- [ ] `PlaceholderResolverTests.test_resolve_pidPlaceholder_replacesWithPid` 通过
- [ ] `.placeholder("$pid")` 替换为 context 中的 pid 值
- [ ] pid 未设置时保留原始占位符

### V5: AC3 — $window_id 占位符解析
- [ ] `PlaceholderResolverTests.test_resolve_windowIdPlaceholder_replacesWithWindowId` 通过
- [ ] `.placeholder("$window_id")` 替换为 context 中的 windowId 值

### V6: AC4 — AX 定位前自动刷新窗口状态
- [ ] `StepExecutorTests.test_executePlan_axOperation_refreshesWindowStateFirst` 通过
- [ ] click/type_text 等 AX 操作前自动调用 get_window_state
- [ ] refresh 发生在 click 之前 (callHistory 顺序验证)

### V7: AC5 — 步骤执行失败处理
- [ ] `StepExecutorTests.test_executeStep_mcpError_returnsFailedExecutedStep` 通过
- [ ] `StepExecutorTests.test_executePlan_stopsOnFirstFailure` 通过
- [ ] 失败后停止后续步骤执行

### V8: AC6 — 共享座椅安全检查阻止前台操作
- [ ] `SafetyCheckerTests.test_check_sharedSeatMode_true_blocksAllForegroundTools` 通过
- [ ] `StepExecutorTests.test_executeStep_safetyBlocked_returnsSafetyError` 通过
- [ ] click/type_text 等 8 个前台工具在 sharedSeatMode=true 时被阻止
- [ ] MCP 不被调用

### V9: AC7 — --allow-foreground 模式放行
- [ ] `SafetyCheckerTests.test_check_sharedSeatMode_false_allowsAllTools` 通过
- [ ] `StepExecutorTests.test_executeStep_allowForeground_executesClick` 通过
- [ ] sharedSeatMode=false 时前台工具正常执行

### V10: absorbResult 上下文提取
- [ ] launch_app 返回 JSON 中提取 pid
- [ ] list_windows 返回 JSON 中提取 window_id 和 pid
- [ ] get_window_state 返回 JSON 中提取 window_id 和 pid
- [ ] 非上下文产出工具不改变 context
- [ ] 无效 JSON 不崩溃、不覆盖已有值

### V11: 无回归
- [ ] LLMPlanner 测试全部通过 (retryDelay 注入无破坏)
- [ ] 其他模块测试全部通过

## 验收结果

| 项目 | 状态 | 备注 |
|------|------|------|
| V1 编译检查 | PASS | swift build 无错误无警告 (5.72s) |
| V2 单元测试 | PASS | 358 tests, 0 failures |
| V3 AC1 MCP调用 | PASS | 12 StepExecutor tests passed; MCP 链路验证 launch_app 返回真实 pid |
| V4 AC2 $pid解析 | PASS | 17 PlaceholderResolver tests passed |
| V5 AC3 $window_id解析 | PASS | 含多占位符混合测试; MCP 链路验证 list_windows 返回真实 window_id |
| V6 AC4 AX刷新 | PASS | get_window_state 使用 window_id 参数(非 pid)调用; MCP 链路验证返回 elements |
| V7 AC5 失败处理 | PASS | MCP 链路验证不存在的应用返回 app_not_found 错误 |
| V8 AC6 安全阻止 | PASS | 33 SafetyChecker tests passed，8个前台工具全部阻止 |
| V9 AC7 放行 | PASS | sharedSeatMode=false 时前台工具正常执行 |
| V10 absorbResult | PASS | launch_app/list_windows/get_window_state 提取正常 |
| V11 无回归 | PASS | LLMPlanner/AxionCore/AxionHelper 测试全部通过 |

### 手工验收（真实 MCP 调用）
- launch_app("Calculator") -> pid=64599, app=计算器
- list_windows(pid=64599) -> window_id=30534, 5 windows
- get_window_state(window_id=30534) -> elements 验证通过
- launch_app("NonExistentAppXYZ999") -> app_not_found 错误正确返回
- quit_app(pid=64599) -> 清理成功

### 验收过程中发现的 Bug 修复
- **Bug:** `StepExecutor.refreshWindowState` 使用 `pid` 参数调用 `get_window_state`，但 Helper 的 `get_window_state` 工具要求 `window_id` 参数
- **修复:** 改为从 `ExecutionContext.windowId` 获取 `window_id` 传参；无 `windowId` 时跳过刷新（不报错）
- **影响:** 更新了两个测试用例的 Plan 结构，在 `launch_app` 和 AX 操作之间加入 `list_windows` 步骤以产生 `windowId`

**最终结论:** 通过
