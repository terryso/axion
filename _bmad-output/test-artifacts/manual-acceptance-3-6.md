# Manual Acceptance: Story 3-6 Run Engine 执行循环状态机

Date: 2026-05-10
Story: 3-6-run-engine-state-machine
Status: 待验收

## 变更范围

### 新建文件
- `Sources/AxionCLI/Engine/RunEngine.swift` — 状态机核心 + RunEngineOptions
- `Tests/AxionCLITests/Engine/RunEngineTests.swift` — 23 个单元测试

### 修改文件
- `Sources/AxionCore/Errors/AxionError.swift` — 新增 stepBudgetExceeded/batchBudgetExceeded
- `Sources/AxionCore/Protocols/ExecutorProtocol.swift` — 新增 executePlan 方法
- `Sources/AxionCLI/Trace/TraceRecorder.swift` — 新增 recordReplan 方法
- `Tests/AxionCoreTests/AxionErrorTests.swift` — 新增错误类型测试
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — 状态更新

### 新建文档
- `_bmad-output/implementation-artifacts/stories/3-6-run-engine-state-machine.md`
- `_bmad-output/test-artifacts/atdd-checklist-3-6-run-engine-state-machine.md`

---

## 验收步骤

### Step 1: 编译验证

```bash
swift build
```

预期: 编译成功，0 errors。

---

### Step 2: 运行 Story 3-6 单元测试

```bash
swift test --filter "AxionCLITests.Engine"
```

预期: 23 个测试全部通过，0 failures。

覆盖 AC 列表:
| AC | 描述 | 测试 |
|----|------|------|
| AC1 | 状态机启动 | test_runEngine_happyPath_planExecuteVerifyDone |
| AC2 | 任务完成终态 | test_runEngine_doneState_displaysSummary |
| AC3 | 重规划循环 | test_runEngine_blockedTriggersReplan |
| AC4 | 重规划后继续 | test_runEngine_replanSuccess_returnsToExecuting |
| AC5 | 最大重规划次数 | test_runEngine_maxReplanRetriesExceeded_entersFailed |
| AC6 | Ctrl-C 中断 | test_runEngine_cancelPropagation_entersCancelled |
| AC7 | 步数和批次限制 | test_runEngine_maxBatchesExceeded_entersFailed, test_runEngine_maxStepsExceeded_stopsExecution |
| AC8 | 干跑模式 | test_runEngine_dryrunMode_plansOnlyNoExecute |
| AC9 | 前台模式 | test_runEngine_allowForeground_executesForegroundOps |
| AC10 | needsClarification | test_runEngine_needsClarification_entersTerminalState |
| AC11 | 不可恢复错误 | test_runEngine_irrecoverableError_entersFailed |
| AC12 | 步骤失败重规划 | test_runEngine_stepFailure_skipsVerifyAndReplans, test_runEngine_stepFailureReplanExhausted_entersFailed |

---

### Step 3: 运行全量单元测试（无回归）

```bash
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"
```

预期: 所有单元测试通过，0 failures。

---

### Step 4: 运行集成测试

```bash
swift test --filter "AxionCLITests.Integration"
```

预期: 所有集成测试通过。包含:
- `Tests/AxionCLITests/Integration/Output/OutputTraceIntegrationTests.swift`
- `Tests/AxionCLITests/Integration/Verifier/VerifierIntegrationTests.swift`

---

### Step 5: 代码审查检查项

- [ ] RunEngine 是 struct，不是 Actor
- [ ] 使用 Protocol 注入（PlannerProtocol, ExecutorProtocol, VerifierProtocol, OutputProtocol）
- [ ] 没有使用 print()，所有输出通过 OutputProtocol
- [ ] 没有新增错误类型，使用 AxionError
- [ ] RunId 格式 YYYYMMDD-{6random}
- [ ] maxSteps 是累计限制（跨所有批次）
- [ ] 步骤失败跳过验证，直接重规划
- [ ] 干跑模式不执行、不验证
- [ ] import 顺序: Foundation, AxionCore

---

## 验收结果

- [ ] Step 1 编译: PASS / FAIL
- [ ] Step 2 单元测试: PASS / FAIL
- [ ] Step 3 回归测试: PASS / FAIL
- [ ] Step 4 集成测试: PASS / FAIL
- [ ] Step 5 代码审查: PASS / FAIL

结论: PASS / FAIL
