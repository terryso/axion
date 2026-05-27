---
baseline_commit: 4bef6e631f3fb0d57c806b60d0b8deed09e63cff
---

# Story 27.1: Session List CLI Command

Status: done

## Story

As a CLI user,
I want to list all historical agent sessions,
so that I can review past executions and select one to resume.

## Acceptance Criteria

1. **Given** 5 historical sessions exist (SDK transcript + Axion state persisted in `~/.axion/sessions/`)
   **When** running `axion sessions`
   **Then** display all 5 sessions with summary info: session ID, task (from SDK `summary`), status (from `axion-state.json`), steps, duration, created date

2. **Given** 3 sessions exist, 1 with status=running
   **When** running `axion sessions --active`
   **Then** display only the 1 active (running) session

3. **Given** no sessions exist
   **When** running `axion sessions`
   **Then** display "No sessions found" message

4. **Given** more than 20 sessions exist
   **When** running `axion sessions` (default limit=20)
   **Then** display only the 20 most recent sessions

5. **Given** sessions exist
   **When** running `axion sessions --limit 5`
   **Then** display only the 5 most recent sessions

## Tasks / Subtasks

- [x] Task 1: Create `SessionsCommand.swift` (AC: #1-5)
  - [x] Create `Sources/AxionCLI/Commands/SessionsCommand.swift` as `AsyncParsableCommand`
  - [x] Add `--active` flag (`@Flag`, short/long) to filter only running sessions
  - [x] Add `--limit` option (`@Option`, short/long, default 20)
  - [x] Register in `AxionCLI.swift` subcommands array
- [x] Task 2: Implement session table rendering (AC: #1)
  - [x] Format output as aligned table: SESSION_ID, TASK, STATUS, STEPS, DURATION, CREATED
  - [x] Truncate long session IDs (show first 8 chars + "...")
  - [x] Truncate long task descriptions (max 30 chars)
  - [x] Format duration as human-readable (e.g. "34s", "2m 15s")
  - [x] Format date as "yyyy-MM-dd HH:mm"
  - [x] Handle "No sessions found" case (AC: #3)
- [x] Task 3: Wire to `AxionRuntime.listSessions()` (AC: #1-5)
  - [x] Create `AxionRuntime()` instance, call `listSessions(limit:)`
  - [x] Apply `--active` filter on returned `[SessionInfo]` (filter by `status == "running"`)
  - [x] Apply limit after filtering
  - [x] Sort by `createdAt` descending (most recent first)
- [x] Task 4: Unit tests (AC: #1-5)
  - [x] Test `SessionsCommand` output with mock sessions
  - [x] Test `--active` filtering logic
  - [x] Test `--limit` truncation
  - [x] Test empty sessions message
  - [x] Test table rendering format (alignment, truncation)

## Dev Notes

### Architecture Context

- **AxionRuntime.listSessions()** already exists (`Sources/AxionCLI/Services/AxionRuntime.swift:249`). It calls SDK's `sessionStore.list()` and merges each session's `axion-state.json` overlay into `SessionInfo`.
- **SessionInfo** model is in `AxionCore/Models/SessionInfo.swift` — has all needed fields: `sessionId`, `summary`, `status`, `totalSteps`, `durationMs`, `createdAt`.
- **AxionRunState** enum (`AxionCore/Models/AxionRunState.swift`) has cases: `created`, `running`, `completed`, `failed`. Status strings come from `axion-state.json`.

### Key Files to Touch

| File | Action | Notes |
|------|--------|-------|
| `Sources/AxionCLI/Commands/SessionsCommand.swift` | NEW | Main command |
| `Sources/AxionCLI/AxionCLI.swift` | UPDATE | Add `SessionsCommand.self` to subcommands array |

### Patterns to Follow

- Follow `SkillListCommand.swift` pattern: simple `AsyncParsableCommand` with `run() async throws`
- Follow `MemoryListCommand.swift` pattern for listing+rendering
- Import order: `ArgumentParser`, `AxionCore`, `Foundation`, `OpenAgentSDK` (as needed)
- Use `print()` for CLI output (this is a list command, not streaming)
- No EventBus or EventHandler needed — this is a read-only query

### Session Data Structure

Sessions are stored in `~/.axion/sessions/{sessionId}/`:
- `transcript.json` — SDK session data (messages, metadata)
- `axion-state.json` — Axion overlay: `{ status, totalSteps, durationMs, updatedAt }`

`AxionRuntime.listSessions()` already merges both into `SessionInfo`.

### SessionInfo Fields Available

```swift
public struct SessionInfo {
    public let sessionId: String
    public let cwd: String
    public let model: String
    public let createdAt: Date?
    public let updatedAt: Date?
    public let messageCount: Int
    public let summary: String?      // Task description from SDK
    public let status: String         // From axion-state.json
    public let totalSteps: Int
    public let durationMs: Int?
}
```

### Output Format Reference

```
SESSION     TASK                         STATUS     STEPS  DURATION  CREATED
a1b2c3d4…   "refactor auth module"       COMPLETED  12     34s       2026-05-27 14:32
e5f6g7h8…   "fix login bug"             FAILED     5      12s       2026-05-27 13:15
```

### Testing Approach

- Mock `AxionRuntime` via protocol abstraction — `SessionsCommand` should call a protocol method, not concrete `AxionRuntime`
- OR: test the rendering/filtering logic as pure functions extracted from the command
- Follow project testing rules: Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`)
- Unit tests in `Tests/AxionCLITests/Commands/SessionsCommandTests.swift`

### Constraints

- **No network calls** — `listSessions()` reads from local filesystem only
- **No Helper process needed** — pure data query
- **SessionsCommand is a top-level command** — `axion sessions`, NOT `axion session list`
- The epic file says both `axion sessions` (top-level) and the roadmap says the same. This is a standalone top-level command.

### References

- [Source: docs/epics/epic-27-session-resume-daemon.md — Story 27.1]
- [Source: docs/agent-runtime-roadmap.md — A6]
- [Source: Sources/AxionCLI/Services/AxionRuntime.swift — listSessions()]
- [Source: Sources/AxionCore/Models/SessionInfo.swift — SessionInfo model]
- [Source: Sources/AxionCLI/Commands/SkillListCommand.swift — list command pattern]
- [Source: Sources/AxionCLI/AxionCLI.swift — subcommand registration]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Initial `String(format: "%-12s", ...)` with Swift strings caused signal 11 crash. Replaced with native Swift `pad()` helper.
- `@Flag(short: .customShort("a"), ...)` not available in this version of swift-argument-parser. Used `name: .long` pattern consistent with project conventions.

### Completion Notes List

- SessionsCommand created as top-level `AsyncParsableCommand` with `--active` flag and `--limit` option
- Rendering logic extracted as static methods (`renderTable`, `filterActive`, `applyLimit`, `sortByMostRecent`) for testability
- 17 unit tests covering all ACs: table rendering, truncation, duration formatting, date formatting, filtering, limit, sorting, empty case
- All 1336 unit tests pass (0 regressions)
- No network calls, no Helper process needed — pure filesystem query via AxionRuntime.listSessions()

### File List

| File | Action |
|------|--------|
| `Sources/AxionCLI/Commands/SessionsCommand.swift` | NEW |
| `Sources/AxionCLI/AxionCLI.swift` | MODIFIED |
| `Sources/AxionCLI/Services/Protocols/SessionListing.swift` | NEW |
| `Tests/AxionCLITests/Commands/SessionsCommandTests.swift` | NEW |

### Change Log

- 2026-05-27: Implemented `axion sessions` CLI command with `--active` and `--limit` flags, table rendering, and 17 unit tests
- 2026-05-27: Review fixes — added `SessionListing` protocol + factory injection, `--limit` validation, `<1s` for sub-second durations, 5 new tests (22 total), 1341 tests pass

## Senior Developer Review (AI)

**Reviewer:** Nick on 2026-05-27
**Outcome:** Approved (after auto-fix)

### Issues Found & Fixed

1. **[HIGH] No protocol abstraction for AxionRuntime** — `run()` directly instantiated `AxionRuntime()`. Fixed: created `SessionListing` protocol, added `nonisolated(unsafe) static var createLister` factory (consistent with RunCommand/ServerCommand pattern), added `MockSessionLister` in tests.
2. **[MEDIUM] No `--limit` validation** — `--limit 0` or `--limit -1` silently produced empty output. Fixed: added `validate()` method that throws `ValidationError` for `limit <= 0`.
3. **[MEDIUM] Test filter mismatch** — Tests only discoverable via `swift test --filter "SessionsCommand"`, not through full `AxionCLITests.Commands.*` path. Not a code issue — Swift Testing `@Suite` structs don't nest under XCTest-style module paths.
4. **[LOW] `formatDuration(500)` showed "0s"** — Sub-second durations now display `<1s`.

### Post-Fix Verification

- 22 unit tests pass (was 17)
- 1341 total unit tests pass (0 regressions)
