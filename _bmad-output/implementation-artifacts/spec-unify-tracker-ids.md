---
title: 'Unify Dual Tracker IDs'
type: 'refactor'
created: '2026-05-30'
status: 'done'
baseline_commit: 'e7145c8'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** SDK `RunTracker`, Axion `RunCoordinator`, and `AxionRuntime` each use different IDs for the same run. `AxionRuntime.execute()` generates its own sessionId (line 150), creating a third ID independent of the SDK's runId. SSE events use the SDK runId while session transcripts use the AxionRuntime sessionId — two different keys for the same run.

**Approach:** Thread the SDK's runId through `DaemonRuntimeManager.executeRun()` to `AxionRuntime.execute()` as an optional `sessionId` parameter. When provided, AxionRuntime uses it instead of calling `executor.generateRunId()`. This unifies RunCoordinator, SSE, and session transcript under one ID. The fragile SDK runId lookup (`task == task && status == .queued`) is documented as a known SDK boundary limitation — not something Axion can fix without SDK API changes.

## Boundaries & Constraints

**Always:** Use the SDK's runId as the single authoritative ID for all subsystems. Add `sessionId: String? = nil` to `executeRun()` (optional with nil default = backward compatible). Document the fragile SDK lookup limitation inline with comments.

**Ask First:** None — the approach is constrained by the SDK callback API signature which cannot be changed from Axion's side.

**Never:** Do not modify the SDK API. Do not attempt to eliminate the `task == task && status == .queued` lookup. Do not change RunCoordinator's ID generation strategy. Do not add retry/matching logic to "fix" the concurrent-task ambiguity.

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift` -- Protocol defining `executeRun()` signatures (currently no sessionId param)
- `Sources/AxionCLI/Services/DaemonRuntimeManager.swift` -- Implements `executeRun()`, creates per-request AxionRuntime, stores session history
- `Sources/AxionCLI/Services/AxionRuntime.swift` -- `execute()` generates sessionId at line 150 via `executor.generateRunId()`; `run()` accepts `resumeSessionId` param (line 53)
- `Sources/AxionCLI/Commands/ServerCommand.swift` -- HTTP server runHandler: finds sdkRunId, passes to RunCoordinator, does NOT pass to runtimeManager
- `Sources/AxionCLI/Commands/GatewayCommand.swift` -- Gateway runHandler: same pattern as ServerCommand
- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` -- Calls `runtimeManager.executeRun()` for new tasks, `resumeRun()` for session resumption

## Tasks & Acceptance

**Execution:**
- [x] `Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift` -- Add `sessionId: String?` parameter to both `executeRun()` overloads + convenience extension -- enables external ID injection
- [x] `Sources/AxionCLI/Services/DaemonRuntimeManager.swift` -- Thread `sessionId` through to `AxionRuntime.execute()` -- unifies ID across subsystems
- [x] `Sources/AxionCLI/Services/AxionRuntime.swift` -- Add `sessionId: String? = nil` parameter to `execute()`: when provided, use it instead of `executor.generateRunId()` -- eliminates the third ID
- [x] `Sources/AxionCLI/Commands/ServerCommand.swift` -- Pass `sdkRunId` as `sessionId` to `runtimeManager.executeRun()`, add SDK limitation comment -- connects SDK runId to AxionRuntime
- [x] `Sources/AxionCLI/Commands/GatewayCommand.swift` -- Same change as ServerCommand: pass `sdkRunId` as `sessionId` to `runtimeManager.executeRun()` with limitation comment
- [x] `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` -- Pass `sessionId: nil` explicitly to `runtimeManager.executeRun()` in `executeNewWithTimeout`
- [x] `Tests/AxionCLITests/Services/DaemonRuntimeManagerTests.swift` -- Test sessionId forwarding + existing tests updated for new protocol signature
- [x] `Tests/AxionCLITests/Services/AxionRuntimeTests.swift` -- Test that provided sessionId is used, and nil triggers auto-generation
- [x] `Tests/AxionCLITests/Commands/RunCommandExecutionTests.swift` -- Updated MockAxionRuntime to match new `execute()` signature
- [x] `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` -- Updated MockRuntimeManager to match new `executeRun()` signatures

**Acceptance Criteria:**
- Given a task submitted via HTTP API or Gateway, when the run completes, then RunCoordinator.runId == SSE event runId == session transcript sessionId, and AxionRuntime does not generate a second ID
- Given two identical-text tasks submitted within 100ms, when both runHandlers execute, then the code does NOT claim the `task == task && status == .queued` lookup guarantees correct matching — the limitation is documented in inline comments
- Given a TG user with active session sessionId S, when a follow-up message triggers resumeSession(S), then the resumed session transcript continues using the same sessionId S and SSE events use the same runId

## Spec Change Log

## Verification

**Commands:**
- `swift build` -- expected: clean build with no errors
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` -- expected: all tests pass

## Suggested Review Order

**Session ID threading — the core change**

- Entry point: sessionId parameter replaces auto-generation when provided
  [`AxionRuntime.swift:150`](../../Sources/AxionCLI/Services/AxionRuntime.swift#L150)

- Protocol adds sessionId to both overloads + convenience extension
  [`DaemonRuntimeManaging.swift:14`](../../Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift#L14)

- Manager threads sessionId through to AxionRuntime
  [`DaemonRuntimeManager.swift:61`](../../Sources/AxionCLI/Services/DaemonRuntimeManager.swift#L61)

**SDK runId unification — callers**

- ServerCommand passes sdkRunId as sessionId with limitation comment
  [`ServerCommand.swift:123`](../../Sources/AxionCLI/Commands/ServerCommand.swift#L123)

- GatewayCommand passes sdkRunId as sessionId with limitation comment
  [`GatewayCommand.swift:198`](../../Sources/AxionCLI/Commands/GatewayCommand.swift#L198)

- AxionRuntimeRunning protocol updated for new execute() signature
  [`AxionRuntimeRunning.swift:8`](../../Sources/AxionCLI/Services/Protocols/AxionRuntimeRunning.swift#L8)

**Peripherals — tests and TG path**

- TaskSerialQueue explicitly passes nil for new TG tasks
  [`TaskSerialQueue.swift:200`](../../Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift#L200)

- SessionId passthrough tests in AxionRuntimeTests
  [`AxionRuntimeTests.swift:274`](../../Tests/AxionCLITests/Services/AxionRuntimeTests.swift#L274)

- SessionId forwarding test in DaemonRuntimeManagerTests
  [`DaemonRuntimeManagerTests.swift:428`](../../Tests/AxionCLITests/Services/DaemonRuntimeManagerTests.swift#L428)
