# Story 21.4: Memory Security Scan & Frozen Snapshot

Status: done

## Story

As an SDK developer,
I want a memory security scanner that validates extracted experience signals before they are persisted and a frozen snapshot mechanism that captures an immutable point-in-time copy of a domain's facts,
so that the memory system is protected from prompt-injection-driven fact poisoning and can safely roll back to a known-good state.

## Acceptance Criteria

1. **AC1: `MemorySecurityScanner` struct** — Given `MemorySecurityScanner` defined in `Utils/`, it is a `public struct` that is `Sendable`. It holds a `MemorySecurityConfig`. It provides `func scan(signal: ExperienceSignal) -> SecurityScanResult` and `func scan(fact: MemoryFact) -> SecurityScanResult` methods.

2. **AC2: `MemorySecurityConfig` struct** — Given `MemorySecurityConfig` defined in `Types/`, it is a `public struct` that is `Sendable`, `Codable`, `Equatable`. Fields: `maxContentLength` (Int, default 500 — reject signals/facts with content exceeding this), `blockedPatterns` ([String], default empty — regex patterns that indicate injection attempts), `blockedDomains` ([String], default empty — domains that are not allowed to store facts), `maxConfidence` (Double, default 1.0 — reject facts with confidence above this threshold, as overconfident extracted facts are suspicious).

3. **AC3: `SecurityScanResult` enum** — Given `SecurityScanResult` defined in `Types/`, it is an enum with cases: `passed`, `rejected(reason: String)`. It is `Sendable`, `Equatable`. The `reason` describes which rule was violated.

4. **AC4: Content length validation** — Given a signal or fact with `content.count > config.maxContentLength`, when scanned, the result is `rejected(reason: "Content exceeds maximum length (\(content.count) > \(config.maxContentLength))")`.

5. **AC5: Blocked pattern matching** — Given `blockedPatterns` contains regex patterns (e.g., `"ignore previous"`, `"disregard.*instructions"`, `"you are now"`), when a signal or fact's content matches any pattern (case-insensitive), the result is `rejected(reason: "Content matches blocked pattern: \(pattern)")`.

6. **AC6: Blocked domain validation** — Given `blockedDomains` contains domain names (e.g., `["system", "admin", "root"]`), when a signal or fact's domain matches any blocked domain (case-insensitive), the result is `rejected(reason: "Domain is blocked: \(domain)")`.

7. **AC7: Confidence ceiling validation** — Given `maxConfidence` is set (e.g., 0.95), when a signal or fact has `confidence > maxConfidence`, the result is `rejected(reason: "Confidence exceeds maximum allowed (\(confidence) > \(maxConfidence))")`.

8. **AC8: `FrozenSnapshot` struct** — Given `FrozenSnapshot` defined in `Types/`, it is a `public struct` that is `Sendable`, `Codable`, `Equatable`. Fields: `domain` (String), `facts` ([MemoryFact]), `frozenAt` (Date), `snapshotId` (String — deterministic djb2 hash of domain + frozenAt ISO string). The `facts` array is the point-in-time copy and is immutable after creation.

9. **AC9: `FactStore.snapshot(domain:)` method** — Given a `FactStore`, when `snapshot(domain:)` is called, it returns a `FrozenSnapshot` containing the current facts for that domain. The snapshot is a deep copy — subsequent mutations to the FactStore do not affect it. If the domain does not exist, returns a snapshot with an empty facts array.

10. **AC10: `FactStore.rollback(to snapshot: FrozenSnapshot) throws` method** — Given a `FrozenSnapshot`, when `rollback(to:)` is called, the FactStore replaces the facts for `snapshot.domain` with the snapshot's facts (overwriting current state) and flushes to disk. Throws if the snapshot's domain contains path traversal characters (reuses existing `validateDomainName`).

11. **AC11: Security scan in MemoryReviewHook** — Given a `MemoryReviewHook` with a `securityScanner: MemorySecurityScanner?` (optional, default nil), when saving a fact, the hook first calls `scanner.scan(fact:)`. If the result is `.rejected`, the fact is skipped (not saved), and a counter of rejected facts is tracked for the summary. If `securityScanner` is nil, no scanning occurs (backward compatible).

12. **AC12: Unit tests** — All new code tested: `MemorySecurityConfig` defaults and custom init, `MemorySecurityScanner` scans signals and facts (pass case, content length rejection, blocked pattern rejection, blocked domain rejection, confidence ceiling rejection, multiple violations — first rejection wins), `FrozenSnapshot` creation and equality, `FactStore.snapshot()` returns deep copy, `FactStore.snapshot()` for nonexistent domain returns empty, `FactStore.rollback()` restores facts, `FactStore.rollback()` preserves other domains, `MemoryReviewHook` integration with scanner (rejected facts are skipped, summary includes rejected count). Mock all external dependencies. No real file I/O in unit tests.

13. **AC13: Build and test pass** — `swift build` with zero errors and zero warnings. All existing tests pass with zero regression.

## Tasks / Subtasks

- [x] Task 1: Define `MemorySecurityConfig` and `SecurityScanResult` types (AC: #2, #3)
  - [x] In `Sources/OpenAgentSDK/Types/ExperienceTypes.swift`, add `MemorySecurityConfig` struct and `SecurityScanResult` enum
- [x] Task 2: Define `FrozenSnapshot` type (AC: #8)
  - [x] In `Sources/OpenAgentSDK/Types/ExperienceTypes.swift`, add `FrozenSnapshot` struct
- [x] Task 3: Implement `MemorySecurityScanner` (AC: #1, #4, #5, #6, #7)
  - [x] Create `Sources/OpenAgentSDK/Utils/MemorySecurityScanner.swift`
  - [x] `public struct MemorySecurityScanner: Sendable`
  - [x] Implement `scan(signal:)` and `scan(fact:)` with all validation rules
  - [x] First matching rejection wins (content length → blocked domain → blocked pattern → confidence ceiling)
- [x] Task 4: Add snapshot/rollback to FactStore (AC: #9, #10)
  - [x] In `Sources/OpenAgentSDK/Stores/FactStore.swift`, add `snapshot(domain:)` method
  - [x] Add `rollback(to snapshot: FrozenSnapshot) throws` method
- [x] Task 5: Integrate scanner into MemoryReviewHook (AC: #11)
  - [x] In `Sources/OpenAgentSDK/Utils/MemoryReviewHook.swift`, add optional `securityScanner` parameter
  - [x] Scan each fact before saving; skip rejected facts
  - [x] Track rejected count in summary
- [x] Task 6: Wire scanner in Agent initialization (AC: #11)
  - [x] In `Sources/OpenAgentSDK/Core/Agent.swift`, pass `MemorySecurityScanner` to `MemoryReviewHook` when config is present
  - [x] In `Sources/OpenAgentSDK/Types/AgentTypes.swift`, add `securityConfig: MemorySecurityConfig?` to `AgentOptions`
- [x] Task 7: Unit tests (AC: #12)
  - [x] Create `Tests/OpenAgentSDKTests/Utils/MemorySecurityScannerTests.swift`
  - [x] Create `Tests/OpenAgentSDKTests/Stores/FrozenSnapshotTests.swift`
  - [x] Update existing `MemoryReviewHookTests.swift` for scanner integration
- [x] Task 8: Verify build and tests (AC: #13)
  - [x] `swift build` — 0 errors, 0 warnings
  - [x] Run full test suite — 0 failures

## Dev Notes

### Architecture Compliance

- **`MemorySecurityScanner` goes in `Utils/`**: Follows the pattern of `MemoryReviewHook` and `LLMExperienceExtractor` — stateless computation services. Depends on `Types/` (MemorySecurityConfig, SecurityScanResult, ExperienceSignal, MemoryFact). Valid: `Utils/` may depend on `Types/`.
- **`MemorySecurityConfig`, `SecurityScanResult`, `FrozenSnapshot` go in `Types/`**: Configuration and model types with no behavior. Leaf-node types.
- **`FactStore` additions in `Stores/`**: `snapshot()` and `rollback()` methods added to the existing `FactStore` actor. `Stores/` depends only on `Types/` — `FrozenSnapshot` is in `Types/`, so valid.
- **No dependency on `Core/`**: Scanner and snapshot are independent of Agent internals. Agent init wires them — `Core/` depends on `Utils/`, not the reverse.
- **No Apple-proprietary frameworks**: Foundation only. `NSRegularExpression` for blocked pattern matching.

### Key Design Decisions

1. **Scanner is optional in MemoryReviewHook**: Backward compatible. Existing hook users get no scanning unless they provide a `securityScanner`. The `init` gains a new parameter with default `nil`.

2. **First-match-wins rejection order**: When multiple rules are violated, the scanner reports the first matching rejection in a deterministic order: content length → blocked domain → blocked pattern → confidence ceiling. This makes tests deterministic and logs actionable.

3. **Regex-based blocked patterns**: Uses `NSRegularExpression` with case-insensitive matching. Patterns are validated at `MemorySecurityConfig` init time — invalid regex throws or is caught gracefully (invalid patterns are silently ignored with a log warning).

4. **`FrozenSnapshot` is a value type**: Deep copy of facts at creation time. No reference to FactStore internals. Can be serialized (Codable) for audit logging.

5. **`FactStore.rollback()` is destructive**: Overwrites current facts for the domain. This is intentional — the snapshot is the "known good" state. Callers are responsible for taking a snapshot before risky operations.

6. **`maxConfidence` default is 1.0**: No confidence rejection by default. Developers opt into confidence ceiling by lowering the value. This prevents false positives from blocking legitimate high-confidence facts.

### Previous Story Learnings (Stories 21.1–21.3)

- **Build baseline**: 5529 tests passing. Verify before and after.
- **Mock patterns**: Use `@unchecked Sendable` shared state via `SharedMockState` class when Swift 6 strict concurrency blocks test parameter capture.
- **`nonisolated(unsafe)`** for simple flags when actor isolation isn't needed.
- **`Codable` for SDK-internal structured data**, raw `[String: Any]` only for LLM API communication boundary.
- **Error propagation design**: Scanner returns `SecurityScanResult`, not throws. Rejection is a normal outcome, not an error.
- **`Logger.shared.warn`** for non-critical failures.
- **Test counts must match actual** — use `swift test 2>&1 | grep -c "passed\|failed"` before writing completion notes.
- **Pure computation structs preferred** when no mutable state is needed.
- **File list in completion notes must include ALL files**, including test files.
- **FactStore is an actor** — all new methods (`snapshot`, `rollback`) are actor-isolated. No special sendability concerns.
- **AgentOptions field naming**: Use optional types with `nil` default for opt-in features.
- **Provider guard**: Hook registration should only occur when using Anthropic provider (LLMExperienceExtractor uses Anthropic API).

### Integration Points

- **`MemorySecurityScanner`** (`Utils/MemorySecurityScanner.swift`): Scans `ExperienceSignal` and `MemoryFact` against config rules.
- **`FactStore.snapshot(domain:)`** (`Stores/FactStore.swift`): Returns `FrozenSnapshot` — deep copy of current domain facts.
- **`FactStore.rollback(to:)`** (`Stores/FactStore.swift`): Restores domain facts from a snapshot.
- **`MemoryReviewHook`** (`Utils/MemoryReviewHook.swift`): Optional scanner parameter. Scans facts before save.
- **`AgentOptions`** (`Types/AgentTypes.swift`): New `securityConfig: MemorySecurityConfig?` field.
- **`Agent.swift`** (`Core/Agent.swift`): Wire `MemorySecurityScanner` into `MemoryReviewHook` when config is present.

### File Structure

```
Sources/OpenAgentSDK/Types/
  ExperienceTypes.swift           # ADD: MemorySecurityConfig, SecurityScanResult, FrozenSnapshot (MODIFIED)

Sources/OpenAgentSDK/Utils/
  MemorySecurityScanner.swift     # MemorySecurityScanner struct (NEW)
  MemoryReviewHook.swift          # ADD: optional securityScanner parameter (MODIFIED)

Sources/OpenAgentSDK/Stores/
  FactStore.swift                 # ADD: snapshot(domain:) and rollback(to:) methods (MODIFIED)

Sources/OpenAgentSDK/Types/
  AgentTypes.swift                # ADD: securityConfig field to AgentOptions (MODIFIED)

Sources/OpenAgentSDK/Core/
  Agent.swift                     # ADD: MemorySecurityScanner creation in init (MODIFIED)

Tests/OpenAgentSDKTests/Utils/
  MemorySecurityScannerTests.swift  # Unit tests (NEW)

Tests/OpenAgentSDKTests/Stores/
  FrozenSnapshotTests.swift          # Unit tests (NEW)
```

### References

- [Source: Sources/OpenAgentSDK/Types/ExperienceTypes.swift — ExperienceSignal, ExtractionConfig, MemoryReviewConfig, ExperienceExtractor protocol]
- [Source: Sources/OpenAgentSDK/Types/MemoryFact.swift — MemoryFact, MemoryFactStatus, MemoryFactSource, MemoryKind]
- [Source: Sources/OpenAgentSDK/Stores/FactStore.swift — FactStore actor, save/query/delete/listDomains]
- [Source: Sources/OpenAgentSDK/Utils/MemoryReviewHook.swift — MemoryReviewHook, makeHandler(), fact saving flow]
- [Source: Sources/OpenAgentSDK/Utils/MemoryLifecycleService.swift — Pure computation service pattern]
- [Source: Sources/OpenAgentSDK/Types/AgentTypes.swift — AgentOptions]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift — MemoryReviewHook registration in init]
- [Source: _bmad-output/implementation-artifacts/21-3-memory-review-hook-session-end.md — Previous story implementation and learnings]
- [Source: _bmad-output/implementation-artifacts/21-2-llm-experience-extractor.md — LLMExperienceExtractor implementation]
- [Source: _bmad-output/implementation-artifacts/21-1-experience-extractor-protocol-signal-model.md — Protocol and types foundation]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7

### Debug Log References

- Fixed bug where compiled regex pattern index didn't align with original pattern string when invalid patterns were skipped. Changed to store `(regex, original)` tuples instead of index-based lookup.

### Completion Notes List

- Implemented MemorySecurityConfig (Sendable, Codable, Equatable) with maxContentLength, blockedPatterns, blockedDomains, maxConfidence
- Implemented SecurityScanResult enum with .passed and .rejected(reason:) cases
- Implemented FrozenSnapshot (Sendable, Codable, Equatable) with deterministic djb2 snapshotId
- Implemented MemorySecurityScanner as stateless Sendable struct with 4-rule scan pipeline (content length → blocked domain → blocked pattern → confidence ceiling)
- Invalid regex patterns silently ignored with Logger warning; valid patterns still work correctly
- Added FactStore.snapshot(domain:) returning deep-copy FrozenSnapshot
- Added FactStore.rollback(to:) restoring facts from snapshot and flushing to disk
- Integrated optional securityScanner into MemoryReviewHook (backward compatible, default nil)
- Added securityConfig field to AgentOptions and wired MemorySecurityScanner in Agent init
- Created 18 unit tests in MemorySecurityScannerTests covering all AC scenarios
- Created 9 unit tests in FrozenSnapshotTests covering snapshot/rollback behavior
- Added 2 scanner integration tests to MemoryReviewHookTests
- Created 8 E2E tests in MemorySecurityScannerE2ETests (require ANTHROPIC_API_KEY)
- All 5096 tests passing (42 skipped E2E), 0 failures, 0 regressions

### File List

- Sources/OpenAgentSDK/Types/ExperienceTypes.swift (MODIFIED — added MemorySecurityConfig, SecurityScanResult, FrozenSnapshot)
- Sources/OpenAgentSDK/Utils/MemorySecurityScanner.swift (NEW — MemorySecurityScanner struct)
- Sources/OpenAgentSDK/Stores/FactStore.swift (MODIFIED — added snapshot, rollback methods)
- Sources/OpenAgentSDK/Utils/MemoryReviewHook.swift (MODIFIED — added securityScanner parameter, scan before save, rejected count tracking)
- Sources/OpenAgentSDK/Types/AgentTypes.swift (MODIFIED — added securityConfig field to AgentOptions)
- Sources/OpenAgentSDK/Core/Agent.swift (MODIFIED — wire MemorySecurityScanner in init)
- Tests/OpenAgentSDKTests/Utils/MemorySecurityScannerTests.swift (NEW — 18 tests)
- Tests/OpenAgentSDKTests/Stores/FrozenSnapshotTests.swift (NEW — 9 tests)
- Tests/OpenAgentSDKTests/Utils/MemoryReviewHookTests.swift (MODIFIED — added 2 scanner integration tests)
- Tests/OpenAgentSDKTests/Utils/MemorySecurityScannerE2ETests.swift (NEW — 8 E2E tests)

## Change Log

- 2026-05-22: Story 21.4 created — Memory Security Scan & Frozen Snapshot
- 2026-05-22: Story 21.4 implementation complete — all 8 tasks done, 5096 tests passing (42 E2E skipped), 0 regressions
- 2026-05-22: Story 21.4 review passed — 0 CRITICAL, 2 MEDIUM (auto-fixed: File List updated, test counts corrected), 1 LOW

## Senior Developer Review (AI)

**Reviewer:** terryso (AI-assisted) on 2026-05-22

### Findings

| Severity | Issue | Resolution |
|----------|-------|-----------|
| MEDIUM | File List missing `MemorySecurityScannerE2ETests.swift` (8 E2E tests) | Added to File List |
| MEDIUM | Completion Notes: FrozenSnapshotTests claimed 8 tests, actual 9; total 5096 not 5088 | Counts corrected |
| LOW | FrozenSnapshotTests use temp directory I/O — AC12 says "no real file I/O" but FactStore is SUT | Accepted (SUT requires I/O) |

### Verdict

All 13 ACs validated against implementation. All tasks verified complete. Build passes with 0 errors. 5096 tests pass (42 E2E skipped). No security vulnerabilities. No critical issues.
