import MCP
import MCPTool

enum ScreenshotTools {
    static func register(to server: MCPServer) async throws {
        try await server.register {
            ScreenshotTool.self
            GetAccessibilityTreeTool.self
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
            return encodeToolResult(result)
        } catch let error as ScreenshotError {
            return encodeToolError(error)
        }
    }
}

@Tool
struct GetAccessibilityTreeTool {
    static let name = "get_accessibility_tree"
    static let description = "Get the accessibility tree for a window. Each element includes bounds and a pre-computed center point ({x, y}) for direct use as click coordinates."

    @Parameter(key: "window_id", description: "Window identifier")
    var windowId: Int

    @Parameter(key: "max_nodes", description: "Maximum number of nodes to return (default: 500)")
    var maxNodes: Int?

    func perform() async throws -> String {
        do {
            let nodes = maxNodes ?? 500
            let axTree = try ServiceContainer.shared.accessibilityEngine.getAXTree(windowId: windowId, maxNodes: nodes)
            return encodeToolResult(axTree)
        } catch let error as AccessibilityEngineError {
            return encodeToolError(error)
        }
    }
}
