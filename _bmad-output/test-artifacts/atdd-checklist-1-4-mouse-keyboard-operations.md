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
storyId: '1.4'
storyKey: 1-4-mouse-keyboard-operations
storyFile: _bmad-output/implementation-artifacts/1-4-mouse-keyboard-operations.md
atddChecklistPath: _bmad-output/test-artifacts/atdd-checklist-1-4-mouse-keyboard-operations.md
generatedTestFiles:
  - Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift
  - Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/1-4-mouse-keyboard-operations.md
  - _bmad-output/test-artifacts/atdd-checklist-1-3-app-launch-window-management.md
  - _bmad/tea/config.yaml
  - .claude/skills/bmad-testarch-atdd/resources/tea-index.csv
---

# ATDD Checklist: Story 1.4 - 鼠标与键盘操作

**Date:** 2026-05-08
**Author:** Nick
**Primary Test Level:** Unit (Backend/Swift)

---

## Story Summary

As a CLI 进程, I want Helper 可以执行鼠标和键盘操作, So that 自动化任务可以与桌面 UI 交互.

---

## Acceptance Criteria

1. **AC1**: click 工具接收坐标 (x, y) → 执行单击操作，返回成功 JSON
2. **AC2**: double_click 工具接收坐标 (x, y) → 执行双击操作，返回成功 JSON
3. **AC3**: right_click 工具接收坐标 (x, y) → 执行右键点击操作，返回成功 JSON
4. **AC4**: type_text 工具接收文本 → 输入文本，返回成功 JSON
5. **AC5**: press_key 工具接收按键名 → 按下对应键，返回成功 JSON
6. **AC6**: hotkey 工具接收组合键字符串 → 执行组合键，返回成功 JSON
7. **AC7**: scroll 工具接收方向和量 → 执行滚动，返回成功 JSON
8. **AC8**: drag 工具接收起止坐标 → 执行拖拽操作，返回成功 JSON

---

## Story Integration Metadata

- **Story ID:** `1.4`
- **Story Key:** `1-4-mouse-keyboard-operations`
- **Story File:** `_bmad-output/implementation-artifacts/1-4-mouse-keyboard-operations.md`
- **Checklist Path:** `_bmad-output/test-artifacts/atdd-checklist-1-4-mouse-keyboard-operations.md`
- **Generated Test Files:**
  - `Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift`
  - `Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift`

---

## Red-Phase Test Scaffolds Created

### Unit Tests - Service Layer (29 tests, all skipped)

**File:** `Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift`

#### Key Name Mapping (AC5: press_key)

- **Test:** `test_keyNameMapping_return_mapsToCorrectKeyCode`
  - **Status:** RED - XCTSkipIf (InputSimulationService 解析方法标记为 ATDD RED PHASE)
  - **Verifies:** "return" -> 0x24

- **Test:** `test_keyNameMapping_enter_mapsToReturnKeyCode`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "enter" 是 "return" 的别名 -> 0x24

- **Test:** `test_keyNameMapping_tab_mapsToCorrectKeyCode`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "tab" -> 0x30

- **Test:** `test_keyNameMapping_escape_mapsToCorrectKeyCode`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "escape" -> 0x35

- **Test:** `test_keyNameMapping_space_mapsToCorrectKeyCode`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "space" -> 0x31

- **Test:** `test_keyNameMapping_delete_mapsToCorrectKeyCode`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "delete" -> 0x33 (Backspace)

- **Test:** `test_keyNameMapping_functionKeys_mapCorrectly`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** F1-F12 全部正确映射

- **Test:** `test_keyNameMapping_arrowKeys_mapCorrectly`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 上下左右箭头键映射

- **Test:** `test_keyNameMapping_singleLetter_a_mapsToZero`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 字母 "a" -> 0x00

- **Test:** `test_keyNameMapping_invalidKey_returnsNil`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 未知键名返回 nil

#### Hotkey Parsing (AC6: hotkey)

- **Test:** `test_hotkeyParsing_cmdC_returnsCommandFlagAndCKeyCode`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "cmd+c" -> (.maskCommand, 0x08)

- **Test:** `test_hotkeyParsing_cmdShiftS_returnsCombinedFlags`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "cmd+shift+s" -> (.maskCommand | .maskShift, 0x01)

- **Test:** `test_hotkeyParsing_ctrlAltDelete_returnsCombinedFlags`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "ctrl+alt+delete" -> (.maskControl | .maskAlternate, 0x33)

- **Test:** `test_hotkeyParsing_singleKeyNoModifier_throwsInvalidHotkeyFormat`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 无修饰键抛出 invalidHotkeyFormat 错误

- **Test:** `test_hotkeyParsing_unknownModifier_throwsInvalidHotkeyFormat`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 未知修饰键抛出错误

- **Test:** `test_hotkeyParsing_commandAlias_worksAsCmd`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "command" 作为 "cmd" 的别名

- **Test:** `test_hotkeyParsing_optionAlias_worksAsAlt`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** "option" 作为 "alt" 的别名

#### Scroll Direction (AC7: scroll)

- **Test:** `test_scrollDirection_up_returnsPositiveValue`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 向上滚动返回正值

- **Test:** `test_scrollDirection_down_returnsNegativeValue`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 向下滚动返回负值

- **Test:** `test_scrollDirection_invalidDirection_throwsError`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 无效方向抛出 invalidDirection 错误

- **Test:** `test_scrollDirection_isCaseInsensitive`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 方向名大小写不敏感

#### Coordinate Validation (AC1, AC2, AC3, AC8)

- **Test:** `test_coordinateValidation_negativeX_throwsOutOfBounds`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 负数 X 坐标抛出错误

- **Test:** `test_coordinateValidation_negativeY_throwsOutOfBounds`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 负数 Y 坐标抛出错误

- **Test:** `test_coordinateValidation_exceedsScreenSize_throwsOutOfBounds`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 超出屏幕尺寸抛出错误

- **Test:** `test_coordinateValidation_validCoordinates_doesNotThrow`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 合法坐标不抛出错误

#### Error Format (cross-cutting)

- **Test:** `test_inputSimulationError_coordinatesOutOfBounds_hasRequiredFields`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 错误包含 errorCode, errorDescription, suggestion

- **Test:** `test_inputSimulationError_invalidKeyName_hasRequiredFields`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** errorCode == "invalid_key_name"

- **Test:** `test_inputSimulationError_invalidHotkeyFormat_hasRequiredFields`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** errorCode == "invalid_hotkey_format"

- **Test:** `test_inputSimulationError_invalidDirection_hasRequiredFields`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** errorCode == "invalid_direction"

### Unit Tests - Tool Layer (16 tests, all skipped)

**File:** `Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift`

- **Test:** `test_click_validCoordinates_returnsSuccessJson`
  - **Status:** RED - XCTSkipIf (ClickTool perform() 为 stub)
  - **Verifies:** AC1 - click 返回 {"success": true, "action": "click", "x": 100, "y": 200}

- **Test:** `test_click_outOfBounds_returnsErrorJson`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC1 错误 - 超出边界返回 {"error": "coordinates_out_of_bounds"}

- **Test:** `test_doubleClick_validCoordinates_returnsSuccessJson`
  - **Status:** RED - XCTSkipIf (DoubleClickTool perform() 为 stub)
  - **Verifies:** AC2 - double_click 返回成功 JSON

- **Test:** `test_rightClick_validCoordinates_returnsSuccessJson`
  - **Status:** RED - XCTSkipIf (RightClickTool perform() 为 stub)
  - **Verifies:** AC3 - right_click 返回成功 JSON

- **Test:** `test_typeText_validText_returnsSuccessJson`
  - **Status:** RED - XCTSkipIf (TypeTextTool perform() 为 stub)
  - **Verifies:** AC4 - type_text 返回 {"success": true, "action": "type_text", "text": "Hello World"}

- **Test:** `test_typeText_unicodeCharacters_returnsSuccessJson`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC4 - Unicode 字符处理

- **Test:** `test_pressKey_validKey_returnsSuccessJson`
  - **Status:** RED - XCTSkipIf (PressKeyTool perform() 为 stub)
  - **Verifies:** AC5 - press_key 返回 {"success": true, "action": "press_key", "key": "return"}

- **Test:** `test_pressKey_invalidKeyName_returnsErrorJson`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC5 错误 - 无效键名返回 {"error": "invalid_key_name"}

- **Test:** `test_hotkey_validCombination_returnsSuccessJson`
  - **Status:** RED - XCTSkipIf (HotkeyTool perform() 为 stub)
  - **Verifies:** AC6 - hotkey 返回 {"success": true, "action": "hotkey", "keys": "cmd+c"}

- **Test:** `test_hotkey_invalidFormat_returnsErrorJson`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC6 错误 - 无效格式返回 {"error": "invalid_hotkey_format"}

- **Test:** `test_scroll_validDirection_returnsSuccessJson`
  - **Status:** RED - XCTSkipIf (ScrollTool perform() 为 stub)
  - **Verifies:** AC7 - scroll 返回 {"success": true, "direction": "down", "amount": 3}

- **Test:** `test_scroll_invalidDirection_returnsErrorJson`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC7 错误 - 无效方向返回 {"error": "invalid_direction"}

- **Test:** `test_drag_validCoordinates_returnsSuccessJson`
  - **Status:** RED - XCTSkipIf (DragTool perform() 为 stub)
  - **Verifies:** AC8 - drag 返回 {"success": true, "action": "drag"}

- **Test:** `test_drag_outOfBounds_returnsErrorJson`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** AC8 错误 - 超出边界返回错误

- **Test:** `test_click_doesNotReturnStubText`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** 工具不再返回 "Not yet implemented" 文本

- **Test:** `test_typeText_doesNotReturnStubText`
  - **Status:** RED - XCTSkipIf
  - **Verifies:** type_text 不返回 stub 文本

---

## Acceptance Criteria Coverage

| AC | Description | Priority | Test File | Test Count | Status |
|----|-------------|----------|-----------|------------|--------|
| AC1 | click 单击操作 | P0 | MouseKeyboardToolTests.swift | 3 | RED |
| AC2 | double_click 双击操作 | P0 | MouseKeyboardToolTests.swift | 1 | RED |
| AC3 | right_click 右键点击 | P0 | MouseKeyboardToolTests.swift | 1 | RED |
| AC4 | type_text 文本输入 | P0 | MouseKeyboardToolTests.swift | 2 | RED |
| AC5 | press_key 按键 | P0 | InputSimulationServiceTests.swift + MouseKeyboardToolTests.swift | 12 | RED |
| AC6 | hotkey 组合键 | P0 | InputSimulationServiceTests.swift + MouseKeyboardToolTests.swift | 9 | RED |
| AC7 | scroll 滚动 | P0 | InputSimulationServiceTests.swift + MouseKeyboardToolTests.swift | 5 | RED |
| AC8 | drag 拖拽 | P0 | MouseKeyboardToolTests.swift | 2 | RED |

**All 8 acceptance criteria have corresponding test coverage.**

---

## Priority Distribution

| Priority | Test Count | Percentage |
|----------|------------|------------|
| P0 | 35 | 78% |
| P1 | 10 | 22% |
| P2 | 0 | 0% |
| P3 | 0 | 0% |

---

## Test Level Strategy

This is a **backend (Swift/SPM)** project. Test level selection:

- **Unit Tests - Service Layer** (29 tests): Pure logic testing via InputSimulationService
  - Key name mapping, hotkey parsing, scroll direction, coordinate validation, error format
  - No CGEvent calls needed — pure parsing/validation logic
  - File: InputSimulationServiceTests.swift

- **Unit Tests - Tool Layer** (16 tests): MCP tool wiring via MCPServer.toolRegistry API with MockInputSimulation
  - Success paths for all 8 tools (click, double_click, right_click, type_text, press_key, hotkey, scroll, drag)
  - Error paths for invalid inputs (out of bounds, invalid key, invalid format, invalid direction)
  - Stub text verification
  - File: MouseKeyboardToolTests.swift

- **No E2E Tests**: CGEvent operations require AX permissions; integration tested via existing HelperProcessSmokeTests

---

## Implementation Checklist

### Test: test_keyNameMapping_* (10 tests)

**File:** `Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift`

**Tasks to make these tests pass:**

- [ ] 在 `InputSimulationService` 中实现 `keyCodeForName()` 方法及 `keyMap` 静态字典
- [ ] 移除 `XCTSkipIf(true, ...)` 
- [ ] 运行测试: `swift test --filter test_keyNameMapping`
- [ ] Tests pass (green phase)

### Test: test_hotkeyParsing_* (7 tests)

**File:** `Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift`

**Tasks to make these tests pass:**

- [ ] 在 `InputSimulationService` 中实现 `parseHotkey()` 方法
- [ ] 支持修饰键: cmd/command, shift, ctrl/control, alt/option
- [ ] 无效格式抛出 `InputSimulationError.invalidHotkeyFormat`
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_hotkeyParsing`
- [ ] Tests pass (green phase)

### Test: test_scrollDirection_* (4 tests)

**File:** `Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift`

**Tasks to make these tests pass:**

- [ ] 在 `InputSimulationService` 中实现 `scrollValueForDirection()` 方法
- [ ] "up" 返回正值, "down" 返回负值
- [ ] 无效方向抛出 `InputSimulationError.invalidDirection`
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_scrollDirection`
- [ ] Tests pass (green phase)

### Test: test_coordinateValidation_* (4 tests)

**File:** `Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift`

**Tasks to make these tests pass:**

- [ ] 在 `InputSimulationService` 中实现 `validateCoordinates()` 方法
- [ ] 使用 `CGDisplayBounds(CGMainDisplayID())` 获取屏幕范围
- [ ] 负数和超出范围抛出 `InputSimulationError.coordinatesOutOfBounds`
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_coordinateValidation`
- [ ] Tests pass (green phase)

### Test: test_inputSimulationError_* (4 tests)

**File:** `Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift`

**Tasks to make these tests pass:**

- [ ] 确保 `InputSimulationError` 有正确的 `errorCode`, `errorDescription`, `suggestion`
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_inputSimulationError`
- [ ] Tests pass (green phase)

### Test: test_click_* (3 tests) + test_doubleClick_* + test_rightClick_* (1 each)

**File:** `Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift`

**Tasks to make these tests pass:**

- [ ] 替换 ClickTool.perform() stub — 调用 ServiceContainer.shared.inputSimulation.click(x:y:)
- [ ] 替换 DoubleClickTool.perform() stub — 调用 doubleClick(x:y:)
- [ ] 替换 RightClickTool.perform() stub — 调用 rightClick(x:y:)
- [ ] 成功返回 `{"success": true, "action": "click", "x": ..., "y": ...}`
- [ ] 错误返回 `ToolErrorPayload` JSON
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_click; swift test --filter test_doubleClick; swift test --filter test_rightClick`
- [ ] Tests pass (green phase)

### Test: test_typeText_* (2 tests) + test_pressKey_* (2 tests) + test_hotkey_* (2 tests)

**File:** `Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift`

**Tasks to make these tests pass:**

- [ ] 替换 TypeTextTool.perform() stub — 调用 typeText(_:)
- [ ] 替换 PressKeyTool.perform() stub — 调用 pressKey(_:)
- [ ] 替换 HotkeyTool.perform() stub — 调用 hotkey(_:)
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_typeText; swift test --filter test_pressKey; swift test --filter test_hotkey`
- [ ] Tests pass (green phase)

### Test: test_scroll_* (2 tests) + test_drag_* (2 tests)

**File:** `Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift`

**Tasks to make these tests pass:**

- [ ] 替换 ScrollTool.perform() stub — 调用 scroll(direction:amount:)
- [ ] 替换 DragTool.perform() stub — 调用 drag(fromX:fromY:toX:toY:)
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_scroll; swift test --filter test_drag`
- [ ] Tests pass (green phase)

### Test: test_*_doesNotReturnStubText (2 tests)

**File:** `Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift`

**Tasks to make these tests pass:**

- [ ] 确保所有工具返回 JSON 格式而非 "Not yet implemented" 文本
- [ ] 移除 `XCTSkipIf(true, ...)`
- [ ] 运行测试: `swift test --filter test_click_doesNotReturnStubText; swift test --filter test_typeText_doesNotReturnStubText`
- [ ] Tests pass (green phase)

---

## Running Tests

```bash
# Run all tests (Story 1.4 tests skipped in RED phase)
swift test

# Run Story 1.4 Service tests only
swift test --filter InputSimulationServiceTests

# Run Story 1.4 Tool tests only
swift test --filter MouseKeyboardToolTests

# Run specific test groups
swift test --filter test_keyNameMapping
swift test --filter test_hotkeyParsing
swift test --filter test_scrollDirection
swift test --filter test_coordinateValidation
swift test --filter test_click
swift test --filter test_typeText

# Run unit tests only (per CLAUDE.md rules)
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Services" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionCoreTests"

# Build without running tests
swift build
```

---

## Red-Green-Refactor Workflow

### RED Phase (Complete)

**TEA Agent Responsibilities:**

- 45 tests written as red-phase scaffolds with `XCTSkipIf(true, "ATDD RED PHASE: ...")`
- 29 service-level tests (pure logic: mapping, parsing, validation)
- 16 tool-level tests (MCP tool wiring with mocked InputSimulating)
- All tests assert EXPECTED behavior based on acceptance criteria
- Implementation checklist created with task-to-test mapping

**Verification:**

- All 45 generated tests are present and skipped via XCTSkipIf
- 93 pre-existing tests continue to pass
- Total: 138 tests, 45 skipped, 0 failures

---

### GREEN Phase (DEV Team - Next Steps)

**DEV Agent Responsibilities:**

1. **Implement InputSimulationService parsing methods** - keyCodeForName, parseHotkey, scrollValueForDirection, validateCoordinates
2. **Remove XCTSkipIf** from InputSimulationServiceTests
3. **Run** `swift test --filter InputSimulationServiceTests` - verify parsing logic
4. **Implement CGEvent calls** in InputSimulationService click/doubleClick/rightClick/scroll/drag/typeText/pressKey/hotkey
5. **Replace ToolRegistrar stubs** for 8 tools (ClickTool through DragTool)
6. **Remove XCTSkipIf** from MouseKeyboardToolTests
7. **Run** `swift test --filter MouseKeyboardToolTests` - verify tool wiring
8. **Run** `swift test` - verify all tests pass

**Key Principles:**

- Parsing/validation layer first (no AX permission needed)
- Then CGEvent implementation (needs AX permission)
- One tool at a time (click -> double_click -> right_click -> type_text -> press_key -> hotkey -> scroll -> drag)
- Minimal implementation (don't over-engineer)
- Run tests frequently (immediate feedback)

---

### REFACTOR Phase (DEV Team - After All Tests Pass)

1. Verify all tests pass with `swift test`
2. Review error handling completeness (all InputSimulationError cases)
3. Ensure tool parameter names match ToolNames.swift constants
4. Verify CGEvent usage follows project patterns
5. Confirm tests are deterministic (no timing dependencies)

---

## Key Assumptions

1. **CGEvent API**: InputSimulationService uses macOS CoreGraphics CGEvent API for all input simulation. This is distinct from OpenClick which uses an external cua-driver binary.

2. **Key Mapping Table**: The static key name -> CGKeyCode mapping is comprehensive but may need extension for special characters (numbers, symbols). The story provides the core mapping table.

3. **Hotkey Format**: The format is "modifier+key" with at least one modifier. Single keys use press_key, not hotkey. Modifiers: cmd/command, shift, ctrl/control, alt/option.

4. **Scroll Direction**: Vertical scroll uses positive values for "up" and negative for "down". Horizontal scroll (left/right) requires CGEvent(scrollWheelEvent2:wheelCount:2).

5. **Coordinate System**: CGEvent uses the main display's top-left corner as origin. Coordinates validated against CGDisplayBounds(CGMainDisplayID()).

6. **Error Format**: All errors follow the ToolErrorPayload convention: `{"error": "...", "message": "...", "suggestion": "..."}`.

7. **AX Permissions**: CGEvent synthesis requires Accessibility permissions. Tests skip AX-dependent operations. Service-layer tests only validate parsing logic.

---

## Knowledge Base References Applied

- **test-quality.md**: Given-When-Then structure, one primary assertion per test, deterministic
- **test-levels-framework.md**: Unit tests for parsing/validation, unit tests for tool wiring with mocks
- **test-priorities-matrix.md**: P0 for core input operations, P1 for edge cases and format validation
- **component-tdd.md**: Red-green-refactor with XCTSkipIf pattern for Swift

---

## Test Execution Evidence

### Initial Scaffold Review / RED Verification

**Command:** `swift test`

**Results:**

```
Test Suite 'InputSimulationServiceTests' passed at 2026-05-08.
  Executed 29 tests, with 29 tests skipped and 0 failures
Test Suite 'MouseKeyboardToolTests' passed at 2026-05-08.
  Executed 16 tests, with 16 tests skipped and 0 failures
Test Suite 'axionPackageTests.xctest' passed at 2026-05-08.
  Executed 138 tests, with 45 tests skipped and 0 failures
```

**Summary:**

- Total tests: 138
- Skipped: 45 (Story 1.4 RED phase scaffolds)
- Activated RED tests: 0 (all skipped via XCTSkipIf)
- Passing: 93 (Stories 1.1 + 1.2 + 1.3 pre-existing)
- Status: RED phase scaffolds verified

---

## Notes

- Story 1.4 replaces 8 tool stubs in ToolRegistrar.swift (ClickTool through DragTool) with real implementations that call InputSimulationService via ServiceContainer.shared.
- Two test levels: service-layer tests verify pure parsing/validation logic without AX permissions; tool-layer tests verify MCP tool wiring with MockInputSimulation.
- The InputSimulationService stub already contains working implementations for keyCodeForName, parseHotkey, scrollValueForDirection, and validateCoordinates. The XCTSkipIf guards allow tests to compile and skip. In GREEN phase, the dev simply removes XCTSkipIf and the tests should pass immediately for parsing logic. CGEvent implementation is separate.
- MockInputSimulation added to MockServices.swift follows the same pattern as MockAppLauncher and MockAccessibilityEngine.
- ServiceContainer updated with inputSimulation property following existing pattern.

---

**Generated by BMad TEA Agent** - 2026-05-08
