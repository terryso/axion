---
stepsCompleted: ['step-01-preflight-and-context', 'step-02-generation-mode', 'step-03-test-strategy', 'step-04-generate-tests', 'step-05-validate-and-complete']
lastStep: 'step-05-validate-and-complete'
lastSaved: '2026-05-12'
inputDocuments:
  - '_bmad-output/implementation-artifacts/19-1-cross-run-memory-store.md'
  - '_bmad-output/project-context.md'
  - 'Tests/OpenAgentSDKTests/Stores/TodoStoreTests.swift'
  - 'Tests/OpenAgentSDKTests/Stores/SessionStoreTests.swift'
  - 'Sources/OpenAgentSDK/Stores/SessionStore.swift'
  - 'Sources/OpenAgentSDK/Stores/TodoStore.swift'
storyId: '19.1'
storyKey: '19-1-cross-run-memory-store'
storyFile: '_bmad-output/implementation-artifacts/19-1-cross-run-memory-store.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-19-1.md'
generatedTestFiles:
  - 'Tests/OpenAgentSDKTests/Stores/MemoryStoreTests.swift'
communication_language: 'English'
detected_stack: 'backend'
generation_mode: 'ai-generation'
---

# ATDD Checklist: Story 19.1 Cross-run Memory Store

## Story Summary

Story 19.1 provides a cross-run knowledge accumulation store so that all Agent applications can persist and reuse structured experience across multiple executions.

**As a** SDK developer
**I want** the SDK to provide a cross-run knowledge accumulation store
**So that** all Agent applications can persist and reuse structured experience across multiple executions

## Stack Detection

- **Detected stack:** `backend` (Swift Package Manager project, XCTest)
- **Test framework:** XCTest (Swift built-in)
- **Test level:** Unit tests for store operations, type validation, concurrency safety

## Generation Mode

- **Mode:** AI Generation (backend project, no browser testing needed)

## Acceptance Criteria

1. **AC1:** MemoryStoreProtocol defined -- public protocol with save, query, delete, listDomains methods
2. **AC2:** InMemoryStore default implementation -- actor storing knowledge entries by domain
3. **AC3:** FileBasedMemoryStore persistent implementation -- actor persisting to disk by domain
4. **AC4:** Auto-expiry -- entries exceeding maxAge (default 30 days) auto-cleaned on query
5. **AC5:** AgentOptions integration -- memoryStore property on AgentOptions and ToolContext
6. **AC6:** Corrupt entry resilience -- FileBasedMemoryStore skips corrupt files with Logger warning
7. **AC7:** Unit tests -- all store operations covered
8. **AC8:** Build and test pass -- zero errors, zero warnings, all tests pass

## Test Strategy: Acceptance Criteria to Test Mapping

### AC1: MemoryStoreProtocol and Types (7 tests)
| # | Test Scenario | Level | Priority | Status |
|---|---|---|---|---|
| 1 | KnowledgeEntry construction with all fields | Unit | P0 | **FAIL (RED)** |
| 2 | KnowledgeEntry Equatable conformance | Unit | P0 | **FAIL (RED)** |
| 3 | KnowledgeEntry Sendable conformance | Unit | P0 | **FAIL (RED)** |
| 4 | KnowledgeEntry with nil sourceRunId | Unit | P0 | **FAIL (RED)** |
| 5 | KnowledgeQueryFilter default construction | Unit | P0 | **FAIL (RED)** |
| 6 | KnowledgeQueryFilter Equatable conformance | Unit | P0 | **FAIL (RED)** |
| 7 | MemoryStoreProtocol is Sendable | Unit | P0 | **FAIL (RED)** |

### AC2: InMemoryStore -- Save, Query, Delete, listDomains (14 tests)
| # | Test Scenario | Level | Priority | Status |
|---|---|---|---|---|
| 1 | InMemoryStore default init | Unit | P0 | **FAIL (RED)** |
| 2 | Save and query back | Unit | P0 | **FAIL (RED)** |
| 3 | Save appends multiple entries to same domain | Unit | P0 | **FAIL (RED)** |
| 4 | Save stores entries in separate domains | Unit | P0 | **FAIL (RED)** |
| 5 | Query with nil filter returns all | Unit | P0 | **FAIL (RED)** |
| 6 | Query with tag filter | Unit | P0 | **FAIL (RED)** |
| 7 | Query with date range filter | Unit | P0 | **FAIL (RED)** |
| 8 | Query with limit | Unit | P1 | **FAIL (RED)** |
| 9 | Query on non-existent domain returns empty | Unit | P0 | **FAIL (RED)** |
| 10 | Delete removes entries older than date | Unit | P0 | **FAIL (RED)** |
| 11 | Delete on empty domain returns 0 | Unit | P0 | **FAIL (RED)** |
| 12 | listDomains returns sorted names | Unit | P0 | **FAIL (RED)** |
| 13 | listDomains returns empty for fresh store | Unit | P0 | **FAIL (RED)** |
| 14 | Concurrent access safety (actor isolation) | Unit | P0 | **FAIL (RED)** |

### AC3: FileBasedMemoryStore -- Persistence, Query, Delete, listDomains (14 tests)
| # | Test Scenario | Level | Priority | Status |
|---|---|---|---|---|
| 1 | Init with custom directory | Unit | P0 | **FAIL (RED)** |
| 2 | Save creates domain JSON file | Unit | P0 | **FAIL (RED)** |
| 3 | Save file has 0600 permissions | Unit | P0 | **FAIL (RED)** |
| 4 | Directory has 0700 permissions | Unit | P0 | **FAIL (RED)** |
| 5 | Persistence across instances | Unit | P0 | **FAIL (RED)** |
| 6 | Loads multiple domains on init | Unit | P0 | **FAIL (RED)** |
| 7 | Query returns cached entries | Unit | P0 | **FAIL (RED)** |
| 8 | Delete rewrites file | Unit | P0 | **FAIL (RED)** |
| 9 | Delete removes file when empty | Unit | P0 | **FAIL (RED)** |
| 10 | listDomains returns sorted | Unit | P0 | **FAIL (RED)** |
| 11 | Empty domain name throws | Unit | P0 | **FAIL (RED)** |
| 12 | Path traversal ".." throws | Unit | P0 | **FAIL (RED)** |
| 13 | Slash in domain throws | Unit | P0 | **FAIL (RED)** |
| 14 | Backslash in domain throws | Unit | P0 | **FAIL (RED)** |

### AC4: Auto-Expiry (4 tests)
| # | Test Scenario | Level | Priority | Status |
|---|---|---|---|---|
| 1 | InMemoryStore auto-expires old entries | Unit | P0 | **FAIL (RED)** |
| 2 | InMemoryStore no expiry within maxAge | Unit | P0 | **FAIL (RED)** |
| 3 | InMemoryStore default maxAge is 30 days | Unit | P1 | **FAIL (RED)** |
| 4 | FileBasedMemoryStore auto-expires | Unit | P0 | **FAIL (RED)** |

### AC5: AgentOptions / ToolContext Integration (4 tests)
| # | Test Scenario | Level | Priority | Status |
|---|---|---|---|---|
| 1 | AgentOptions has memoryStore property (nil default) | Unit | P0 | **FAIL (RED)** |
| 2 | AgentOptions init with memoryStore | Unit | P0 | **FAIL (RED)** |
| 3 | ToolContext has memoryStore field | Unit | P0 | **FAIL (RED)** |
| 4 | ToolContext.withToolUseId preserves memoryStore | Unit | P0 | **FAIL (RED)** |

### AC6: Corrupt Entry Resilience (2 tests)
| # | Test Scenario | Level | Priority | Status |
|---|---|---|---|---|
| 1 | Corrupt JSON file skipped without crash | Unit | P0 | **FAIL (RED)** |
| 2 | Empty JSON array file handled gracefully | Unit | P0 | **FAIL (RED)** |

### Additional: FileBasedMemoryStore defaults (2 tests)
| # | Test Scenario | Level | Priority | Status |
|---|---|---|---|---|
| 1 | FileBasedMemoryStore default maxAge is 30 days | Unit | P1 | **FAIL (RED)** |
| 2 | Concurrent saves without data loss | Unit | P0 | **FAIL (RED)** |

## TDD Red Phase Status

**RED PHASE CONFIRMED:** All 47 tests fail at compilation stage due to missing types:
- `KnowledgeEntry` -- not defined yet
- `KnowledgeQueryFilter` -- not defined yet
- `MemoryStoreProtocol` -- not defined yet
- `InMemoryStore` -- not defined yet
- `FileBasedMemoryStore` -- not defined yet
- `ToolContext.memoryStore` -- field not added yet
- `AgentOptions.memoryStore` -- property not added yet

Build command `swift build --build-tests` produces compilation errors confirming all tests are in RED phase.

## Implementation Checklist

### Task 1: Define Types (AC1)
- [ ] Create `Sources/OpenAgentSDK/Types/MemoryTypes.swift`
- [ ] Define `KnowledgeEntry` struct (Sendable, Equatable)
- [ ] Define `KnowledgeQueryFilter` struct (Sendable, Equatable)
- [ ] Define `MemoryStoreProtocol` (Sendable)

### Task 2: Implement InMemoryStore (AC2)
- [ ] Create `Sources/OpenAgentSDK/Stores/MemoryStore.swift`
- [ ] Implement `InMemoryStore` actor with maxAge property
- [ ] Implement save, query, delete, listDomains

### Task 3: Implement FileBasedMemoryStore (AC3, AC6)
- [ ] Add `FileBasedMemoryStore` actor in same file
- [ ] Implement disk persistence with JSONSerialization
- [ ] Add domain name validation
- [ ] Handle corrupt files with Logger warning

### Task 4: Auto-Expiry (AC4)
- [ ] Add maxAge to both implementations
- [ ] Filter expired entries on query

### Task 5: Integration (AC5)
- [ ] Add memoryStore to AgentOptions
- [ ] Add memoryStore to ToolContext
- [ ] Update withToolUseId() and withSkillContext()
- [ ] Update ToolContext construction sites in Agent.swift

### Task 6: Build Verification (AC7, AC8)
- [ ] `swift build` zero errors zero warnings
- [ ] All tests pass
- [ ] Run full test suite, report total count

## Summary

| Metric | Count |
|---|---|
| Total tests | 47 |
| AC1 (Types) | 7 |
| AC2 (InMemoryStore) | 14 |
| AC3 (FileBasedMemoryStore) | 14 |
| AC4 (Auto-Expiry) | 4 |
| AC5 (Integration) | 4 |
| AC6 (Corrupt Resilience) | 2 |
| Additional (defaults) | 2 |
| P0 tests | 39 |
| P1 tests | 8 |
| Test file | `Tests/OpenAgentSDKTests/Stores/MemoryStoreTests.swift` |

## Next Steps

1. Implement Task 1 (Types) to resolve compilation errors for KnowledgeEntry, KnowledgeQueryFilter, MemoryStoreProtocol
2. Implement Task 2 (InMemoryStore) to resolve actor tests
3. Implement Task 3 (FileBasedMemoryStore) to resolve persistence tests
4. Implement Task 4 (Auto-Expiry) to resolve expiry tests
5. Implement Task 5 (Integration) to resolve AgentOptions/ToolContext tests
6. Run `swift build --build-tests` to verify compilation passes
7. Run `swift test` to verify all 47 tests pass (GREEN phase)
8. Run full test suite and report total count
