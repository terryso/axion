---
baseline_commit: 4c10dab8b4e240942e212fcd8d5a0507c7c6567c
---
# Story 26.1: RunCommand AxionRuntime Execution

**Status:** done
**Epic:** 26 (CLI + API 改造)
**Priority:** P0
**Depends on:** Epic 24 (AxionRuntime Core), Epic 25 (EventHandler 体系)

## Story

As an Axion developer,
I want RunCommand to delegate all execution to AxionRuntime instead of directly calling RunOrchestrator,
so that session lifecycle (state transitions, session metadata, event dispatch) is managed consistently in one place.

## Acceptance Criteria

1. **Given** RunCommand with a valid task, **When** `run()` is invoked, **Then** it creates an `AxionRuntime` instance, registers all 7 EventHandlers, starts the event loop, calls `runtime.execute(buildConfig:runOverrides:)`, and stops the event loop on completion
2. **Given** AxionRuntime.execute() succeeds, **When** result.state is .completed, **Then** RunCommand exits normally (ExitCode 0)
3. **Given** AxionRuntime.execute() returns .failed, **When** result.state is .failed, **Then** RunCommand throws ExitCode(1)
4. **Given** RunCommand with a skill-prefixed task (`/skill-name ...`), **When** skill is found, **Then** skill executes via `RunOrchestrator.executeSkillDirectly()` bypassing AxionRuntime (fast path)
5. **Given** RunCommand with `--no-skills`, **When** task starts with `/`, **Then** skill fast-path is skipped and task goes through AxionRuntime
6. **Given** unit tests for RunCommand execution path, **When** running tests, **Then** all external dependencies (AxionRuntime, AgentBuilder, RunOrchestrator) are mocked via Protocol injection

## Tasks / Subtasks

- [x] Task 1: Verify RunCommand uses AxionRuntime.execute() path (AC: #1)
  - [x] 1.1 Confirm `RunCommand.run()` creates `EventBus()` and `AxionRuntime(eventBus:)` — Lines 104-105
  - [x] 1.2 Confirm all 7 handlers registered: CostEventHandler, VisualDeltaHandler, SeatMonitorHandler, MemoryProcessingHandler, ReviewHandler, NotificationHandler, TraceEventHandler — Lines 131-137
  - [x] 1.3 Confirm event loop starts before execute and stops after (startEventLoop/stopEventLoop) — Lines 109, 119-120
  - [x] 1.4 Confirm `runtime.execute(buildConfig:runOverrides:)` is called with correct BuildConfig and RunOverrides — Line 118
- [x] Task 2: Verify exit code handling (AC: #2, #3)
  - [x] 2.1 Confirm `.completed` → normal exit — Lines 122-124: only .failed throws, .completed falls through
  - [x] 2.2 Confirm `.failed` → `throw ExitCode(1)` — Line 123
- [x] Task 3: Verify skill fast-path (AC: #4, #5)
  - [x] 3.1 Confirm skill detection via `RunOrchestrator.parseSkillName(from:)` happens before AxionRuntime — Line 78, before Line 104
  - [x] 3.2 Confirm `--no-skills` flag bypasses skill detection — Line 78: `if !noSkills` guard
- [x] Task 4: Add unit tests for RunCommand execution flow (AC: #6)
  - [x] 4.1 Extract `AxionRuntimeRunning` protocol from AxionRuntime with `execute(buildConfig:runOverrides:)` method
  - [x] 4.2 Create `MockAxionRuntime` conforming to `AxionRuntimeRunning`
  - [x] 4.3 Test: successful execution returns exit code 0
  - [x] 4.4 Test: failed execution throws ExitCode(1)
  - [x] 4.5 Test: skill fast-path bypasses AxionRuntime
  - [x] 4.6 Test: handler registration count matches expected 7

## Dev Notes

### Current State (Already Migrated)

RunCommand was migrated to AxionRuntime during Epic 25 (commit `4afff9d feat(epic-25): EventHandler 体系 — 7 个 handler 实现 + RunCommand 集成`). The current code at `Sources/AxionCLI/Commands/RunCommand.swift` already:
- Creates `EventBus()` and `AxionRuntime(eventBus:)` (lines 104-105)
- Registers all 7 handlers via `registerHandlers(into:config:)` (lines 127-138)
- Starts/stops event loop (lines 109, 119-120)
- Calls `runtime.execute(buildConfig:runOverrides:)` (line 118)
- Handles exit codes based on result.state (lines 122-124)

### Remaining Work

The primary gap is **test coverage**. RunCommand's execution path lacks unit tests because AxionRuntime is an `actor` with no protocol abstraction. To enable testability:
1. Extract an `AxionRuntimeRunning` protocol from AxionRuntime's public interface
2. Make RunCommand accept the protocol (dependency injection)
3. Create MockAxionRuntime for testing

### Key Files

| File | Role |
|------|------|
| `Sources/AxionCLI/Commands/RunCommand.swift` | CLI entry point — argument parsing + AxionRuntime delegation |
| `Sources/AxionCLI/Services/AxionRuntime.swift` | Actor wrapping RunOrchestrator with session lifecycle |
| `Sources/AxionCLI/Services/Protocols/RunExecuting.swift` | Protocol for RunOrchestrator mock |
| `Tests/AxionCLITests/Services/AxionRuntimeTests.swift` | AxionRuntime unit tests (existing, 17 tests) |
| `Tests/AxionCLITests/Commands/RunCommand*Tests.swift` | RunCommand test files (existing, but no execution-flow tests) |

### Testing Standards

- Use Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`)
- All external dependencies must be mocked via Protocol injection
- Do NOT call real AgentBuilder.build(), RunOrchestrator.execute(), or MCP connections in unit tests
- Unit test directories: `Tests/AxionCLITests/Commands/`, `Tests/AxionCLITests/Services/`
- Run: `swift test --filter "AxionCLITests"`

### Project Structure Notes

- RunCommand is in `Sources/AxionCLI/Commands/` (ArgumentParser layer)
- AxionRuntime is in `Sources/AxionCLI/Services/` (business logic layer)
- Protocols for mocking go in `Sources/AxionCLI/Services/Protocols/`
- Test mocks can live in the test file or in a shared test helper

### References

- [Source: Sources/AxionCLI/Commands/RunCommand.swift] — Current RunCommand implementation
- [Source: Sources/AxionCLI/Services/AxionRuntime.swift] — AxionRuntime actor with execute() method
- [Source: _bmad-output/implementation-artifacts/24-1-axionruntime-skeleton.md] — AxionRuntime design story
- [Source: _bmad-output/implementation-artifacts/25-1-eventhandler-protocol-registration.md] — EventHandler protocol
- [Source: _bmad-output/implementation-artifacts/25-7-trace-event-handler.md] — TraceEventHandler (last handler)
- [Source: _bmad-output/planning-artifacts/architecture.md] — Architecture decisions D1-D8

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Swift Testing parallel execution caused static factory state corruption; fixed with `.serialized` suite trait.

### Completion Notes List

- Tasks 1-3: Verified existing RunCommand code (already migrated in Epic 25) — EventBus creation, 7 handler registration, event loop lifecycle, exit code handling, skill fast-path.
- Task 4: Extracted `AxionRuntimeRunning` protocol from AxionRuntime; added `createRuntime` and `skillExecutorOverride` test seams to RunCommand; created `MockAxionRuntime` actor mock; wrote 5 unit tests (all pass, 1087 total tests pass).
- Key design: `AxionRuntimeRunning` protocol covers `registerHandler`, `startEventLoop`, `stopEventLoop`, and `execute`. `AxionRuntime` conforms automatically (existing methods satisfy protocol). Test seams use `nonisolated(unsafe)` static vars to avoid Sendability warnings.

### File List

- `Sources/AxionCLI/Services/Protocols/AxionRuntimeRunning.swift` (new) — Protocol for AxionRuntime dependency injection
- `Sources/AxionCLI/Services/AxionRuntime.swift` (modified) — Added `AxionRuntimeRunning` conformance
- `Sources/AxionCLI/Commands/RunCommand.swift` (modified) — Added `createRuntime` and `skillExecutorOverride` test seams; `registerHandlers` accepts `any AxionRuntimeRunning`
- `Tests/AxionCLITests/Commands/RunCommandExecutionTests.swift` (new) — 8 unit tests with MockAxionRuntime

### Change Log

- 2026-05-27: Extracted AxionRuntimeRunning protocol, added DI test seams to RunCommand, created 5 unit tests covering execution flow, exit codes, skill fast-path, and handler registration

## Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.7
**Date:** 2026-05-27

### Findings (4 total)

| # | Severity | Issue | Status |
|---|----------|-------|--------|
| 1 | HIGH | Event loop resource leak: `runtime.execute()` throws → `eventLoopTask.cancel()` and `runtime.stopEventLoop()` never called | Fixed |
| 2 | MEDIUM | Missing event loop lifecycle verification: mock didn't track `startEventLoop`/`stopEventLoop` calls | Fixed |
| 3 | MEDIUM | Missing test for skill-not-found fallback: `/nonexistent-skill` should fall through to AxionRuntime | Fixed |
| 4 | LOW | Test boilerplate duplication: save/restore pattern repeated across all tests | Fixed |

### Fixes Applied

1. **RunCommand.swift**: Wrapped `execute()` in do/catch to ensure event loop cleanup on error path
2. **RunCommandExecutionTests.swift**: Added `startEventLoopCallCount`/`stopEventLoopCallCount` tracking to MockAxionRuntime; added `executeError` initializer for throw-on-execute scenarios
3. Added 3 new tests: `eventLoopStoppedOnSuccess`, `eventLoopCleanupOnError`, `unknownSkillFallsThroughToRuntime`
4. Extracted `withMockRuntime` helper to eliminate static state save/restore duplication

### Test Results

1090 tests pass (1087 original + 3 new)
