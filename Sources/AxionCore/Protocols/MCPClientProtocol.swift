import Foundation

public protocol MCPClientProtocol {
    func callTool(name: String, arguments: [String: Value]) async throws -> String
    func listTools() async throws -> [String]
}
