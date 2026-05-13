import ArgumentParser
import Foundation

import AxionCore

/// `axion mcp` — Start an MCP stdio server exposing Axion's desktop automation tools.
struct McpCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "启动 MCP stdio 服务器，暴露 Axion 工具供外部 Agent 调用"
    )

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    func run() async throws {
        let config = try await ConfigManager.loadConfig()
        let runner = MCPServerRunner(config: config, verbose: verbose)
        try await runner.run()
    }
}
