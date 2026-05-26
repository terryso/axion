# State Machines

Transition tables for the core entities in the Axion Runtime. All transitions are event-driven.

## Session State

```
CREATED → RUNNING → COMPLETED
                  → PAUSED → RUNNING (resume)
                           → COMPLETED
                  → FAILED
```

| State | Description |
|-------|-------------|
| CREATED | Session initialized, not yet executing |
| RUNNING | Agent actively executing |
| PAUSED | Execution suspended, state persisted |
| COMPLETED | Execution finished successfully |
| FAILED | Execution terminated with error |

## Agent State

```
IDLE → THINKING → EXECUTING_TOOL → COMPLETED
                                   → FAILED
               → WAITING → THINKING
                          → COMPLETED
                          → FAILED
```

| State | Description |
|-------|-------------|
| IDLE | Agent not executing |
| THINKING | Agent processing, no tool call |
| EXECUTING_TOOL | Agent invoked a tool, awaiting result |
| WAITING | Agent paused, awaiting external input |
| COMPLETED | Agent finished |
| FAILED | Agent errored |

## Tool State

```
INIT → RUNNING → STREAMING → DONE
                              → ERROR
              → DONE
              → ERROR
```

| State | Description |
|-------|-------------|
| INIT | Tool invocation created |
| RUNNING | Tool executing |
| STREAMING | Tool emitting output chunks |
| DONE | Tool completed |
| ERROR | Tool failed |

## Workflow State

```
NOT_STARTED → IN_PROGRESS → COMPLETED
                           → PAUSED → IN_PROGRESS (resume)
                                    → COMPLETED
                           → FAILED
```

| State | Description |
|-------|-------------|
| NOT_STARTED | Workflow defined, not executing |
| IN_PROGRESS | Workflow executing steps |
| PAUSED | Workflow suspended |
| COMPLETED | All steps finished |
| FAILED | Workflow errored |

## Context Evolution Model

Context is not a static prompt — it evolves through events:

```
ContextUpdated → ContextCompressed → ContextMerged → ContextRebuilt
```

Actions: incremental update, compression (reduce size), merge (combine contexts), rebuild (from event log).
