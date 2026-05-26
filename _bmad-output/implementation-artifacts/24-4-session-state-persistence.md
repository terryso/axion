---
baseline_commit: a449c56b2e9099fe23d3f47cd9ec031d98e9c26f
---

# Story 24.4: Session State Persistence

Status: ready-for-dev

## Story

As a Axion developer,
I want session state transitions persisted to `axion-state.json` at every lifecycle stage (CREATED → RUNNING → COMPLETED/FAILED),
so that sessions survive process crashes, can be queried by CLI/API commands, and EventHandler consumers can rely on durable state.

## Acceptance Criteria

1. **Given** `AxionRuntime.createSession(task:config:)` is called
   **When** a new session ID is generated
   **Then** `axion-state.json` is written to `~/.axion/sessions/{sessionId}/` with `status: "created"`, `totalSteps: 0`, `durationMs: 0`

2. **Given** `AxionRuntime.run()` transitions to RUNNING state
   **When** the state machine validates and applies the transition
   **Then** `axion-state.json` is updated with `status: "running"`, `totalSteps: 0`, `durationMs: 0`

3. **Given** a run completes successfully
   **When** `RunOrchestrator.execute()` returns with `runSucceeded: true`
   **Then** `axion-state.json` is updated with `status: "completed"`, actual `totalSteps`, and `durationMs`

4. **Given** a run fails
   **When** `RunOrchestrator.execute()` throws or returns an error
   **Then** `axion-state.json` is updated with `status: "failed"`, `totalSteps: 0`, `durationMs: 0`

5. **Given** multiple `AxionRuntime` instances run sequentially
   **When** each creates a session and completes
   **Then** each session's `axion-state.json` is written independently without overwriting others

## Tasks / Subtasks

- [x] Task 1: Add `createSession()` method (AC: #1)
  - [x] 1.1 Generate session ID via `RunOrchestrator.generateRunId()`
  - [x] 1.2 Set `sessionId` and `createdAt` on the actor
  - [x] 1.3 Call `writeAxionState()` with `.created` status

- [x] Task 2: Persist RUNNING state in `run()` (AC: #2)
  - [x] 2.1 After `currentState = .running`, call `writeAxionState()` with `.running` status, `totalSteps: 0`, `durationMs: 0`

- [x] Task 3: Persist COMPLETED/FAILED state in `run()` (AC: #3, #4)
  - [x] 3.1 On success path: call `writeAxionState()` with `.completed` status and actual result values
  - [x] 3.2 On error path: call `writeAxionState()` with `.failed` status

- [x] Task 4: Write unit tests (AC: #1–#5)
  - [x] 4.1 Test `createSession()` writes CREATED state
  - [x] 4.2 Test `run()` writes RUNNING then COMPLETED state
  - [x] 4.3 Test two sessions write state files independently

## Dev Notes

### Architecture Context

This story implements **Phase 9, Epic 24, Story 4** — the session lifecycle persistence layer. Stories 24.1–24.3 established the AxionRuntime skeleton (state machine enum + result struct + actor), the `execute()` pipeline (build→run), and runtime state + session metadata models. This story wires the `writeAxionState()` calls into the session lifecycle so that every state transition is durably persisted to disk.

### Session State Persistence Pattern

The `writeAxionState()` private method was created in Story 24.3. It writes an `AxionStateOverlay` (Codable) to `~/.axion/sessions/{sessionId}/axion-state.json`. This story adds three call sites:

1. **`createSession()`** — new public method that writes CREATED state before any execution
2. **`run()` transition to RUNNING** — writes intermediate RUNNING state after state machine validation
3. **`run()` COMPLETED/FAILED** — writes terminal state with actual result data

### Key Implementation Detail: `try?` for Intermediate Writes

The `writeAxionState()` calls use `try?` (not `try`) because:
- Intermediate state persistence is best-effort — failure should not crash the run
- The final COMPLETED/FAILED write also uses `try?` for the same reason
- Only `createSession()` uses `try` (no `?`) because it's a setup operation where write failure should propagate

### File Locations

| File | Action | Details |
|------|--------|---------|
| `Sources/AxionCLI/Services/AxionRuntime.swift` | **UPDATE** | Add `createSession()`, RUNNING state write in `run()`, terminal state writes |
| `Tests/AxionCLITests/Services/AxionRuntimeTests.swift` | **UPDATE** | Add session lifecycle persistence tests |

### Previous Story Learnings (24.1–24.3)

- `AxionRuntime` is `public actor` — new methods should be `func` (internal) unless cross-module access is needed
- `writeAxionState()` was created in 24.3 — handles directory creation, ISO8601 formatting, JSON encoding, file permissions (0o600)
- `AxionRunState` enum raw values match state machine names: `.created`, `.running`, `.completed`, `.failed`
- `RunOrchestrator.generateRunId()` generates `YYYYMMDD-{6 lowercase alphanumeric}` format
- Use `dryrun: true` for testing — RunOrchestrator returns quickly without LLM calls
- Sessions directory: `~/.axion/sessions/` — created with `createDirectory(withIntermediateDirectories: true)`

### Import Order Reminder

```swift
// AxionRuntime.swift
import Foundation
import OpenAgentSDK

import AxionCore
```

### Testing Strategy

- Use `dryrun: true` via `makeDryrunBuildConfig()` for testing state transitions
- Verify `axion-state.json` contents by reading from `FileManager.default.contents(atPath:)`
- Test multi-session isolation by creating separate `AxionRuntime` instances
- All tests follow Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`)
- Run with: `make test`

### References

- [Source: _bmad-output/specs/spec-axion-runtime/SPEC.md] — CAP-1 (session persistence), CAP-9 (session listing)
- [Source: _bmad-output/specs/spec-axion-runtime/state-machines.md] — Session state machine (CREATED → RUNNING → COMPLETED/FAILED)
- [Source: _bmad-output/specs/spec-axion-runtime/api-protocol.md] — Session lifecycle API (create/attach/resume)
- [Source: _bmad-output/specs/spec-axion-runtime/implementation-roadmap.md] — A2 (AxionRuntime Actor) phase
- [Source: Sources/AxionCore/Models/AxionRunState.swift] — State machine enum with `isValidTransition(to:)`
- [Source: Sources/AxionCore/Models/AxionStateOverlay.swift] — axion-state.json schema
- [Source: Sources/AxionCore/Models/SessionInfo.swift] — Session query model
- [Source: Sources/AxionCLI/Services/AxionRuntime.swift] — AxionRuntime actor

### Project Structure Notes

- All session state persistence lives in `AxionRuntime.swift` — the single actor owns the lifecycle
- `AxionStateOverlay` (AxionCore) and `SessionInfo` (AxionCore) are pure models consumed by CLI and future TUI/App
- No new files created — this story only adds methods to existing files and tests

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
