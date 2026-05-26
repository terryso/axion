# Story 28.1: AgentEvent → SSE Event Mapping

Status: review

## Story

As a SDK developer,
I want to convert AgentEvent to SSE event format,
So that EventBus events can be transparently forwarded to HTTP SSE clients.

## Acceptance Criteria

1. **AC1: ToolStartedEvent maps to step_started**
   - Given `ToolStartedEvent(toolName: "bash", toolUseId: "xxx")`
   - When converted via mapping function
   - Then result is `AgentSSEEvent.stepStarted(StepStartedData(stepIndex: N, tool: "bash"))`

2. **AC2: AgentStartedEvent maps to run_started**
   - Given `AgentStartedEvent(sessionId: "s1", task: "do work")`
   - When converted via mapping function
   - Then result is `AgentSSEEvent.runStarted(RunStartedData(runId: "s1", task: "do work"))`

3. **AC3: LLMCostEvent maps to cost_update**
   - Given `LLMCostEvent(sessionId: "s1", model: "claude-sonnet-4-6", inputTokens: 100, outputTokens: 50, ..., estimatedCostUsd: 0.003)`
   - When converted via mapping function
   - Then result is `AgentSSEEvent.costUpdate(CostUpdateData(...))` containing all token and cost fields

4. **AC4: AgentCompletedEvent maps to run_completed**
   - Given `AgentCompletedEvent(sessionId: "s1", totalSteps: 5, durationMs: 3200)`
   - When converted via mapping function
   - Then result is `AgentSSEEvent.runCompleted(RunCompletedData(runId: "s1", finalStatus: "completed", totalSteps: 5, durationMs: 3200))`

5. **AC5: ToolCompletedEvent maps to step_completed**
   - Given `ToolCompletedEvent(toolName: "bash", durationMs: 150, isError: false)`
   - When converted via mapping function
   - Then result is `AgentSSEEvent.stepCompleted(StepCompletedData(stepIndex: N, tool: "bash", success: true, durationMs: 150))`

6. **AC6: Unmapped event types return nil**
   - Given `SessionCreatedEvent` or `ToolStreamingEvent` or any event not in the mapping table
   - When converted via mapping function
   - Then result is `nil`

7. **AC7: New SSE event types are Codable, Equatable, Sendable**
   - Given `RunStartedData` and `CostUpdateData`
   - Then they conform to `Codable`, `Equatable`, `Sendable` (same as existing SSE data types)

8. **AC8: Existing tests all pass**
   - Given no EventBus injection
   - When running all existing tests
   - Then all pass with no regressions

## Tasks / Subtasks

- [x] Task 1: Add RunStartedData and CostUpdateData structs to APITypes.swift (AC: #7)
  - [x] 1.1 Add `RunStartedData` struct (Codable, Equatable, Sendable) with fields: `runId: String`, `task: String`
  - [x] 1.2 Add `CostUpdateData` struct (Codable, Equatable, Sendable) with fields: `model: String`, `inputTokens: Int`, `outputTokens: Int`, `cacheCreationInputTokens: Int?`, `cacheReadInputTokens: Int?`, `estimatedCostUsd: Double`
  - [x] 1.3 Follow existing CodingKeys snake_case pattern (e.g. `run_id`, `input_tokens`, `estimated_cost_usd`)

- [x] Task 2: Extend AgentSSEEvent enum with new cases (AC: #7)
  - [x] 2.1 Add `.runStarted(RunStartedData)` case
  - [x] 2.2 Add `.costUpdate(CostUpdateData)` case
  - [x] 2.3 Update `eventType` computed property: `.runStarted → "run_started"`, `.costUpdate → "cost_update"`
  - [x] 2.4 Update `encodeToSSE(sequenceId:)` to handle new cases

- [x] Task 3: Update PersistedSSEEvent for new cases (AC: #7)
  - [x] 3.1 Add `runStarted: RunStartedData?` and `costUpdate: CostUpdateData?` optional fields
  - [x] 3.2 Update `init(from event:)` switch for new cases
  - [x] 3.3 Update `toSSEEvent()` switch for `"run_started"` and `"cost_update"` string matching

- [x] Task 4: Create AgentEventSSEMapping.swift (AC: #1-#6)
  - [x] 4.1 Create `Sources/OpenAgentSDK/Utils/AgentEventSSEMapping.swift`
  - [x] 4.2 Define `public enum AgentEventSSEMapping` (stateless, like `TraceEventMapping`)
  - [x] 4.3 Implement `public static func map(_ event: any AgentEvent, stepIndex: Int = 0) -> AgentSSEEvent?`
  - [x] 4.4 Mapping: `AgentStartedEvent` → `.runStarted(RunStartedData(runId: sessionId ?? "", task: task))`
  - [x] 4.5 Mapping: `ToolStartedEvent` → `.stepStarted(StepStartedData(stepIndex: stepIndex, tool: toolName))`
  - [x] 4.6 Mapping: `ToolCompletedEvent` → `.stepCompleted(StepCompletedData(stepIndex: stepIndex, tool: toolName, success: !isError, durationMs: durationMs))`
  - [x] 4.7 Mapping: `AgentCompletedEvent` → `.runCompleted(RunCompletedData(runId: sessionId ?? "", finalStatus: "completed", totalSteps: totalSteps, durationMs: durationMs))`
  - [x] 4.8 Mapping: `LLMCostEvent` → `.costUpdate(CostUpdateData(model: model, inputTokens: inputTokens, outputTokens: outputTokens, cacheCreationInputTokens: cacheCreationInputTokens, cacheReadInputTokens: cacheReadInputTokens, estimatedCostUsd: estimatedCostUsd))`
  - [x] 4.9 All other event types → `nil`

- [x] Task 5: Write unit tests (AC: #1-#6)
  - [x] 5.1 Create `Tests/OpenAgentSDKTests/Utils/AgentEventSSEMappingTests.swift`
  - [x] 5.2 Test AC1: ToolStartedEvent → stepStarted (verify tool name extracted correctly)
  - [x] 5.3 Test AC2: AgentStartedEvent → runStarted (verify runId from sessionId, task preserved)
  - [x] 5.4 Test AC3: LLMCostEvent → costUpdate (verify all token/cost fields mapped)
  - [x] 5.5 Test AC4: AgentCompletedEvent → runCompleted (verify totalSteps, durationMs, finalStatus)
  - [x] 5.6 Test AC5: ToolCompletedEvent → stepCompleted (verify success=!isError, durationMs)
  - [x] 5.7 Test AC6: SessionCreatedEvent/ToolStreamingEvent/SessionClosedEvent → nil
  - [x] 5.8 Test stepIndex parameter is correctly passed through for tool events

- [x] Task 6: Verify build and regression tests (AC: #8)
  - [x] 6.1 `swift build` confirms compilation
  - [x] 6.2 `swift test` confirms all existing tests pass

## Dev Notes

### Architecture Context

This story creates a **pure mapping function** (no state, no side effects) that converts `AgentEvent` instances to `AgentSSEEvent` instances. It follows the same pattern as `TraceEventMapping` (`Sources/OpenAgentSDK/Utils/TraceEventMapping.swift`) — a stateless `enum` with a static function.

This mapping is the foundation for Story 28.2 (EventBus → EventBroadcaster bridge), which will subscribe to EventBus, call this mapping function for each event, and forward non-nil results to EventBroadcaster.

### Mapping Table

| AgentEvent | AgentSSEEvent | Notes |
|---|---|---|
| `AgentStartedEvent` | `.runStarted(RunStartedData)` | **NEW SSE type** — runId from sessionId, task preserved |
| `ToolStartedEvent` | `.stepStarted(StepStartedData)` | stepIndex from parameter, tool from toolName |
| `ToolCompletedEvent` | `.stepCompleted(StepCompletedData)` | success = !isError |
| `AgentCompletedEvent` | `.runCompleted(RunCompletedData)` | Existing SSE type — runId from sessionId |
| `LLMCostEvent` | `.costUpdate(CostUpdateData)` | **NEW SSE type** — all token/cost fields |
| All others | `nil` | Not mapped in this story |

### stepIndex Parameter

ToolStartedEvent and ToolCompletedEvent do not carry a `stepIndex` field. The mapping function accepts `stepIndex: Int = 0` as a parameter, matching the `TraceEventMapping.traceEvent(from:stepIndex:)` pattern. The caller (Story 28.2's bridge) will maintain a counter.

### New SSE Data Types

**RunStartedData** — mirrors AgentStartedEvent payload:
```swift
public struct RunStartedData: Codable, Equatable, Sendable {
    public let runId: String     // from AgentStartedEvent.sessionId
    public let task: String      // from AgentStartedEvent.task
}
```

**CostUpdateData** — mirrors LLMCostEvent payload:
```swift
public struct CostUpdateData: Codable, Equatable, Sendable {
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationInputTokens: Int?
    public let cacheReadInputTokens: Int?
    public let estimatedCostUsd: Double
}
```

### Files to Modify/Create

- **UPDATE**: `Sources/OpenAgentSDK/HTTP/APITypes.swift` — Add RunStartedData, CostUpdateData structs; extend AgentSSEEvent enum with `.runStarted` and `.costUpdate` cases; update `eventType`, `encodeToSSE`, and `PersistedSSEEvent`
- **CREATE**: `Sources/OpenAgentSDK/Utils/AgentEventSSEMapping.swift` — Pure mapping function
- **CREATE**: `Tests/OpenAgentSDKTests/Utils/AgentEventSSEMappingTests.swift` — Unit tests

### Key Design Decisions

1. **Stateless enum** (like TraceEventMapping) — no actor, no stored properties
2. **stepIndex as parameter** — not tracked internally, caller provides it
3. **sessionId → runId mapping** — SSE uses `run_id` naming, AgentEvent uses `session_id`. They represent the same concept. The mapping converts the naming.
4. **Nil for unmapped events** — explicit design choice: not every AgentEvent needs SSE representation. Session events, memory events, sub-agent events don't map to SSE (they're not HTTP API concerns).

### Future Mappings (NOT in this story)

These AgentEvents may be mapped in future stories but return `nil` for now:
- `AgentFailedEvent` → could map to `.runCompleted` with `finalStatus: "failed"`
- `AgentInterruptedEvent` → could map to `.runCompleted` with `finalStatus: "interrupted"`
- `SessionCreatedEvent`, `SessionClosedEvent`, `SessionAutoSavedEvent` → not HTTP SSE concerns
- `ToolStreamingEvent` → too high-frequency for SSE

### Testing Strategy

**Unit tests** (`Tests/OpenAgentSDKTests/Utils/AgentEventSSEMappingTests.swift`):
- Pure function tests — no mocks needed, just construct events and verify output
- Test each mapped event type
- Test nil return for unmapped types
- Test edge cases: nil sessionId, optional fields

### Scope Boundaries

**This story ONLY does:**
- Define the mapping function (AgentEvent → AgentSSEEvent?)
- Add new SSE data types and enum cases
- Unit tests

**NOT in this story (future):**
- Subscribing EventBus to forward events (Story 28.2)
- Removing manual SSE emit code from ApiRunner (Story 28.2)
- Token streaming (Story 28.3)

### Previous Story Intelligence (Epic 27)

Epic 27 established the EventBus publish pattern in Agent.swift:
- `EventBus` is a `public actor` with `publish(_ event: any AgentEvent)` and `subscribe()` methods
- Events use `BaseAgentEvent` composition for id/timestamp
- EventBus is injected via `AgentOptions.eventBus: EventBus?`
- All 5955 tests pass

Story 28.1 does NOT touch Agent.swift — it creates a standalone mapping utility.

### Project Structure Notes

- New file goes in `Utils/` (flat directory, no subdirectories)
- SSE types live in `HTTP/APITypes.swift` — the mapping connects Utils to HTTP
- Test mirrors source structure: `Tests/OpenAgentSDKTests/Utils/`
- No E2E tests needed for this story (pure function, no external dependencies)

### References

- [Source: docs/epics/epic-28-eventbus-sse-bridge.md#Story 28.1]
- [Source: Sources/OpenAgentSDK/HTTP/APITypes.swift:215 — AgentSSEEvent enum]
- [Source: Sources/OpenAgentSDK/HTTP/APITypes.swift:249 — PersistedSSEEvent]
- [Source: Sources/OpenAgentSDK/Utils/TraceEventMapping.swift — pattern reference for stateless mapping enum]
- [Source: Sources/OpenAgentSDK/Types/AgentEventTypes.swift — all AgentEvent types]
- [Source: Sources/OpenAgentSDK/Core/EventBus.swift — EventBus actor]
- [Source: docs/runtime-event-layer-roadmap.md#S4 — SSE bridge design]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- Implemented RunStartedData and CostUpdateData structs with Codable/Equatable/Sendable conformance and snake_case CodingKeys
- Extended AgentSSEEvent enum with .runStarted and .costUpdate cases, updated eventType and encodeToSSE
- Updated PersistedSSEEvent with new optional fields and switch cases for init/toSSEEvent
- Created AgentEventSSEMapping as stateless enum with static map function (following TraceEventMapping pattern)
- 17 unit tests covering all 8 ACs: mapped events, nil returns for unmapped, stepIndex pass-through, nil sessionId edge cases
- All 5971 tests pass (0 failures, 42 skipped)

### File List

- Sources/OpenAgentSDK/HTTP/APITypes.swift — Added RunStartedData, CostUpdateData structs; extended AgentSSEEvent with .runStarted/.costUpdate; updated PersistedSSEEvent
- Sources/OpenAgentSDK/Utils/AgentEventSSEMapping.swift — NEW: stateless mapping enum (AgentEvent → AgentSSEEvent?)
- Tests/OpenAgentSDKTests/Utils/AgentEventSSEMappingTests.swift — NEW: 17 unit tests for mapping function
- Tests/OpenAgentSDKTests/HTTP/APITypesTests.swift — Added CodingKeys, SSE encoding, PersistedSSEEvent round-trip tests for RunStartedData and CostUpdateData

## Change Log

- 2026-05-26: Story 28.1 implemented — AgentEvent → SSE event mapping with 2 new SSE data types (RunStartedData, CostUpdateData), 5 event mappings, and 17 unit tests. All 5971 tests pass.
- 2026-05-26: Review fix — Added 10 tests to APITypesTests.swift (CodingKeys, SSE encoding, PersistedSSEEvent round-trip for new types), 1 nil sessionId edge case test for AgentCompletedEvent.
