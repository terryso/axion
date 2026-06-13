import Testing

@testable import AxionCLI

@Suite("MCP Status Formatter")
struct MCPStatusFormatterTests {
    private func entry(
        _ name: String,
        type: String = "stdio",
        source: String = "config",
        state: String = "ready",
        details: [String] = ["command: npx -y server", "env: TOKEN=<redacted>"]
    ) -> MCPStatusEntry {
        MCPStatusEntry(
            name: name,
            type: type,
            source: source,
            state: state,
            details: details
        )
    }

    @Test("renderList shows first window with controls")
    func renderListShowsFirstWindow() {
        let entries = (1...20).map { entry("server-\($0)") }

        let output = MCPStatusFormatter.renderList(
            entries,
            selectedIndex: 0,
            maxItems: 15,
            startIndex: 0,
            terminalWidth: 100
        )

        #expect(output.contains("MCP servers（20 ready，20 total），显示 1-15"))
        #expect(output.contains("↑/↓ 选择"))
        #expect(output.contains("Enter 详情"))
        #expect(output.contains("显示 1-15 / 20"))
        #expect(output.contains("▶ server-1"))
        #expect(output.contains("server-15"))
        #expect(!output.contains("server-16"))
        #expect(!output.contains("command:"))
    }

    @Test("renderList supports shifted window")
    func renderListSupportsShiftedWindow() {
        let entries = (1...20).map { entry("server-\($0)") }

        let output = MCPStatusFormatter.renderList(
            entries,
            selectedIndex: 15,
            maxItems: 15,
            startIndex: 1,
            terminalWidth: 100
        )

        #expect(output.contains("显示 2-16 / 20"))
        #expect(output.contains("server-2"))
        #expect(output.contains("▶ server-16"))
        #expect(!output.contains("  server-1        stdio"))
    }

    @Test("renderDetail includes redacted configuration")
    func renderDetailIncludesRedactedConfiguration() {
        let output = MCPStatusFormatter.renderDetail(
            entry(
                "web-search-prime",
                type: "http",
                details: [
                    "url: https://open.bigmodel.cn/api/mcp/web_search_prime/mcp",
                    "headers: Authorization=<redacted>",
                ]
            ),
            terminalWidth: 120
        )

        #expect(output.contains("MCP server 详情"))
        #expect(output.contains("名称: web-search-prime"))
        #expect(output.contains("状态: ready"))
        #expect(output.contains("来源: config"))
        #expect(output.contains("类型: http"))
        #expect(output.contains("命名空间: mcp__web-search-prime__<tool>"))
        #expect(output.contains("headers: Authorization=<redacted>"))
        #expect(output.contains("headers/env 只显示 key"))
    }

    @Test("renderAll prints full redacted details")
    func renderAllPrintsFullRedactedDetails() {
        let longURL = "url: https://open.bigmodel.cn/api/mcp/web_search_prime/mcp?very_long_query_parameter=abcdefghijklmnopqrstuvwxyz"
        let output = MCPStatusFormatter.renderAll([
            entry("axion-helper", source: "built-in"),
            entry("zai-mcp-server", details: [
                "command: npx -y @z_ai/mcp-server",
                "env: Z_AI_API_KEY=<redacted>",
            ]),
            entry("web-search-prime", type: "http", details: [longURL]),
        ], terminalWidth: 48)

        #expect(output.contains("MCP servers（3 ready，3 total）"))
        #expect(output.contains("axion-helper"))
        #expect(output.contains("zai-mcp-server"))
        #expect(output.contains("command: npx -y @z_ai/mcp-server"))
        #expect(output.contains("env: Z_AI_API_KEY=<redacted>"))
        #expect(output.contains(longURL))
        #expect(!output.contains("…"))
    }

    @Test("renderList 空列表显示未找到提示")
    func renderListEmptyEntriesShowsNotFound() {
        let output = MCPStatusFormatter.renderList(
            [],
            selectedIndex: nil,
            maxItems: 15,
            terminalWidth: 100
        )

        #expect(output.contains("MCP servers（0 ready，0 total）"))
        #expect(output.contains("未找到 MCP server"))
        #expect(!output.contains("Server"))
    }

    @Test("renderDetail 空详情显示占位短横")
    func renderDetailEmptyDetailsShowsDash() {
        let output = MCPStatusFormatter.renderDetail(
            entry("solo", details: []),
            terminalWidth: 100
        )

        #expect(output.contains("详情: -"))
        #expect(!output.contains("配置:"))
    }

    @Test("renderDetail 对非 ready 或含双下划线的名字不渲染命名空间")
    func renderDetailNamespaceDashForNonReadyAndDoubleUnderscore() {
        let nonReady = MCPStatusFormatter.renderDetail(
            entry("worker", state: "missing", details: []),
            terminalWidth: 100
        )
        #expect(nonReady.contains("命名空间: -"))

        let underscoreName = MCPStatusFormatter.renderDetail(
            entry("bad__name", details: []),
            terminalWidth: 100
        )
        #expect(underscoreName.contains("命名空间: -"))
    }

    @Test("renderList 截断超长 server 名并补省略号")
    func renderListTruncatesLongServerName() {
        // Name longer than the max name width (30) is truncated with an ellipsis.
        let longName = "this-is-a-very-long-mcp-server-name-that-exceeds-thirty-chars"
        let output = MCPStatusFormatter.renderList(
            [entry(longName)],
            selectedIndex: 0,
            maxItems: 15,
            terminalWidth: 100
        )

        #expect(output.contains("…"))
        #expect(!output.contains(longName))
    }
}
