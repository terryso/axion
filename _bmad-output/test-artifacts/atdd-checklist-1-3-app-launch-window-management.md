---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-05-08'
storyId: '1.3'
storyKey: 1-3-app-launch-window-management
storyFile: _bmad-output/planning-artifacts/epics.md
atddChecklistPath: _bmad-output/test-artifacts/atdd-checklist-1-3-app-launch-window-management.md
generatedTestFiles:
  - Tests/AxionHelperTests/AppManagement/LaunchAppToolTests.swift
  - Tests/AxionHelperTests/WindowManagement/WindowManagementToolTests.swift
inputDocuments:
  - _bmad-output/planning-artifacts/epics.md
  - _bmad-output/test-artifacts/atdd-checklist-1-1-spm-scaffolding-axioncore-models.md
  - _bmad-output/test-artifacts/atdd-checklist-1-2-helper-mcp-server-foundation.md
  - _bmad/tea/config.yaml
  - .claude/skills/bmad-testarch-atdd/resources/tea-index.csv
---

# ATDD Checklist: Story 1.3 - 应用启动与窗口管理

**Date:** 2026-05-08
**Author:** Nick
**Primary Test Level:** Unit + Integration (Backend/Swift)

---

## Story Summary

As a CLI 进程, I want Helper 可以启动应用和管理窗口, So that 自动化任务可以控制 macOS 应用.

---

## Acceptance Criteria

1. **AC1**: launch_app 工具调用 app_name="Calculator" → Calculator.app 启动成功，返回包含 pid 的结果
2. **AC2**: list_apps 工具调用 → 返回当前运行的应用列表，每项包含 pid 和 app_name
3. **AC3**: Calculator 正在运行时调用 list_windows → 返回窗口列表，每项包含 window_id、title、bounds
4. **AC4**: Calculator 窗口存在时调用 get_window_state 传入 window_id → 返回完整窗口状态（bounds, is_minimized, is_focused, ax_tree）
5. **AC5**: 指定应用未安装时调用 launch_app → 返回错误结果，包含 error: "app_not_found" 和 suggestion

---

## Story Integration Metadata

- **Story ID:** `1.3`
- **Story Key:** `1-3-app-launch-window-management`
- **Story File:** `_bmad-output/planning-artifacts/epics.md`
- **Checklist Path:** `_bmad-output/test-artifacts/atdd-checklist-1-3-app-launch-window-management.md`
- **Generated Test Files:**
  - `Tests/AxionHelperTests/AppManagement/LaunchAppToolTests.swift`
  - `Tests/AxionHelperTests/WindowManagement/WindowManagementToolTests.swift`

---

## Red-Phase Test Scaffolds Created

### Unit Tests (16 tests, all skipped)

**File:** `Tests/AxionHelperTests/AppManagement/LaunchAppToolTests.swift` (~230 lines)

- **Test:** `test_launchApp_calculator_returnsSuccessWithPid`
  - **Status:** RED - XCTSkipIf (launch_app 当前为 stub 实现)
  - **Verifies:** AC1 - launch_app 启动 Calculator 并返回 pid

- **Test:** `test_launchApp_appIsRunningAfterLaunch`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC1 + AC2 - 启动后应用出现在 list_apps 中

- **Test:** `test_launchApp_alreadyRunning_returnsExistingPid`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC1 - 重复启动已运行应用不报错

- **Test:** `test_launchApp_appNotFound_returnsError`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC5 - 未安装应用返回 app_not_found 错误 + suggestion

- **Test:** `test_launchApp_missingAppName_returnsError`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 参数验证 - 缺少 app_name 抛出错误

- **Test:** `test_listApps_returnsRunningAppsList`
  - **Status:** RED - XCTSkipIf (list_apps 当前为 stub 实现)
  - **Verifies:** AC2 - 返回应用列表而非 stub 文本

- **Test:** `test_listApps_eachAppHasPidAndName`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC2 - 每项包含 pid 和 app_name 字段

- **Test:** `test_listApps_containsFinder`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC2 - 包含 Finder（macOS 始终运行）

**File:** `Tests/AxionHelperTests/WindowManagement/WindowManagementToolTests.swift` (~350 lines)

- **Test:** `test_listWindows_returnsWindowList`
  - **Status:** RED - XCTSkipIf (list_windows 当前为 stub 实现)
  - **Verifies:** AC3 - 返回窗口列表而非 stub 文本

- **Test:** `test_listWindows_eachWindowHasRequiredFields`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC3 - 每项包含 window_id、title、bounds

- **Test:** `test_listWindows_filterByPid_returnsFilteredResults`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC3 - 按 pid 过滤窗口

- **Test:** `test_getWindowState_returnsCompleteState`
  - **Status:** RED - XCTSkipIf (get_window_state 当前为 stub 实现)
  - **Verifies:** AC4 - 返回完整窗口状态而非 stub 文本

- **Test:** `test_getWindowState_containsRequiredFields`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC4 - 包含 bounds, is_minimized, is_focused, ax_tree

- **Test:** `test_getWindowState_boundsContainsPositionAndSize`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC4 - bounds 包含 x, y, width, height

- **Test:** `test_getWindowState_invalidWindowId_returnsError`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 错误处理 - 不存在的 window_id 返回错误

- **Test:** `test_fullWorkflow_launchToListWindowsToGetState`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC1+AC3+AC4 完整集成链路

---

## Acceptance Criteria Coverage

| AC | Description | Priority | Test File | Test Count | Status |
|----|-------------|----------|-----------|------------|--------|
| AC1 | launch_app 启动 Calculator | P0 | LaunchAppToolTests.swift | 3 | RED |
| AC2 | list_apps 返回应用列表 | P0 | LaunchAppToolTests.swift | 3 | RED |
| AC3 | list_windows 返回窗口列表 | P0 | WindowManagementToolTests.swift | 3 | RED |
| AC4 | get_window_state 返回完整状态 | P0 | WindowManagementToolTests.swift | 4 | RED |
| AC5 | app_not_found 错误处理 | P0 | LaunchAppToolTests.swift | 2 | RED |

**All 5 acceptance criteria have corresponding test coverage.**

---

## Priority Distribution

| Priority | Test Count | Percentage |
|----------|------------|------------|
| P0 | 9 | 56% |
| P1 | 7 | 44% |
| P2 | 0 | 0% |
| P3 | 0 | 0% |

---

## Test Level Strategy

This is a **backend (Swift/SPM)** project. Test level selection:

- **Unit Tests** (primary): Individual tool execution via MCPServer.toolRegistry API
  - Used for: AC1 (launch_app), AC2 (list_apps), AC3 (list_windows), AC4 (get_window_state), AC5 (app_not_found)
  - Justification: Tools are testable in-process using MCP toolRegistry.execute()
  - Files: LaunchAppToolTests.swift, WindowManagementToolTests.swift

- **Integration Tests** (one test): Full workflow across multiple tools
  - Used for: End-to-end launch → list_windows → get_window_state chain
  - Justification: Verifies tools compose correctly with real AX data
  - File: WindowManagementToolTests.swift (test_fullWorkflow_launchToListWindowsToGetState)

- **No E2E Tests**: Process-level tests already covered by Story 1.2's HelperProcessSmokeTests

---

## Implementation Checklist

### Test: test_launchApp_calculator_returnsSuccessWithPid

**File:** `Tests/AxionHelperTests/AppManagement/LaunchAppToolTests.swift`

**Tasks to make this test pass:**

- [ ] 在 `LaunchAppTool` 的 `perform()` 方法中实现 NSWorkspace.launchApplication 或 AX API 调用
- [ ] 返回 JSON 格式结果包含 `pid` 字段
- [ ] 移除 "Not yet implemented" stub 返回值
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_launchApp_calculator_returnsSuccessWithPid`
- [ ] Test passes (green phase)

### Test: test_launchApp_appNotFound_returnsError

**File:** `Tests/AxionHelperTests/AppManagement/LaunchAppToolTests.swift`

**Tasks to make this test pass:**

- [ ] 在 launch_app 实现中检测应用是否存在（NSWorkspace）
- [ ] 应用不存在时返回包含 "error"/"not found" 和 "suggestion" 的 JSON
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_launchApp_appNotFound_returnsError`
- [ ] Test passes (green phase)

### Test: test_listApps_returnsRunningAppsList + test_listApps_eachAppHasPidAndName

**File:** `Tests/AxionHelperTests/AppManagement/LaunchAppToolTests.swift`

**Tasks to make these tests pass:**

- [ ] 在 `ListAppsTool` 的 `perform()` 方法中实现 NSWorkspace.runningApplications 查询
- [ ] 返回 JSON 数组，每项包含 `pid` (processIdentifier) 和 `app_name` (localizedName)
- [ ] 移除 stub 返回值
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_listApps`
- [ ] Tests pass (green phase)

### Test: test_listWindows_returnsWindowList + test_listWindows_eachWindowHasRequiredFields

**File:** `Tests/AxionHelperTests/WindowManagement/WindowManagementToolTests.swift`

**Tasks to make these tests pass:**

- [ ] 在 `ListWindowsTool` 的 `perform()` 方法中实现 CGWindowListCopyWindowInfo 查询
- [ ] 返回 JSON 数组，每项包含 `window_id`、`title`、`bounds`
- [ ] 支持可选的 `pid` 参数过滤
- [ ] 移除 stub 返回值
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_listWindows`
- [ ] Tests pass (green phase)

### Test: test_getWindowState_returnsCompleteState + test_getWindowState_containsRequiredFields

**File:** `Tests/AxionHelperTests/WindowManagement/WindowManagementToolTests.swift`

**Tasks to make these tests pass:**

- [ ] 在 `GetWindowStateTool` 的 `perform()` 方法中实现 AX UIElement 查询
- [ ] 返回 JSON 包含 `bounds`、`is_minimized`、`is_focused`、`ax_tree`
- [ ] `bounds` 包含 `x`、`y`、`width`、`height` 子字段
- [ ] 无效 window_id 返回错误
- [ ] 移除 stub 返回值
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_getWindowState`
- [ ] Tests pass (green phase)

### Test: test_fullWorkflow_launchToListWindowsToGetState

**File:** `Tests/AxionHelperTests/WindowManagement/WindowManagementToolTests.swift`

**Tasks to make this test pass:**

- [ ] 所有上述工具实现完成后自动通过
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_fullWorkflow_launchToListWindowsToGetState`
- [ ] Test passes (green phase)

---

## Running Tests

```bash
# Run all tests (Story 1.3 tests skipped in RED phase)
swift test

# Run Story 1.3 App Management tests only
swift test --filter LaunchAppToolTests

# Run Story 1.3 Window Management tests only
swift test --filter WindowManagementToolTests

# Run specific test
swift test --filter test_launchApp_calculator_returnsSuccessWithPid
swift test --filter test_fullWorkflow_launchToListWindowsToGetState

# Build without running tests
swift build
```

---

## Red-Green-Refactor Workflow

### RED Phase (Complete)

**TEA Agent Responsibilities:**

- 16 tests written as red-phase scaffolds with `XCTSkipIf(true, "ATDD RED PHASE: ...")`
- All tests assert EXPECTED behavior based on acceptance criteria
- Implementation checklist created with task-to-test mapping

**Verification:**

- All 16 generated tests are present and skipped via XCTSkipIf
- 54 pre-existing tests (Stories 1.1 + 1.2) continue to pass
- Total: 70 tests, 16 skipped, 0 failures

---

### GREEN Phase (DEV Team - Next Steps)

**DEV Agent Responsibilities:**

1. **Implement LaunchAppTool.perform()** - Replace stub with NSWorkspace AX API
2. **Remove XCTSkipIf** from LaunchAppToolTests tests
3. **Run** `swift test --filter LaunchAppToolTests` - verify launch_app works
4. **Implement ListAppsTool.perform()** - Replace stub with NSWorkspace.runningApplications
5. **Remove XCTSkipIf** from list_apps tests
6. **Run** `swift test --filter test_listApps` - verify list_apps works
7. **Implement ListWindowsTool.perform()** - Replace stub with CGWindowListCopyWindowInfo
8. **Remove XCTSkipIf** from list_windows tests
9. **Run** `swift test --filter test_listWindows` - verify list_windows works
10. **Implement GetWindowStateTool.perform()** - Replace stub with AX UIElement API
11. **Remove XCTSkipIf** from get_window_state tests
12. **Run** `swift test --filter test_getWindowState` - verify get_window_state works
13. **Remove XCTSkipIf** from fullWorkflow test
14. **Run** `swift test` - verify all tests pass

**Key Principles:**

- One tool at a time (launch_app → list_apps → list_windows → get_window_state)
- Minimal implementation (don't over-engineer)
- Run tests frequently (immediate feedback)
- Use implementation checklist as roadmap

---

### REFACTOR Phase (DEV Team - After All Tests Pass)

1. Verify all tests pass with `swift test`
2. Review error handling completeness
3. Ensure tool parameter names match ToolNames.swift constants
4. Verify AX API usage follows project patterns
5. Confirm tests are deterministic (no timing dependencies)

---

## Key Assumptions

1. **NSWorkspace API**: Tests assume LaunchAppTool uses NSWorkspace.launchApplication (or AX API equivalent) to start apps. The return format should be JSON containing a `pid` field.

2. **CGWindowListCopyWindowInfo**: Tests assume ListWindowsTool uses CGWindowListCopyWindowInfo (or equivalent) to enumerate windows. Each window must have `window_id`, `title`, and `bounds`.

3. **AX UIElement API**: Tests assume GetWindowStateTool uses Accessibility API (AXUIElement) to query window state including `bounds`, `is_minimized`, `is_focused`, and `ax_tree`.

4. **JSON response format**: All tools return JSON strings (not free-form text) for programmatic parsing. This aligns with the MCP ToolResult text content convention.

5. **Pid filtering**: ListWindowsTool's optional `pid` parameter filters results to windows belonging to a specific process. This is already declared in the stub's `@Parameter`.

6. **Error format**: Errors follow the AxionError MCP ToolResult format: `{"error": "...", "message": "...", "suggestion": "..."}`.

---

## Knowledge Base References Applied

- **test-quality.md**: Given-When-Then structure, one primary assertion per test, deterministic
- **test-levels-framework.md**: Unit tests for individual tools, integration test for full workflow
- **test-priorities-matrix.md**: P0 for core AX operations, P1 for edge cases and format validation
- **component-tdd.md**: Red-green-refactor with XCTSkipIf pattern for Swift

---

## Test Execution Evidence

### Initial Scaffold Review / RED Verification

**Command:** `swift test`

**Results:**

```
Test Suite 'LaunchAppToolTests' passed at 2026-05-08.
  Executed 8 tests, with 8 tests skipped and 0 failures
Test Suite 'WindowManagementToolTests' passed at 2026-05-08.
  Executed 8 tests, with 8 tests skipped and 0 failures
Test Suite 'axionPackageTests.xctest' passed at 2026-05-08.
  Executed 70 tests, with 16 tests skipped and 0 failures
```

**Summary:**

- Total tests: 70
- Skipped: 16 (Story 1.3 RED phase scaffolds)
- Activated RED tests: 0 (all skipped via XCTSkipIf)
- Passing: 54 (Stories 1.1 + 1.2 pre-existing)
- Status: RED phase scaffolds verified

---

## Notes

- Story 1.3 builds on Story 1.2's MCP Server foundation. The ToolRegistrar stubs from Story 1.2 are the starting point; Story 1.3 replaces them with real AX implementations.
- Tests verify that tools return real data (not "Not yet implemented" stub text) by checking for absence of that string.
- The full workflow integration test (`test_fullWorkflow_launchToListWindowsToGetState`) validates the complete chain: launch → list → get state, which mirrors the real CLI-to-Helper usage pattern.
- Accessibility permissions are required for AX operations. Tests assume the test runner has Accessibility access granted.

---

**Generated by BMad TEA Agent** - 2026-05-08
