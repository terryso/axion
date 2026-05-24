# Story 23.2: SessionSearchPlugin — 会话全文搜索

Status: done

## Story

As an SDK developer,
I want a session search plugin that enables full-text search across all persisted sessions,
so that agents can discover and recall relevant past conversations without any LLM cost.

## Acceptance Criteria

1. **AC1: `SessionSearchMode` enum** — Defined in `Types/SessionSearchTypes.swift`. `public enum`, `String`, `Codable`, `Sendable`, `Equatable`, `CaseIterable`. Cases: `discover` (keyword search across all sessions), `scroll` (browse messages around a specific point in one session), `browse` (list recent sessions).

2. **AC2: `SessionSearchQuery` struct** — Defined in `Types/SessionSearchTypes.swift`. `public struct`, `Sendable`, `Equatable`. Fields: `mode` (SessionSearchMode), `query` (String?, nil for browse), `sessionId` (String?, nil for discover/browse), `aroundMessageIndex` (Int?, nil unless scroll), `limit` (Int, default 10). Validation: `discover` requires non-nil `query`; `scroll` requires non-nil `sessionId`; `browse` requires nil `query` and nil `sessionId`. Invalid combinations throw via a `validate()` method that throws `SDKError.invalidConfiguration`.

3. **AC3: `SessionSearchResult` struct** — Defined in `Types/SessionSearchTypes.swift`. `public struct`, `Sendable`, `Equatable`. Fields: `mode` (SessionSearchMode), `matchedSessionId` (String?), `matchedMessageIndex` (Int?), `messages` ([SessionMessage] — the context window), `totalMatches` (Int?, nil for scroll/browse), `hasMore` (Bool). For `discover`: contains matching message and surrounding context (±5 messages). For `scroll`: contains messages around `aroundMessageIndex`. For `browse`: contains `matchedSessionId` and summary info with `messages` empty.

4. **AC4: `SessionSearchEngine` struct** — Defined in `Utils/SessionSearchEngine.swift`. `public struct`, `Sendable`. Pure computation engine (no mutable state). Takes a `SessionStore` reference and performs searches:
   - `func search(_ query: SessionSearchQuery, store: SessionStore) async throws -> [SessionSearchResult]` — main entry point, dispatches by mode.
   - `discover` mode: iterate all sessions via `store.list()`, load each, scan messages for case-insensitive substring match of `query` in message content, return results sorted by session `updatedAt` descending. Each result includes ±5 messages around the match (clamped to bounds).
   - `scroll` mode: load the specific session via `store.load()`, extract messages around `aroundMessageIndex` (±10 message window, clamped). Return a single result.
   - `browse` mode: return results from `store.list()` with `limit` applied, one `SessionSearchResult` per session with summary fields populated and `messages` empty.
   - All modes are pure database/file operations — zero LLM calls.

5. **AC5: `SessionSearchPlugin` actor** — Defined in `Utils/SessionSearchPlugin.swift`. `public actor`, conforms to `SelfEvolutionPlugin`. Properties:
   - `name`: `"session-search"` (constant)
   - `supportedPhases`: `{.initialize, .prefetch}`
   - Private `searchEngine: SessionSearchEngine` (created in init)
   - Private `store: SessionStore?` (set during initialize)
   - `func initialize(sessionId:)`: store the `SessionStore` from plugin config or create a default one.
   - `func onPhase(_:context:)`:
     - On `.prefetch`: perform a search if `context.currentQuery` is non-nil and plugin is configured for auto-search. Return `PluginResult.systemPromptBlock` with formatted search context to inject into system prompt.
     - On `.initialize`: no-op (already handled).
     - All other phases: return `.none`.
   - `func shutdown()`: release store reference.

6. **AC6: Plugin config via `EvolutionPluginConfig`** — `SessionSearchPlugin` reads its config from `EvolutionPluginConfig.config` dictionary. Supported keys: `"autoSearch"` ("true"/"false", default "true"), `"maxResults"` (int string, default "5"), `"contextWindow"` (int string, default "5" for ±5 messages). The plugin is instantiated by the host application and registered with `PluginRegistry`.

7. **AC7: Exposed tool schemas** — `SessionSearchPlugin.onPhase(.prefetch, ...)` returns `PluginResult.toolSchemas` containing JSON Schema for a `session_search` tool so the LLM can invoke search on demand. Schema: `{ type: "object", properties: { query: { type: "string", description: "..." }, session_id: { type: "string" }, mode: { type: "string", enum: ["discover", "scroll", "browse"] } }, required: ["mode"] }`.

8. **AC8: Module boundary compliance** — `Types/SessionSearchTypes.swift` lives in `Types/` and depends only on other Types (SessionMessage, SessionMetadata, SDKError). `SessionSearchEngine` lives in `Utils/` and depends on `Types/` + `Stores/SessionStore` (same pattern as existing Utils). `SessionSearchPlugin` lives in `Utils/` and depends on `Types/` (for plugin types, search types) + `Stores/` (for SessionStore). No imports of `Core/` or `Tools/` from any new file.

9. **AC9: Unit tests** — All new code tested:
   - `SessionSearchMode`: CaseIterable, rawValue round-trip
   - `SessionSearchQuery`: valid construction for each mode, validation rejects invalid combinations (discover without query, scroll without sessionId)
   - `SessionSearchResult`: construction, equality
   - `SessionSearchEngine`: discover returns matching sessions (use temp directory with pre-saved sessions), scroll returns context window, browse returns session list, empty results for no matches, pagination via limit
   - `SessionSearchPlugin`: name is "session-search", supportedPhases correct, initialize sets store, onPhase returns correct PluginResult types, shutdown clears state
   - All store tests use temp directories (no real I/O paths per project convention)

10. **AC10: Build and test pass** — `swift build` with zero errors. Full test suite passes with zero regression.

## Tasks / Subtasks

- [x] Task 1: Define search type models (AC: #1, #2, #3)
  - [x] Create `Sources/OpenAgentSDK/Types/SessionSearchTypes.swift`
  - [x] Add `SessionSearchMode` enum with three cases
  - [x] Add `SessionSearchQuery` struct with validation
  - [x] Add `SessionSearchResult` struct

- [x] Task 2: Create `SessionSearchEngine` (AC: #4)
  - [x] Create `Sources/OpenAgentSDK/Utils/SessionSearchEngine.swift`
  - [x] Implement `discover` mode — cross-session keyword search with ±5 context window
  - [x] Implement `scroll` mode — single-session message window browsing
  - [x] Implement `browse` mode — recent session listing
  - [x] Use `SessionStore.list()` and `SessionStore.load()` for data access

- [x] Task 3: Create `SessionSearchPlugin` (AC: #5, #6, #7)
  - [x] Create `Sources/OpenAgentSDK/Utils/SessionSearchPlugin.swift`
  - [x] Implement `SelfEvolutionPlugin` conformance
  - [x] Implement `initialize` to set up store reference
  - [x] Implement `onPhase(.prefetch)` for auto-search + tool schema exposure
  - [x] Implement config parsing from `EvolutionPluginConfig.config`

- [x] Task 4: Unit tests for search types (AC: #9)
  - [x] Create `Tests/OpenAgentSDKTests/Utils/SessionSearchTypesTests.swift`
  - [x] Test SessionSearchMode cases and rawValues
  - [x] Test SessionSearchQuery valid/invalid construction
  - [x] Test SessionSearchResult construction and equality

- [x] Task 5: Unit tests for SessionSearchEngine (AC: #9)
  - [x] Create `Tests/OpenAgentSDKTests/Utils/SessionSearchEngineTests.swift`
  - [x] Test discover mode with pre-saved sessions in temp dir
  - [x] Test scroll mode with context window
  - [x] Test browse mode with session listing
  - [x] Test edge cases: no matches, empty sessions, pagination

- [x] Task 6: Unit tests for SessionSearchPlugin (AC: #9)
  - [x] Create `Tests/OpenAgentSDKTests/Utils/SessionSearchPluginTests.swift`
  - [x] Test plugin name, supportedPhases
  - [x] Test initialize/shutdown lifecycle
  - [x] Test onPhase returns correct PluginResult types
  - [x] Test config parsing

- [x] Task 7: Verify build and tests (AC: #10)
  - [x] `swift build` — 0 errors
  - [x] Full test suite — 0 failures

## Dev Notes

### Architecture Compliance

- **`Types/SessionSearchTypes.swift`**: Search data models. Types/ is the leaf dependency — no outbound imports beyond other Types. References `SessionMessage` (from `SessionTypes.swift`), `SDKError` (from `SDKError.swift`).
- **`Utils/SessionSearchEngine.swift`**: Pure computation struct in Utils/. Depends on `Types/` (search types, SessionMessage) and `Stores/SessionStore` (for data access). Same pattern as `LLMExperienceExtractor`, `SkillUsageTracker` — Utils/ depends on Types/ and Stores/.
- **`Utils/SessionSearchPlugin.swift`**: Plugin implementation in Utils/. Depends on `Types/` (plugin types, search types) and `Stores/` (SessionStore). Conforms to `SelfEvolutionPlugin` protocol from `PluginEvolutionTypes.swift`.
- **No new external dependencies**: No SQLite needed. The search uses the existing `SessionStore` JSON file infrastructure with in-memory substring matching. This avoids adding a new SPM dependency and keeps the plugin lightweight.
- **No Apple-proprietary frameworks**: Foundation only.

### Key Design Decisions

1. **No SQLite/FTS5**: The project has zero SQLite usage and no SPM dependency for it. Adding SQLite would be a heavy new dependency. Instead, the search engine reads session JSON files via the existing `SessionStore` API and performs case-insensitive substring matching in memory. This is sufficient for the typical session count (dozens to hundreds of sessions). If performance becomes an issue, a future story can add SQLite caching.

2. **`SessionSearchEngine` is a pure struct**: No mutable state, no actor needed. The `SessionStore` actor handles thread safety for file access. The engine takes a `SessionStore` reference and performs pure computation on the results.

3. **Three search modes map to Hermes `session_search` API**: The Hermes Python SDK has `session_search(query=)`, `session_search(session_id=, around_message_id=)`, and `session_search()` (no args = list recent). Our `SessionSearchMode` enum captures these three patterns.

4. **Context window of ±5 messages**: Matches the Hermes specification. For `scroll` mode, a wider ±10 window is used for browsing.

5. **Plugin exposes tool schema via `PluginResult.toolSchemas`**: The `SessionSearchPlugin` returns tool schemas on `.prefetch` so the LLM can invoke search as a tool. The actual tool execution is handled by the plugin framework (to be wired in future stories). For now, the plugin returns the schema and any auto-search results as a system prompt block.

6. **Config via `EvolutionPluginConfig.config` dictionary**: Simple key-value string config. `autoSearch` controls whether the plugin automatically searches on every prefetch; `maxResults` caps results; `contextWindow` sets the ±N window size.

7. **`SessionSearchPlugin` is an actor**: Conforms to `SelfEvolutionPlugin` which requires `Sendable`. Using `actor` provides natural isolation for the mutable `store` reference. Same pattern as other stateful components in the SDK.

### Integration Points with Existing SDK

- **`Types/PluginEvolutionTypes.swift`** (Story 23.1): `SelfEvolutionPlugin` protocol, `PluginResult`, `PluginContext`, `PluginLifecyclePhase`, `EvolutionPluginConfig`. The search plugin implements this protocol.
- **`Hooks/PluginRegistry.swift`** (Story 23.1): `PluginRegistry` actor where the search plugin will be registered at agent creation time.
- **`Types/SessionTypes.swift`**: `SessionMessage`, `SessionMetadata`, `SessionData`. Search results reference `SessionMessage`.
- **`Stores/SessionStore.swift`**: `list()`, `load()`, `save()`. The search engine uses `list()` for browse/discover and `load()` for scroll/discover detail.
- **`Types/AgentTypes.swift`**: `AgentOptions.evolutionPlugins` field (added in 23.1). Configuration entry point.

### Hermes Reference Mapping

```
Hermes trajectory.py               →  SDK Component
──────────────────────────────────────────────────────
session_search(query=)             →  SessionSearchEngine.search(discover, query:)
session_search(session_id=,        →  SessionSearchEngine.search(scroll, sessionId:
  around_message_id=)                  aroundMessageIndex:)
session_search()                   →  SessionSearchEngine.search(browse)
FTS5 full-text search              →  In-memory substring match (no SQLite)
Match fragment ±5 messages         →  SessionSearchResult.messages context window
Session opening 3 msgs +           →  Not needed for plugin use case (agent
  closing 3 msgs                      reads full context window, not snippets)
```

### Previous Story Learnings (Story 23.1)

- **Build baseline**: 5,292 tests passing. Any regression check must match this baseline.
- **`nonisolated(unsafe)`** for simple flags when actor isolation isn't needed.
- **Swift 6.1 strict concurrency**: closures need explicit capture lists. `[String: Any]` dicts need `@unchecked Sendable` wrappers.
- **`Codable` for SDK-internal structured data**, raw `[String: Any]` only for LLM API communication boundary.
- **Pure computation structs preferred** when no mutable state is needed.
- **`precondition()` for config validation** — not `assert()` — catches issues in release builds too.
- **SendableJSONSchema/SendableToolSchemaList pattern**: Wrap `[String: Any]` in `@unchecked Sendable` struct for use in Equatable/Sendable contexts. `PluginResult.toolSchemas` uses `SendableToolSchemaList`.
- **Actor tests use `await`** for all actor-isolated methods.
- **JSON encoder pattern**: `.iso8601` date strategy, `.prettyPrinted` + `.sortedKeys` output formatting.
- **`SharedMockState` pattern**: `final class SharedMockState: @unchecked Sendable` with `NSLock` for test state capture.
- **Logger dependency**: Use `Logger.shared` for structured logging.
- **Module boundary**: Utils/ can depend on Types/ and Stores/. Hooks/ depends on Types/ only.

### File Structure

```
Sources/OpenAgentSDK/Types/
  SessionSearchTypes.swift            # NEW: SessionSearchMode, SessionSearchQuery,
                                      #       SessionSearchResult

Sources/OpenAgentSDK/Utils/
  SessionSearchEngine.swift           # NEW: Pure computation search engine
  SessionSearchPlugin.swift           # NEW: SelfEvolutionPlugin implementation

Tests/OpenAgentSDKTests/Utils/
  SessionSearchTypesTests.swift       # NEW: Type model tests
  SessionSearchEngineTests.swift      # NEW: Engine tests with temp directories
  SessionSearchPluginTests.swift      # NEW: Plugin lifecycle tests
```

### References

- [Source: docs/epics.md — Epic 23, Story 23.2 definition with Hermes trajectory.py references]
- [Source: Sources/OpenAgentSDK/Types/PluginEvolutionTypes.swift — SelfEvolutionPlugin protocol, PluginResult, PluginContext]
- [Source: Sources/OpenAgentSDK/Hooks/PluginRegistry.swift — Plugin registration pattern]
- [Source: Sources/OpenAgentSDK/Types/SessionTypes.swift — SessionMessage, SessionMetadata, SessionData]
- [Source: Sources/OpenAgentSDK/Stores/SessionStore.swift — list(), load(), save(), session persistence]
- [Source: _bmad-output/implementation-artifacts/23-1-self-evolution-plugin-protocol.md — Previous story, plugin protocol patterns]
- [Source: _bmad-output/project-context.md — Architecture rules, module boundaries, actor conventions]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (claude-opus-4-7)

### Debug Log References

- Swift 6 strict concurrency: `[[String: Any]]` arrays cannot be sent across actor boundaries from XCTest instance methods. Resolved by using file-scoped free functions for test message construction instead of class methods.

### Completion Notes List

- Task 1: Created `SessionSearchTypes.swift` with `SessionSearchMode` (3 cases, CaseIterable), `SessionSearchQuery` (with `validate()` throwing `SDKError.invalidConfiguration`), and `SessionSearchResult`.
- Task 2: Created `SessionSearchEngine` as a pure `Sendable` struct. Implements `discover` (keyword search with ±5 context window, sorted by updatedAt desc), `scroll` (±10 message window around index), `browse` (session listing via `store.list()`). Zero LLM calls.
- Task 3: Created `SessionSearchPlugin` as a `public actor` conforming to `SelfEvolutionPlugin`. On `.prefetch`: performs auto-search if `currentQuery` is non-nil and `autoSearch` config is "true", returns `.systemPromptBlock` with results; otherwise returns `.toolSchemas` with `session_search` JSON Schema. Config supports `autoSearch`, `maxResults`, `contextWindow` keys.
- Task 4: 14 type tests covering mode round-trips, query validation for all modes, result construction/equality.
- Task 5: 12 engine tests covering discover (match, context window, no matches, case-insensitive, limit, total count), scroll (context window, clamping, invalid session, empty session), browse (listing, limit, empty dir), and validation.
- Task 6: 10 plugin tests covering identity, lifecycle (init/shutdown), onPhase for all phases, auto-search behavior, config parsing, protocol conformance.
- Task 7: `swift build` passes with 0 errors. Full test suite: **5337 tests passing, 0 failures**.

### Senior Developer Review (AI)

**Reviewer:** Claude (automated review) on 2026-05-23

**Issues found:** 2 High, 4 Medium, 1 Low

**Issues fixed automatically:**

1. **[HIGH] `contextWindow` config not wired through** — `SessionSearchEngine` now accepts `discoverContextWindow` and `scrollContextWindow` init params. `SessionSearchPlugin` reads `contextWindow` from config and passes it to the engine.

2. **[HIGH] `hasMore` always false — pagination broken** — `discover` mode now computes `hasMore=true` on the last result when there are more matching sessions beyond the limit. `browse` mode queries `limit + 1` and sets `hasMore=true` on the last result when extra sessions exist.

3. **[MEDIUM] `initialize()` never reads `sessionsDir` from config** — `SessionSearchPlugin.initialize()` now reads `sessionsDir` from `EvolutionPluginConfig.config` and creates `SessionStore(sessionsDir:)` accordingly.

4. **[MEDIUM] Files not in story File List** — Added `Sources/E2ETest/SessionSearchE2ETests.swift`, `Tests/OpenAgentSDKTests/Utils/SessionSearchE2ETests.swift`, and `Sources/E2ETest/main.swift` to the File List.

5. **[MEDIUM] `.systemPromptBlock` path never tested** — Added `testOnPhasePrefetchAutoSearchReturnsSystemPromptBlock` that seeds a temp directory via `sessionsDir` config, triggers auto-search with a matching query, and verifies the `.systemPromptBlock` result contains the expected session data.

6. **[MEDIUM] Added test coverage** — New tests: `testDiscoverCustomContextWindow`, `testDiscoverHasMoreWhenMoreResultsExist`, `testDiscoverHasMoreFalseWhenAllResultsReturned`, `testScrollCustomContextWindow`, `testBrowseHasMoreWhenMoreResultsExist`, `testBrowseHasMoreFalseWhenAllReturned`, `testConfigSessionsDir`, `testConfigContextWindow`, `testOnPhasePrefetchAutoSearchFallsBackWhenNoMatches`.

**Not fixed (design limitation):**
- **[LOW] Auto-search results hide tool schema** — When auto-search finds matches, `.systemPromptBlock` is returned instead of `.toolSchemas`. This is an AC design constraint (PluginResult is an enum, not a set). Future refactor could split into multiple results or a combined case.

**Post-fix verification:** `swift build` 0 errors. Full test suite: **5361 tests passing, 0 failures** (+9 new tests).

### Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-05-22 | Claude Opus 4.7 | Initial implementation (Tasks 1-7) |
| 2026-05-23 | Claude (review) | Code review: 6 issues fixed (2H, 4M), 9 new tests added, status → done |

### File List

**New files:**
- `Sources/OpenAgentSDK/Types/SessionSearchTypes.swift`
- `Sources/OpenAgentSDK/Utils/SessionSearchEngine.swift`
- `Sources/OpenAgentSDK/Utils/SessionSearchPlugin.swift`
- `Sources/E2ETest/SessionSearchE2ETests.swift`
- `Tests/OpenAgentSDKTests/Utils/SessionSearchTypesTests.swift`
- `Tests/OpenAgentSDKTests/Utils/SessionSearchEngineTests.swift`
- `Tests/OpenAgentSDKTests/Utils/SessionSearchPluginTests.swift`
- `Tests/OpenAgentSDKTests/Utils/SessionSearchE2ETests.swift`

**Modified files:**
- `Sources/E2ETest/main.swift` (added SessionSearchE2ETests.run() call)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (23-2 status: ready-for-dev → in-progress → review → done)
- `_bmad-output/implementation-artifacts/23-2-session-search-plugin.md` (status, tasks, dev agent record)
