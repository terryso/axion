---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-05-08'
storyId: '1.1'
storyKey: 1-1-spm-scaffolding-axioncore-models
storyFile: _bmad-output/implementation-artifacts/1-1-spm-scaffolding-axioncore-models.md
atddChecklistPath: _bmad-output/test-artifacts/atdd-checklist-1-1-spm-scaffolding-axioncore-models.md
generatedTestFiles:
  - Tests/AxionCoreTests/PlanTests.swift
  - Tests/AxionCoreTests/RunStateTests.swift
  - Tests/AxionCoreTests/AxionConfigTests.swift
  - Tests/AxionCoreTests/AxionErrorTests.swift
  - Tests/AxionCoreTests/SPMScaffoldTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/1-1-spm-scaffolding-axioncore-models.md
  - _bmad/tea/config.yaml
  - .claude/skills/bmad-testarch-atdd/resources/tea-index.csv
  - .claude/skills/bmad-testarch-atdd/resources/knowledge/data-factories.md
  - .claude/skills/bmad-testarch-atdd/resources/knowledge/test-quality.md
  - .claude/skills/bmad-testarch-atdd/resources/knowledge/test-healing-patterns.md
  - .claude/skills/bmad-testarch-atdd/resources/knowledge/test-levels-framework.md
  - .claude/skills/bmad-testarch-atdd/resources/knowledge/test-priorities-matrix.md
---

# ATDD Checklist: Story 1.1 - SPM 项目脚手架与 AxionCore 共享模型

## TDD Red Phase (Current)

Red-phase test scaffolds generated. All tests use `XCTSkip()` to indicate TDD red phase.

- **Unit Tests**: 25 test methods across 5 test files (all skipped via XCTSkip)
- **Integration Tests**: 9 test methods for SPM build/protocol verification (all skipped via XCTSkip)
- **Total**: 34 test methods (all in RED phase)

## Acceptance Criteria Coverage

| AC | Description | Priority | Test File | Test Count | Status |
|----|-------------|----------|-----------|------------|--------|
| AC1 | SPM 编译成功 | P0 | SPMScaffoldTests.swift | 1 | RED |
| AC2 | Plan 模型 Codable round-trip | P0 | PlanTests.swift | 8 | RED |
| AC3 | RunState 枚举完整性 | P0 | RunStateTests.swift | 5 | RED |
| AC4 | AxionConfig Codable camelCase 输出 | P0 | AxionConfigTests.swift | 6 | RED |
| AC5 | AxionError MCP ToolResult 格式 | P0 | AxionErrorTests.swift | 6 | RED |
| AC6 | Protocol 文件位置 | P0 | SPMScaffoldTests.swift | 5 | RED |

**All 6 acceptance criteria have corresponding test coverage.**

## Priority Distribution

| Priority | Test Count | Percentage |
|----------|------------|------------|
| P0 | 23 | 68% |
| P1 | 11 | 32% |
| P2 | 0 | 0% |
| P3 | 0 | 0% |

## Test Level Strategy

This is a **backend (Swift/SPM)** project. Test level selection:

- **Unit Tests** (primary): Pure Codable round-trip, enum completeness, default values
  - Used for: AC2, AC3, AC4, AC5
  - Justification: All models are pure data structures with no external dependencies

- **Integration Tests** (supplementary): Module compilation, protocol existence
  - Used for: AC1, AC6
  - Justification: Verifies SPM target configuration and file organization

- **No E2E Tests**: Not applicable for a backend-only project with no browser-based UI

## Test Files Created

| File | Tests | ACs Covered | Lines |
|------|-------|-------------|-------|
| `Tests/AxionCoreTests/PlanTests.swift` | 8 | AC2 | ~200 |
| `Tests/AxionCoreTests/RunStateTests.swift` | 5 | AC3 | ~110 |
| `Tests/AxionCoreTests/AxionConfigTests.swift` | 6 | AC4 | ~140 |
| `Tests/AxionCoreTests/AxionErrorTests.swift` | 6 | AC5 | ~130 |
| `Tests/AxionCoreTests/SPMScaffoldTests.swift` | 9 | AC1, AC6 | ~130 |

## Red-Green-Refactor Workflow

### RED Phase (Current - TEA Responsibility)

All 34 test methods are marked with `XCTSkip("ATDD RED PHASE: ...")`. Tests assert EXPECTED behavior based on acceptance criteria. When run via `swift test`, all tests will be skipped (not failed), documenting the TDD red phase.

### GREEN Phase (DEV Team Responsibility)

During implementation of each task:

1. Create `Package.swift` and directory structure (Task 1)
2. Remove `XCTSkip` from `SPMScaffoldTests` tests for module compilation checks
3. Run `swift build` and `swift test` to verify AxionCore compiles
4. Implement data models (Task 2)
5. Remove `XCTSkip` from `PlanTests`, `RunStateTests`, `AxionConfigTests`, `AxionErrorTests`
6. Run `swift test` -- tests should now PASS (green phase)
7. Implement protocols (Task 3)
8. Remove `XCTSkip` from protocol-related `SPMScaffoldTests`
9. Run `swift test` -- all tests pass
10. Implement constants (Task 4)

### REFACTOR Phase

After GREEN:
- Review test coverage for gaps
- Ensure test naming follows `test_方法名_场景_预期结果` convention
- Verify no hardcoded test data
- Confirm tests are deterministic

## Task-to-Test Mapping

| Story Task | Tests to Activate | Expected Behavior |
|------------|-------------------|-------------------|
| Task 1: Package.swift + directories | SPMScaffoldTests.test_axionCore_module_compiles | Module imports successfully |
| Task 2.1-2.3: Plan, Step, StopCondition models | PlanTests (all 8) | Codable round-trip, placeholder preservation |
| Task 2.4: RunState model | RunStateTests (all 5) | All 9 cases, Codable round-trip |
| Task 2.5-2.6: RunContext, ExecutedStep | SPMScaffoldTests.test_runContext/ExecutedStep_exists | Types accessible |
| Task 2.7: AxionConfig | AxionConfigTests (all 6) | camelCase JSON, defaults, round-trip |
| Task 2.8: AxionError | AxionErrorTests (all 6) | MCP ToolResult format, 3 required fields |
| Task 3: Protocols | SPMScaffoldTests protocol tests (5) | All protocols accessible |
| Task 4: Constants | SPMScaffoldTests.test_toolNamesConstant | Constants accessible |

## Execution Commands

```bash
# Run all tests (skipped in RED phase)
swift test

# Run specific test file
swift test --filter PlanTests
swift test --filter RunStateTests
swift test --filter AxionConfigTests
swift test --filter AxionErrorTests
swift test --filter SPMScaffoldTests

# Build without running tests
swift build

# Build for release
swift build -c release
```

## Key Assumptions

1. **Value.placeholder Codable strategy**: Tests assume a type-discriminator approach (e.g., `{"type": "placeholder", "value": "$pid"}`) rather than relying on string prefix detection. The implementation must preserve the distinction between `.string("$pid")` and `.placeholder("$pid")`.

2. **AxionError cases**: Tests assume error enum cases based on common patterns (toolNotFound, planFailed, executionTimeout, invalidConfiguration). Exact case names may need adjustment when implementation defines the actual enum.

3. **AxionConfig.apiKey exclusion**: Tests assume apiKey uses a CodingKeys exclusion strategy so it does NOT appear in JSON output. This is a security requirement from the architecture spec.

4. **Protocol skeletons**: Protocol tests only verify existence, not method signatures. This aligns with the story's note that "协议方法签名不需要在本 Story 中完全精确."

## Knowledge Base References

- `test-quality.md`: Deterministic tests, explicit assertions, under 300 lines per test
- `test-levels-framework.md`: Unit tests for pure functions/business logic
- `test-priorities-matrix.md`: P0 for foundational data models, P1 for edge cases
- `data-factories.md`: Factory patterns adapted to Swift (direct struct construction)
- `test-healing-patterns.md`: Patterns for diagnosing Codable failures

## Next Steps

1. **DEV team**: Implement Story 1.1 following the task list
2. **During implementation**: Remove `XCTSkip()` from tests as each task completes
3. **After GREEN**: Run `bmad-testarch-automate` to expand test coverage
4. **Next story**: Create ATDD tests for subsequent stories
