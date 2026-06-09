import MCP
import MCPTool

enum WindowTools {
    static func register(to server: MCPServer) async throws {
        try await server.register {
            ActivateWindowTool.self
            ListWindowsTool.self
            GetWindowStateTool.self
            ValidateWindowTool.self
            ResizeWindowTool.self
            ArrangeWindowsTool.self
        }
    }
}
