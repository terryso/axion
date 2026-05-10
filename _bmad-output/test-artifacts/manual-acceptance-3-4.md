# Story 3-4 Manual Acceptance Test

**Story:** 任务验证与停止条件评估
**Date:** 2026-05-10
**Tester:** Nick (assisted by Claude + Happy)

---

## Pre-conditions

- [ ] Git working tree contains uncommitted Story 3-4 changes
- [ ] Swift toolchain available (`swift build` / `swift test`)
- [ ] No other uncommitted changes from different stories

## File Structure Verification

### New files must exist

| # | File | Description |
|---|------|-------------|
| 1 | `Sources/AxionCore/Models/VerificationResult.swift` | VerificationResult model (Codable, Equatable, factory methods) |
| 2 | `Sources/AxionCLI/Verifier/TaskVerifier.swift` | Task verification main logic |
| 3 | `Sources/AxionCLI/Verifier/StopConditionEvaluator.swift` | Local stop condition evaluation |
| 4 | `Prompts/verifier-system.md` | Verifier LLM system prompt |

### Modified files

| # | File | Change |
|---|------|--------|
| 1 | `Sources/AxionCore/Protocols/VerifierProtocol.swift` | Updated signature: `verify(plan:executedSteps:context:) -> VerificationResult` |

### Test files must exist

| # | File |
|---|------|
| 1 | `Tests/AxionCoreTests/VerificationResultTests.swift` |
| 2 | `Tests/AxionCLITests/Verifier/StopConditionEvaluatorTests.swift` |
| 3 | `Tests/AxionCLITests/Verifier/TaskVerifierTests.swift` |

**Command:**
```bash
ls -la Sources/AxionCore/Models/VerificationResult.swift \
       Sources/AxionCLI/Verifier/TaskVerifier.swift \
       Sources/AxionCLI/Verifier/StopConditionEvaluator.swift \
       Prompts/verifier-system.md \
       Sources/AxionCore/Protocols/VerifierProtocol.swift \
       Tests/AxionCoreTests/VerificationResultTests.swift \
       Tests/AxionCLITests/Verifier/StopConditionEvaluatorTests.swift \
       Tests/AxionCLITests/Verifier/TaskVerifierTests.swift
```

**Expected:** All 8 files exist, non-empty.

---

## Build Verification

**Command:**
```bash
swift build 2>&1
```

**Expected:** Build succeeds with 0 errors. Warnings are acceptable but should be noted.

---

## Unit Test Execution

### Test 1: VerificationResult tests (AC3, AC4, AC5)

**Command:**
```bash
swift test --filter "AxionCoreTests.VerificationResultTests" 2>&1
```

**Expected:** All tests pass. Tests cover:
- Codable round-trip for .done / .blocked / .needsClarification
- Factory methods produce correct states
- Equality semantics

### Test 2: StopConditionEvaluator tests (AC2)

**Command:**
```bash
swift test --filter "AxionCLITests.Verifier.StopConditionEvaluatorTests" 2>&1
```

**Expected:** All tests pass. Tests cover:
- textAppears: found / not found / case insensitive / nil AX tree
- windowAppears: found / not found / nil AX tree
- windowDisappears: gone / still present
- maxStepsReached: equal / below
- custom / fileExists: returns uncertain
- Empty conditions: satisfied
- Multiple conditions: all satisfied / one not satisfied
- processExits: process gone

### Test 3: TaskVerifier tests (AC1, AC2, AC3, AC4, AC5)

**Command:**
```bash
swift test --filter "AxionCLITests.Verifier.TaskVerifierTests" 2>&1
```

**Expected:** All tests pass. Tests cover:
- Type existence and protocol conformance
- Full flow: screenshot + AX tree captured → done
- Stop condition not met → blocked
- LLM returns needs_clarification
- LLM returns done / blocked
- LLM failure → safe degradation (blocked)
- LLM invalid JSON → safe degradation (blocked)
- MCP screenshot failure → graceful degradation
- MCP AX tree failure → graceful degradation
- MCP both fail → graceful degradation
- Correct MCP arguments (window_id, pid)
- No stop conditions → done
- textAppears matched locally → skips LLM
- Custom condition → calls LLM
- Context without pid → calls MCP without pid

### Test 4: Full regression suite

**Command:**
```bash
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests" 2>&1
```

**Expected:** All tests pass, 0 failures. No regressions from previous stories.

---

## Code Quality Checks

### Import rule compliance

**Command:**
```bash
grep -n "import" Sources/AxionCLI/Verifier/TaskVerifier.swift Sources/AxionCLI/Verifier/StopConditionEvaluator.swift Sources/AxionCore/Models/VerificationResult.swift
```

**Expected:**
- VerificationResult.swift: only `import Foundation`
- StopConditionEvaluator.swift: `import Foundation`, `import AxionCore`
- TaskVerifier.swift: `import Foundation`, `import AxionCore`
- NO imports of: AxionHelper, OpenAgentSDK, MCP

### No print() statements

**Command:**
```bash
grep -n "print(" Sources/AxionCLI/Verifier/*.swift Sources/AxionCore/Models/VerificationResult.swift
```

**Expected:** No matches.

### No new error types

**Command:**
```bash
grep -rn "enum.*Error" Sources/AxionCLI/Verifier/ Sources/AxionCore/Models/VerificationResult.swift
```

**Expected:** No matches (should reuse AxionError).

---

## Acceptance Criteria Traceability

| AC | Description | Validated By | Status |
|----|-------------|-------------|--------|
| AC1 | 批次执行后获取验证上下文 (screenshot + AX tree) | TaskVerifierTests: `test_verify_screenshotAndAxTreeCaptured_returnsDone`, `test_verify_callsScreenshotWithCorrectWindowId`, `test_verify_callsGetAccessibilityTreeWithCorrectPid` | ☐ |
| AC2 | StopCondition 评估（LLM 辅助） | StopConditionEvaluatorTests (all), TaskVerifierTests: `test_verify_textAppears_matchedLocally_skipsLLM`, `test_verify_customCondition_callsLLM` | ☐ |
| AC3 | 任务完成状态 .done | VerificationResultTests: `test_verificationResult_doneFactoryMethod_correctState`, TaskVerifierTests: `test_verify_screenshotAndAxTreeCaptured_returnsDone` | ☐ |
| AC4 | 任务受阻状态 .blocked | VerificationResultTests: `test_verificationResult_blockedFactoryMethod_correctState`, TaskVerifierTests: `test_verify_stopConditionNotMet_returnsBlocked`, `test_verify_llmFailure_returnsBlocked` | ☐ |
| AC5 | 需要澄清状态 .needsClarification | VerificationResultTests: `test_verificationResult_needsClarificationFactoryMethod_correctState`, TaskVerifierTests: `test_verify_llmReturnsNeedsClarification_returnsNeedsClarification` | ☐ |

---

## Sign-off

- [ ] All file structure checks pass
- [ ] Build succeeds with 0 errors
- [ ] All 3 test suites pass (VerificationResult + StopConditionEvaluator + TaskVerifier)
- [ ] Full regression suite passes (0 failures)
- [ ] Code quality checks pass (imports, no print(), no new error types)
- [ ] All 5 ACs validated

**Verdict:** ☐ PASS / ☐ FAIL
**Signed:** ___________
