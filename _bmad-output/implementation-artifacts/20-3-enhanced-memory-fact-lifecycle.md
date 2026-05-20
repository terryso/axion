# Story 20.3: 增强 Memory — Fact-based 生命周期与分类

Status: done

## Story

As an SDK developer,
I want the SDK to provide a Fact-based enhanced Memory system,
so that all Agents can accumulate and reuse structured experience backed by evidence, instead of simple text records.

## Acceptance Criteria

1. **AC1: `MemoryFact` model** — Given `MemoryFact`, when created via `MemoryFact.create(domain:kind:description:)`, it contains factId (djb2 deterministic hash of kind + normalized description), domain, content, status (candidate/active/retired), confidence (0–1), evidenceCount, source (observation/imported), kind (affordance/avoid/observation), createdAt, lastVerifiedAt. `Sendable, Codable, Equatable`.

2. **AC2: `FactStore` actor** — Given `FactStore(memoryDir:)`, when calling `save(domain:fact:)`, it persists facts as JSON files at `{memoryDir}/{domain}-facts.json`. Supports `query(domain:filter:)` with optional status/kind filtering, `delete(domain:)`, `listDomains()`. Performs lazy migration from legacy `KnowledgeEntry` `{domain}.json` files when reading.

3. **AC3: `MemoryLifecycleService`** — Given a `MemoryLifecycleService` struct (pure computation, no I/O), when `addFact(_:mergingWith:)` is called, it merges by factId: sums evidenceCount, takes max confidence, keeps latest updatedAt. Retired facts matching by id get reactivated as candidate with evidenceCount=1.

4. **AC4: Candidate → Active promotion** — Given a candidate fact with evidenceCount >= 2 AND confidence >= 0.65, when lifecycle check runs, it auto-promotes to active with a +0.1 confidence boost (capped at 1.0).

5. **AC5: Active → Retired demotion** — Given an active fact not verified for 30+ days (2,592,000 seconds), when lifecycle check runs, it demotes to retired. Retired facts re-observed get reactivated as candidate with evidenceCount=1.

6. **AC6: `MemoryContextProvider`** — Given `MemoryContextProvider`, when `buildContext(domain:facts:)` is called, it formats active facts by kind: affordance (recommended paths), avoid (cautions), observation (environment notes). Each kind capped at 5 entries sorted by confidence descending. Prepended with "soft hints, not hard rules" declaration.

7. **AC7: `MemoryBundleExportService`** — Given `MemoryBundleExportService`, when `exportAll(store:)` or `exportDomain(store:domain:)` is called, it outputs a `MemoryBundle` JSON with schema_version, exported_at, and memories array of domain→facts. Uses Codable with iso8601 dates.

8. **AC8: `MemoryBundleImportService`** — Given `MemoryBundleImportService`, when `importBundle(from:store:)` is called, all imported facts are downgraded: status forced to candidate, confidence capped at 0.55, source marked as imported. Matching existing facts by id are merged (stronger status wins, max confidence, evidence deduplication keeping latest 5).

9. **AC9: Unit tests** — MemoryFact (creation, id determinism, normalization, Codable round-trip), FactStore (CRUD, lazy migration from KnowledgeEntry, query filtering), MemoryLifecycleService (merge, promotion, demotion, reactivation), MemoryContextProvider (formatting, per-kind cap, empty input), MemoryBundleExportService (full export, single domain), MemoryBundleImportService (import, downgrade, merge, schema validation) are covered by unit tests.

10. **AC10: Build and test pass** — `swift build` with zero errors and zero warnings. All existing tests pass with zero regression.

## Tasks / Subtasks

- [x] Task 1: Add MemoryFact and supporting types (AC: #1)
  - [x] Create `Sources/OpenAgentSDK/Types/MemoryFact.swift`
  - [x] Define `MemoryFactStatus` enum (candidate, active, retired) — `Codable, Sendable, Equatable, CaseIterable`
  - [x] Define `MemoryFactSource` enum (observation, imported) — `Codable, Sendable, Equatable`
  - [x] Define `MemoryKind` enum (affordance, avoid, observation) — `Codable, Sendable, Equatable, CaseIterable`
  - [x] Define `MemoryFact` struct — `Codable, Sendable, Equatable`
  - [x] Stored properties: id, domain, content, status, confidence, evidenceCount, source, kind, createdAt, lastVerifiedAt
  - [x] `static func create(domain:kind:description:confidence:source:)` — generates deterministic djb2 id, sets defaults
  - [x] `static func factId(kind:description:) -> String` — djb2 hash of normalized description
  - [x] `static func normalize(_:) -> MemoryFact` — clamp confidence 0–1, evidenceCount >= 0, valid status

- [x] Task 2: Implement FactStore actor (AC: #2)
  - [x] Create `Sources/OpenAgentSDK/Stores/FactStore.swift`
  - [x] `actor FactStore` — reads/writes `{domain}-facts.json` files
  - [x] `init(memoryDir: String)` — resolves directory, loads cache
  - [x] `func save(domain:fact:) throws` — upsert by id, flush to disk
  - [x] `func saveAll(domain:facts:) throws` — batch upsert
  - [x] `func query(domain:filter:) throws -> [MemoryFact]` — filter by status, kind
  - [x] `func delete(domain:) throws` — remove domain file
  - [x] `func listDomains() throws -> [String]` — discover both new and legacy files
  - [x] Lazy migration: when reading `{domain}.json` (KnowledgeEntry format), convert to MemoryFact and write as `{domain}-facts.json`
  - [x] `FactFilter` struct (status: MemoryFactStatus?, kind: MemoryKind?) — `Sendable, Equatable`

- [x] Task 3: Implement MemoryLifecycleService (AC: #3, #4, #5)
  - [x] Create `Sources/OpenAgentSDK/Utils/MemoryLifecycleService.swift`
  - [x] `struct MemoryLifecycleService` — pure computation, no I/O, no actor
  - [x] `func addFact(_:mergingWith:) -> MemoryFact` — new or merge by id
  - [x] `func mergeFact(existing:incoming:) -> MemoryFact` — max confidence, sum evidence, check promotion
  - [x] `func maybePromote(fact:) -> MemoryFact?` — candidate→active if evidenceCount >= 2 && confidence >= 0.65
  - [x] `func demoteRetired(facts:lastVerifiedBefore:) -> [MemoryFact]` — active→retired for stale facts
  - [x] `func reactivateRetired(fact:) -> MemoryFact` — retired→candidate with evidenceCount=1
  - [x] `func selectActiveFacts(domain:from:) -> [MemoryFact]` — filter + sort by confidence descending

- [x] Task 4: Implement MemoryContextProvider (AC: #6)
  - [x] Create `Sources/OpenAgentSDK/Utils/MemoryContextProvider.swift`
  - [x] `struct MemoryContextProvider`
  - [x] `func buildContext(domain:facts:) -> String?` — returns nil for empty input
  - [x] Groups active facts by kind: affordance, avoid, observation
  - [x] Each kind capped at 5 entries (configurable via `maxFactsPerKind`), sorted by confidence descending
  - [x] Output format: markdown with headers, bullet items with confidence/evidence annotations
  - [x] Prepended with "soft hints, not hard rules" declaration
  - [x] `static let maxFactsPerKind = 5`

- [x] Task 5: Implement MemoryBundle model (AC: #7, #8)
  - [x] Create `Sources/OpenAgentSDK/Types/MemoryBundle.swift`
  - [x] `MemoryBundle` struct — `Codable, Equatable, Sendable`: schemaVersion, exportedAt, memories: [ExportedDomain]
  - [x] `ExportedDomain` struct — `Codable, Equatable, Sendable`: domain: String, facts: [MemoryFact]
  - [x] CodingKeys for snake_case JSON fields

- [x] Task 6: Implement MemoryBundleExportService (AC: #7)
  - [x] Create `Sources/OpenAgentSDK/Utils/MemoryBundleExportService.swift`
  - [x] `struct MemoryBundleExportService`
  - [x] `func exportAll(store:) async throws -> MemoryBundle` — all domains
  - [x] `func exportDomain(store:domain:) async throws -> MemoryBundle` — single domain
  - [x] `func writeBundle(_:to:) throws` — JSON to disk (sorted keys, pretty-printed, iso8601 dates)

- [x] Task 7: Implement MemoryBundleImportService (AC: #8)
  - [x] Create `Sources/OpenAgentSDK/Utils/MemoryBundleImportService.swift`
  - [x] `struct MemoryBundleImportService`
  - [x] `func importBundle(from:store:) async throws -> ImportResult`
  - [x] Validate schema_version == 1
  - [x] Downgrade imported facts: status→candidate, confidence capped at 0.55, source→imported
  - [x] Merge matching facts: stronger status wins, max confidence, evidence dedup (keep latest 5)
  - [x] `ImportResult` struct: domainsProcessed, factsImported, factsMerged, errors
  - [x] `MemoryBundleError` enum: invalidBundle(reason)

- [x] Task 8: Unit tests (AC: #9)
  - [x] Create `Tests/OpenAgentSDKTests/Types/MemoryFactTests.swift`
    - [x] Test deterministic id generation (same input → same id)
    - [x] Test different inputs → different ids
    - [x] Test confidence clamping in normalize
    - [x] Test Codable round-trip
  - [x] Create `Tests/OpenAgentSDKTests/Stores/FactStoreTests.swift`
    - [x] Test save and query CRUD
    - [x] Test upsert behavior (same id updates)
    - [x] Test query filtering by status and kind
    - [x] Test lazy migration from KnowledgeEntry files
    - [x] Test listDomains discovers both formats
    - [x] Test delete removes domain
  - [x] Create `Tests/OpenAgentSDKTests/Utils/MemoryLifecycleServiceTests.swift`
    - [x] Test addFact creates new
    - [x] Test addFact merges with existing
    - [x] Test addFact reactivates retired
    - [x] Test promotion: evidenceCount >= 2 && confidence >= 0.65
    - [x] Test no promotion below thresholds
    - [x] Test demotion: stale active facts
    - [x] Test reactivation of retired
    - [x] Test selectActiveFacts sorting by confidence
  - [x] Create `Tests/OpenAgentSDKTests/Utils/MemoryContextProviderTests.swift`
    - [x] Test returns nil for empty facts
    - [x] Test groups by kind correctly
    - [x] Test caps at 5 per kind
    - [x] Test sorts by confidence descending
    - [x] Test includes soft hints declaration
  - [x] Create `Tests/OpenAgentSDKTests/Utils/MemoryBundleExportServiceTests.swift`
    - [x] Test exportAll includes all domains
    - [x] Test exportDomain for single domain
    - [x] Test writeBundle produces valid JSON
  - [x] Create `Tests/OpenAgentSDKTests/Utils/MemoryBundleImportServiceTests.swift`
    - [x] Test import with valid bundle
    - [x] Test downgrade: status forced to candidate, confidence capped at 0.55
    - [x] Test merge with existing facts
    - [x] Test reject invalid schema_version
    - [x] Test ImportResult counts

- [x] Task 9: Verify build and tests (AC: #10)
  - [x] `swift build` — 0 errors, 0 warnings
  - [x] Run full test suite — 0 failures

## Dev Notes

### Architecture Compliance

- **Module boundary:** `MemoryFact`, `MemoryFactStatus`, `MemoryFactSource`, `MemoryKind`, `MemoryBundle`, `ExportedDomain` go in `Types/`. `FactStore` goes in `Stores/`. `MemoryLifecycleService`, `MemoryContextProvider`, `MemoryBundleExportService`, `MemoryBundleImportService` go in `Utils/`. This follows existing patterns: `MemoryTypes.swift` (Types/) for data models, `MemoryStore.swift` (Stores/) for persistence, `SessionMemory.swift` (Utils/) for logic.
- **FactStore is an actor:** Like all stores in this project (SessionStore, TaskStore, TeamStore, InMemoryStore, FileBasedMemoryStore), FactStore must be an actor for thread-safe file I/O.
- **MemoryLifecycleService is a struct (pure computation):** No state, no I/O — just transforms facts. Same pattern as `TraceEventMapping` (pure functions). Easy to unit test.
- **MemoryContextProvider is a struct:** Read-and-format service, no mutable state. Same pattern as the Axion version.
- **No Apple-proprietary frameworks:** All file I/O uses Foundation (FileManager, JSONEncoder/Decoder). Cross-platform.
- **JSON boundary:** FactStore uses Codable (not raw `[String: Any]`) for the new fact files — these are SDK-internal structured data, not LLM API communication. The legacy migration path handles raw JSON for KnowledgeEntry files.

### Key Design Decisions

1. **FactStore is a new actor, NOT extending MemoryStoreProtocol:** The existing `MemoryStoreProtocol` (save/query/delete/listDomains) operates on `KnowledgeEntry` with a flat content+tags model. Facts have a fundamentally different shape (status, confidence, evidenceCount, kind, lifecycle). Rather than breaking the existing protocol, FactStore is a separate actor. The lazy migration bridge reads old KnowledgeEntry files but writes the new format.

2. **djb2 hash for deterministic fact IDs:** Same as Axion. Ensures the same observation produces the same id across process restarts, enabling correct merge/dedup. `factId(kind:description:)` normalizes the description (lowercased, trimmed) before hashing.

3. **Lazy migration, not eager:** When FactStore encounters a legacy `{domain}.json` file (KnowledgeEntry format), it migrates it to `{domain}-facts.json` on first read. Legacy entries become `MemoryFact` with status=candidate, confidence=0.5, kind=observation, evidenceCount=1. The original file is NOT deleted — both files coexist until the old one is manually cleaned up.

4. **No scope/cause fields from Axion:** The Axion `AppMemoryFact` has `scope` and `cause` fields that are desktop-agent-specific (e.g., `scope: "window-title:Calculator"`). The SDK version omits these. Only the universal fields are kept: id, domain, content, status, confidence, evidenceCount, source, kind, timestamps.

5. **MemoryContextProvider is domain-agnostic:** Unlike the Axion version (which has a hardcoded `appNameMap` for macOS app name → bundle identifier mapping), the SDK version takes `(domain:facts:)` parameters. Domain inference is the caller's responsibility — the SDK doesn't prescribe how domains map to real-world entities.

### Integration Points with Existing SDK

- **MemoryTypes.swift** (`Types/MemoryTypes.swift`): Existing `KnowledgeEntry`, `KnowledgeQueryFilter`, `MemoryStoreProtocol`. **Not modified** — FactStore is additive.
- **MemoryStore.swift** (`Stores/MemoryStore.swift`): Existing `InMemoryStore` and `FileBasedMemoryStore`. **Not modified** — FactStore is a separate actor.
- **FileBasedMemoryStore default path**: `~/.agent/memory/`. FactStore should use the same base path for consistency. The `{domain}-facts.json` naming avoids collision with existing `{domain}.json` files.
- **Logger.shared**: Use existing Logger for warnings (corrupt files, migration issues) per project convention.

### What NOT to Extract from Axion

These are Axion-specific and must NOT be included in the SDK:
- `appNameMap` (MemoryContextProvider) — hardcoded macOS app name → bundle ID mapping
- `scope` field (AppMemoryFact) — desktop window-scoped facts
- `cause` field (AppMemoryFact) — desktop-specific cause tracking
- `FamiliarityTracker` — desktop app familiarity tracking
- `AppProfileAnalyzer` — macOS Accessibility profile analysis
- `RunMemoryProcessor` — Axion-specific run-to-memory extraction
- `AppMemoryExtractor` — desktop accessibility tree extraction
- `TakeoverLearningService` / `TakeoverMarker` — desktop visual takeover learning
- `MemoryCleanupService` — Axion-specific cleanup scheduling

### File Structure

```
Sources/OpenAgentSDK/Types/
  MemoryFact.swift              # MemoryFact, MemoryFactStatus, MemoryFactSource, MemoryKind (NEW)
  MemoryBundle.swift            # MemoryBundle, ExportedDomain (NEW)

Sources/OpenAgentSDK/Stores/
  FactStore.swift               # FactStore actor + FactFilter (NEW)

Sources/OpenAgentSDK/Utils/
  MemoryLifecycleService.swift  # Pure fact lifecycle logic (NEW)
  MemoryContextProvider.swift   # Prompt formatting from facts (NEW)
  MemoryBundleExportService.swift  # Export facts as JSON bundle (NEW)
  MemoryBundleImportService.swift  # Import + downgrade + merge (NEW)

Tests/OpenAgentSDKTests/Types/
  MemoryFactTests.swift         # MemoryFact model tests (NEW)

Tests/OpenAgentSDKTests/Stores/
  FactStoreTests.swift          # FactStore CRUD + migration tests (NEW)

Tests/OpenAgentSDKTests/Utils/
  MemoryLifecycleServiceTests.swift    # Lifecycle logic tests (NEW)
  MemoryContextProviderTests.swift     # Context formatting tests (NEW)
  MemoryBundleExportServiceTests.swift # Export tests (NEW)
  MemoryBundleImportServiceTests.swift # Import tests (NEW)
  MemoryLifecycleIntegrationTests.swift # Integration tests across all components (NEW)
```

### Modified Files

None — this story is purely additive. All existing files remain unchanged.

### Previous Story Learnings (Stories 20.1, 20.2)

- Build baseline: 4862 tests passing. Any regression check must match this baseline.
- `nonisolated(unsafe)` for simple flags when actor isolation isn't needed
- Swift 6.1 strict concurrency: closures need explicit capture lists to avoid capturing `self`
- `NSLock` for protecting mutable state in non-actor contexts
- `FileHandle` writes need careful error handling
- Hummingbird 2.x already added as dependency — no new dependencies needed
- `ISO8601DateFormatter` should be instance property on actors (not allocated per call) — M1 fix from Story 20.2 review
- Test counts in completion notes must match actual test count — L1 fix from Story 20.2 review

### Testing Strategy

- **Unit tests:** All new components tested in isolation. Use temp directories for FactStore file tests.
- **No E2E tests for this story** — these are infrastructure utilities, not agent-facing features.
- **FactStore tests:** Write to temp dir, verify JSON read/write, verify lazy migration from KnowledgeEntry files, verify query filtering.
- **Lifecycle tests:** All paths (new, merge, promote, demote, reactivate) tested as pure functions.
- **Context provider tests:** Verify grouping, capping, sorting, formatting.
- **Import/export tests:** Verify JSON round-trip, downgrade logic, merge logic, schema validation.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 20 Story 20.3]
- [Source: _bmad-output/project-context.md]
- [Source: _bmad-output/implementation-artifacts/20-1-agent-http-server.md — Previous story learnings]
- [Source: _bmad-output/implementation-artifacts/20-2-cost-tracker-trace-recorder.md — Previous story learnings]
- [Reference: /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Memory/AppMemoryFact.swift — Fact model]
- [Reference: /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Memory/MemoryFactStore.swift — Persistence]
- [Reference: /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Memory/MemoryLifecycleService.swift — Lifecycle logic]
- [Reference: /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Memory/MemoryContextProvider.swift — Context formatting]
- [Reference: /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Memory/MemoryBundleExportService.swift — Export]
- [Reference: /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Memory/MemoryBundleImportService.swift — Import]
- [Reference: /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Memory/MemoryBundle.swift — Bundle model]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Fixed testCodableRoundTrip: ISO8601 date encoding truncates fractional seconds, causing Equatable failure. Changed to field-by-field comparison.
- Fixed testAddFactMergesWithExisting: Merge result triggered auto-promotion (+0.1 boost) because evidenceCount reached 2 and confidence was 0.7 (>= 0.65). Adjusted test values to stay below promotion threshold.
- Fixed testNoDemotionOfRecentActiveFacts: Date() for lastVerifiedAt is not strictly less than Date() cutoff. Changed cutoff to 1 second in the past.

### Completion Notes List

- Implemented MemoryFact model with djb2 deterministic hashing, supporting enums (MemoryFactStatus, MemoryFactSource, MemoryKind)
- Implemented FactStore actor with CRUD, Codable-based JSON persistence, and lazy migration from legacy KnowledgeEntry files
- Implemented MemoryLifecycleService as a pure-computation struct with add/merge/promote/demote/reactivate operations
- Implemented MemoryContextProvider with per-kind grouping, 5-entry cap, confidence-descending sort, and "soft hints" preamble
- Implemented MemoryBundle model with snake_case CodingKeys for export/import
- Implemented MemoryBundleExportService with exportAll, exportDomain, and writeBundle
- Implemented MemoryBundleImportService with downgrade (candidate/0.55 cap/imported), merge (stronger status, max confidence, evidence cap at 5), and schema validation
- 69 new unit tests across 7 test files — all passing
- Full suite: 4931 tests passing (baseline 4862 + 69 new), 0 failures, 14 skipped
- Zero existing files modified — purely additive story

### File List

New files:
- Sources/OpenAgentSDK/Types/MemoryFact.swift
- Sources/OpenAgentSDK/Types/MemoryBundle.swift
- Sources/OpenAgentSDK/Stores/FactStore.swift
- Sources/OpenAgentSDK/Utils/MemoryLifecycleService.swift
- Sources/OpenAgentSDK/Utils/MemoryContextProvider.swift
- Sources/OpenAgentSDK/Utils/MemoryBundleExportService.swift
- Sources/OpenAgentSDK/Utils/MemoryBundleImportService.swift
- Tests/OpenAgentSDKTests/Types/MemoryFactTests.swift
- Tests/OpenAgentSDKTests/Stores/FactStoreTests.swift
- Tests/OpenAgentSDKTests/Utils/MemoryLifecycleServiceTests.swift
- Tests/OpenAgentSDKTests/Utils/MemoryContextProviderTests.swift
- Tests/OpenAgentSDKTests/Utils/MemoryBundleExportServiceTests.swift
- Tests/OpenAgentSDKTests/Utils/MemoryBundleImportServiceTests.swift
- Tests/OpenAgentSDKTests/Utils/MemoryLifecycleIntegrationTests.swift

## Change Log

- 2026-05-20: Story 20.3 implemented — added Fact-based enhanced Memory system with lifecycle management, context formatting, and import/export services. 68 new tests, all passing. No existing files modified.
- 2026-05-20: Code review fixes — propagate migration errors, normalize facts before persisting, atomic file writes, pure reactivateRetired with date parameter. 69 tests passing.
