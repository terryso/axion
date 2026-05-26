# Implementation Roadmap

Phased delivery plan with dependency ordering. Two parallel tracks: SDK changes (event layer) and Axion changes (runtime layer).

## Dependency Graph

```
SDK S1 (AgentEvent types)
    ↓
SDK S2 (EventBus)
    ↓
SDK S3 (Agent Event Emitter) ← core SDK change, modifies Agent.swift
    ↓
SDK S4 (EventBus → SSE bridge)          P1
SDK S5 (Token Streaming Event)          P2

Axion A1 (Import SDK EventBus)          P0 — depends on SDK S1+S2
    ↓
Axion A2 (AxionRuntime Actor)           P0 — core Axion change
    ↓
Axion A3 (EventHandler System)          P0 — extract from RunOrchestrator
    ↓
Axion A4 (CLI Migration)                P0 — RunCommand → Runtime
Axion A5 (API Migration)                P1 — ApiRunner → Runtime
Axion A6 (Session Resume CLI)           P1
Axion A7 (Skill/Daemon Integration)     P2
```

## Phase 1: Runtime Foundation (A1–A4)

### SDK Epic 1: AgentEvent + EventBus (S1 + S2)
- Define event protocol and all event types
- Implement EventBus actor (AsyncChannel, type-filtered subscribe, bufferingLatest(100))
- Unit tests

### SDK Epic 2: Agent Event Emitter (S3)
- Add `eventBus: EventBus?` to AgentOptions (optional injection, zero cost when absent)
- Emit events at key points in Agent.stream()/promptImpl
- E2E tests pass (882 existing tests unchanged)

### Axion Epic 1: AxionRuntime Core (A1 + A2)
- Import SDK EventBus
- Implement AxionRuntime actor (session lifecycle, agent execution)
- Session state machine: CREATED → RUNNING → PAUSED / COMPLETED / FAILED
- Unit tests

### Axion Epic 2: EventHandler System (A3)
- Extract cross-cutting concerns from RunOrchestrator into independent handlers:

| Handler | Subscribes To | Extracted From |
|---------|--------------|----------------|
| CostEventHandler | LLMCostEvent | RunOrchestrator cost calc |
| VisualDeltaHandler | ToolCompletedEvent | RunOrchestrator visualDeltaTracker |
| SeatMonitorHandler | ToolStartedEvent | RunOrchestrator seatMonitor |
| MemoryProcessingHandler | AgentCompletedEvent | RunMemoryProcessor |
| ReviewHandler | AgentCompletedEvent | ReviewOrchestrator |
| NotificationHandler | AgentCompletedEvent | sendDesktopNotification |
| TraceEventHandler | All events | TraceRecorder |

### Axion Epic 3: CLI + API Migration (A4)
- RunCommand → AxionRuntime (gradual: first parallel, then switch)
- CLI renders events from EventBus
- Existing functionality preserved

## Phase 2: Observability (A8–A10)

- Timeline-first TUI (consumes EventBus, renders execution timeline)
- Event log persistence to SQLite (append-only)
- `axion replay <session-id>` — replay from event log
- Cost dashboard (`axion stats`)

## Phase 3: Workflow / Multi-Agent (A11–A12)

- YAML workflow definition (planner → researcher → implementer → reviewer)
- Multi-agent orchestration (SDK SubAgent + Team via EventBus)
- DAG workflow support
- Timeline visualization of agent tree

## Transition Strategy

Axion A2 can use a mock EventBus before SDK S3 is complete. SDK and Axion Epic 1 can run in parallel. After SDK S3 delivers real event emission, Axion swaps mock for real EventBus.

## What Phase 1 Does NOT Do

| Item | Reason |
|------|--------|
| TUI | Phase 2 |
| Workflow DAG engine | Phase 3; SDK lacks corresponding support |
| Multi-agent orchestration | Phase 3 |
| Event log persistence / replay | Phase 2 (needs persistence layer) |
| macOS App | Phase 2 |
| Token streaming events | SDK P2, opt-in, non-blocking |
| Cross-process EventBus | v1 is in-process only; daemon handles multi-session |

## Suggested Timeline

```
Week 1-2:  SDK Epic 1 (AgentEvent + EventBus)
Week 2-3:  SDK Epic 2 (Agent Event Emitter)
    ↓ parallel (with mock EventBus)
Week 1-3:  Axion Epic 1 (AxionRuntime Core)
Week 3-4:  Axion Epic 2 (EventHandler System)
Week 4-5:  Axion Epic 3 (CLI Migration)
Week 5-6:  Axion Epic 4 (Session Resume + Daemon)
```
