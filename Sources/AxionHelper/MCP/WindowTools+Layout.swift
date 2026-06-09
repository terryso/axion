import AppKit
import MCP
import MCPTool

// MARK: - Window Layout Tools (Story 8.3)

@Tool
struct ResizeWindowTool {
    static let name = "resize_window"
    static let description = "Move and/or resize a window by setting position and/or dimensions"

    @Parameter(key: "window_id", description: "Window identifier")
    var windowId: Int

    @Parameter(description: "New X position (optional, keeps current if omitted)")
    var x: Int?

    @Parameter(description: "New Y position (optional, keeps current if omitted)")
    var y: Int?

    @Parameter(description: "New width (optional, keeps current if omitted)")
    var width: Int?

    @Parameter(description: "New height (optional, keeps current if omitted)")
    var height: Int?

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.accessibilityEngine.setWindowBounds(
                windowId: windowId, x: x, y: y, width: width, height: height
            )
            let state = try ServiceContainer.shared.accessibilityEngine.getWindowState(windowId: windowId)
            let result = WindowBoundsResult(
                success: true, action: "resize_window", windowId: windowId,
                x: state.bounds.x, y: state.bounds.y,
                width: state.bounds.width, height: state.bounds.height
            )
            return encodeToolResult(result)
        } catch let error as AccessibilityEngineError {
            return encodeToolError(error)
        }
    }
}

@Tool
struct ArrangeWindowsTool {
    static let name = "arrange_windows"
    static let description = "Arrange multiple windows in a layout pattern (tile-left-right, tile-top-bottom, cascade)"

    @Parameter(description: "Layout type: 'tile-left-right', 'tile-top-bottom', or 'cascade'")
    var layout: String

    @Parameter(key: "window_ids", description: "Window identifiers to arrange (2+ windows)")
    var windowIds: [Int]

    func perform() async throws -> String {
        guard windowIds.count >= 2 else {
            return encodeToolError(error: "invalid_params", message: "At least 2 window_ids required for arrangement", suggestion: "Provide 2 or more window_ids.")
        }

        guard let screen = NSScreen.main else {
            return encodeToolError(error: "no_screen", message: "No main screen available", suggestion: "Ensure a display is connected.")
        }
        let screenRect = screen.visibleFrame

        do {
            switch layout {
            case WindowLayoutKind.tileLeftRight.rawValue:
                let halfWidth = Int(screenRect.width) / 2
                let fullWidth = Int(screenRect.width)
                let fullHeight = Int(screenRect.height)
                try ServiceContainer.shared.accessibilityEngine.setWindowBounds(
                    windowId: windowIds[0],
                    x: Int(screenRect.origin.x), y: Int(screenRect.origin.y),
                    width: halfWidth, height: fullHeight
                )
                try ServiceContainer.shared.accessibilityEngine.setWindowBounds(
                    windowId: windowIds[1],
                    x: Int(screenRect.origin.x) + halfWidth, y: Int(screenRect.origin.y),
                    width: fullWidth - halfWidth, height: fullHeight
                )
            case WindowLayoutKind.tileTopBottom.rawValue:
                let halfHeight = Int(screenRect.height) / 2
                let fullWidth = Int(screenRect.width)
                let fullHeight = Int(screenRect.height)
                try ServiceContainer.shared.accessibilityEngine.setWindowBounds(
                    windowId: windowIds[0],
                    x: Int(screenRect.origin.x), y: Int(screenRect.origin.y),
                    width: fullWidth, height: halfHeight
                )
                try ServiceContainer.shared.accessibilityEngine.setWindowBounds(
                    windowId: windowIds[1],
                    x: Int(screenRect.origin.x), y: Int(screenRect.origin.y) + halfHeight,
                    width: fullWidth, height: fullHeight - halfHeight
                )
            case WindowLayoutKind.cascade.rawValue:
                let cascadeOffset = 30
                let cascadeWidth = Int(screenRect.width) - cascadeOffset * (windowIds.count - 1)
                let cascadeHeight = Int(screenRect.height) - cascadeOffset * (windowIds.count - 1)
                for (i, wid) in windowIds.enumerated() {
                    try ServiceContainer.shared.accessibilityEngine.setWindowBounds(
                        windowId: wid,
                        x: Int(screenRect.origin.x) + cascadeOffset * i,
                        y: Int(screenRect.origin.y) + cascadeOffset * i,
                        width: max(cascadeWidth, 200),
                        height: max(cascadeHeight, 200)
                    )
                }
            default:
                let validLayouts = WindowLayoutKind.allCases.map(\.rawValue).joined(separator: ", ")
                return encodeToolError(error: "invalid_layout", message: "Unknown layout: \(layout)", suggestion: "Use one of: \(validLayouts).")
            }

            var results: [WindowBoundsResult] = []
            for wid in windowIds {
                let state = try ServiceContainer.shared.accessibilityEngine.getWindowState(windowId: wid)
                results.append(WindowBoundsResult(
                    success: true, action: "arrange_windows", windowId: wid,
                    x: state.bounds.x, y: state.bounds.y,
                    width: state.bounds.width, height: state.bounds.height
                ))
            }

            let result = ArrangeResult(success: true, action: "arrange_windows", layout: layout, windows: results)
            return encodeToolResult(result)
        } catch let error as AccessibilityEngineError {
            return encodeToolError(error)
        }
    }
}
