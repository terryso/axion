# Story 32.5: Interactive Approval, Confirmation & Clarify

Status: done
baseline_commit: 2c13b64de9efb25a0c1e92fca8e72ec25739d4c8

## Story

As a Axion Telegram user,
I want dangerous operation approvals, confirmations, and multi-choice clarifications to be completable via inline keyboard buttons,
So that remote operations don't require typing fragile text commands.

## Acceptance Criteria

1. **Given** agent triggers dangerous command approval via `pause_for_human`
   **When** Gateway needs user confirmation
   **Then** Telegram sends an inline keyboard with at least `Allow Once`, `Session`, `Always`, `Deny` buttons
   **And** message body contains command preview and approval reason
   **And** `callback_data` is encoded as `approve:{scope}:{pendingId}` (total length ≤ 64 bytes, TG limit)

2. **Given** a slash command requires secondary confirmation
   **When** Gateway sends confirmation message
   **Then** Telegram shows `Approve Once`, `Always Approve`, `Cancel` buttons
   **And** user completes confirmation by tapping a button (no text input required)

3. **Given** agent provides multiple candidate options for clarification
   **When** Adapter renders clarify message
   **Then** message body shows full option text
   **And** each option has an independent button
   **And** a `Type Answer` entry switches to text capture mode

4. **Given** callback query from unauthorized user, expired confirmation ID, or wrong chat/session
   **When** Gateway processes the callback
   **Then** safely ignore or return "expired/unauthorized" hint
   **And** never incorrectly unlock another user's session

5. **Given** user taps a button and Telegram still shows loading spinner
   **When** callback is successfully processed
   **Then** Gateway calls `answerCallbackQuery` to dismiss spinner
   **And** original approval message is updated to "approved/denied/awaiting text input"

6. **Given** free-text clarify mode is active (user tapped `Type Answer`)
   **When** next text message arrives from that chat
   **Then** text is captured as resume context and passed to `agent.resume(context:)`
   **And** text capture mode is exited after one message

7. **Given** pending interaction exceeds TTL (default 5 minutes)
   **When** user taps expired button
   **Then** `answerCallbackQuery` returns "interaction expired" message
   **And** no stale resume handle is invoked

## Tasks / Subtasks

- [x] Task 1: Extend TGModels with callback query and inline keyboard types (AC: #1, #2, #3)
  - [x] 1.1 Add `callbackQuery` field to `TGUpdate` (optional `TGCallbackQuery?`)
  - [x] 1.2 Create `TGCallbackQuery` struct: `id`, `from: TGUser`, `message: TGMessage?`, `data: String?`
  - [x] 1.3 Create `TGInlineKeyboardMarkup` struct with `inline_keyboard: [[TGInlineKeyboardButton]]`
  - [x] 1.4 Create `TGInlineKeyboardButton` struct: `text`, `callback_data`, `url` (all optional)
  - [x] 1.5 Codable CodingKeys for all new types (snake_case JSON ↔ camelCase Swift)
  - [x] 1.6 Unit tests: Codable round-trip for all new model types

- [x] Task 2: Extend TGAPIClient with callback and keyboard APIs (AC: #1, #5)
  - [x] 2.1 Add `answerCallbackQuery(callbackQueryId:text:) async throws` to protocol and implementation
  - [x] 2.2 Add `sendMessage` overload accepting `replyMarkup: TGInlineKeyboardMarkup?`
  - [x] 2.3 Add `editMessageText` overload accepting `replyMarkup: TGInlineKeyboardMarkup?`
  - [x] 2.4 Add mock support in `MockTGAPIClient` for new methods
  - [x] 2.5 Unit tests for new API methods

- [x] Task 3: Create `TGInteractiveSessionStore` actor (AC: #1, #4, #7)
  - [x] 3.1 Define `TGInteractionMode` enum: `approval`, `confirm`, `clarify(options: [String])`, `textCapture`
  - [x] 3.2 Define `TGInteractionResolution` enum: `resume(context:)`, `expired`, `unauthorized`, `notFound`
  - [x] 3.3 Define `PendingInteraction` struct: `pendingId`, `chatId`, `sessionId`, `allowedUserId`, `createdAt`, `ttl`, `mode`, `callbackPayloads`, `awaitsTextReply`
  - [x] 3.4 Implement `register(...)` → generates `pendingId`, stores `PendingInteraction`
  - [x] 3.5 Implement `resolveCallback(pendingId:data:fromUser:)` → validates and returns `TGInteractionResolution`
  - [x] 3.6 Implement `resolveTextReply(chatId:fromUser:text:)` → finds text-capture session, returns resolution
  - [x] 3.7 Implement `cleanupExpired()` → removes TTL-exceeded entries
  - [x] 3.8 Implement `hasTextCaptureSession(chatId:)` → checks if chat awaits text input
  - [x] 3.9 Unit tests: register, resolve valid/expired/unauthorized callbacks, text capture, cleanup

- [x] Task 4: Bridge pause detection from SDK to EventBus (AC: #1)
  - [x] 4.1 Create `AgentPausedEvent` struct conforming to `AgentEvent` with `reason: String`, `sessionId: String?`
  - [x] 4.2 In `AxionRuntime.execute()` or the message processing loop, detect `SDKMessage.system(.paused)` and publish `AgentPausedEvent` to EventBus
  - [x] 4.3 Unit tests verifying pause event is published

- [x] Task 5: Add resume handle support to `TaskSerialQueue` (AC: #1, #6)
  - [x] 5.1 Add `activeResumeHandles: [String: @Sendable (String) async -> Void]` stored property
  - [x] 5.2 Add `registerResumeHandle(pendingId:handle:)` method
  - [x] 5.3 Add `resumeInteraction(pendingId:context:) async -> Bool` method: looks up handle, invokes it, removes entry
  - [x] 5.4 In `executeNewWithTimeout` / `executeWithTimeout`: after creating agent, extract `agent.resume` closure, store it for later binding
  - [x] 5.5 Clean up resume handles when task group child task completes (success, failure, or timeout)
  - [x] 5.6 Add to `TaskSerialQueueProtocol` for mockability
  - [x] 5.7 Unit tests for resume handle registration, invocation, and cleanup

- [x] Task 6: Handle pause events in `TGEventHandler` (AC: #1, #2, #3)
  - [x] 6.1 Subscribe to `AgentPausedEvent` in `subscribedEventTypes`
  - [x] 6.2 On pause: register pending interaction via `TGInteractiveSessionStore.register()`, get `pendingId`
  - [x] 6.3 Build inline keyboard buttons based on interaction mode (approval/confirm/clarify)
  - [x] 6.4 Send inline keyboard message via `sendMessage` with `replyMarkup`
  - [x] 6.5 Register resume handle with `TaskSerialQueue` (pass pendingId + agent resume closure)
  - [x] 6.6 Unit tests for pause → keyboard message flow

- [x] Task 7: Handle callback queries in `TelegramAdapter` (AC: #4, #5, #6)
  - [x] 7.1 Extend `pollLoop()` and `processUpdates()` to check `update.callbackQuery`
  - [x] 7.2 Add `processCallback(_ query: TGCallbackQuery)` method
  - [x] 7.3 Resolve via `TGInteractiveSessionStore.resolveCallback()`
  - [x] 7.4 On valid resolution: call `answerCallbackQuery`, then `TaskSerialQueue.resumeInteraction()`
  - [x] 7.5 On invalid resolution: call `answerCallbackQuery` with error text
  - [x] 7.6 Edit original keyboard message to show resolution state (remove buttons, show "approved/denied")
  - [x] 7.7 Unit tests for callback processing: valid, expired, unauthorized, wrong chat

- [x] Task 8: Handle text capture mode in `TelegramAdapter.processMessage()` (AC: #6)
  - [x] 8.1 Before command router / task enqueue: check `TGInteractiveSessionStore.hasTextCaptureSession(chatId:)`
  - [x] 8.2 If text capture active: resolve via `store.resolveTextReply()`, call `resumeInteraction()`
  - [x] 8.3 Skip normal command/task processing for captured text
  - [x] 8.4 Unit tests for text capture interception

- [x] Task 9: Wire everything in `GatewayCommand` (AC: #1-#7)
  - [x] 9.1 Create `TGInteractiveSessionStore` instance
  - [x] 9.2 Pass store to `TGEventHandler` init (new parameter)
  - [x] 9.3 Pass store to `TelegramAdapter` for callback/text resolution
  - [x] 9.4 Wire `TaskSerialQueue.resumeInteraction` through to adapter
  - [x] 9.5 Integration verification: end-to-end pause → keyboard → callback → resume

## Dev Notes

### Critical Architectural Finding: No AgentPausedEvent in SDK

**The SDK does NOT publish an `AgentPausedEvent` to EventBus.** Pause is communicated via `SDKMessage.system(.paused)` with `PausedData` in the message stream. This is a critical gap — `TGEventHandler` only receives EventBus `AgentEvent` types, not SDK messages.

**Solution:** Create a custom `AgentPausedEvent` and publish it to EventBus. The AxionRuntime already processes SDKMessages during execution — add a detection point for `.system(.paused)` that publishes the custom event. This is the minimal bridge; it doesn't require SDK changes.

**Evidence:**
- `Agent.swift:466-474`: Pause emits `continuation.yield(.system(.paused, ...))` to SDKMessage stream
- `Agent.swift:438`: Resume DOES publish `AgentResumedEvent` to EventBus
- `AgentEventTypes.swift`: Has `AgentResumedEvent` (line 409), `AgentInterruptedEvent` (line 369), but NO `AgentPausedEvent`
- `SDKMessage.swift:390-391`: `Subtype.paused` and `.pausedTimeout` exist in message stream

### Agent Pause/Resume API

SDK `Agent` provides:
- `pause(reason: String)` — Sets pause state; actual suspension happens in stream's pause handler
- `resume(context: String)` — Resumes from pause, publishes `AgentResumedEvent`, injects context as user message
- `interrupt()` — Aborts pause with `"__PAUSE_ABORT__"` sentinel
- Timeout: If `pauseTimeoutMs > 0`, auto-resumes with `"__PAUSE_TIMEOUT__"` sentinel after timeout

The agent's resume closure is the key bridge. It must be captured during task execution and stored in `TaskSerialQueue.activeResumeHandles` for later invocation when a TG callback arrives.

### Resume Handle Architecture

The agent runs inside a `withThrowingTaskGroup` child task in `TaskSerialQueue.executeNewWithTimeout()`. The `TelegramAdapter.pollLoop()` runs on the actor's main loop. When a callback arrives, it cannot directly access the agent — it must go through:

```
Agent (task group child task)
  ↓ pause(reason:)
  ↓ AxionRuntime detects SDKMessage.system(.paused)
  ↓ Publishes AgentPausedEvent to EventBus
TGEventHandler receives AgentPausedEvent
  ↓ Registers pending interaction in TGInteractiveSessionStore
  ↓ Sends inline keyboard via TelegramAdapter
  ↓ Stores resume closure in TaskSerialQueue.activeResumeHandles
TelegramAdapter.pollLoop() receives callback_query
  ↓ Resolves via TGInteractiveSessionStore
  ↓ Calls TaskSerialQueue.resumeInteraction(pendingId, context)
TaskSerialQueue looks up activeResumeHandles[pendingId]
  ↓ Invokes resume closure with context
Agent.resume(context:) is called, continues execution
```

### Files Being Modified (UPDATE)

| File | Current State | What Changes |
|------|---------------|--------------|
| `Sources/AxionCLI/Services/Telegram/TGModels.swift` (131 lines) | TGUpdate has only `message` field. No callback/keyboard models | Add `callbackQuery` to TGUpdate. Add `TGCallbackQuery`, `TGInlineKeyboardMarkup`, `TGInlineKeyboardButton` structs |
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` (272 lines) | `sendMessage` and `editMessageText` have no replyMarkup support. No `answerCallbackQuery` | Add `answerCallbackQuery` method. Add overloads with `replyMarkup: TGInlineKeyboardMarkup?` for sendMessage and editMessageText. Extend protocol |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` (277 lines) | `pollLoop` and `processUpdates` only check `update.message`. No callback handling | Add callback query branch in pollLoop/processUpdates. Add `processCallback()` method. Add text capture interception in processMessage |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` (364 lines) | Agent runs in task group, no resume handle storage | Add `activeResumeHandles` dict. Add `registerResumeHandle` and `resumeInteraction` methods. Clean up handles on task completion |
| `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` (115 lines) | Subscribes to streaming + completion events only | Add `AgentPausedEvent` subscription. Add sessionStore dependency. On pause: register interaction, send keyboard, bind resume handle |
| `Sources/AxionCLI/Commands/GatewayCommand.swift` (~585 lines) | Creates adapter, queue, registry, wires handlers | Create `TGInteractiveSessionStore`. Pass to TGEventHandler and TelegramAdapter. Wire resume path |

### Files Being Created (NEW)

| File | Purpose |
|------|---------|
| `Sources/AxionCLI/Services/Telegram/TGInteractiveSessionStore.swift` | Actor managing pending interactions (approval/confirm/clarify/text capture). In-memory only, TTL-based cleanup |
| `Sources/AxionCLI/Runtime/Events/AgentPausedEvent.swift` | Custom AgentEvent bridging SDK pause to EventBus |

### Key Design Decisions

1. **`AgentPausedEvent` is a custom Axion event** — SDK doesn't provide one. We create it and publish from AxionRuntime when detecting `.system(.paused)` in the SDK message stream. This is a thin bridge, not a SDK fork.

2. **`TGInteractiveSessionStore` is actor-isolated, in-memory only** — No persistence needed. Gateway restart invalidates all pending interactions. TTL (default 5 min / `gateway.telegramApprovalTTLSeconds`) auto-expires entries.

3. **Resume handles stored in `TaskSerialQueue`** — The queue owns the task group where the agent runs. Resume closures capture `agent.resume(context:)` and are keyed by `pendingId`. Cleanup happens when the task group child task finishes.

4. **`callback_data` encoding** — Format: `{action}:{scope}:{pendingId}`. Examples: `approve:once:abc123`, `deny::abc123`, `clarify:2:abc123`, `text::abc123`. Max 64 bytes (TG limit). `pendingId` should be short (8-12 chars hex).

5. **Text capture mode** — When user taps `Type Answer`, store marks chat as awaiting text. Next non-command text message from that chat is intercepted in `processMessage()` before command router or task enqueue, captured as resume context, and text capture mode is exited.

6. **Security: per-callback user validation** — `resolveCallback()` validates `fromUser` matches `allowedUserId` from registration. Cross-chat injection is prevented by checking `chatId` match.

7. **Keyboard message lifecycle** — On callback: (1) `answerCallbackQuery` to dismiss spinner, (2) `editMessageText` to update original message (remove buttons, show outcome), (3) `resumeInteraction` to unblock agent.

### Interaction Mode Definitions

```swift
enum TGInteractionMode: String, Codable, Sendable {
    case approval     // dangerous command: Allow Once / Session / Always / Deny
    case confirm      // slash command confirm: Approve Once / Always Approve / Cancel
    case clarify      // multi-choice: option buttons + Type Answer
    case textCapture  // waiting for free-text reply
}

enum TGInteractionResolution: Sendable {
    case resume(context: String)  // valid interaction, resume agent with context
    case expired                   // TTL exceeded
    case unauthorized              // wrong user
    case notFound                  // unknown pendingId
}
```

### Inline Keyboard Layouts

**Approval (dangerous command):**
```
[Allow Once] [Session] [Always]
[Deny]
```
callback_data: `approve:once:{id}`, `approve:session:{id}`, `approve:always:{id}`, `deny::{id}`

**Confirm (slash command):**
```
[Approve Once] [Always Approve]
[Cancel]
```
callback_data: `confirm:once:{id}`, `confirm:always:{id}`, `cancel::{id}`

**Clarify (multi-choice):**
```
[Option A]
[Option B]
[Option C]
[Type Answer]
```
callback_data: `clarify:0:{id}`, `clarify:1:{id}`, `clarify:2:{id}`, `text::{id}`

### Telegram API References

| API | Endpoint | Notes |
|-----|----------|-------|
| `answerCallbackQuery` | `POST /answerCallbackQuery` | `callback_query_id` (required), `text` (optional, 0-200 chars), `show_alert` (optional) |
| `sendMessage` with keyboard | `POST /sendMessage` | Add `reply_markup` field: `{"inline_keyboard": [[{"text": "...", "callback_data": "..."}]]}` |
| `editMessageText` with keyboard | `POST /editMessageText` | Same `reply_markup` field. Pass `reply_markup: {"inline_keyboard": []}` to remove buttons |

**TG limits:**
- `callback_data`: max 64 bytes
- `inline_keyboard` buttons per row: no hard limit, but 1-4 per row is practical
- `answerCallbackQuery` text: max 200 chars
- `setMyCommands`: max 100 commands (already implemented)

### AxionRuntime Pause Detection Point

The pause detection needs to happen where SDKMessages are consumed. In `AxionRuntime.execute()`:
1. The agent's `stream()` returns `AsyncStream<SDKMessage>`
2. The runtime processes each message (for output, cost tracking, etc.)
3. **Add:** When message is `.system(.paused, data)` where `data.pausedData != nil`, publish `AgentPausedEvent(reason: data.pausedData.reason, sessionId: data.sessionId)` to EventBus

This is a small addition to the existing message processing loop. No structural changes needed.

### Testing Standards

- **All tests use Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Mock `TGAPIClient`**: Extend existing `MockTGAPIClient` with `answerCallbackQuery` mock, `replyMarkup` support
- **Mock `TGInteractiveSessionStore`**: Create `MockTGInteractiveSessionStore` for testing handlers and adapter
- **Mock `TaskSerialQueue`**: Extend `MockTaskSerialQueue` with `registerResumeHandle` and `resumeInteraction` stubs
- **Never call real Telegram API** in unit tests
- **Never build real agent** in unit tests — mock the pause event and resume handle flow

### Previous Story Learnings

From Story 32.4:
1. **`_Concurrency.Task` required** — OpenAgentSDK has a `Task` name collision. Use `_Concurrency.Task` everywhere.
2. **Deferred wiring pattern** — Closures in `TaskSerialQueue.init()` use no-op defaults, then `updateReplyHandler`/`updateEditHandler` rewire after adapter creation. Same pattern for any new queue-related closures.
3. **Config wiring goes through `makeStreamingConfig()`** — If any new command needs config values, follow this pattern.
4. **`setMyCommands` must be called before `adapter.start()`** — Start is blocking (contains pollLoop). Discovered in review.
5. **`/commands` should iterate registry, not hardcode** — Discovered in review, commands handler must pull from registry dynamically.

From Story 32.2:
6. **Double formatting bug** — Controller should NOT format text; adapter handles formatting. Keep command response formatting in router/handler, not in adapter.
7. **`sendMessage` closure returns `Int64?`** — `replyHandler` returns message ID. New closures should follow established return type patterns.

From Story 32.1:
8. **`TGAPIError` four-category classification** — Already implemented. New API methods (`answerCallbackQuery`) should classify errors through the same `classifyHTTPError()` mechanism.
9. **Three-tier format fallback** — MarkdownV2 → HTML → PlainText. Keyboard messages should use same fallback chain.

### Project Structure Notes

- `TGInteractiveSessionStore.swift` goes in `Sources/AxionCLI/Services/Telegram/`
- `AgentPausedEvent.swift` goes in `Sources/AxionCLI/Runtime/Events/` (new directory, alongside existing handlers)
- New models added to existing `TGModels.swift`
- API client additions in existing `TGAPIClient.swift`
- No changes to AxionCore (no new config fields in this story; config extension is optional scope)
- No changes to AxionBar (TG-only)

### Scope Boundaries

**In scope:**
- Inline keyboard rendering for approval, confirm, clarify
- Callback query handling and resolution
- Text capture mode for free-text clarify
- Pause/resume bridge from SDK to EventBus
- `TGInteractiveSessionStore` for managing pending interactions

**Out of scope (deferred):**
- Config fields for approval TTL (use hardcoded default 300s for now; config extension is optional)
- Persisting interaction state across gateway restarts (in-memory is sufficient)
- Re-enabling `AskUserTool` globally (Epic decision #2: not in scope)
- Safety hook integration for tool-level approval (future enhancement)
- Cross-platform command abstraction (Epic decision #3: TG-only)

### References

- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#Story 32.5] — Full story spec with AC, callback model, session store design
- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#4 个决策] — Locked decisions: SDK pause/resume, no AskUser, TG-only registry, draft gate
- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#TG API 限流策略总览] — answerCallbackQuery: no explicit rate limit
- [Source: Sources/AxionCLI/Services/Telegram/TGModels.swift] — Current models (131 lines), need callback query + keyboard types
- [Source: Sources/AxionCLI/Services/Telegram/TGAPIClient.swift] — API client (272 lines), need answerCallbackQuery + replyMarkup
- [Source: Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift] — Adapter (277 lines), need callback + text capture handling
- [Source: Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift] — Queue (364 lines), need resume handle storage
- [Source: Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift] — Handler (115 lines), need pause event subscription
- [Source: OpenAgentSDK/Core/Agent.swift:420-450] — `pause(reason:)` / `resume(context:)` API
- [Source: OpenAgentSDK/Types/SDKMessage.swift:390-391] — `Subtype.paused` / `.pausedTimeout` (message stream, NOT EventBus)
- [Source: OpenAgentSDK/Types/AgentEventTypes.swift] — `AgentResumedEvent` (line 409) exists but `AgentPausedEvent` does NOT
- [Source: OpenAgentSDK/Tools/Core/PauseForHumanTool.swift] — pause_for_human tool implementation

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List

**New Files:**
- `Sources/AxionCLI/Services/Telegram/TGInteractiveSessionStore.swift` — Session store actor with TGCallbackData encoding, keyboard building, resolveCallback security
- `Sources/AxionCLI/Services/Events/AgentPausedEvent.swift` — Custom AgentEvent bridging SDK pause to EventBus
- `Tests/AxionCLITests/Services/Telegram/TGInteractiveSessionStoreTests.swift` — Tests for callback data, register/resume, resolveCallback, keyboard layouts
- `Tests/AxionCLITests/Services/Events/AgentPausedEventTests.swift` — Round-trip and encoding tests

**Modified Files:**
- `Sources/AxionCLI/Services/Telegram/TGModels.swift` — Added TGCallbackQuery, TGInlineKeyboardMarkup, TGInlineKeyboardButton, TGAnswerCallbackQueryRequest
- `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` — Added answerCallbackQuery, sendMessage with replyMarkup, editMessageText with replyMarkup
- `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` — Added processCallback with approve/deny/confirm/cancel/skip/respond/clarify handling, text capture mode
- `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` — Added AgentPausedEvent subscription, handlePaused with keyboard, allowedUserId
- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` — Added activeResumeHandles, registerResumeHandle, resumeInteraction, allowedUserId wiring
- `Sources/AxionCLI/Commands/GatewayCommand.swift` — Creates TGInteractiveSessionStore, wires to adapter and handler
- `Sources/AxionCLI/Services/RunOrchestrator.swift` — Publishes AgentPausedEvent on SDK pause, registers resume handle
- `Sources/AxionCLI/Services/AxionRuntime.swift` — RunOverrides with nonInteractivePause and registerResumeHandle
- `Tests/AxionCLITests/Services/Telegram/TGModelsTests.swift` — Callback query, inline keyboard, edit message, answer callback query tests
- `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift` — Mock with answerCallbackQuery, sendMessage/editMessage with markup
- `Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift` — Subscribed types include AgentPausedEvent
- `Tests/AxionCLITests/Services/Telegram/TelegramAdapterTests.swift` — MockTaskSerialQueue with resumeInteraction
- `Tests/AxionCLITests/Services/AxionRuntimeTests.swift` — RunOverrides includes nonInteractivePause and registerResumeHandle
