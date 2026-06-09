import MCP
import MCPTool

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
            return encodeToolResult(result)
        } catch let error as InputSimulationError {
            return encodeToolError(error)
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
            return encodeToolResult(result)
        } catch let error as InputSimulationError {
            return encodeToolError(error)
        }
    }
}
