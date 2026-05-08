import Foundation
import MCP
import MCPTool

/// AxionHelper MCP Server entry point.
///
/// Creates an `MCPServer` configured with all AxionHelper tools
/// and starts listening on stdio for JSON-RPC requests.
///
/// Usage:
/// ```swift
/// try await HelperMCPServer.run()
/// ```
enum HelperMCPServer {

    /// Starts the MCP server with stdio transport.
    ///
    /// This method blocks until stdin receives EOF or an error occurs.
    /// All tools are registered as stubs — actual implementations are
    /// added in subsequent stories.
    ///
    /// - Throws: Any error from MCP server initialization or transport.
    static func run() async throws {
        let server = MCPServer(
            name: "AxionHelper",
            version: "0.1.0"
        )

        try await ToolRegistrar.registerAll(to: server)

        let session = await server.createSession()
        let stdioTransport = StdioTransport()
        try await session.start(transport: stdioTransport)

        // Block until stdin closes (EOF) or transport disconnects
        await session.waitUntilCompleted()
    }
}
