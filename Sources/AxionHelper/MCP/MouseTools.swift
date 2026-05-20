import Foundation
import MCP
import MCPTool

enum MouseTools {
    static func register(to server: MCPServer) async throws {
        try await server.register {
            ClickTool.self
            DoubleClickTool.self
            RightClickTool.self
            ScrollTool.self
            DragTool.self
        }
    }
}

// MARK: - Mouse Tools (Story 1.4)

@Tool
struct ClickTool {
    static let name = "click"
    static let description = "Perform a single click, either at coordinates or by AX selector"

    @Parameter(description: "X coordinate (required when not using __selector)")
    var x: Int?

    @Parameter(description: "Y coordinate (required when not using __selector)")
    var y: Int?

    @Parameter(description: "Process ID of the target application (used with __selector)")
    var pid: Int?

    @Parameter(key: "window_id", description: "Window identifier (required with __selector)")
    var windowId: Int?

    @Parameter(key: "__selector", description: "AX element selector: { title?, title_contains?, ax_id?, role?, ordinal? }")
    var selector: SelectorQuery?

    func perform() async throws -> String {
        do {
            let (resolvedX, resolvedY) = try resolveClickCoordinates(x: x, y: y, windowId: windowId, selector: selector)
            try ServiceContainer.shared.inputSimulation.click(x: resolvedX, y: resolvedY)
            return encodeClickResult(action: "click", x: resolvedX, y: resolvedY)
        } catch let error as InputSimulationError {
            return encodeError(error)
        } catch let error as AccessibilityEngineService.SelectorError {
            return encodeSelectorError(error)
        }
    }
}

@Tool
struct DoubleClickTool {
    static let name = "double_click"
    static let description = "Perform a double click, either at coordinates or by AX selector"

    @Parameter(description: "X coordinate (required when not using __selector)")
    var x: Int?

    @Parameter(description: "Y coordinate (required when not using __selector)")
    var y: Int?

    @Parameter(description: "Process ID of the target application (used with __selector)")
    var pid: Int?

    @Parameter(key: "window_id", description: "Window identifier (required with __selector)")
    var windowId: Int?

    @Parameter(key: "__selector", description: "AX element selector: { title?, title_contains?, ax_id?, role?, ordinal? }")
    var selector: SelectorQuery?

    func perform() async throws -> String {
        do {
            let (resolvedX, resolvedY) = try resolveClickCoordinates(x: x, y: y, windowId: windowId, selector: selector)
            try ServiceContainer.shared.inputSimulation.doubleClick(x: resolvedX, y: resolvedY)
            return encodeClickResult(action: "double_click", x: resolvedX, y: resolvedY)
        } catch let error as InputSimulationError {
            return encodeError(error)
        } catch let error as AccessibilityEngineService.SelectorError {
            return encodeSelectorError(error)
        }
    }
}

@Tool
struct RightClickTool {
    static let name = "right_click"
    static let description = "Perform a right click, either at coordinates or by AX selector"

    @Parameter(description: "X coordinate (required when not using __selector)")
    var x: Int?

    @Parameter(description: "Y coordinate (required when not using __selector)")
    var y: Int?

    @Parameter(description: "Process ID of the target application (used with __selector)")
    var pid: Int?

    @Parameter(key: "window_id", description: "Window identifier (required with __selector)")
    var windowId: Int?

    @Parameter(key: "__selector", description: "AX element selector: { title?, title_contains?, ax_id?, role?, ordinal? }")
    var selector: SelectorQuery?

    func perform() async throws -> String {
        do {
            let (resolvedX, resolvedY) = try resolveClickCoordinates(x: x, y: y, windowId: windowId, selector: selector)
            try ServiceContainer.shared.inputSimulation.rightClick(x: resolvedX, y: resolvedY)
            return encodeClickResult(action: "right_click", x: resolvedX, y: resolvedY)
        } catch let error as InputSimulationError {
            return encodeError(error)
        } catch let error as AccessibilityEngineService.SelectorError {
            return encodeSelectorError(error)
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
