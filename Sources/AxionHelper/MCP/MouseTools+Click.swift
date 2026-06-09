import MCP
import MCPTool

// MARK: - Click Tools (Story 1.4)

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
struct ClickElementTool {
    static let name = "click_element"
    static let description = "Click an AX element by title or role in a window. Resolves the element's center coordinates automatically — no manual coordinate lookup needed."

    @Parameter(key: "window_id", description: "Window identifier")
    var windowId: Int

    @Parameter(description: "Exact element title to match (e.g. \"3\", \"OK\", \"AC\")")
    var title: String?

    @Parameter(key: "title_contains", description: "Partial title match (case-insensitive)")
    var titleContains: String?

    @Parameter(description: "AX role filter (e.g. \"AXButton\")")
    var role: String?

    @Parameter(description: "0-based index when multiple elements match the same criteria")
    var ordinal: Int?

    func perform() async throws -> String {
        let query = SelectorQuery(
            title: title,
            titleContains: titleContains,
            axId: nil,
            role: role,
            ordinal: ordinal
        )
        do {
            let result = try ServiceContainer.shared.accessibilityEngine.resolveSelector(windowId: windowId, query: query)
            try ServiceContainer.shared.inputSimulation.click(x: result.x, y: result.y)
            return encodeClickResult(action: "click_element", x: result.x, y: result.y)
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
