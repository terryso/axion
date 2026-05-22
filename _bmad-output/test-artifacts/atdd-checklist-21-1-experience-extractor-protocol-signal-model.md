---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: 'step-05-validate-and-complete'
lastSaved: '2026-05-22'
storyId: '21.1'
storyKey: '21-1-experience-extractor-protocol-signal-model'
storyFile: '_bmad-output/implementation-artifacts/21-1-experience-extractor-protocol-signal-model.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-21-1-experience-extractor-protocol-signal-model.md'
generatedTestFiles:
  - 'Tests/OpenAgentSDKTests/Types/ExperienceTypesTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/21-1-experience-extractor-protocol-signal-model.md'
  - '_bmad-output/project-context.md'
  - 'Sources/OpenAgentSDK/Types/MemoryFact.swift'
  - 'Sources/OpenAgentSDK/Types/MemoryTypes.swift'
  - 'Sources/OpenAgentSDK/Types/SDKMessage.swift'
  - 'Tests/OpenAgentSDKTests/Types/MemoryFactTests.swift'
---

# ATDD Checklist: Story 21.1 — ExperienceExtractor Protocol & Signal Model

## Stack Detection

- **Detected Stack**: `backend` (Swift SPM project, XCTest framework, no frontend/browser dependencies)
- **Test Framework**: XCTest (Swift built-in)
- **Execution Mode**: Sequential (single-agent, no subagent orchestration needed for backend-only unit tests)

---

## TDD Red Phase (Current)

Red-phase test scaffolds generated. All tests use `try XCTSkipIf(true, "RED: awaiting implementation")` to skip until the feature is implemented.

- **Unit Tests**: 26 test methods (all skipped)
- **E2E/API Tests**: N/A — purely additive Types/ story with no I/O or endpoints

---

## Acceptance Criteria Coverage

| AC | Description | Test Methods | Priority |
|----|-------------|-------------|----------|
| AC1 | `ExperienceSignal` struct (Sendable, Codable, Equatable, fields, djb2 id) | testExperienceSignalCreation, testExperienceSignalIdDeterminism, testExperienceSignalDifferentInputsDifferentId, testExperienceSignalCodableRoundTrip, testExperienceSignalMetadataNil, testExperienceSignalMetadataPresent | P0 |
| AC2 | `ExperienceSource` enum (raw values, cases) | testExperienceSourceRawValues, testExperienceSourceCodableRoundTrip | P0 |
| AC3 | `ExperienceExtractor` protocol (Sendable, method signature, no Core/Tools deps) | testExperienceExtractorProtocolConformance, testExperienceExtractorProtocolIsSendable | P0 |
| AC4 | `ExtractionConfig` struct (defaults, custom init, Codable, Equatable) | testExtractionConfigDefaults, testExtractionConfigCustomInit, testExtractionConfigCodableRoundTrip, testExtractionConfigEquatable | P0 |
| AC5 | `ExtractionResult` struct (fields, Equatable) | testExtractionResultConstruction, testExtractionResultEquatable | P0 |
| AC6 | `ExperienceSignal.toFact()` conversion (status, confidence, source mapping) | testToFactConversionConversationSource, testToFactConversionObservationSource, testToFactConversionImportedSource, testToFactMapsFields | P0 |
| AC7 | `ExtractionConfig` default anti-pattern list (Hermes research keywords) | testDefaultAntiPatternKeywordsContainsEnvironmentFailures, testDefaultAntiPatternKeywordsContainsTransientErrors, testDefaultAntiPatternKeywordsContainsOneOffTaskNarratives | P0 |
| AC8 | Unit tests (all new types tested, mock extractor) | All tests above | P0 |
| AC9 | Build and test pass | Verified by `swift build` and full test suite | P0 |

---

## Test Strategy

### Test Level Selection

Since this is a **backend** story defining pure data types and a protocol in `Types/`:

- **Unit tests only** — all types are value types (struct/enum/protocol) with no I/O, no network, no LLM calls
- **No E2E tests** — no endpoints, no HTTP handlers, no browser interaction
- **No integration tests** — no actor stores or external dependencies modified

### Test Priority Matrix

| Priority | Count | Rationale |
|----------|-------|-----------|
| P0 | 26 | All tests are critical — types and protocol form the foundation for Stories 21.2-21.4 |
| P1 | 0 | No secondary scenarios (pure types, no edge-case paths beyond confidence clamping) |
| P2 | 0 | No performance or stress tests needed |
| P3 | 0 | No optional/nice-to-have scenarios |

---

## Test File

**File**: `Tests/OpenAgentSDKTests/Types/ExperienceTypesTests.swift`

### Test Methods (26 total)

1. **ExperienceSource enum** (2 tests)
   - `testExperienceSourceRawValues` — verifies all three raw values
   - `testExperienceSourceCodableRoundTrip` — Codable round-trip for each case

2. **ExperienceSignal struct** (6 tests)
   - `testExperienceSignalCreation` — factory method produces correct fields
   - `testExperienceSignalIdDeterminism` — same input = same id
   - `testExperienceSignalDifferentInputsDifferentId` — different domain/content = different id
   - `testExperienceSignalCodableRoundTrip` — encode/decode symmetry
   - `testExperienceSignalMetadataNil` — nil metadata works
   - `testExperienceSignalMetadataPresent` — metadata dictionary preserved

3. **ExperienceSignal.toFact()** (4 tests)
   - `testToFactConversionConversationSource` — conversation -> .observation
   - `testToFactConversionObservationSource` — observation -> .observation
   - `testToFactConversionImportedSource` — imported -> .imported
   - `testToFactMapsFields` — status=.candidate, evidenceCount=1, confidence preserved, kind preserved

4. **ExtractionConfig struct** (4 tests)
   - `testExtractionConfigDefaults` — default anti-patterns non-empty, threshold=0.4, max=10
   - `testExtractionConfigCustomInit` — custom values override defaults
   - `testExtractionConfigCodableRoundTrip` — Codable symmetry
   - `testExtractionConfigEquatable` — equal configs are equal, different configs are not

5. **ExtractionConfig anti-pattern defaults** (3 tests)
   - `testDefaultAntiPatternKeywordsContainsEnvironmentFailures` — "command not found", "not installed"
   - `testDefaultAntiPatternKeywordsContainsTransientErrors` — "timeout", "temporary failure"
   - `testDefaultAntiPatternKeywordsContainsOneOffTaskNarratives` — "summarize today's"

6. **ExtractionResult struct** (2 tests)
   - `testExtractionResultConstruction` — all fields set correctly
   - `testExtractionResultEquatable` — equality semantics

7. **ExperienceExtractor protocol** (2 tests)
   - `testExperienceExtractorProtocolConformance` — mock implementation compiles and returns correct result
   - `testExperienceExtractorProtocolIsSendable` — protocol can be used as Sendable constraint

8. **Edge cases** (3 tests)
   - `testExperienceSignalConfidenceClampingNegative` — negative clamped to 0
   - `testExperienceSignalConfidenceClampingAboveOne` — >1.0 clamped to 1.0
   - `testExperienceSignalConfidenceZero` — 0.0 stays 0.0

---

## Red Phase Skip Pattern

Since Swift compiles all test files together and the production types don't exist yet, the entire test file is wrapped in a **conditional compilation guard**:

```swift
#if EXPERIENCE_TYPES_IMPLEMENTED
  // ... all test code ...
#endif
```

### Activation Steps During Implementation

1. Create `Sources/OpenAgentSDK/Types/ExperienceTypes.swift` with the required types
2. Remove the `#if EXPERIENCE_TYPES_IMPLEMENTED` / `#endif` guards from the test file
3. Inside each test method, remove the `try XCTSkipIf(true, "RED: ...")` line
4. Run: `swift test --filter ExperienceTypesTests`
5. Verify each activated test **fails** before the corresponding implementation code is written, then **passes** after

The inner `try XCTSkipIf(true, ...)` calls provide a second layer of red-phase control for fine-grained task-by-task activation during implementation.

---

## Implementation Guidance

### Files to Create (during dev)

1. `Sources/OpenAgentSDK/Types/ExperienceTypes.swift` — All new types: ExperienceSource, ExperienceSignal, ExtractionConfig, ExtractionResult, ExperienceExtractor

### Integration Points

- `MemoryFact.swift` — `toFact()` creates `MemoryFact` via `MemoryFact.create()`
- `SDKMessage.swift` — `ExperienceExtractor.extract()` takes `[SDKMessage]`
- `MemoryTypes.swift` — Pattern reference for protocol-in-Types/

---

## Next Steps (Task-by-Task Activation)

**Step 1**: Create `Sources/OpenAgentSDK/Types/ExperienceTypes.swift` with stub types (empty structs/enums with correct signatures).

**Step 2**: Remove the `#if EXPERIENCE_TYPES_IMPLEMENTED` / `#endif` guards from `ExperienceTypesTests.swift`.

**Step 3**: For each task in the story:

1. Remove `try XCTSkipIf(true, ...)` from the current test method(s)
2. Run tests: `swift test --filter ExperienceTypesTests`
3. Verify the activated test **fails first** (red), then **passes** after writing the implementation (green)
4. If any activated tests still fail unexpectedly:
   - Either fix implementation (feature bug)
   - Or fix test (test bug)
5. Commit passing tests

**Step 4**: After all tests pass, run the full test suite to confirm zero regressions.

---

## ATDD Artifacts

- **Checklist**: `_bmad-output/test-artifacts/atdd-checklist-21-1-experience-extractor-protocol-signal-model.md`
- **Unit Tests**: `Tests/OpenAgentSDKTests/Types/ExperienceTypesTests.swift`
- **E2E Tests**: N/A (backend-only, pure Types/ story)
- **Story File**: `_bmad-output/implementation-artifacts/21-1-experience-extractor-protocol-signal-model.md`
