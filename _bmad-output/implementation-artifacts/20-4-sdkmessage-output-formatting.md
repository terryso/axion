# Story 20.4: SDKMessage 输出格式化协议

Status: done

## Story

As an SDK developer,
I want the SDK to provide a structured SDKMessage output formatting protocol,
so that all Agent projects can easily convert SDK message streams into terminal output, JSON output, or custom formats.

## Acceptance Criteria

1. **AC1: `SDKMessageOutputHandler` protocol** — Given `SDKMessageOutputHandler`, when defined, it is a public protocol in `Types/` with `handle(_ message: SDKMessage)` method. Includes `displayRunStart(runId:task:)` called at run start and `displayCompletion()` called at run end.

2. **AC2: `TerminalOutputHandler`** — Given `TerminalOutputHandler` (SDK built-in implementation), when it receives `.toolUse` message, it outputs a step-counted execution message like `Step {n}: {toolName} — executing`. Uses a `TextOutputStream` for output (injectable, defaults to `FileHandle.standardOutput`).

3. **AC3: `TerminalOutputHandler` result handling** — Given `TerminalOutputHandler`, when it receives `.result` message, it outputs a completion summary including: total steps, elapsed time (from `ContinuousClock`), and status-appropriate messages for each `ResultData.Subtype` (success, errorMaxTurns, errorMaxBudgetUsd, cancelled, errorDuringExecution, errorMaxStructuredOutputRetries, errorMaxModelCalls).

4. **AC4: `TerminalOutputHandler` streaming text buffering** — Given `TerminalOutputHandler`, when it receives `.partialMessage` messages, it buffers text and flushes when a structured event (`.toolUse`, `.toolResult`, `.result`, `.system`) arrives. This prevents streaming fragments from interleaving with step log lines.

5. **AC5: `JSONOutputHandler`** — Given `JSONOutputHandler` (SDK built-in implementation), when it receives any SDKMessage, it accumulates state (steps, errors, result data). When `finalize()` is called, it outputs a complete JSON structure containing: runId, task, status, text, numTurns, durationMs, steps (array of toolName + toolUseId), errors (array of toolUseId + message), and mode.

6. **AC6: `JSONOutputHandler` JSON output** — Given `JSONOutputHandler`, when `finalize()` returns, the result is a `[String: Any]` dictionary suitable for `JSONSerialization`. The `write` closure receives the JSON string. Supports `writeEvent` closure for streaming pause/timeout events as JSON.

7. **AC7: Sendable conformance** — All handlers conform to `Sendable`. `TerminalOutputHandler` is a `struct` (stateless aside from counters/timer). `JSONOutputHandler` is a `struct` accumulating immutable snapshots. Both use `@unchecked Sendable` only where closures prevent compiler verification.

8. **AC8: Unit tests** — `SDKMessageOutputHandler` protocol compliance (mock handler implements protocol), `TerminalOutputHandler` (step counting, streaming buffer flush, result formatting per subtype, elapsed time computation), `JSONOutputHandler` (state accumulation, finalize JSON structure, pause event streaming, empty run) are covered by unit tests.

9. **AC9: Build and test pass** — `swift build` with zero errors and zero warnings. All existing tests pass with zero regression.

## Tasks / Subtasks

- [x] Task 1: Define SDKMessageOutputHandler protocol (AC: #1)
  - [x] Create `Sources/OpenAgentSDK/Types/SDKMessageOutputHandler.swift`
  - [x] Define `public protocol SDKMessageOutputHandler: Sendable`
  - [x] `func displayRunStart(runId: String, task: String)`
  - [x] `func handle(_ message: SDKMessage)`
  - [x] `func displayCompletion()`

- [x] Task 2: Implement TerminalOutputHandler (AC: #2, #3, #4)
  - [x] Create `Sources/OpenAgentSDK/Utils/TerminalOutputHandler.swift`
  - [x] `public struct TerminalOutputHandler: SDKMessageOutputHandler`
  - [x] Injectable `TextOutputStream` (default: stdout wrapper)
  - [x] Step counter: increment on `.toolUse`, format as `Step {n}: {toolName} — executing`
  - [x] Streaming text buffer: accumulate `.partialMessage` text, flush on structured events
  - [x] `.toolResult`: truncate errors (100 chars) and success results (120 chars), detect Base64 screenshots
  - [x] `.result`: format per subtype — success (steps + time), errorMaxTurns (steps + suggestion), errorMaxBudgetUsd, cancelled, errorDuringExecution, errorMaxStructuredOutputRetries, errorMaxModelCalls
  - [x] `.system(.paused)`: display pause reason
  - [x] `.assistant`: flush buffer, output text with prefix
  - [x] `ContinuousClock` for elapsed time tracking

- [x] Task 3: Implement JSONOutputHandler (AC: #5, #6)
  - [x] Create `Sources/OpenAgentSDK/Utils/JSONOutputHandler.swift`
  - [x] `public struct JSONOutputHandler: SDKMessageOutputHandler`
  - [x] `let write: (String) -> Void` — closure for final JSON output
  - [x] `let writeEvent: (String) -> Void?` — optional closure for streaming JSON events (pause/timeout)
  - [x] Internal state: `runId`, `task`, `steps: [[String: Any]]`, `errors: [[String: String]]`, `resultData: SDKMessage.ResultData?`
  - [x] `.toolUse`: append `{toolName, toolUseId}` to steps
  - [x] `.toolResult` with error: append `{toolUseId, message}` to errors
  - [x] `.result`: store resultData
  - [x] `.system(.paused)` / `.system(.pausedTimeout)`: emit JSON event via writeEvent
  - [x] `finalize() -> [String: Any]`: build full JSON with runId, task, status, text, numTurns, durationMs, steps, errors, mode

- [x] Task 4: Unit tests (AC: #8)
  - [x] Create `Tests/OpenAgentSDKTests/Utils/TerminalOutputHandlerTests.swift`
    - [x] Test step counting increments on .toolUse
    - [x] Test partialMessage buffering and flush on .toolUse
    - [x] Test .result formatting for each Subtype (7 cases)
    - [x] Test .toolResult error truncation
    - [x] Test .toolResult success summarization
    - [x] Test .system(.paused) displays reason
    - [x] Test .assistant flushes buffer and outputs text
    - [x] Test elapsed time computation
  - [x] Create `Tests/OpenAgentSDKTests/Utils/JSONOutputHandlerTests.swift`
    - [x] Test .toolUse appends to steps array
    - [x] Test .toolResult error appends to errors array
    - [x] Test .result stores resultData
    - [x] Test finalize produces correct JSON structure
    - [x] Test finalize with empty run (no messages)
    - [x] Test .system(.paused) emits JSON event
    - [x] Test .system(.pausedTimeout) emits JSON event
  - [x] Create `Tests/OpenAgentSDKTests/Types/SDKMessageOutputHandlerTests.swift`
    - [x] Test mock handler conforms to protocol (compile-time check)
    - [x] Test protocol methods are callable through existential

- [x] Task 5: Verify build and tests (AC: #9)
  - [x] `swift build` — 0 errors, 0 warnings
  - [x] Run full test suite — 0 failures

## Dev Notes

### Architecture Compliance

- **Protocol goes in `Types/`**: `SDKMessageOutputHandler` is a public protocol with no I/O dependencies. Follows the pattern of `ToolProtocol` (also in `Types/`). Protocols are leaf-node types.
- **Implementations go in `Utils/`**: `TerminalOutputHandler` and `JSONOutputHandler` are utility structs with no mutable shared state. Follows existing pattern: `MemoryContextProvider`, `MemoryLifecycleService`, `MemoryBundleExportService` are all structs in `Utils/`.
- **No actor needed**: Handlers are structs, not actors. They receive messages synchronously from the streaming loop. The caller (`QueryEngine` or consuming app) owns the handler and calls `handle()` in sequence.
- **No Apple-proprietary frameworks**: Use `Foundation` for `TextOutputStream`, `JSONSerialization`, `ContinuousClock` (Swift 5.7+, cross-platform). No UIKit/AppKit.
- **No dependencies on Core/ or Tools/**: Handlers only import `Types/` (for `SDKMessage`). They do not import `Core/` or `Tools/` — strict module boundary.

### Key Design Decisions

1. **TextOutputStream injection, NOT TerminalOutput**: The Axion reference uses a `TerminalOutput` abstraction (ANSI colors, cursor control). The SDK version uses Swift's built-in `TextOutputStream` protocol — simpler, cross-platform, testable with string capture. No ANSI/TTY dependencies.

2. **Struct, not class**: Both handlers are structs. No shared mutable state means no need for actors or classes. `TerminalOutputHandler` tracks step count and stream buffer as `var` properties. `JSONOutputHandler` accumulates state. Both are `Sendable` via struct semantics.

3. **No mode parameter in SDK version**: The Axion version has a `mode: String` ("standard"/"fast") that affects error messages. The SDK version omits this — mode-specific messaging is the consuming app's responsibility. The SDK provides the raw data; apps format for their mode.

4. **finalize() returns dictionary, not string**: `JSONOutputHandler.finalize()` returns `[String: Any]` so consumers can further customize before serialization. The `write` closure receives the serialized string.

5. **ContinuousClock for timing**: Uses Swift's `ContinuousClock` (available since Swift 5.7) instead of `Date()` for monotonic elapsed time. This avoids issues with system clock adjustments.

### Integration Points with Existing SDK

- **SDKMessage.swift** (`Types/SDKMessage.swift`): The 17-case enum that handlers consume. **Not modified** — handlers are pure consumers.
- **LogOutput.swift** (`Types/LogOutput.swift`): Similar pattern — enum with console/file/custom cases. The `TextOutputStream` injection for `TerminalOutputHandler` follows the same philosophy of injectable output destinations.
- **No integration with QueryEngine**: Handlers are standalone utilities. The consuming app wires them: `for await msg in agent.stream(task) { handler.handle(msg) }`. The SDK does not auto-wire handlers into the agent loop.

### What NOT to Extract from Axion

These are Axion-specific and must NOT be included:
- `TerminalOutput` class (ANSI cursor control, color formatting) — replaced by `TextOutputStream`
- `mode: String` parameter ("standard"/"fast") — SDK is mode-agnostic
- `[axion]` prefix in terminal output — replaced by configurable prefix or none
- `summarizeResult()` screenshot detection with Base64 — simplified to truncation in SDK version
- Fast mode suggestion messages ("try fast mode") — consuming app responsibility

### File Structure

```
Sources/OpenAgentSDK/Types/
  SDKMessageOutputHandler.swift    # Protocol definition (NEW)

Sources/OpenAgentSDK/Utils/
  TerminalOutputHandler.swift      # Terminal output implementation (NEW)
  JSONOutputHandler.swift          # JSON output implementation (NEW)

Tests/OpenAgentSDKTests/Types/
  SDKMessageOutputHandlerTests.swift  # Protocol conformance tests (NEW)

Tests/OpenAgentSDKTests/Utils/
  TerminalOutputHandlerTests.swift    # Terminal handler tests (NEW)
  JSONOutputHandlerTests.swift        # JSON handler tests (NEW)
```

### Modified Files

None — this story is purely additive. All existing files remain unchanged.

### Previous Story Learnings (Stories 20.1, 20.2, 20.3)

- Build baseline: 4931 tests passing. Any regression check must match this baseline.
- `nonisolated(unsafe)` for simple flags when actor isolation isn't needed
- Swift 6.1 strict concurrency: closures need explicit capture lists to avoid capturing `self`
- `NSLock` for protecting mutable state in non-actor contexts
- Hummingbird 2.x already added as dependency — no new dependencies needed
- `ISO8601DateFormatter` should be instance property on actors (not allocated per call)
- Test counts in completion notes must match actual test count
- `Codable` for SDK-internal structured data, raw `[String: Any]` only for LLM API communication boundary
- Pure computation structs (like MemoryLifecycleService) are preferred when no I/O is needed

### Testing Strategy

- **Unit tests:** All handlers tested in isolation. Use a `String`-backed `TextOutputStream` for `TerminalOutputHandler` tests. Use a closure-captured array for `JSONOutputHandler` tests.
- **No E2E tests for this story** — these are output formatting utilities, not agent-facing features that require LLM interaction.
- **TerminalOutputHandler tests:** Verify step counting, buffer flush, result formatting per subtype (7 cases), error truncation, pause display, elapsed time.
- **JSONOutputHandler tests:** Verify step/error accumulation, finalize JSON structure, pause event streaming, empty run handling.
- **Protocol conformance test:** Verify a mock struct can implement the protocol, proving the interface is usable.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 20 Story 20.4]
- [Source: _bmad-output/project-context.md]
- [Source: _bmad-output/implementation-artifacts/20-3-enhanced-memory-fact-lifecycle.md — Previous story learnings]
- [Reference: /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Commands/SDKOutputHandlers.swift — Terminal/JSON output handlers]
- [Source: Sources/OpenAgentSDK/Types/SDKMessage.swift — All 17 SDKMessage cases and associated data types]
- [Source: Sources/OpenAgentSDK/Types/LogOutput.swift — Injectable output pattern reference]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

None.

### Completion Notes List

- Implemented `SDKMessageOutputHandler` protocol in Types/ with three Sendable methods: displayRunStart, handle, displayCompletion
- Implemented `TerminalOutputHandler` struct using internal State class for non-mutating protocol conformance; includes step counting, streaming text buffer with flush-on-structured-event, per-subtype result formatting (7 cases), Base64 detection, ContinuousClock elapsed time
- Implemented `JSONOutputHandler` struct with state accumulation (steps, errors, resultData), finalize() returning [String: Any], writeEvent for streaming pause/timeout JSON events
- Both handlers use @unchecked Sendable with internal final class State to satisfy non-mutating protocol requirements
- Used @Sendable closure-based write API (TextOutputStream semantics via injectable closure)
- Fixed Swift 6 strict concurrency: private static default arg not accessible from public init → inlined closure; test capture vars → LineCollector class
- 44 new tests: 26 TerminalOutputHandler, 16 JSONOutputHandler, 2 protocol conformance
- Full suite: 4975 tests passing, 0 failures, 14 skipped

### File List

- Sources/OpenAgentSDK/Types/SDKMessageOutputHandler.swift (NEW)
- Sources/OpenAgentSDK/Utils/TerminalOutputHandler.swift (NEW)
- Sources/OpenAgentSDK/Utils/JSONOutputHandler.swift (NEW)
- Tests/OpenAgentSDKTests/Types/SDKMessageOutputHandlerTests.swift (NEW)
- Tests/OpenAgentSDKTests/Utils/TerminalOutputHandlerTests.swift (NEW)
- Tests/OpenAgentSDKTests/Utils/JSONOutputHandlerTests.swift (NEW)

## Change Log

- 2026-05-20: Story 20.4 implementation complete — SDKMessage output formatting protocol with TerminalOutputHandler and JSONOutputHandler, 44 tests added, 4975 total passing
- 2026-05-20: Senior Developer Review (AI) — 3 HIGH, 3 MEDIUM, 2 LOW issues found. All HIGH/MEDIUM fixed. Changes: (1) removed dead `stdoutWrite` static method, (2) fixed "steps" → "turns" in errorMaxTurns message, (3) corrected test count 34→44 in completion notes, (4) improved Base64 detection to use image format prefixes instead of substring match. 4975 tests passing after fixes. Status: done.

_Reviewer: Claude AI on 2026-05-20_
