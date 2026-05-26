# Event Taxonomy

Runtime-level event classification for the Axion Agent Runtime. All events conform to `AgentEvent` protocol with `id` and `timestamp` fields. Events are the sole mechanism for state communication — no hidden state, no direct mutation.

## Base Protocol

```swift
public protocol AgentEvent: Sendable {
    var id: String { get }
    var timestamp: Date { get }
}
```

## Category: Session

| Event | Description |
|-------|-------------|
| `SessionCreatedEvent` | New session initialized |
| `SessionRestoredEvent` | Session restored from persistence |
| `SessionAttachedEvent` | Frontend attached to existing session |
| `SessionResumedEvent` | Paused session resumed |
| `SessionClosedEvent` | Session terminated |
| `SessionAutoSavedEvent` | Automatic session persistence |

## Category: Agent

| Event | Description |
|-------|-------------|
| `AgentStartedEvent` | Agent begins execution |
| `AgentThinkingEvent` | Agent processing (no tool call) |
| `AgentCompletedEvent` | Agent finished successfully |
| `AgentFailedEvent` | Agent execution failed |
| `AgentInterruptedEvent` | Agent interrupted by user/system |
| `AgentResumedEvent` | Interrupted agent resumed |

## Category: Tool

| Event | Payload | Description |
|-------|---------|-------------|
| `ToolStartedEvent` | tool_name, input | Tool invocation begins |
| `ToolStreamingEvent` | chunk | Streaming output data |
| `ToolCompletedEvent` | output, duration | Tool finished |
| `ToolFailedEvent` | error | Tool execution failed |

## Category: LLM

| Event | Payload | Description |
|-------|---------|-------------|
| `LLMRequestStartedEvent` | model, input_tokens | API call begins |
| `LLMResponseReceivedEvent` | model, output_tokens | Response complete |
| `LLMTokenStreamEvent` | token chunk (opt-in) | Streaming token output |
| `LLMCostEvent` | input_tokens, output_tokens, cost | Per-call cost tracking |

## Category: Memory

| Event | Description |
|-------|-------------|
| `MemoryUpdatedEvent` | Memory entry added or modified |
| `MemoryCompressedEvent` | Memory compressed/summarized |
| `MemoryEvictedEvent` | Memory entry evicted |
| `ContextRebuiltEvent` | Context window rebuilt |

## Category: SubAgent

| Event | Description |
|-------|-------------|
| `SubAgentSpawnedEvent` | Child agent created |
| `SubAgentCompletedEvent` | Child agent finished |

## Category: Workflow

| Event | Description |
|-------|-------------|
| `WorkflowStartedEvent` | Workflow begins |
| `WorkflowStepStartedEvent` | Individual step begins |
| `WorkflowStepCompletedEvent` | Step finished |
| `WorkflowCompletedEvent` | Workflow finished |
| `WorkflowPausedEvent` | Workflow paused |
| `WorkflowResumedEvent` | Workflow resumed |

## Event Envelope

All events transmitted over the wire use a unified envelope:

```json
{
  "id": "event_id",
  "session_id": "session_id",
  "timestamp": 1234567890,
  "type": "AgentEvent | ToolEvent | WorkflowEvent | MemoryEvent | SystemEvent",
  "payload": {}
}
```
