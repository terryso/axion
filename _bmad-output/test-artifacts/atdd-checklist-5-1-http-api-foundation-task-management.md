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
storyId: '5.1'
storyKey: '5-1-http-api-foundation-task-management'
storyFile: '_bmad-output/implementation-artifacts/5-1-http-api-foundation-task-management.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-5-1-http-api-foundation-task-management.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/API/APITypesTests.swift'
  - 'Tests/AxionCLITests/API/RunTrackerTests.swift'
  - 'Tests/AxionCLITests/API/AxionAPIRoutesTests.swift'
  - 'Tests/AxionCLITests/Commands/ServerCommandTests.swift'
---

# ATDD Checklist: Story 5.1 — HTTP API 基础与任务管理

## TDD Red Phase (Current)

Red-phase test scaffolds generated. All tests will fail until implementation exists.

- **Unit Tests (API Types):** 21 tests (Codable round-trip, JSON keys, enum raw values)
- **Unit Tests (RunTracker):** 12 tests (submit/get/update/list, SSE callback)
- **Integration Tests (API Routes):** 10 tests (Hummingbird HTTP route testing)
- **Unit Tests (ServerCommand):** 8 tests (ArgumentParser parameter parsing)
- **Total: 51 tests**

## Acceptance Criteria Coverage

| AC | Description | Test Level | Test File(s) | Tests |
|----|------------|------------|-------------|-------|
| AC1 | Server 启动与端口监听 | Unit + Integration | ServerCommandTests, AxionAPIRoutesTests | 8 + 1 |
| AC2 | 提交异步任务 | Unit + Integration | APITypesTests, RunTrackerTests, AxionAPIRoutesTests | 8 + 4 + 2 |
| AC3 | 查询运行中任务状态 | Unit + Integration | RunTrackerTests, AxionAPIRoutesTests | 3 + 1 |
| AC4 | 查询已完成任务结果 | Unit + Integration | APITypesTests, RunTrackerTests, AxionAPIRoutesTests | 2 + 2 + 1 |
| AC5 | 请求参数校验 | Integration | AxionAPIRoutesTests | 2 |
| AC6 | Health check 端点 | Integration | APITypesTests, AxionAPIRoutesTests | 2 + 2 |
| SSE Prep | RunTracker callback | Unit | RunTrackerTests | 1 |

## Test Strategy

**Detected Stack:** Backend (Swift / SPM / XCTest)

**Test Levels:**
- **Unit** — Codable round-trip, RunTracker actor logic, ServerCommand parameter parsing
- **Integration** — Hummingbird route testing via `HBApplication.test` (in-process HTTP)

**No E2E or browser tests needed** — this is a pure backend feature.

## Generated Test Files

| File | Tests | AC Coverage | Priority |
|------|-------|-------------|----------|
| `Tests/AxionCLITests/API/APITypesTests.swift` | 21 | AC2-AC6 | P0 |
| `Tests/AxionCLITests/API/RunTrackerTests.swift` | 12 | AC2-AC4, SSE Prep | P0 |
| `Tests/AxionCLITests/API/AxionAPIRoutesTests.swift` | 10 | AC1-AC6 | P0 |
| `Tests/AxionCLITests/Commands/ServerCommandTests.swift` | 8 | AC1 | P0 |

## Implementation Tasks & Activation Guide

During implementation of each task, follow TDD red-green-refactor:

### Task 2: API Data Models -> Activate APITypesTests

1. Create `Sources/AxionCLI/API/Models/APITypes.swift`
2. Define `APIRunStatus`, `CreateRunRequest`, `CreateRunResponse`, `RunStatusResponse`, `StepSummary`, `HealthResponse`, `APIErrorResponse`, `TrackedRun`, `RunOptions`
3. Ensure all JSON keys are snake_case (custom CodingKeys)
4. Run: `swift test --filter "AxionCLITests.API.APITypesTests"`
5. Verify all 21 tests pass

### Task 3: RunTracker -> Activate RunTrackerTests

1. Create `Sources/AxionCLI/API/RunTracker.swift`
2. Implement `actor RunTracker` with `submitRun`, `getRun`, `updateRun`, `listRuns`
3. Implement `setOnStatusChanged` callback for SSE prep
4. Run: `swift test --filter "AxionCLITests.API.RunTrackerTests"`
5. Verify all 12 tests pass

### Task 4: AxionAPI Routes -> Activate AxionAPIRoutesTests

1. Create `Sources/AxionCLI/API/AxionAPI.swift`
2. Define routes: `GET /v1/health`, `POST /v1/runs`, `GET /v1/runs/:runId`
3. Add Hummingbird dependency to Package.swift
4. Run: `swift test --filter "AxionCLITests.API.AxionAPIRoutesTests"`
5. Verify all 10 tests pass

### Task 5: ServerCommand -> Activate ServerCommandTests

1. Create `Sources/AxionCLI/Commands/ServerCommand.swift`
2. Register server subcommand in `AxionCLI.swift`
3. Run: `swift test --filter "AxionCLITests.Commands.ServerCommandTests"`
4. Verify all 8 tests pass

## Execution Commands

```bash
# Run all Story 5.1 tests
swift test --filter "AxionCLITests.API" --filter "AxionCLITests.Commands.ServerCommandTests"

# Run specific test files
swift test --filter "AxionCLITests.API.APITypesTests"
swift test --filter "AxionCLITests.API.RunTrackerTests"
swift test --filter "AxionCLITests.API.AxionAPIRoutesTests"
swift test --filter "AxionCLITests.Commands.ServerCommandTests"
```

## Red-Green-Refactor Workflow

1. **RED (Current):** All 51 test scaffolds generated — they will fail to compile until implementation types exist
2. **GREEN:** Implement each task, activate corresponding tests, verify they pass
3. **REFACTOR:** Clean up code, ensure no regressions

## Key Risks & Assumptions

- **Hummingbird SPM dependency** must be added to Package.swift before route tests can compile
- **AxionAPIRoutesTests** uses Hummingbird's `test()` method — requires `import Hummingbird` in test target
- **No real Agent execution** in route tests — AgentRunner is mocked/stubbed (no real LLM calls)
- **RunTracker** is an actor — all test calls use `await`
- **Test isolation:** Each test creates its own RunTracker instance (no shared state)

## Knowledge Base References Applied

- `data-factories.md` — Test data created inline (factory pattern not needed for Codable structs)
- `test-quality.md` — Atomic tests, one assertion per test where possible, descriptive names
- `test-levels-framework.md` — Unit for models/actor, Integration for HTTP routes
- `test-healing-patterns.md` — Naming conventions follow project patterns
- `test-priorities-matrix.md` — All P0 (core API functionality)

## Next Steps

1. **Dev Agent:** Execute story via `dev-story` workflow
2. **Task order:** Task 1 (SPM dep) -> Task 2 (Models) -> Task 3 (RunTracker) -> Task 4 (Routes) -> Task 5 (ServerCommand) -> Task 6 (AgentRunner)
3. **After implementation:** Run `automate` workflow for green-phase verification
