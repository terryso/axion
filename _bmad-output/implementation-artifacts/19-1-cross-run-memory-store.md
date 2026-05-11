# Story 19.1: Cross-run Memory Store

Status: done

## Story

As an SDK developer,
I want the SDK to provide a cross-run knowledge accumulation store,
so that all Agent applications can persist and reuse structured experience across multiple executions.

## Acceptance Criteria

1. **AC1: MemoryStore protocol defined** -- `MemoryStoreProtocol` is a public protocol with `save(domain:knowledge:)`, `query(domain:filter:)`, `delete(domain:olderThan:)`, `listDomains()` methods.

2. **AC2: InMemoryStore default implementation** -- `InMemoryStore` (actor) stores knowledge entries by domain with `content`, `tags`, `createdAt`, `sourceRunId` fields. No persistence across process restarts.

3. **AC3: FileBasedMemoryStore persistent implementation** -- `FileBasedMemoryStore` (actor) persists knowledge to disk organized by domain (e.g., `~/.agent/memory/calculator.json`), auto-loads on init. Base directory configurable.

4. **AC4: Auto-expiry** -- Knowledge entries exceeding `maxAge` (default 30 days) are automatically cleaned up on next query.

5. **AC5: AgentOptions integration** -- `AgentOptions` has a `memoryStore` property. When set, `MemoryStoreProtocol` is accessible via `ToolContext.memoryStore` for custom tool read/write.

6. **AC6: Corrupt entry resilience** -- When `FileBasedMemoryStore` encounters a corrupt entry file, it logs a warning via `Logger.shared.warn` and skips the entry without blocking Agent execution.

7. **AC7: Unit tests** -- All store operations (save, query, delete, listDomains, expiry, corrupt-file handling) covered by unit tests in `Tests/OpenAgentSDKTests/Stores/MemoryStoreTests.swift`.

8. **AC8: Build and test pass** -- `swift build` zero errors zero warnings. All existing tests pass with zero regression.

## Tasks / Subtasks

- [x] Task 1: Define MemoryStoreProtocol and KnowledgeEntry types (AC: #1)
  - [x] Create `Sources/OpenAgentSDK/Types/MemoryTypes.swift` with `KnowledgeEntry` struct (content, tags, createdAt, sourceRunId), `KnowledgeQueryFilter` struct (tags, olderThan, newerThan, limit), `MemoryStoreProtocol` with 4 core methods
  - [x] Ensure all types are `Sendable` (entry is struct, protocol conforms to Sendable + Actor)

- [x] Task 2: Implement InMemoryStore actor (AC: #2)
  - [x] Create `Sources/OpenAgentSDK/Stores/MemoryStore.swift` with `InMemoryStore` actor
  - [x] Internal storage: `[String: [KnowledgeEntry]]` dictionary keyed by domain
  - [x] `save(domain:knowledge:)` -- appends entry to domain array
  - [x] `query(domain:filter:)` -- filters by tags and date range, respects limit
  - [x] `delete(domain:olderThan:)` -- removes entries older than date in specified domain
  - [x] `listDomains()` -- returns sorted array of domain names with entries

- [x] Task 3: Implement FileBasedMemoryStore actor (AC: #3, #6)
  - [x] Add `FileBasedMemoryStore` actor in same `MemoryStore.swift` file
  - [x] Constructor takes optional `memoryDir: String?` (default `~/.agent/memory/`)
  - [x] `init` loads all domain JSON files from disk, skipping corrupt ones with Logger warning
  - [x] `save` writes to `<memoryDir>/<domain>.json` (array of entries serialized via JSONSerialization)
  - [x] `query` reads from in-memory cache (loaded at init + updated on save)
  - [x] `delete` filters entries and rewrites domain file; removes file if empty
  - [x] `listDomains` returns cached domain names sorted alphabetically
  - [x] File permissions: directory 0o700, files 0o600 (matching SessionStore pattern)
  - [x] Domain name validation: reject empty, `/`, `\\`, `..` (matching SessionStore's validateSessionId pattern)

- [x] Task 4: Add auto-expiry to both implementations (AC: #4)
  - [x] Add `maxAge: TimeInterval` property to both stores (default 30 days = 2,592,000 seconds)
  - [x] In `query()`, filter out entries where `createdAt + maxAge < Date()`
  - [x] Optionally trigger full cleanup on `query` call (lazy eviction)

- [x] Task 5: Integrate into AgentOptions and ToolContext (AC: #5)
  - [x] Add `memoryStore: (any MemoryStoreProtocol)?` property to `AgentOptions` (after `todoStore`, before `sessionStore`)
  - [x] Add `memoryStore` parameter to `AgentOptions.init` with default `nil`
  - [x] Set `self.memoryStore = memoryStore` in memberwise init body
  - [x] Set `self.memoryStore = nil` in `init(from config:)` body
  - [x] Add `memoryStore: (any MemoryStoreProtocol)?` field to `ToolContext`
  - [x] Pass `options.memoryStore` in both ToolContext construction sites in `Agent.swift` (line ~1187 and line ~1977)
  - [x] Update `ToolContext.withToolUseId()` to include `memoryStore` in the copy

- [x] Task 6: Write unit tests (AC: #7)
  - [x] Create `Tests/OpenAgentSDKTests/Stores/MemoryStoreTests.swift`
  - [x] Test InMemoryStore: save, query all, query by tags, query by date range, delete, listDomains, auto-expiry
  - [x] Test FileBasedMemoryStore: save + reload from disk, corrupt file handling, delete removes file when empty, domain validation
  - [x] Test KnowledgeEntry construction and field access
  - [x] Use temp directory for file-based tests (clean up in tearDown)

- [x] Task 7: Update module entry point doc comments (AC: #8)
  - [x] Add `MemoryStoreProtocol`, `InMemoryStore`, `FileBasedMemoryStore`, `KnowledgeEntry`, `KnowledgeQueryFilter` to `OpenAgentSDK.swift` DocC symbol list under a "Memory Store" section

- [x] Task 8: Build and verify (AC: #8)
  - [x] `swift build` zero errors zero warnings
  - [x] Run full test suite, report total count

## Dev Notes

### Position in Epic and Project

- **Epic 19** (Axion Phase 2 SDK Capabilities), first story
- **Prerequisites:** Epic 1 (Agent basics), Epic 6 (MCP protocol), Epic 7 (session persistence) -- all done
- **No TypeScript SDK reference** -- MemoryStore is a new Swift SDK capability not present in the TS SDK
- **Source:** Axion Phase 2 requirement, generalized to all SDK consumers

### CRITICAL: Follow Existing Store Patterns

This store MUST follow the established patterns from existing stores. Reference implementations:

1. **SessionStore** (`Sources/OpenAgentSDK/Stores/SessionStore.swift`) -- File-based persistence pattern:
   - Actor with `customSessionsDir: String?` for configurable path
   - `FileManager.default` for all file operations
   - `ISO8601DateFormatter` for timestamp serialization
   - `Logger.shared.warn` for corrupt file handling
   - `validateSessionId` for path traversal prevention
   - File permissions: directory `0o700`, files `0o600`
   - Platform-aware home directory resolution (`NSHomeDirectory()` / `getenv("HOME")`)

2. **TodoStore** (`Sources/OpenAgentSDK/Stores/TodoStore.swift`) -- In-memory actor pattern:
   - Simple actor with `[Int: TodoItem]` dictionary
   - Clean public API with doc comments
   - No file I/O

3. **AgentOptions store injection pattern** (from `AgentTypes.swift`):
   - Each store is an optional property: `public var todoStore: TodoStore?`
   - Passed in `init(...)` with default `nil`
   - Set to `nil` in `init(from config:)`
   - Injected into `ToolContext` at construction time in `Agent.swift`

4. **ToolContext store fields** (from `ToolTypes.swift`):
   - Each store is an optional field with doc comment: `public let todoStore: TodoStore?`
   - Copied in `withToolUseId()` method
   - Copied in `withSkillContext()` method

### Architecture Compliance

- **Stores/ depends only on Types/** -- MemoryStore files must NOT import Core/ or Tools/
- **Types/ is the leaf node** -- MemoryTypes.swift has zero outbound dependencies
- **Actor for shared mutable state** -- Both InMemoryStore and FileBasedMemoryStore MUST be actors
- **No Apple-proprietary frameworks** -- Use Foundation only, cross-platform (macOS + Linux)
- **Error model** -- Use `SDKError.sessionError(message:)` for consistency (or add a dedicated `memoryStoreError` case to `SDKError` if the dev prefers; sessionError is acceptable since memory is conceptually similar to session persistence)
- **JSON boundary** -- Use `JSONSerialization` for file I/O (NOT Codable for LLM communication, but Codable IS fine for file serialization; however, SessionStore uses raw JSONSerialization, so follow that pattern for consistency)
- **No force-unwrap** -- Use `guard let` / `if let` everywhere

### File Locations

```
Sources/OpenAgentSDK/Types/MemoryTypes.swift                         # NEW -- KnowledgeEntry, KnowledgeQueryFilter, MemoryStoreProtocol
Sources/OpenAgentSDK/Stores/MemoryStore.swift                        # NEW -- InMemoryStore, FileBasedMemoryStore actors
Sources/OpenAgentSDK/Types/AgentTypes.swift                          # MODIFY -- add memoryStore to AgentOptions
Sources/OpenAgentSDK/Types/ToolTypes.swift                           # MODIFY -- add memoryStore to ToolContext + withToolUseId + withSkillContext
Sources/OpenAgentSDK/Core/Agent.swift                                # MODIFY -- pass memoryStore in ToolContext construction (2 sites)
Sources/OpenAgentSDK/OpenAgentSDK.swift                              # MODIFY -- add DocC symbol references
Tests/OpenAgentSDKTests/Stores/MemoryStoreTests.swift                # NEW -- unit tests
_bmad-output/implementation-artifacts/sprint-status.yaml             # MODIFY -- status update
```

### MemoryStoreProtocol API Design

```swift
// In Types/MemoryTypes.swift

/// A single piece of knowledge accumulated by an agent across runs.
public struct KnowledgeEntry: Sendable, Equatable {
    public let id: String           // UUID
    public let content: String      // The knowledge text
    public let tags: [String]       // Categorization tags
    public let createdAt: Date      // When this was stored
    public let sourceRunId: String? // Which run produced this knowledge
}

/// Filter parameters for querying knowledge entries.
public struct KnowledgeQueryFilter: Sendable, Equatable {
    public let tags: [String]?          // Match entries with any of these tags
    public let olderThan: Date?         // Only entries older than this date
    public let newerThan: Date?         // Only entries newer than this date
    public let limit: Int?              // Max entries to return
}

/// Protocol for cross-run knowledge accumulation stores.
public protocol MemoryStoreProtocol: Sendable {
    func save(domain: String, knowledge: KnowledgeEntry) async throws
    func query(domain: String, filter: KnowledgeQueryFilter?) async throws -> [KnowledgeEntry]
    func delete(domain: String, olderThan: Date) async throws -> Int
    func listDomains() async throws -> [String]
}
```

### FileBasedMemoryStore Disk Layout

```
~/.agent/memory/
  calculator.json       # [{"id":"...","content":"...","tags":[...],"createdAt":"...","sourceRunId":"..."}, ...]
  finder-navigation.json
  project-structure.json
```

### ToolContext Integration Sites

Two places in `Agent.swift` construct `ToolContext` and must pass `memoryStore`:

1. **Line ~1187** (in the main query loop): `ToolContext(cwd:..., ...todoStore: options.todoStore, ...)`
   - Add `memoryStore: options.memoryStore` after `todoStore`

2. **Line ~1977** (in the streaming query loop): Same pattern
   - Add `memoryStore: capturedMemoryStore` (following the captured store pattern used for todoStore on line ~1346/1987)

### Anti-Patterns to Avoid

- Do NOT make MemoryStoreProtocol a class -- it must be a protocol so users can provide custom implementations
- Do NOT use Codable for JSON serialization in FileBasedMemoryStore -- follow SessionStore pattern using JSONSerialization for consistency
- Do NOT import Core/ or Tools/ from Stores/ -- violates module boundary
- Do NOT use force-unwrap (!) -- use guard let / if let
- Do NOT use Apple-proprietary APIs -- must work on macOS and Linux
- Do NOT block Agent execution on corrupt memory files -- skip and warn, as per AC6
- Do NOT make KnowledgeEntry a class -- it must be a struct (immutable data type per project-context.md rule 1)
- Do NOT add a MemoryStoreTool in this story -- tool creation is out of scope; the store is accessible via ToolContext.memoryStore for custom tools

### Testing Requirements

- **New test file:** `Tests/OpenAgentSDKTests/Stores/MemoryStoreTests.swift`
- **Pattern:** Follow `TodoStoreTests.swift` (18 tests) for in-memory tests, `SessionStoreTests.swift` (25 tests) for file-based tests
- **Test categories:**
  - InMemoryStore: CRUD operations, query filters, domain management, auto-expiry
  - FileBasedMemoryStore: persistence across instances, corrupt file handling, domain validation, file permissions
  - KnowledgeEntry: construction, field access
- **File-based test setup:** Use `NSTemporaryDirectory()` + unique subdirectory, clean up in tearDown
- **After implementation, run full test suite and report total count**

### Previous Story Intelligence

**From Story 18-12 (last story completed):**
- Pattern: update compat examples to reflect new features
- Test count at completion: ~4439 tests passing
- `swift build` zero errors zero warnings

**From Epic 17 (most recent feature epics):**
- Adding fields to AgentOptions requires updating BOTH the memberwise init AND `init(from config:)`
- Adding fields to ToolContext requires updating the init, `withToolUseId()`, AND `withSkillContext()`
- Both `withToolUseId()` and `withSkillContext()` must include ALL fields (existing + new)
- Agent.swift has TWO ToolContext construction sites that both need the new field

### Project Structure Notes

- New types file `MemoryTypes.swift` goes in `Sources/OpenAgentSDK/Types/` (leaf node, no outbound deps)
- New store file `MemoryStore.swift` goes in `Sources/OpenAgentSDK/Stores/` (depends only on Types/)
- No Package.swift changes needed (all files are in the existing OpenAgentSDK target)
- No new dependencies needed

### References

- [Source: Sources/OpenAgentSDK/Stores/SessionStore.swift] -- File-based store pattern (JSONSerialization, FileManager, ISO8601DateFormatter, Logger.warn, path validation, permissions)
- [Source: Sources/OpenAgentSDK/Stores/TodoStore.swift] -- In-memory store pattern (actor, simple dict, clean API)
- [Source: Sources/OpenAgentSDK/Types/ToolTypes.swift] -- ToolContext struct with store fields (lines 269-467)
- [Source: Sources/OpenAgentSDK/Types/AgentTypes.swift] -- AgentOptions struct with store properties (lines 229-686)
- [Source: Sources/OpenAgentSDK/Core/Agent.swift] -- ToolContext construction sites (lines ~1187 and ~1977)
- [Source: _bmad-output/planning-artifacts/epics.md#Epic19] -- Story 19.1 requirements and acceptance criteria
- [Source: _bmad-output/project-context.md] -- Project rules (actor for shared state, Stores/ module boundaries, no force-unwrap, cross-platform)
- [Source: _bmad-output/implementation-artifacts/18-9-update-compat-permissions.md] -- Most recent completed story pattern

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Fixed `Task` naming conflict with Swift Concurrency -- used static `nonisolated` methods for FileBasedMemoryStore init loading
- Fixed ATDD test file syntax errors: `FileManager.default.writeToFile` replaced with `String.write(toFile:)`
- Fixed ATDD test ToolContext construction to match actual API signature

### Completion Notes List

- Implemented MemoryStoreProtocol with 4 core methods (save, query, delete, listDomains)
- InMemoryStore: actor with domain-keyed dictionary, tag/date/limit filtering, auto-expiry via maxAge
- FileBasedMemoryStore: actor with disk persistence at ~/.agent/memory/<domain>.json, corrupt file resilience, domain name validation, auto-expiry
- Both stores default maxAge to 30 days (2,592,000 seconds)
- AgentOptions: added memoryStore property with memberwise init and config init support
- ToolContext: added memoryStore field, updated init, withToolUseId(), and withSkillContext()
- Agent.swift: passed memoryStore in both ToolContext construction sites (main query loop + streaming loop)
- OpenAgentSDK.swift: added Memory Store DocC section with all 5 public types
- 49 unit tests passing, covering all ACs (InMemoryStore CRUD, query filters, expiry, FileBased persistence, corrupt files, domain validation, permissions, concurrent access, AgentOptions/ToolContext integration)
- Full test suite: 4611 tests passing with 0 failures, 14 skipped
- swift build: zero errors

### File List

- Sources/OpenAgentSDK/Types/MemoryTypes.swift (NEW)
- Sources/OpenAgentSDK/Stores/MemoryStore.swift (NEW)
- Sources/OpenAgentSDK/Types/AgentTypes.swift (MODIFIED)
- Sources/OpenAgentSDK/Types/ToolTypes.swift (MODIFIED)
- Sources/OpenAgentSDK/Core/Agent.swift (MODIFIED)
- Sources/OpenAgentSDK/OpenAgentSDK.swift (MODIFIED)
- Tests/OpenAgentSDKTests/Stores/MemoryStoreTests.swift (MODIFIED)
- _bmad-output/implementation-artifacts/sprint-status.yaml (MODIFIED)
