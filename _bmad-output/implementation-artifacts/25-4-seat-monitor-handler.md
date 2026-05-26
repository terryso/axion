# Story 25.4: SeatMonitorHandler

**Status:** backlog
**Epic:** 25 (EventHandler 体系)
**Priority:** P0
**Data Source:** AgentEvent + AxionRunState

## Goal
Monitor user seat activity during helper tool execution. Detect external modification.

## Implementation

1. Create `Sources/AxionCLI/Runtime/Handlers/SeatMonitorHandler.swift`
2. Subscribe to ToolStartedEvent (filter toolName starting with "mcp__axion-helper__")
3. Reuse existing SeatActivityMonitor actor
4. Lazy-init monitor on first helper tool call
5. On detection: set axionState.externallyModified = true

## Acceptance Criteria

- Given SeatMonitorHandler with sharedSeatMode=true, When helper tool starts, Then handler checks seat activity
- Given user activity detected, When handler checks, Then externallyModified set to true
- Given sharedSeatMode=false, When handler created, Then no monitoring occurs
