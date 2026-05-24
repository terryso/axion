---
stepsCompleted: ['step-01-load-context', 'step-02-discover-tests', 'step-03-map-criteria', 'step-04-analyze-gaps', 'step-05-gate-decision']
lastStep: 'step-05-gate-decision'
lastSaved: '2026-05-22'
coverageBasis: 'acceptance_criteria'
oracleConfidence: 'high'
oracleResolutionMode: 'formal_requirements'
oracleSources: ['_bmad-output/implementation-artifacts/21-1-experience-extractor-protocol-signal-model.md']
externalPointerStatus: 'not_used'
tempCoverageMatrixPath: '/tmp/tea-trace-coverage-matrix-21-1.json'
---

# Traceability Report: Story 21-1

## Gate Decision: PASS

**Rationale:** P0 coverage is 100%, P1 coverage is 100% (target: 90%), and overall coverage is 100% (minimum: 80%). All 9 acceptance criteria are fully covered by 26 unit tests with zero failures.

---

## Coverage Summary

| Metric | Value |
|--------|-------|
| Total Requirements (ACs) | 9 |
| Fully Covered | 9 (100%) |
| Partially Covered | 0 |
| Uncovered | 0 |
| Total Tests | 26 |
| Test Failures | 0 |

### Priority Coverage

| Priority | Total | Covered | Percentage |
|----------|-------|---------|------------|
| P0 | 9 | 9 | 100% |
| P1 | 0 | n/a | n/a |
| P2 | 0 | n/a | n/a |
| P3 | 0 | n/a | n/a |

---

## Traceability Matrix

### AC1: ExperienceSignal struct (P0)

**Coverage: FULL** | Tests: 9

| Test | File | Line | Coverage Focus |
|------|------|------|----------------|
| testExperienceSignalCreation | ExperienceTypesTests.swift | 28 | Field initialization, id non-empty, metadata |
| testExperienceSignalIdDeterminism | ExperienceTypesTests.swift | 48 | Same input produces same id (djb2) |
| testExperienceSignalDifferentInputsDifferentId | ExperienceTypesTests.swift | 66 | Different domain/content produce different ids |
| testExperienceSignalCodableRoundTrip | ExperienceTypesTests.swift | 92 | Codable serialization/deserialization |
| testExperienceSignalMetadataNil | ExperienceTypesTests.swift | 123 | Nil metadata field |
| testExperienceSignalMetadataPresent | ExperienceTypesTests.swift | 135 | Metadata dictionary with 3 keys |
| testExperienceSignalConfidenceClampingNegative | ExperienceTypesTests.swift | 157 | Negative confidence clamped to 0.0 |
| testExperienceSignalConfidenceClampingAboveOne | ExperienceTypesTests.swift | 168 | >1.0 confidence clamped to 1.0 |
| testExperienceSignalConfidenceZero | ExperienceTypesTests.swift | 179 | Zero confidence preserved |

### AC2: ExperienceSource enum (P0)

**Coverage: FULL** | Tests: 2

| Test | File | Line | Coverage Focus |
|------|------|------|----------------|
| testExperienceSourceRawValues | ExperienceTypesTests.swift | 10 | All 3 raw values (conversation, observation, imported) |
| testExperienceSourceCodableRoundTrip | ExperienceTypesTests.swift | 16 | Codable round-trip for all cases |

### AC3: ExperienceExtractor protocol (P0)

**Coverage: FULL** | Tests: 2 + 1 mock implementation

| Test | File | Line | Coverage Focus |
|------|------|------|----------------|
| testExperienceExtractorProtocolConformance | ExperienceTypesTests.swift | 362 | Mock extract() returns valid ExtractionResult |
| testExperienceExtractorProtocolIsSendable | ExperienceTypesTests.swift | 374 | Protocol requires Sendable, verified via type constraint |
| MockExperienceExtractor (private struct) | ExperienceTypesTests.swift | 384 | Proves protocol is implementable |

### AC4: ExtractionConfig struct (P0)

**Coverage: FULL** | Tests: 4

| Test | File | Line | Coverage Focus |
|------|------|------|----------------|
| testExtractionConfigDefaults | ExperienceTypesTests.swift | 247 | Default anti-patterns non-empty, threshold 0.4, max 10, domain nil |
| testExtractionConfigCustomInit | ExperienceTypesTests.swift | 255 | Custom overrides for all fields |
| testExtractionConfigCodableRoundTrip | ExperienceTypesTests.swift | 269 | Codable serialization round-trip |
| testExtractionConfigEquatable | ExperienceTypesTests.swift | 283 | Equatable (equal and not-equal) |

### AC5: ExtractionResult struct (P0)

**Coverage: FULL** | Tests: 2

| Test | File | Line | Coverage Focus |
|------|------|------|----------------|
| testExtractionResultConstruction | ExperienceTypesTests.swift | 321 | All fields (signals, skippedCount, extractionDate, sourceMessageCount) |
| testExtractionResultEquatable | ExperienceTypesTests.swift | 344 | Equatable conformance |

### AC6: Signal-to-Fact conversion (P0)

**Coverage: FULL** | Tests: 4

| Test | File | Line | Coverage Focus |
|------|------|------|----------------|
| testToFactConversionConversationSource | ExperienceTypesTests.swift | 192 | conversation -> MemoryFactSource.observation |
| testToFactConversionObservationSource | ExperienceTypesTests.swift | 204 | observation -> MemoryFactSource.observation |
| testToFactConversionImportedSource | ExperienceTypesTests.swift | 215 | imported -> MemoryFactSource.imported |
| testToFactMapsFields | ExperienceTypesTests.swift | 228 | status=.candidate, evidenceCount=1, confidence, domain, content, kind |

### AC7: Default anti-pattern list (P0)

**Coverage: FULL** | Tests: 3

| Test | File | Line | Coverage Focus |
|------|------|------|----------------|
| testDefaultAntiPatternKeywordsContainsEnvironmentFailures | ExperienceTypesTests.swift | 294 | "command not found", "not installed" |
| testDefaultAntiPatternKeywordsContainsTransientErrors | ExperienceTypesTests.swift | 303 | "timeout", "temporary failure" |
| testDefaultAntiPatternKeywordsContainsOneOffTaskNarratives | ExperienceTypesTests.swift | 311 | "summarize today's" |

### AC8: Unit tests (P0 - meta-criterion)

**Coverage: FULL** | All 26 tests above satisfy this criterion.

### AC9: Build and test pass (P0)

**Coverage: FULL** | Verified: 26 tests executed, 0 failures, 0 unexpected.

---

## Gaps & Recommendations

### Critical Gaps (P0): 0
None.

### High Gaps (P1): 0
None.

### Coverage Heuristics

| Heuristic | Status |
|-----------|--------|
| Endpoint coverage gaps | N/A (no API endpoints in this story) |
| Auth negative-path gaps | N/A (no auth in this story) |
| Happy-path-only criteria | Present -- boundary/edge-case tests exist for confidence clamping, id determinism, source mapping |
| UI journey gaps | N/A (no UI in this story) |

### Minor Observations

1. **AC7 anti-pattern coverage is selective**: The 3 anti-pattern tests verify representative keywords from each category (environment failures, transient errors, one-off narratives) but do not assert every single keyword in the default list. This is acceptable since the full list is a static constant and the tests verify the categories are present.

2. **AC6 source mapping for `.observation`**: The `toFact()` method maps both `.conversation` and `.observation` to `MemoryFactSource.observation`. This is tested but worth noting as a design decision -- the story spec calls for this behavior.

3. **No test for `ExtractionResult.Codable`**: `ExtractionResult` conforms to `Codable` but there is no Codable round-trip test. Since the type is `Equatable` and `Codable` with all standard Foundation types, this is low risk.

### Recommendations

| Priority | Action |
|----------|--------|
| LOW | Consider adding a Codable round-trip test for `ExtractionResult` for completeness |
| LOW | Run /bmad:tea:test-review to assess test quality |

---

## Gate Criteria

| Criterion | Required | Actual | Status |
|-----------|----------|--------|--------|
| P0 Coverage | 100% | 100% | MET |
| P1 Coverage Target | 90% | N/A (no P1) | MET |
| P1 Coverage Minimum | 80% | N/A (no P1) | MET |
| Overall Coverage | >= 80% | 100% | MET |

---

## Test Inventory

- **Files**: 1 (ExperienceTypesTests.swift)
- **Total test cases**: 26
- **Active**: 26
- **Skipped**: 0
- **Fixme**: 0
- **Pending**: 0
- **By level**: Unit: 26

---

## Oracle Metadata

- **Coverage basis**: acceptance_criteria
- **Oracle resolution mode**: formal_requirements
- **Oracle confidence**: high
- **Oracle sources**: `_bmad-output/implementation-artifacts/21-1-experience-extractor-protocol-signal-model.md`
- **External pointer status**: not_used
