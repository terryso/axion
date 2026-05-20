import AxionCore
import Foundation
import OpenAgentSDK

/// Resolves MCP server configurations for desktop automation and Playwright.
enum MCPConfigResolver {

    /// Builds the MCP server dictionary with the AxionHelper stdio server and
    /// optionally the Playwright MCP server.
    ///
    /// - Parameters:
    ///   - helperPath: Resolved path to AxionHelper.app executable.
    ///   - includePlaywright: Whether to include the Playwright MCP server.
    /// - Returns: Dictionary of MCP server configs keyed by name.
    static func resolveMCPServers(helperPath: String, includePlaywright: Bool) -> [String: McpServerConfig] {
        var mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath)),
        ]
        if includePlaywright {
            if let playwrightConfig = resolvePlaywrightConfig() {
                mcpServers["playwright"] = playwrightConfig
            }
        }
        return mcpServers
    }

    /// Resolves the Playwright MCP server configuration.
    ///
    /// Uses Node directly with the installed `@playwright/mcp` module to avoid
    /// shebang/PATH issues. Finds the newest Node 18+ version from nvm and
    /// locates the playwright-mcp CLI entry point.
    static func resolvePlaywrightConfig() -> McpServerConfig? {
        let nvmDir = ProcessInfo.processInfo.environment["NVM_DIR"]
            ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.nvm"
        let nvmVersionsDir = "\(nvmDir)/versions/node"

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) else {
            return nil
        }

        let nodeVersions = contents.filter { $0.hasPrefix("v") }
            .compactMap { version -> (version: String, major: Int)? in
                let numStr = version.dropFirst()
                let major = numStr.split(separator: ".").first.flatMap { Int($0) }
                guard let major, major >= 18 else { return nil }
                return (version, major)
            }
            .sorted { $0.version > $1.version }

        for (version, _) in nodeVersions {
            let nodeBin = "\(nvmVersionsDir)/\(version)/bin/node"
            let cliPath = "\(nvmVersionsDir)/\(version)/lib/node_modules/@playwright/mcp/cli.js"

            guard FileManager.default.fileExists(atPath: nodeBin),
                  FileManager.default.fileExists(atPath: cliPath) else {
                continue
            }

            return .stdio(McpStdioConfig(
                command: nodeBin,
                args: [cliPath, "--headless"]
            ))
        }

        return nil
    }
}
