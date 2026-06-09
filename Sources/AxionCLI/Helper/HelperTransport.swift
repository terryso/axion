import MCP
import OpenAgentSDK

// MARK: - HelperTransportProtocol

/// Protocol abstracting MCPStdioTransport for testability.
///
/// Production uses ``RealHelperTransport`` wrapping ``MCPStdioTransport``.
/// Tests inject ``MockHelperTransport`` to isolate from real Process management.
protocol HelperTransportProtocol: Sendable {
    func connect() async throws
    func disconnect() async
    func getIsRunning() async -> Bool
    /// Returns the underlying Transport for MCPClient.connect's transport factory.
    func getTransport() async -> (any Transport)?
}

// MARK: - RealHelperTransport

/// Production transport wrapping SDK's ``MCPStdioTransport``.
actor RealHelperTransport: HelperTransportProtocol {
    private let transport: MCPStdioTransport

    init(config: McpStdioConfig) {
        self.transport = MCPStdioTransport(config: config)
    }

    func connect() async throws {
        try await transport.connect()
    }

    func disconnect() async {
        await transport.disconnect()
    }

    func getIsRunning() async -> Bool {
        await transport.isRunning
    }

    func getTransport() async -> (any Transport)? {
        transport as any Transport
    }
}
