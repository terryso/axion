---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
lastStep: step-04c-aggregate
lastSaved: '2026-05-13'
storyId: '4.2'
storyKey: 4-2-app-profile-auto-accumulation
storyFile: _bmad-output/implementation-artifacts/4-2-app-profile-auto-accumulation.md
atddChecklistPath: _bmad-output/test-artifacts/atdd-checklist-4-2-app-profile-auto-accumulation.md
generatedTestFiles:
  - Tests/AxionCLITests/Memory/AppProfileAnalyzerTests.swift
  - Tests/AxionCLITests/Memory/FamiliarityTrackerTests.swift
  - Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/4-2-app-profile-auto-accumulation.md
  - _bmad-output/project-context.md
  - Sources/AxionCLI/Memory/AppMemoryExtractor.swift
  - Sources/AxionCLI/Memory/MemoryCleanupService.swift
  - Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift
  - Tests/AxionCLITests/Memory/MemoryCleanupServiceTests.swift
---

# ATDD Checklist: Story 4.2 -- App Profile Auto Accumulation

## TDD Red Phase (Current)

Red-phase test scaffolds generated. All tests assert EXPECTED behavior and will fail until the feature is implemented.

- Unit Tests: 31 tests total (all compile-time RED -- types do not exist yet)

## Acceptance Criteria Coverage

### AC1: Extract AX tree structure features after successful operations
| # | Test | Level | Priority | File |
|---|------|-------|----------|------|
| 1 | `test_extract_contentIncludesAxTreeSummary_whenWindowStatePresent` | Unit | P1 | AppMemoryExtractorTests.swift |
| 2 | `test_extract_contentIncludesAxTreeSummary_whenGetAxTreePresent` | Unit | P1 | AppMemoryExtractorTests.swift |
| 3 | `test_analyze_singleSuccessfulRun_extractsAxCharacteristics` | Unit | P0 | AppProfileAnalyzerTests.swift |

### AC2: Identify high-frequency operation paths
| # | Test | Level | Priority | File |
|---|------|-------|----------|------|
| 1 | `test_analyze_multipleRuns_identifiesHighFrequencyPatterns` | Unit | P0 | AppProfileAnalyzerTests.swift |
| 2 | `test_analyze_diverseRuns_onlyReportsFrequentPatterns` | Unit | P0 | AppProfileAnalyzerTests.swift |
| 3 | `test_analyze_highFrequencyPattern_includesDescription` | Unit | P0 | AppProfileAnalyzerTests.swift |
| 4 | `test_analyze_operationPattern_successRateIsCorrect` | Unit | P1 | AppProfileAnalyzerTests.swift |

### AC3: Mark failure experiences
| # | Test | Level | Priority | File |
|---|------|-------|----------|------|
| 1 | `test_extract_contentIncludesFailureMarker_whenToolFails` | Unit | P1 | AppMemoryExtractorTests.swift |
| 2 | `test_extract_contentIncludesWorkaround_whenFailureFollowedBySuccess` | Unit | P1 | AppMemoryExtractorTests.swift |
| 3 | `test_analyze_failureEntries_extractsKnownFailures` | Unit | P0 | AppProfileAnalyzerTests.swift |
| 4 | `test_analyze_failureWithWorkaround_extractsWorkaround` | Unit | P0 | AppProfileAnalyzerTests.swift |
| 5 | `test_analyze_failureWithoutWorkaround_workaroundIsNil` | Unit | P0 | AppProfileAnalyzerTests.swift |

### AC4: Auto-mark familiar apps (>= 3 successful runs)
| # | Test | Level | Priority | File |
|---|------|-------|----------|------|
| 1 | `test_analyze_threeSuccessfulRuns_marksFamiliar` | Unit | P0 | AppProfileAnalyzerTests.swift |
| 2 | `test_analyze_twoSuccessfulRuns_notFamiliar` | Unit | P0 | AppProfileAnalyzerTests.swift |
| 3 | `test_analyze_exactlyThreeSuccessfulRuns_marksFamiliar` | Unit | P0 | AppProfileAnalyzerTests.swift |
| 4 | `test_checkAndUpdateFamiliarity_belowThreshold_doesNotMark` | Unit | P0 | FamiliarityTrackerTests.swift |
| 5 | `test_checkAndUpdateFamiliarity_atThreshold_marksFamiliar` | Unit | P0 | FamiliarityTrackerTests.swift |
| 6 | `test_checkAndUpdateFamiliarity_aboveThreshold_marksFamiliar` | Unit | P0 | FamiliarityTrackerTests.swift |
| 7 | `test_checkAndUpdateFamiliarity_alreadyFamiliar_doesNotDuplicate` | Unit | P0 | FamiliarityTrackerTests.swift |
| 8 | `test_checkAndUpdateFamiliarity_onlyCountsSuccesses` | Unit | P0 | FamiliarityTrackerTests.swift |
| 9 | `test_checkAndUpdateFamiliarity_mixedWithThreeSuccesses_marksFamiliar` | Unit | P0 | FamiliarityTrackerTests.swift |

## Type Existence Tests (P0 Infrastructure)

| # | Test | File |
|---|------|------|
| 1 | `test_appProfileAnalyzer_typeExists` | AppProfileAnalyzerTests.swift |
| 2 | `test_appProfile_typeExists` | AppProfileAnalyzerTests.swift |
| 3 | `test_operationPattern_typeExists` | AppProfileAnalyzerTests.swift |
| 4 | `test_failurePattern_typeExists` | AppProfileAnalyzerTests.swift |
| 5 | `test_familiarityTracker_typeExists` | FamiliarityTrackerTests.swift |

## Edge Case Tests (P1)

| # | Test | File |
|---|------|------|
| 1 | `test_analyze_emptyHistory_returnsEmptyProfile` | AppProfileAnalyzerTests.swift |
| 2 | `test_analyze_allFailures_countsCorrectly` | AppProfileAnalyzerTests.swift |
| 3 | `test_analyze_mixedSuccessFailure_countsCorrectly` | AppProfileAnalyzerTests.swift |
| 4 | `test_analyze_ignoresEntriesFromOtherDomains` | AppProfileAnalyzerTests.swift |
| 5 | `test_analyze_axCharacteristics_deduplicatesAcrossRuns` | AppProfileAnalyzerTests.swift |
| 6 | `test_checkAndUpdateFamiliarity_emptyDomain_doesNotMark` | FamiliarityTrackerTests.swift |
| 7 | `test_checkAndUpdateFamiliarity_zeroSuccessfulEntries_doesNotMark` | FamiliarityTrackerTests.swift |
| 8 | `test_checkAndUpdateFamiliarity_familiarEntryHasCorrectTags` | FamiliarityTrackerTests.swift |

## Next Steps (Task-by-Task Activation)

During implementation of each task:

1. Implement the types/methods to make the type existence tests compile
2. Run tests: `swift test --filter "AxionCLITests.Memory"`
3. Verify tests fail first (TDD red), then pass after implementation (green)
4. If any tests still fail unexpectedly:
   - Fix implementation (feature bug)
   - Or fix test (test bug)
5. Commit passing tests

## Implementation Guidance

### Types to Implement

1. **AppProfileAnalyzer** (Sources/AxionCLI/Memory/AppProfileAnalyzer.swift)
   - Pure struct, no MemoryStore dependency
   - `analyze(domain:history:) -> AppProfile`

2. **AppProfile, OperationPattern, FailurePattern** (same file)
   - Runtime-only types, not Codable
   - AppProfile contains: domain, totalRuns, successfulRuns, failedRuns, commonPatterns, knownFailures, axCharacteristics, isFamiliar

3. **FamiliarityTracker** (Sources/AxionCLI/Memory/FamiliarityTracker.swift)
   - Lightweight struct with MemoryStoreProtocol dependency
   - `checkAndUpdateFamiliarity(domain:store:) async throws`

### Existing Files to Modify

1. **AppMemoryExtractor.swift** -- Enhance `extract()` to include AX tree summary, failure markers, workaround inference in content
2. **RunCommand.swift** -- Add Profile analysis + FamiliarityTracker calls after memory extraction

### Run Tests

```bash
swift test --filter "AxionCLITests.Memory"
```

## ATDD Artifacts

- Checklist: `_bmad-output/test-artifacts/atdd-checklist-4-2-app-profile-auto-accumulation.md`
- Unit Tests: `Tests/AxionCLITests/Memory/AppProfileAnalyzerTests.swift`
- Unit Tests: `Tests/AxionCLITests/Memory/FamiliarityTrackerTests.swift`
- Enhanced Tests: `Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift`
