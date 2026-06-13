import Foundation
import Testing
import OpenAgentSDK

@testable import AxionCLI

// Dedicated unit suite for the AxionConfig → [MCPStatusEntry] bridge in
// SlashCommandHandler+MCP.swift. The formatter (MCPStatusFormatter) and the
// interactive browser (MCPSelectionPrompt) already have their own suites; this
// one targets the entry-construction, secret redaction, and reserved/invalid
// name handling that previously only ran under the E2E target.
@Suite("SlashCommandHandler MCP Status")
struct SlashCommandHandlerMCPStatusTests {

    // MARK: - Helpers

    /// Build a chat-mode BuildConfig (includePlaywright == true per AgentBuilder+Config).
    private func chatBuildConfig(_ config: AxionConfig) -> AgentBuilder.BuildConfig {
        AgentBuilder.BuildConfig.forChat(config: config)
    }

    private func config(_ servers: [String: AxionMcpServerConfig]) -> AxionConfig {
        var config = AxionConfig.default
        config.mcpServers = servers
        return config
    }

    private func entries(_ all: [MCPStatusEntry], named name: String) -> [MCPStatusEntry] {
        all.filter { $0.name == name }
    }

    // MARK: - P0: sse auth-headers redaction (new feature, zero prior unit coverage)

    @Test("mcpStatusEntries 对 sse server 的 headers 脱敏且保留 key")
    func sseServerHeadersAreRedactedInEntries() throws {
        let secret = "Bearer super-secret-sse-token"
        let config = self.config([
            "web-search-sse": .sse(
                url: "https://open.bigmodel.cn/api/mcp/sse",
                headers: ["Authorization": secret]
            ),
        ])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )

        let sseEntries = entries(result, named: "web-search-sse")
        #expect(sseEntries.count == 1)
        let sse = try #require(sseEntries.first)
        #expect(sse.type == "sse")
        #expect(sse.state == "ready")
        #expect(sse.source == "config")
        #expect(sse.details.contains("url: https://open.bigmodel.cn/api/mcp/sse"))
        #expect(sse.details.contains("headers: Authorization=<redacted>"))
        // No detail line may carry the secret value.
        #expect(sse.details.allSatisfy { !$0.contains(secret) })
    }

    @Test("handleMCPStatus 渲染输出绝不泄漏 sse server 的 header 密钥")
    func sseServerSecretsDoNotLeakInRenderedOutput() {
        let secret = "Bearer super-secret-sse-token"
        let config = self.config([
            "web-search-sse": .sse(
                url: "https://open.bigmodel.cn/api/mcp/sse",
                headers: ["Authorization": secret]
            ),
        ])

        let output = SlashCommandHandler.handleMCPStatus(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )

        #expect(output.contains("web-search-sse"))
        #expect(output.contains("headers: Authorization=<redacted>"))
        #expect(!output.contains(secret))
    }

    @Test("多个 header/env key 全部脱敏并按字典序排序")
    func multipleKeysAreSortedAndRedacted() throws {
        let headerSecret = "header-value"
        let envSecret = "env-value"
        let config = self.config([
            "multi-http": .http(
                url: "https://example.com/mcp",
                headers: [
                    "X-Custom": headerSecret,
                    "Authorization": headerSecret,
                    "Z-Trace": headerSecret,
                ]
            ),
            "multi-stdio": .stdio(
                command: "npx",
                args: ["-y", "server"],
                env: [
                    "Z_AI_API_KEY": envSecret,
                    "DEBUG": envSecret,
                    "ABC_TOKEN": envSecret,
                ]
            ),
        ])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )

        let http = try #require(entries(result, named: "multi-http").first)
        #expect(http.details.contains("headers: Authorization=<redacted>, X-Custom=<redacted>, Z-Trace=<redacted>"))
        #expect(!http.details.contains(headerSecret))

        let stdio = try #require(entries(result, named: "multi-stdio").first)
        #expect(stdio.details.contains("env: ABC_TOKEN=<redacted>, DEBUG=<redacted>, Z_AI_API_KEY=<redacted>"))
        #expect(!stdio.details.contains(envSecret))
    }

    // MARK: - P1: reserved name handling

    @Test("user config 中的 axion-helper 被标记为 ignored reserved server name")
    func reservedAxionHelperInConfigYieldsIgnoredEntry() throws {
        let config = self.config([
            "axion-helper": .stdio(command: "/usr/bin/false", args: nil, env: nil),
        ])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )

        let helperEntries = entries(result, named: "axion-helper")
        // Built-in ready entry plus the config-supplied ignored entry.
        #expect(helperEntries.contains { $0.state == "ready" && $0.source == "built-in" })
        let ignored = try #require(helperEntries.first { $0.state == "ignored" })
        #expect(ignored.source == "config")
        #expect(ignored.details.contains("reason: reserved server name"))
        #expect(ignored.type == "-")
    }

    @Test("user config 中 playwright 使用 sse/http 被忽略并提示 must use stdio")
    func playwrightUserConfigHttpOrSseIsIgnoredAsMustUseStdio() throws {
        let config = self.config([
            "playwright": .http(url: "https://example.com/mcp", headers: nil),
        ])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            // Should not be consulted: user-config branch wins over auto-include.
            playwrightResolver: { nil }
        )

        let pw = try #require(entries(result, named: "playwright").first)
        #expect(pw.state == "ignored")
        #expect(pw.source == "config")
        #expect(pw.details.contains("reason: reserved playwright server must use stdio"))
    }

    @Test("user config 中 playwright 使用 stdio 渲染为 ready config 条目")
    func playwrightUserConfigStdioIsReadyConfigEntry() throws {
        let config = self.config([
            "playwright": .stdio(command: "npx", args: ["-y", "@playwright/mcp"], env: nil),
        ])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )

        let pw = try #require(entries(result, named: "playwright").first)
        #expect(pw.state == "ready")
        #expect(pw.source == "config")
        #expect(pw.type == "stdio")
        #expect(pw.details.contains("command: npx -y @playwright/mcp"))
    }

    @Test("playwright 自动解析命中时渲染为 ready auto 条目")
    func playwrightAutoResolvedIsReadyAutoEntry() throws {
        // No playwright in user config; includePlaywright is true (forChat).
        let config = self.config([
            "unrelated": .stdio(command: "npx", args: ["-y", "other"], env: nil),
        ])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            playwrightResolver: {
                .stdio(McpStdioConfig(command: "npx", args: ["-y", "@playwright/mcp"]))
            }
        )

        let pw = try #require(entries(result, named: "playwright").first)
        #expect(pw.state == "ready")
        #expect(pw.source == "auto")
        #expect(pw.type == "stdio")
        #expect(pw.details.contains("command: npx -y @playwright/mcp"))
    }

    // MARK: - P2: validation + state transitions + optional fields

    @Test("含双下划线的非法 server name 被标记 ignored invalid server name")
    func invalidServerNameWithDoubleUnderscoreIsIgnored() throws {
        let config = self.config([
            "bad__name": .stdio(command: "npx", args: nil, env: nil),
        ])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )

        let bad = try #require(entries(result, named: "bad__name").first)
        #expect(bad.state == "ignored")
        #expect(bad.details.contains("reason: invalid server name"))
    }

    @Test("helperPath 为 nil 时 axion-helper 标记为 missing")
    func helperPathNilMarksAxionHelperMissing() throws {
        let config = self.config([:])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: nil,
            playwrightResolver: { nil }
        )

        let helper = try #require(entries(result, named: "axion-helper").first)
        #expect(helper.state == "missing")
        #expect(helper.details.contains("command: (not found)"))
    }

    @Test("stdio 无 env 时不输出 env 详情行")
    func stdioWithoutEnvOmitsEnvDetail() throws {
        let config = self.config([
            "plain-stdio": .stdio(command: "npx", args: ["-y", "server"], env: nil),
        ])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )

        let entry = try #require(entries(result, named: "plain-stdio").first)
        #expect(entry.details.contains("command: npx -y server"))
        #expect(!entry.details.contains { $0.hasPrefix("env:") })
    }

    @Test("sse/http 无 headers 时不输出 headers 详情行")
    func sseAndHttpWithoutHeadersOmitHeadersDetail() throws {
        let config = self.config([
            "plain-sse": .sse(url: "https://example.com/sse", headers: nil),
            "plain-http": .http(url: "https://example.com/mcp", headers: nil),
        ])

        let result = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: chatBuildConfig(config),
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )

        let sse = try #require(entries(result, named: "plain-sse").first)
        #expect(sse.details.contains("url: https://example.com/sse"))
        #expect(!sse.details.contains { $0.hasPrefix("headers:") })

        let http = try #require(entries(result, named: "plain-http").first)
        #expect(http.details.contains("url: https://example.com/mcp"))
        #expect(!http.details.contains { $0.hasPrefix("headers:") })
    }
}
