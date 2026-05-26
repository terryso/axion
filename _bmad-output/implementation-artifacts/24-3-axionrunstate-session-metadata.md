---
baseline_commit: 835e2d62d72a219f644ef4c47070dc67dcde5533
---

# Story 24.3: AxionRunState + Session 元数据

Status: ready-for-dev

## Story

As a Axion developer,
I want AxionRuntime to maintain Axion-specific runtime state and expose session metadata via SDK's SessionStore,
so that EventHandlers can access SDK-provided data (toolPairs, usage, cost) AND Axion-specific data (externallyModified, takeoverEvent) through a unified context.

## Acceptance Criteria

1. **Given** `AxionRuntime` has `AxionRuntimeState` properties (`externallyModified`, `takeoverEvent`)
   **When** a run completes with external desktop activity detected
   **Then** `externallyModified` is `true` on the runtime and accessible via `await runtime.externallyModified`

2. **Given** `AxionRuntime` has `AxionRuntimeState` properties
   **When** a takeover occurs during execution (user pauses → resumes)
   **Then** `takeoverEvent` is populated with `TakeoverEventContext` data (issue, summary, feedback, reason, duration)

3. **Given** `EventHandlerContext` struct exists
   **When** constructed with sessionId, config, eventBus, and runtime state
   **Then** all fields are accessible: sessionId, config, eventBus, externallyModified, takeoverEvent, runCompleteContext, sessionStore

4. **Given** `AxionRuntime` initializes a `SessionStore(sessionsDir: "~/.axion/sessions")`
   **When** `listSessions()` is called
   **Then** it returns `[SessionInfo]` containing SDK's `SessionMetadata` + Axion overlay (status, totalSteps, durationMs)

5. **Given** a session has completed
   **When** `getSession(sessionId:)` is called
   **Then** it returns `SessionInfo?` with SDK metadata and Axion-specific status/totalSteps/durationMs from `axion-state.json`

6. **Given** `AxionRuntime.execute()` completes a run
   **When** the run finishes (success or failure)
   **Then** `axion-state.json` is written to `~/.axion/sessions/{sessionId}/` with status, totalSteps, durationMs, and updatedAt

7. **Given** `SessionInfo` combines SDK and Axion data
   **When** a session directory has `transcript.json` (SDK) but no `axion-state.json`
   **Then** `SessionInfo` still returns with SDK metadata and default Axion values (status=unknown, totalSteps=0, durationMs=nil)

8. **Given** `AxionRunResult` now carries `runCompleteContext`
   **When** a run completes
   **Then** `AxionRunResult` includes the `RunCompleteContext?` captured from the `onRunComplete` callback

## Tasks / Subtasks

- [ ] Task 1: Add AxionRuntimeState properties to AxionRuntime (AC: #1, #2)
  - [ ] 1.1 Add `private(set) var externallyModified: Bool = false` to `AxionRuntime`
  - [ ] 1.2 Add `private(set) var takeoverEvent: RunMemoryProcessor.TakeoverEventContext?` to `AxionRuntime`
  - [ ] 1.3 Add `private(set) var lastRunCompleteContext: RunCompleteContext?` to `AxionRuntime`
  - [ ] 1.4 In `run()` method: after `RunOrchestrator.execute()` returns, extract `externallyModified`, `takeoverEvent`, and `runCompleteContext` from the orchestrator result — requires extending `RunOrchestrator.RunResult` to carry these fields
  - [ ] 1.5 Store extracted values on AxionRuntime properties

- [ ] Task 2: Extend RunOrchestrator.RunResult with runtime state (AC: #1, #2, #8)
  - [ ] 2.1 Add `externallyModified: Bool`, `takeoverEvent: RunMemoryProcessor.TakeoverEventContext?`, `runCompleteContext: RunCompleteContext?` to `RunResult`
  - [ ] 2.2 Populate these fields from the stream loop local variables when constructing `RunResult`

- [ ] Task 3: Create EventHandlerContext struct (AC: #3)
  - [ ] 3.1 Create `Sources/AxionCLI/Services/EventHandlerContext.swift` with `struct EventHandlerContext: Sendable`
  - [ ] 3.2 Fields: `sessionId: String?`, `config: AxionConfig`, `eventBus: EventBus?`, `externallyModified: Bool`, `takeoverEvent: RunMemoryProcessor.TakeoverEventContext?`, `runCompleteContext: RunCompleteContext?`, `sessionStore: SessionStore`

- [ ] Task 4: Create SessionInfo and AxionStateOverlay models (AC: #4, #5, #7)
  - [ ] 4.1 Create `Sources/AxionCore/Models/SessionInfo.swift` with `public struct SessionInfo: Codable, Equatable, Sendable`
  - [ ] 4.2 Fields: `sessionId: String`, `status: String`, `totalSteps: Int`, `durationMs: Int?`, `updatedAt: Date?`, plus SDK metadata fields that AxionCore can carry (cwd, model, createdAt, messageCount, summary) — no SDK type dependencies
  - [ ] 4.3 Create `Sources/AxionCore/Models/AxionStateOverlay.swift` with `struct AxionStateOverlay: Codable, Sendable` — the `axion-state.json` schema: status, totalSteps, durationMs, updatedAt

- [ ] Task 5: Add SessionStore and session query methods to AxionRuntime (AC: #4, #5, #6)
  - [ ] 5.1 Add `let sessionStore: SessionStore` to `AxionRuntime`, initialized with `SessionStore(sessionsDir: sessionsDir)` where `sessionsDir = NSHomeDirectory()/.axion/sessions`
  - [ ] 5.2 Implement `func listSessions(limit: Int? = nil) async throws -> [SessionInfo]` — calls `sessionStore.list()`, then loads `axion-state.json` overlay for each
  - [ ] 5.3 Implement `func getSession(_ sessionId: String) async throws -> SessionInfo?` — calls `sessionStore.load()` + reads `axion-state.json`
  - [ ] 5.4 Implement `private func writeAxionState(sessionId: String, status: String, totalSteps: Int, durationMs: Int) throws` — writes `axion-state.json`

- [ ] Task 6: Write axion-state.json on run completion (AC: #6)
  - [ ] 6.1 In `run()`: after state transition to COMPLETED/FAILED, call `writeAxionState()` with the result data
  - [ ] 6.2 Ensure session directory exists before writing (FileManager.createDirectory)

- [ ] Task 7: Write unit tests (AC: #1–#8)
  - [ ] 7.1 Test: AxionRuntime sets externallyModified after RunOrchestrator returns (AC #1) — use a test scenario that triggers external modification
  - [ ] 7.2 Test: EventHandlerContext construction with all fields (AC #3)
  - [ ] 7.3 Test: AxionStateOverlay Codable round-trip
  - [ ] 7.4 Test: SessionInfo construction with and without overlay (AC #7)
  - [ ] 7.5 Test: listSessions() returns empty array when no sessions exist (AC #4)
  - [ ] 7.6 Test: writeAxionState writes valid JSON to expected path (AC #6)
  - [ ] 7.7 Test: getSession() returns nil for non-existent session (AC #5)
  - [ ] 7.8 Test: AxionRunResult carries runCompleteContext from dryrun (AC #8)

## Dev Notes

### Architecture Context

This story implements **Phase 9, Epic 24, Story 3** — enriching AxionRuntime with runtime state that EventHandlers need. Story 24.1 created the skeleton (state machine enum + result struct + actor). Story 24.2 added `execute()` with the full build→run pipeline. This story bridges the gap between RunOrchestrator's internal state (externallyModified, takeoverEvent, runCompleteContext) and AxionRuntime's public API, and introduces session querying.

### Critical: Naming Collision with Epic Spec

The epic spec defines `AxionRunState` as a `public actor` with `externallyModified` and `takeoverEvent`. **But story 24.1 already created `AxionRunState` as a `public enum`** (session state machine: created/running/completed/failed) in `Sources/AxionCore/Models/AxionRunState.swift`.

**Resolution:** The epic's actor concept is split into:
1. **Properties on existing `AxionRuntime`** — `externallyModified`, `takeoverEvent`, `lastRunCompleteContext` as actor-isolated vars (no separate actor needed; AxionRuntime IS already an actor)
2. **`EventHandlerContext`** — a snapshot struct that captures runtime state at event time for EventHandler consumption

This is simpler than the epic's separate actor approach and avoids the naming collision.

### RunOrchestrator.RunResult Extension

Currently `RunResult` only carries `totalSteps`, `durationMs`, `runSucceeded`. The stream loop computes `externallyModified`, `takeoverEvent`, and captures `runCompleteContext` (via `buildResult.runCompleteBox`) but does NOT return them. This story extends `RunResult` to carry all three, enabling AxionRuntime to store them.

**Current `RunResult`:**
```swift
struct RunResult: Sendable {
    let totalSteps: Int
    let durationMs: Int
    let runSucceeded: Bool
}
```

**Extended `RunResult`:**
```swift
struct RunResult: Sendable {
    let totalSteps: Int
    let durationMs: Int
    let runSucceeded: Bool
    let externallyModified: Bool
    let takeoverEvent: RunMemoryProcessor.TakeoverEventContext?
    let runCompleteContext: RunCompleteContext?
}
```

This is a backward-compatible change — all existing call sites use named fields, and the new fields have defaults or are optional.

### SDK SessionStore Integration

The SDK provides `SessionStore` (actor) at `Sources/OpenAgentSDK/Stores/SessionStore.swift`:
- `init(sessionsDir: String?)` — custom directory, defaults to `~/.open-agent-sdk/sessions/`
- `list(limit:includeWorktrees:) -> [SessionMetadata]` — sorted by updatedAt descending
- `load(sessionId:limit:offset:) -> SessionData?` — metadata + messages
- `save(sessionId:messages:metadata:)` — persists transcript

SDK types used:
- `SessionMetadata` — id, cwd, model, createdAt, updatedAt, messageCount, summary?, tag?, fileSize?, firstPrompt?, gitBranch?
- `SessionData` — metadata + `[[String: Any]]` messages
- `PartialSessionMetadata` — cwd, model, summary?, tag?, firstPrompt?, gitBranch?
- `RunCompleteContext` — toolPairs, task, runId?, status, usage, totalCostUsd, durationMs, numTurns, costBreakdown

### SessionInfo Design (AxionCore, no SDK dependency)

`SessionInfo` goes in AxionCore because AxionBar and future TUI need to consume it without importing SDK. It mirrors SDK's SessionMetadata fields as primitives:

```swift
public struct SessionInfo: Codable, Equatable, Sendable {
    // From SDK SessionMetadata
    public let sessionId: String
    public let cwd: String
    public let model: String
    public let createdAt: Date?
    public let updatedAt: Date?
    public let messageCount: Int
    public let summary: String?

    // From Axion overlay (axion-state.json)
    public let status: String      // "created", "running", "completed", "failed"
    public let totalSteps: Int
    public let durationMs: Int?
}
```

### AxionStateOverlay (axion-state.json)

Lightweight JSON file stored alongside SDK's `transcript.json`:

```swift
struct AxionStateOverlay: Codable, Sendable {
    let status: String      // AxionRunState raw value
    let totalSteps: Int
    let durationMs: Int?
    let updatedAt: String   // ISO8601
}
```

File location: `~/.axion/sessions/{sessionId}/axion-state.json`

Written by AxionRuntime after run completes. Read when `getSession()` or `listSessions()` is called. If missing (SDK-only session), defaults apply.

### EventHandlerContext Design

```swift
struct EventHandlerContext: Sendable {
    let sessionId: String?
    let config: AxionConfig
    let eventBus: EventBus?
    let externallyModified: Bool
    let takeoverEvent: RunMemoryProcessor.TakeoverEventContext?
    let runCompleteContext: RunCompleteContext?
    let sessionStore: SessionStore
}
```

This struct is constructed by AxionRuntime and passed to EventHandlers in Epic 25. It goes in AxionCLI because it references SDK types (EventBus, RunCompleteContext, SessionStore).

### File Locations

| File | Action | Details |
|------|--------|---------|
| `Sources/AxionCore/Models/SessionInfo.swift` | **NEW** | Pure model, no SDK dependency |
| `Sources/AxionCore/Models/AxionStateOverlay.swift` | **NEW** | axion-state.json schema |
| `Sources/AxionCLI/Services/AxionRuntime.swift` | **UPDATE** | Add runtime state props, SessionStore, listSessions(), getSession(), writeAxionState() |
| `Sources/AxionCLI/Services/RunOrchestrator.swift` | **UPDATE** | Extend RunResult with externallyModified, takeoverEvent, runCompleteContext |
| `Sources/AxionCLI/Services/EventHandlerContext.swift` | **NEW** | Handler context struct |
| `Tests/AxionCoreTests/Models/SessionInfoTests.swift` | **NEW** | SessionInfo + AxionStateOverlay tests |
| `Tests/AxionCLITests/Services/AxionRuntimeTests.swift` | **UPDATE** | Add session query + state tests |
| `Tests/AxionCLITests/Services/EventHandlerContextTests.swift` | **NEW** | EventHandlerContext tests |

### Import Order Reminder

```swift
// AxionRuntime.swift
import Foundation
import OpenAgentSDK

import AxionCore

// EventHandlerContext.swift
import Foundation
import OpenAgentSDK

import AxionCore
```

### Testing Strategy

- Use `dryrun: true` for testing session state capture — RunOrchestrator returns quickly
- Use temp directory for session store tests — `SessionStore(sessionsDir: tmpDir)` + cleanup after
- Test axion-state.json round-trip via FileManager in temp dir
- All tests follow Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`)
- Run with: `make test`

### Previous Story Learnings (24.1, 24.2)

- `AxionRuntime` is `public actor` — new methods should be `func` (internal) unless cross-module access is needed
- `AgentBuildResult` and `RunOrchestrator.RunConfig` are internal types — methods using them must also be internal
- `RunOrchestrator.generateRunId()` is static — `YYYYMMDD-{6 lowercase alphanumeric}`
- `RunOrchestrator` is an `enum` with static methods — cannot be subclassed or mocked
- `RunMemoryProcessor.TakeoverEventContext` is already `Sendable` — can be stored on actor
- `buildResult.runCompleteBox` is a boxed `RunCompleteContext?` — captured by RunOrchestrator's `onRunComplete` callback
- `AxionRunResult` already has `errorMessage: String?` (added during 24.1 review)
- Review/curator run in detached tasks — their output goes to stderr via fputs()
- `AxionRunState` enum is in AxionCore — use `.rawValue` for status string in axion-state.json

### References

- [Source: docs/epics/epic-24-axion-runtime-core.md#Story-24.3] — Epic definition for this story
- [Source: _bmad-output/specs/spec-axion-runtime/SPEC.md] — CAP-2 (event stream), CAP-8 (cross-cutting handlers), CAP-9 (session listing)
- [Source: _bmad-output/specs/spec-axion-runtime/state-machines.md] — Session state machine
- [Source: _bmad-output/specs/spec-axion-runtime/api-protocol.md] — Session Model schema
- [Source: _bmad-output/specs/spec-axion-runtime/implementation-roadmap.md] — A2 (AxionRuntime Actor) phase
- [Source: Sources/AxionCore/Models/AxionRunState.swift] — Existing state machine enum (24.1)
- [Source: Sources/AxionCore/Models/AxionRunResult.swift] — Existing result struct (24.1)
- [Source: Sources/AxionCLI/Services/AxionRuntime.swift] — Current AxionRuntime actor (24.1 + 24.2)
- [Source: Sources/AxionCLI/Services/RunOrchestrator.swift:30-34] — RunResult struct to extend
- [Source: Sources/AxionCLI/Services/RunOrchestrator.swift:101-102] — externallyModified and takeoverEvent local vars
- [Source: Sources/AxionCLI/Services/RunOrchestrator.swift:215] — externallyModified = true (seat monitor)
- [Source: Sources/AxionCLI/Services/RunOrchestrator.swift:191] — takeoverEvent assignment (pause/resume)
- [Source: Sources/AxionCLI/Memory/RunMemoryProcessor.swift:47-53] — TakeoverEventContext definition
- [Source: SDK SessionStore.swift] — SessionStore actor with list/load/save
- [Source: SDK SessionTypes.swift] — SessionMetadata, SessionData, PartialSessionMetadata
- [Source: SDK AgentTypes.swift:822-852] — RunCompleteContext definition

### Project Structure Notes

- SessionInfo goes in AxionCore/Models (pure model, no SDK dependency) — follows AxionRunState/AxionRunResult pattern
- AxionStateOverlay goes in AxionCore/Models (Codable schema for JSON file)
- EventHandlerContext goes in AxionCLI/Services (references SDK types)
- SessionStore integration is inside AxionRuntime (AxionCLI) — AxionCore can't import SDK
- Tests mirror source: `Tests/AxionCoreTests/Models/` for models, `Tests/AxionCLITests/Services/` for runtime tests

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
