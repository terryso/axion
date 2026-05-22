---
title: 'Epic 21 Continued: Enable SDK trace + onRunComplete + Delete Adapters'
type: 'refactor'
created: '2026-05-21'
status: 'in-progress'
baseline_commit: '2da5a59'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-axion-deep-analysis-sdk-extraction.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** After Epic 21's SDK extraction refactor, AxionCLI still has 10,688 lines (target ≤ 6,000). Story 21.2 incorrectly claimed SDK lacked `traceEnabled`/`onRunComplete` — these already exist and are fully wired into the Agent run loop. Story 21.1 kept adapter files (`AxionRunTracker`, `AxionRunPersistence`) that could directly use SDK components. Three files should have been deleted but weren't: `TraceRecorder.swift` (309 lines), `AxionRunTracker.swift` (154 lines), `AxionRunPersistence.swift` (149 lines).

**Approach:** (1) Delete Axion's `TraceRecorder.swift`, configure `AgentOptions.traceEnabled = true` and `traceBaseURL`, letting SDK Agent auto-create and manage TraceRecorder. (2) Hook `AgentOptions.onRunComplete` callback for post-run logic (cost display, Memory extraction). (3) Delete `AxionRunTracker` and `AxionRunPersistence`, use SDK's `RunTracker` and `RunPersistenceService` directly (with Axion's `~/.axion/` directory). Target: AxionCLI ≤ 8,000 lines.

## Boundaries & Constraints

**Always:**
- All existing CLI args, flags, and observable behavior unchanged
- Memory operations stay non-fatal (do/catch wrapped, failures only warning)
- API response format remains `StandardTaskOutput` (AxionBar compatible)
- AxionHelper and AxionBar untouched
- Unit tests all pass after each phase

**Ask First:**
- Whether Axion desktop-specific trace events (lock_acquired, takeover_*, seat_baseline, etc.) can be dropped — SDK doesn't auto-generate these

**Never:**
- Modify SDK Agent run loop internals (use SDK public API only)
- Change `StandardTaskOutput` or any API response format
- Move desktop-specific code into SDK

</frozen-after-approval>

## Code Map

**Files to delete (3 source files, ~612 lines):**
- `Sources/AxionCLI/Trace/TraceRecorder.swift` (309 lines) — SDK `AgentOptions.traceEnabled` replaces
- `Sources/AxionCLI/API/AxionRunTracker.swift` (154 lines) — SDK `RunTracker` replaces
- `Sources/AxionCLI/API/AxionRunPersistence.swift` (149 lines) — SDK `RunPersistenceService` replaces

**Files to simplify:**
- `Sources/AxionCLI/Services/RunOrchestrator.swift` (513 lines) — Remove all TraceRecorder calls (~96 lines), simplify post-run with onRunComplete data
- `Sources/AxionCLI/API/ApiRunner.swift` (329 lines) — Remove TraceRecorder parameter and all trace calls (~11 lines)
- `Sources/AxionCLI/Services/AgentBuilder.swift` (412 lines) — Add traceEnabled, traceBaseURL, onRunComplete config (~5 lines net)

**Files to update references:**
- `Sources/AxionCLI/Commands/ServerCommand.swift` — Use SDK's `RunTracker` + `RunPersistenceService`
- `Sources/AxionCLI/API/AxionAPI.swift` — Update parameter types to SDK's `RunTracker`/`RunPersistenceService`
- `Sources/AxionCLI/API/AxionRunRecovery.swift` — Use SDK's `RunPersistenceService`
- `Sources/AxionCLI/MCP/RunTaskTool.swift` — Update tracker type to SDK `RunTracker`
- `Sources/AxionCLI/MCP/QueryTaskStatusTool.swift` — Update tracker type to SDK `RunTracker`
- `Sources/AxionCLI/MCP/MCPServerRunner.swift` — Update tracker creation

**Test files to delete:**
- `Tests/AxionCLITests/Trace/TraceRecorderTests.swift` (322 lines)
- `Tests/AxionCLITests/Trace/TraceWindowContextTests.swift` (161 lines)

**SDK reference (read-only):**
- `../open-agent-sdk-swift/Sources/OpenAgentSDK/Types/AgentTypes.swift` — AgentOptions fields: traceEnabled (Bool, default false), traceBaseURL (String?, default nil → `~/.open-agent-sdk/traces/`), onRunComplete (callback), runId (String?), RunCompleteContext struct
- `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/RunTracker.swift` — SDK actor: `init()`, `submitRun(task:)`, `startRun/completeRun/failRun`, `getRun/listRuns`
- `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/RunPersistenceService.swift` — SDK struct: `init(baseDirectory:)`, `persistRecord/persistEvent/loadRecord/loadEvents`

## Tasks & Acceptance

**Phase A: Delete TraceRecorder, enable SDK built-in trace (-309 source lines)**

- [ ] `Sources/AxionCLI/Services/AgentBuilder.swift` — Set `agentOptions.traceEnabled = true`, `agentOptions.traceBaseURL = "~/.axion/runs"`, keep existing `agentOptions.runId = buildConfig.runId`
- [ ] `Sources/AxionCLI/Services/RunOrchestrator.swift` — Remove `TraceRecorder` init (line 80), all `await tracer?.record*` calls, `recordToTrace` function (lines 463-512), `await tracer?.close()` (line 266). Keep seat monitor, visual delta, takeover, and memory processing logic unchanged.
- [ ] `Sources/AxionCLI/API/ApiRunner.swift` — Remove `tracer: TraceRecorder` parameter from `processStream`/`processStreamFromAsyncStream`, remove tracer creation (line 57), remove `await tracer?.close()` (line 286), remove `recordSeatBaseline` and `recordExternalActivityDetected` calls
- [ ] `Sources/AxionCLI/Trace/TraceRecorder.swift` — Delete file
- [ ] `Tests/AxionCLITests/Trace/TraceRecorderTests.swift` — Delete file
- [ ] `Tests/AxionCLITests/Trace/TraceWindowContextTests.swift` — Delete file
- [ ] Remove any remaining `import` or references to deleted `TraceRecorder` in `RunMemoryProcessor.swift`, `TakeoverMarker.swift` — change `tracer` parameter to nil or remove

**Phase B: Delete AxionRunTracker + AxionRunPersistence, use SDK directly (-303 source lines)**

- [ ] `Sources/AxionCLI/API/Models/APITypes.swift` — Keep Axion's `TrackedRun` model (extra fields: submittedAt, steps, costTelemetry, exitCode, intervention, result, etc.). Add conversion: `init(fromSDK:)` and `func toSDK() -> OpenAgentSDK.TrackedRun`
- [ ] `Sources/AxionCLI/Commands/ServerCommand.swift` — Replace `AxionRunPersistence()` + `AxionRunTracker()` with `RunPersistenceService(baseDirectory: "~/.axion/api-runs")` + SDK `RunTracker()`. Pass SDK types to `AxionAPI.registerRoutes`.
- [ ] `Sources/AxionCLI/API/AxionAPI.swift` — Update `registerRoutes` parameter types from `AxionRunTracker`/`AxionRunPersistence` to SDK's `RunTracker`/`RunPersistenceService`. Convert between Axion and SDK TrackedRun where needed.
- [ ] `Sources/AxionCLI/API/AxionRunRecovery.swift` — Use SDK's `RunPersistenceService` for loading persisted runs, keep recovery logic
- [ ] `Sources/AxionCLI/API/AxionRunTracker.swift` — Delete file
- [ ] `Sources/AxionCLI/API/AxionRunPersistence.swift` — Delete file
- [ ] `Sources/AxionCLI/MCP/RunTaskTool.swift` — Change `runTracker: AxionRunTracker` to `runTracker: RunTracker`
- [ ] `Sources/AxionCLI/MCP/QueryTaskStatusTool.swift` — Change `runTracker: AxionRunTracker` to `runTracker: RunTracker`
- [ ] `Sources/AxionCLI/MCP/MCPServerRunner.swift` — Change `AxionRunTracker()` to `RunTracker()`

**Phase C: Hook onRunComplete callback**

- [ ] `Sources/AxionCLI/Services/AgentBuilder.swift` — Add `onRunComplete` closure to AgentOptions, capturing RunCompleteContext data (toolPairs, totalCostUsd, usage, costBreakdown, durationMs, numTurns, status, runId) into a thread-safe container accessible after the stream loop
- [ ] `Sources/AxionCLI/Services/RunOrchestrator.swift` — After stream loop, use onRunComplete data instead of manually tracking resultToolPairs, resultUsage, resultTotalCostUsd, resultCostBreakdown from the `.result` message. Pass the captured data to `RunMemoryProcessor.processRunResult`.

**Acceptance Criteria:**
- Given `Sources/AxionCLI/Trace/TraceRecorder.swift`, when checked, then file is deleted
- Given `axion run "open calculator" --trace` completes, then `~/.axion/runs/{runId}/trace.jsonl` contains SDK auto-generated trace events (step_start, step_done, run_done, tool_use, tool_result, result)
- Given `Sources/AxionCLI/API/AxionRunTracker.swift`, when checked, then file is deleted
- Given `Sources/AxionCLI/API/AxionRunPersistence.swift`, when checked, then file is deleted
- Given `axion server --port 4242`, when running, then all HTTP endpoints respond identically to before (StandardTaskOutput format, SSE stream, run history)
- Given `swift test`, when running, then all unit tests pass
- Given `Sources/AxionCLI/`, when counting lines, then total ≤ 8,000

## Spec Change Log

## Design Notes

### SDK Trace Already Fully Implemented

SDK Agent loop auto-creates `TraceRecorder` when `options.traceEnabled = true`:
```swift
var traceRecorder: TraceRecorder? = nil
if options.traceEnabled {
    let traceBaseURL: URL? = options.traceBaseURL.map { URL(fileURLWithPath: $0) }
    traceRecorder = try? TraceRecorder(runId: runIdForTrace, baseURL: traceBaseURL)
}
```

And fires `onRunComplete` at run end with `RunCompleteContext(toolPairs, task, runId, status, usage, totalCostUsd, durationMs, numTurns, costBreakdown)`.

### Axion Desktop-Specific Trace Events (to be dropped)

Axion's TraceRecorder recorded events SDK won't auto-generate:
- `lock_acquired`, `lock_released` (RunLockService)
- `takeover_start`, `takeover_end` (TakeoverIO)
- `seat_baseline` (SeatActivityMonitor)
- `verifier_skipped` (RunOrchestrator)
- `external_activity_detected` (SeatActivityMonitor)
- `assistant_message` (RunOrchestrator)

**Decision:** Accept losing these Axion-specific events. SDK covers core events (tool use/result, step start/done, run done, budget). Axion-specific events are debug aids, not functional.

### RunTracker Adapter Elimination Strategy

SDK's `RunTracker` (in-memory actor) differs from Axion's `AxionRunTracker`:
- SDK: `submitRun(task:)` → SDK `TrackedRun`, separate `startRun/completeRun/failRun`
- Axion: `submitRun(task:options:)` → `String`, `updateRun` handles everything

Axion's `TrackedRun` has 15+ fields (submittedAt, steps, costTelemetry, intervention, result, exitCode, etc.) vs SDK's 9 fields.

**Strategy:** Keep Axion's `TrackedRun` model. Use SDK's `RunTracker` for in-memory lifecycle management. Add conversion methods `init(fromSDK:)` / `toSDK()` on Axion's TrackedRun. Use SDK's `RunPersistenceService(baseDirectory: "~/.axion/api-runs")` for disk persistence, converting to/from SDK TrackedRun at persistence boundaries.

**Important:** SDK's `RunPersistenceService.persistRecord()` encodes SDK `TrackedRun`. To persist Axion's richer TrackedRun, we write Axion TrackedRun JSON directly to the same path structure (`~/.axion/api-runs/{runId}/api-output.json`), bypassing SDK's persistRecord for the record but using SDK's persistEvent for SSE events.

## Verification

**Commands:**
- `swift build` — expected: clean build, no warnings
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` — expected: all pass
- `find Sources/AxionCLI -name "*.swift" -exec wc -l {} + | tail -1` — expected: ≤ 8,000
