# Architecture Diagrams

## System Topology

```
┌──────────────────────────────────┐
│        CLI / TUI / App           │
│     (stateless event consumers)  │
└──────────────┬───────────────────┘
               │ Event Stream (subscribe only)
               ▼
┌──────────────────────────────────┐
│         Axion Runtime            │
│                                  │
│  ┌────────────────────────────┐  │
│  │     Agent Scheduler        │  │
│  └────────────────────────────┘  │
│  ┌────────────────────────────┐  │
│  │     Workflow Engine        │  │
│  └────────────────────────────┘  │
│  ┌────────────────────────────┐  │
│  │     Tool Runtime           │  │
│  └────────────────────────────┘  │
│  ┌────────────────────────────┐  │
│  │     Memory System          │  │
│  └────────────────────────────┘  │
│  ┌────────────────────────────┐  │
│  │     Event Bus (core)       │  │
│  └────────────────────────────┘  │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│      Persistence Layer           │
│  - Event Log (SQLite, append)    │
│  - Session Store                 │
│  - Artifact Store                │
└──────────────────────────────────┘
```

## Current Architecture (Pre-Runtime)

```
RunCommand (CLI) ──→ AgentBuilder ──→ Agent.stream() ──→ SDKMessageOutputHandler
                                              ↓
ApiRunner (HTTP) ──→ AgentBuilder ──→ Agent.stream() ──→ EventBroadcaster (SSE)
```

Problem: Two independent execution paths, each manually processing SDKMessage. Cross-cutting concerns handled inline in RunOrchestrator's stream loop (~350 lines).

## Target Architecture (Post-Runtime)

```
RunCommand (CLI) ──→ AxionRuntime ──→ AgentBuilder ──→ Agent.stream()
                          ↓                              ↓
ApiRunner (HTTP) ──→ AxionRuntime                EventBus (from SDK)
                          ↓                              ↓
                    EventBus.subscribe()          AgentEvents
                          ↓
               ┌──────────┼──────────┐
               ↓          ↓          ↓
          CLI Output   SSE Push   TUI / App
```

Core changes:
1. **AxionRuntime actor** — single execution entry point
2. **EventBus** — single event channel from SDK
3. **Cross-cutting concerns** — event handlers, not inline code
4. **CLI / API / TUI** — all EventBus subscribers

## Execution Flow

```
Workflow → Node → Agent → Tool → Event Stream → State Update
```

## Event Flow

```
Agent → emits event → EventBus → persists to log → UI renders
```

## Multi-Agent Tree

```
Root Agent
   ├── Planner
   ├── Implementer
   └── Reviewer
```

Agents communicate via events only. No direct function calls. No shared mutable state.

## Data Flow

```
CLI Command (event generator)
        ↓
AxionRuntime (state machine)
        ↓
AgentBuilder → Agent.stream()
        ↓
EventBus.publish(event)
        ↓
    ┌───┼───┐
    ↓   ↓   ↓
  CLI  SSE  Log
```
