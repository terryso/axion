import Foundation
import MCP
import MCPTool

/// Centralized registration of all AxionHelper MCP tools.
///
/// Delegates to category-specific registration functions in separate files.
enum ToolRegistrar {

    /// Registers all AxionHelper tools on the given MCP server.
    static func registerAll(to server: MCPServer) async throws {
        try await AppTools.register(to: server)
        try await WindowTools.register(to: server)
        try await MouseTools.register(to: server)
        try await KeyboardTools.register(to: server)
        try await ScreenshotTools.register(to: server)
        try await RecordingTools.register(to: server)
    }
}
