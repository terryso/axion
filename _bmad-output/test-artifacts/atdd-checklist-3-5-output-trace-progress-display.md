---
stepsCompleted: ['step-01-preflight-and-context', 'step-02-generation-mode', 'step-03-test-strategy', 'step-04-generate-tests', 'step-05-validate-and-complete']
lastStep: 'step-05-validate-and-complete'
lastSaved: '2026-05-10'
storyId: '3.5'
storyKey: '3-5-output-trace-progress-display'
storyFile: '_bmad-output/implementation-artifacts/stories/3-5-output-trace-progress-display.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-3-5-output-trace-progress-display.md'
generatedTestFiles:
  - 'Tests/AxionCoreTests/OutputProtocolTests.swift'
  - 'Tests/AxionCLITests/Output/TerminalOutputTests.swift'
  - 'Tests/AxionCLITests/Output/JSONOutputTests.swift'
  - 'Tests/AxionCLITests/Trace/TraceRecorderTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/stories/3-5-output-trace-progress-display.md'
  - '_bmad-output/project-context.md'
  - 'Sources/AxionCore/Protocols/OutputProtocol.swift'
  - 'Sources/AxionCore/Models/RunContext.swift'
  - 'Sources/AxionCore/Models/RunState.swift'
  - 'Sources/AxionCore/Models/ExecutedStep.swift'
  - 'Sources/AxionCore/Models/Plan.swift'
  - 'Sources/AxionCore/Models/Step.swift'
  - 'Sources/AxionCore/Models/StopCondition.swift'
  - 'Sources/AxionCore/Models/VerificationResult.swift'
  - 'Sources/AxionCore/Models/AxionConfig.swift'
  - 'Sources/AxionCore/Errors/AxionError.swift'
---

# ATDD Checklist: Story 3.5 - Output, Trace & Progress Display

## Stack Detection

- **detected_stack**: backend (Swift SPM project, no frontend manifests)
- **test_framework**: XCTest (Swift Package Manager)

## Generation Mode

- **mode**: AI Generation (backend project, no browser recording needed)

## Test Strategy

### Acceptance Criteria to Test Mapping

| AC | Description | Test Level | Priority | Test File |
|----|-------------|-----------|----------|-----------|
| AC1 | Run start info display (run ID, mode, task) | Unit | P0 | TerminalOutputTests.swift |
| AC2 | Step execution progress display | Unit | P0 | TerminalOutputTests.swift |
| AC3 | Step result feedback (ok/x) | Unit | P0 | TerminalOutputTests.swift |
| AC4 | Task completion summary | Unit | P0 | TerminalOutputTests.swift |
| AC5 | JSON structured output | Unit | P0 | JSONOutputTests.swift |
| AC6 | Trace event recording (JSONL file) | Unit | P0 | TraceRecorderTests.swift |
| AC7 | Trace file format (JSON lines with ts + event) | Unit | P0 | TraceRecorderTests.swift |

### Test Scenarios

#### OutputProtocolTests (AxionCore -- protocol extension & conformance)

| # | Test Method | AC | Priority | Description |
|---|-------------|-----|----------|-------------|
| 1 | `test_outputProtocol_hasRequiredMethods` | AC1-7 | P0 | Protocol declares all 8 methods (5 existing + 3 new) |
| 2 | `test_outputProtocol_displayRunStart_signature` | AC1 | P0 | displayRunStart(runId:task:mode:) exists |
| 3 | `test_outputProtocol_displayReplan_signature` | AC4 | P0 | displayReplan(attempt:maxRetries:reason:) exists |
| 4 | `test_outputProtocol_displayVerificationResult_signature` | AC4 | P0 | displayVerificationResult(_:) exists |
| 5 | `test_outputProtocol_existingMethods_unchanged` | AC1-7 | P0 | Original 5 methods still exist with same signatures |

#### TerminalOutputTests (AxionCLI -- write closure injection, no stdout capture)

| # | Test Method | AC | Priority | Description |
|---|-------------|-----|----------|-------------|
| 1 | `test_terminalOutput_typeExists` | AC1 | P0 | TerminalOutput type can be referenced |
| 2 | `test_terminalOutput_conformsToOutputProtocol` | AC1 | P0 | TerminalOutput conforms to OutputProtocol |
| 3 | `test_terminalOutput_displayRunStart_showsRunIdAndTask` | AC1 | P0 | Output contains [axion] prefix, run ID, task, mode |
| 4 | `test_terminalOutput_displayRunStart_allThreeLines` | AC1 | P0 | Three output lines: mode, run ID, task |
| 5 | `test_terminalOutput_displayPlan_showsStepCount` | AC2 | P0 | Output contains step count (e.g. "3 个步骤") |
| 6 | `test_terminalOutput_displayStepResult_success_showsOk` | AC3 | P0 | Successful step shows "ok" status |
| 7 | `test_terminalOutput_displayStepResult_failure_showsError` | AC3 | P0 | Failed step shows "x" + reason |
| 8 | `test_terminalOutput_displayStepResult_showsStepIndex` | AC2 | P0 | Shows step number like "1/3" |
| 9 | `test_terminalOutput_displayStateChange_planning` | AC4 | P1 | Planning state change outputs correct text |
| 10 | `test_terminalOutput_displayStateChange_executing` | AC4 | P1 | Executing state change outputs correct text |
| 11 | `test_terminalOutput_displayError_showsUserFriendlyMessage` | AC3 | P0 | Error output shows message from errorPayload |
| 12 | `test_terminalOutput_displaySummary_showsStepCountAndDuration` | AC4 | P0 | Summary includes total steps and duration |
| 13 | `test_terminalOutput_displaySummary_showsReplanCount` | AC4 | P0 | Summary includes replan count |
| 14 | `test_terminalOutput_displayReplan_showsAttemptInfo` | AC4 | P1 | Replan info shows attempt number and reason |
| 15 | `test_terminalOutput_displayVerificationResult_done` | AC4 | P1 | Verification done shows completion text |
| 16 | `test_terminalOutput_displayVerificationResult_blocked` | AC4 | P1 | Verification blocked shows block reason |
| 17 | `test_terminalOutput_allOutputs_haveAxionPrefix` | AC1-4 | P0 | Every output line starts with "[axion]" |
| 18 | `test_terminalOutput_noEmojiInOutput` | AC1-4 | P1 | No emoji characters in any output |

#### JSONOutputTests (AxionCLI -- JSON structure validation)

| # | Test Method | AC | Priority | Description |
|---|-------------|-----|----------|-------------|
| 1 | `test_jsonOutput_typeExists` | AC5 | P0 | JSONOutput type can be referenced |
| 2 | `test_jsonOutput_conformsToOutputProtocol` | AC5 | P0 | JSONOutput conforms to OutputProtocol |
| 3 | `test_jsonOutput_finalize_producesValidJSON` | AC5 | P0 | finalize() returns valid JSON string |
| 4 | `test_jsonOutput_finalize_containsRunId` | AC5 | P0 | JSON has runId field |
| 5 | `test_jsonOutput_finalize_containsTask` | AC5 | P0 | JSON has task field |
| 6 | `test_jsonOutput_finalize_containsSteps` | AC5 | P0 | JSON has steps array |
| 7 | `test_jsonOutput_finalize_containsSummary` | AC5 | P0 | JSON has summary object |
| 8 | `test_jsonOutput_stepsArray_reflectsExecutedSteps` | AC5 | P0 | Steps array matches displayStepResult calls |
| 9 | `test_jsonOutput_summary_computesTotalSteps` | AC5 | P0 | summary.totalSteps matches step count |
| 10 | `test_jsonOutput_summary_computesSuccessfulSteps` | AC5 | P0 | summary.successfulSteps counts only successes |
| 11 | `test_jsonOutput_summary_computesFailedSteps` | AC5 | P0 | summary.failedSteps counts only failures |
| 12 | `test_jsonOutput_displayRunStart_storesRunInfo` | AC5 | P1 | displayRunStart stores runId, task, mode |
| 13 | `test_jsonOutput_displayError_recordsError` | AC5 | P1 | displayError records error in output |
| 14 | `test_jsonOutput_displayStateChange_recordsTransition` | AC5 | P1 | State transitions are recorded |
| 15 | `test_jsonOutput_displayVerificationResult_recordsResult` | AC5 | P1 | Verification results are recorded |

#### TraceRecorderTests (AxionCLI -- temp directory, JSONL validation)

| # | Test Method | AC | Priority | Description |
|---|-------------|-----|----------|-------------|
| 1 | `test_traceRecorder_typeExists` | AC6 | P0 | TraceRecorder type can be referenced |
| 2 | `test_traceRecorder_isActor` | AC6 | P0 | TraceRecorder is an actor type |
| 3 | `test_traceRecorder_createsDirectoryAndFile` | AC6 | P0 | Init creates ~/.axion/runs/{runId}/trace.jsonl |
| 4 | `test_traceRecorder_eventsHaveTimestampAndEventField` | AC7 | P0 | Each JSONL line has "ts" and "event" fields |
| 5 | `test_traceRecorder_timestampIsISO8601` | AC7 | P0 | ts field is valid ISO8601 format |
| 6 | `test_traceRecorder_eventNameIsSnakeCase` | AC7 | P0 | event field is snake_case |
| 7 | `test_traceRecorder_multipleRecords_allWritten` | AC6 | P0 | Multiple records all appear in file |
| 8 | `test_traceRecorder_disabled_doesNotWrite` | AC6 | P0 | traceEnabled=false produces no file |
| 9 | `test_traceRecorder_close_flushesData` | AC6 | P1 | After close(), all data is readable |
| 10 | `test_traceRecorder_recordRunStart_eventType` | AC6 | P0 | recordRunStart emits "run_start" event |
| 11 | `test_traceRecorder_recordPlanCreated_eventType` | AC6 | P0 | recordPlanCreated emits "plan_created" event |
| 12 | `test_traceRecorder_recordStepStart_eventType` | AC6 | P0 | recordStepStart emits "step_start" event |
| 13 | `test_traceRecorder_recordStepDone_eventType` | AC6 | P0 | recordStepDone emits "step_done" event |
| 14 | `test_traceRecorder_recordStateChange_eventType` | AC6 | P0 | recordStateChange emits "state_change" event |
| 15 | `test_traceRecorder_recordVerificationResult_eventType` | AC6 | P0 | recordVerificationResult emits "verification_result" event |
| 16 | `test_traceRecorder_recordRunDone_eventType` | AC6 | P0 | recordRunDone emits "run_done" event |
| 17 | `test_traceRecorder_recordError_eventType` | AC6 | P0 | recordError emits "error" event |
| 18 | `test_traceRecorder_apiKeyNotInPayload` | AC7 | P0 | API key never appears in trace output |
| 19 | `test_traceRecorder_eachLineIsIndependentJSON` | AC7 | P0 | Each line parses as independent JSON object |

## TDD Red Phase Status

All tests are designed to **fail before implementation**:
- TerminalOutput type does not exist yet (Sources/AxionCLI/Output/TerminalOutput.swift)
- JSONOutput type does not exist yet (Sources/AxionCLI/Output/JSONOutput.swift)
- TraceRecorder actor does not exist yet (Sources/AxionCLI/Trace/TraceRecorder.swift)
- OutputProtocol has only 5 methods, missing 3 new methods (displayRunStart, displayReplan, displayVerificationResult)
- RunResult / StepRecord / StateTransition helper types do not exist yet

Tests will compile after implementation types are created and OutputProtocol is updated.
