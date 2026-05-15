import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

/// ATDD 红色阶段测试 — 覆盖 Story 3-3 AC6 (共享座椅安全检查) 和 AC7 (--allow-foreground 模式放行)
/// 这些测试将在 SafetyChecker 实现后通过 (TDD red-green-refactor)
@Suite("SafetyChecker")
struct SafetyCheckerTests {

    @Test("safetyChecker type exists")
    func safetyCheckerTypeExists() {
        let _ = SafetyChecker.self
    }

    @Test("toolSafetyCategory type exists")
    func toolSafetyCategoryTypeExists() {
        let _ = ToolSafetyCategory.self
    }

    @Test("safetyCheckResult type exists")
    func safetyCheckResultTypeExists() {
        let _ = SafetyCheckResult.self
    }

    @Test("classify list_apps as readOnly")
    func classifyToolListAppsIsReadOnly() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("list_apps") == .readOnly)
    }

    @Test("classify list_windows as readOnly")
    func classifyToolListWindowsIsReadOnly() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("list_windows") == .readOnly)
    }

    @Test("classify screenshot as readOnly")
    func classifyToolScreenshotIsReadOnly() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("screenshot") == .readOnly)
    }

    @Test("classify get_accessibility_tree as readOnly")
    func classifyToolGetAccessibilityTreeIsReadOnly() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("get_accessibility_tree") == .readOnly)
    }

    @Test("classify get_file_info as readOnly")
    func classifyToolGetFileInfoIsReadOnly() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("get_file_info") == .readOnly)
    }

    @Test("classify launch_app as backgroundSafe")
    func classifyToolLaunchAppIsBackgroundSafe() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("launch_app") == .backgroundSafe)
    }

    @Test("classify open_url as backgroundSafe")
    func classifyToolOpenUrlIsBackgroundSafe() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("open_url") == .backgroundSafe)
    }

    @Test("classify get_window_state as backgroundSafe")
    func classifyToolGetWindowStateIsBackgroundSafe() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("get_window_state") == .backgroundSafe)
    }

    @Test("classify move_window as backgroundSafe")
    func classifyToolMoveWindowIsBackgroundSafe() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("move_window") == .backgroundSafe)
    }

    @Test("classify resize_window as backgroundSafe")
    func classifyToolResizeWindowIsBackgroundSafe() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("resize_window") == .backgroundSafe)
    }

    @Test("classify activate_window as backgroundSafe")
    func classifyToolActivateWindowIsBackgroundSafe() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("activate_window") == .backgroundSafe)
    }

    @Test("classify quit_app as backgroundSafe")
    func classifyToolQuitAppIsBackgroundSafe() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("quit_app") == .backgroundSafe)
    }

    @Test("classify click as foregroundRequired")
    func classifyToolClickIsForegroundRequired() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("click") == .foregroundRequired)
    }

    @Test("classify double_click as foregroundRequired")
    func classifyToolDoubleClickIsForegroundRequired() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("double_click") == .foregroundRequired)
    }

    @Test("classify right_click as foregroundRequired")
    func classifyToolRightClickIsForegroundRequired() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("right_click") == .foregroundRequired)
    }

    @Test("classify type_text as foregroundRequired")
    func classifyToolTypeTextIsForegroundRequired() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("type_text") == .foregroundRequired)
    }

    @Test("classify press_key as foregroundRequired")
    func classifyToolPressKeyIsForegroundRequired() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("press_key") == .foregroundRequired)
    }

    @Test("classify hotkey as foregroundRequired")
    func classifyToolHotkeyIsForegroundRequired() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("hotkey") == .foregroundRequired)
    }

    @Test("classify scroll as foregroundRequired")
    func classifyToolScrollIsForegroundRequired() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("scroll") == .foregroundRequired)
    }

    @Test("classify drag as foregroundRequired")
    func classifyToolDragIsForegroundRequired() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("drag") == .foregroundRequired)
    }

    @Test("classify unknown tool as unsupported")
    func classifyToolUnknownToolIsUnsupported() {
        let checker = SafetyChecker()
        #expect(checker.classifyTool("nonexistent_tool") == .unsupported)
    }

    @Test("shared seat mode blocks foreground tool")
    func checkSharedSeatModeTrueBlocksForegroundTool() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "click", sharedSeatMode: true)

        #expect(!result.allowed)
        #expect(!result.errorMessage.isEmpty)
    }

    @Test("shared seat mode blocks type_text")
    func checkSharedSeatModeTrueBlocksTypeText() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "type_text", sharedSeatMode: true)

        #expect(!result.allowed)
    }

    @Test("shared seat mode blocks all foreground tools")
    func checkSharedSeatModeTrueBlocksAllForegroundTools() {
        let checker = SafetyChecker()
        let foregroundTools = ["click", "double_click", "right_click", "type_text",
                               "press_key", "hotkey", "scroll", "drag"]

        for tool in foregroundTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            #expect(!result.allowed)
        }
    }

    @Test("shared seat mode allows read-only tools")
    func checkSharedSeatModeTrueAllowsReadOnlyTools() {
        let checker = SafetyChecker()
        let readOnlyTools = ["list_apps", "list_windows", "screenshot",
                             "get_accessibility_tree", "get_file_info"]

        for tool in readOnlyTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            #expect(result.allowed)
        }
    }

    @Test("shared seat mode allows background-safe tools")
    func checkSharedSeatModeTrueAllowsBackgroundSafeTools() {
        let checker = SafetyChecker()
        let bgSafeTools = ["launch_app", "open_url", "get_window_state",
                           "move_window", "resize_window", "activate_window", "quit_app"]

        for tool in bgSafeTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            #expect(result.allowed)
        }
    }

    @Test("allow-foreground mode allows all tools")
    func checkSharedSeatModeFalseAllowsAllTools() {
        let checker = SafetyChecker()
        let allTools = ["click", "type_text", "launch_app", "list_apps",
                        "double_click", "scroll", "drag", "screenshot"]

        for tool in allTools {
            let result = checker.check(tool: tool, sharedSeatMode: false)
            #expect(result.allowed)
        }
    }

    @Test("allow-foreground mode allows click")
    func checkSharedSeatModeFalseAllowsClick() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "click", sharedSeatMode: false)

        #expect(result.allowed)
    }

    @Test("allow-foreground mode allows type_text")
    func checkSharedSeatModeFalseAllowsTypeText() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "type_text", sharedSeatMode: false)

        #expect(result.allowed)
    }

    @Test("unsupported tool blocked in shared seat mode")
    func checkUnsupportedToolSharedSeatModeBlocks() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "nonexistent_tool", sharedSeatMode: true)

        #expect(!result.allowed)
    }

    @Test("unsupported tool blocked in allow-foreground mode")
    func checkUnsupportedToolAllowForegroundBlocks() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "nonexistent_tool", sharedSeatMode: false)

        #expect(!result.allowed)
    }

    @Test("foreground tool returns descriptive error")
    func checkForegroundToolReturnsDescriptiveError() {
        let checker = SafetyChecker()
        let result = checker.check(tool: "click", sharedSeatMode: true)

        #expect(!result.allowed)
        #expect(result.errorMessage.contains("foreground") || result.errorMessage.contains("shared seat") || result.errorMessage.contains("safety"))
    }
}
