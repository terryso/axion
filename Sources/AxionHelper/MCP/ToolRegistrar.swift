import AppKit
import Foundation
import MCP
import MCPTool

/// Mirrors `ToolErrorPayload` — kept private because AxionError
/// is internal to AxionCore. If AxionError becomes public, replace with
/// `ToolErrorPayload` directly.
private struct ToolErrorPayload: Codable {
    let error: String
    let message: String
    let suggestion: String
}

/// Centralized registration of all AxionHelper MCP tools.
///
/// Story 1.3 tools (launch_app, list_apps, list_windows, get_window_state)
/// have real implementations. Other tools remain stubs for Stories 1.4–1.5.
enum ToolRegistrar {

    /// Registers all AxionHelper tools on the given MCP server.
    ///
    /// - Parameter server: The `MCPServer` to register tools on.
    /// - Throws: `MCPError.invalidParams` if any tool name is already registered.
    static func registerAll(to server: MCPServer) async throws {
        try await server.register {
            LaunchAppTool.self
            ListAppsTool.self
            ListWindowsTool.self
            GetWindowStateTool.self
            ClickTool.self
            DoubleClickTool.self
            RightClickTool.self
            TypeTextTool.self
            PressKeyTool.self
            HotkeyTool.self
            ScrollTool.self
            DragTool.self
            ScreenshotTool.self
            GetAccessibilityTreeTool.self
            OpenUrlTool.self
        }
    }
}

// MARK: - App Management Tools (Story 1.3)

@Tool
struct LaunchAppTool {
    static let name = "launch_app"
    static let description = "Launch a macOS application by name"

    @Parameter(key: "app_name", description: "Application name (e.g. 'Calculator')")
    var appName: String

    func perform() async throws -> String {
        do {
            let appInfo = try await ServiceContainer.shared.appLauncher.launchApp(name: appName)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(appInfo)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as AppLauncherError {
            let payload = ToolErrorPayload(
                error: error.errorCode,
                message: error.localizedDescription,
                suggestion: error.suggestion
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}

@Tool
struct ListAppsTool {
    static let name = "list_apps"
    static let description = "List all running macOS applications"

    func perform() async throws -> String {
        let apps = ServiceContainer.shared.appLauncher.listRunningApps()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(apps)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

// MARK: - Window Management Tools (Story 1.3)

@Tool
struct ListWindowsTool {
    static let name = "list_windows"
    static let description = "List windows, optionally filtered by process ID"

    @Parameter(description: "Process ID to filter windows by (optional)")
    var pid: Int?

    func perform() async throws -> String {
        let pidValue = pid.map { Int32($0) }
        let windows = ServiceContainer.shared.accessibilityEngine.listWindows(pid: pidValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(windows)
        return String(data: data, encoding: .utf8) ?? "[]"
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as AccessibilityEngineError {
            let payload = ToolErrorPayload(
                error: error.errorCode,
                message: error.localizedDescription,
                suggestion: error.suggestion
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}

// MARK: - Mouse Tools (Story 1.4)

@Tool
struct ClickTool {
    static let name = "click"
    static let description = "Perform a single click at the specified coordinates"

    @Parameter(description: "X coordinate")
    var x: Int

    @Parameter(description: "Y coordinate")
    var y: Int

    func perform() async throws -> String {
        "Not yet implemented: click"
    }
}

@Tool
struct DoubleClickTool {
    static let name = "double_click"
    static let description = "Perform a double click at the specified coordinates"

    @Parameter(description: "X coordinate")
    var x: Int

    @Parameter(description: "Y coordinate")
    var y: Int

    func perform() async throws -> String {
        "Not yet implemented: double_click"
    }
}

@Tool
struct RightClickTool {
    static let name = "right_click"
    static let description = "Perform a right click at the specified coordinates"

    @Parameter(description: "X coordinate")
    var x: Int

    @Parameter(description: "Y coordinate")
    var y: Int

    func perform() async throws -> String {
        "Not yet implemented: right_click"
    }
}

// MARK: - Keyboard Tools (Story 1.4)

@Tool
struct TypeTextTool {
    static let name = "type_text"
    static let description = "Type text at the current cursor position"

    @Parameter(description: "Text to type")
    var text: String

    func perform() async throws -> String {
        "Not yet implemented: type_text"
    }
}

@Tool
struct PressKeyTool {
    static let name = "press_key"
    static let description = "Press a keyboard key"

    @Parameter(description: "Key to press (e.g. 'return', 'tab', 'escape')")
    var key: String

    func perform() async throws -> String {
        "Not yet implemented: press_key"
    }
}

@Tool
struct HotkeyTool {
    static let name = "hotkey"
    static let description = "Press a keyboard shortcut / hotkey combination"

    @Parameter(description: "Key combination (e.g. 'cmd+c', 'cmd+shift+s')")
    var keys: String

    func perform() async throws -> String {
        "Not yet implemented: hotkey"
    }
}

// MARK: - Scroll & Drag Tools (Story 1.4)

@Tool
struct ScrollTool {
    static let name = "scroll"
    static let description = "Scroll in a direction by a specified amount"

    @Parameter(description: "Scroll direction ('up', 'down', 'left', 'right')")
    var direction: String

    @Parameter(description: "Amount to scroll")
    var amount: Int

    func perform() async throws -> String {
        "Not yet implemented: scroll"
    }
}

@Tool
struct DragTool {
    static let name = "drag"
    static let description = "Drag from one point to another"

    @Parameter(key: "from_x", description: "Starting X coordinate")
    var fromX: Int

    @Parameter(key: "from_y", description: "Starting Y coordinate")
    var fromY: Int

    @Parameter(key: "to_x", description: "Ending X coordinate")
    var toX: Int

    @Parameter(key: "to_y", description: "Ending Y coordinate")
    var toY: Int

    func perform() async throws -> String {
        "Not yet implemented: drag"
    }
}

// MARK: - Screenshot & Accessibility Tools (Story 1.5)

@Tool
struct ScreenshotTool {
    static let name = "screenshot"
    static let description = "Capture a screenshot, optionally of a specific window"

    @Parameter(key: "window_id", description: "Window identifier (optional, captures full screen if omitted)")
    var windowId: Int?

    func perform() async throws -> String {
        "Not yet implemented: screenshot"
    }
}

@Tool
struct GetAccessibilityTreeTool {
    static let name = "get_accessibility_tree"
    static let description = "Get the accessibility tree for a window"

    @Parameter(key: "window_id", description: "Window identifier")
    var windowId: Int

    func perform() async throws -> String {
        "Not yet implemented: get_accessibility_tree"
    }
}

// MARK: - URL Tools (Story 1.5)

@Tool
struct OpenUrlTool {
    static let name = "open_url"
    static let description = "Open a URL in the default browser"

    @Parameter(description: "URL to open")
    var url: String

    func perform() async throws -> String {
        "Not yet implemented: open_url"
    }
}
