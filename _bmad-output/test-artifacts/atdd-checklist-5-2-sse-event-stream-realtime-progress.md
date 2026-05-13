---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: 'step-05-validate-and-complete'
lastSaved: '2026-05-13'
storyId: '5.2'
storyKey: '5-2-sse-event-stream-realtime-progress'
storyFile: '_bmad-output/implementation-artifacts/5-2-sse-event-stream-realtime-progress.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-5-2-sse-event-stream-realtime-progress.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/API/SSEEventTests.swift'
  - 'Tests/AxionCLITests/API/EventBroadcasterTests.swift'
  - 'Tests/AxionCLITests/API/RunTrackerTests.swift'
  - 'Tests/AxionCLITests/API/AxionAPIRoutesTests.swift'
---

# ATDD Checklist: Story 5.2 — SSE 事件流实时进度

## TDD Red Phase (Current)

Red-phase test scaffolds generated.

- Unit Tests (SSEEvent models): 14 tests
- Unit Tests (EventBroadcaster actor): 12 tests
- Integration Tests (RunTracker + EventBroadcaster): 3 tests
- API Tests (SSE endpoint via HummingbirdTesting): 4 tests
- **Total: 33 tests**

## Acceptance Criteria Coverage

| AC | 描述 | 测试覆盖 | 测试文件 |
|----|------|---------|---------|
| AC1 | SSE 连接与实时事件推送 | SSE endpoint content-type, headers, event format | SSEEventTests, AxionAPIRoutesTests |
| AC2 | step_completed 事件数据 | StepCompletedData Codable round-trip, snake_case, encodeToSSE | SSEEventTests |
| AC3 | run_completed 事件数据 | RunCompletedData Codable round-trip, snake_case, encodeToSSE | SSEEventTests |
| AC4 | 已完成任务的重放 | replayBuffer, late subscriber replay, completed run SSE response | EventBroadcasterTests, AxionAPIRoutesTests |
| AC5 | 多客户端并发订阅 | multiple subscribers, event isolation per runId | EventBroadcasterTests |

## Test Files Created

| File | Tests | Priority | Type |
|------|-------|----------|------|
| `Tests/AxionCLITests/API/SSEEventTests.swift` | 14 | P0 | Unit (models + SSE encoding) |
| `Tests/AxionCLITests/API/EventBroadcasterTests.swift` | 12 | P0 | Unit (actor behavior) |
| `Tests/AxionCLITests/API/RunTrackerTests.swift` | 3 (new) + 13 (existing) | P0/P1 | Integration |
| `Tests/AxionCLITests/API/AxionAPIRoutesTests.swift` | 4 (new) + 9 (existing) | P0/P1 | API endpoint |

## Test Strategy

- **Stack**: Backend (Swift SPM, no frontend)
- **Generation mode**: AI generation (backend = no browser recording)
- **Test levels**:
  - Unit: SSEEvent models, EventBroadcaster actor, Codable conformance
  - Integration: RunTracker + EventBroadcaster dependency injection
  - API: SSE endpoint via HummingbirdTesting framework
- **No E2E tests** (backend-only project, no browser UI)

## Priority Breakdown

| Priority | Count | Description |
|----------|-------|-------------|
| P0 | 25 | Core model round-trips, actor behavior, endpoint happy paths |
| P1 | 8 | Optional fields, edge cases, backward compatibility |

## Implementation Tasks (Green Phase)

1. Create `StepStartedData`, `StepCompletedData`, `RunCompletedData` structs in `APITypes.swift`
2. Create `SSEEvent` enum with `encodeToSSE()` method in `APITypes.swift`
3. Create `EventBroadcaster` actor in `Sources/AxionCLI/API/EventBroadcaster.swift`
4. Modify `RunTracker` to accept `EventBroadcaster` in constructor
5. Modify `AgentRunner.runAgent()` to emit step events
6. Add `GET /v1/runs/:runId/events` SSE endpoint to `AxionAPI.swift`
7. Modify `ServerCommand` to wire up `EventBroadcaster` dependency chain
8. Update `AxionAPI.registerRoutes()` signature to accept `eventBroadcaster`

## Execution Commands

```bash
# Run all unit tests (excluding integration)
swift test --filter "AxionCLITests.API"

# Run specific test file
swift test --filter "SSEEventTests"
swift test --filter "EventBroadcasterTests"

# Run all Story 5.2 related tests
swift test --filter "SSEEventTests" --filter "EventBroadcasterTests"
```

## Key Assumptions

1. `EventBroadcaster` is an actor for thread-safe subscriber management
2. `subscribeWithReplay()` method delivers cached events to late subscribers (AC4)
3. `getReplayBuffer()` is a test-only accessor for verifying internal state
4. `RunTracker` constructor gains optional `eventBroadcaster` parameter (backward compatible)
5. `AxionAPI.registerRoutes()` gains `eventBroadcaster` parameter
6. SSE endpoint uses Hummingbird's `ResponseBody(asyncSequence:)` for streaming
7. Tests reference `SSEEvent` enum with associated values pattern (not raw values)
8. All SSE data types use snake_case CodingKeys per project convention

## Next Steps

1. Implement Story 5.2 following the dev-story workflow
2. Run tests to confirm RED phase (all new tests fail as expected)
3. Implement feature incrementally, activating test groups as each task completes
4. Verify GREEN phase: all tests pass after implementation
5. Run full unit test suite: `swift test --filter "AxionCLITests.API"`
