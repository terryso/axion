import AppKit
import MCP
import MCPTool

// MARK: - Window Management Tools (Story 1.3)

@Tool
struct ActivateWindowTool {
    static let name = "activate_window"
    static let description = "Activate (bring to front) an application and optionally a specific window"

    @Parameter(description: "Process ID of the application")
    var pid: Int

    @Parameter(key: "window_id", description: "Window identifier (optional, activates the app's frontmost window if omitted)")
    var windowId: Int?

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.accessibilityEngine.activateWindow(pid: Int32(pid), windowId: windowId)
            var result: [String: Any] = ["success": true, "action": "activate_window", "pid": pid]
            if let windowId { result["window_id"] = windowId }
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as AccessibilityEngineError {
            return encodeToolError(error)
        }
    }
}

@Tool
struct ListWindowsTool {
    static let name = "list_windows"
    static let description = "List windows, optionally filtered by process ID"

    @Parameter(description: "Process ID to filter windows by (optional)")
    var pid: Int?

    func perform() async throws -> String {
        let pidValue = pid.map { Int32($0) }
        let windows = ServiceContainer.shared.accessibilityEngine.listWindows(pid: pidValue)
        return encodeToolResult(windows, fallback: "[]")
    }
}

@Tool
struct GetWindowStateTool {
    static let name = "get_window_state"
    static let description = "Get the state of a window by its ID"

    @Parameter(key: "window_id", description: "Window identifier")
    var windowId: Int

    func perform() async throws -> String {
        do {
            let state = try ServiceContainer.shared.accessibilityEngine.getWindowState(windowId: windowId)
            return encodeToolResult(state)
        } catch let error as AccessibilityEngineError {
            return encodeToolError(error)
        }
    }
}

// MARK: - Window Validation Tool

@Tool
struct ValidateWindowTool {
    static let name = "validate_window"
    static let description = "Validate that a window still exists and is actionable (on-screen, non-zero bounds)"

    @Parameter(key: "window_id", description: "Window identifier to validate")
    var windowId: Int

    func perform() async throws -> String {
        let result = ServiceContainer.shared.accessibilityEngine.validateWindow(windowId: windowId)
        return encodeToolResult(result)
    }
}
