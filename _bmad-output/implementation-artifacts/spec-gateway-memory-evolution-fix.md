---
status: done
created: 2026-06-02
epic: 28
story: hotfix
---

# Fix: Gateway TG Path Missing Memory + Review Integration

## Problem

Gateway TG tasks do not accumulate memory or trigger auto-evolution. Two root causes:

1. **MemoryProcessingHandler not registered** — The handler that extracts AppMemoryFact from tool calls after each run is only registered in the CLI path (RunCommand), never in the Gateway/TG path. Result: zero App operation memory from TG interactions.

2. **reviewDataContext nil in TG RunOverrides** — `TaskSerialQueue.makeGatewayRunOverrides()` passes `reviewDataContext: nil`, so RunOrchestrator never calls `reviewDataContext.update(agent:messages:reviewOrchestrator:)`. Without this, ReviewScheduler's `reviewOrchestrator` and `agent` are nil, and it silently returns without scheduling reviews. Result: no review-based memory extraction, no skill evolution.

## Fix

### File 1: `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift`

- Add `reviewDataContext: ReviewDataContext?` and `memoryDir: String` to init
- In `makeGatewayRunOverrides()`, pass `reviewDataContext` instead of nil
- In `executeNewWithTimeout` and `executeWithTimeout`, add `MemoryProcessingHandler` to allHandlers

### File 2: `Sources/AxionCLI/Commands/GatewayCommand.swift`

- Create a shared `ReviewDataContext` for the TG path
- Pass it to both `ReviewScheduler` init and `TaskSerialQueue` init
- Pass `memoryDir` to `TaskSerialQueue`

## Acceptance Criteria

- Given a TG task completes successfully, When the event fires, Then MemoryProcessingHandler extracts and stores AppMemoryFacts
- Given a TG task completes, When ReviewScheduler receives AgentCompletedEvent, Then reviewDataContext has agent + orchestrator set, and review is scheduled
- Given a TG task triggers review, When review completes, Then memory changes are persisted and curator notification fires
- Existing tests pass (`swift test --filter AxionCLITests`)
