import OpenAgentSDK
import Testing
@testable import AxionCLI

@Suite("MCPConfigResolver")
struct MCPConfigResolverTests {

    @Test("without user servers returns helper only when playwright disabled")
    func test_withoutUserServers_returnsHelperOnlyWhenPlaywrightDisabled() {
        let servers = MCPConfigResolver.resolveMCPServers(
            helperPath: "/real/helper",
            includePlaywright: false
        )

        #expect(servers.count == 1)
        #expect(stdioConfig(servers["axion-helper"])?.command == "/real/helper")
    }

    @Test("adds user stdio server")
    func test_userStdioServer_isAdded() {
        let servers = MCPConfigResolver.resolveMCPServers(
            helperPath: "/real/helper",
            includePlaywright: false,
            userServers: [
                "my-server": .stdio(
                    command: "node",
                    args: ["server.js"],
                    env: ["FOO": "bar"]
                )
            ]
        )

        let config = stdioConfig(servers["my-server"])
        #expect(config?.command == "node")
        #expect(config?.args == ["server.js"])
        #expect(config?.env == ["FOO": "bar"])
        #expect(stdioConfig(servers["axion-helper"])?.command == "/real/helper")
    }

    @Test("adds user sse and http servers")
    func test_userRemoteServers_areAdded() {
        let servers = MCPConfigResolver.resolveMCPServers(
            helperPath: "/real/helper",
            includePlaywright: false,
            userServers: [
                "sse-server": .sse(url: "http://localhost:8080/sse"),
                "http-server": .http(url: "http://localhost:8080/mcp"),
            ]
        )

        #expect(sseConfig(servers["sse-server"])?.url == "http://localhost:8080/sse")
        #expect(httpConfig(servers["http-server"])?.url == "http://localhost:8080/mcp")
    }

    @Test("reserved axion helper key is ignored")
    func test_reservedAxionHelperKey_isIgnored() {
        var warnings: [String] = []
        let servers = MCPConfigResolver.resolveMCPServers(
            helperPath: "/real/helper",
            includePlaywright: false,
            userServers: [
                "axion-helper": .stdio(command: "/tmp/fake", args: nil, env: nil)
            ],
            writeWarning: { warnings.append($0) }
        )

        #expect(stdioConfig(servers["axion-helper"])?.command == "/real/helper")
        #expect(warnings.contains { $0.contains("axion-helper") })
    }

    @Test("user playwright stdio overrides automatic discovery")
    func test_userPlaywrightStdio_overridesAutomaticDiscovery() {
        let servers = MCPConfigResolver.resolveMCPServers(
            helperPath: "/real/helper",
            includePlaywright: true,
            userServers: [
                "playwright": .stdio(
                    command: "/custom/node",
                    args: ["/custom/cli.js", "--port", "9999"],
                    env: nil
                )
            ]
        )

        let config = stdioConfig(servers["playwright"])
        #expect(config?.command == "/custom/node")
        #expect(config?.args == ["/custom/cli.js", "--port", "9999"])
    }

    @Test("user playwright non stdio is ignored")
    func test_userPlaywrightNonStdio_isIgnored() {
        var warnings: [String] = []
        let servers = MCPConfigResolver.resolveMCPServers(
            helperPath: "/real/helper",
            includePlaywright: true,
            userServers: [
                "playwright": .sse(url: "http://localhost:8080/sse")
            ],
            writeWarning: { warnings.append($0) }
        )

        #expect(servers["playwright"] == nil)
        #expect(warnings.contains { $0.contains("playwright") })
    }

    @Test("invalid user server names are ignored")
    func test_invalidUserServerNames_areIgnored() {
        var warnings: [String] = []
        let servers = MCPConfigResolver.resolveMCPServers(
            helperPath: "/real/helper",
            includePlaywright: false,
            userServers: [
                "bad__server": .stdio(command: "node", args: nil, env: nil),
                "   ": .stdio(command: "node", args: nil, env: nil),
                "valid-server": .stdio(command: "node", args: nil, env: nil),
            ],
            writeWarning: { warnings.append($0) }
        )

        #expect(servers["bad__server"] == nil)
        #expect(servers["   "] == nil)
        #expect(stdioConfig(servers["valid-server"])?.command == "node")
        #expect(warnings.count == 2)
    }

    private func stdioConfig(_ config: McpServerConfig?) -> McpStdioConfig? {
        guard case let .stdio(stdio)? = config else { return nil }
        return stdio
    }

    private func sseConfig(_ config: McpServerConfig?) -> McpSseConfig? {
        guard case let .sse(sse)? = config else { return nil }
        return sse
    }

    private func httpConfig(_ config: McpServerConfig?) -> McpHttpConfig? {
        guard case let .http(http)? = config else { return nil }
        return http
    }
}
