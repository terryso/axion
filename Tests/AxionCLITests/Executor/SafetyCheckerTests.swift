import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] 基础设施验证
// [P1] 行为验证

// MARK: - SafetyChecker ATDD Tests

/// ATDD 红色阶段测试 — 覆盖 Story 3-3 AC6 (共享座椅安全检查) 和 AC7 (--allow-foreground 模式放行)
/// 这些测试将在 SafetyChecker 实现后通过 (TDD red-green-refactor)
final class SafetyCheckerTests: XCTestCase {

    // MARK: - P0 类型存在性

    func test_safetyChecker_typeExists() {
        let _ = SafetyChecker.self
    }

    func test_toolSafetyCategory_typeExists() {
        let _ = ToolSafetyCategory.self
    }

    func test_safetyCheckResult_typeExists() {
        let _ = SafetyCheckResult.self
    }

    // MARK: - P0 工具安全分类 (AC6 辅助)

    func test_classifyTool_listApps_isReadOnly() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("list_apps"), .readOnly)
    }

    func test_classifyTool_listWindows_isReadOnly() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("list_windows"), .readOnly)
    }

    func test_classifyTool_screenshot_isReadOnly() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("screenshot"), .readOnly)
    }

    func test_classifyTool_getAccessibilityTree_isReadOnly() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("get_accessibility_tree"), .readOnly)
    }

    func test_classifyTool_getFileInfo_isReadOnly() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("get_file_info"), .readOnly)
    }

    func test_classifyTool_launchApp_isBackgroundSafe() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("launch_app"), .backgroundSafe)
    }

    func test_classifyTool_openUrl_isBackgroundSafe() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("open_url"), .backgroundSafe)
    }

    func test_classifyTool_getWindowState_isBackgroundSafe() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("get_window_state"), .backgroundSafe)
    }

    func test_classifyTool_moveWindow_isBackgroundSafe() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("move_window"), .backgroundSafe)
    }

    func test_classifyTool_resizeWindow_isBackgroundSafe() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("resize_window"), .backgroundSafe)
    }

    func test_classifyTool_activateWindow_isBackgroundSafe() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("activate_window"), .backgroundSafe)
    }

    func test_classifyTool_quitApp_isBackgroundSafe() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("quit_app"), .backgroundSafe)
    }

    func test_classifyTool_click_isForegroundRequired() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("click"), .foregroundRequired)
    }

    func test_classifyTool_doubleClick_isForegroundRequired() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("double_click"), .foregroundRequired)
    }

    func test_classifyTool_rightClick_isForegroundRequired() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("right_click"), .foregroundRequired)
    }

    func test_classifyTool_typeText_isForegroundRequired() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("type_text"), .foregroundRequired)
    }

    func test_classifyTool_pressKey_isForegroundRequired() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("press_key"), .foregroundRequired)
    }

    func test_classifyTool_hotkey_isForegroundRequired() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("hotkey"), .foregroundRequired)
    }

    func test_classifyTool_scroll_isForegroundRequired() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("scroll"), .foregroundRequired)
    }

    func test_classifyTool_drag_isForegroundRequired() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("drag"), .foregroundRequired)
    }

    func test_classifyTool_unknownTool_isUnsupported() {
        let checker = SafetyChecker()
        XCTAssertEqual(checker.classifyTool("nonexistent_tool"), .unsupported)
    }

    // MARK: - P0 共享座椅模式阻止前台操作 (AC6)

    func test_check_sharedSeatMode_true_blocksForegroundTool() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "click", sharedSeatMode: true)

        XCTAssertFalse(result.allowed)
        XCTAssertFalse(result.errorMessage.isEmpty)
    }

    func test_check_sharedSeatMode_true_blocksTypeText() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "type_text", sharedSeatMode: true)

        XCTAssertFalse(result.allowed)
    }

    func test_check_sharedSeatMode_true_blocksAllForegroundTools() {
        let checker = SafetyChecker()
        let foregroundTools = ["click", "double_click", "right_click", "type_text",
                               "press_key", "hotkey", "scroll", "drag"]

        for tool in foregroundTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            XCTAssertFalse(result.allowed, "Shared seat mode should block \(tool)")
        }
    }

    func test_check_sharedSeatMode_true_allowsReadOnlyTools() {
        let checker = SafetyChecker()
        let readOnlyTools = ["list_apps", "list_windows", "screenshot",
                             "get_accessibility_tree", "get_file_info"]

        for tool in readOnlyTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            XCTAssertTrue(result.allowed, "Shared seat mode should allow read-only tool \(tool)")
        }
    }

    func test_check_sharedSeatMode_true_allowsBackgroundSafeTools() {
        let checker = SafetyChecker()
        let bgSafeTools = ["launch_app", "open_url", "get_window_state",
                           "move_window", "resize_window", "activate_window", "quit_app"]

        for tool in bgSafeTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            XCTAssertTrue(result.allowed, "Shared seat mode should allow background-safe tool \(tool)")
        }
    }

    // MARK: - P0 allow-foreground 模式放行 (AC7)

    func test_check_sharedSeatMode_false_allowsAllTools() {
        let checker = SafetyChecker()
        let allTools = ["click", "type_text", "launch_app", "list_apps",
                        "double_click", "scroll", "drag", "screenshot"]

        for tool in allTools {
            let result = checker.check(tool: tool, sharedSeatMode: false)
            XCTAssertTrue(result.allowed, "Allow-foreground mode should allow \(tool)")
        }
    }

    func test_check_sharedSeatMode_false_allowsClick() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "click", sharedSeatMode: false)

        XCTAssertTrue(result.allowed)
    }

    func test_check_sharedSeatMode_false_allowsTypeText() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "type_text", sharedSeatMode: false)

        XCTAssertTrue(result.allowed)
    }

    // MARK: - P1 边界情况

    func test_check_unsupportedTool_sharedSeatMode_blocks() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "nonexistent_tool", sharedSeatMode: true)

        XCTAssertFalse(result.allowed, "Unsupported tools should be blocked in shared seat mode")
    }

    func test_check_unsupportedTool_allowForeground_blocks() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "nonexistent_tool", sharedSeatMode: false)

        XCTAssertFalse(result.allowed, "Unsupported tools should be blocked even in allow-foreground mode")
    }

    func test_check_foregroundTool_returnsDescriptiveError() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "click", sharedSeatMode: true)

        XCTAssertFalse(result.allowed)
        XCTAssertTrue(result.errorMessage.contains("foreground") || result.errorMessage.contains("shared seat") || result.errorMessage.contains("safety"),
                      "Error message should explain why the tool was blocked: \(result.errorMessage)")
    }
}
