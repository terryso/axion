# Story 25.2: CostEventHandler

**Status:** backlog
**Epic:** 25 (EventHandler 体系)
**Priority:** P0
**Data Source:** RunCompleteContext (terminal event)

## Goal
Track LLM call token and cost data. On terminal events, output cost summary from RunCompleteContext.

## Implementation

1. Create `Sources/AxionCLI/Runtime/Handlers/CostEventHandler.swift`
2. Subscribe to terminal events: AgentCompletedEvent, AgentFailedEvent, AgentInterruptedEvent
3. Read totalCostUsd, usage, costBreakdown from context.runCompleteContext
4. Output cost summary to stderr (same format as current RunOrchestrator)

## Key Design
- No mutable state — reads from RunCompleteContext directly
- Daemon-safe: no cross-session state accumulation
- Zero-cost when runCompleteContext is nil

## Acceptance Criteria

- Given CostEventHandler registered, When agent completes, Then cost summary output includes totalCostUsd
- Given no runCompleteContext, When handler receives terminal event, Then handler skips gracefully
- Given daemon mode with 2 concurrent sessions, When each completes, Then cost data is independent
