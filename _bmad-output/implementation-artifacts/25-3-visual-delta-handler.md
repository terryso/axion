# Story 25.3: VisualDeltaHandler

**Status:** backlog
**Epic:** 25 (EventHandler 体系)
**Priority:** P0
**Data Source:** Pure AgentEvent (ToolCompletedEvent.output)

## Goal
Check visual changes when screenshot tool completes. Skip verification screenshots when no change detected.

## Implementation

1. Create `Sources/AxionCLI/Runtime/Handlers/VisualDeltaHandler.swift`
2. Subscribe to ToolCompletedEvent (filter toolName containing "screenshot")
3. Extract base64 from event.output
4. Reuse existing VisualDeltaTracker actor
5. Track checked/skipped counts

## Acceptance Criteria

- Given VisualDeltaHandler registered with noVisualDelta=false, When screenshot completes, Then handler checks visual delta
- Given config.noVisualDelta=true, When handler created, Then tracker is nil, no checks run
- Given non-screenshot tool completes, When handler receives event, Then handler ignores it
