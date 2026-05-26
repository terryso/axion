---
baseline_commit: 835e2d62d72a219f644ef4c47070dc67dcde5533
---

# Story 24.2: Agent Build + Execution — AxionRuntime Owns the Full Pipeline

Status: in-progress

## Story

As a Axion developer,
I want AxionRuntime to own the complete agent build → execute pipeline,
so that callers (CLI, API, MCP) provide config + task and receive a structured result, without manually orchestrating AgentBuilder and RunOrchestrator.

## Acceptance Criteria

1. **Given** `AxionRuntime.execute(buildConfig:runOverrides:)` is called with a valid BuildConfig
   **When** the method completes
   **Then** AxionRuntime internally calls `AgentBuilder.build(buildConfig)`, constructs a `RunOrchestrator.RunConfig`, delegates to the existing `run()` method, and returns an `AxionRunResult`

2. **Given** `AgentBuilder.build()` throws an error (e.g., missing API key)
   **When** `execute()` is called
   **Then** AxionRuntime transitions to FAILED and returns `AxionRunResult` with `runSucceeded=false`, `errorMessage` populated, `totalSteps=0`, `durationMs=0` — the error does NOT propagate to the caller

3. **Given** `AgentBuilder.build()` succeeds but `RunOrchestrator.execute()` throws
   **When** `execute()` is called
   **Then** AxionRuntime transitions to FAILED with the error message (same behavior as existing `run()` — already working)

4. **Given** the `RunOverrides` struct with default values
   **When** no overrides are provided
   **Then** `json=false`, `noVisualDelta=false`, `noReview=false`, `onReviewCompleted=nil` are used

5. **Given** `AxionRuntime.execute()` with `eventBus` provided at init
   **When** the internal RunConfig is constructed
   **Then** `eventBus` from the runtime is passed through (same as existing `run()` behavior)

6. **Given** `buildConfig.task` is set
   **When** `execute()` constructs the RunConfig
   **Then** `runConfig.task` equals `buildConfig.task` — single source of truth, no separate task parameter

7. **Given** the existing `run(task:buildResult:runConfig:)` method
   **When** callers use it directly
   **Then** behavior is unchanged — backward compatible

8. **Given** `AxionRuntime.execute()` is called twice on the same instance
   **When** the second call is made
   **Then** the state transition guard rejects it (CREATED → RUNNING only valid once, same as existing `run()`)

9. **Given** `AxionRuntime.execute()` runs in dryrun mode
   **When** the dryrun completes
   **Then** it returns a valid `AxionRunResult` with `state=completed` and `runSucceeded=true`

## Tasks / Subtasks

- [ ] Task 1: Define RunOverrides struct (AC: #4)
  - [ ] 1.1 Add `RunOverrides` struct inside `AxionRuntime` with fields: `json: Bool`, `noVisualDelta: Bool`, `noReview: Bool`, `onReviewCompleted: (@Sendable (String) -> Void)?`
  - [ ] 1.2 Add `static let `default`` with all booleans false and closure nil
  - [ ] 1.3 Make it `Sendable`

- [ ] Task 2: Implement `execute()` method (AC: #1, #2, #5, #6)
  - [ ] 2.1 Add `func execute(buildConfig: AgentBuilder.BuildConfig, runOverrides: RunOverrides = .default) async throws -> AxionRunResult`
  - [ ] 2.2 Generate sessionId and createdAt, set state to RUNNING
  - [ ] 2.3 Call `AgentBuilder.build(buildConfig)` — on failure, transition to FAILED and return error result (AC #2)
  - [ ] 2.4 Construct `RunOrchestrator.RunConfig` from buildConfig fields + runOverrides fields + eventBus (AC #5, #6)
  - [ ] 2.5 Delegate to existing `run()` method with the buildResult and constructed runConfig
  - [ ] 2.6 Return the AxionRunResult from `run()`

- [ ] Task 3: Write unit tests (AC: #1–#9)
  - [ ] 3.1 Test: `execute()` with dryrun BuildConfig returns COMPLETED with valid result (AC #1)
  - [ ] 3.2 Test: `execute()` with missing API key config returns FAILED with errorMessage (AC #2)
  - [ ] 3.3 Test: `execute()` with default RunOverrides uses correct values (AC #4)
  - [ ] 3.4 Test: `execute()` passes eventBus through to RunConfig (AC #5)
  - [ ] 3.5 Test: `execute()` uses buildConfig.task as runConfig.task (AC #6)
  - [ ] 3.6 Test: existing `run()` method still works unchanged (AC #7)
  - [ ] 3.7 Test: second `execute()` call on same instance is rejected by state guard (AC #8)
  - [ ] 3.8 Test: `execute()` in dryrun mode returns completed with runSucceeded (AC #9)

## Dev Notes

### Architecture Context

This story implements **Phase 9, Epic 24, Story 2** — giving AxionRuntime ownership of the full build→execute pipeline. Story 24.1 created the AxionRuntime skeleton with `run()` that wraps RunOrchestrator.execute(). This story adds `execute()` that wraps the complete AgentBuilder.build() → RunOrchestrator.execute() pipeline.

**Current flow (Story 24.1):**
```
Caller: AgentBuilder.build(config) → buildResult
Caller: AxionRuntime.run(task, buildResult, runConfig) → AxionRunResult
```

**New flow (Story 24.2):**
```
Caller: AxionRuntime.execute(buildConfig, runOverrides) → AxionRunResult
  Internally: AgentBuilder.build(config) → RunOrchestrator.execute() → AxionRunResult
```

The existing `run()` method is preserved for callers that already have a buildResult (backward compatible). Future Epic 26 (CLI/API migration) will switch RunCommand and ApiRunner to use `execute()`.

### RunOverrides Design

`RunOverrides` captures run-time options that are NOT in `AgentBuilder.BuildConfig`:

| Field | In BuildConfig? | In RunConfig? | Notes |
|-------|-----------------|---------------|-------|
| task | YES | YES | Derived from buildConfig.task |
| fast | YES | YES | Derived from buildConfig.fast |
| dryrun | YES | YES | Derived from buildConfig.dryrun |
| noMemory | YES | YES | Derived from buildConfig.noMemory |
| allowForeground | YES | YES | Derived from buildConfig.allowForeground |
| maxSteps | YES | YES | Derived from buildConfig.maxSteps |
| config | YES | YES | Derived from buildConfig.config |
| json | NO | YES | **RunOverrides.json** |
| noVisualDelta | NO | YES | **RunOverrides.noVisualDelta** |
| noReview | NO | YES | **RunOverrides.noReview** |
| onReviewCompleted | NO | YES | **RunOverrides.onReviewCompleted** |
| eventBus | NO | YES | From AxionRuntime.eventBus |
| noSkills | YES | NO | Build-time only |
| maxTokens | YES | NO | Build-time only |
| verbose | YES | NO | Build-time only |

### Build Failure Handling (AC #2)

This is a key improvement over the current `run()` method. Currently, if `AgentBuilder.build()` fails (e.g., missing API key, helper not found), the error is thrown BEFORE AxionRuntime is involved. The runtime stays in CREATED state.

With `execute()`, the build step is INSIDE AxionRuntime. Build failures are caught, the runtime transitions to FAILED, and returns a structured `AxionRunResult` with the error. This means AxionRuntime always transitions CREATED → terminal state, providing consistent lifecycle tracking.

```swift
func execute(buildConfig: AgentBuilder.BuildConfig, runOverrides: RunOverrides = .default) async throws -> AxionRunResult {
    let sid = RunOrchestrator.generateRunId()
    let startedAt = Date()
    sessionId = sid
    createdAt = startedAt

    guard currentState.isValidTransition(to: .running) else {
        assertionFailure("Invalid state transition from \(currentState) to running")
        currentState = .failed
        return AxionRunResult(
            sessionId: sid, task: buildConfig.task, state: .failed,
            totalSteps: 0, durationMs: 0, runSucceeded: false,
            errorMessage: "Invalid state transition from \(currentState) to running",
            createdAt: startedAt
        )
    }
    currentState = .running

    // Build agent — catch failures and map to FAILED
    let buildResult: AgentBuildResult
    do {
        buildResult = try await AgentBuilder.build(buildConfig)
    } catch {
        currentState = .failed
        return AxionRunResult(
            sessionId: sid, task: buildConfig.task, state: .failed,
            totalSteps: 0, durationMs: 0, runSucceeded: false,
            errorMessage: error.localizedDescription,
            createdAt: startedAt
        )
    }

    // Construct RunConfig from buildConfig + runOverrides
    let runConfig = RunOrchestrator.RunConfig(
        task: buildConfig.task,
        fast: buildConfig.fast,
        dryrun: buildConfig.dryrun,
        json: runOverrides.json,
        noMemory: buildConfig.noMemory,
        noVisualDelta: runOverrides.noVisualDelta,
        allowForeground: buildConfig.allowForeground,
        maxSteps: buildConfig.maxSteps,
        config: buildConfig.config,
        noReview: runOverrides.noReview,
        onReviewCompleted: runOverrides.onReviewCompleted,
        eventBus: eventBus
    )

    // Delegate to existing run() for the execute phase
    return await run(task: buildConfig.task, buildResult: buildResult, runConfig: runConfig)
    // Note: run() already handles CREATED→RUNNING transition, but we already transitioned above.
    // run() will see state as RUNNING and the guard will fail. We need to adjust this.
}
```

**Wait — there's a problem.** The existing `run()` method transitions CREATED → RUNNING. But `execute()` already transitioned before calling `run()`. So calling `run()` from `execute()` would hit the state guard.

**Solution:** Refactor the transition logic out of `run()`. Extract the core execution into a private method that doesn't do state transitions, then have both `run()` and `execute()` do their own transitions and call the private method.

Or simpler: `execute()` should NOT call `run()`. Instead, duplicate the RunOrchestrator.execute() call with the same error handling. But that's code duplication.

**Best approach:** Extract a private `executeWithBuildResult()` that takes buildResult + runConfig and calls RunOrchestrator.execute(), handles state transitions, and returns AxionRunResult. Both `run()` and `execute()` set up their own pre-conditions (run validates CREATED, execute does build) and then call the private method.

Actually, the simplest approach: **`execute()` does NOT transition to RUNNING before building.** It transitions after building succeeds. And `run()` stays as-is for backward compatibility.

```swift
func execute(buildConfig: AgentBuilder.BuildConfig, runOverrides: RunOverrides = .default) async throws -> AxionRunResult {
    let sid = RunOrchestrator.generateRunId()
    let startedAt = Date()
    sessionId = sid
    createdAt = startedAt

    // Build agent first (before state transition)
    let buildResult: AgentBuildResult
    do {
        buildResult = try await AgentBuilder.build(buildConfig)
    } catch {
        // Build failed — transition CREATED → FAILED directly
        currentState = .failed
        return AxionRunResult(
            sessionId: sid, task: buildConfig.task, state: .failed,
            totalSteps: 0, durationMs: 0, runSucceeded: false,
            errorMessage: error.localizedDescription,
            createdAt: startedAt
        )
    }

    // Build succeeded — now delegate to run() which handles CREATED → RUNNING → COMPLETED/FAILED
    let runConfig = RunOrchestrator.RunConfig(
        task: buildConfig.task,
        fast: buildConfig.fast,
        dryrun: buildConfig.dryrun,
        json: runOverrides.json,
        noMemory: buildConfig.noMemory,
        noVisualDelta: runOverrides.noVisualDelta,
        allowForeground: buildConfig.allowForeground,
        maxSteps: buildConfig.maxSteps,
        config: buildConfig.config,
        noReview: runOverrides.noReview,
        onReviewCompleted: runOverrides.onReviewCompleted,
        eventBus: eventBus
    )

    // run() still sees CREATED state and does CREATED → RUNNING transition
    return try await run(task: buildConfig.task, buildResult: buildResult, runConfig: runConfig)
}
```

This works because `execute()` does NOT change state before calling `run()`. Build failures go CREATED → FAILED directly. Build successes go through `run()` which does CREATED → RUNNING → COMPLETED/FAILED.

But wait — `isValidTransition` doesn't allow CREATED → FAILED. Let me check:

```swift
case (.created, .running): true
case (.running, .completed): true
case (.running, .failed): true
default: false
```

CREATED → FAILED is not valid! This is correct for the state machine design (you can't fail before starting), but for build failures we need a way to express "never started, but failed."

**Options:**
1. Add CREATED → FAILED transition (valid: session initialized but failed before running)
2. Skip state transition on build failure and return result with .failed anyway (inconsistent state)
3. Return a special error result without changing state (state stays CREATED)

**Best option: #1** — add CREATED → FAILED transition. This makes sense: a session was created, but it failed to start (build error). The AxionRunState should support this. It's also what the spec's state machine implies — FAILED is a terminal state reachable from RUNNING, but "never ran" should also be expressible.

Actually, looking at the spec state machine again:
```
CREATED → RUNNING → COMPLETED
                  → PAUSED → RUNNING (resume)
                           → COMPLETED
                  → FAILED
```

FAILED is only from RUNNING. But that's the ideal state machine. For build failures (pre-running), we need CREATED → FAILED. This is pragmatic.

Alternatively, we could NOT change state and just return the result. The caller sees `AxionRunResult.state == .failed` but `AxionRuntime.currentState == .created`. That's inconsistent but harmless.

**Simplest approach:** Don't transition state on build failure. The runtime stays in CREATED. The returned `AxionRunResult` has `state: .failed`. The state machine is about the runtime's own state, while the result's state is about the run outcome. They can differ.

Actually, this IS what the current `run()` does in the guard-failure case:
```swift
guard currentState.isValidTransition(to: .running) else {
    currentState = .failed  // ← This sets state to .failed even though transition is invalid!
    return AxionRunResult(...)
}
```

Hmm, the current code DOES force .failed even for invalid transitions. So we could do the same for build failures. But that's inconsistent with isValidTransition().

Let me just keep it simple: on build failure, set `currentState = .failed` and return `.failed` result. The state machine transition is CREATED → FAILED, which we'll add as valid.

### Files to Modify

| File | Action | Details |
|------|--------|---------|
| `Sources/AxionCLI/Services/AxionRuntime.swift` | **UPDATE** | Add RunOverrides struct, execute() method, add CREATED→FAILED transition |
| `Sources/AxionCore/Models/AxionRunState.swift` | **UPDATE** | Add `(.created, .failed)` as valid transition |
| `Tests/AxionCLITests/Services/AxionRuntimeTests.swift` | **UPDATE** | Add tests for execute() method |
| `Tests/AxionCoreTests/Models/AxionRunStateTests.swift` | **UPDATE** | Add test for CREATED→FAILED transition |

### AxionRunState Change

Add `(.created, .failed)` transition — represents "session created but build/initialization failed before execution started":

```swift
public func isValidTransition(to target: AxionRunState) -> Bool {
    switch (self, target) {
    case (.created, .running): true
    case (.created, .failed): true   // NEW: build failure
    case (.running, .completed): true
    case (.running, .failed): true
    default: false
    }
}
```

### Import Order Reminder

```swift
// AxionRuntime.swift
import Foundation
import OpenAgentSDK

import AxionCore
```

### Testing Strategy

- Use `dryrun: true` in BuildConfig to test the success path without real LLM calls
- Use `AxionConfig(apiKey: nil)` (no API key) to trigger build failure
- All tests follow Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`)
- Run with: `make test` (runs all unit tests, skips integration/e2e)

### Previous Story Learnings (24.1)

- `AxionRuntime` is `public actor` — new method should be `func execute(...)` (internal, like `run()`)
- `AgentBuildResult` and `RunOrchestrator.RunConfig` are internal types — `execute()` must also be internal
- `RunOrchestrator.generateRunId()` is static — `YYYYMMDD-{6 lowercase alphanumeric}`
- `RunOrchestrator.RunConfig` is `Sendable`
- `AgentBuildResult` contains: agent, helperPath, memoryDir, systemPrompt, agentOptions, skillRegistry, skillRegisteredCount, runCompleteBox, reviewOrchestrator, intelligentCurator, usageStore
- SIGINT is handled inside RunOrchestrator — no need to duplicate in execute()
- `AxionRunResult` has `errorMessage: String?` field (added during 24.1 review)
- Review/curator run in detached tasks — their output goes to stderr via fputs()

### References

- [Source: _bmad-output/specs/spec-axion-runtime/SPEC.md] — AxionRuntime capabilities, constraints
- [Source: _bmad-output/specs/spec-axion-runtime/implementation-roadmap.md] — A2 (AxionRuntime Actor)
- [Source: _bmad-output/specs/spec-axion-runtime/architecture-diagrams.md] — Target: AxionRuntime → AgentBuilder → Agent.stream()
- [Source: _bmad-output/specs/spec-axion-runtime/state-machines.md] — Session state transitions
- [Source: Sources/AxionCLI/Services/AxionRuntime.swift] — Current AxionRuntime actor (Story 24.1)
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift] — AgentBuilder.build() and BuildConfig
- [Source: Sources/AxionCLI/Services/RunOrchestrator.swift] — RunConfig, RunResult, execute()
- [Source: Sources/AxionCore/Models/AxionRunState.swift] — State machine with isValidTransition()
- [Source: Tests/AxionCLITests/Services/AxionRuntimeTests.swift] — Existing test patterns

### Project Structure Notes

- AxionRuntime stays in `Sources/AxionCLI/Services/` (same as 24.1)
- RunOverrides is defined inside AxionRuntime (nested type) — no new file needed
- Tests go in existing `Tests/AxionCLITests/Services/AxionRuntimeTests.swift`
- No new dependencies — all types already exist from 24.1

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
