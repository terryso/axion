---
stepsCompleted: ['step-01-preflight-and-context', 'step-02-generation-mode', 'step-03-test-strategy', 'step-04-generate-tests']
lastStep: 'step-04-generate-tests'
lastSaved: '2026-05-10'
storyId: '3.4'
storyKey: '3-4-task-verification-stop-condition'
storyFile: '_bmad-output/implementation-artifacts/stories/3-4-task-verification-stop-condition.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-3-4-task-verification-stop-condition.md'
generatedTestFiles:
  - 'Tests/AxionCoreTests/VerificationResultTests.swift'
  - 'Tests/AxionCLITests/Verifier/StopConditionEvaluatorTests.swift'
  - 'Tests/AxionCLITests/Verifier/TaskVerifierTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/stories/3-4-task-verification-stop-condition.md'
  - '_bmad-output/project-context.md'
  - 'Sources/AxionCore/Protocols/VerifierProtocol.swift'
  - 'Sources/AxionCore/Models/StopCondition.swift'
  - 'Sources/AxionCore/Models/RunState.swift'
  - 'Sources/AxionCore/Models/ExecutedStep.swift'
  - 'Sources/AxionCore/Models/RunContext.swift'
  - 'Sources/AxionCore/Models/Plan.swift'
  - 'Sources/AxionCore/Models/Step.swift'
  - 'Sources/AxionCore/Protocols/MCPClientProtocol.swift'
  - 'Sources/AxionCore/Constants/ToolNames.swift'
  - 'Sources/AxionCore/Errors/AxionError.swift'
  - 'Sources/AxionCLI/Planner/LLMPlanner.swift'
  - 'Tests/AxionCLITests/Executor/StepExecutorTests.swift'
---

# ATDD Checklist: Story 3.4 - Task Verification & Stop Condition Evaluation

## Stack Detection

- **detected_stack**: backend (Swift SPM project, no frontend manifests)
- **test_framework**: XCTest (Swift Package Manager)

## Generation Mode

- **mode**: AI Generation (backend project, no browser recording needed)

## Test Strategy

### Acceptance Criteria to Test Mapping

| AC | Description | Test Level | Priority | Test File |
|----|-------------|-----------|----------|-----------|
| AC1 | Batch execution captures verification context (screenshot + AX tree) | Unit | P0 | TaskVerifierTests.swift |
| AC2 | StopCondition evaluation with LLM assistance | Unit | P0 | StopConditionEvaluatorTests.swift, TaskVerifierTests.swift |
| AC3 | Task completion state `.done` | Unit | P0 | VerificationResultTests.swift, TaskVerifierTests.swift |
| AC4 | Task blocked state `.blocked` | Unit | P0 | VerificationResultTests.swift, TaskVerifierTests.swift |
| AC5 | Needs clarification state `.needsClarification` | Unit | P0 | VerificationResultTests.swift, TaskVerifierTests.swift |

### Test Scenarios

#### VerificationResultTests (AxionCore — pure model, no mocks)

| # | Test Method | AC | Priority | Description |
|---|-------------|-----|----------|-------------|
| 1 | `test_verificationResult_doneRoundTrip_preservesAllFields` | AC3 | P0 | Codable round-trip for .done state |
| 2 | `test_verificationResult_blockedRoundTrip_preservesAllFields` | AC4 | P0 | Codable round-trip for .blocked state |
| 3 | `test_verificationResult_needsClarificationRoundTrip_preservesAllFields` | AC5 | P0 | Codable round-trip for .needsClarification state |
| 4 | `test_verificationResult_doneFactoryMethod_correctState` | AC3 | P0 | .done() factory sets correct state |
| 5 | `test_verificationResult_blockedFactoryMethod_correctState` | AC4 | P0 | .blocked() factory sets correct state |
| 6 | `test_verificationResult_needsClarificationFactoryMethod_correctState` | AC5 | P0 | .needsClarification() factory sets correct state |
| 7 | `test_verificationResult_done_withoutOptionals` | AC3 | P1 | .done with nil optional fields |
| 8 | `test_verificationResult_equality_sameValues` | AC3-5 | P1 | Equal results compare equal |
| 9 | `test_verificationResult_equality_differentReason` | AC3-5 | P1 | Different reasons are not equal |

#### StopConditionEvaluatorTests (AxionCLI — pure function, no mocks)

| # | Test Method | AC | Priority | Description |
|---|-------------|-----|----------|-------------|
| 1 | `test_evaluate_textAppears_textFoundInAxTree_returnsSatisfied` | AC2 | P0 | textAppears matches text in AX tree |
| 2 | `test_evaluate_textAppears_textNotFound_returnsNotSatisfied` | AC2 | P0 | textAppears no match returns notSatisfied |
| 3 | `test_evaluate_textAppears_caseInsensitive` | AC2 | P1 | textAppears matching is case-insensitive |
| 4 | `test_evaluate_windowAppears_windowTitleFound_returnsSatisfied` | AC2 | P0 | windowAppears matches window title in AX tree |
| 5 | `test_evaluate_windowAppears_windowNotFound_returnsNotSatisfied` | AC2 | P0 | windowAppears no match returns notSatisfied |
| 6 | `test_evaluate_windowDisappears_windowGone_returnsSatisfied` | AC2 | P0 | windowDisappears when window absent returns satisfied |
| 7 | `test_evaluate_windowDisappears_windowStillPresent_returnsNotSatisfied` | AC2 | P0 | windowDisappears when window present returns notSatisfied |
| 8 | `test_evaluate_maxStepsReached_stepsEqualMax_returnsSatisfied` | AC2 | P0 | maxStepsReached when count equals max |
| 9 | `test_evaluate_maxStepsReached_stepsBelowMax_returnsNotSatisfied` | AC2 | P0 | maxStepsReached when count below max |
| 10 | `test_evaluate_processExits_processGone_returnsSatisfied` | AC2 | P1 | processExits when pid absent from recent steps |
| 11 | `test_evaluate_customType_returnsUncertain` | AC2 | P0 | custom type always returns uncertain |
| 12 | `test_evaluate_fileExists_returnsUncertain` | AC2 | P1 | fileExists returns uncertain (MCP not available) |
| 13 | `test_evaluate_emptyConditions_returnsSatisfied` | AC2 | P1 | No stop conditions means satisfied (no conditions to fail) |
| 14 | `test_evaluate_multipleConditions_allSatisfied_returnsSatisfied` | AC2 | P1 | All conditions satisfied returns satisfied |
| 15 | `test_evaluate_multipleConditions_oneNotSatisfied_returnsNotSatisfied` | AC2 | P1 | One condition failing returns notSatisfied |
| 16 | `test_evaluate_textAppears_nilAxTree_returnsUncertain` | AC2 | P1 | textAppears with no AX tree data returns uncertain |
| 17 | `test_evaluate_windowAppears_nilAxTree_returnsUncertain` | AC2 | P1 | windowAppears with no AX tree data returns uncertain |
| 18 | `test_evaluate_stopEvaluationResult_isCodableAndEquatable` | AC2 | P0 | StopEvaluationResult supports Codable + Equatable |

#### TaskVerifierTests (AxionCLI — Mock MCPClientProtocol + LLMClientProtocol)

| # | Test Method | AC | Priority | Description |
|---|-------------|-----|----------|-------------|
| 1 | `test_taskVerifier_typeExists` | AC1 | P0 | TaskVerifier type can be referenced |
| 2 | `test_taskVerifier_conformsToVerifierProtocol` | AC1 | P0 | TaskVerifier conforms to updated VerifierProtocol |
| 3 | `test_verify_screenshotAndAxTreeCaptured_returnsDone` | AC1,AC3 | P0 | Full flow: MCP captures context, conditions met, returns .done |
| 4 | `test_verify_stopConditionNotMet_returnsBlocked` | AC4 | P0 | Conditions not met returns .blocked |
| 5 | `test_verify_llmReturnsNeedsClarification_returnsNeedsClarification` | AC5 | P0 | LLM returns needs_clarification status |
| 6 | `test_verify_llmReturnsDone_returnsDone` | AC3 | P0 | LLM confirms task done |
| 7 | `test_verify_llmReturnsBlocked_returnsBlocked` | AC4 | P0 | LLM reports blocked state |
| 8 | `test_verify_mcpScreenshotFailure_degradesGracefully` | AC1 | P1 | Screenshot MCP failure, still proceeds with AX tree |
| 9 | `test_verify_mcpAxTreeFailure_degradesGracefully` | AC1 | P1 | AX tree MCP failure, falls back to LLM |
| 10 | `test_verify_mcpBothFail_degradesGracefully` | AC1 | P1 | Both MCP calls fail, LLM evaluates without context |
| 11 | `test_verify_llmFailure_returnsBlocked` | AC2 | P0 | LLM failure returns .blocked (safe degradation) |
| 12 | `test_verify_llmInvalidJSON_returnsBlocked` | AC2 | P1 | LLM returns unparseable JSON, defaults to .blocked |
| 13 | `test_verify_callsScreenshotWithCorrectWindowId` | AC1 | P1 | Screenshot MCP call uses window_id from context |
| 14 | `test_verify_callsGetAccessibilityTreeWithCorrectPid` | AC1 | P1 | AX tree MCP call uses pid from context |
| 15 | `test_verify_noStopConditions_returnsDone` | AC3 | P1 | Empty stopWhen means task is done by default |
| 16 | `test_verify_textAppears_matchedLocally_skipsLLM` | AC2 | P1 | textAppears matched locally does not call LLM |
| 17 | `test_verify_customCondition_callsLLM` | AC2 | P0 | custom condition triggers LLM evaluation |
| 18 | `test_verify_contextWithoutPid_callsMCPWithoutPid` | AC1 | P1 | No pid in context, MCP called with empty args |

## TDD Red Phase Status

All tests are designed to **fail before implementation**:
- VerificationResult model does not exist yet
- StopConditionEvaluator type does not exist yet
- TaskVerifier type does not exist yet
- VerifierProtocol has old signature (will be updated)
- StopEvaluationResult type does not exist yet

Tests will compile after implementation types are created and VerifierProtocol is updated.
