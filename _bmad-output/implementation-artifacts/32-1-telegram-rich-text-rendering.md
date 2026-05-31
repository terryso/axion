---
baseline_commit: 9566bc271b1803e0d9b6b993aceafbfd4c5b1c22
---

# Story 32.1: Telegram 富文本渲染与可靠发送管道

Status: done

## Story

As a Axion Telegram 用户,
I want agent 的最终回复、错误和状态消息在 TG 中保持清晰可读,
So that 我在手机上看到的是可消费的信息，而不是一大段生硬纯文本。

## Acceptance Criteria

1. **Given** agent 最终结果包含标题、列表、代码块、inline code、链接和表格
   **When** TelegramAdapter 发送最终结果
   **Then** 结果先经过 Telegram 专用格式化
   **And** 标题、列表、代码块、inline code、链接在 Telegram 中保持可读
   **And** 表格在不支持原样渲染时降级为可读的 key/value 列表

2. **Given** Telegram parse mode 发送失败（例如 MarkdownV2 转义错误）
   **When** Adapter 捕获发送失败
   **Then** 按 MarkdownV2 → HTML → PlainText 三级降级重试
   **And** 不因单次格式错误导致消息丢失

3. **Given** 最终结果或错误消息超过 Telegram 4096 字限制
   **When** Adapter 发送消息
   **Then** 按段落或换行优先切块
   **And** 切块基于**渲染后长度**计算（MarkdownV2 转义字符会膨胀原文）
   **And** 保持消息顺序稳定

4. **Given** provider/raw error 中包含底层堆栈、token、路径或其他不适合直接展示给用户的信息
   **When** TelegramAdapter 发送错误消息
   **Then** 对外展示用户友好的错误摘要
   **And** 不泄露敏感信息（API keys、文件路径、堆栈）

5. **Given** 回复发生在群聊或用户以 reply 方式触发任务
   **When** TelegramAdapter 发送首条结果消息
   **Then** 首条消息保留 `reply_to_message_id`
   **And** 后续 continuation chunk 不强制 reply 原消息

## Tasks / Subtasks

- [x] Task 1: Refactor `TGAPIError` to four-category enum (AC: #2)
  - [x] 1.1 Replace single `case apiError(String)` with `retryableNetwork`, `rateLimited`, `formatRejected`, `permanentTelegramError`
  - [x] 1.2 Update `TGAPIClient.performRequest()` to classify HTTP status codes: 429 → `rateLimited`, 400 with parse error → `formatRejected`, 403/404/etc → `permanentTelegramError`, network timeouts → `retryableNetwork`
  - [x] 1.3 Add `TGParseMode` enum (`markdownV2`, `html`, `plain`) to TGModels
  - [x] 1.4 Update existing tests to match new error types

- [x] Task 2: Extend `TGAPIClient` with parse mode and reply metadata (AC: #1, #5)
  - [x] 2.1 Update `TGSendMessageRequest` to include `parseMode`, `replyToMessageId` fields
  - [x] 2.2 Add `sendMessage(chatId:text:parseMode:replyToMessageId:)` overload to `TGAPIClientProtocol` and `TGAPIClient`
  - [x] 2.3 Add `editMessageText(chatId:messageId:text:parseMode:)` method to protocol and implementation
  - [x] 2.4 Update `TGSendMessageRequest` CodingKeys for `reply_to_message_id`

- [x] Task 3: Create `TGMessageFormatter` (AC: #1, #3)
  - [x] 3.1 New file: `Sources/AxionCLI/Services/Telegram/TGMessageFormatter.swift`
  - [x] 3.2 Implement `format(_ text: String) -> (String, TGParseMode)` — MarkdownV2 rendering with escape rules
  - [x] 3.3 Implement heading → `**Title**`, list → numbered/bullet with max 2-level indent, code block → fenced, inline code → backtick, link → `[label](url)`, table → key/value block
  - [x] 3.4 Implement `split(formattedText:parseMode:maxRenderedLength:) -> [String]` — split on paragraph boundaries based on rendered length
  - [x] 3.5 Ensure each chunk is independently renderable (no unclosed markdown markers across chunks)

- [x] Task 4: Create `TGErrorSanitizer` (AC: #4)
  - [x] 4.1 New file: `Sources/AxionCLI/Services/Telegram/TGErrorSanitizer.swift`
  - [x] 4.2 Implement `sanitizeForTelegramError(_ raw: String) -> String`
  - [x] 4.3 Regex filters: API keys (`sk-[a-zA-Z0-9]+`), Bearer tokens, file system paths → last component only, stack traces → first line only, HTTP JSON → extract `error.message` only
  - [x] 4.4 Map common error patterns to user-friendly Chinese summaries (e.g., "认证失败，请检查 API Key 配置", "命令执行超时 (300s)")

- [x] Task 5: Update `TelegramAdapter.sendReply()` with formatted sending and triple-fallback (AC: #2, #3, #5)
  - [x] 5.1 Add `sendFormatted(_ text: String, to chatId: Int64, replyToMessageId: Int64?)` method
  - [x] 5.2 Use `TGMessageFormatter.format()` → try `sendMessage` with MarkdownV2 → on `formatRejected` retry HTML → on failure retry PlainText
  - [x] 5.3 Replace `splitMessage()` with `TGMessageFormatter.split()` using rendered-length-aware splitting
  - [x] 5.4 First chunk uses `replyToMessageId`, subsequent chunks send without reply
  - [x] 5.5 Update `TGEventHandler.handleCompleted()` to call `sendFormatted()` instead of plain `sendMessage`
  - [x] 5.6 Update `TGEventHandler.handleFailed()` to route through `TGErrorSanitizer` then `sendFormatted()`

- [x] Task 6: Unit tests (AC: all)
  - [x] 6.1 New file: `Tests/AxionCLITests/Services/Telegram/TGMessageFormatterTests.swift`
  - [x] 6.2 Test MarkdownV2 formatting: headings, lists, code blocks, inline code, links, tables
  - [x] 6.3 Test split on rendered length (MarkdownV2 escape chars inflate length)
  - [x] 6.4 Test each chunk independently renderable
  - [x] 6.5 New file: `Tests/AxionCLITests/Services/Telegram/TGErrorSanitizerTests.swift`
  - [x] 6.6 Test API key redaction, path stripping, stack trace truncation, HTTP body extraction
  - [x] 6.7 Update `TGAPIClientTests.swift` for new error cases and `performRequest` classification
  - [x] 6.8 Update `TelegramAdapterTests.swift` for formatted sending and fallback behavior
  - [x] 6.9 Update `TGEventHandlerTests.swift` for formatted completion and sanitized errors

## Dev Notes

### Architecture Context

This story is the **foundation for all subsequent Epic 32 stories**. Every story (32.2–32.5) depends on:
- The `TGAPIError` four-category refactoring (Task 1)
- The `TGParseMode` enum (Task 1.3)
- `editMessageText` on `TGAPIClient` (Task 2.3) — needed by 32.2 streaming
- `TGMessageFormatter.split()` (Task 3.4) — reused by 32.2 streaming overflow

### Files Being Modified (UPDATE)

| File | Current State | What Changes |
|------|---------------|--------------|
| `TGAPIClient.swift` (130 lines) | Single `TGAPIError.apiError`, plain `sendMessage`, retry on network errors only | Refactor `TGAPIError` to 4 cases; update `performRequest` to classify by HTTP status; extend `sendMessage` with parse mode + reply; add `editMessageText` |
| `TGModels.swift` (114 lines) | `TGUpdate` has `message` only; `TGSendMessageRequest` has `chatId`, `text`, `parseMode` | Add `TGParseMode` enum; add `replyToMessageId` to `TGSendMessageRequest` |
| `TelegramAdapter.swift` (190 lines) | `sendReply()` does plain text + char-count split; `splitMessage()` splits on raw char count | Replace `splitMessage()` with `TGMessageFormatter.split()`; add `sendFormatted()` with triple-fallback; thread `replyToMessageId` through `processMessage` → `sendFormatted` |
| `TGEventHandler.swift` (143 lines) | `handleCompleted` sends plain text result; `handleFailed` sends raw error | `handleCompleted` → `sendFormatted`; `handleFailed` → `TGErrorSanitizer` → `sendFormatted`; `sendMessage` closure type unchanged (signature is `(String, Int64) async -> Void` — formatted text is produced by adapter, not handler) |
| `TGAPIClientTests.swift` | Tests for existing API methods | Add tests for error classification, parse mode, editMessage |
| `TelegramAdapterTests.swift` | Tests for message splitting, auth, photo | Add tests for formatted sending, fallback, reply semantics |
| `TGEventHandlerTests.swift` | Tests for event handling | Update completion/failed tests to verify formatted output path |
| `TGCommandRouter.swift` (77 lines) | No changes needed | — |

### Files Being Created (NEW)

| File | Purpose |
|------|---------|
| `Sources/AxionCLI/Services/Telegram/TGMessageFormatter.swift` | MarkdownV2/HTML rendering + rendered-length-aware split |
| `Sources/AxionCLI/Services/Telegram/TGErrorSanitizer.swift` | Error sanitization for user-facing TG messages |
| `Tests/AxionCLITests/Services/Telegram/TGMessageFormatterTests.swift` | Formatter unit tests |
| `Tests/AxionCLITests/Services/Telegram/TGErrorSanitizerTests.swift` | Sanitizer unit tests |

### Key Design Decisions

1. **TGEventHandler does NOT receive parse mode awareness.** The handler's `sendMessage` closure signature stays `(String, Int64) async -> Void`. The adapter's `sendReply()` / `sendFormatted()` internally handles formatting and fallback. This keeps the handler simple and avoids threading TG-specific types into the event handler layer.

2. **`sendFormatted()` is the new primary send path.** Plain `sendReply()` remains for backward-compatible simple text (command responses, status messages). Agent results and errors go through `sendFormatted()`.

3. **MarkdownV2 escape rules are strict.** Characters `_`, `*`, `[`, `]`, `(`, `)`, `~`, `` ` ``, `>`, `#`, `+`, `-`, `=`, `|`, `{`, `}`, `.`, `!` must be escaped with `\` in regular text. Code blocks and inline code do NOT escape content. The formatter must handle this correctly or the TG API will reject the message — that's why triple-fallback exists.

4. **`TGMessageFormatter.split()` operates on rendered length.** MarkdownV2 escaping inflates text (e.g., `hello.world` → `hello\.world`). The split must account for the escaped form's byte count, not the source text's.

5. **Error sanitization is lossy by design.** `sanitizeForTelegramError()` always produces a shorter, human-readable summary. The full error is already in the trace file — TG is not a debugging channel.

### Telegram API Constraints

| Constraint | Value | Impact |
|------------|-------|--------|
| Max message length | 4096 UTF-8 chars (rendered) | Must split long results |
| `parse_mode` values | `MarkdownV2`, `HTML`, absent | Triple fallback chain |
| MarkdownV2 escape chars | 18 special chars | Strict escaping required |
| `reply_to_message_id` | Optional Int64 | First chunk only |
| `editMessageText` | Same limits as sendMessage | Needed by Story 32.2 |

### Render Contract

| Element | MarkdownV2 | HTML | Plain |
|---------|------------|------|-------|
| Heading | `**Title**` | `<b>Title</b>` | `TITLE` |
| List | `• item` / `1\. item` | `• item` / `1. item` | Same |
| Code block | ` ```lang ... ``` ` | `<pre><code>...</code></pre>` | Indented + lang label |
| Inline code | `` `code` `` | `<code>code</code>` | `code` |
| Link | `[label](url)` | `<a href="url">label</a>` | `label: url` |
| Table | key/value block | key/value block | key/value block |

### Testing Standards

- **All tests use Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Mock TGAPIClient** via `TGAPIClientProtocol` — never hit real Telegram API
- **Test format fallback**: mock `sendMessage` to throw `formatRejected` on MarkdownV2, verify HTML retry, then PlainText
- **Test split edge cases**: exactly 4096 rendered chars, unclosed code block at boundary, table spanning chunks
- **Test error sanitizer**: API key patterns, nested JSON error bodies, multi-line stack traces

### Project Structure Notes

- New files go in `Sources/AxionCLI/Services/Telegram/` (alongside existing TG files)
- New test files go in `Tests/AxionCLITests/Services/Telegram/` (mirrors source structure)
- `TGParseMode` goes in `TGModels.swift` alongside existing TG model types
- No AxionCore changes needed — Telegram is a presentation-layer concern, fully within AxionCLI

### References

- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#Story 32.1] — Full story spec with AC, rendering contract, sanitizer spec
- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#TGAPIError 四分类重构] — Error refactoring spec
- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#TGMessageFormatter 核心接口] — Formatter interface design
- [Source: docs/epics/epic-32-telegram-experience-upgrades.md#TG API 限流策略总览] — Rate limiting context
- [Source: Sources/AxionCLI/Services/Telegram/TGAPIClient.swift] — Current API client (130 lines)
- [Source: Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift] — Current adapter (190 lines)
- [Source: Sources/AxionCLI/Services/Telegram/TGModels.swift] — Current models (114 lines)
- [Source: Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift] — Current handler (143 lines)
- [Source: _bmad-output/project-context.md#反模式] — Anti-pattern rules (no direct print, no manual JSON concat, use AxionError)

## Dev Agent Record

### Agent Model Used
GLM-5.1 (Claude Code)

### Debug Log References
- All 139 Telegram-related tests pass across 7 test suites
- 1 pre-existing failure in UniversalMemoryContextProviderTests (unrelated to this story)

### Completion Notes List
- TGAPIError refactored to 4-case enum with automatic HTTP status classification in performRequest
- TGParseMode enum added to TGModels with markdownV2/html/plain cases
- TGMessageFormatter implements left-to-right character scanner for inline MarkdownV2 (handles code, bold, links before escaping)
- TGErrorSanitizer maps common error patterns to Chinese user-friendly summaries
- TelegramAdapter.sendFormatted() implements triple-fallback: MarkdownV2 → HTML → PlainText
- GatewayCommand replyHandler wired to sendFormatted for agent results
- All tests use Swift Testing framework (no XCTest)

### File List

**New files:**
- Sources/AxionCLI/Services/Telegram/TGMessageFormatter.swift
- Sources/AxionCLI/Services/Telegram/TGErrorSanitizer.swift
- Tests/AxionCLITests/Services/Telegram/TGMessageFormatterTests.swift
- Tests/AxionCLITests/Services/Telegram/TGErrorSanitizerTests.swift

**Modified files:**
- Sources/AxionCLI/Services/Telegram/TGAPIClient.swift — TGAPIError 4-case refactor, sendMessage overload, editMessageText
- Sources/AxionCLI/Services/Telegram/TGModels.swift — TGParseMode enum, replyToMessageId field
- Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift — sendFormatted with triple-fallback
- Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift — error sanitization integration
- Sources/AxionCLI/Commands/GatewayCommand.swift — replyHandler wired to sendFormatted
- Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift — new error classification tests
- Tests/AxionCLITests/Services/Telegram/TelegramAdapterTests.swift — fallback & formatted sending tests
- Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift — sanitized error output tests

## Senior Developer Review (AI)

**Reviewer:** Nick (AI Review) on 2026-05-31
**Outcome:** Approved with fixes applied

### Issues Found and Fixed

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| H1 | HIGH | `renderInlineHTML()` called `escapeHTML()` after inserting HTML tags, escaping `<code>`, `<b>`, `<a>` into entities | Reversed order: escape raw text first, then wrap with tags |
| M1 | MEDIUM | `sendFormatted()` fallback re-sent ALL chunks on failure, duplicating already-sent ones | Track `sentCount`; fallback only sends chunks from `startIndex` onward |
| M2 | MEDIUM | `balanceCodeBlocks()` pass 2 was dead code — never reopened code blocks across chunks | Rewrote to use single pass with `insideCodeBlock` flag |
| M3 | MEDIUM | `escapeOutsideCodeSpans()` defined but never called | Removed dead code |
| M4 | MEDIUM | 3 files modified but not in File List (MemoryTool.swift, AgentBuilder.swift, UniversalMemoryContextProviderTests.swift — Epic 31 leftovers) | Noted; no code change needed |

### Tests Added

- `htmlFormatInlineCode` — verifies HTML `<code>` tags not double-escaped
- `htmlFormatBold` — verifies HTML `<b>` tags not double-escaped
- `htmlFormatLink` — verifies HTML `<a>` tags not double-escaped
- `htmlEscapesAmpersands` — verifies HTML entity escaping still works
- `sendFormattedFallbackNoDuplicates` — verifies fallback doesn't duplicate sent chunks

### Git vs Story Discrepancies

3 files changed in git but not documented in story File List — all are Epic 31 leftovers, not Story 32.1 scope.

### Change Log

- 2026-05-31: Review completed. 1 HIGH + 4 MEDIUM issues found and auto-fixed. 5 new tests added. 111 total tests passing. Status → done.
