# Story 3-5 Manual Acceptance Report

**Story**: 3-5 输出、Trace 与进度显示
**Date**: 2026-05-10
**Status**: PASS

---

## Test Execution Summary

| Suite | Tests | Passed | Failed | Command |
|-------|-------|--------|--------|---------|
| Unit Tests | 460 | 460 | 0 | `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` |
| CLI Integration Tests | 3 | 3 | 0 | `AXION_HELPER_PATH="$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter "AxionCLIIntegrationTests"` |
| Helper Integration Tests | 103 | 103 | 0 | `AXION_HELPER_PATH="$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter "AxionHelperIntegrationTests"` |
| **Total** | **566** | **566** | **0** | |

---

## Acceptance Criteria Verification

### AC1: 运行启动信息显示

**Given** 任务开始执行
**When** TerminalOutput 显示
**Then** 输出运行 ID 和模式信息

**Verification Method**: Unit test + code review

**Evidence**:
- `TerminalOutput.displayRunStart()` (line 26-29) outputs:
  - `[axion] 模式: {mode}`
  - `[axion] 运行 ID: {runId}`
  - `[axion] 任务: {task}`
- Unit test `test_terminalOutput_displayRunStart_showsRunIdAndTask` validates runId and task appear in output
- Unit test `test_terminalOutput_displayRunStart_allThreeLines` validates 3+ lines output with mode info
- All outputs carry `[axion]` prefix (verified by `test_terminalOutput_allOutputs_haveAxionPrefix`)

**Result**: PASS

---

### AC2: 步骤执行进度显示

**Given** 步骤开始执行
**When** TerminalOutput 更新
**Then** 显示步骤编号、工具名和目的

**Verification Method**: Unit test + code review

**Evidence**:
- `TerminalOutput.displayPlan()` (line 56-59) sets `planStepsCount` and outputs `[axion] 规划完成: N 个步骤`
- `TerminalOutput.displayStepResult()` (line 61-73) outputs `[axion] 步骤 {current}/{total}: {tool} — {status}`
- Step index is 1-based display (`stepIndex + 1`)
- Total comes from `planStepsCount` set by `displayPlan`
- Unit test `test_terminalOutput_displayPlan_showsStepCount` validates step count
- Unit test `test_terminalOutput_displayStepResult_showsStepIndex` validates `2/3` format
- `StepExecutor.onStepStart` callback (line 22) enables trace integration for step start

**Result**: PASS

---

### AC3: 步骤结果反馈

**Given** 步骤执行完成
**When** TerminalOutput 更新
**Then** 显示步骤结果（ok 成功 或 x 失败及原因）

**Verification Method**: Unit test + code review

**Evidence**:
- `TerminalOutput.displayStepResult()` (line 61-73):
  - Success: shows `ok` status marker
  - Failure: shows `x {truncated_result}` (80 char snippet)
- Unit test `test_terminalOutput_displayStepResult_success_showsOk` validates `ok` marker
- Unit test `test_terminalOutput_displayStepResult_failure_showsError` validates failure indicator
- `StepExecutor.onStepDone` callback fires after both success and failure steps

**Result**: PASS

---

### AC4: 任务完成汇总

**Given** 任务全部完成
**When** TerminalOutput 显示汇总
**Then** 显示总步数、耗时、重规划次数

**Verification Method**: Unit test + code review

**Evidence**:
- `TerminalOutput.displaySummary()` (line 85-100) outputs:
  - `[axion] 完成。{N} 步，耗时 {T} 秒，重规划 {R} 次。`
- Duration calculated from first/last step timestamps
- Unit test `test_terminalOutput_displaySummary_showsStepCountAndDuration` validates step count
- Unit test `test_terminalOutput_displaySummary_showsReplanCount` validates replan count display
- `displayReplan()` (line 32-34) outputs `[axion] 正在重规划 (attempt/maxRetries): reason`

**Result**: PASS

---

### AC5: JSON 结构化输出

**Given** `--json` 标志启用
**When** JSONOutput 输出
**Then** 以结构化 JSON 格式输出完整的执行结果

**Verification Method**: Unit test + code review

**Evidence**:
- `JSONOutput` (class) accumulates data via OutputProtocol methods, outputs via `finalize()`
- `finalize()` produces pretty-printed JSON with: runId, task, mode, state, steps, stateTransitions, errors, verificationResults, replanInfo, summary
- Unit test `test_jsonOutput_finalize_producesValidJSON` validates valid JSON
- Unit test `test_jsonOutput_finalize_containsRunId` validates runId field
- Unit test `test_jsonOutput_finalize_containsTask` validates task field
- Unit test `test_jsonOutput_finalize_containsSteps` validates steps array
- Unit test `test_jsonOutput_finalize_containsSummary` validates summary object
- Unit test `test_jsonOutput_stepsArray_reflectsExecutedSteps` validates 2 steps
- Unit test `test_jsonOutput_summary_computesTotalSteps` validates totalSteps=1
- Unit test `test_jsonOutput_summary_computesSuccessfulSteps` validates successfulSteps=1
- Unit test `test_jsonOutput_summary_computesFailedSteps` validates failedSteps=1

**Result**: PASS

---

### AC6: Trace 事件记录

**Given** 任务运行中
**When** TraceRecorder 记录
**Then** 向 `~/.axion/runs/{runId}/trace.jsonl` 追加 JSONL 事件

**Verification Method**: Unit test + code review

**Evidence**:
- `TraceRecorder` (actor) writes to `{baseURL}/{runId}/trace.jsonl`
- Auto-creates directory via `FileManager.createDirectory(withIntermediateDirectories:)` (line 59-62)
- Actor isolation ensures serialized file writes
- 8 convenience methods: `recordRunStart`, `recordPlanCreated`, `recordStepStart`, `recordStepDone`, `recordStateChange`, `recordVerificationResult`, `recordRunDone`, `recordError`
- Unit test `test_traceRecorder_createsDirectoryAndFile` validates file creation
- Unit test `test_traceRecorder_multipleRecords_allWritten` validates 4 events written
- Unit test `test_traceRecorder_disabled_doesNotWrite` validates traceEnabled=false behavior
- Unit test `test_traceRecorder_close_flushesData` validates close persistence
- All 8 convenience method tests pass (recordRunStart, recordPlanCreated, recordStepStart, recordStepDone, recordStateChange, recordVerificationResult, recordRunDone, recordError)
- API key sanitization: `test_traceRecorder_apiKeyNotInPayload` validates sensitive data removal

**Result**: PASS

---

### AC7: Trace 文件格式

**Given** trace 文件存在
**When** 用 jq 或 cat 查看
**Then** 每行是一个独立 JSON 对象，包含 `ts`（ISO8601）和 `event`（snake_case）字段

**Verification Method**: Unit test + code review

**Evidence**:
- Each record: `{"ts":"ISO8601","event":"snake_case",...payload}` + `\n`
- `ts` auto-added via `ISO8601DateFormatter` with `.withInternetDateTime, .withFractionalSeconds`
- `event` auto-added with snake_case name
- Unit test `test_traceRecorder_eventsHaveTimestampAndEventField` validates ts and event fields
- Unit test `test_traceRecorder_timestampIsISO8601` validates ISO8601 format parseability
- Unit test `test_traceRecorder_eventNameIsSnakeCase` validates all 8 event names match `^[a-z][a-z0-9_]*$`
- Unit test `test_traceRecorder_eachLineIsIndependentJSON` validates 4 independent JSON objects

**Result**: PASS

---

## Integration Test Details

### CLI Integration Tests (VerifierIntegrationTests)

These tests launch the real AxionHelper.app, start Calculator via MCP, and verify:

1. **test_real_captureScreenshotAndAxTree** (3.9s):
   - Launches real Calculator
   - Captures real screenshot (16,559 bytes) and AX tree (49,529 chars)
   - Evaluates stop conditions: textAppears= Calculator title, windowAppears=wrong name, custom=uncertain

2. **test_real_taskVerifier_withRealMCP** (3.5s):
   - Full TaskVerifier flow with real MCP context capture
   - Real screenshot + AX tree captured
   - Verifier returns `.done` with "All stop conditions satisfied"
   - This test validates the `onVerificationResult` callback added in Story 3-5

3. **test_real_stopConditionEvaluator_withRealAxTree** (2.3s):
   - StopConditionEvaluator against real Calculator AX tree
   - textAppears with dynamic title = satisfied
   - windowAppears with wrong name = notSatisfied

All 3 tests passed with real macOS app interaction.

---

## Non-Functional Requirements

### NFR15: 实时进度更新
- TerminalOutput uses injectable `write` closure (defaults to `print`)
- Each method call immediately outputs — no buffering

### NFR20: Trace 文件可调试
- JSONL format (one JSON per line) is grep/jq friendly
- ISO8601 timestamps for chronological ordering
- API key sanitization prevents sensitive data leakage

### Cross-cutting Concerns
- No emoji in output (verified by `test_terminalOutput_noEmojiInOutput`)
- All outputs use `[axion]` prefix (verified by `test_terminalOutput_allOutputs_haveAxionPrefix`)
- TerminalOutput is testable via `write` closure injection
- JSONOutput produces machine-parseable output
- TraceRecorder uses Actor for thread safety
- OutputProtocol changes are backward compatible (5 existing methods unchanged)

---

## Package.swift Changes

Added `AxionCLIIntegrationTests` test target:
```swift
.testTarget(
    name: "AxionCLIIntegrationTests",
    dependencies: [
        "AxionCLI",
        "AxionCore",
        .product(name: "MCP", package: "swift-mcp"),
    ],
    path: "Tests/AxionCLITests/Integration"
)
```

This enables running CLI integration tests with:
```bash
AXION_HELPER_PATH="$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter "AxionCLIIntegrationTests"
```

---

## Verdict

**All 7 Acceptance Criteria: PASS**
**All 566 tests (460 unit + 3 CLI integration + 103 Helper integration): PASS**
**Story 3-5 is ready for commit.**
