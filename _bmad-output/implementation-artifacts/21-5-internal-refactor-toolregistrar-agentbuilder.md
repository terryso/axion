Status: done

## Story

As a project maintainer,
I want Axion's desktop-specific code organized more clearly, with the monolithic ToolRegistrar split into category modules and AgentBuilder cleaned up to separate generic from desktop-specific logic,
so that the codebase is easier to navigate, maintain, and extend.

## Acceptance Criteria

1. **Given** `Sources/AxionHelper/MCP/ToolRegistrar.swift` **When** checking line count **Then** ≤ 200 lines (entry point only, delegating to category files)
2. **Given** `Sources/AxionHelper/MCP/` directory **When** listing files **Then** contains: `MouseTools.swift`, `KeyboardTools.swift`, `WindowTools.swift`, `AppTools.swift`, `ScreenshotTools.swift`, `RecordingTools.swift`, plus `ToolRegistrar.swift` (entry) and `HelperMCPServer.swift` (unchanged)
3. **Given** each category file **When** inspecting **Then** contains all tool structs and their registration call for that category, with proper imports
4. **Given** `AgentBuilder.swift` **When** reading **Then** generic Agent building is cleanly separated from desktop-specific setup (SafetyHook factory, MCP config resolution, Helper path resolution)
5. **Given** `swift build` **When** run **Then** clean build with no errors
6. **Given** `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` **When** run **Then** all tests pass
7. **Given** `axion run "打开计算器"` **When** execution completes **Then** all tool calls work identically to pre-refactor behavior

## Tasks / Subtasks

- [x] Task 1: Create shared types file for ToolRegistrar split (AC: #3)
  - [x] Create `Sources/AxionHelper/MCP/ToolTypes.swift` containing:
    - `ToolErrorPayload` struct (change from `private` to `internal`)
    - `BlockingDialogInfo` struct + `detectBlockingDialog(windows:appPid:)` function
    - `ClickPoint` / `ClickTarget` result types and helper encoding logic (lines 53-119, 459-483)
  - [x] These types are shared across multiple tool categories and must be accessible from all category files

- [x] Task 2: Extract AppTools.swift (AC: #2, #3)
  - [x] Move `LaunchAppTool` (lines 150-211) and `ListAppsTool` (lines 213-224) to `Sources/AxionHelper/MCP/AppTools.swift`
  - [x] Add `import AppKit; import Foundation; import MCP; import MCPTool` + `import AxionCore` if needed
  - [x] Add `static func registerAppTools(to server: MCPServer) async throws` that registers both app tools

- [x] Task 3: Extract WindowTools.swift (AC: #2, #3)
  - [x] Move window tool structs to `Sources/AxionHelper/MCP/WindowTools.swift`:
    - `ActivateWindowTool` (lines 229-259)
    - `ListWindowsTool` (lines 261-277)
    - `GetWindowStateTool` (lines 279-305)
    - `ValidateWindowTool` (lines 742-756)
    - `ResizeWindowTool` (lines 777-839)
    - `ArrangeWindowsTool` (lines 840-959)
  - [x] Add `static func registerWindowTools(to server: MCPServer) async throws`
  - [x] Window layout structs (Story 8.3 types) used by ArrangeWindowsTool stay in this file

- [x] Task 4: Extract MouseTools.swift (AC: #2, #3)
  - [x] Move mouse/pointer tool structs to `Sources/AxionHelper/MCP/MouseTools.swift`:
    - `ClickTool` (lines 319-364)
    - `DoubleClickTool` (lines 366-411)
    - `RightClickTool` (lines 413-457)
    - `ScrollTool` (lines 598-629)
    - `DragTool` (lines 631-667)
  - [x] Add `static func registerMouseTools(to server: MCPServer) async throws`

- [x] Task 5: Extract KeyboardTools.swift (AC: #2, #3)
  - [x] Move keyboard tool structs to `Sources/AxionHelper/MCP/KeyboardTools.swift`:
    - `TypeTextTool` (lines 488-522)
    - `PressKeyTool` (lines 524-558)
    - `HotkeyTool` (lines 560-593)
  - [x] Add `static func registerKeyboardTools(to server: MCPServer) async throws`

- [x] Task 6: Extract ScreenshotTools.swift (AC: #2, #3)
  - [x] Move to `Sources/AxionHelper/MCP/ScreenshotTools.swift`:
    - `ScreenshotTool` (lines 672-705)
    - `GetAccessibilityTreeTool` (lines 707-737)
  - [x] Add `static func registerScreenshotTools(to server: MCPServer) async throws`

- [x] Task 7: Extract RecordingTools.swift (AC: #2, #3)
  - [x] Move to `Sources/AxionHelper/MCP/RecordingTools.swift`:
    - `StartRecordingTool` (lines 985-1013)
    - `StopRecordingTool` (lines 1015-1043)
  - [x] Add `static func registerRecordingTools(to server: MCPServer) async throws`

- [x] Task 8: Simplify ToolRegistrar.swift to entry point (AC: #1)
  - [x] Replace all tool struct definitions with calls to category registration functions
  - [x] `registerAll(to:)` becomes: call each `registerXxxTools(to:)` from category files
  - [x] Delete moved struct/code — only keep imports + `registerAll` delegation
  - [x] Target: ≤ 50 lines for the entry file

- [x] Task 9: Clean up AgentBuilder.swift (AC: #4)
  - [x] Extract `buildSafetyHookRegistry()` + related SafetyChecker logic into `Sources/AxionCLI/Services/SafetyHookFactory.swift`
  - [x] Extract `resolvePlaywrightConfig()` + MCP server dictionary building into `Sources/AxionCLI/Services/MCPConfigResolver.swift`
  - [x] Extract `HelperPathResolver` usage (path resolution + validation) — consider if it should stay inline or move to MCPConfigResolver
  - [x] `AgentBuilder.swift` retains: `BuildConfig` definitions, `build()` main flow (calling extracted helpers), `buildFullSystemPrompt()`, `buildSkillAgent()`, `appendModeInstructions()`
  - [x] Ensure `build()` flow reads top-to-bottom with clear sections: config → prompt → MCP → hooks → tools → options → create

- [x] Task 10: Evaluate RunLockService (AC: #4, #7)
  - [x] Analyze: RunLockService (142 lines) is used by 3 callers: `RunOrchestrator`, `AxionAPI`, `RunTaskTool`
  - [x] Decision: **Keep as-is** — merging into RunOrchestrator would break AxionAPI and RunTaskTool which need independent lock access
  - [x] No code changes needed for RunLockService

- [x] Task 11: Update tests (AC: #6)
  - [x] `Tests/AxionHelperTests/Tools/ToolRegistrarMockTests.swift` — verify mock registration still works with new entry point
  - [x] If any test files import `ToolRegistrar` types directly, update import paths
  - [x] Run `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` — all pass

- [x] Task 12: Verify build and behavior (AC: #5, #7)
  - [x] `swift build` — clean build
  - [x] `swift test` — all tests pass
  - [x] Verify ToolRegistrar.swift ≤ 200 lines
  - [x] Verify all 7 category files exist in `Sources/AxionHelper/MCP/`

## Dev Notes

### Critical: ToolRegistrar Structure for Splitting

ToolRegistrar.swift (1,042 lines) contains these sections with approximate line counts:

| Section | Lines | Tool Structs | Target File |
|---------|-------|-------------|-------------|
| Shared types (error payload, dialog detection, result types) | ~120 | — | `ToolTypes.swift` |
| `registerAll(to:)` entry | ~25 | — | `ToolRegistrar.swift` (keep) |
| App tools | ~78 | LaunchAppTool, ListAppsTool | `AppTools.swift` |
| Window tools | ~80 | ActivateWindowTool, ListWindowsTool, GetWindowStateTool | `WindowTools.swift` |
| Window validation + layout | ~220 | ValidateWindowTool, ResizeWindowTool, ArrangeWindowsTool | `WindowTools.swift` |
| Mouse tools | ~175 | ClickTool, DoubleClickTool, RightClickTool | `MouseTools.swift` |
| Click helper encoding | ~25 | (shared encoding logic) | `ToolTypes.swift` |
| Keyboard tools | ~110 | TypeTextTool, PressKeyTool, HotkeyTool | `KeyboardTools.swift` |
| Scroll & Drag | ~70 | ScrollTool, DragTool | `MouseTools.swift` |
| Screenshot + Accessibility | ~70 | ScreenshotTool, GetAccessibilityTreeTool | `ScreenshotTools.swift` |
| Recording tools | ~60 | StartRecordingTool, StopRecordingTool | `RecordingTools.swift` |

### Critical: Visibility Changes for Split

Currently `ToolErrorPayload` is `private` and helper functions like `detectBlockingDialog` are file-private. After splitting:
- `ToolErrorPayload` → `internal` (accessible within `AxionHelper` target, not public)
- `BlockingDialogInfo` is already `internal` — no change needed
- `detectBlockingDialog` → `internal` (used by LaunchAppTool in AppTools.swift)
- Click helper encoding types → `internal` (used by Click/DoubleClick/RightClick tools)
- All `@Tool` structs are already `internal` — no change needed

### Critical: Category Registration Pattern

Each category file should expose a single registration function:

```swift
// Example: AppTools.swift
import AppKit
import Foundation
import MCP
import MCPTool

struct AppTools {
    static func register(to server: MCPServer) async throws {
        try await server.registerTool(LaunchAppTool())
        try await server.registerTool(ListAppsTool())
    }
}
```

Then `ToolRegistrar.registerAll` becomes:
```swift
static func registerAll(to server: MCPServer) async throws {
    try await AppTools.register(to: server)
    try await WindowTools.register(to: server)
    try await MouseTools.register(to: server)
    try await KeyboardTools.register(to: server)
    try await ScreenshotTools.register(to: server)
    try await RecordingTools.register(to: server)
}
```

### AgentBuilder Extraction Strategy

`AgentBuilder.swift` (483 lines) mixes generic Agent creation with Axion-specific setup. Extract into focused helpers:

**SafetyHookFactory.swift** (~50 lines):
- `buildSafetyHookRegistry(sharedSeatMode:)` → HookRegistry
- Contains the preToolUse hook that blocks `mcp__axion-helper__` foreground tools
- Uses `ToolNames.foregroundToolNames` from AxionCore

**MCPConfigResolver.swift** (~60 lines):
- `resolveMCPServers(helperPath:dryrun:)` → [String: MCPServerConfig]
- Contains Helper path resolution + validation + Playwright config resolution
- Currently spread across `build()` method and `resolvePlaywrightConfig()`

After extraction, `AgentBuilder.swift` retains (~370 lines):
- `BuildConfig` struct + static factories (`forCLI`, `forAPI`, `forSkillExecution`, `forMCP`)
- `build(_:)` main flow calling extracted helpers
- `buildSkillAgent(_:)` for skill execution path
- `buildFullSystemPrompt()` + `buildSystemPrompt()`
- `appendModeInstructions()`

### RunLockService Decision

**Keep as-is.** The spec says "evaluate if it can be simplified or merged into RunOrchestrator." Analysis shows it's used by 3 independent callers:

1. `RunOrchestrator` — CLI mode: acquire lock before execution
2. `AxionAPI` — API server mode: multiple routes (run, skill run) use lock
3. `RunTaskTool` — MCP server mode: lock during task execution

Merging into RunOrchestrator would require either duplicating logic in AxionAPI/RunTaskTool or making AxionAPI depend on RunOrchestrator (wrong direction). The 142-line actor is appropriately scoped.

### Previous Story Learnings (from 21.1–21.4)

1. **Spec may describe features that don't fully match reality.** Always verify by reading actual source files before implementing.
2. **SDK exports `public struct Task`** which shadows Swift's `_Concurrency.Task`. Use `_Concurrency.Task` explicitly where needed.
3. **Type disambiguation is critical** when both SDK and Axion define similar types.
4. **Run `swift test --filter "AxionCLITests"` for verification** — unit tests only, no integration tests.
5. **Unicode-escaped Chinese characters are unreadable** — use literal characters, not `\u{XXXX}`.
6. **Empty directories after file moves** — clean up any leftover empty directories.

### File Structure After Refactor

```
Sources/AxionHelper/MCP/
├── HelperMCPServer.swift      # Unchanged — MCP server entry point
├── ToolRegistrar.swift         # ≤200 lines — entry point delegating to categories
├── ToolTypes.swift             # ~120 lines — shared types (error payload, dialog detection, result types)
├── AppTools.swift              # ~80 lines — launch_app, list_apps
├── WindowTools.swift           # ~300 lines — activate/list/get/validate/resize/arrange
├── MouseTools.swift            # ~175 lines — click/double_click/right_click/scroll/drag
├── KeyboardTools.swift         # ~110 lines — type_text/press_key/hotkey
├── ScreenshotTools.swift       # ~70 lines — screenshot, get_accessibility_tree
└── RecordingTools.swift        # ~60 lines — start_recording, stop_recording

Sources/AxionCLI/Services/
├── AgentBuilder.swift          # ~370 lines — build config + flow (generic parts)
├── SafetyHookFactory.swift     # ~50 lines — desktop safety hook construction
├── MCPConfigResolver.swift     # ~60 lines — MCP server config resolution
├── RunLockService.swift        # 142 lines — unchanged (shared across 3 callers)
└── ... (other services unchanged)
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 21.5]
- [Source: Sources/AxionHelper/MCP/ToolRegistrar.swift — 1,042 lines monolithic file]
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift — 483 lines mixed generic/desktop]
- [Source: Sources/AxionCLI/Services/RunLockService.swift — 142 lines, shared by 3 callers]
- [Source: Tests/AxionHelperTests/Tools/ToolRegistrarMockTests.swift — existing mock tests]
- [Source: Tests/AxionCLITests/Services/RunLockServiceTests.swift — lock service tests]
- [Source: Sources/AxionCLI/API/AxionAPI.swift — RunLockService caller (18 references)]
- [Source: Sources/AxionCLI/MCP/RunTaskTool.swift — RunLockService caller]

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

### Completion Notes List

- Task 1-7: Extracted all tool structs from monolithic ToolRegistrar.swift (1,042 lines) into 7 category files + shared ToolTypes.swift. Changed `private` visibility to `internal` for cross-file access.
- Task 8: Reduced ToolRegistrar.swift to 19-line entry point (well under 200-line AC). Uses category `register(to:)` pattern.
- Task 9: Extracted SafetyHookFactory.swift (34 lines) and MCPConfigResolver.swift (67 lines) from AgentBuilder.swift. AgentBuilder now 412 lines (down from 483).
- Task 10: RunLockService kept as-is — used by 3 independent callers.
- Task 11: Updated SDKBoundaryAuditTests to check extracted files instead of AgentBuilder. ToolRegistrarMockTests passed without changes.
- Task 12: `swift build` clean, 1169 tests pass.

### File List

**New files:**
- Sources/AxionHelper/MCP/ToolTypes.swift (190 lines — shared types)
- Sources/AxionHelper/MCP/AppTools.swift (88 lines)
- Sources/AxionHelper/MCP/WindowTools.swift (290 lines)
- Sources/AxionHelper/MCP/MouseTools.swift (233 lines)
- Sources/AxionHelper/MCP/KeyboardTools.swift (124 lines)
- Sources/AxionHelper/MCP/ScreenshotTools.swift (83 lines)
- Sources/AxionHelper/MCP/RecordingTools.swift (75 lines)
- Sources/AxionCLI/Services/SafetyHookFactory.swift (34 lines)
- Sources/AxionCLI/Services/MCPConfigResolver.swift (67 lines)

**Modified files:**
- Sources/AxionHelper/MCP/ToolRegistrar.swift (1,042 → 19 lines)
- Sources/AxionCLI/Services/AgentBuilder.swift (483 → 412 lines)
- Tests/AxionCLITests/Commands/SDKBoundaryAuditTests.swift (updated file path references)

## Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.7 on 2026-05-21

**Git vs Story Discrepancies:** 1 found (sprint-status.yaml modified but not in File List)

**Issues Found:** 0 Critical, 3 Medium, 1 Low

### Medium Issues (all auto-fixed)

1. **Duplicated `resolveClickTarget()` in MouseTools.swift** — The same 13-line method was copy-pasted 3 times (ClickTool line 52, DoubleClickTool line 99, RightClickTool line 146). Extracted to shared `resolveClickCoordinates()` in ToolTypes.swift. All three tools now call the shared function.

2. **Confusing self-referencing comment in ToolTypes.swift** — Doc comment said "Mirrors `ToolErrorPayload`" but the struct IS `ToolErrorPayload`. Replaced with accurate description: "Generic error payload returned by tool implementations."

3. **Unnecessary `import AppKit` in 6 category files** — ToolTypes.swift, AppTools.swift, MouseTools.swift, KeyboardTools.swift, ScreenshotTools.swift, and RecordingTools.swift all imported AppKit but none use AppKit types directly (only WindowTools.swift uses `NSScreen.main`). Removed unused imports.

### Low Issues (documented only)

4. **Story File List missing sprint-status.yaml** — Modified in git but not listed in story's File List.

### Verification

- `swift build` — clean ✓
- 1169 tests pass ✓
- ToolRegistrar.swift = 19 lines (AC #1: ≤200) ✓
- All 7 category files + ToolTypes.swift present (AC #2) ✓

### Change Log

- 2026-05-21: Review by Claude Opus 4.7 — 3 Medium issues found and auto-fixed. Status → done.
