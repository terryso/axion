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

        try await withHelperPath(fixture.helper.path) {
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
            let result = try await buildAPIAgent(config: config)

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

        try await withHelperPath("/usr/bin/true") {
            let result = try await buildAPIAgent(config: config)

            let names = Set(result.agentOptions.mcpServers?.keys.map { key in key } ?? [])
            #expect(names == ["axion-helper"])
            #expect(stdioConfig(result.agentOptions.mcpServers?["axion-helper"])?.command == "/usr/bin/true")
            try? await result.agent.close()
        }
    }

    @Test("reserved axion-helper user config cannot override resolved helper")
    func reservedAxionHelperUserConfigCannotOverrideResolvedHelper() async throws {
        try await withHelperPath("/usr/bin/true") {
            let config = AxionConfig(
                apiKey: "sk-test",
                maxSteps: 1,
                mcpServers: [
                    "axion-helper": .stdio(command: "/usr/bin/false", args: nil, env: nil)
                ]
            )
            let result = try await buildAPIAgent(config: config)

            let helper = stdioConfig(result.agentOptions.mcpServers?["axion-helper"])
            #expect(helper?.command == "/usr/bin/true")
            try? await result.agent.close()
        }
    }

    @Test("custom Playwright stdio config survives CLI build")
    func customPlaywrightStdioConfigSurvivesCLIBuild() async throws {
        try await withHelperPath("/usr/bin/true") {
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
            let result = try await AgentBuilder.build(
                AgentBuilder.BuildConfig.forCLI(
                    config: config,
                    task: "mcp config playwright e2e",
                    noMemory: true,
                    noSkills: true,
                    maxSteps: 1
                )
            )

            let playwright = stdioConfig(result.agentOptions.mcpServers?["playwright"])
            #expect(playwright?.command == "/custom/playwright-node")
            #expect(playwright?.args == ["/custom/playwright-mcp.js", "--headless"])
            #expect(playwright?.env == ["PW_TEST": "1"])
            try? await result.agent.close()
        }
    }

    @Test("http MCP headers survive real agent build")
    func httpMcpHeadersSurviveRealAgentBuild() async throws {
        try await withHelperPath("/usr/bin/true") {
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
            let result = try await buildAPIAgent(config: config)

            let http = httpConfig(result.agentOptions.mcpServers?["web-search-prime"])
            #expect(http?.url == "https://open.bigmodel.cn/api/mcp/web_search_prime/mcp")
            #expect(http?.headers == ["Authorization": "Bearer redacted"])
            try? await result.agent.close()
        }
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

    private func buildAPIAgent(config: AxionConfig) async throws -> AgentBuildResult {
        try await AgentBuilder.build(
            AgentBuilder.BuildConfig.forAPI(
                config: config,
                task: "mcp config e2e",
                request: CreateRunRequest(task: "mcp config e2e", maxSteps: 1)
            )
        )
    }

    private func withHelperPath<T>(
        _ path: String,
        body: () async throws -> T
    ) async throws -> T {
        let saved = ProcessInfo.processInfo.environment["AXION_HELPER_PATH"]
        setenv("AXION_HELPER_PATH", path, 1)
        defer {
            if let saved {
                setenv("AXION_HELPER_PATH", saved, 1)
            } else {
                unsetenv("AXION_HELPER_PATH")
            }
        }
        return try await body()
    }

    private func stdioConfig(_ config: McpServerConfig?) -> McpStdioConfig? {
        guard case let .stdio(stdio)? = config else { return nil }
        return stdio
    }

    private func httpConfig(_ config: McpServerConfig?) -> McpHttpConfig? {
        guard case let .http(http)? = config else { return nil }
        return http
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
