import MCP
import MCPTool

enum MouseTools {
    static func register(to server: MCPServer) async throws {
        try await server.register {
            ClickTool.self
            ClickElementTool.self
            DoubleClickTool.self
            RightClickTool.self
            ScrollTool.self
            DragTool.self
        }
    }
}
