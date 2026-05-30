---
title: 'TG Persistent Sessions'
type: 'feature'
created: '2026-05-30'
status: 'done'
baseline_commit: '94fe96b'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Every Telegram message creates a brand-new agent session. Users cannot follow up on previous results — asking "what was the result?" starts from scratch with no conversation context.

**Approach:** Add `chatId → sessionId` mapping in `TaskSerialQueue`. When a follow-up message arrives within 30 minutes, resume the existing session via `AxionRuntime.resumeSession()` instead of creating a new one. Add a `/new` command to explicitly reset, and auto-reset on 30-minute inactivity timeout. Session decisions are frozen at enqueue time so queued tasks are not retroactively affected by `/new` or timeout.

## Boundaries & Constraints

**Always:**
- Session decisions frozen in `PendingTask` at `enqueue()` time — `/new` and timeout only affect future tasks
- Resume failure auto-degrades to `executeRun()` with a warning log — no user-visible errors from stale sessions
- All unit tests use `MockDaemonRuntimeManager` with `resumeRun()` support — no real runtime, no MCP, no Helper
- Swift Testing framework only (`import Testing`, `@Suite`, `@Test`, `#expect`)
- `/new` wiring: `TelegramAdapter` passes `chatId` + `clearSession` callback to `TGCommandRouter`; `GatewayCommand` injects the callback

**Ask First:** None — all design decisions are pre-made in this spec.

**Never:**
- Gateway restart session-map recovery (sessions are on disk via `SessionStore`; in-memory map rebuild is deferred)
- Configurable timeout (hardcode 30 minutes first)
- Multi-round context injection (SDK's `resumeSession` handles it)

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Follow-up within timeout | Second TG message from same chatId, active session < 30 min old | `resumeRun()` called with existing sessionId, agent has prior context | N/A |
| Timeout expiry | Active session with `lastActivityAt` > 30 min ago | New session created, startup message: `"新会话已开始\n任务开始执行..."` | N/A |
| `/new` command | User sends `/new` with active session | Session mapping cleared, immediate reply `"新会话已开始"`, next message creates new session | N/A |
| Resume failure | `resumeSession()` throws (corrupted session) | Auto-degrade to `executeRun()`, warning log, user gets normal result | Log warning, clear session mapping |
| `/new` with queued tasks | T1 queued with old session, then `/new`, then T2 enqueued | T1 executes with its frozen session decision; T2 uses new (cleared) session | N/A |
| First message ever | No existing session for chatId | Normal `executeRun()`, session stored after completion | N/A |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` — Serial task execution; add `ActiveSession` struct, `chatSessions` map, timeout check, `PendingTask` session fields, resume logic in `startProcessing()`
- `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift` — Command routing; add `/new` command with `clearSession(chatId:)` callback
- `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` — TG message processing; pass `chatId` and `clearSession` to router
- `Sources/AxionCLI/Commands/GatewayCommand.swift` — Dependency wiring; inject `clearSession(chatId:)` callback from `TaskSerialQueue` into `TGCommandRouter`
- `Sources/AxionCLI/Services/DaemonRuntimeManager.swift` — Runtime management; add `resumeRun()` method mirroring `executeRun()` but calling `runtime.resumeSession()`
- `Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift` — Protocol; add `resumeRun()` signature
- `Sources/AxionCLI/Services/Protocols/AxionRuntimeRunning.swift` — Protocol; add `resumeSession()` signature so `DaemonRuntimeManager` can call it through the factory
- `Sources/AxionCLI/Services/AxionRuntime.swift` — Already has `resumeSession()`; no changes needed (it already conforms)

## Tasks & Acceptance

**Execution:**
- [x] `Sources/AxionCLI/Services/Protocols/AxionRuntimeRunning.swift` — Add `resumeSession(_:buildConfig:runOverrides:)` to protocol so `DaemonRuntimeManager` can invoke it through `runtimeFactory`
- [x] `Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift` — Add `resumeRun(sessionId:task:buildConfig:eventBus:runOverrides:extraHandlers:)` to protocol
- [x] `Sources/AxionCLI/Services/DaemonRuntimeManager.swift` — Implement `resumeRun()`: create runtime via factory, register handlers (same as `executeRun`), call `runtime.resumeSession()` instead of `runtime.execute()`, store session history
- [x] `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` — Add `ActiveSession` struct (sessionId, chatId, lastActivityAt, createdAt), `chatSessions: [Int64: ActiveSession]`, `clearSession(chatId:)` method. Expand `PendingTask` with `shouldResume`, `existingSessionId: String?`, `startMessage: String`. Modify `enqueue()`: check timeout → freeze session decision → set startMessage. Modify `startProcessing()`: if `shouldResume`, call `runtimeManager.resumeRun()` with error-degradation fallback
- [x] `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift` — Add `clearSession: @Sendable (Int64) -> Void` callback property. Add `/new` case in `handle()` that calls `clearSession(chatId)` and returns `"新会话已开始"`. Change `handle()` to accept `chatId: Int64` parameter. Update help text to include `/new`
- [x] `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` — Pass `chatId` to `commandRouter.handle(text, chatId:)`. Wire `clearSession` from `TaskSerialQueue` into `TGCommandRouter` init
- [x] `Sources/AxionCLI/Commands/GatewayCommand.swift` — Extract `clearSession` capability from `TaskSerialQueue` and pass through to `TGCommandRouter` init. Wire `TelegramAdapter` with chatId-aware router
- [x] `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` — Add tests: session resume within timeout, timeout creates new session with startup message, resume-failure degradation, `/new` via clearSession does not affect queued tasks, clearSession method
- [x] `Tests/AxionCLITests/Services/Telegram/TGCommandRouterTests.swift` — Add tests: `/new` clears session and returns message, `/new` updates help text, unknown commands still list `/new`
- [x] `Tests/AxionCLITests/Services/Telegram/TelegramAdapterTests.swift` — Add tests: `/new` message triggers clearSession and immediate reply, `/new` does not enqueue task

**Acceptance Criteria:**
- Given a TG user sends "open calculator" and receives a completion response, when the same user sends "what was the result" within 30 minutes, then the second task resumes the same session (same sessionId) and the agent has conversation context from the first task
- Given a TG user has an active session with lastActivity > 30 min ago, when the user sends a new message, then a new session is created and the startup message is "新会话已开始\n任务开始执行..."
- Given a TG user has an active session, when the user sends "/new", then the session mapping is cleared, an immediate reply "新会话已开始" is sent, and the next normal message creates a new session
- Given a TG user has an active session mapping but the session is corrupted, when a follow-up message triggers `resumeSession()` which throws, then the system auto-degrades to `executeRun()`, logs a warning, and the user receives a normal result
- Given chatId C has a queued task T1 frozen with old session decision, when the user sends "/new" and then enqueues T2, then T1 continues with its frozen session decision and T2 uses the cleared session — T1 is not cancelled or redirected

## Spec Change Log

| Date | Change |
|------|--------|
| 2026-05-30 | Initial draft from deferred-work.md |
| 2026-05-30 | Clarified `/new` wiring, timeout prompt, queued task semantics |

## Design Notes

**Frozen session decision in `PendingTask`:** Each `PendingTask` captures `shouldResume: Bool`, `existingSessionId: String?`, and `startMessage: String` at enqueue time. This is necessary because the FIFO queue may hold multiple tasks, and a `/new` or timeout between enqueue and execution must not retroactively alter a task's session semantics. The `startMessage` is frozen too so the "新会话已开始" prefix appears only for timeout-triggered new sessions, not for the first-ever message.

**`resumeSession` on `AxionRuntimeRunning` protocol:** `DaemonRuntimeManager` creates runtimes through `runtimeFactory: (EventBus) -> any AxionRuntimeRunning`. Since `resumeSession()` currently exists only on `AxionRuntime` (the concrete type), adding it to the protocol lets `DaemonRuntimeManager.resumeRun()` call it without a type cast. `AxionRuntime` already implements it — only the protocol declaration changes.

**Timeout check is lazy (enqueue-time, no background timer):** Checking `lastActivityAt` at enqueue is sufficient because session lookup only happens when a message arrives. A background timer would add complexity with no user-facing benefit — if nobody messages, there's nothing to time out.

## Verification

**Commands:**
- `swift test --filter "AxionCLITests.Services.Gateway.TaskSerialQueueTests"` -- expected: all tests pass including new session tests
- `swift test --filter "AxionCLITests.Services.Telegram.TGCommandRouterTests"` -- expected: all tests pass including `/new` tests
- `swift test --filter "AxionCLITests.Services.Telegram.TelegramAdapterTests"` -- expected: all tests pass including `/new` wiring tests
- `swift build` -- expected: compiles with no errors

## Suggested Review Order

**Session tracking & resume logic (core mechanism)**

- Entry point: session mapping, timeout check, and frozen decisions in enqueue
  [`TaskSerialQueue.swift:80`](../../Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift#L80)

- Resume execution with timeout, error degradation to executeRun
  [`TaskSerialQueue.swift:197`](../../Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift#L197)

- Session stored after task completion, chatId-keyed activity tracking
  [`TaskSerialQueue.swift:257`](../../Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift#L257)

**Protocol & runtime layer**

- resumeRun added to protocol for session continuation
  [`DaemonRuntimeManaging.swift:29`](../../Sources/AxionCLI/Services/Protocols/DaemonRuntimeManaging.swift#L29)

- resumeRun mirrors executeRun but calls runtime.resumeSession()
  [`DaemonRuntimeManager.swift:97`](../../Sources/AxionCLI/Services/DaemonRuntimeManager.swift#L97)

- resumeSession added to AxionRuntimeRunning protocol
  [`AxionRuntimeRunning.swift:13`](../../Sources/AxionCLI/Services/Protocols/AxionRuntimeRunning.swift#L13)

**/new command wiring**

- /new command with clearSession callback and chatId parameter
  [`TGCommandRouter.swift:42`](../../Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift#L42)

- chatId passed from adapter to router for command context
  [`TelegramAdapter.swift:72`](../../Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift#L72)

- Dependency injection: queue → router → adapter wiring
  [`GatewayCommand.swift:271`](../../Sources/AxionCLI/Commands/GatewayCommand.swift#L271)

**Tests**

- Session resume, timeout, degradation, clearSession isolation tests
  [`TaskSerialQueueTests.swift:449`](../../Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift#L449)

- /new command tests with clearSession callback
  [`TGCommandRouterTests.swift:271`](../../Tests/AxionCLITests/Services/Telegram/TGCommandRouterTests.swift#L271)

- /new integration tests in adapter
  [`TelegramAdapterTests.swift:719`](../../Tests/AxionCLITests/Services/Telegram/TelegramAdapterTests.swift#L719)
