# Story 19.3: API 路径对齐

Status: done

## Story

As a API 用户,
I want HTTP API 的 skill 和普通任务执行与 CLI 使用相同的代码路径,
So that CLI 和 API 的行为一致, 不会出现"CLI 能用但 API 不行"的问题.

## Acceptance Criteria

1. **Given** HTTP API 的 `/v1/runs` 端点收到任务请求,
   **When** ApiRunner 执行任务,
   **Then** 使用与 RunCommand 相同的共享构建函数 (`AgentBuilder.build()`),
   **And** 传入 skillRegistry、tools、mcpServers,
   **And** SSE 事件和 CostTracking 仍然正常工作.

2. **Given** HTTP API 的 skill 触发端点,
   **When** 执行 skill 任务,
   **Then** 使用与 CLI `/skill-name` 相同的预解析 + user message 模式,
   **And** skill 的工具限制由 SDK 的 ToolRestrictionStack 强制执行.

3. **Given** `AgentRunner` 类型和文件名存在,
   **When** 本 story 完成,
   **Then** 文件重命名为 `ApiRunner.swift`,
   **And** 枚举类型重命名为 `ApiRunner`,
   **And** 所有引用更新（AxionAPI、测试、AgentBuilder 注释、MCPServerRunner 注释）,
   **And** `swift build` 编译通过.

4. **Given** `runAgent()` 和 `runSkillAgent()` 中的流处理循环（~120 行）,
   **When** 本 story 完成,
   **Then** 共享流处理逻辑提取为内部函数,
   **And** 两个入口函数只负责参数准备和调用共享流处理器,
   **And** Agent 构建逻辑重复率 < 10%（NFR47）.

5. **Given** 重构后的代码,
   **When** `swift build` 和 `swift test --filter "AxionCLITests" --filter "AxionCoreTests"` 运行,
   **Then** 全部编译通过并测试通过.

## Tasks / Subtasks

- [x] Task 1: Rename AgentRunner → ApiRunner (AC: #3)
  - [x] Rename file: `Sources/AxionCLI/API/AgentRunner.swift` → `Sources/AxionCLI/API/ApiRunner.swift`
  - [x] Rename enum: `AgentRunner` → `ApiRunner`
  - [x] Update all references in `AxionAPI.swift` (6 call sites: 3×runAgent, 3×runSkillAgent)
  - [x] Update references in `APITypesTests.swift` (14×inferResultKind calls)
  - [x] Update comments in `AgentBuilder.swift` (2 references in doc comments)
  - [x] Update comment in `MCPServerRunner.swift` (1 reference)
  - [x] Verify `swift build` compiles after rename

- [x] Task 2: Extract shared stream processing (AC: #4)
  - [x] Identify the duplicated stream processing logic in `runAgent()` (lines 89-176) and `runSkillAgent()` (lines 261-333) — both have identical: message loop, SSE step_started/step_completed events, costTracker recording, pendingToolUses tracking, stepSummaries collection, resultSubtype handling, runTracker persistence
  - [x] Create a private internal function (e.g., `processStream()`) that encapsulates: the `for await message in messageStream` loop, SSE broadcasting, cost tracking, step summaries, RunTracker result persistence, duration calculation
  - [x] `runAgent()` keeps only: AgentBuilder.BuildConfig.forAPI() setup, seat monitor creation, tracer setup, then calls shared stream processor
  - [x] `runSkillAgent()` keeps only: pre-resolution via `resolveExplicitSlashSkillRequest()`, BuildConfig.forCLI() setup, then calls shared stream processor
  - [x] Return type of shared processor: (totalSteps, durationMs, replanCount, finalStatus, stepSummaries, costTelemetry, externallyModified)

- [x] Task 3: Verify API path alignment (AC: #1, #2)
  - [x] Confirm `runAgent()` passes `skillRegistry` to AgentBuilder (inherited from 19.1's `BuildConfig.forAPI()` — check it's not an empty registry)
  - [x] Confirm `runSkillAgent()` uses pre-resolution pattern (inherited from 19.2)
  - [x] Confirm SSE events still fire correctly (step_started, step_completed)
  - [x] Confirm CostTracker and RunTracker logic preserved

- [x] Task 4: Update tests (AC: #5)
  - [x] Update `APITypesTests.swift`: `AgentRunner.inferResultKind` → `ApiRunner.inferResultKind`
  - [x] Verify all tests pass: `swift test --filter "AxionCLITests" --filter "AxionCoreTests"`
  - [x] No new tests needed — existing tests cover inferResultKind, and integration tests cover SSE/CostTracker

## Dev Notes

### Architecture Context

This is the third and final story in Epic 19 (SDK alignment refactor). Stories 19.1 and 19.2 already did the heavy lifting:

- **19.1** created the shared `AgentBuilder`, unified CLI/API agent construction, fixed skillRegistry and tools bugs
- **19.2** aligned skill handling to SwiftWork's pre-resolution pattern, removed skill.promptTemplate system prompt injection

This story completes the alignment by:
1. Renaming `AgentRunner` → `ApiRunner` (eliminates semantic conflict with SDK's `Agent` class)
2. Extracting duplicated stream processing into a shared internal function
3. Verifying end-to-end API path alignment

### Current State After 19.1 + 19.2

**`AgentRunner.runAgent()`** (lines 41-199):
- Uses `AgentBuilder.BuildConfig.forAPI()` + `AgentBuilder.build()` ✓
- Has SSE broadcasting (step_started/step_completed) ✓
- Has CostTracker (model calls + screenshots) ✓
- Has RunTracker (ApiTaskResult persistence) ✓
- Has SeatActivityMonitor (shared seat mode) ✓
- Has TraceRecorder ✓

**`AgentRunner.runSkillAgent()`** (lines 205-354):
- Uses `AgentBuilder.resolveExplicitSlashSkillRequest()` + `BuildConfig.forCLI()` ✓
- Has SSE broadcasting (step_started/step_completed) ✓
- Has CostTracker ✓
- Has RunTracker ✓
- Does NOT have SeatActivityMonitor (acceptable — skill tasks are shorter)
- Does NOT have TraceRecorder (acceptable)

**Shared stream loop** (duplicated ~120 lines between both):
```
for await message in messageStream {
    switch message {
    case .assistant: costTracker.recordModelCall
    case .toolUse: totalSteps++, pendingToolUses, SSE step_started
    case .toolResult: stepSummaries, SSE step_completed
    case .result: resultSubtype, costTracker.finalizeWithSDKData, runTracker.updateRunResult
    }
}
duration calculation
agent.close()
finalStatus mapping
```

### What to Extract

Create a private struct or function that handles the stream loop:

```swift
private static func processStream(
    agent: Agent,
    task: String,
    resolvedTask: String,  // for runTracker title
    model: String,
    runId: String,
    eventBroadcaster: EventBroadcaster?,
    runTracker: RunTracker?,
    costTracker: CostTracker,
    seatMonitor: SeatActivityMonitor?,
    tracer: TraceRecorder?
) async -> StreamResult
```

Where `StreamResult` contains: totalSteps, durationMs, stepSummaries, costTelemetry, externallyModified, resultSubtype.

**Callers then become thin:**

`runAgent()`: BuildConfig.forAPI → AgentBuilder.build → create SeatMonitor, CostTracker, Tracer → processStream → return

`runSkillAgent()`: resolveExplicitSlashSkillRequest → BuildConfig.forCLI → AgentBuilder.build → create CostTracker → processStream → return

### Files Being Modified

| File | Action | Notes |
|------|--------|-------|
| `Sources/AxionCLI/API/AgentRunner.swift` | RENAME + UPDATE | Rename to ApiRunner.swift, extract shared stream processing |
| `Sources/AxionCLI/API/AxionAPI.swift` | UPDATE | 6× `AgentRunner` → `ApiRunner` references |
| `Tests/AxionCLITests/API/APITypesTests.swift` | UPDATE | 14× `AgentRunner.inferResultKind` → `ApiRunner.inferResultKind` |
| `Sources/AxionCLI/Services/AgentBuilder.swift` | UPDATE | Comments: `AgentRunner` → `ApiRunner` |
| `Sources/AxionCLI/MCP/MCPServerRunner.swift` | UPDATE | Comment: `AgentRunner` → `ApiRunner` |

### What NOT to Change

- Do NOT change `RunCommand` — already aligned via 19.1/19.2
- Do NOT change `AgentBuilder.build()` — already correct
- Do NOT change `SkillAPIRunner` — recorded skills, out of scope for Epic 19
- Do NOT change `SkillLookupService`, `RecordedSkillRunner`, `SkillExecutor` — not related
- Do NOT delete `runSkillAgent()` — keep it as a separate entry point (different BuildConfig params)
- Do NOT touch dead code in Engine/Executor/Planner/Verifier/Output/ — that's Epic 20

### BuildConfig.forAPI() Gap: Empty SkillRegistry

Note: `BuildConfig.forAPI()` currently creates an empty `SkillRegistry()` — this means API path has no skills registered. This is intentional for `runAgent()` (normal tasks don't need skills), but `runSkillAgent()` correctly uses `BuildConfig.forCLI()` which gets the real registry. No change needed, but be aware.

### Naming Convention

`ApiRunner` follows the project convention:
- File: `ApiRunner.swift` in `Sources/AxionCLI/API/`
- Type: `enum ApiRunner` (same pattern as current `enum AgentRunner`)
- Matches the "重构后职责划分" table in `phase6-refactor-architecture.md` which uses "ApiRunner"

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 19.3 — acceptance criteria + refactoring plan]
- [Source: _bmad-output/planning-artifacts/phase6-refactor-architecture.md — "重构后" architecture diagram + responsibility table]
- [Source: _bmad-output/implementation-artifacts/19-1-unified-agent-execution-entry.md — 19.1 dev notes + learnings]
- [Source: _bmad-output/implementation-artifacts/19-2-skill-swiftwork-alignment.md — 19.2 dev notes + learnings]
- [Source: Sources/AxionCLI/API/AgentRunner.swift — current implementation to rename + refactor]
- [Source: Sources/AxionCLI/API/AxionAPI.swift:313-727 — 6 call sites to update]
- [Source: Tests/AxionCLITests/API/APITypesTests.swift:568-591 — 14 test assertions to update]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

No issues encountered.

### Completion Notes List

- Renamed `AgentRunner` → `ApiRunner` (file + enum + all 6 call sites in AxionAPI.swift + 14 test assertions + 2 doc comments in AgentBuilder.swift + 1 comment in MCPServerRunner.swift)
- Extracted duplicated stream processing (~120 lines) into `processStream()` private static function with `StreamResult` struct
- `runAgent()` now thin: BuildConfig.forAPI → AgentBuilder.build → create CostTracker/SeatMonitor/Tracer → processStream → return
- `runSkillAgent()` now thin: resolveExplicitSlashSkillRequest → BuildConfig.forAPISkill → AgentBuilder.build → create CostTracker → processStream → return
- SSE events, CostTracker, RunTracker, seat monitoring all preserved in shared processor
- Agent build logic duplication eliminated (NFR47 satisfied — both paths use AgentBuilder.build())
- `swift build` compiles, all 1605 tests pass

### File List

- `Sources/AxionCLI/API/AgentRunner.swift` → **RENAMED** to `Sources/AxionCLI/API/ApiRunner.swift` — renamed enum, extracted `processStream()` shared function
- `Sources/AxionCLI/API/AxionAPI.swift` — updated 6 `AgentRunner` → `ApiRunner` references
- `Tests/AxionCLITests/API/APITypesTests.swift` — updated 14 `AgentRunner.inferResultKind` → `ApiRunner.inferResultKind` references
- `Sources/AxionCLI/Services/AgentBuilder.swift` — updated 2 doc comment references
- `Sources/AxionCLI/MCP/MCPServerRunner.swift` — updated 1 comment reference + fixed safety hook MCP prefix bug
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — status updated to in-progress

## Senior Developer Review (AI)

**Reviewer:** Nick on 2026-05-19
**Outcome:** Approved (all fixes applied)

### Findings (5 total: 1 HIGH, 2 MEDIUM, 2 LOW)

**HIGH-1: MCPServerRunner safety hook missing MCP prefix** (FIXED)
- `MCPServerRunner.buildSafetyHookRegistry()` used bare `ToolNames.foregroundToolNames` without MCP prefix
- SDK passes MCP-prefixed tool names through hooks (e.g., `mcp__axion-helper__click`)
- Safety hook comparison would never match, making shared-seat-mode foreground tool blocking completely broken
- Fix: Added `.map { "mcp__axion-helper__\($0)" }` to match AgentBuilder.swift:422 pattern

**MED-1: Completion Notes claimed `BuildConfig.forCLI()` but code uses `BuildConfig.forAPISkill()`** (FIXED)
- Story documentation said `forCLI()` but implementation correctly uses `forAPISkill()` (no Playwright for API)
- Fix: Updated Completion Notes to match actual implementation

**MED-2: `inferResultKind(task:output:)` accepted unused `output` parameter** (FIXED)
- Function signature had `output: String` parameter that was never read
- Fix: Removed unused parameter, updated all callers in processStream() and APITypesTests.swift

**LOW-1: `extractPurpose()` returns only toolName** (NOTED — placeholder, not blocking)
**LOW-2: Dual callback+return pattern** (NOTED — pre-existing design, not from this story)

### Verification
- `swift build` compiles ✓
- 1311 tests pass (AxionCLITests + AxionCoreTests) ✓
- No remaining `AgentRunner` references in source ✓
- All 5 ACs validated against implementation ✓

### Change Log
- 2026-05-19: Review by Nick — 3 fixes applied (safety hook prefix, unused param, doc accuracy). Status → done.
