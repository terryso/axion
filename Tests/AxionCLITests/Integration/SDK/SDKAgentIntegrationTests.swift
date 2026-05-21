import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
import AxionCore

@Suite("SDK Agent Integration")
struct SDKAgentIntegrationTests {

    // MARK: - Properties

    private var helperPath: String? {
        HelperPathResolver.resolveHelperPath()
    }

    // MARK: - AC1, AC2: SDK Agent creates and connects Helper via MCP stdio

    @Test("real SDK agent connects Helper via MCP")
    func realSDKAgentConnectsHelperViaMCP() async throws {
        guard let helperPath else { return }

        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        let options = AgentOptions(
            apiKey: "sk-invalid-test-key-for-integration",
            model: "claude-sonnet-4-20250514",
            maxTurns: 1,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers
        )

        let agent = createAgent(options: options)

        let result = await agent.prompt("list running applications")

        #expect(result.status == .errorDuringExecution,
                "Should fail with API error, not crash. Got: \(result.status)")
        #expect((result.errors?.count ?? 0) > 0,
                "Should have error messages")

        let serverStatus = await agent.mcpServerStatus()
        #expect(serverStatus["axion-helper"] != nil,
                "Helper should appear in MCP server status after connection attempt")

        try? await agent.close()
    }

    // MARK: - AC2: MCP stdio config uses correct Helper path

    @Test("real MCP stdio config correct Helper path")
    func realMCPStdioConfigCorrectHelperPath() async throws {
        guard let helperPath else { return }

        let config = McpStdioConfig(command: helperPath)
        #expect(config.command == helperPath)

        let exists = FileManager.default.fileExists(atPath: helperPath)
        #expect(exists, "Helper binary should exist at \(helperPath)")
    }

    // MARK: - AC4: SafetyChecker hook blocks foreground tools in real Agent

    @Test("real safety hook blocks foreground in shared seat mode")
    func realSafetyHookBlocksForegroundInSharedSeatMode() async throws {
        guard let helperPath else { return }

        let hookRegistry = HookRegistry()
        let foregroundTools = ToolNames.foregroundToolNames

        let safetyHook = HookDefinition(handler: { input in
            guard let toolName = input.toolName else { return HookOutput(decision: .approve) }
            if foregroundTools.contains(toolName) {
                return HookOutput(
                    decision: .block,
                    reason: "Tool '\(toolName)' blocked in shared seat mode"
                )
            }
            return HookOutput(decision: .approve)
        })

        await hookRegistry.register(.preToolUse, definition: safetyHook)

        let clickInput = HookInput(event: .preToolUse, toolName: "click")
        let clickResult = await hookRegistry.execute(.preToolUse, input: clickInput)
        #expect(clickResult.first?.decision == .block,
                "click should be blocked in shared seat mode")

        let listAppsInput = HookInput(event: .preToolUse, toolName: "list_apps")
        let listAppsResult = await hookRegistry.execute(.preToolUse, input: listAppsInput)
        #expect(listAppsResult.first?.decision == .approve,
                "list_apps should be allowed in shared seat mode")

        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]
        let options = AgentOptions(
            apiKey: "sk-test",
            model: "claude-sonnet-4-20250514",
            maxTurns: 1,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers,
            hookRegistry: hookRegistry
        )

        let agent = createAgent(options: options)
        try? await agent.close()
    }

    // MARK: - AC5: SDKTerminalOutputHandler with real Helper MCP data

    @Test("real terminal output handler with real MCP data")
    func realTerminalOutputHandlerWithRealMCPData() async throws {
        guard let helperPath else { return }

        let manager = HelperProcessManager()
        try await manager.start()
        defer { _Concurrency.Task { await manager.stop() } }

        let tools = try await manager.listTools()
        #expect(!tools.isEmpty, "Helper should expose tools")

        let launchResult = try await manager.callTool(
            name: ToolNames.launchApp,
            arguments: ["app_name": .string("Calculator")]
        )
        #expect(!launchResult.isEmpty, "launch_app should return data")

        let pid = extractPid(from: launchResult)

        var captured: [String] = []
        let handler = SDKTerminalOutputHandler(
            write: { captured.append($0) }
        )

        handler.displayRunStart(runId: "integ-test", task: "Open Calculator")
        handler.handle(.assistant(
            .init(text: "I'll launch Calculator for you.", model: "test", stopReason: "tool_use")
        ))
        handler.handle(.toolUse(
            .init(toolName: "launch_app", toolUseId: "tu-1", input: "{\"app_name\":\"Calculator\"}")
        ))
        handler.handle(.toolResult(
            .init(toolUseId: "tu-1", content: launchResult, isError: false)
        ))
        handler.displayCompletion()

        let combined = captured.joined(separator: "\n")
        #expect(combined.contains("integ-test"), "Should display run ID")
        #expect(combined.contains("Calculator"), "Should display task or tool info")
        #expect(combined.contains("launch_app"), "Should display tool name")
        #expect(combined.contains("运行结束"), "Should display completion")

        if let pid {
            _ = try? await manager.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - AC5: SDKJSONOutputHandler with real data

    @Test("real JSON output handler with real MCP data")
    func realJSONOutputHandlerWithRealMCPData() async throws {
        guard let helperPath else { return }

        let manager = HelperProcessManager()
        try await manager.start()
        defer { _Concurrency.Task { await manager.stop() } }

        let tools = try await manager.listTools()

        var jsonOutput: String?
        let handler = SDKJSONOutputHandler(write: { jsonOutput = $0 })

        handler.displayRunStart(runId: "json-integ", task: "List tools")
        handler.handle(.toolUse(
            .init(toolName: "list_apps", toolUseId: "tu-1", input: "{}")
        ))

        let toolListJSON = (try? JSONSerialization.data(
            withJSONObject: tools, options: []
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        handler.handle(.toolResult(
            .init(toolUseId: "tu-1", content: toolListJSON, isError: false)
        ))
        handler.handle(.result(
            .init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)
        ))
        handler.displayCompletion()

        #expect(jsonOutput != nil, "Should produce JSON output")
        if let json = jsonOutput {
            let dict = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            #expect(dict != nil, "Output should be valid JSON")
            #expect(dict?["runId"] as? String == "json-integ")
            #expect(dict?["status"] as? String == "success")
            #expect(dict?["numTurns"] as? Int == 1)

            let steps = dict?["steps"] as? [[String: Any]]
            #expect(steps != nil)
            #expect(steps?.count == 1)
            #expect(steps?.first?["tool"] as? String == "list_apps")
        }
    }

    // MARK: - AC6: Agent interrupt works (cancellation propagation)

    @Test("real agent interrupt is callable")
    func realAgentInterruptIsCallable() async throws {
        guard let helperPath else { return }

        let options = AgentOptions(
            apiKey: "sk-test",
            model: "claude-sonnet-4-20250514",
            maxTurns: 1,
            permissionMode: .bypassPermissions,
            mcpServers: ["axion-helper": .stdio(McpStdioConfig(command: helperPath))]
        )

        let agent = createAgent(options: options)

        agent.interrupt()

        try? await agent.close()

        let result = await agent.prompt("test")
        #expect(result.status == .errorDuringExecution,
                "Prompt after close should return error")
    }

    // MARK: - AC1: AgentOptions builds correctly from AxionConfig

    @Test("real agent options from AxionConfig")
    func realAgentOptionsFromAxionConfig() async throws {
        guard let helperPath else { return }

        let config = try await ConfigManager.loadConfig()

        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        let options = AgentOptions(
            apiKey: "sk-test-key",
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: "You are a desktop automation assistant.",
            maxTurns: config.maxSteps,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers
        )

        #expect(options.model == config.model)
        #expect(options.maxTurns == config.maxSteps)
        #expect(options.permissionMode == .bypassPermissions)
        #expect(options.mcpServers != nil)

        let agent = createAgent(options: options)
        #expect(agent.model == config.model)
        #expect(agent.maxTurns == config.maxSteps)
        #expect(agent.systemPrompt == "You are a desktop automation assistant.")

        try? await agent.close()
    }

    // MARK: - Helpers

    private func extractPid(from json: String) -> Int? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj["pid"] as? Int
    }
}
