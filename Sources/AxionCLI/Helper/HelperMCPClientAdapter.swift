import AxionCore

struct HelperMCPClientAdapter: MCPClientProtocol {
    let manager: HelperProcessManager

    func callTool(name: String, arguments: [String: Value]) async throws -> String {
        try await manager.callTool(name: name, arguments: arguments)
    }

    func listTools() async throws -> [String] {
        try await manager.listTools()
    }
}
