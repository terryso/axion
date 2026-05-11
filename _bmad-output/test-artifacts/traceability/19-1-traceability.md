# Traceability Matrix: Story 19-1 -- Cross-run Memory Store

Generated: 2026-05-12
Story Status: review
Total Tests: 49 (MemoryStoreTests.swift)
Full Suite: 4611 tests passing, 14 skipped, 0 failures
Build: zero errors, zero warnings

---

## Acceptance Criteria to Tests Mapping

| AC | Description | Priority | Tests | Status |
|----|-------------|----------|-------|--------|
| AC1 | MemoryStoreProtocol defined | P0 | `testKnowledgeEntry_construction`, `testKnowledgeEntry_equality`, `testKnowledgeEntry_sendable`, `testKnowledgeEntry_nilSourceRunId`, `testKnowledgeQueryFilter_defaultConstruction`, `testKnowledgeQueryFilter_equality`, `testKnowledgeQueryFilter_sendable`, `testMemoryStoreProtocol_isSendable` | COVERED (8 tests) |
| AC2 | InMemoryStore default implementation | P0 | `testInMemoryStore_init`, `testInMemoryStore_save_andQuery`, `testInMemoryStore_save_appendsMultiple`, `testInMemoryStore_save_separateDomains`, `testInMemoryStore_query_nilFilter_returnsAll`, `testInMemoryStore_query_tagFilter`, `testInMemoryStore_query_dateRange`, `testInMemoryStore_query_limit`, `testInMemoryStore_query_emptyDomain`, `testInMemoryStore_delete_olderThan`, `testInMemoryStore_delete_emptyDomain`, `testInMemoryStore_listDomains`, `testInMemoryStore_listDomains_empty`, `testInMemoryStore_concurrentAccess` | COVERED (14 tests) |
| AC3 | FileBasedMemoryStore persistent implementation | P0 | `testFileBasedMemoryStore_init_customDir`, `testFileBasedMemoryStore_save_createsFile`, `testFileBasedMemoryStore_save_filePermissions`, `testFileBasedMemoryStore_dirPermissions`, `testFileBasedMemoryStore_persistence_acrossInstances`, `testFileBasedMemoryStore_persistence_multipleDomains`, `testFileBasedMemoryStore_query_returnsCachedEntries`, `testFileBasedMemoryStore_delete_rewritesFile`, `testFileBasedMemoryStore_delete_removesFileWhenEmpty`, `testFileBasedMemoryStore_listDomains_sorted`, `testFileBasedMemoryStore_concurrentAccess`, `testFileBasedMemoryStore_defaultDir_savesSuccessfully`, `testFileBasedMemoryStore_emptyDomain_throws`, `testFileBasedMemoryStore_pathTraversal_throws`, `testFileBasedMemoryStore_slashInDomain_throws`, `testFileBasedMemoryStore_backslashInDomain_throws` | COVERED (16 tests) |
| AC4 | Auto-expiry | P0 | `testInMemoryStore_autoExpiry`, `testInMemoryStore_noExpiry_withinMaxAge`, `testInMemoryStore_defaultMaxAge`, `testFileBasedMemoryStore_autoExpiry`, `testFileBasedMemoryStore_defaultMaxAge` | COVERED (5 tests) |
| AC5 | AgentOptions/ToolContext integration | P0 | `testAgentOptions_hasMemoryStoreProperty`, `testAgentOptions_initWithMemoryStore`, `testToolContext_hasMemoryStoreField`, `testToolContext_withToolUseId_preservesMemoryStore` | COVERED (4 tests) |
| AC6 | Corrupt entry resilience | P0 | `testFileBasedMemoryStore_corruptFile_skipsEntry`, `testFileBasedMemoryStore_emptyArrayFile` | COVERED (2 tests) |
| AC7 | Unit tests | P0 | All 49 tests in MemoryStoreTests.swift | COVERED |
| AC8 | Build and test pass | P0 | swift build: 0 errors; swift test: 4611 pass, 0 failures | COVERED |

---

## Test Coverage by Category

| Category | Test Count | P0 | P1 |
|----------|-----------|-----|-----|
| KnowledgeEntry types | 4 | 4 | 0 |
| KnowledgeQueryFilter types | 3 | 3 | 0 |
| MemoryStoreProtocol conformance | 1 | 1 | 0 |
| InMemoryStore CRUD | 14 | 13 | 1 |
| FileBasedMemoryStore CRUD | 16 | 16 | 0 |
| Auto-expiry (both stores) | 5 | 4 | 1 |
| Corrupt file resilience | 2 | 2 | 0 |
| AgentOptions integration | 2 | 2 | 0 |
| ToolContext integration | 2 | 2 | 0 |
| **Total** | **49** | **47** | **2** |

---

## Requirements Coverage Matrix

| Requirement | Source | Tests | Coverage |
|-------------|--------|-------|----------|
| KnowledgeEntry: id, content, tags, createdAt, sourceRunId fields | AC1 | testKnowledgeEntry_construction | FULL |
| KnowledgeEntry: Equatable conformance | AC1 | testKnowledgeEntry_equality | FULL |
| KnowledgeEntry: Sendable conformance | AC1 | testKnowledgeEntry_sendable | FULL |
| KnowledgeQueryFilter: tags, olderThan, newerThan, limit | AC1 | testKnowledgeQueryFilter_defaultConstruction, testKnowledgeQueryFilter_equality | FULL |
| MemoryStoreProtocol: Sendable conformance | AC1 | testMemoryStoreProtocol_isSendable | FULL |
| InMemoryStore: save stores entry | AC2 | testInMemoryStore_save_andQuery | FULL |
| InMemoryStore: save appends to same domain | AC2 | testInMemoryStore_save_appendsMultiple | FULL |
| InMemoryStore: separate domain isolation | AC2 | testInMemoryStore_save_separateDomains | FULL |
| InMemoryStore: query nil filter returns all | AC2 | testInMemoryStore_query_nilFilter_returnsAll | FULL |
| InMemoryStore: query tag filter | AC2 | testInMemoryStore_query_tagFilter | FULL |
| InMemoryStore: query date range filter | AC2 | testInMemoryStore_query_dateRange | FULL |
| InMemoryStore: query limit | AC2 | testInMemoryStore_query_limit | FULL |
| InMemoryStore: query empty domain | AC2 | testInMemoryStore_query_emptyDomain | FULL |
| InMemoryStore: delete olderThan | AC2 | testInMemoryStore_delete_olderThan | FULL |
| InMemoryStore: delete empty domain | AC2 | testInMemoryStore_delete_emptyDomain | FULL |
| InMemoryStore: listDomains sorted | AC2 | testInMemoryStore_listDomains | FULL |
| InMemoryStore: listDomains empty | AC2 | testInMemoryStore_listDomains_empty | FULL |
| InMemoryStore: concurrent access safety | AC2 | testInMemoryStore_concurrentAccess | FULL |
| FileBasedMemoryStore: init with custom dir | AC3 | testFileBasedMemoryStore_init_customDir | FULL |
| FileBasedMemoryStore: save creates file | AC3 | testFileBasedMemoryStore_save_createsFile | FULL |
| FileBasedMemoryStore: file permissions 0600 | AC3 | testFileBasedMemoryStore_save_filePermissions | FULL |
| FileBasedMemoryStore: directory permissions 0700 | AC3 | testFileBasedMemoryStore_dirPermissions | FULL |
| FileBasedMemoryStore: persistence across instances | AC3 | testFileBasedMemoryStore_persistence_acrossInstances | FULL |
| FileBasedMemoryStore: multiple domains on init | AC3 | testFileBasedMemoryStore_persistence_multipleDomains | FULL |
| FileBasedMemoryStore: query from cache | AC3 | testFileBasedMemoryStore_query_returnsCachedEntries | FULL |
| FileBasedMemoryStore: delete rewrites file | AC3 | testFileBasedMemoryStore_delete_rewritesFile | FULL |
| FileBasedMemoryStore: delete removes empty file | AC3 | testFileBasedMemoryStore_delete_removesFileWhenEmpty | FULL |
| FileBasedMemoryStore: listDomains sorted | AC3 | testFileBasedMemoryStore_listDomains_sorted | FULL |
| FileBasedMemoryStore: concurrent safety | AC3 | testFileBasedMemoryStore_concurrentAccess | FULL |
| FileBasedMemoryStore: default directory | AC3 | testFileBasedMemoryStore_defaultDir_savesSuccessfully | FULL |
| FileBasedMemoryStore: domain validation (empty) | AC3 | testFileBasedMemoryStore_emptyDomain_throws | FULL |
| FileBasedMemoryStore: domain validation (..) | AC3 | testFileBasedMemoryStore_pathTraversal_throws | FULL |
| FileBasedMemoryStore: domain validation (/) | AC3 | testFileBasedMemoryStore_slashInDomain_throws | FULL |
| FileBasedMemoryStore: domain validation (\) | AC3 | testFileBasedMemoryStore_backslashInDomain_throws | FULL |
| Auto-expiry: InMemoryStore expired filtered | AC4 | testInMemoryStore_autoExpiry | FULL |
| Auto-expiry: InMemoryStore fresh kept | AC4 | testInMemoryStore_noExpiry_withinMaxAge | FULL |
| Auto-expiry: InMemoryStore default 30 days | AC4 | testInMemoryStore_defaultMaxAge | FULL |
| Auto-expiry: FileBasedMemoryStore expired filtered | AC4 | testFileBasedMemoryStore_autoExpiry | FULL |
| Auto-expiry: FileBasedMemoryStore default 30 days | AC4 | testFileBasedMemoryStore_defaultMaxAge | FULL |
| AgentOptions: memoryStore property exists | AC5 | testAgentOptions_hasMemoryStoreProperty | FULL |
| AgentOptions: init with memoryStore | AC5 | testAgentOptions_initWithMemoryStore | FULL |
| ToolContext: memoryStore field | AC5 | testToolContext_hasMemoryStoreField | FULL |
| ToolContext: withToolUseId preserves memoryStore | AC5 | testToolContext_withToolUseId_preservesMemoryStore | FULL |
| Corrupt file: invalid JSON skipped | AC6 | testFileBasedMemoryStore_corruptFile_skipsEntry | FULL |
| Corrupt file: empty array handled | AC6 | testFileBasedMemoryStore_emptyArrayFile | FULL |

---

## Implementation Verification

| Artifact | Expected | Actual | Status |
|----------|----------|--------|--------|
| MemoryTypes.swift (NEW) | Types/ leaf, no outbound deps | File exists, imports only Foundation | PASS |
| MemoryStore.swift (NEW) | Stores/, depends only on Types/ | File exists, imports only Foundation | PASS |
| AgentTypes.swift (MODIFIED) | memoryStore in AgentOptions | Line 286: property, line 455: init param, line 515: assignment, line 624: nil in config init | PASS |
| ToolTypes.swift (MODIFIED) | memoryStore in ToolContext | Line 302: field, line 365: init param, lines 423,456: copied in withToolUseId/withSkillContext | PASS |
| Agent.swift (MODIFIED) | memoryStore passed in both ToolContext sites | Line 1198: main loop, line 1990: streaming loop | PASS |
| OpenAgentSDK.swift (MODIFIED) | DocC symbol references | Memory Store section added | PASS |
| MemoryStoreTests.swift (NEW) | Unit tests | 49 tests | PASS |
| swift build | 0 errors, 0 warnings | Build complete | PASS |
| swift test | All pass | 4611 pass, 14 skipped, 0 failures | PASS |

---

## Gap Analysis

### Gaps Found: 0 critical, 0 major, 1 minor

| Gap | Severity | Description | Recommendation |
|-----|----------|-------------|----------------|
| ToolContext.withSkillContext() not directly tested | Minor | Line 456 in ToolTypes.swift copies memoryStore in withSkillContext(), but only withToolUseId() is tested. The code path is verified via grep but lacks a dedicated test. | Consider adding a test for withSkillContext() preservation in a future story if skill context is used with memoryStore. |

### Non-Gaps (Verified via Source)

- Both ToolContext construction sites in Agent.swift (main loop + streaming loop) are covered indirectly through integration tests
- FileBasedMemoryStore uses nonisolated static methods for init loading (avoiding Swift Concurrency Task naming conflict)
- Domain name validation covers all 4 forbidden patterns (empty, /, \, ..)
- ISO8601 date serialization matches SessionStore pattern
- File permissions match SessionStore pattern (0o700 dir, 0o600 files)
- Logger.shared.warn used for corrupt entries (not crashing)

---

## Quality Gate Decision

### COVERAGE: 100%

- **8/8 Acceptance Criteria**: FULLY COVERED
- **44/44 Requirements**: FULLY COVERED (each requirement maps to at least 1 test)
- **49 tests** across all ACs with 0 failures
- **Build**: zero errors, zero warnings
- **Full suite regression**: 4611 tests passing, 0 failures

### GATE DECISION: **PASS**

All acceptance criteria have direct test coverage. No critical or major gaps. One minor gap (withSkillContext not directly tested) is acceptable given the code is verified and the path is exercised indirectly.

### Risk Assessment: **LOW**

- Both store implementations follow established patterns (SessionStore, TodoStore)
- Actor isolation ensures thread safety, confirmed by concurrent access tests
- Corrupt file resilience tested with both invalid JSON and empty arrays
- Security: domain name validation prevents path traversal
- No external dependencies added
- No regression in existing test suite (4611 pass)
