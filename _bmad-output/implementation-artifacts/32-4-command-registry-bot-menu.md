---
baseline_commit: d339fcd
---

# Story 32.4: Command Registry, Help Output & Bot Menu

Status: done

## Story

As a Axion Telegram user,
I want TG commands to be discoverable and extensible alongside Gateway capabilities,
So that I don't need to memorize all commands, and the Bot menu stays in sync.

## Acceptance Criteria

1. **Given** TelegramAdapter starts successfully
   **When** initializing the command system
   **Then** a `TGCommandRegistry` is built with Telegram command metadata
   **And** at least supports `/help`, `/commands`, `/status`, `/skills`, `/new`, `/queue`
   **And** the registry syncs high-priority commands to Telegram via `setMyCommands`

2. **Given** user sends `/help`
   **When** TGCommandRouter processes the command
   **Then** returns concise getting-started help
   **And** explains that plain text messages are treated as tasks
   **And** command names comply with Telegram naming rules (lowercase, underscores, max 32 chars)

3. **Given** user sends `/commands`
   **When** Router processes the command
   **Then** returns full command list with one-line description per command
   **And** long output is automatically split into chunks (reuse TGMessageFormatter.split)

4. **Given** user sends `/queue`
   **When** a task is executing or queue is non-empty for that chat
   **Then** replies with the chat's execution status, queue length, and session reuse info

5. **Given** Telegram command contains `@botname` suffix, mixed case, or registry internal command with `-`
   **When** Router normalizes the command
   **Then** correctly identifies the command
   **And** Telegram menu display uses Bot API allowed lowercase/underscore naming

6. **Given** Bot starts or command set changes
   **When** Adapter calls Telegram Bot API
   **Then** syncs high-frequency commands to `setMyCommands` menu
   **And** trims to 100 commands by priority when limit exceeded

## Tasks / Subtasks

- [x] Task 1: Create `TGCommandRegistry` (AC: #1, #2, #3, #5)
  - [x] 1.1 Create `Sources/AxionCLI/Services/Telegram/TGCommandRegistry.swift` with `TGCommandDef` and `TGCommandRegistry` types
  - [x] 1.2 `TGCommandDef` struct: `name` (no slash), `description`, `helpText`, `menuPriority`, `handler` closure
  - [x] 1.3 `TGCommandRegistry` struct (Sendable): `register()`, `resolve()`, `allCommands()`, `menuCommands(limit:)`
  - [x] 1.4 `resolve()` normalizes input: strip leading `/`, strip `@botname`, lowercase, map `-` to `_`
  - [x] 1.5 Unit tests for registry: register, resolve with normalization, menuCommands ordering/priority

- [x] Task 2: Refactor `TGCommandRouter` to use registry (AC: #1, #2, #3, #4)
  - [x] 2.1 Replace hardcoded switch with `TGCommandRegistry`-driven dispatch
  - [x] 2.2 Router init takes `TGCommandRegistry` instead of individual provider closures
  - [x] 2.3 Default case uses registry to suggest closest match or list available commands
  - [x] 2.4 Register `/help` handler: return getting-started text with task explanation
  - [x] 2.5 Register `/commands` handler: return full list with one-line descriptions
  - [x] 2.6 Register `/status` handler: reuse existing `formatStatus()` logic
  - [x] 2.7 Register `/skills` handler: reuse existing `formatSkills()` logic
  - [x] 2.8 Register `/new` handler: clear session + confirm
  - [x] 2.9 Register `/queue` handler: query per-chat queue status from TaskSerialQueue
  - [x] 2.10 Unit tests for router: command dispatch, normalization, unknown command fallback

- [x] Task 3: Add `setMyCommands` to `TGAPIClient` (AC: #1, #6)
  - [x] 3.1 Add `setMyCommands(commands: [(name: String, description: String)]) async throws` to `TGAPIClient`
  - [x] 3.2 Add method to `TGAPIClientProtocol`
  - [x] 3.3 Add mock support in tests
  - [x] 3.4 Unit test for `setMyCommands` API call

- [x] Task 4: Expose per-chat queue status from `TaskSerialQueue` (AC: #4)
  - [x] 4.1 Add `pendingCount(chatId:) -> Int` method: count pending tasks for specific chat
  - [x] 4.2 Add `isProcessing(chatId:) -> Bool` method: check if currently executing for specific chat
  - [x] 4.3 Add `hasActiveSession(chatId:) -> Bool` method: check if chat has a session in `chatSessions`
  - [x] 4.4 Unit tests for per-chat status methods

- [x] Task 5: Wire registry + bot menu sync in `GatewayCommand` (AC: #1, #6)
  - [x] 5.1 Build `TGCommandRegistry` with all handlers, inject status/skills/queue/clearSession providers
  - [x] 5.2 Pass registry to `TGCommandRouter` init
  - [x] 5.3 After adapter creation, call `setMyCommands` with `registry.menuCommands()`
  - [x] 5.4 Integrate with `TelegramAdapter.start()` or immediately after adapter init
  - [x] 5.5 Unit test verifying registry construction and menu command extraction

- [x] Task 6: Integration verification (AC: all)
  - [x] 6.1 Verify all 6 commands return correct responses via router unit tests
  - [x] 6.2 Verify `@botname` suffix stripping works
  - [x] 6.3 Verify `/QUEUE` and `/Status` (case-insensitive) work
  - [x] 6.4 Verify unknown `/unknown` command returns helpful message

## Dev Notes

### Architecture Context

This story replaces the hardcoded 3-command switch in `TGCommandRouter` with a registry pattern. The registry is Telegram-specific (per locked decision #3 from Epic 32) — it does NOT attempt to unify CLI/MCP/Telegram commands.

**Key relationships to existing code:**

- `TGCommandRouter` (77 lines) → complete rewrite, replacing switch with registry dispatch
- `TGCommandRegistry` → NEW file, self-contained registry struct
- `TGAPIClient` → add `setMyCommands` method (follows existing pattern of other API methods)
- `TaskSerialQueue` → add 3 per-chat query methods (existing `pendingCount` and `isProcessing` are global)
- `GatewayCommand` → change how `TGCommandRouter` is constructed (from closure injection to registry injection)
- `TelegramAdapter` → minimal changes; only if `setMyCommands` call needs to go through adapter

### Files Being Modified (UPDATE)

| File | Current State | What Changes |
|------|---------------|--------------|
| `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift` (77 lines) | Hardcoded switch for `/status`, `/skills`, `/new`. Default returns "未知命令。可用命令：/status, /skills, /new" | Replace switch with registry-driven dispatch. Init takes `TGCommandRegistry`. Retain `handle()` API. Remove `StatusProvider`/`SkillsProvider`/`ClearSession` typealias closures — handlers come from registry |
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` (~260 lines) | Has `getUpdates`, `sendMessage`, `editMessageText`, `getFile`, `downloadFile`, `sendChatAction` | Add `setMyCommands(commands:)` method. Add to `TGAPIClientProtocol`. Simple POST to `/setMyCommands` |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` (~335 lines) | Has `pendingCount` (total) and `isProcessing` (global). `chatSessions: [Int64: ActiveSession]` dict tracks per-chat sessions | Add `pendingCount(chatId:)`, `isProcessing(chatId:)`, `hasActiveSession(chatId:)` per-chat query methods. Add to `TaskSerialQueueProtocol` |
| `Sources/AxionCLI/Commands/GatewayCommand.swift` (~585 lines) | Creates `TGCommandRouter` with 3 closures (statusProvider, skillsProvider, clearSession). Wires adapter. Starts task queue + adapter | Build `TGCommandRegistry` with all command handlers. Create `TGCommandRouter` with registry. After adapter start, call `setMyCommands` via apiClient |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` (~277 lines) | Takes `commandRouter` in init. `processMessage` calls `commandRouter?.handle()` | Possibly add `syncBotMenu()` method that calls `apiClient.setMyCommands()`. Or keep it in GatewayCommand. Minimal change expected |

### Files Being Created (NEW)

| File | Purpose |
|------|---------|
| `Sources/AxionCLI/Services/Telegram/TGCommandRegistry.swift` | Command metadata registry. `TGCommandDef` + `TGCommandRegistry` structs. ~80 lines |

### Key Design Decisions

1. **`TGCommandRegistry` is a value type (`struct`, Sendable)** — not an actor. Registry is built once at startup and never mutated after. All handlers are `@Sendable` closures. This keeps it simple and avoids actor overhead for a static lookup.

2. **Command name normalization in `resolve()`** — Input like `/Status@mybot`, `/STATUS`, `/help` all resolve. Algorithm: strip leading `/`, split on `@` and take first part, lowercase, replace `-` with `_`. Registry stores names without `/` prefix and in lowercase+underscore form.

3. **Handler closure captures providers** — Each `TGCommandDef.handler` is `@Sendable (Int64) async -> String`. The closures capture `statusProvider`, `skillsProvider`, etc. This keeps `TGCommandRegistry` unaware of provider details — it's pure routing metadata.

4. **`/queue` requires per-chat status** — Current `TaskSerialQueue.pendingCount` and `isProcessing` are global aggregates. `/queue` needs per-chatId variants to tell the user "your queue position" not "total system queue". Add `pendingCount(chatId:)`, `isProcessing(chatId:)`, `hasActiveSession(chatId:)` as separate methods on `TaskSerialQueueProtocol`.

5. **`setMyCommands` called once at startup** — Not on every poll loop iteration. Commands don't change at runtime. If commands are added/removed dynamically in future, a separate re-sync mechanism would be needed (out of scope for this story).

6. **Bot menu trimming by `menuPriority`** — `TGCommandDef.menuPriority` controls order in `setMyCommands`. Lower = shown first. If more than 100 commands (TG limit), `menuCommands(limit: 100)` trims by priority. Current 6 commands are well within limit.

7. **`/help` and `/commands` are distinct** — `/help` is a getting-started guide (what is this bot, how to use it). `/commands` is a terse list of all commands with one-line descriptions. Both are registered as separate commands in the registry.

8. **`TGCommandRouter` becomes thin** — After registry, `handle()` just does: normalize input → `registry.resolve()` → call handler → return result. Default case returns list of available commands instead of hardcoded string.

### Command Definitions

| Command | name | description | helpText | menuPriority |
|---------|------|-------------|----------|-------------|
| `/help` | `help` | "入门指南" | "Axion 是一个桌面自动化助手。\n\n直接发送文本即可执行任务。\n\n可用命令:\n/commands — 查看所有命令\n/status — 查看网关状态\n/skills — 查看技能列表\n/new — 开始新会话\n/queue — 查看任务队列" | 1 |
| `/commands` | `commands` | "查看所有命令" | "列出所有可用命令及其说明。" | 2 |
| `/status` | `status` | "查看网关状态" | "显示 Gateway 运行状态、运行时长、TG 连接状态和可用技能数。" | 3 |
| `/skills` | `skills` | "查看技能列表" | "列出所有已注册的技能名称和说明。" | 4 |
| `/new` | `new` | "开始新会话" | "清除当前会话上下文，下一次任务将从全新会话开始。" | 5 |
| `/queue` | `queue` | "查看任务队列" | "显示当前 chat 的任务执行状态、队列长度和会话复用情况。" | 6 |

### Telegram `setMyCommands` API

- Endpoint: `POST https://api.telegram.org/bot{token}/setMyCommands`
- Body: `{"commands": [{"command": "status", "description": "查看网关状态"}, ...]}`
- Max 100 commands per scope
- Command name: 1-32 chars, lowercase letters, digits, underscores
- Description: 1-256 chars
- Scope default: all private chats

### TaskSerialQueue Per-Chat Methods

```swift
// Add to TaskSerialQueueProtocol
func pendingCount(chatId: Int64) async -> Int
func isProcessing(chatId: Int64) async -> Bool
func hasActiveSession(chatId: Int64) async -> Bool
```

Implementation in `TaskSerialQueue`:
- `pendingCount(chatId:)`: filter `queue.filter { $0.chatId == chatId }.count`
- `isProcessing(chatId:)`: `isExecuting && currentTask?.chatId == chatId` (need to track current task's chatId)
- `hasActiveSession(chatId:)`: `chatSessions[chatId] != nil`

Note: `isProcessing(chatId:)` needs a new stored property `currentChatId: Int64?` to track which chat the active task belongs to. Set it when dequeuing, clear it when task finishes.

### Testing Standards

- **All tests use Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Mock `TGAPIClient`**: Already has `MockTGAPIClient` in test target. Add `setMyCommands` mock.
- **Registry tests**: Test registration, resolution with normalization, menuCommands ordering.
- **Router tests**: Test dispatch to correct handler, unknown command fallback, case insensitivity.
- **Per-chat status tests**: Test `pendingCount(chatId:)`, `isProcessing(chatId:)`, `hasActiveSession(chatId:)` with multiple chats.
- **Never call real Telegram API** in unit tests.

### Previous Story Learnings

From Story 32.3:
1. **`_Concurrency.Task` required** — OpenAgentSDK has a `Task` name collision. Use `_Concurrency.Task` everywhere.
2. **Deferred wiring pattern** — Closures in `TaskSerialQueue.init()` use no-op defaults, then `updateReplyHandler`/`updateEditHandler`/`updateChatActionHandler` rewire after adapter creation. Same pattern for any new queue-related closures.
3. **Config wiring goes through `makeStreamingConfig()`** — If any new command needs config values, follow this pattern.

From Story 32.2:
4. **Double formatting bug** — Controller should NOT format text; adapter handles formatting. Keep command response formatting in router/handler, not in adapter.
5. **`sendMessage` closure must return `Int64?`** — `replyHandler` returns message ID. New closures for `/queue` handler should follow established return type patterns.

### Project Structure Notes

- `TGCommandRegistry.swift` goes in `Sources/AxionCLI/Services/Telegram/` — alongside other TG service files
- Registry is a struct, not an actor — built once at startup, immutable after construction
- Router remains in same file (`TGCommandRouter.swift`) — just rewritten internally
- No changes to AxionCore models needed (no new config fields)
- No changes to AxionBar (this is TG-only)

### References

- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#Story 32.4] — Full story spec with AC, registry interface, command definitions
- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#命令注册表边界] — Registry scope boundary (Telegram-only, not cross-platform)
- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#TG API 限流策略总览] — setMyCommands rate limit docs
- [Source: Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift] — Current hardcoded router (77 lines, complete rewrite)
- [Source: Sources/AxionCLI/Services/Telegram/TGAPIClient.swift] — API client, needs setMyCommands
- [Source: Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift] — Queue, needs per-chat status methods
- [Source: Sources/AxionCLI/Commands/GatewayCommand.swift] — Gateway wiring, builds command router and adapter
- [Source: Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift] — Adapter, processMessage dispatches to command router

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7

### Debug Log References

- GatewayCommand compilation: old 3-arg TGCommandRouter init replaced by registry init → resolved with `buildCommandRegistry()` static helper
- `Skill` type ambiguity: two `Skill` types (OpenAgentSDK vs AxionCore) → disambiguated with `OpenAgentSDK.Skill`
- MockTaskSerialQueue: new protocol methods not in mock → added stubs for per-chat methods
- MockTGAPIClient variants: `setMyCommands` not in fallback mocks → added to all mock types
- TelegramAdapter test assertion: mock handler returned minimal text → updated to return full status text matching assertion

### Completion Notes List

- All 6 tasks implemented with 1705 unit tests passing (0 regressions)
- `TGCommandRegistry` is a Sendable struct, built once at startup, immutable after construction
- `TGCommandRouter` completely rewritten: thin dispatch layer using registry resolution
- 6 commands registered: help, commands, status, skills, new, queue
- `setMyCommands` syncs bot menu after adapter start
- Per-chat queue status methods added to `TaskSerialQueue` with `currentChatId` tracking
- All tests use Swift Testing framework (no XCTest)

### File List

| File | Change |
|------|--------|
| `Sources/AxionCLI/Services/Telegram/TGCommandRegistry.swift` | NEW — TGCommandDef + TGCommandRegistry structs (~100 lines) |
| `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift` | REWRITTEN — registry-driven dispatch replacing hardcoded switch |
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` | MODIFIED — added `setMyCommands` to protocol and implementation |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | MODIFIED — added per-chat status methods + `currentChatId` tracking |
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | MODIFIED — added `buildCommandRegistry()`, `formatStatus()`, `formatSkills()`, bot menu sync |
| `Tests/AxionCLITests/Services/Telegram/TGCommandRegistryTests.swift` | NEW — 12 tests for registry |
| `Tests/AxionCLITests/Services/Telegram/TGCommandRouterTests.swift` | REWRITTEN — registry-based router tests |
| `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift` | MODIFIED — added setMyCommands tests + MockRecordingURLSession |
| `Tests/AxionCLITests/Services/Telegram/TelegramAdapterTests.swift` | MODIFIED — updated to registry-based router, added per-chat stubs |
| `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` | MODIFIED — added 3 per-chat status tests |

### Change Log

- 2026-05-31: Story 32.4 implemented — Command Registry, Help Output & Bot Menu. Added TGCommandRegistry pattern, rewrote TGCommandRouter, added setMyCommands API, per-chat queue status, and wired everything in GatewayCommand. All 1705 unit tests pass.
- 2026-05-31: Senior Developer Review (AI) — 5 issues found, 4 auto-fixed.
  - **CRITICAL fixed**: `setMyCommands` was placed after `adapter.start()` (blocking poll loop), so bot menu was never synced. Moved to separate concurrent task before `start()`.
  - **HIGH fixed**: `/commands` handler hardcoded command list — refactored to iterate actual `TGCommandDef` array from registry.
  - **MEDIUM fixed**: `MockTaskSerialQueue.hasActiveSession` always returned `false` — now tracks active sessions per chatId.
  - **MEDIUM fixed**: `TGCommandRegistry.init` silently overwrote duplicate names — now logs warning to stderr.
  - LOW: `menuCommands` filter for `menuPriority > 0` — noted but acceptable behavior.
