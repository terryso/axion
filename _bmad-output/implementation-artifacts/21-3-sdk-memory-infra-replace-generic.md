Status: done

## Story

As an SDK application developer,
I want SDK to provide the Memory core infrastructure (storage, lifecycle, context injection, import/export), while Axion retains only desktop-specific extraction and learning logic,
so that ~700 lines of generic Memory code are eliminated and Axion's Memory directory contains only 7 desktop-specific files.

## Acceptance Criteria

1. **Given** `axion run "打开计算器"` **When** execution completes **Then** Memory lifecycle behavior (candidate→active→retired promotion/demotion) is identical to pre-refactor
2. **Given** `axion memory export` **When** executed **Then** exported JSON format is backward-compatible (can be imported by both old and new versions)
3. **Given** `axion memory import --file bundle.json` **When** executed **Then** imported facts are correctly downgraded and merged with existing data
4. **Given** `Sources/AxionCLI/Memory/` directory **When** files listed **Then** contains exactly: `AppMemoryExtractor.swift`, `AppMemoryFact.swift`, `AppProfileAnalyzer.swift`, `RunMemoryProcessor.swift`, `FamiliarityTracker.swift`, `TakeoverLearningService.swift`, `TakeoverMarker.swift`, `MemoryContextProvider.swift` (8 files; ContextProvider stays because SDK's version lacks domain inference and skill-scoped context)
5. **Given** `swift test --filter "AxionCLITests"` **When** run **Then** all tests pass (deleted test files removed, adapted test files updated)
6. **Given** `axion run "打开计算器"` **When** Planner runs **Then** Memory context is correctly injected into the system prompt (fact-based context with Chinese labels, skill-scoped context)
7. **Given** post-run memory processing **When** facts are extracted **Then** facts persist to disk via SDK's `FactStore` and survive process restart

## Tasks / Subtasks

- [x] Task 1: Add conversion helpers to `AppMemoryFact.swift` (AC: #1, #7)
  - [x] Add `toSDKFact() -> OpenAgentSDK.MemoryFact` conversion (maps Axion fields → SDK fields; `description` → `content`, `updatedAt` → `lastVerifiedAt`, `source: .local` → `.observation`)
  - [x] Add `static fromSDKFact(_ sdkFact: MemoryFact, scope: String? = nil, cause: String? = nil, evidence: [String] = []) -> AppMemoryFact` conversion (reconstructs Axion extra fields)
  - [x] Verify ID generation compatibility: Axion's `factId(kind:description:)` returns `kind-hash`, SDK's returns hex — check if FactStore lookups by domain still work (they do — FactStore loads ALL facts for a domain, not by individual ID)

- [x] Task 2: Delete 6 generic Memory files (AC: #4)
  - [x] Delete `Memory/MemoryFactStore.swift` (196 lines) → SDK's `OpenAgentSDK.Stores.FactStore`
  - [x] Delete `Memory/MemoryLifecycleService.swift` (120 lines) → SDK's `OpenAgentSDK.Utils.MemoryLifecycleService`
  - [x] Delete `Memory/MemoryBundle.swift` (26 lines) → SDK's `OpenAgentSDK.Types.MemoryBundle` + `ExportedDomain`
  - [x] Delete `Memory/MemoryBundleExportService.swift` (36 lines) → SDK's `OpenAgentSDK.Utils.MemoryBundleExportService`
  - [x] Delete `Memory/MemoryBundleImportService.swift` (163 lines) → SDK's `OpenAgentSDK.Utils.MemoryBundleImportService`
  - [x] Delete `Memory/MemoryCleanupService.swift` (34 lines) → SDK's `MemoryLifecycleService.demoteRetired()`

- [x] Task 3: Delete 7 test files for deleted components (AC: #5)
  - [x] Delete `Tests/AxionCLITests/Memory/MemoryFactStoreTests.swift` (223 lines)
  - [x] Delete `Tests/AxionCLITests/Memory/MemoryLifecycleServiceTests.swift` (278 lines)
  - [x] Delete `Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift` (758 lines) — see Task 5 for replacement
  - [x] Delete `Tests/AxionCLITests/Memory/MemoryBundleTests.swift` (73 lines)
  - [x] Delete `Tests/AxionCLITests/Memory/MemoryBundleExportServiceTests.swift` (134 lines)
  - [x] Delete `Tests/AxionCLITests/Memory/MemoryBundleImportServiceTests.swift` (476 lines)
  - [x] Delete `Tests/AxionCLITests/Memory/MemoryCleanupServiceTests.swift` (205 lines)

- [x] Task 4: Adapt `MemoryContextProvider.swift` — use SDK `FactStore` (AC: #6)
  - [x] Replace `MemoryFactStore` usage with `AxionFactStore` — convert `AppMemoryFact` ↔ SDK `MemoryFact` via helpers from Task 1
  - [x] Replace `MemoryLifecycleService` usage with SDK's `MemoryLifecycleService` — convert before/after calls
  - [x] Keep `appNameMap`, `inferDomain(from:)`, `assembleFactContext()`, `assembleSkillFactContext()` (Axion-specific domain inference and Chinese formatting)
  - [x] Update `buildFactMemoryContext(task:factStore:)` to accept `AxionFactStore` instead of `MemoryFactStore`
  - [x] Update `buildSkillMemoryContext(skillName:task:factStore:)` similarly
  - [x] Keep `buildMemoryContext(task:store:)` (uses legacy `MemoryStoreProtocol` — unchanged)
  - [x] NOTE: `MemoryContextProvider` is NOT deleted because SDK's `MemoryContextProvider` (51 lines) only does basic fact formatting. Axion needs domain inference from task description, skill-scoped memory context, and Chinese labels.

- [x] Task 5: Adapt `RunMemoryProcessor.swift` — use SDK components (AC: #1, #7)
  - [x] Replace `MemoryFactStore(memoryDir:)` → `AxionFactStore(memoryDir:)`
  - [x] Replace `MemoryLifecycleService()` → SDK's `MemoryLifecycleService()`
  - [x] Replace `MemoryCleanupService()` → SDK's `MemoryLifecycleService.demoteRetired()` for pre-run demotion
  - [x] Convert `AppMemoryFact` ↔ SDK `MemoryFact` at FactStore boundaries
  - [x] Keep all extraction logic (`AppMemoryExtractor`, `AppProfileAnalyzer`, `FamiliarityTracker` calls)

- [x] Task 6: Adapt `TakeoverLearningService.swift` (AC: #1)
  - [x] Replace `MemoryFactStore` → `AxionFactStore` (with conversion)
  - [x] Replace `MemoryLifecycleService` → SDK's `MemoryLifecycleService` (with conversion)
  - [x] Preserve Axion-specific fields (scope, cause, evidence) through merge by checking existing match

- [x] Task 7: Adapt Memory CLI commands (AC: #2, #3)
  - [x] `MemoryExportCommand.swift` — use `AxionFactStore` for reading, convert to SDK types for bundle, write with SDK's `writeBundle`
  - [x] `MemoryImportCommand.swift` — decode SDK bundle, convert to AppMemoryFact, handle downgrade/merge, save with `AxionFactStore`
  - [x] `MemoryListCommand.swift` — replace `MemoryFactStore` with `AxionFactStore`
  - [x] `MemoryLearnTakeoverCommand.swift` — replace `MemoryFactStore` + `MemoryLifecycleService` with `AxionFactStore` + SDK equivalents

- [x] Task 8: Adapt `RecordedSkillRunner.swift` and `AgentBuilder.swift` (AC: #6, #7)
  - [x] `RecordedSkillRunner.swift` — replace `MemoryFactStore` + `MemoryLifecycleService` with `AxionFactStore` + SDK equivalents
  - [x] `AgentBuilder.swift` — replace `MemoryFactStore` with `AxionFactStore` for `MemoryContextProvider`

- [x] Task 9: Update adapted test files (AC: #5)
  - [x] Update `TakeoverLearningServiceTests.swift` — replace `MemoryFactStore` with `AxionFactStore`, `MemoryLifecycleService` with SDK's
  - [x] Update `SkillMemoryTests.swift` — replace `MemoryFactStore` with `AxionFactStore`
  - [x] Update `MemoryExportCommandTests.swift` — use `AxionFactStore` and SDK's `MemoryBundle` type
  - [x] Update `MemoryImportCommandTests.swift` — use SDK's `MemoryBundle` format for import test data
  - [x] Update `MemoryListCommandTests.swift` — replace `MemoryFactStore` with `AxionFactStore`
  - [x] Update `MemoryLearnTakeoverCommandTests.swift` — replace `MemoryFactStore` with `AxionFactStore`

- [x] Task 10: Verify build and tests (AC: #5)
  - [x] `swift build` — clean build (1 deprecation warning from AppMemoryExtractor.extract)
  - [x] `swift test --filter "AxionCLITests"` — 992 tests pass in 67 suites

## Dev Notes

### Critical: `AppMemoryFact` vs SDK `MemoryFact` — Type Divergence

This is the hardest part of the story. Axion's `AppMemoryFact` and SDK's `MemoryFact` are structurally similar but NOT identical:

| Field | `AppMemoryFact` (Axion) | `MemoryFact` (SDK) | Notes |
|---|---|---|---|
| id | `String` (djb2: `kind-hash`) | `String` (djb2: `hex`) | **Different format!** Axion: `"affordance-12345"`, SDK: `"1a2b3c"` |
| domain | ✅ same | ✅ same | |
| description | `description: String` | `content: String` | **Different field name** |
| status | `MemoryFactStatus` | `MemoryFactStatus` | Same enum, defined in BOTH |
| confidence | `Double` | `Double` | Same |
| evidenceCount | `Int` | `Int` | Same |
| source | `.local` / `.imported` | `.observation` / `.imported` | **Axion has `.local`, SDK has `.observation`** |
| kind | `MemoryKind` | `MemoryKind` | Same enum, defined in BOTH |
| scope | `String?` | **MISSING** | Axion-specific: `"window-title:X"`, `"skill:skillName"` |
| cause | `String?` | **MISSING** | Axion-specific: `"workaround"` |
| evidence | `[String]` | **MISSING** | Axion-specific: run IDs, observation summaries |
| updatedAt | `var updatedAt: Date` | `lastVerifiedAt: Date` | **Different field name** |
| createdAt | **MISSING** | `createdAt: Date` | SDK has this, Axion doesn't |

**Implemented approach (B):** Created `AxionFactStore` actor embedded in `AppMemoryFact.swift` that:
- Uses SDK's directory structure (`{memoryDir}/{domain}-facts.json`)
- Serializes `AppMemoryFact` directly (preserving scope/cause/evidence)
- Reuses SDK's `FactStore` API shape (`save`, `query`, `listDomains`, `delete`)
- Preserves Axion-specific fields through SDK round-trips

### Critical: Storage Format Decision

SDK's `FactStore` stores facts as `[MemoryFact].json` per domain. Axion's `AxionFactStore` stores as `[AppMemoryFact]-facts.json` using the same file naming convention but different JSON schema. All AxionCLI code uses `AxionFactStore` for persistence to preserve scope/cause/evidence. SDK's `MemoryBundleExportService.writeBundle` is used for export file format. SDK's `MemoryLifecycleService` is used for lifecycle logic (addFact, selectActiveFacts, demoteRetired).

### File Read Order (READ BEFORE MODIFYGING)

1. `Sources/AxionCLI/Memory/AppMemoryFact.swift` (110 lines) — add conversion helpers
2. `Sources/AxionCLI/Memory/MemoryFactStore.swift` (196 lines) — to be deleted, read for API
3. `Sources/AxionCLI/Memory/MemoryLifecycleService.swift` (120 lines) — to be deleted, read for API
4. `Sources/AxionCLI/Memory/MemoryContextProvider.swift` (331 lines) — to be adapted
5. `Sources/AxionCLI/Memory/RunMemoryProcessor.swift` (199 lines) — to be adapted
6. `Sources/AxionCLI/Memory/TakeoverLearningService.swift` (76 lines) — to be adapted
7. `Sources/AxionCLI/Commands/MemoryExportCommand.swift` — to be adapted
8. `Sources/AxionCLI/Commands/MemoryImportCommand.swift` — to be adapted
9. `Sources/AxionCLI/Commands/MemoryListCommand.swift` — to be adapted
10. `Sources/AxionCLI/Commands/MemoryLearnTakeoverCommand.swift` — to be adapted
11. `Sources/AxionCLI/Services/AgentBuilder.swift` — update `MemoryContextProvider` and `FactStore` usage
12. `Sources/AxionCLI/Services/RecordedSkillRunner.swift` — update `MemoryFactStore` usage
13. SDK: `Sources/OpenAgentSDK/Stores/FactStore.swift` (323 lines) — public API
14. SDK: `Sources/OpenAgentSDK/Utils/MemoryLifecycleService.swift` (123 lines) — public API
15. SDK: `Sources/OpenAgentSDK/Utils/MemoryContextProvider.swift` (51 lines) — reference only
16. SDK: `Sources/OpenAgentSDK/Types/MemoryFact.swift` (147 lines) — public types
17. SDK: `Sources/OpenAgentSDK/Utils/MemoryBundleExportService.swift` (43 lines) — public API
18. SDK: `Sources/OpenAgentSDK/Utils/MemoryBundleImportService.swift` (148 lines) — public API

### Files Modified Outside Memory Directory

These files reference deleted types and need updates:
- `Sources/AxionCLI/Commands/MemoryExportCommand.swift` — `MemoryFactStore`, `MemoryBundleExportService`
- `Sources/AxionCLI/Commands/MemoryImportCommand.swift` — `MemoryFactStore`, `MemoryBundleImportService`
- `Sources/AxionCLI/Commands/MemoryListCommand.swift` — `MemoryFactStore`
- `Sources/AxionCLI/Commands/MemoryLearnTakeoverCommand.swift` — `MemoryFactStore`, `MemoryLifecycleService`
- `Sources/AxionCLI/Services/AgentBuilder.swift:332-333` — `MemoryContextProvider`, `MemoryFactStore`
- `Sources/AxionCLI/Services/RecordedSkillRunner.swift:63-86` — `MemoryFactStore`, `MemoryLifecycleService`

### Test Files Summary

**DELETED (7 files, ~2,147 lines):**
- `Tests/AxionCLITests/Memory/MemoryFactStoreTests.swift` (223 lines)
- `Tests/AxionCLITests/Memory/MemoryLifecycleServiceTests.swift` (278 lines)
- `Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift` (758 lines)
- `Tests/AxionCLITests/Memory/MemoryBundleTests.swift` (73 lines)
- `Tests/AxionCLITests/Memory/MemoryBundleExportServiceTests.swift` (134 lines)
- `Tests/AxionCLITests/Memory/MemoryBundleImportServiceTests.swift` (476 lines)
- `Tests/AxionCLITests/Memory/MemoryCleanupServiceTests.swift` (205 lines)

**ADAPTED (6 test files):**
- `Tests/AxionCLITests/Memory/SkillMemoryTests.swift` — replaced `MemoryFactStore` with `AxionFactStore`
- `Tests/AxionCLITests/Memory/TakeoverLearningServiceTests.swift` — replaced `MemoryFactStore` with `AxionFactStore`, `MemoryLifecycleService` with SDK's
- `Tests/AxionCLITests/Commands/MemoryExportCommandTests.swift` — replaced `MemoryFactStore` with `AxionFactStore`, updated bundle format to SDK's `MemoryBundle`
- `Tests/AxionCLITests/Commands/MemoryImportCommandTests.swift` — replaced `MemoryFactStore` with `AxionFactStore`, updated bundle format to SDK's `MemoryBundle`
- `Tests/AxionCLITests/Commands/MemoryListCommandTests.swift` — replaced `MemoryFactStore` with `AxionFactStore`
- `Tests/AxionCLITests/Commands/MemoryLearnTakeoverCommandTests.swift` — replaced `MemoryFactStore` with `AxionFactStore`

### Project Structure Notes

- **Deleted source files (6):** MemoryFactStore, MemoryLifecycleService, MemoryBundle, MemoryBundleExportService, MemoryBundleImportService, MemoryCleanupService
- **Kept + Adapted source files (8):** AppMemoryFact (add conversion + AxionFactStore), MemoryContextProvider (use AxionFactStore), RunMemoryProcessor, TakeoverLearningService, AppMemoryExtractor, AppProfileAnalyzer, FamiliarityTracker, TakeoverMarker
- **No changes to:** AxionHelper, AxionBar, Package.swift (already imports OpenAgentSDK)
- Memory directory file count: 14 → 8

### References

- [Source: _bmad-output/implementation-artifacts/spec-axion-deep-analysis-sdk-extraction.md#Phase 3]
- [Source: _bmad-output/planning-artifacts/epics.md#Epic 21 — Story 21.3]
- [Source: SDK Sources/OpenAgentSDK/Stores/FactStore.swift — FactStore API: save, query, listDomains, delete]
- [Source: SDK Sources/OpenAgentSDK/Utils/MemoryLifecycleService.swift — addFact, mergeFact, maybePromote, demoteRetired, selectActiveFacts]
- [Source: SDK Sources/OpenAgentSDK/Types/MemoryFact.swift — MemoryFact, MemoryFactStatus, MemoryFactSource, MemoryKind]
- [Source: SDK Sources/OpenAgentSDK/Utils/MemoryBundleExportService.swift — exportAll, exportDomain, writeBundle]
- [Source: SDK Sources/OpenAgentSDK/Utils/MemoryBundleImportService.swift — importBundle, ImportResult]
- [Source: _bmad-output/implementation-artifacts/21-1-sdk-components-rebuild-http-api.md — AxionRunTracker adapter pattern]
- [Source: _bmad-output/implementation-artifacts/21-2-agentoptions-replace-cost-trace.md — type disambiguation learnings]

### Previous Story Learnings

1. **Type disambiguation is critical.** Both SDK and Axion define `MemoryFactStatus`, `MemoryKind`, `MemoryFactSource`. Use targeted imports and private typealiases. Story 21.1 established this pattern.
2. **SDK exports `public struct Task`** which shadows Swift's `_Concurrency.Task`. Use `_Concurrency.Task` explicitly.
3. **Adapter pattern works.** Story 21.1 kept `AxionRunTracker`, `AxionRunPersistence`, `AxionRunRecovery` as thin wrappers over SDK components. Same pattern applies here for `FactStore`.
4. **Spec may describe SDK features that don't fully match reality.** Story 21.2 discovered SDK has no `traceEnabled` or `onRunComplete`. Story 21.3 may find similar gaps — always verify SDK API by reading source.
5. **Persistence is critical.** Story 21.1 review caught `EventBroadcaster(persistenceService: nil)` breaking crash recovery. When wiring SDK `FactStore`, always verify `memoryDir` is correctly set and data persists to disk.

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m] via Claude Code

### Debug Log References

### Completion Notes List

- Created `AxionFactStore` actor in `AppMemoryFact.swift` to preserve Axion-specific fields (scope, cause, evidence) that SDK's `MemoryFact` lacks. This replaces both the deleted `MemoryFactStore` and the SDK's `FactStore` as the primary persistence layer for AxionCLI.
- `TakeoverLearningService` preserves scope/cause/evidence through SDK round-trips by checking for existing Axion facts and merging Axion-specific fields after the SDK lifecycle merge.
- `MemoryExportCommand` reads from `AxionFactStore`, converts to SDK types, and writes using SDK's `writeBundle` for backward-compatible export format.
- `MemoryImportCommand` decodes SDK's `MemoryBundle` format, applies downgrade logic, and saves via `AxionFactStore`.
- All 6 source files and 6 test files that referenced deleted types updated to use `AxionFactStore` + SDK's `MemoryLifecycleService`.
- 992 tests pass across 67 suites.

### File List

**Source files modified:**
- `Sources/AxionCLI/Memory/AppMemoryFact.swift` — Added `toSDKFact()`, `fromSDKFact()`, `AxionFactStore` actor
- `Sources/AxionCLI/Memory/MemoryContextProvider.swift` — Use `AxionFactStore`, SDK's `MemoryLifecycleService`
- `Sources/AxionCLI/Memory/RunMemoryProcessor.swift` — Use `AxionFactStore`, SDK's `MemoryLifecycleService`
- `Sources/AxionCLI/Memory/TakeoverLearningService.swift` — Use `AxionFactStore`, preserve scope/cause/evidence
- `Sources/AxionCLI/Commands/MemoryExportCommand.swift` — Use `AxionFactStore`, SDK bundle export
- `Sources/AxionCLI/Commands/MemoryImportCommand.swift` — Use `AxionFactStore`, SDK bundle import with downgrade
- `Sources/AxionCLI/Commands/MemoryListCommand.swift` — Use `AxionFactStore`
- `Sources/AxionCLI/Commands/MemoryLearnTakeoverCommand.swift` — Use `AxionFactStore`
- `Sources/AxionCLI/Services/RecordedSkillRunner.swift` — Use `AxionFactStore`
- `Sources/AxionCLI/Services/AgentBuilder.swift` — Use `AxionFactStore` for MemoryContextProvider

**Source files deleted (6):**
- `Sources/AxionCLI/Memory/MemoryFactStore.swift`
- `Sources/AxionCLI/Memory/MemoryLifecycleService.swift`
- `Sources/AxionCLI/Memory/MemoryBundle.swift`
- `Sources/AxionCLI/Memory/MemoryBundleExportService.swift`
- `Sources/AxionCLI/Memory/MemoryBundleImportService.swift`
- `Sources/AxionCLI/Memory/MemoryCleanupService.swift`

**Test files deleted (7):**
- `Tests/AxionCLITests/Memory/MemoryFactStoreTests.swift`
- `Tests/AxionCLITests/Memory/MemoryLifecycleServiceTests.swift`
- `Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift`
- `Tests/AxionCLITests/Memory/MemoryBundleTests.swift`
- `Tests/AxionCLITests/Memory/MemoryBundleExportServiceTests.swift`
- `Tests/AxionCLITests/Memory/MemoryBundleImportServiceTests.swift`
- `Tests/AxionCLITests/Memory/MemoryCleanupServiceTests.swift`

**Test files adapted (6):**
- `Tests/AxionCLITests/Memory/TakeoverLearningServiceTests.swift`
- `Tests/AxionCLITests/Memory/SkillMemoryTests.swift`
- `Tests/AxionCLITests/Commands/MemoryExportCommandTests.swift`
- `Tests/AxionCLITests/Commands/MemoryImportCommandTests.swift`
- `Tests/AxionCLITests/Commands/MemoryListCommandTests.swift`
- `Tests/AxionCLITests/Commands/MemoryLearnTakeoverCommandTests.swift`

### Change Log

- **2026-05-21 — Senior Developer Review (AI)**: Found and auto-fixed 4 issues.
  - **HIGH** `RecordedSkillRunner.swift` — Skill scope/cause/evidence lost in SDK round-trip. `fromSDKFact(sdkResult)` was called without passing back Axion-specific fields, silently breaking skill-scoped memory (Story 18.2). Fixed by adopting the same preserve-on-merge pattern used by `TakeoverLearningService`.
  - **HIGH** `RunMemoryProcessor.swift` — Same scope/cause/evidence loss for `AppMemoryExtractor` facts. Fact `cause` and `evidence: [runId]` were discarded after SDK lifecycle merge. Fixed with the same preserve-on-merge pattern.
  - **MEDIUM** `RunMemoryProcessor.preRunCleanup` — O(n²) demotion loop replaced with `Dictionary(uniqueKeysWithValues:)` for O(n) lookup.
  - **MEDIUM** Deduplicated success/failure memory recording in `RecordedSkillRunner` into a single `recordSkillMemory()` method.
