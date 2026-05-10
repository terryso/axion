import Foundation

import AxionCore

// MARK: - ToolSafetyCategory

/// Categorises MCP tools by the level of desktop interaction they require.
/// Used by SafetyChecker to enforce shared-seat mode restrictions.
public enum ToolSafetyCategory: Equatable {
    /// Read-only tools that never modify desktop state: list_apps, list_windows,
    /// screenshot, get_accessibility_tree, get_file_info.
    case readOnly
    /// Tools that modify state but can run without stealing focus in background mode:
    /// launch_app, open_url, get_window_state, move_window, resize_window,
    /// activate_window, quit_app.
    case backgroundSafe
    /// Tools that simulate user input and always affect the foreground:
    /// click, double_click, right_click, type_text, press_key, hotkey, scroll, drag.
    case foregroundRequired
    /// Tool name not recognised — blocked by default.
    case unsupported
}

// MARK: - SafetyCheckResult

/// Result of a safety policy check.
public struct SafetyCheckResult: Equatable {
    public let allowed: Bool
    public let errorMessage: String

    public init(allowed: Bool, errorMessage: String = "") {
        self.allowed = allowed
        self.errorMessage = errorMessage
    }
}

// MARK: - SafetyChecker

/// Enforces the shared-seat safety policy. When `sharedSeatMode` is true,
/// foreground-required tools (click, type_text, etc.) are blocked to prevent
/// interfering with the user's desktop. When `sharedSeatMode` is false
/// (--allow-foreground mode), all known tools are allowed.
///
/// MVP strategy: Since Axion's Helper uses AX API (CGEvent synthesised events),
/// all foreground operations can affect the user's desktop. Therefore the policy
/// is conservative — block all input-simulation tools in shared-seat mode.
public struct SafetyChecker {

    public init() {}

    // MARK: - Tool sets

    private static let readOnlyTools: Set<String> = [
        ToolNames.listApps,
        ToolNames.listWindows,
        ToolNames.screenshot,
        ToolNames.getAccessibilityTree,
        ToolNames.getFileInfo
    ]

    private static let backgroundSafeTools: Set<String> = [
        ToolNames.launchApp,
        ToolNames.openUrl,
        ToolNames.getWindowState,
        ToolNames.moveWindow,
        ToolNames.resizeWindow,
        ToolNames.activateWindow,
        ToolNames.quitApp
    ]

    private static let foregroundRequiredTools: Set<String> = [
        ToolNames.click,
        ToolNames.doubleClick,
        ToolNames.rightClick,
        ToolNames.typeText,
        ToolNames.pressKey,
        ToolNames.hotkey,
        ToolNames.scroll,
        ToolNames.drag
    ]

    // MARK: - Public API

    /// Returns the safety category for a given tool name.
    public func classifyTool(_ tool: String) -> ToolSafetyCategory {
        if Self.readOnlyTools.contains(tool) { return .readOnly }
        if Self.backgroundSafeTools.contains(tool) { return .backgroundSafe }
        if Self.foregroundRequiredTools.contains(tool) { return .foregroundRequired }
        return .unsupported
    }

    /// Checks whether a tool is allowed under the current shared-seat policy.
    ///
    /// - Parameters:
    ///   - tool: MCP tool name.
    ///   - sharedSeatMode: When `true`, foreground-required tools are blocked.
    /// - Returns: A `SafetyCheckResult` indicating whether execution may proceed.
    public func check(tool: String, sharedSeatMode: Bool) -> SafetyCheckResult {
        let category = classifyTool(tool)

        // Unsupported tools are always blocked regardless of mode
        if category == .unsupported {
            return SafetyCheckResult(
                allowed: false,
                errorMessage: "Unknown tool '\(tool)' is not supported."
            )
        }

        // In shared-seat mode, block foreground-required tools
        if sharedSeatMode && category == .foregroundRequired {
            return SafetyCheckResult(
                allowed: false,
                errorMessage: "Tool '\(tool)' requires foreground interaction and is blocked in shared seat mode for safety. Use --allow-foreground to enable."
            )
        }

        return SafetyCheckResult(allowed: true)
    }
}
