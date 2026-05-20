Status: done

## Story

As an SDK application developer,
I want SDK to provide the unified `SDKMessageOutputHandler` protocol and generic handler implementations, while Axion retains only desktop-specific output formatting,
so that the Axion-local protocol definition and old unused output wrappers (~120 lines) are eliminated and output handling aligns with SDK conventions.

## Acceptance Criteria

1. **Given** `axion run "打开计算器"` **When** execution completes **Then** terminal output format (Chinese messages, `[axion]` prefix, fast-mode hints) is identical to pre-refactor
2. **Given** `axion run "打开计算器" --json` **When** execution completes **Then** JSON output format (field names, structure) is identical to pre-refactor
3. **Given** `Sources/AxionCLI/Commands/SDKOutputHandlers.swift` **When** inspecting protocol definition **Then** it uses SDK's `OpenAgentSDK.SDKMessageOutputHandler` protocol (method `handle(_:)` not `handleMessage(_:)`)
4. **Given** `Sources/AxionCLI/Output/JSONOutput.swift` **When** checking existence **Then** file is deleted (unused old wrapper)
5. **Given** `Sources/AxionCLI/Output/TerminalOutput.swift` **When** checking existence **Then** file is deleted (fputs pattern inlined into handler + RecordCommand)
6. **Given** `swift test --filter "AxionCLITests"` **When** run **Then** all tests pass (deleted test files removed, adapted test files updated)

## Tasks / Subtasks

- [x] Task 1: Delete old unused output wrappers (AC: #4, #5)
  - [x] Delete `Sources/AxionCLI/Output/JSONOutput.swift` (42 lines) — old pre-SDK JSON accumulator, no longer referenced by any production code
  - [x] Delete `Sources/AxionCLI/Output/TerminalOutput.swift` (39 lines) — old terminal write wrapper; inline `fputs` pattern into handler and RecordCommand
  - [x] Delete `Tests/AxionCLITests/Output/JSONOutputTests.swift` (87 lines) — tests for deleted class
  - [x] Delete `Tests/AxionCLITests/Output/TerminalOutputTests.swift` (79 lines) — tests for deleted class

- [x] Task 2: Rewrite `SDKOutputHandlers.swift` to use SDK protocol (AC: #3)
  - [x] Delete Axion's local `SDKMessageOutputHandler` protocol (lines 7-11)
  - [x] `SDKTerminalOutputHandler`: change `handleMessage(_:)` → `handle(_:)` to satisfy SDK protocol
  - [x] `SDKTerminalOutputHandler`: remove `TerminalOutput` wrapper dependency; inline `fputs($0 + "\n", stdout); fflush(stdout)` as default `write` closure
  - [x] `SDKJSONOutputHandler`: change `handleMessage(_:)` → `handle(_:)` to satisfy SDK protocol
  - [x] Both handlers now conform to `OpenAgentSDK.SDKMessageOutputHandler` (import OpenAgentSDK already present)
  - [x] Keep all Axion-specific formatting unchanged: `[axion]` prefix, Chinese messages, fast-mode output, screenshot binary detection in `summarizeResult`

- [x] Task 3: Update `RecordCommand.swift` — remove `TerminalOutput` dependency (AC: #5)
  - [x] Replace `let output = TerminalOutput()` with inline `fputs` calls or a simple local closure
  - [x] RecordCommand only uses `output.write("[axion] ...")` pattern — replace with `fputs("[axion] ...\n", stdout); fflush(stdout)` directly

- [x] Task 4: Update `RunOrchestrator.swift` call sites (AC: #1, #2, #3)
  - [x] Line 133: `outputHandler.handleMessage(message)` → `outputHandler.handle(message)`
  - [x] Line 349: `outputHandler.handleMessage(message)` → `outputHandler.handle(message)`
  - [x] Verify both `SDKTerminalOutputHandler` and `SDKJSONOutputHandler` instantiation (lines 48-50, 327-329) still work with updated types

- [x] Task 5: Update test files (AC: #6)
  - [x] Update `Tests/AxionCLITests/SDKOutputHandlerTests.swift` (365 lines): rename all `handleMessage` calls → `handle`, verify conformance to SDK protocol
  - [x] Update `Tests/AxionCLITests/Output/SDKMessageOutputHandlerTests.swift` (474 lines): rename `handleMessage` → `handle`, update protocol conformance checks
  - [x] Update `Tests/AxionCLITests/OutputImplementationTests.swift` (79 lines): remove references to deleted `TerminalOutput` / `JSONOutput` if present
  - [x] Run `swift test --filter "AxionCLITests"` — all tests pass

- [x] Task 6: Verify build and output format (AC: #1, #2)
  - [x] `swift build` — clean build
  - [x] `swift test --filter "AxionCLITests"` — all tests pass
  - [x] Verify no `TerminalOutput` or `JSONOutput` references remain in production code (grep)

## Dev Notes

### Critical: Protocol Method Name Change

SDK's `SDKMessageOutputHandler` uses `handle(_:)`, Axion's local protocol uses `handleMessage(_:)`. All call sites in `RunOrchestrator` and tests must be updated. This is the core mechanical change:

```
// Before (Axion protocol)
func handleMessage(_ message: SDKMessage)
outputHandler.handleMessage(message)

// After (SDK protocol)
func handle(_ message: SDKMessage)
outputHandler.handle(message)
```

### Critical: Why We Can't Use SDK's Handler Implementations Directly

SDK provides `TerminalOutputHandler` and `JSONOutputHandler` structs, but they output **generic English text** (e.g., `"Run run-1 started: Task"`, `"Completed: 5 steps in 3s"`). Axion requires:

- **`[axion]` prefix** on every line — brand identity
- **Chinese messages** — `"模式"`, `"运行 ID"`, `"任务"`, `"执行错误"`, `"已取消"`, `"运行结束"`, etc.
- **Fast-mode specific hints** — `"Fast mode 完成。X 步，耗时 Y 秒。"`, `"建议去掉 --fast 重新尝试"`
- **Screenshot binary detection** — `summarizeResult` checks for `{"action":"screenshot"}`, `image_data`, `[微压缩]`, `Base64`, `base64` patterns
- **JSON `"tool"` field name** — Axion uses `"tool"`, SDK uses `"toolName"` (breaking change for JSON consumers)
- **JSON `mode` from config** — Axion passes actual mode string, SDK hard-codes `"default"`

**Decision:** Keep Axion's handler implementations with Axion-specific formatting. Only align the protocol (method name) and delete unused wrappers. Do NOT replace with SDK handler instances.

### File Layout After Refactor

```
Sources/AxionCLI/
├── Commands/
│   ├── SDKOutputHandlers.swift    # Keeps: SDKTerminalOutputHandler + SDKJSONOutputHandler (SDK protocol)
│   ├── RecordCommand.swift        # Updated: inline fputs instead of TerminalOutput
│   └── ...
├── Output/
│   └── (empty or deleted)         # TerminalOutput.swift + JSONOutput.swift deleted
└── ...
```

### Files to Delete (4 source + 2 test = 6 files)

| File | Lines | Reason |
|------|-------|--------|
| `Sources/AxionCLI/Output/JSONOutput.swift` | 42 | Unused old pre-SDK JSON accumulator |
| `Sources/AxionCLI/Output/TerminalOutput.swift` | 39 | Old write wrapper, inlined into handler + RecordCommand |
| `Tests/AxionCLITests/Output/JSONOutputTests.swift` | 87 | Tests for deleted JSONOutput |
| `Tests/AxionCLITests/Output/TerminalOutputTests.swift` | 79 | Tests for deleted TerminalOutput |

**Net removal: ~247 lines** (source + tests)

### Files to Modify (6 files)

| File | Change |
|------|--------|
| `Sources/AxionCLI/Commands/SDKOutputHandlers.swift` | Delete local protocol, rename `handleMessage` → `handle`, inline TerminalOutput pattern, add `import OpenAgentSDK` to protocol conformance |
| `Sources/AxionCLI/Commands/RecordCommand.swift` | Replace `TerminalOutput()` with inline `fputs` calls (4 call sites) |
| `Sources/AxionCLI/Services/RunOrchestrator.swift` | Rename `handleMessage` → `handle` at lines 133, 349 |
| `Tests/AxionCLITests/SDKOutputHandlerTests.swift` | Rename `handleMessage` → `handle` |
| `Tests/AxionCLITests/Output/SDKMessageOutputHandlerTests.swift` | Rename `handleMessage` → `handle` |
| `Tests/AxionCLITests/OutputImplementationTests.swift` | Update references to deleted types |

### Previous Story Learnings (from 21.1, 21.2, 21.3)

1. **Type disambiguation is critical.** Both SDK and Axion define `SDKMessageOutputHandler`. After deleting Axion's protocol, all conformances automatically resolve to SDK's. No typealias needed — just delete the local protocol.
2. **SDK exports `public struct Task`** which shadows Swift's `_Concurrency.Task`. Use `_Concurrency.Task` explicitly where needed.
3. **Spec may describe SDK features that don't fully match reality.** Always verify SDK API by reading source files before implementing.
4. **Run `swift test --filter "AxionCLITests"` for verification** — unit tests only, no integration tests needed.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 21.4]
- [Source: Sources/AxionCLI/Commands/SDKOutputHandlers.swift — current Axion protocol + handlers (247 lines)]
- [Source: Sources/AxionCLI/Output/TerminalOutput.swift — to be deleted (39 lines)]
- [Source: Sources/AxionCLI/Output/JSONOutput.swift — to be deleted (42 lines)]
- [Source: Sources/AxionCLI/Services/RunOrchestrator.swift:48-50, 133, 327-329, 349 — call sites]
- [Source: Sources/AxionCLI/Commands/RecordCommand.swift:18 — TerminalOutput usage]
- [Source: SDK Sources/OpenAgentSDK/Types/SDKMessageOutputHandler.swift — SDK protocol: `handle(_:)`, `displayRunStart(runId:task:)`, `displayCompletion()`]
- [Source: SDK Sources/OpenAgentSDK/Utils/TerminalOutputHandler.swift — SDK generic terminal handler (English)]
- [Source: SDK Sources/OpenAgentSDK/Utils/JSONOutputHandler.swift — SDK generic JSON handler]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- E2ETestHelpers.swift import needed `import protocol OpenAgentSDK.SDKMessageOutputHandler` + `import enum OpenAgentSDK.SDKMessage` instead of `import OpenAgentSDK` because SDK also exports a `TraceRecorder` actor that would conflict with AxionCLI's `TraceRecorder`
- `OutputImplementationTests.swift` entirely tested `TerminalOutput` and `JSONOutput` (both deleted) — deleted the file entirely
- Additional test files beyond the story spec required updating: `FastModeTests.swift`, `SDKIntegrationATDDTests.swift`, E2E test files (`MockLLME2ETests.swift`, `RealLLME2ETests.swift`, `E2ETestHelpers.swift`), and `SDKAgentIntegrationTests.swift` — all used `TerminalOutput` or `handleMessage` API

### Completion Notes List

- ✅ Deleted 5 files: `JSONOutput.swift`, `TerminalOutput.swift`, `JSONOutputTests.swift`, `TerminalOutputTests.swift`, `OutputImplementationTests.swift`
- ✅ Rewrote `SDKOutputHandlers.swift`: deleted local `SDKMessageOutputHandler` protocol, both handlers now conform to `OpenAgentSDK.SDKMessageOutputHandler`, renamed `handleMessage(_:)` → `handle(_:)`, replaced `TerminalOutput` dependency with inline `write` closure, added `@unchecked Sendable` conformance
- ✅ Updated `RecordCommand.swift`: replaced `TerminalOutput()` with local `write` closure using `fputs`
- ✅ Updated `RunOrchestrator.swift`: renamed `handleMessage` → `handle` at both call sites
- ✅ Updated all test files: `SDKOutputHandlerTests.swift`, `SDKMessageOutputHandlerTests.swift`, `FastModeTests.swift`, `SDKIntegrationATDDTests.swift`, E2E test files
- ✅ All 973 tests pass, clean build with no errors
- ✅ No `TerminalOutput` or `JSONOutput` references remain in production code

### File List

**Deleted:**
- Sources/AxionCLI/Output/JSONOutput.swift
- Sources/AxionCLI/Output/TerminalOutput.swift
- Tests/AxionCLITests/Output/JSONOutputTests.swift
- Tests/AxionCLITests/Output/TerminalOutputTests.swift
- Tests/AxionCLITests/OutputImplementationTests.swift

**Modified:**
- Sources/AxionCLI/Commands/SDKOutputHandlers.swift
- Sources/AxionCLI/Commands/RecordCommand.swift
- Sources/AxionCLI/Services/RunOrchestrator.swift
- Tests/AxionCLITests/SDKOutputHandlerTests.swift
- Tests/AxionCLITests/Output/SDKMessageOutputHandlerTests.swift
- Tests/AxionCLITests/Commands/FastModeTests.swift
- Tests/AxionCLITests/Commands/SDKIntegrationATDDTests.swift
- Tests/AxionCLITests/Integration/SDK/SDKAgentIntegrationTests.swift
- Tests/AxionE2ETests/E2ETestHelpers.swift
- Tests/AxionE2ETests/MockLLME2ETests.swift
- Tests/AxionE2ETests/RealLLME2ETests.swift
- _bmad-output/implementation-artifacts/sprint-status.yaml

## Senior Developer Review (AI)

**Reviewer:** Claude (adversarial review) on 2026-05-21

### Findings (4 total: 0 CRITICAL, 2 HIGH/MEDIUM, 2 LOW)

**M1 (Fixed):** No test for `.errorMaxModelCalls` result subtype — handler at SDKOutputHandlers.swift:77 had no test coverage. **Fix:** Added `terminalHandlerResultMaxModelCalls` test.

**M2 (Fixed):** Unicode-escaped Chinese characters in SDKOutputHandlers.swift — all Chinese text used `\u{XXXX}` escape sequences instead of literal characters, making code significantly harder to read. **Fix:** Converted all 12 escape sequences to literal Chinese characters for consistency with RecordCommand.swift and other files.

**L1 (Fixed):** 8 test function names in SDKMessageOutputHandlerTests.swift still referenced old `handleMessage` API (e.g., `handleMessageToolUseWritesToolName`). **Fix:** Renamed all to use `handle` prefix.

**L2 (Fixed):** Empty `Sources/AxionCLI/Output/` directory left behind after file deletions. **Fix:** Removed empty directory.

### Verification
- All 974 tests pass (was 973, +1 new test)
- Clean build
- No `handleMessage` references remain in codebase
- No `TerminalOutput`/`JSONOutput` type references remain in production code

## Change Log

- 2026-05-21: Review complete — fixed 4 issues (Unicode readability, missing test coverage, stale test names, empty directory). Status → done.
- 2026-05-21: Story 21.4 implementation complete — deleted local protocol + unused wrappers, aligned with SDK's `SDKMessageOutputHandler` protocol, all tests pass
