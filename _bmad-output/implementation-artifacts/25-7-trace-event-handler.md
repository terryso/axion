# Story 25.7: TraceEventHandler

**Status:** backlog
**Epic:** 25 (EventHandler 体系)
**Priority:** P1
**Data Source:** Pure AgentEvent

## Goal
Record all runtime events to trace system for debugging.

## Implementation

1. Create `Sources/AxionCLI/Runtime/Handlers/TraceEventHandler.swift`
2. Subscribe to all events (subscribedEventTypes = [])
3. Map AgentEvent to TraceRecord using existing TraceRecorder
4. Record event type, timestamp, session, and key data

## Event Mapping

| AgentEvent | trace type | key data |
|------------|-----------|----------|
| AgentStartedEvent | agent_started | task |
| AgentCompletedEvent | agent_completed | totalSteps, durationMs |
| ToolStartedEvent | tool_started | toolName |
| ToolCompletedEvent | tool_completed | toolName, durationMs, isError |
| LLMCostEvent | llm_cost | model, tokens, cost |

## Acceptance Criteria

- Given TraceEventHandler with traceDir configured, When any AgentEvent emitted, Then recorded to trace
- Given agent runs 3 tool calls, When checking trace, Then full sequence recorded
- Given traceDir is nil, When handler created, Then no recording
