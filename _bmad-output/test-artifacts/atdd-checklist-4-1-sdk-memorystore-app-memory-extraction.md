---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-05-13'
storyId: '4.1'
storyKey: '4-1-sdk-memorystore-app-memory-extraction'
storyFile: '_bmad-output/implementation-artifacts/4-1-sdk-memorystore-app-memory-extraction.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-4-1-sdk-memorystore-app-memory-extraction.md'
generatedTestFiles:
  - Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift
  - Tests/AxionCLITests/Memory/MemoryCleanupServiceTests.swift
  - Tests/AxionCLITests/Commands/DoctorCommandTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/4-1-sdk-memorystore-app-memory-extraction.md
  - _bmad-output/project-context.md
  - Sources/AxionCLI/Commands/RunCommand.swift
  - Sources/AxionCLI/Commands/DoctorCommand.swift
  - Sources/AxionCore/Models/AxionConfig.swift
  - Tests/AxionCLITests/Commands/DoctorCommandTests.swift
  - Tests/AxionCLITests/Trace/TraceRecorderTests.swift
---

# ATDD Checklist: Story 4.1 — SDK MemoryStore 与 App Memory 提取

## TDD Red Phase (Current)

测试以 red-phase scaffold 形式生成，实现代码尚不存在时将无法编译。

- Unit Tests: **23 tests** (新建) + **4 tests** (DoctorCommandTests 新增)
  - AppMemoryExtractorTests: 15 tests
  - MemoryCleanupServiceTests: 8 tests
  - DoctorCommandTests (新增): 4 tests

## Acceptance Criteria Coverage

| AC | Description | Tests | Priority |
|----|-------------|-------|----------|
| AC1 | 任务完成后自动提取 App 操作摘要并持久化 | `test_extract_returnsKnowledgeEntries_fromToolMessages`, `test_extract_contentIncludesToolSequence`, `test_extract_contentIncludesTaskDescription`, `test_extract_includesSuccessOrFailurePath`, `test_extract_successfulPathIndicatesSuccess`, `test_extract_sourceRunIdSet`, `test_extract_stepCountIncluded` | P0 |
| AC2 | Memory 按 App domain 组织 | `test_extract_usesBundleIdentifierAsDomain`, `test_extract_fallsBackToAppNameWhenNoBundleId`, `test_extract_tagsIncludeToolTypes`, `test_extract_multipleApps_producesMultipleDomains` | P0 |
| AC3 | 自动清理过期记录 | `test_cleanupExpired_removesOldEntries`, `test_cleanupExpired_removesFromMultipleDomains`, `test_cleanupExpired_noExpiredEntries_returnsZero`, `test_cleanupExpired_emptyStore_returnsZero`, `test_cleanupExpired_preservesRecentEntries`, `test_cleanupExpired_uses30DayThreshold`, `test_cleanupExpired_mixedOldAndRecentInSameDomain` | P0 |
| AC4 | 损坏 Memory 不阻塞任务 | SDK FileBasedMemoryStore 内置行为，Axion 层不单独测试 | N/A |
| AC5 | `axion doctor` 报告 Memory 状态 | `test_doctor_reportsMemoryStatus_whenMemoryExists`, `test_doctor_reportsMemoryUnused_whenNoMemory`, `test_doctor_memoryCheck_showsDomainCountAndEntryCount`, `test_doctor_memoryCheckFormat_whenUnused` | P0 |

## Test Strategy

### Detected Stack: Backend (Swift/XCTest)

- **Unit Tests** for pure logic (AppMemoryExtractor extraction, MemoryCleanupService cleanup)
- **Protocol-based testing** using SDK's `InMemoryStore` for MemoryCleanupService tests
- **MockDoctorIO** pattern (existing) for DoctorCommand Memory check tests
- **Temporary directory isolation** for file-based Doctor tests

### Test Levels

| Level | Count | Scope |
|-------|-------|-------|
| P0 — Critical Path | 19 | Type existence, core extraction, cleanup, 30-day threshold, doctor check |
| P1 — Edge Cases | 8 | Empty inputs, non-app tools, mixed ages, fallback naming |

### Key Test Patterns Used

1. **Type existence scaffolding** — `test_appMemoryExtractor_typeExists` confirms the type compiles
2. **SDK InMemoryStore** — Used for MemoryCleanupService tests, avoids disk I/O
3. **Temporary directory isolation** — DoctorCommand Memory tests use `NSTemporaryDirectory() + UUID`
4. **SDKMessage.ToolUseData / ToolResultData construction** — Helper methods for building test messages
5. **Test naming**: `test_{unit}_{scenario}_{expectedResult}` following project conventions

### Key Design Decisions

1. **AppMemoryExtractor.extract(from:task:runId:)** — Takes array of (toolUse, toolResult) pairs, returns [KnowledgeEntry]
2. **MemoryCleanupService.cleanupExpired(in:)** — Accepts any MemoryStoreProtocol (testable with InMemoryStore)
3. **DoctorCommand.runDoctor(io:configDirectory:)** — Extended with Memory check, existing tests preserved
4. **AC4 (corrupted memory)** — Handled by SDK FileBasedMemoryStore natively, no Axion-layer test needed

## Generated Test Files

### 1. Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift (NEW)

**15 tests**, covers AC1 and AC2.

| Test | AC | Priority |
|------|----|----------|
| `test_appMemoryExtractor_typeExists` | Setup | P0 |
| `test_extract_returnsKnowledgeEntries_fromToolMessages` | AC1 | P0 |
| `test_extract_contentIncludesToolSequence` | AC1 | P0 |
| `test_extract_contentIncludesTaskDescription` | AC1 | P0 |
| `test_extract_includesSuccessOrFailurePath` | AC1 | P0 |
| `test_extract_successfulPathIndicatesSuccess` | AC1 | P0 |
| `test_extract_usesBundleIdentifierAsDomain` | AC2 | P0 |
| `test_extract_fallsBackToAppNameWhenNoBundleId` | AC2 | P0 |
| `test_extract_tagsIncludeToolTypes` | AC2 | P0 |
| `test_extract_sourceRunIdSet` | AC1 | P0 |
| `test_extract_emptyToolPairs_returnsEmptyArray` | AC1 | P1 |
| `test_extract_nonAppTools_onlyStillExtracts` | AC1 | P1 |
| `test_extract_multipleApps_producesMultipleDomains` | AC2 | P1 |
| `test_extract_stepCountIncluded` | AC1 | P1 |

### 2. Tests/AxionCLITests/Memory/MemoryCleanupServiceTests.swift (NEW)

**8 tests**, covers AC3.

| Test | AC | Priority |
|------|----|----------|
| `test_memoryCleanupService_typeExists` | Setup | P0 |
| `test_cleanupExpired_removesOldEntries` | AC3 | P0 |
| `test_cleanupExpired_removesFromMultipleDomains` | AC3 | P0 |
| `test_cleanupExpired_noExpiredEntries_returnsZero` | AC3 | P0 |
| `test_cleanupExpired_emptyStore_returnsZero` | AC3 | P0 |
| `test_cleanupExpired_preservesRecentEntries` | AC3 | P0 |
| `test_cleanupExpired_uses30DayThreshold` | AC3 | P0 |
| `test_cleanupExpired_mixedOldAndRecentInSameDomain` | AC3 | P1 |

### 3. Tests/AxionCLITests/Commands/DoctorCommandTests.swift (UPDATED)

**+4 tests** added for AC5 (Memory status check in doctor command).

| Test | AC | Priority |
|------|----|----------|
| `test_doctor_reportsMemoryStatus_whenMemoryExists` | AC5 | P0 |
| `test_doctor_reportsMemoryUnused_whenNoMemory` | AC5 | P0 |
| `test_doctor_memoryCheck_showsDomainCountAndEntryCount` | AC5 | P0 |
| `test_doctor_memoryCheckFormat_whenUnused` | AC5 | P0 |

## Implementation Checklist

### Task-by-Task Activation (Red-Green-Refactor)

#### Task 1: AppMemoryExtractor (AC1, AC2)

**Activate:** Remove `test_appMemoryExtractor_typeExists` failure by creating the type.

1. Create `Sources/AxionCLI/Memory/AppMemoryExtractor.swift`
2. Define `AppMemoryExtractor` struct with `extract(from:task:runId:) async throws -> [KnowledgeEntry]`
3. Implement extraction logic from toolUse/toolResult pairs
4. Implement bundle identifier extraction from tool results
5. Implement tag generation (app domain, tool types, success/failure)
6. Run: `swift test --filter "AxionCLITests.Memory.AppMemoryExtractorTests"`

**Red Phase Verify:** All 14 functional tests fail (type/method not implemented)
**Green Phase:** Implement until all 14 functional tests pass
**Refactor:** Clean up extraction logic, improve content formatting

#### Task 2: RunCommand MemoryStore Integration (AC1)

1. Update `Sources/AxionCLI/Commands/RunCommand.swift`
2. Create `FileBasedMemoryStore(memoryDir: "~/.axion/memory/")` instance
3. Inject into `AgentOptions(memoryStore:)`
4. Collect toolUse/toolResult events during message stream
5. After stream ends, call `AppMemoryExtractor.extract()` and save to store
6. Call `MemoryCleanupService.cleanupExpired()` at run start

**No dedicated ATDD tests for this task** (integration covered by AppMemoryExtractorTests)

#### Task 3: MemoryCleanupService (AC3)

**Activate:** Remove `test_memoryCleanupService_typeExists` failure by creating the type.

1. Create `Sources/AxionCLI/Memory/MemoryCleanupService.swift`
2. Define `MemoryCleanupService` struct with `cleanupExpired(in:) async throws -> Int`
3. Implement: list domains -> delete entries older than 30 days per domain
4. Run: `swift test --filter "AxionCLITests.Memory.MemoryCleanupServiceTests"`

**Red Phase Verify:** All 7 functional tests fail (type not implemented)
**Green Phase:** Implement until all 7 functional tests pass

#### Task 4: DoctorCommand Memory Check (AC5)

**Activate:** The 4 new tests in DoctorCommandTests will fail until Memory check is added.

1. Update `Sources/AxionCLI/Commands/DoctorCommand.swift`
2. Add `checkMemory(configDirectory:)` method
3. Check if memory directory exists, count domains and entries
4. Format output: `[OK] Memory: X domains, Y entries` or `[OK] Memory: unused`
5. Run: `swift test --filter "AxionCLITests.Commands.DoctorCommandTests"`

**Red Phase Verify:** The 4 new Memory tests fail
**Green Phase:** Add Memory check to runDoctor(), tests pass

## Execution Commands

```bash
# Run all unit tests for Story 4.1
swift test --filter "AxionCLITests.Memory" --filter "AxionCLITests.Commands.DoctorCommandTests"

# Run specific test files
swift test --filter "AppMemoryExtractorTests"
swift test --filter "MemoryCleanupServiceTests"
swift test --filter "DoctorCommandTests"

# Run only the new doctor memory tests
swift test --filter "test_doctor_reportsMemoryStatus_whenMemoryExists"
swift test --filter "test_doctor_reportsMemoryUnused_whenNoMemory"
swift test --filter "test_doctor_memoryCheck"
```

## Next Steps

1. **Implement Task 1 (AppMemoryExtractor)** — Start with type creation, then extraction logic
2. **Implement Task 3 (MemoryCleanupService)** — Simple wrapper around SDK's delete API
3. **Implement Task 4 (DoctorCommand Memory check)** — Add Memory check to existing doctor flow
4. **Implement Task 2 (RunCommand integration)** — Wire everything together
5. **Remove test skips** as each task is implemented (verify RED then GREEN)
6. **Run full test suite** after all tasks complete

## Notes

- **AC4 (corrupted memory)** is handled by SDK's FileBasedMemoryStore natively — it skips corrupt entries with warning logs. No Axion-specific test needed.
- **InMemoryStore** from SDK is used for MemoryCleanupServiceTests instead of FileBasedMemoryStore, following the project's rule: "unit tests must not make real system calls, must isolate via mock/protocol".
- **KnowledgeEntry** and **MemoryStoreProtocol** are SDK types — no new AxionCore models needed.
- The tests will not compile until the implementation types (`AppMemoryExtractor`, `MemoryCleanupService`) are created. This is intentional TDD red phase behavior.
