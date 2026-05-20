Status: ready-for-dev

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

- [ ] Task 1: Add conversion helpers to `AppMemoryFact.swift` (AC: #1, #7)
  - [ ] Add `toSDKFact() -> OpenAgentSDK.MemoryFact` conversion (maps Axion fields → SDK fields; `description` → `content`, `updatedAt` → `lastVerifiedAt`, `source: .local` → `.observation`)
  - [ ] Add `static fromSDKFact(_ sdkFact: MemoryFact, scope: String? = nil, cause: String? = nil, evidence: [String] = []) -> AppMemoryFact` conversion (reconstructs Axion extra fields)
  - [ ] Verify ID generation compatibility: Axion's `factId(kind:description:)` returns `kind-hash`, SDK's returns hex — check if FactStore lookups by domain still work (they do — FactStore loads ALL facts for a domain, not by individual ID)

- [ ] Task 2: Delete 6 generic Memory files (AC: #4)
  - [ ] Delete `Memory/MemoryFactStore.swift` (196 lines) → SDK's `OpenAgentSDK.Stores.FactStore`
  - [ ] Delete `Memory/MemoryLifecycleService.swift` (120 lines) → SDK's `OpenAgentSDK.Utils.MemoryLifecycleService`
  - [ ] Delete `Memory/MemoryBundle.swift` (26 lines) → SDK's `OpenAgentSDK.Types.MemoryBundle` + `ExportedDomain`
  - [ ] Delete `Memory/MemoryBundleExportService.swift` (36 lines) → SDK's `OpenAgentSDK.Utils.MemoryBundleExportService`
  - [ ] Delete `Memory/MemoryBundleImportService.swift` (163 lines) → SDK's `OpenAgentSDK.Utils.MemoryBundleImportService`
  - [ ] Delete `Memory/MemoryCleanupService.swift` (34 lines) → SDK's `MemoryLifecycleService.demoteRetired()`

- [ ] Task 3: Delete 7 test files for deleted components (AC: #5)
  - [ ] Delete `Tests/AxionCLITests/Memory/MemoryFactStoreTests.swift` (223 lines)
  - [ ] Delete `Tests/AxionCLITests/Memory/MemoryLifecycleServiceTests.swift` (278 lines)
  - [ ] Delete `Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift` (758 lines) — see Task 5 for replacement
  - [ ] Delete `Tests/AxionCLITests/Memory/MemoryBundleTests.swift` (73 lines)
  - [ ] Delete `Tests/AxionCLITests/Memory/MemoryBundleExportServiceTests.swift` (134 lines)
  - [ ] Delete `Tests/AxionCLITests/Memory/MemoryBundleImportServiceTests.swift` (476 lines)
  - [ ] Delete `Tests/AxionCLITests/Memory/MemoryCleanupServiceTests.swift` (205 lines)

- [ ] Task 4: Adapt `MemoryContextProvider.swift` — use SDK `FactStore` (AC: #6)
  - [ ] Replace `MemoryFactStore` usage with SDK's `FactStore` — convert `AppMemoryFact` ↔ SDK `MemoryFact` via helpers from Task 1
  - [ ] Replace `MemoryLifecycleService` usage with SDK's `MemoryLifecycleService` — convert before/after calls
  - [ ] Keep `appNameMap`, `inferDomain(from:)`, `assembleFactContext()`, `assembleSkillFactContext()` (Axion-specific domain inference and Chinese formatting)
  - [ ] Update `buildFactMemoryContext(task:factStore:)` to accept SDK's `FactStore` instead of `MemoryFactStore`
  - [ ] Update `buildSkillMemoryContext(skillName:task:factStore:)` similarly
  - [ ] Keep `buildMemoryContext(task:store:)` (uses legacy `MemoryStoreProtocol` — unchanged)
  - [ ] NOTE: `MemoryContextProvider` is NOT deleted because SDK's `MemoryContextProvider` (51 lines) only does basic fact formatting. Axion needs domain inference from task description, skill-scoped memory context, and Chinese labels.

- [ ] Task 5: Adapt `RunMemoryProcessor.swift` — use SDK components (AC: #1, #7)
  - [ ] Replace `MemoryFactStore(memoryDir:)` → SDK's `FactStore(memoryDir:)`
  - [ ] Replace `MemoryLifecycleService()` → SDK's `MemoryLifecycleService()`
  - [ ] Replace `MemoryCleanupService()` → SDK's `MemoryLifecycleService.demoteRetired()` for pre-run demotion
  - [ ] Convert `AppMemoryFact` ↔ SDK `MemoryFact` at FactStore boundaries
  - [ ] Keep all extraction logic (`AppMemoryExtractor`, `AppProfileAnalyzer`, `FamiliarityTracker` calls)

- [ ] Task 6: Adapt `TakeoverLearningService.swift` (AC: #1)
  - [ ] Replace `MemoryFactStore` → SDK's `FactStore` (with conversion)
  - [ ] Replace `MemoryLifecycleService` → SDK's `MemoryLifecycleService` (with conversion)

- [ ] Task 7: Adapt Memory CLI commands (AC: #2, #3)
  - [ ] `MemoryExportCommand.swift` — replace `MemoryFactStore` + `MemoryBundleExportService` with SDK's `FactStore` + `MemoryBundleExportService` (with conversion)
  - [ ] `MemoryImportCommand.swift` — replace `MemoryFactStore` + `MemoryBundleImportService` with SDK's `FactStore` + `MemoryBundleImportService` (with conversion)
  - [ ] `MemoryListCommand.swift` — replace `MemoryFactStore` with SDK's `FactStore`
  - [ ] `MemoryLearnTakeoverCommand.swift` — replace `MemoryFactStore` + `MemoryLifecycleService` with SDK equivalents

- [ ] Task 8: Adapt `RecordedSkillRunner.swift` and `AgentBuilder.swift` (AC: #6, #7)
  - [ ] `RecordedSkillRunner.swift:63-86` — replace `MemoryFactStore` + `MemoryLifecycleService` with SDK equivalents
  - [ ] `AgentBuilder.swift:332-333` — replace `MemoryFactStore` with SDK's `FactStore`, update `MemoryContextProvider` calls

- [ ] Task 9: Update adapted test files (AC: #5)
  - [ ] Update `MemoryContextProviderTests.swift` — new tests that verify domain inference, fact context assembly, and skill context with SDK's `FactStore` mock
  - [ ] Update `SkillMemoryTests.swift` — replace `MemoryFactStore` with SDK's `FactStore` in test setup
  - [ ] Update `MemoryExportCommandTests.swift`, `MemoryImportCommandTests.swift`, `MemoryListCommandTests.swift`, `MemoryClearCommandTests.swift` — replace deleted type references

- [ ] Task 10: Verify build and tests (AC: #5)
  - [ ] `swift build` — clean build, no warnings
  - [ ] `swift test --filter "AxionCLITests"` — all tests pass

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

**Recommended approach:** Add conversion helpers to `AppMemoryFact.swift`:
```swift
extension AppMemoryFact {
    func toSDKFact() -> OpenAgentSDK.MemoryFact { ... }
    static func fromSDKFact(_ fact: OpenAgentSDK.MemoryFact, scope: String?, cause: String?, evidence: [String]) -> AppMemoryFact { ... }
}
```

**ID compatibility concern:** Axion's `factId` produces `"kind-djb2Decimal"`, SDK's produces `"djb2Hex"`. Since both `FactStore` and Axion's `MemoryFactStore` load ALL facts for a domain and match by `id` field within the array, the ID format difference means **existing Axion facts will have different IDs than newly created SDK facts**. This is OK as long as the same `factId` function is used consistently. Since `AppMemoryFact.create()` and `AppMemoryFact.factId()` are kept, new facts will use Axion's format. When converting to SDK `MemoryFact` for storage, the ID is preserved as-is.

**Storage format concern:** SDK's `FactStore` stores facts as `[MemoryFact].json` per domain. Axion's `MemoryFactStore` stores as `[AppMemoryFact]-facts.json`. These are **different file formats** (`MemoryFact` has `content` + `createdAt` + `lastVerifiedAt`, `AppMemoryFact` has `description` + `updatedAt` + `scope` + `cause` + `evidence`). **Decision needed:** Either (A) use SDK's `FactStore` directly and accept that `AppMemoryFact` extra fields are lost on round-trip, or (B) create an `AxionFactStore` adapter that serializes `AppMemoryFact` directly but uses SDK's file structure.

**Recommendation (B):** Create `AxionFactStore` adapter (thin wrapper) that:
- Uses SDK's directory structure (`{memoryDir}/{domain}-facts.json`)
- Serializes `AppMemoryFact` directly (preserving scope/cause/evidence)
- Reuses SDK's `FactStore` API shape (`save`, `query`, `listDomains`, `delete`)
- Delegates to SDK's `FactStore` internally but stores in Axion's format

This follows the same pattern as Story 21.1's `AxionRunTracker` adapter.

### Critical: SDK's `FactStore` Default Directory

SDK's `FactStore` defaults to `~/.agent/memory/`. Axion uses a custom `memoryDir` from config. Always pass `memoryDir` explicitly:
```swift
let factStore = FactStore(memoryDir: config.memoryDir)
```

### Critical: `MemoryContextProvider` Cannot Be Fully Replaced

The spec lists `MemoryContextProvider.swift` for deletion, but **SDK's `MemoryContextProvider` (51 lines) is too simple** to replace Axion's version (331 lines). SDK only does `buildContext(domain:facts:) -> String?`. Axion has:
- Domain inference from task description (`appNameMap` with Chinese/English keywords)
- Skill-scoped memory context (`buildSkillMemoryContext`)
- Chinese formatting labels (推荐路径, 注意事项, 环境备注)
- Legacy `MemoryStoreProtocol` support

**Keep `MemoryContextProvider.swift`** but adapt it to use SDK's `FactStore` as the data source instead of Axion's `MemoryFactStore`.

### Critical: Type Name Collisions

Same challenge as Stories 21.1 and 21.2. Both SDK and Axion define:
- `MemoryFactStatus` enum (identical)
- `MemoryFactSource` enum (Axion has `.local`, SDK has `.observation`)
- `MemoryKind` enum (identical)
- `MemoryLifecycleService` struct (different — operates on different fact types)
- `MemoryContextProvider` struct (different — SDK is 51 lines, Axion is 331 lines)
- `MemoryBundle` struct (different — stores different fact types)
- `FactFilter` struct (Axion defines it, SDK has its own)

Use targeted imports and private typealiases:
```swift
import struct OpenAgentSDK.MemoryFact
import actor OpenAgentSDK.Stores.FactStore as SDKFactStore
```

### File Read Order (READ BEFORE MODIFYING)

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

**DELETE (7 files, ~2,147 lines):**
- `Tests/AxionCLITests/Memory/MemoryFactStoreTests.swift` (223 lines)
- `Tests/AxionCLITests/Memory/MemoryLifecycleServiceTests.swift` (278 lines)
- `Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift` (758 lines)
- `Tests/AxionCLITests/Memory/MemoryBundleTests.swift` (73 lines)
- `Tests/AxionCLITests/Memory/MemoryBundleExportServiceTests.swift` (134 lines)
- `Tests/AxionCLITests/Memory/MemoryBundleImportServiceTests.swift` (476 lines)
- `Tests/AxionCLITests/Memory/MemoryCleanupServiceTests.swift` (205 lines)

**ADAPT (7 files):**
- `Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift` (844 lines)
- `Tests/AxionCLITests/Memory/AppMemoryFactTests.swift` (254 lines) — add conversion tests
- `Tests/AxionCLITests/Memory/AppProfileAnalyzerTests.swift` (608 lines)
- `Tests/AxionCLITests/Memory/SkillMemoryTests.swift` (413 lines)
- `Tests/AxionCLITests/Memory/FamiliarityTrackerTests.swift` (245 lines)
- `Tests/AxionCLITests/Memory/TakeoverLearningServiceTests.swift` (266 lines)
- `Tests/AxionCLITests/Memory/TakeoverMarkerTests.swift` (286 lines)

**ADAPT command tests (5 files):**
- `Tests/AxionCLITests/Commands/MemoryExportCommandTests.swift` (91 lines)
- `Tests/AxionCLITests/Commands/MemoryImportCommandTests.swift` (114 lines)
- `Tests/AxionCLITests/Commands/MemoryLearnTakeoverCommandTests.swift` (123 lines)
- `Tests/AxionCLITests/Commands/MemoryListCommandTests.swift` (234 lines)
- `Tests/AxionCLITests/Commands/MemoryClearCommandTests.swift` (197 lines)

### Project Structure Notes

- **Deleted source files (6):** MemoryFactStore, MemoryLifecycleService, MemoryBundle, MemoryBundleExportService, MemoryBundleImportService, MemoryCleanupService
- **Kept + Adapted source files (8):** AppMemoryFact (add conversion), MemoryContextProvider (use SDK FactStore), RunMemoryProcessor, TakeoverLearningService, AppMemoryExtractor, AppProfileAnalyzer, FamiliarityTracker, TakeoverMarker
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

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
