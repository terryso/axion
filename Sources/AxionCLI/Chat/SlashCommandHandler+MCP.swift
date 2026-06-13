import Foundation
import OpenAgentSDK

extension SlashCommandHandler {

    static func handleMCPStatus(
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        helperPath: String? = HelperPathResolver.resolveHelperPath(),
        playwrightResolver: () -> McpServerConfig? = MCPConfigResolver.resolvePlaywrightConfig
    ) -> String {
        if buildConfig.dryrun {
            return """
            MCP servers:
              MCP disabled in dryrun mode.

            """
        }

        let userServers = config.mcpServers ?? [:]
        let entries = makeMCPStatusEntries(
            helperPath: helperPath,
            includePlaywright: buildConfig.includePlaywright,
            userServers: userServers,
            playwrightResolver: playwrightResolver
        )

        let enabledCount = entries.filter { $0.state != "ignored" }.count
        var lines = ["MCP servers (\(enabledCount) enabled):", ""]
        let nameWidth = max((entries.map(\.name.count).max() ?? 0) + 2, 16)
        let typeWidth = 7
        let sourceWidth = 9

        for entry in entries {
            let name = entry.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            let type = entry.type.padding(toLength: typeWidth, withPad: " ", startingAt: 0)
            let source = entry.source.padding(toLength: sourceWidth, withPad: " ", startingAt: 0)
            lines.append("  \(name)\(type)\(source)\(entry.state)")
            for detail in entry.details {
                lines.append("    \(detail)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n") + "\n"
    }

    private struct MCPStatusEntry {
        let name: String
        let type: String
        let source: String
        let state: String
        let details: [String]
    }

    private static func makeMCPStatusEntries(
        helperPath: String?,
        includePlaywright: Bool,
        userServers: [String: AxionMcpServerConfig],
        playwrightResolver: () -> McpServerConfig?
    ) -> [MCPStatusEntry] {
        var entries: [MCPStatusEntry] = []

        entries.append(
            MCPStatusEntry(
                name: "axion-helper",
                type: "stdio",
                source: "built-in",
                state: helperPath == nil ? "missing" : "ready",
                details: [
                    "command: \(helperPath ?? "(not found)")",
                    "tools: desktop automation",
                ]
            )
        )

        if userServers["axion-helper"] != nil {
            entries.append(
                MCPStatusEntry(
                    name: "axion-helper",
                    type: "-",
                    source: "config",
                    state: "ignored",
                    details: ["reason: reserved server name"]
                )
            )
        }

        if let playwrightConfig = userServers["playwright"] {
            switch playwrightConfig {
            case .stdio:
                entries.append(statusEntry(name: "playwright", source: "config", config: playwrightConfig))
            case .sse, .http:
                entries.append(
                    MCPStatusEntry(
                        name: "playwright",
                        type: serverType(playwrightConfig),
                        source: "config",
                        state: "ignored",
                        details: ["reason: reserved playwright server must use stdio"]
                    )
                )
            }
        } else if includePlaywright {
            if let playwrightConfig = playwrightResolver() {
                entries.append(statusEntry(name: "playwright", source: "auto", config: playwrightConfig))
            } else {
                entries.append(
                    MCPStatusEntry(
                        name: "playwright",
                        type: "stdio",
                        source: "auto",
                        state: "missing",
                        details: ["reason: @playwright/mcp not found in Node 18+ installations"]
                    )
                )
            }
        }

        for name in userServers.keys.sorted() {
            guard name != "axion-helper", name != "playwright",
                  let serverConfig = userServers[name] else {
                continue
            }

            guard MCPConfigResolver.isValidServerName(name) else {
                entries.append(
                    MCPStatusEntry(
                        name: name,
                        type: serverType(serverConfig),
                        source: "config",
                        state: "ignored",
                        details: ["reason: invalid server name"]
                    )
                )
                continue
            }

            entries.append(statusEntry(name: name, source: "config", config: serverConfig))
        }

        return entries
    }

    private static func statusEntry(
        name: String,
        source: String,
        config: AxionMcpServerConfig
    ) -> MCPStatusEntry {
        switch config {
        case let .stdio(command, args, env):
            var details = ["command: \(formatCommand(command: command, args: args))"]
            if let env, !env.isEmpty {
                details.append("env: \(redactedKeys(env))")
            }
            return MCPStatusEntry(
                name: name,
                type: "stdio",
                source: source,
                state: "ready",
                details: details
            )
        case let .sse(url, headers):
            var details = ["url: \(url)"]
            if let headers, !headers.isEmpty {
                details.append("headers: \(redactedKeys(headers))")
            }
            return MCPStatusEntry(
                name: name,
                type: "sse",
                source: source,
                state: "ready",
                details: details
            )
        case let .http(url, headers):
            var details = ["url: \(url)"]
            if let headers, !headers.isEmpty {
                details.append("headers: \(redactedKeys(headers))")
            }
            return MCPStatusEntry(
                name: name,
                type: "http",
                source: source,
                state: "ready",
                details: details
            )
        }
    }

    private static func statusEntry(
        name: String,
        source: String,
        config: McpServerConfig
    ) -> MCPStatusEntry {
        switch config {
        case let .stdio(stdio):
            var details = ["command: \(formatCommand(command: stdio.command, args: stdio.args))"]
            if let env = stdio.env, !env.isEmpty {
                details.append("env: \(redactedKeys(env))")
            }
            return MCPStatusEntry(name: name, type: "stdio", source: source, state: "ready", details: details)
        case let .sse(sse):
            var details = ["url: \(sse.url)"]
            if let headers = sse.headers, !headers.isEmpty {
                details.append("headers: \(redactedKeys(headers))")
            }
            return MCPStatusEntry(name: name, type: "sse", source: source, state: "ready", details: details)
        case let .http(http):
            var details = ["url: \(http.url)"]
            if let headers = http.headers, !headers.isEmpty {
                details.append("headers: \(redactedKeys(headers))")
            }
            return MCPStatusEntry(name: name, type: "http", source: source, state: "ready", details: details)
        case .sdk:
            return MCPStatusEntry(
                name: name,
                type: "sdk",
                source: source,
                state: "ready",
                details: ["transport: in-process SDK"]
            )
        case .claudeAIProxy:
            return MCPStatusEntry(
                name: name,
                type: "proxy",
                source: source,
                state: "ready",
                details: ["transport: Claude AI proxy"]
            )
        }
    }

    private static func serverType(_ config: AxionMcpServerConfig) -> String {
        switch config {
        case .stdio: return "stdio"
        case .sse: return "sse"
        case .http: return "http"
        }
    }

    private static func formatCommand(command: String, args: [String]?) -> String {
        ([command] + (args ?? [])).joined(separator: " ")
    }

    private static func redactedKeys(_ values: [String: String]) -> String {
        values.keys.sorted().map { "\($0)=<redacted>" }.joined(separator: ", ")
    }
}
