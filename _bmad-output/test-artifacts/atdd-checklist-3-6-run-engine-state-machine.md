---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-05-10'
storyId: '3.6'
storyKey: '3-6-run-engine-state-machine'
storyFile: '_bmad-output/implementation-artifacts/stories/3-6-run-engine-state-machine.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-3-6-run-engine-state-machine.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/Engine/RunEngineTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/stories/3-6-run-engine-state-machine.md'
  - '_bmad-output/project-context.md'
  - 'Sources/AxionCore/Models/RunState.swift'
  - 'Sources/AxionCore/Models/RunContext.swift'
  - 'Sources/AxionCore/Models/Plan.swift'
  - 'Sources/AxionCore/Models/ExecutedStep.swift'
  - 'Sources/AxionCore/Models/VerificationResult.swift'
  - 'Sources/AxionCore/Models/AxionConfig.swift'
  - 'Sources/AxionCore/Protocols/PlannerProtocol.swift'
  - 'Sources/AxionCore/Protocols/ExecutorProtocol.swift'
  - 'Sources/AxionCore/Protocols/VerifierProtocol.swift'
  - 'Sources/AxionCore/Protocols/OutputProtocol.swift'
  - 'Sources/AxionCore/Errors/AxionError.swift'
  - 'Sources/AxionCLI/Executor/StepExecutor.swift'
  - 'Sources/AxionCLI/Trace/TraceRecorder.swift'
---

# ATDD Checklist: Story 3.6 - Run Engine 执行循环状态机

## TDD Red Phase (Current)

Red-phase test scaffolds generated.

- Unit Tests: 23 tests (covering all 12 ACs)
- Test file: `Tests/AxionCLITests/Engine/RunEngineTests.swift`
- Execution mode: sequential (backend Swift/XCTest)
- Detected stack: backend

## Acceptance Criteria Coverage

| AC | 描述 | 测试 | 优先级 |
|----|------|------|--------|
| AC1 | 状态机启动: planning -> executing -> verifying | `test_runEngine_happyPath_planExecuteVerifyDone` | P0 |
| AC2 | 任务完成终态 (.done) | `test_runEngine_doneState_displaysSummary` | P0 |
| AC3 | 重规划循环 (blocked -> replanning) | `test_runEngine_blockedTriggersReplan` | P0 |
| AC4 | 重规划后继续执行 | `test_runEngine_replanSuccess_returnsToExecuting` | P0 |
| AC5 | 最大重规划次数 | `test_runEngine_maxReplanRetriesExceeded_entersFailed` | P0 |
| AC6 | Ctrl-C 中断 | `test_runEngine_cancelPropagation_entersCancelled` | P1 |
| AC7 | 步数和批次限制 | `test_runEngine_maxBatchesExceeded_entersFailed`, `test_runEngine_maxStepsExceeded_stopsExecution` | P0 |
| AC8 | 干跑模式 | `test_runEngine_dryrunMode_plansOnlyNoExecute` | P0 |
| AC9 | 前台模式 | `test_runEngine_allowForeground_executesForegroundOps` | P1 |
| AC10 | needsClarification 处理 | `test_runEngine_needsClarification_entersTerminalState` | P1 |
| AC11 | 不可恢复错误 | `test_runEngine_irrecoverableError_entersFailed` | P0 |
| AC12 | 步骤执行失败触发重规划 | `test_runEngine_stepFailure_skipsVerifyAndReplans` | P0 |

## Test Strategy

### Test Levels

- **Unit**: All 23 tests are unit-level, using protocol mocks for PlannerProtocol, ExecutorProtocol, VerifierProtocol, OutputProtocol
- **No Integration/E2E**: RunEngine is tested in isolation through protocol injection

### Priority Distribution

- **P0 (必须通过)**: 16 tests - Happy path, replanning, limits, error handling, dryrun
- **P1 (重要)**: 7 tests - Cancellation, foreground mode, needsClarification, output/trace calls

### Mock Strategy

All RunEngine dependencies are mocked via protocols:
- `MockPlanner` - PlannerProtocol (createPlan + replan)
- `MockExecutor` - ExecutorProtocol (executePlan)
- `MockVerifier` - VerifierProtocol (verify)
- `MockOutput` - OutputProtocol (all 8 methods)

Note: TraceRecorder is an actor; tests use a no-op trace recorder to avoid file I/O.

## Next Steps (Task-by-Task Activation)

During implementation of each task:

1. Remove `XCTSkip` from the current test method
2. Run tests: `swift test --filter "AxionCLITests.Engine"`
3. Verify the activated test fails first (red), then passes after implementation (green)
4. Commit passing tests

## Implementation Guidance

### Feature Endpoints to Implement

- `Sources/AxionCLI/Engine/RunEngine.swift` - State machine core
- `Sources/AxionCLI/Engine/RunEngineOptions.swift` - Run options struct
- `Sources/AxionCLI/Commands/RunCommand.swift` - Integration (modify existing)

### Key Design Decisions

1. RunEngine is a plain struct (not Actor) - state only mutated within single async call
2. State machine is implicit (structured while loop, not explicit enum variable)
3. maxSteps is cumulative across all batches; maxBatches is per-batch limit
4. Step failure skips verification, goes directly to replanning
5. First planning uses createPlan(), subsequent uses replan() with failure context

### ATDD Artifacts

- Checklist: `_bmad-output/test-artifacts/atdd-checklist-3-6-run-engine-state-machine.md`
- Tests: `Tests/AxionCLITests/Engine/RunEngineTests.swift`
