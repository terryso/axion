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

// MARK: - Tool Result Types (Story 1.4)

private struct CoordinateActionResult: Codable {
    let success: Bool
    let action: String
    let x: Int
    let y: Int
}

private struct DragActionResult: Codable {
    let success: Bool
    let action: String
    let fromX: Int
    let fromY: Int
    let toX: Int
    let toY: Int
    enum CodingKeys: String, CodingKey {
        case success, action
        case fromX = "from_x", fromY = "from_y", toX = "to_x", toY = "to_y"
    }
}

private struct TextActionResult: Codable {
    let success: Bool
    let action: String
    let text: String
}

private struct KeyActionResult: Codable {
    let success: Bool
    let action: String
    let key: String
}

private struct HotkeyActionResult: Codable {
    let success: Bool
    let action: String
    let keys: String
}

private struct ScrollActionResult: Codable {
    let success: Bool
    let action: String
    let direction: String
    let amount: Int
}

private struct ScreenshotActionResult: Codable {
    let success: Bool
    let action: String
    let imageData: String

    enum CodingKeys: String, CodingKey {
        case success, action
        case imageData = "image_data"
    }
}

private struct OpenURLActionResult: Codable {
    let success: Bool
    let action: String
    let url: String
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
        do {
            try ServiceContainer.shared.inputSimulation.click(x: x, y: y)
            let result = CoordinateActionResult(success: true, action: "click", x: x, y: y)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
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
struct DoubleClickTool {
    static let name = "double_click"
    static let description = "Perform a double click at the specified coordinates"

    @Parameter(description: "X coordinate")
    var x: Int

    @Parameter(description: "Y coordinate")
    var y: Int

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.inputSimulation.doubleClick(x: x, y: y)
            let result = CoordinateActionResult(success: true, action: "double_click", x: x, y: y)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
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
struct RightClickTool {
    static let name = "right_click"
    static let description = "Perform a right click at the specified coordinates"

    @Parameter(description: "X coordinate")
    var x: Int

    @Parameter(description: "Y coordinate")
    var y: Int

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.inputSimulation.rightClick(x: x, y: y)
            let result = CoordinateActionResult(success: true, action: "right_click", x: x, y: y)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
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

// MARK: - Keyboard Tools (Story 1.4)

@Tool
struct TypeTextTool {
    static let name = "type_text"
    static let description = "Type text at the current cursor position"

    @Parameter(description: "Text to type")
    var text: String

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.inputSimulation.typeText(text)
            let result = TextActionResult(success: true, action: "type_text", text: text)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
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
struct PressKeyTool {
    static let name = "press_key"
    static let description = "Press a keyboard key"

    @Parameter(description: "Key to press (e.g. 'return', 'tab', 'escape')")
    var key: String

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.inputSimulation.pressKey(key)
            let result = KeyActionResult(success: true, action: "press_key", key: key)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
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
struct HotkeyTool {
    static let name = "hotkey"
    static let description = "Press a keyboard shortcut / hotkey combination"

    @Parameter(description: "Key combination (e.g. 'cmd+c', 'cmd+shift+s')")
    var keys: String

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.inputSimulation.hotkey(keys)
            let result = HotkeyActionResult(success: true, action: "hotkey", keys: keys)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
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
        do {
            try ServiceContainer.shared.inputSimulation.scroll(direction: direction, amount: amount)
            let result = ScrollActionResult(success: true, action: "scroll", direction: direction, amount: amount)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
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
        do {
            try ServiceContainer.shared.inputSimulation.drag(fromX: fromX, fromY: fromY, toX: toX, toY: toY)
            let result = DragActionResult(success: true, action: "drag", fromX: fromX, fromY: fromY, toX: toX, toY: toY)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
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

// MARK: - Screenshot & Accessibility Tools (Story 1.5)

@Tool
struct ScreenshotTool {
    static let name = "screenshot"
    static let description = "Capture a screenshot, optionally of a specific window"

    @Parameter(key: "window_id", description: "Window identifier (optional, captures full screen if omitted)")
    var windowId: Int?

    func perform() async throws -> String {
        do {
            let base64: String
            if let windowId {
                base64 = try ServiceContainer.shared.screenshotCapture.captureWindow(windowId: windowId)
            } else {
                base64 = try ServiceContainer.shared.screenshotCapture.captureFullScreen()
            }
            let result = ScreenshotActionResult(success: true, action: "screenshot", imageData: base64)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as ScreenshotError {
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
struct GetAccessibilityTreeTool {
    static let name = "get_accessibility_tree"
    static let description = "Get the accessibility tree for a window"

    @Parameter(key: "window_id", description: "Window identifier")
    var windowId: Int

    @Parameter(key: "max_nodes", description: "Maximum number of nodes to return (default: 500)")
    var maxNodes: Int?

    func perform() async throws -> String {
        do {
            let nodes = maxNodes ?? 500
            let axTree = try ServiceContainer.shared.accessibilityEngine.getAXTree(windowId: windowId, maxNodes: nodes)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(axTree)
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

// MARK: - URL Tools (Story 1.5)

@Tool
struct OpenUrlTool {
    static let name = "open_url"
    static let description = "Open a URL in the default browser"

    @Parameter(description: "URL to open")
    var url: String

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.urlOpener.openURL(url)
            let result = OpenURLActionResult(success: true, action: "open_url", url: url)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as URLOpenerError {
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
