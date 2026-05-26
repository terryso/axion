# Story 25.5: MemoryProcessingHandler

**Status:** backlog
**Epic:** 25 (EventHandler 体系)
**Priority:** P0
**Data Source:** RunCompleteContext + AxionRunState

## Goal
Process memory data after agent completes. Accumulate knowledge across runs.

## Implementation

1. Create `Sources/AxionCLI/Runtime/Handlers/MemoryProcessingHandler.swift`
2. Subscribe to terminal events as trigger
3. Get toolPairs from context.runCompleteContext (NOT self-built)
4. Get externallyModified/takeoverEvent from context
5. Call existing RunMemoryProcessor.processRunResult()

## Acceptance Criteria

- Given handler registered with noMemory=false, When agent completes, Then processRunResult called with toolPairs from runCompleteContext
- Given noMemory=true, When terminal event, Then handler skips
- Given externallyModified=true, When terminal event, Then handler skips memory processing
