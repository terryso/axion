# Test Automation Summary — Story 25.2: CuratorArchiveTool

## Generated Tests

### E2E Tests (ReviewToolsE2ETests.swift)
- [x] `testE2E_ArchiveSkill_RetiresInRegistry` — Archives agent-created skill, verifies lifecycle transitions to `.retired`
- [x] `testE2E_ArchiveSkill_RecordsAbsorbedInto` — Archives with merge target, verifies `absorbedInto` persisted in usage data
- [x] `testE2E_ArchiveSkill_PruningWithoutTarget` — Archives with empty `absorbedInto`, verifies pruning (nil absorbedInto)
- [x] `testE2E_ArchiveSkill_RejectsBundled` — Verifies provenance guard rejects non-agent-created skills
- [x] `testE2E_ArchiveSkill_RejectsPinned` — Verifies pinned guard rejects pinned skills
- [x] `testE2E_CreateThenArchiveWorkflow` — Cross-tool: create skill → set usage data → archive with merge target

### Fixes Applied
- [x] `Sources/E2ETest/ReviewOrchestratorE2ETests.swift` — Added `curator_archive_skill` to `allowedTools` in test 84 (executeReview full pipeline)

## Coverage

### Acceptance Criteria Coverage
| AC | Description | E2E Tests |
|----|-------------|-----------|
| AC3 | Provenance guard | `testE2E_ArchiveSkill_RejectsBundled` |
| AC4 | Pinned guard | `testE2E_ArchiveSkill_RejectsPinned` |
| AC5 | Archive action (retire + usage update) | `testE2E_ArchiveSkill_RetiresInRegistry` |
| AC6 | `absorbedInto` tracking | `testE2E_ArchiveSkill_RecordsAbsorbedInto`, `testE2E_ArchiveSkill_PruningWithoutTarget` |
| AC7 | Integration with `createReviewTools` | `testToolNamesMatchReviewAgentConfigAllowedTools` (existing), `testE2E_CreateThenArchiveWorkflow` |

### Tool Guard Coverage
| Guard | Test |
|-------|------|
| Empty skillName | Covered by existing unit test |
| Non-agent-created | `testE2E_ArchiveSkill_RejectsBundled` |
| Pinned | `testE2E_ArchiveSkill_RejectsPinned` |
| Non-existent skill | Covered by existing unit test |
| Unknown provenance | Covered by existing unit test |

## Test Results

**Full suite: 5,585 tests executed, 0 failures, 42 skipped**

No regressions from baseline (5,579 tests from story completion).

## Checklist Validation

- [x] E2E tests generated
- [x] Tests use standard test framework APIs (XCTest)
- [x] Tests cover happy path
- [x] Tests cover critical error cases (provenance guard, pinned guard)
- [x] All generated tests run successfully
- [x] Tests have clear descriptions
- [x] No hardcoded waits or sleeps
- [x] Tests are independent (no order dependency)
- [x] Test summary created
- [x] Tests saved to appropriate directory
