# Runtime API Protocol

The contract between frontends (CLI, TUI, App, HTTP) and the Axion Runtime. Runtime is the sole source of truth; frontends emit commands and consume events.

## Session Lifecycle

### Create Session

```
POST /session.create
Input:  { "task": "string", "workflow": "optional", "context": {} }
Output: { "session_id": "string" }
```

### Attach to Session

```
POST /session.attach
Input:  { "session_id": "string" }
Output: { "status": "attached" }
```

### Resume Session

```
POST /session.resume
Input:  { "session_id": "string" }
```

### Pause Session

```
POST /session.pause
Input:  { "session_id": "string" }
```

### Close Session

```
POST /session.close
Input:  { "session_id": "string" }
```

## Event Stream

### Subscribe

```
GET /events.subscribe?session_id=xxx
Returns: streaming JSONL — one event envelope per line
```

### Send User Event

```
POST /events.send
Input: { "session_id": "string", "type": "UserEvent | ControlEvent", "payload": {} }
```

## CLI → Runtime Mapping

CLI commands are event generators — no logic execution in the CLI layer:

| CLI Command | Equivalent API Calls |
|-------------|----------------------|
| `axion run "task"` | `POST /session.create` → `POST /events.send { type: UserInputEvent }` |
| `axion resume <id>` | `POST /session.resume` |
| `axion sessions` | Query session list from runtime |
| `axion replay <id>` | `POST /session.replay` |

## Workflow Model

```json
{
  "workflow": ["planner", "researcher", "implementer", "reviewer"]
}
```

## Replay Protocol

```
POST /session.replay
Input:  { "session_id": "string" }
Rule:   Reconstruct state from event log; same event sequence → same state.
```

## Session Model

```json
{
  "session_id": "string",
  "state": "RUNNING | PAUSED | COMPLETED | FAILED",
  "created_at": 123,
  "workflow": {},
  "context": {}
}
```

## Transport Layer

| Transport | Use Case | Phase |
|-----------|----------|-------|
| STDIO | CLI, local execution | Phase 1 |
| WebSocket | TUI, App, streaming UI | Phase 2 |
| HTTP | IDE plugin, remote agent | Future |

## Error Model

```json
{
  "type": "ErrorOccurred",
  "payload": {
    "code": "string",
    "message": "string",
    "recoverable": true
  }
}
```
