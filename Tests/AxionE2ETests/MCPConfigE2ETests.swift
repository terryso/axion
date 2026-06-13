import Foundation
import OpenAgentSDK
import Testing
@testable import AxionCLI

@Suite("MCP Config E2E", .serialized)
struct MCPConfigE2ETests {
    private let pythonPath = "/Users/nick/.browser-use-env/bin/python3"

    @Test("user stdio MCP server is discovered through real SDK MCP connection")
    func userStdioMcpServerIsDiscoveredThroughRealSDKConnection() async throws {
        let fixture = try makeProbeFixture(label: "stdio-discovery")
        defer { cleanup(fixture.root) }

        let config = AxionConfig(
            apiKey: "sk-test",
            maxSteps: 1,
            mcpServers: [
                "acceptance-probe": .stdio(
                    command: pythonPath,
                    args: [fixture.script.path],
                    env: ["AXION_MCP_ACCEPTANCE_LOG": fixture.log.path]
                )
            ]
        )
        let result = buildMCPAgent(config: config, helperPath: fixture.helper.path)

        let (tools, manager) = await result.agent.assembleFullToolPool()
        let toolNames = Set(tools.map(\.name))
        let connections = await manager?.getConnections() ?? [:]
        await manager?.shutdown()
        try? await result.agent.close()

        #expect(toolNames.contains("mcp__acceptance-probe__acceptance_ping"))
        #expect(connections["acceptance-probe"]?.status == .connected)
        let log = try String(contentsOf: fixture.log, encoding: .utf8)
        #expect(log.contains("method initialize"))
        #expect(log.contains("method tools/list"))
    }

    @Test("dryrun build keeps user MCP servers out of AgentOptions")
    func dryrunBuildKeepsUserMcpServersOutOfAgentOptions() async throws {
        let fixture = try makeProbeFixture(label: "dryrun")
        defer { cleanup(fixture.root) }

        let config = AxionConfig(
            apiKey: "sk-test",
            maxSteps: 1,
            mcpServers: [
                "acceptance-probe": .stdio(
                    command: pythonPath,
                    args: [fixture.script.path],
                    env: ["AXION_MCP_ACCEPTANCE_LOG": fixture.log.path]
                )
            ]
        )
        let result = try await AgentBuilder.build(
            AgentBuilder.BuildConfig.forCLI(
                config: config,
                task: "mcp config dryrun e2e",
                noMemory: true,
                noSkills: true,
                maxSteps: 1,
                dryrun: true
            )
        )

        let (tools, manager) = await result.agent.assembleFullToolPool()
        try? await result.agent.close()

        #expect(result.agentOptions.mcpServers == nil)
        #expect(manager == nil)
        #expect(!tools.map(\.name).contains("mcp__acceptance-probe__acceptance_ping"))
        #expect(!FileManager.default.fileExists(atPath: fixture.log.path))
    }

    @Test("bad mcpServers JSON degrades before real agent build")
    func badMcpServersJSONDegradesBeforeRealAgentBuild() async throws {
        let json = """
        {
          "apiKey": "sk-test",
          "maxSteps": 1,
          "mcpServers": {
            "acceptance-probe": {
              "type": "stdio",
              "command": "\(pythonPath)",
              "args": ["/tmp/probe.py"]
            },
            "broken": {
              "type": "stdio"
            }
          }
        }
        """
        let config = try JSONDecoder().decode(AxionConfig.self, from: Data(json.utf8))
        #expect(config.mcpServers == nil)

        let result = buildMCPAgent(config: config, helperPath: "/usr/bin/true")

        let names = Set(result.agentOptions.mcpServers?.keys.map { key in key } ?? [])
        #expect(names == ["axion-helper"])
        #expect(stdioConfig(result.agentOptions.mcpServers?["axion-helper"])?.command == "/usr/bin/true")
        try? await result.agent.close()
    }

    @Test("reserved axion-helper user config cannot override resolved helper")
    func reservedAxionHelperUserConfigCannotOverrideResolvedHelper() async throws {
        let config = AxionConfig(
            apiKey: "sk-test",
            maxSteps: 1,
            mcpServers: [
                "axion-helper": .stdio(command: "/usr/bin/false", args: nil, env: nil)
            ]
        )
        let result = buildMCPAgent(config: config, helperPath: "/usr/bin/true")

        let helper = stdioConfig(result.agentOptions.mcpServers?["axion-helper"])
        #expect(helper?.command == "/usr/bin/true")
        try? await result.agent.close()
    }

    @Test("custom Playwright stdio config survives CLI build")
    func customPlaywrightStdioConfigSurvivesCLIBuild() async throws {
        let config = AxionConfig(
            apiKey: "sk-test",
            maxSteps: 1,
            mcpServers: [
                "playwright": .stdio(
                    command: "/custom/playwright-node",
                    args: ["/custom/playwright-mcp.js", "--headless"],
                    env: ["PW_TEST": "1"]
                )
            ]
        )
        let result = buildMCPAgent(config: config, helperPath: "/usr/bin/true", includePlaywright: true)

        let playwright = stdioConfig(result.agentOptions.mcpServers?["playwright"])
        #expect(playwright?.command == "/custom/playwright-node")
        #expect(playwright?.args == ["/custom/playwright-mcp.js", "--headless"])
        #expect(playwright?.env == ["PW_TEST": "1"])
        try? await result.agent.close()
    }

    @Test("http MCP headers survive real agent build")
    func httpMcpHeadersSurviveRealAgentBuild() async throws {
        let config = AxionConfig(
            apiKey: "sk-test",
            maxSteps: 1,
            mcpServers: [
                "web-search-prime": .http(
                    url: "https://open.bigmodel.cn/api/mcp/web_search_prime/mcp",
                    headers: ["Authorization": "Bearer redacted"]
                )
            ]
        )
        let result = buildMCPAgent(config: config, helperPath: "/usr/bin/true")

        let http = httpConfig(result.agentOptions.mcpServers?["web-search-prime"])
        #expect(http?.url == "https://open.bigmodel.cn/api/mcp/web_search_prime/mcp")
        #expect(http?.headers == ["Authorization": "Bearer redacted"])
        try? await result.agent.close()
    }

    @Test("BigModel MCP config renders slash status with redacted secrets")
    func bigModelMcpConfigRendersSlashStatusWithRedactedSecrets() throws {
        let bearerSecret = "Bearer should-not-leak"
        let zaiSecret = "zai-secret-should-not-leak"
        let longURL = "https://open.bigmodel.cn/api/mcp/web_search_prime/mcp?query=abcdefghijklmnopqrstuvwxyz"
        let json = """
        {
          "apiKey": "sk-test",
          "maxSteps": 1,
          "mcpServers": {
            "web-search-prime": {
              "type": "http",
              "url": "\(longURL)",
              "headers": {
                "Authorization": "\(bearerSecret)"
              }
            },
            "zai-mcp-server": {
              "type": "stdio",
              "command": "\(pythonPath)",
              "args": ["-m", "zai_mcp_probe"],
              "env": {
                "Z_AI_API_KEY": "\(zaiSecret)"
              }
            },
            "web-reader": {
              "type": "http",
              "url": "https://open.bigmodel.cn/api/mcp/web_reader/mcp",
              "headers": {
                "Authorization": "\(bearerSecret)"
              }
            },
            "zread": {
              "type": "http",
              "url": "https://open.bigmodel.cn/api/mcp/zread/mcp",
              "headers": {
                "Authorization": "\(bearerSecret)"
              }
            }
          }
        }
        """
        let config = try JSONDecoder().decode(AxionConfig.self, from: Data(json.utf8))
        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            noMemory: true,
            noSkills: true,
            maxSteps: 1
        )

        let output = SlashCommandHandler.handleMCPStatus(
            config: config,
            buildConfig: buildConfig,
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )

        #expect(output.contains("MCP servers"))
        #expect(output.contains("web-search-prime"))
        #expect(output.contains("web-reader"))
        #expect(output.contains("zread"))
        #expect(output.contains("zai-mcp-server"))
        #expect(output.contains(longURL))
        #expect(output.contains("headers: Authorization=<redacted>"))
        #expect(output.contains("env: Z_AI_API_KEY=<redacted>"))
        #expect(!output.contains(bearerSecret))
        #expect(!output.contains(zaiSecret))
        #expect(!output.contains("…"))
    }

    @Test("interactive MCP list windows configured servers and opens redacted detail")
    func interactiveMcpListWindowsConfiguredServersAndOpensRedactedDetail() {
        let envSecret = "secret-for-windowed-detail"
        let servers = Dictionary(uniqueKeysWithValues: (1...18).map { index in
            (
                String(format: "server-%02d", index),
                AxionMcpServerConfig.stdio(
                    command: pythonPath,
                    args: ["server-\(index).py"],
                    env: ["TOKEN": "\(envSecret)-\(index)"]
                )
            )
        })
        let config = AxionConfig(apiKey: "sk-test", maxSteps: 1, mcpServers: servers)
        let buildConfig = AgentBuilder.BuildConfig.forAPI(
            config: config,
            task: "mcp windowed list e2e",
            request: CreateRunRequest(task: "mcp windowed list e2e", maxSteps: 1)
        )
        let entries = SlashCommandHandler.mcpStatusEntries(
            config: config,
            buildConfig: buildConfig,
            helperPath: "/usr/bin/true",
            playwrightResolver: { nil }
        )
        let output = OutputCapture()
        let prompt = MCPSelectionPrompt(
            isTTY: true,
            keyReader: MCPConfigE2EMockKeyReader(Array(repeating: KeyEvent.down, count: 15) + [.enter, .escape]),
            writeOutput: { output.write($0) },
            maxItems: 15,
            terminalWidth: 100
        )

        #expect(prompt.run(entries: entries) == .cancelled)
        #expect(output.text.contains("显示 2-16 / 19"))
        #expect(output.text.contains("MCP server 详情"))
        #expect(output.text.contains("名称: server-15"))
        #expect(output.text.contains("command: \(pythonPath) server-15.py"))
        #expect(output.text.contains("env: TOKEN=<redacted>"))
        #expect(!output.text.contains(envSecret))
    }

    private struct ProbeFixture {
        let root: URL
        let script: URL
        let helper: URL
        let log: URL
    }

    private func makeProbeFixture(label: String) throws -> ProbeFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxionMCPConfigE2E-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let script = root.appendingPathComponent("probe_mcp.py")
        let helper = root.appendingPathComponent("fake_helper")
        let log = root.appendingPathComponent("probe.log")
        try probeScript.write(to: script, atomically: true, encoding: .utf8)
        try probeExecutableScript.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return ProbeFixture(root: root, script: script, helper: helper, log: log)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func buildMCPAgent(
        config: AxionConfig,
        helperPath: String,
        includePlaywright: Bool = false
    ) -> (agent: Agent, agentOptions: AgentOptions) {
        let mcpServers = MCPConfigResolver.resolveMCPServers(
            helperPath: helperPath,
            includePlaywright: includePlaywright,
            userServers: config.mcpServers,
            writeWarning: { _ in }
        )
        let options = AgentOptions(
            apiKey: config.apiKey,
            model: config.model,
            baseURL: config.baseURL,
            maxTurns: config.maxSteps,
            mcpServers: mcpServers
        )
        return (createAgent(options: options), options)
    }

    private func stdioConfig(_ config: McpServerConfig?) -> McpStdioConfig? {
        guard case let .stdio(stdio)? = config else { return nil }
        return stdio
    }

    private func httpConfig(_ config: McpServerConfig?) -> McpHttpConfig? {
        guard case let .http(http)? = config else { return nil }
        return http
    }

    private final class OutputCapture {
        var text = ""

        func write(_ value: String) {
            text += value
        }
    }

    private final class MCPConfigE2EMockKeyReader: KeyReading, Sendable {
        nonisolated(unsafe) private var events: [KeyEvent]
        nonisolated(unsafe) private var index = 0

        init(_ events: [KeyEvent]) {
            self.events = events
        }

        func readNext() -> KeyEvent? {
            guard index < events.count else { return .eof }
            let event = events[index]
            index += 1
            return event
        }
    }

    private var probeScript: String {
        """
        import json
        import os
        import sys

        LOG_PATH = os.environ.get("AXION_MCP_ACCEPTANCE_LOG", "/tmp/axion-mcp-config-e2e.log")


        def log(message):
            with open(LOG_PATH, "a", encoding="utf-8") as handle:
                handle.write(message + "\\n")
                handle.flush()


        def send(payload):
            sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\\n")
            sys.stdout.flush()
            log("sent " + json.dumps(payload, sort_keys=True))


        for raw_line in sys.stdin:
            raw_line = raw_line.strip()
            if not raw_line:
                continue

            log("received " + raw_line)
            try:
                request = json.loads(raw_line)
            except Exception as error:
                log("invalid-json " + str(error))
                continue

            method = request.get("method")
            request_id = request.get("id")
            log("method " + str(method))

            if method == "initialize":
                params = request.get("params") or {}
                send({
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "protocolVersion": params.get("protocolVersion", "2024-11-05"),
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "acceptance-probe", "version": "0.1.0"}
                    }
                })
            elif method == "notifications/initialized":
                continue
            elif method == "tools/list":
                send({
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "tools": [{
                            "name": "acceptance_ping",
                            "description": "MCP config E2E probe tool",
                            "inputSchema": {
                                "type": "object",
                                "properties": {},
                                "additionalProperties": False
                            }
                        }]
                    }
                })
            elif method == "tools/call":
                send({
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "content": [{"type": "text", "text": "pong"}],
                        "isError": False
                    }
                })
            elif method == "ping":
                send({"jsonrpc": "2.0", "id": request_id, "result": {}})
            elif request_id is not None:
                send({
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "error": {"code": -32601, "message": "Method not found"}
                })
        """
    }

    private var probeExecutableScript: String {
        "#!\(pythonPath)\n" + probeScript
    }
}
