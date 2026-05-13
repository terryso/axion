---
stepsCompleted: ['step-01-preflight-and-context', 'step-02-generation-mode', 'step-03-test-strategy']
lastStep: 'step-03-test-strategy'
lastSaved: '2026-05-13'
storyId: '4.3'
storyKey: '4-3-memory-enhanced-planning'
storyFile: '_bmad-output/implementation-artifacts/4-3-memory-enhanced-planning.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-4-3-memory-enhanced-planning.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift'
  - 'Tests/AxionCLITests/Commands/MemoryListCommandTests.swift'
  - 'Tests/AxionCLITests/Commands/MemoryClearCommandTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/4-3-memory-enhanced-planning.md'
  - '_bmad-output/project-context.md'
  - 'Sources/AxionCLI/Memory/AppMemoryExtractor.swift'
  - 'Sources/AxionCLI/Memory/AppProfileAnalyzer.swift'
  - 'Sources/AxionCLI/Memory/FamiliarityTracker.swift'
  - 'Sources/AxionCLI/Commands/RunCommand.swift'
  - 'Sources/AxionCLI/Planner/PromptBuilder.swift'
  - 'Sources/AxionCLI/AxionCLI.swift'
  - 'Tests/AxionCLITests/Memory/FamiliarityTrackerTests.swift'
  - 'Tests/AxionCLITests/Memory/AppProfileAnalyzerTests.swift'
---

# ATDD Checklist: Story 4.3 — Memory Enhanced Planning

## Story Summary

**Story 4.3:** Memory 增强规划 — 在生成计划时利用 Memory 中积累的历史操作经验，使计划更精准，减少试错和重规划次数。

**Stack:** Backend (Swift 6.1+, SPM, XCTest)
**Test Framework:** XCTest
**Generation Mode:** AI Generation (backend stack)

---

## Acceptance Criteria Coverage

### AC1: Inject App Memory context into Planner prompt

| # | Test | Priority | File | Status |
|---|------|----------|------|--------|
| 1 | test_memoryContextProvider_typeExists | P0 | MemoryContextProviderTests | RED |
| 2 | test_buildMemoryContext_withProfileData_returnsNonNil | P0 | MemoryContextProviderTests | RED |
| 3 | test_buildMemoryContext_containsAppMemorySection | P0 | MemoryContextProviderTests | RED |
| 4 | test_buildMemoryContext_containsReliableOperationPaths | P0 | MemoryContextProviderTests | RED |
| 5 | test_buildMemoryContext_containsAxCharacteristics | P0 | MemoryContextProviderTests | RED |

### AC2: Annotate known unreliable operation paths

| # | Test | Priority | File | Status |
|---|------|----------|------|--------|
| 6 | test_buildMemoryContext_annotatesKnownFailures | P0 | MemoryContextProviderTests | RED |
| 7 | test_buildMemoryContext_failureDataMarkedAsAvoid | P0 | MemoryContextProviderTests | RED |

### AC3: Familiar App uses compact planning strategy

| # | Test | Priority | File | Status |
|---|------|----------|------|--------|
| 8 | test_buildMemoryContext_familiarApp_includesCompactStrategy | P0 | MemoryContextProviderTests | RED |
| 9 | test_buildMemoryContext_unfamiliarApp_includesFullVerificationStrategy | P0 | MemoryContextProviderTests | RED |

### AC4: --no-memory flag disables Memory injection

| # | Test | Priority | File | Status |
|---|------|----------|------|--------|
| 10 | test_buildMemoryContext_noMatchingApp_returnsNil | P0 | MemoryContextProviderTests | RED |
| 11 | test_buildMemoryContext_emptyStore_returnsNil | P0 | MemoryContextProviderTests | RED |

### AC5: `axion memory list` command

| # | Test | Priority | File | Status |
|---|------|----------|------|--------|
| 12 | test_memoryListCommand_typeExists | P0 | MemoryListCommandTests | RED |
| 13 | test_listOutput_containsAppMemoryHeader | P0 | MemoryListCommandTests | RED |
| 14 | test_listOutput_showsDomainEntryCountAndDate | P0 | MemoryListCommandTests | RED |
| 15 | test_listOutput_multipleDomains_showsAll | P0 | MemoryListCommandTests | RED |
| 16 | test_listOutput_noMemory_showsEmptyMessage | P0 | MemoryListCommandTests | RED |
| 17 | test_listOutput_nonExistentDirectory_showsEmptyMessage | P0 | MemoryListCommandTests | RED |

### AC6: `axion memory clear --app` command

| # | Test | Priority | File | Status |
|---|------|----------|------|--------|
| 18 | test_memoryClearCommand_typeExists | P0 | MemoryClearCommandTests | RED |
| 19 | test_clear_existingDomain_removesDomainFile | P0 | MemoryClearCommandTests | RED |
| 20 | test_clear_existingDomain_returnsSuccess | P0 | MemoryClearCommandTests | RED |
| 21 | test_clear_nonExistentDomain_doesNotError | P0 | MemoryClearCommandTests | RED |
| 22 | test_clear_oneDomain_doesNotAffectOther | P0 | MemoryClearCommandTests | RED |

### Domain Inference (Supports AC1, AC2, AC3)

| # | Test | Priority | File | Status |
|---|------|----------|------|--------|
| 23 | test_domainInference_matchesCalculator | P0 | MemoryContextProviderTests | RED |
| 24 | test_domainInference_matchesFinder | P0 | MemoryContextProviderTests | RED |
| 25 | test_domainInference_matchesSafari | P0 | MemoryContextProviderTests | RED |
| 26 | test_domainInference_matchesChrome | P0 | MemoryContextProviderTests | RED |
| 27 | test_domainInference_matchesTextEdit | P0 | MemoryContextProviderTests | RED |
| 28 | test_domainInference_matchesTerminal | P0 | MemoryContextProviderTests | RED |
| 29 | test_domainInference_caseInsensitive | P1 | MemoryContextProviderTests | RED |

### Edge Cases (P1)

| # | Test | Priority | File | Status |
|---|------|----------|------|--------|
| 30 | test_buildMemoryContext_noProfileData_returnsNil | P1 | MemoryContextProviderTests | RED |
| 31 | test_buildMemoryContext_storeError_returnsNil | P1 | MemoryContextProviderTests | RED |
| 32 | test_appNameMap_containsCommonApps | P1 | MemoryContextProviderTests | RED |
| 33 | test_buildMemoryContext_format_hasSectionHeaders | P1 | MemoryContextProviderTests | RED |
| 34 | test_buildMemoryContext_taskMentionsMultipleApps_matchesFirst | P1 | MemoryContextProviderTests | RED |
| 35 | test_listOutput_showsLastUsedDate | P1 | MemoryListCommandTests | RED |
| 36 | test_clear_emptyMemoryDir_doesNotCrash | P1 | MemoryClearCommandTests | RED |
| 37 | test_clear_nonExistentDir_doesNotCrash | P1 | MemoryClearCommandTests | RED |

---

## Summary

| Metric | Count |
|--------|-------|
| Total tests | 37 |
| P0 tests | 29 |
| P1 tests | 8 |
| Test files | 3 |
| AC coverage | 6/6 (100%) |

---

## Test File Manifest

### 1. `Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift`
- **AC covered:** AC1, AC2, AC3, AC4
- **Tests:** 25 tests (type existence, context assembly, domain inference, familiar/unfamiliar strategies, failure annotation, edge cases)
- **Uses:** `InMemoryStore` (SDK) for unit testing without file I/O

### 2. `Tests/AxionCLITests/Commands/MemoryListCommandTests.swift`
- **AC covered:** AC5
- **Tests:** 7 tests (list output format, domain display, empty memory, date format, non-existent dir)
- **Uses:** `FileBasedMemoryStore` with temp directories for realistic file-based testing

### 3. `Tests/AxionCLITests/Commands/MemoryClearCommandTests.swift`
- **AC covered:** AC6
- **Tests:** 6 tests (clear existing, clear non-existent, cross-domain isolation, edge cases)
- **Uses:** `FileBasedMemoryStore` with temp directories for file deletion verification

---

## Test Strategy Notes

- **MemoryContextProvider** is a pure computation service (struct). Tests use `InMemoryStore` to avoid file I/O.
- **MemoryListCommand / MemoryClearCommand** interact with filesystem. Tests use temp directories (`/tmp/axion-test-*`) with automatic cleanup via `defer`.
- Domain inference tests cover the `appNameMap` mapping table with Chinese and English keywords.
- Familiar/unfamiliar strategy tests verify prompt content includes strategy suggestions.
- All tests follow existing project conventions: `test_被测单元_场景_预期结果` naming, `@testable import AxionCLI`, XCTest framework.

---

## Implementation Dependencies

The following types must be created for these tests to compile (RED phase):

1. **`MemoryContextProvider`** (struct) — `Sources/AxionCLI/Memory/MemoryContextProvider.swift`
   - `buildMemoryContext(task:store:) async throws -> String?`
   - `appNameMap: [(keywords: [String], domain: String)]`

2. **`MemoryListCommand`** (struct) — `Sources/AxionCLI/Commands/MemoryListCommand.swift`
   - `listMemory(in:) async throws -> String` (static method for testability)

3. **`MemoryClearCommand`** (struct) — `Sources/AxionCLI/Commands/MemoryClearCommand.swift`
   - `clearDomain(_:memoryDir:) async throws -> ClearResult` (static method for testability)
   - `ClearResult` struct with `success: Bool` and `message: String`

4. **`MemoryCommand`** (struct) — `Sources/AxionCLI/Commands/MemoryCommand.swift`
   - ArgumentParser command group with `list` and `clear` subcommands

5. **Updates to `RunCommand.swift`** — Add `@Flag var noMemory: Bool`
6. **Updates to `AxionCLI.swift`** — Register `MemoryCommand` subcommand
