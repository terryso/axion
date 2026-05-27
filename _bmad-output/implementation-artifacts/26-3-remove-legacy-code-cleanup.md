---
baseline_commit: 6d53ff83be762d3bf59e2a4f3fd211ddf4442cc0
---
# Story 26.3: Remove Legacy Code Cleanup

Status: done

## Story

As an Axion developer,
I want to remove duplicated concerns from RunOrchestrator and dead code from ApiRunner,
so that the codebase is simpler, there's no double-processing of cost/memory/visual-delta/notification concerns, and maintenance is easier.

## Acceptance Criteria

1. **Given** `ApiRunner.runAgent()` has zero callers in `Sources/`, **When** removed, **Then** the project compiles and all tests pass
2. **Given** `ApiRunner.processStream()` is only called by `runAgent()` (dead), **When** removed alongside `runAgent()`, **Then** `runSkillAgent()` still works via `processStreamFromAsyncStream()` (its only call site is `AxionAPI.swift:283`)
3. **Given** RunOrchestrator.execute() has visual delta tracking (lines 100-103, 108, 166-176), **When** removed, **Then** VisualDeltaHandler handles all visual delta concerns via EventBus
4. **Given** RunOrchestrator.execute() has seat monitoring (lines 111, 136-139, 217-220), **When** removed, **Then** SeatMonitorHandler handles all seat monitoring via EventBus
5. **Given** RunOrchestrator.execute() has cost summary output (lines 237-242), **When** removed, **Then** CostEventHandler outputs cost summary via EventBus
6. **Given** RunOrchestrator.execute() has memory processing (lines 244-267), **When** removed, **Then** MemoryProcessingHandler handles memory processing via EventBus
7. **Given** RunOrchestrator.execute() has desktop notification + activateTerminal (lines 370-381), **When** removed, **Then** NotificationHandler handles notifications via EventBus
8. **Given** all legacy code removed, **When** running `swift test --filter "AxionCLITests"`, **Then** all tests pass with 0 failures
9. **Given** all legacy code removed, **When** running `swift build`, **Then** the project compiles with 0 errors

## Tasks / Subtasks

- [x] Task 1: Remove dead ApiRunner code (AC: #1, #2)
  - [x] 1.1 Delete `ApiRunner.runAgent()` (lines 29-74) — zero callers in `Sources/`
  - [x] 1.2 Delete `ApiRunner.processStream()` (lines 139-164) — only caller was `runAgent()`
  - [x] 1.3 Verify `runSkillAgent()` still works: it calls `processStreamFromAsyncStream()` directly (line 102)
  - [x] 1.4 Remove `extractPurpose()` helper (line 324-326) — only used by `processStream`'s `StepSummary` creation, which was used by `runAgent()`. Check if `processStreamFromAsyncStream` also uses it
- [x] Task 2: Remove visual delta tracking from RunOrchestrator.execute() (AC: #3)
  - [x] 2.1 Remove `pendingScreenshotToolUseIds` state variable (line 100)
  - [x] 2.2 Remove `visualDeltaSkipped` and `visualDeltaChecked` counters (lines 102-103)
  - [x] 2.3 Remove `visualDeltaTracker` creation (line 108)
  - [x] 2.4 Remove visual delta screenshot tracking in `.toolUse` case — `pendingScreenshotToolUseIds.insert()` (lines 143)
  - [x] 2.5 Remove visual delta processing in `.toolResult` case — `extractBase64FromToolResult()` + `tracker.processScreenshot()` (lines 166-176)
  - [x] 2.6 Remove visual delta statistics output — `fputs("[axion] 视觉增量:...")` (lines 232-234)
- [x] Task 3: Remove seat monitoring from RunOrchestrator.execute() (AC: #4)
  - [x] 3.1 Remove `seatMonitor` state variable (line 111)
  - [x] 3.2 Remove `shouldMonitorSeat` computation (line 112)
  - [x] 3.3 Remove seat monitor lazy-init in `.toolUse` case (lines 137-139)
  - [x] 3.4 Remove `externallyModified` seat activity check (lines 217-220)
- [x] Task 4: Remove cost summary output from RunOrchestrator.execute() (AC: #5)
  - [x] 4.1 Remove cost breakdown extraction from `runCompleteBox` (lines 237-242) — CostEventHandler handles this
  - [x] 4.2 Note: keep `screenshotCount` tracking if TraceEventHandler or other handlers need it; remove if only used by cost output
- [x] Task 5: Remove memory processing from RunOrchestrator.execute() (AC: #6)
  - [x] 5.1 Remove `RunMemoryProcessor.preRunCleanup()` call (lines 86-88) — MemoryProcessingHandler handles post-run processing. Pre-run cleanup may need to stay if handler doesn't do it
  - [x] 5.2 Remove `RunMemoryProcessor.processRunResult()` call (lines 256-267)
  - [x] 5.3 Remove `takeoverEvent` construction (lines 247-255) if only used by memory processing. Check if it's also used in RunResult return value
- [x] Task 6: Remove desktop notification + activateTerminal from RunOrchestrator.execute() (AC: #7)
  - [x] 6.1 Remove notification block (lines 370-381) — `sendDesktopNotification()` + `activateTerminal()` calls
  - [x] 6.2 Verify `sendDesktopNotification()` and `activateTerminal()` static methods are kept (used by NotificationHandler default init and other callers)
- [x] Task 7: Update RunOrchestrator.execute() state variables (AC: #8)
  - [x] 7.1 Remove `externallyModified` from RunResult if it's now handled entirely by AxionRuntime via SeatMonitorHandler. Check: AxionRuntime stores `externallyModified` from handler, not from RunOrchestrator result
  - [x] 7.2 Remove `takeoverEvent` from RunResult if AxionRuntime captures it via handler instead
  - [x] 7.3 Clean up `resultText` variable if only used by notification
- [x] Task 8: Update tests (AC: #8)
  - [x] 8.1 Search `Tests/` for any reference to removed code and update
  - [x] 8.2 Run `swift test --filter "AxionCLITests"` to verify 0 failures
  - [x] 8.3 Run `swift build` to verify 0 compilation errors

## Dev Notes

### What to Keep in RunOrchestrator.execute()

After cleanup, RunOrchestrator.execute() should only handle:

| Concern | Lines | Why Keep |
|---------|-------|----------|
| Output handler creation | 50-54 | CLI rendering, not an EventHandler concern |
| TakeoverIO | 56-65 | Terminal interaction, not an EventHandler concern |
| Run lock | 70-81 | Desktop-level lock, not handled by handlers |
| SIGINT handler | 91-96 | Signal handling, not an EventHandler concern |
| Stream loop: step counting | 121 | Needed for RunResult |
| Stream loop: output rendering | 122 | CLI terminal output |
| Stream loop: message collection | 125-130 | Needed for review execution |
| Stream loop: launch_app activation | 144-145, 159-165 | Must run from CLI process, not AxionHelper |
| Stream loop: screenshot count | 142-143 | Used by cost tracking (if CostEventHandler needs it from result context) |
| Stream loop: skill usage tracking | 148-158 | Not an EventHandler concern |
| Stream loop: takeover handling | 177-205 | Terminal interaction |
| Stream loop: result text capture | 206-207 | Used by review |
| Agent cleanup | 226-229 | Resource management |
| Review + Curator execution | 269-361 | **NOT fully migrated to handlers** — ReviewHandler only logs, doesn't execute |
| Lock release | 363-366 | Desktop-level lock |
| Review summary output | 311-313 | `formatReviewSummary()` terminal output |

### What NOT to Remove (Review + Curator)

**Review code (lines 269-326):** ReviewHandler only logs "review scheduled" but does NOT execute the review. The full review execution (creating review agent, running it, tracking results) remains in RunOrchestrator.execute(). Do NOT remove this.

**Curator code (lines 328-361):** No handler equivalent exists. The curator execution (checking shouldRun, running IntelligentCurator, recording results) remains in RunOrchestrator.execute(). Do NOT remove this.

This is a conscious scope decision: only remove what's been FULLY migrated to EventHandlers. Review and Curator migration would require enhancing EventHandlerContext and making handlers capable of executing full review/curator pipelines, which is a separate story.

### Static Utility Methods (Keep All)

These static methods on RunOrchestrator are used by other files and must NOT be removed:

| Method | Callers |
|--------|---------|
| `parseSkillName()` | RunCommand.swift:82 |
| `generateRunId()` | RunExecuting.swift:17, AxionRuntime.swift:50 |
| `computeEffectiveMaxSteps()` | RunCommand.swift:101 |
| `computeEffectiveMaxTokens()` | RunCommand.swift:104 |
| `traceMode()` | RunCommand.swift |
| `buildProfileContent()` | RunMemoryProcessor.swift:146 |
| `sendDesktopNotification()` | NotificationHandler.swift:17 (default param) |
| `extractSkillName()` | ApiRunner.swift:220 |
| `executeSkillDirectly()` | RunCommand.swift:91 |
| `extractBase64FromToolResult()` | Shared utility |
| `extractBundleIdFromLaunchResult()` | Used in execute() stream loop |
| `activateAppFromCLI()` | Used in execute() stream loop |
| `activateTerminal()` | Shared utility |
| `extractSummary()` | Shared utility |
| `formatReviewSummary()` | Used in review execution |
| `formatCuratorSummary()` | Used in curator execution |
| `RunConfig` struct | AxionRuntime.swift:48, 70, 160 |
| `RunResult` struct | AxionRuntime.swift:90 |

### ApiRunner Dead Code Analysis

```
ApiRunner.swift:
  runAgent()          — DEAD (zero callers in Sources/)
  ├── processStream() — DEAD (only caller was runAgent())
  │   └── processStreamFromAsyncStream() — ALIVE (called by runSkillAgent() at line 102)
  └── extractPurpose() — Check if used by processStreamFromAsyncStream()
  runSkillAgent()     — ALIVE (called by AxionAPI.swift:283)
  inferResultKind()   — ALIVE (used in processStreamFromAsyncStream at line ~277)
```

**Important**: `processStreamFromAsyncStream()` contains SSE emit code (lines 231-260) that was retained in story 26.2 for the `runSkillAgent()` path. Do NOT touch this.

### Files to Modify

| File | Change |
|------|--------|
| `Sources/AxionCLI/API/ApiRunner.swift` | Remove `runAgent()`, `processStream()`, possibly `extractPurpose()` |
| `Sources/AxionCLI/Services/RunOrchestrator.swift` | Remove duplicated concerns from `execute()`: visual delta, seat monitoring, cost summary, memory processing, notification |

### Previous Story Learnings

- From Story 20 retro: **Dead code cleanup is never just deletion** — grep every symbol before removing. Live code may depend on types defined alongside dead code. Budget for extraction, not just deletion.
- From Story 20 retro: **Pre-deletion audit is the most valuable artifact** — verify each symbol has zero references before removing.
- From Story 26.1: Use `.serialized` suite trait for tests to prevent static state corruption.
- From Story 26.2: SSE emit code in `processStreamFromAsyncStream()` was retained for `runSkillAgent()` path — do NOT remove it.

### Testing Standards

- Use Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`)
- Run: `swift test --filter "AxionCLITests"` (unit tests only, not integration)
- Verify: `swift build` compiles cleanly
- Do NOT run integration tests (require real macOS app + AX permissions)

### References

- [Source: docs/epics/epic-26-cli-api-refactor.md#Story-26.3] — Epic definition
- [Source: Sources/AxionCLI/Services/RunOrchestrator.swift] — Main cleanup target (681 lines)
- [Source: Sources/AxionCLI/API/ApiRunner.swift] — Dead code removal (342 lines)
- [Source: Sources/AxionCLI/Runtime/Handlers/] — All 7 EventHandlers confirming migration status
- [Source: _bmad-output/implementation-artifacts/26-1-runcommand-axionruntime-execution.md] — Story 26.1 learnings
- [Source: _bmad-output/implementation-artifacts/26-2-apirunner-axionruntime-execution.md] — Story 26.2 learnings (dead code notes, deferred tasks)
- [Source: _bmad-output/implementation-artifacts/epic-20-retro-20260519.md] — Dead code cleanup lessons

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- Removed `ApiRunner.runAgent()` — verified zero callers in Sources/
- Removed `ApiRunner.processStream()` — only caller was `runAgent()`
- Kept `extractPurpose()` — still used by `processStreamFromAsyncStream()` at line 247
- Removed visual delta tracking from `RunOrchestrator.execute()`: `pendingScreenshotToolUseIds`, `visualDeltaSkipped`/`visualDeltaChecked` counters, `visualDeltaTracker`, `.toolResult` visual delta processing, stats output
- Removed seat monitoring from `RunOrchestrator.execute()`: `seatMonitor`, `shouldMonitorSeat`, lazy-init, post-stream activity check
- Removed cost summary output (fputs) from `RunOrchestrator.execute()` — CostEventHandler handles via EventBus
- Removed memory processing from `RunOrchestrator.execute()`: `preRunCleanup()` call, `processRunResult()` call, `memoryStore`/`memoryDir` locals
- Removed notification + activateTerminal block from `RunOrchestrator.execute()` — NotificationHandler handles via EventBus
- Cleaned up unused variables: `screenshotCount`, `resultText`, `config`, `runCompleted`, `memoryStore`, `memoryDir`
- `externallyModified` in RunResult changed to `let false` (always false now, AxionRuntime reads it from handler)
- `takeoverEvent` mapping kept in RunResult (AxionRuntime still consumes it)
- `RunConfig.noVisualDelta` field kept — it's a config field used by callers
- All static utility methods preserved: `sendDesktopNotification()`, `activateTerminal()`, `extractSummary()`, etc.
- No test changes needed — test references are to types (`SeatActivityMonitor`, `VisualDeltaTracker`) not removed code
- 1229 tests pass, 0 failures; `swift build` compiles cleanly

### File List

- `Sources/AxionCLI/API/ApiRunner.swift` — Removed `runAgent()`, `processStream()` dead code
- `Sources/AxionCLI/Services/RunOrchestrator.swift` — Removed visual delta, seat monitoring, cost output, memory processing, notification from `execute()`
- `Sources/AxionCLI/Services/EventHandlerContext.swift` — Added `ExternallyModifiedFlag` class and `externallyModifiedFlag` field for handler→runtime state propagation
- `Sources/AxionCLI/Services/AxionRuntime.swift` — Uses `ExternallyModifiedFlag` to sync SeatMonitorHandler detections; resets flag per run
- `Sources/AxionCLI/Runtime/Handlers/SeatMonitorHandler.swift` — Sets `externallyModifiedFlag` on external activity detection
- `Tests/AxionCLITests/Services/*.swift` — Updated EventHandlerContext constructor calls with new `externallyModifiedFlag` param

### Change Log

- 2026-05-27: Story 26.3 implementation complete — removed dead ApiRunner code and duplicated concerns from RunOrchestrator.execute() (all 8 tasks, AC#1-AC#9 satisfied)
- 2026-05-27: **Senior Developer Review (AI)** — Found 2 HIGH + 2 MEDIUM + 1 LOW issues. Auto-fixed all: (1) `externallyModified` was always false — added `ExternallyModifiedFlag` for SeatMonitorHandler→MemoryProcessingHandler propagation via AxionRuntime, (2) restored `preRunCleanup()` call (fact demotion was lost), (3) updated stale doc comment. 1229 tests pass.
