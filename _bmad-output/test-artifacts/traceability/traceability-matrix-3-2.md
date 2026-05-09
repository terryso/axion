---
stepsCompleted:
  - step-01-load-context
  - step-02-discover-tests
  - step-03-map-criteria
  - step-04-analyze-gaps
  - step-05-gate-decision
lastStep: step-05-gate-decision
lastSaved: '2026-05-10'
storyId: '3.2'
storyKey: '3-2-prompt-management-planning-engine'
coverageBasis: acceptance_criteria
oracleConfidence: high
oracleResolutionMode: formal_requirements
oracleSources:
  - '_bmad-output/implementation-artifacts/3-2-prompt-management-planning-engine.md'
  - '_bmad-output/test-artifacts/atdd-checklist-3-2-prompt-management-planning-engine.md'
externalPointerStatus: not_used
tempCoverageMatrixPath: '_bmad-output/test-artifacts/traceability/coverage-matrix-3-2.json'
gateDecision: PASS
---

# Traceability Report: Story 3.2

**Prompt 管理与规划引擎**

---

## Gate Decision: PASS

**Rationale:** P0 coverage is 100%, P1 coverage is 100% (no P1 requirements -- all 7 ACs are P0), and overall coverage is 100% (minimum: 80%). All acceptance criteria have FULL test coverage with 51 active unit tests across 3 test files. No critical or high gaps identified.

---

## Coverage Summary

| Metric | Value |
|--------|-------|
| Total Acceptance Criteria | 7 |
| Fully Covered | 7 (100%) |
| Partially Covered | 0 (0%) |
| Uncovered | 0 (0%) |
| **P0 Coverage** | **7/7 (100%)** |
| P1 Coverage | N/A (0 P1 requirements) |

### Test Execution Results

- PromptBuilderTests: **12 tests passed**, 0 failures
- PlanParserTests: **24 tests passed**, 0 failures
- LLMPlannerTests: **15 tests passed**, 0 failures
- **Total: 51 tests passed**, 0 failures, 0 skipped

---

## Traceability Matrix

| AC | Description | Priority | Coverage | Tests |
|----|-------------|----------|----------|-------|
| AC1 | Prompt 文件加载与模板变量注入 | P0 | FULL | 12 tests |
| AC2 | LLM 规划生成结构化 Plan | P0 | FULL | 5 tests |
| AC3 | Plan 步骤结构完整性 | P0 | FULL | 6 tests |
| AC4 | Markdown 围栏解析 | P0 | FULL | 5 tests |
| AC5 | 前导文本解析 | P0 | FULL | 2 tests |
| AC6 | LLM API 重试（NFR6） | P0 | FULL | 3 tests |
| AC7 | Plan 解析失败不静默丢弃（NFR7） | P0 | FULL | 2 tests |

---

## Detailed AC-to-Test Mapping

### AC1: Prompt 文件加载与模板变量注入 (P0) -- FULL

| Test | File | Level | Verified Behavior |
|------|------|-------|-------------------|
| test_promptBuilder_typeExists | PromptBuilderTests.swift | unit | PromptBuilder type exists |
| test_load_existingFile_returnsContent | PromptBuilderTests.swift | unit | Loads .md file and replaces template variables |
| test_load_missingFile_throwsError | PromptBuilderTests.swift | unit | Throws error for nonexistent file |
| test_load_noVariables_returnsRawContent | PromptBuilderTests.swift | unit | Returns raw content without variable substitution |
| test_load_multipleOccurrences_replacesAll | PromptBuilderTests.swift | unit | Replaces all occurrences of same variable |
| test_templateVariable_injectedCorrectly | PromptBuilderTests.swift | unit | {{tools}} placeholder replaced with tool list |
| test_buildToolListDescription_formatsToolNames | PromptBuilderTests.swift | unit | Tool names formatted for prompt inclusion |
| test_buildToolListDescription_emptyList_returnsEmpty | PromptBuilderTests.swift | unit | Empty tool list returns empty string |
| test_buildPlannerPrompt_includesTask | PromptBuilderTests.swift | unit | User prompt contains task description and maxSteps |
| test_buildPlannerPrompt_withReplanContext_includesFailureInfo | PromptBuilderTests.swift | unit | Replan prompt includes REPLAN marker, error, executed steps |
| test_resolvePromptDirectory_returnsValidPath | PromptBuilderTests.swift | unit | Prompt directory resolution returns non-empty path |
| test_load_unresolvedVariables_remainAsPlaceholders | PromptBuilderTests.swift | unit | Unresolved {{var}} placeholders preserved as-is |

### AC2: LLM 规划生成结构化 Plan (P0) -- FULL

| Test | File | Level | Verified Behavior |
|------|------|-------|-------------------|
| test_llmPlanner_typeExists | LLMPlannerTests.swift | unit | LLMPlanner type exists and conforms to PlannerProtocol |
| test_llmClientProtocol_typeExists | LLMPlannerTests.swift | unit | LLMClientProtocol abstraction exists |
| test_createPlan_callsLLMWithCorrectPrompt | LLMPlannerTests.swift | unit | createPlan calls LLM with system + user prompts |
| test_createPlan_returnsPlanWithSteps | LLMPlannerTests.swift | unit | createPlan returns Plan with correct steps and task |
| test_llmPlanner_init_withConfigAndClients | LLMPlannerTests.swift | unit | LLMPlanner initializes with config + injected clients |

### AC3: Plan 步骤结构完整性 (P0) -- FULL

| Test | File | Level | Verified Behavior |
|------|------|-------|-------------------|
| test_parsePlan_stepStructure_hasAllRequiredFields | PlanParserTests.swift | unit | Each step has tool, parameters, purpose, expectedChange |
| test_validatePlan_validPlan_returnsPlan | PlanParserTests.swift | unit | Valid plan passes validation |
| test_parsePlan_argsField_mapsToParameters | PlanParserTests.swift | unit | LLM "args" field maps to Step "parameters" |
| test_parsePlan_expectedChangeField_snakeCaseMapped | PlanParserTests.swift | unit | LLM "expected_change" maps to Step "expectedChange" |
| test_validatePlan_emptySteps_throwsInvalidPlan | PlanParserTests.swift | unit | Empty steps array rejected |
| test_validatePlan_emptyStopWhen_throwsInvalidPlan | PlanParserTests.swift | unit | Empty stopWhen rejected |

### AC4: Markdown 围栏解析 (P0) -- FULL

| Test | File | Level | Verified Behavior |
|------|------|-------|-------------------|
| test_planParser_typeExists | PlanParserTests.swift | unit | PlanParser type exists |
| test_stripFences_jsonInBackticks_extractsJSON | PlanParserTests.swift | unit | Extracts JSON from ```json...``` fences |
| test_stripFences_jsonInPlainBackticks_extractsJSON | PlanParserTests.swift | unit | Extracts JSON from ```...``` fences |
| test_stripFences_pureJSON_returnsAsIs | PlanParserTests.swift | unit | Pure JSON returned unchanged |
| test_stripFences_nestedBracesInStrings_handlesCorrectly | PlanParserTests.swift | unit | Braces inside string values handled correctly |

### AC5: 前导文本解析 (P0) -- FULL

| Test | File | Level | Verified Behavior |
|------|------|-------|-------------------|
| test_stripFences_proseBeforeJSON_extractsJSON | PlanParserTests.swift | unit | Skips prose text, extracts JSON object |
| test_stripFences_jsonWithTrailingText_extractsJSON | PlanParserTests.swift | unit | Truncates at closing brace, ignores trailing text |

### AC6: LLM API 重试 NFR6 (P0) -- FULL

| Test | File | Level | Verified Behavior |
|------|------|-------|-------------------|
| test_createPlan_retriesOnNetworkError_upToMaxRetries | LLMPlannerTests.swift | unit | Retries up to 3 times on transient error (4 total calls) |
| test_createPlan_succeedsOnRetry_afterInitialFailure | LLMPlannerTests.swift | unit | Succeeds on retry after initial failure (exponential backoff) |
| test_createPlan_doesNotRetryOnParseError | LLMPlannerTests.swift | unit | Parse errors do NOT trigger retry (1 call only) |

### AC7: Plan 解析失败不静默丢弃 NFR7 (P0) -- FULL

| Test | File | Level | Verified Behavior |
|------|------|-------|-------------------|
| test_parsePlan_failurePreservesRawResponse_NFR7 | PlanParserTests.swift | unit | Error reason contains raw response context |
| test_parsePlan_invalidJSON_throwsInvalidPlan | PlanParserTests.swift | unit | Invalid input throws AxionError.invalidPlan |

---

## Additional Coverage (Non-AC Tests)

The following tests cover edge cases and behavioral details beyond the strict AC requirements:

| Test | File | Behavior |
|------|------|----------|
| test_createPlan_llmThrowsError_propagatesError | LLMPlannerTests.swift | LLM error propagated correctly |
| test_createPlan_parseFailure_throwsInvalidPlan | LLMPlannerTests.swift | Parse failure in createPlan throws invalidPlan |
| test_createPlan_capturesCurrentState_callsMCPTools | LLMPlannerTests.swift | createPlan captures AX tree context |
| test_createPlan_screenshotFailure_degradesGracefully | LLMPlannerTests.swift | Works without screenshot/AX tree (degraded mode) |
| test_replan_includesFailureContext | LLMPlannerTests.swift | replan prompt includes failure context |
| test_replan_passesExecutedStepsToPrompt | LLMPlannerTests.swift | replan prompt includes executed steps |
| test_createPlan_systemPromptContainsToolList | LLMPlannerTests.swift | System prompt contains tool information |
| test_parsePlan_doneStatus_returnsEmptyStepsPlan | PlanParserTests.swift | status:done returns 0-step plan |
| test_parsePlan_needsClarificationStatus_throwsAppropriateError | PlanParserTests.swift | needs_clarification throws planningFailed |
| test_parsePlan_stopWhenString_mapsToStopCondition | PlanParserTests.swift | stopWhen string mapped to StopCondition(type:.custom) |
| test_parsePlan_emptySteps_throwsInvalidPlan | PlanParserTests.swift | Empty steps in raw response rejected |
| test_parsePlan_missingStopWhen_throwsInvalidPlan | PlanParserTests.swift | Empty stopWhen in raw response rejected |
| test_parsePlan_stepMissingTool_throwsInvalidPlan | PlanParserTests.swift | Step without tool rejected |
| test_parsePlan_stepMissingPurpose_throwsInvalidPlan | PlanParserTests.swift | Step without purpose rejected |
| test_parsePlan_exceedsMaxSteps_throwsInvalidPlan | PlanParserTests.swift | Steps exceeding maxSteps rejected |

---

## Gaps & Recommendations

### Critical Gaps: 0

None.

### High Gaps: 0

None.

### Medium Gaps: 2

1. **真实 LLM API 集成测试** -- All LLMPlanner tests use MockLLMClient. End-to-end verification with real Anthropic API requires integration tests (Tests/**/Integration/ directory). This is by design (unit tests mock external dependencies).

2. **planner-system.md 内容验证** -- Story Task 2 created the prompt file but no dedicated test verifies its content ({{tools}} placeholder, shifted key mapping, etc.). Indirectly covered by PromptBuilder.load and LLMPlanner.buildPrompts.

### Low Gaps: 1

1. **非 AxionError 类型的重试** -- callLLMWithRetry retries non-AxionError errors (e.g., URLError) but tests only cover AxionError.planningFailed scenario.

### Recommendations

| Priority | Action |
|----------|--------|
| LOW | Add integration tests for real Anthropic API end-to-end Planner flow |
| LOW | Add test verifying planner-system.md content contains required placeholders |
| LOW | Run /bmad:tea:test-review to assess test quality |

---

## Test Files

| File | Tests | Status |
|------|-------|--------|
| Tests/AxionCLITests/Planner/PromptBuilderTests.swift | 12 | All PASS |
| Tests/AxionCLITests/Planner/PlanParserTests.swift | 24 | All PASS |
| Tests/AxionCLITests/Planner/LLMPlannerTests.swift | 15 | All PASS |
| **Total** | **51** | **All PASS** |

---

## Source Files Covered

| File | Public API | Tests Covering |
|------|-----------|----------------|
| Sources/AxionCLI/Planner/PromptBuilder.swift | load(), resolvePromptDirectory(), buildToolListDescription(), buildPlannerPrompt() | PromptBuilderTests (12) |
| Sources/AxionCLI/Planner/PlanParser.swift | parse(), stripFences(), validatePlan() | PlanParserTests (24) |
| Sources/AxionCLI/Planner/LLMPlanner.swift | createPlan(), replan(), callLLMWithRetry() + LLMClientProtocol, ReplanContext | LLMPlannerTests (15) |
