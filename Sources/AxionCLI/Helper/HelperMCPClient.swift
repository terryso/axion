import MCP

// MARK: - HelperMCPClientProtocol

/// Protocol abstracting MCPClient for testability.
///
/// Production uses ``RealHelperMCPClient`` wrapping ``MCPClient``.
/// Tests inject ``MockHelperMCPClient`` to control tool call results.
protocol HelperMCPClientProtocol: Sendable {
    func connect(transport: @escaping @Sendable () async throws -> any Transport) async throws
    func disconnect() async
    func callTool(name: String, arguments: [String: MCP.Value]?) async throws -> CallTool.Result
    func listTools() async throws -> ListTools.Result
}

// MARK: - RealHelperMCPClient

/// Production MCP client wrapping SDK's ``MCPClient``.
actor RealHelperMCPClient: HelperMCPClientProtocol {
    private let client: MCPClient

    init() {
        self.client = MCPClient(
            name: "AxionCLI",
            version: "1.0.0",
            reconnectionOptions: MCPClient.ReconnectionOptions(
                maxRetries: 0,
                initialDelay: .seconds(1),
                maxDelay: .seconds(1),
                delayGrowFactor: 1.0,
                healthCheckInterval: nil
            )
        )
    }

    func connect(transport: @escaping @Sendable () async throws -> any Transport) async throws {
        try await client.connect(transport: transport)
    }

    func disconnect() async {
        await client.disconnect()
    }

    func callTool(name: String, arguments: [String: MCP.Value]?) async throws -> CallTool.Result {
        try await client.callTool(name: name, arguments: arguments)
    }

    func listTools() async throws -> ListTools.Result {
        try await client.listTools()
    }
}
