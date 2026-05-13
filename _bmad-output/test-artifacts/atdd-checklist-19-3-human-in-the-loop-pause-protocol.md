---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-05-12'
storyId: '19.3'
storyKey: 19-3-human-in-the-loop-pause-protocol
storyFile: _bmad-output/implementation-artifacts/19-3-human-in-the-loop-pause-protocol.md
atddChecklistPath: _bmad-output/test-artifacts/atdd-checklist-19-3-human-in-the-loop-pause-protocol.md
generatedTestFiles:
  - Tests/OpenAgentSDKTests/Core/PauseProtocolTests.swift
---

# ATDD Checklist: Story 19-3 — Human-in-the-loop Pause Protocol

## TDD Red Phase (Current)

Red-phase test scaffolds generated. All tests assert EXPECTED behavior and will FAIL until the feature is implemented.

- Unit Tests: 31 tests (all will fail until implementation)
- E2E Tests: N/A (backend Swift project, no browser-based testing)

## Acceptance Criteria Coverage

| AC   | Description                                      | Tests                                                                                             | Priority |
|------|--------------------------------------------------|---------------------------------------------------------------------------------------------------|----------|
| AC1  | Agent.pause(reason:) emits paused event          | testStream_pauseForHuman_emitsPausedMessage, testAgent_hasPauseMethod                             | P0       |
| AC2  | Agent.resume(context:) injects context           | testStream_resumeAfterPause_agentContinues, testAgent_hasResumeMethod                             | P0       |
| AC3  | Agent.abort() from paused returns cancelled      | testStream_abortFromPaused_returnsCancelled                                                       | P0       |
| AC4  | Pause timeout auto-cancels                       | testStream_pauseTimeout_emitsPausedTimeoutAndCancels, testAgentOptions_hasPauseTimeoutMs_*        | P0       |
| AC5  | SDKMessage new cases (PausedData, Subtype)       | testPausedData_*, testSystemDataSubtype_hasPausedCase, testSystemDataSubtype_hasPausedTimeoutCase | P0       |
| AC6  | Built-in pause_for_human tool                    | testPauseForHumanTool_*, testPauseResult_*, testPauseToolRegistrationTests_*                      | P0       |
| AC7  | Unit tests covering all operations               | All tests in PauseProtocolTests.swift                                                             | P0       |
| AC8  | Build and test pass                              | Manual verification (swift build + full test suite)                                               | P1       |

## Test Classes and Method Summary

### PausedDataTypeTests (7 tests) — AC5
- `testPausedData_canBeCreatedWithAllFields` [P0]
- `testPausedData_hasSensibleDefaults` [P0]
- `testPausedData_isEquatable` [P0]
- `testSystemDataSubtype_hasPausedCase` [P0]
- `testSystemDataSubtype_hasPausedTimeoutCase` [P0]
- `testSystemData_hasPausedDataField` [P0]
- `testSystemData_pausedDataIsNilForNonPauseEvents` [P0]
- `testSystemData_equalityIncludesPausedData` [P0]

### PauseTimeoutConfigTests (3 tests) — AC4
- `testAgentOptions_hasPauseTimeoutMs_withDefault` [P0]
- `testAgentOptions_pauseTimeoutMs_canBeCustomized` [P0]
- `testAgentOptions_pauseTimeoutMs_zeroDisablesTimeout` [P1]

### PauseForHumanToolTests (7 tests) — AC6
- `testPauseForHumanTool_hasCorrectName` [P0]
- `testPauseForHumanTool_isReadOnly` [P0]
- `testPauseForHumanTool_requiresReasonInSchema` [P0]
- `testPauseForHumanTool_noHandler_returnsNonInteractive` [P0]
- `testPauseForHumanTool_withHandler_returnsResumedContext` [P0]
- `testPauseForHumanTool_handlerAborted_returnsError` [P0]
- `testPauseForHumanTool_handlerTimedOut_returnsError` [P0]
- `testPauseForHumanTool_noHandler_includesReasonInMessage` [P0]

### PauseResultTypeTests (3 tests) — AC6
- `testPauseResult_resumed_carriesContext` [P0]
- `testPauseResult_aborted_isValid` [P0]
- `testPauseResult_timedOut_isValid` [P0]

### PauseHandlerRegistrationTests (2 tests) — AC6
- `testPauseHandler_canBeSetAndCleared` [P0]
- `testPauseHandler_settingNewHandlerReplacesOld` [P1]

### PauseStreamTests (4 tests) — AC1, AC2, AC3, AC4
- `testStream_pauseForHuman_emitsPausedMessage` [P0]
- `testStream_resumeAfterPause_agentContinues` [P0]
- `testStream_abortFromPaused_returnsCancelled` [P0]
- `testStream_pauseTimeout_emitsPausedTimeoutAndCancels` [P0]

### PauseDirectAPITests (3 tests) — AC1, AC2, AC3
- `testAgent_hasPauseMethod` [P0]
- `testAgent_hasResumeMethod` [P0]
- `testAgent_resumeWhenNotPaused_doesNotCrash` [P0]

### PauseToolRegistrationTests (2 tests) — AC6
- `testPauseForHuman_isInCoreTierTools` [P0]
- `testCreatePauseForHumanTool_isCallable` [P1]

## Test Strategy

- **Stack**: Backend (Swift SPM, XCTest)
- **Generation Mode**: AI Generation (backend, no browser recording needed)
- **Test Level**: Unit tests for types/tools/config; Integration tests for stream pause/resume flows
- **Total Tests**: 31

## Risks and Assumptions

1. **PauseResult enum location**: Assumed to be in `PauseForHumanTool.swift` alongside the tool, following the AskUser pattern. If placed elsewhere, import adjustments may be needed.
2. **CheckedContinuation suspension**: The stream tests use a synchronous-resolve handler (immediately returns). Real-world pause/resume will need async coordination via CheckedContinuation -- tested behavior validates the contract, not the timing.
3. **AbortMockURLProtocol reuse**: Stream tests reuse `AbortMockURLProtocol`, `Box`, `makeAbortSUT`, and `runStreamInTask` from `AbortTests.swift`. These helpers are in the same test target and accessible.
4. **No `prompt()` flow test**: The story specifies pause/resume should work in both `stream()` and `prompt()`. The `prompt()` tests validate method existence only -- full `prompt()` integration testing can be added during green phase if needed.
5. **PauseResult is assumed public**: Tests import `@preconcurrency import OpenAgentSDK` and reference `PauseResult` as a public type. If the implementation uses a different visibility, the tests will need adjustment.

## Next Steps (Task-by-Task Activation)

During implementation of each task from the story:

1. Implement the types/methods for the current task
2. Run the relevant tests: `swift test --filter PauseProtocolTests`
3. Verify tests transition from RED to GREEN
4. Run full test suite: `swift test` -- verify zero regressions
5. Commit passing tests

## Generated Files

- `Tests/OpenAgentSDKTests/Core/PauseProtocolTests.swift` — 31 ATDD tests
