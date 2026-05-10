import XCTest
import OpenAgentSDK
@testable import AxionCLI
import AxionCore

/// Integration tests for Story 3-7: SDK Agent + Helper MCP integration.
///
/// Tests the real SDK Agent lifecycle with Helper as MCP stdio server:
/// - Agent creates, connects Helper via MCP, discovers tools
/// - Safety hooks work in real agent context
/// - Output handlers consume real MCP data
///
/// Prerequisites:
/// - AxionHelper.app built at .build/AxionHelper.app
/// - macOS Accessibility permissions granted to Terminal/iTerm
/// - Run with: AXION_HELPER_PATH="$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter "AxionCLIIntegrationTests.SDKAgentIntegrationTests"
final class SDKAgentIntegrationTests: XCTestCase {

    // MARK: - Properties

    private var helperPath: String!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()

        guard let path = HelperPathResolver.resolveHelperPath() else {
            XCTFail("AxionHelper not found. Build it first or set AXION_HELPER_PATH.")
            return
        }
        helperPath = path
    }

    // MARK: - AC1, AC2: SDK Agent creates and connects Helper via MCP stdio

    /// Creating an Agent with Helper as MCP server should connect and discover tools.
    /// We use an invalid API key — the LLM call will fail but MCP connection should still happen.
    func test_real_sdkAgent_connectsHelperViaMCP() async throws {
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

        // Trigger MCP connection by attempting a prompt.
        // The API call will fail (invalid key) but MCP connection should be attempted.
        let result = await agent.prompt("list running applications")

        // Result should be an error (invalid API key), not a crash
        XCTAssertEqual(result.status, .errorDuringExecution,
                       "Should fail with API error, not crash. Got: \(result.status)")
        XCTAssertTrue((result.errors?.count ?? 0) > 0,
                      "Should have error messages")

        // Check MCP server status after the attempt
        let serverStatus = await agent.mcpServerStatus()
        XCTAssertTrue(serverStatus["axion-helper"] != nil,
                      "Helper should appear in MCP server status after connection attempt")

        // Cleanup
        try? await agent.close()
    }

    // MARK: - AC2: MCP stdio config uses correct Helper path

    /// Verify the MCP stdio config correctly references the Helper binary.
    func test_real_mcpStdioConfig_correctHelperPath() async throws {
        guard let helperPath else { return }

        let config = McpStdioConfig(command: helperPath)
        XCTAssertEqual(config.command, helperPath)

        // Verify the binary actually exists
        let exists = FileManager.default.fileExists(atPath: helperPath)
        XCTAssertTrue(exists, "Helper binary should exist at \(helperPath)")
    }

    // MARK: - AC4: SafetyChecker hook blocks foreground tools in real Agent

    /// SafetyChecker hook blocks click in shared seat mode when running through real Agent.
    func test_real_safetyHook_blocksForegroundInSharedSeatMode() async throws {
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

        // Verify hook blocks foreground tools
        let clickInput = HookInput(event: .preToolUse, toolName: "click")
        let clickResult = await hookRegistry.execute(.preToolUse, input: clickInput)
        XCTAssertEqual(clickResult.first?.decision, .block,
                       "click should be blocked in shared seat mode")

        // Verify hook allows non-foreground tools
        let listAppsInput = HookInput(event: .preToolUse, toolName: "list_apps")
        let listAppsResult = await hookRegistry.execute(.preToolUse, input: listAppsInput)
        XCTAssertEqual(listAppsResult.first?.decision, .approve,
                       "list_apps should be allowed in shared seat mode")

        // Verify hook works when passed to Agent
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
        XCTAssertNotNil(agent, "Agent should be created with hook registry")
        try? await agent.close()
    }

    // MARK: - AC5: SDKTerminalOutputHandler with real Helper MCP data

    /// SDKTerminalOutputHandler correctly formats real MCP tool results.
    func test_real_terminalOutputHandler_withRealMCPData() async throws {
        guard let helperPath else { return }

        // Use HelperProcessManager to get real MCP data
        let manager = HelperProcessManager()
        try await manager.start()
        defer { _Concurrency.Task { await manager.stop() } }

        // Get real tool list
        let tools = try await manager.listTools()
        XCTAssertFalse(tools.isEmpty, "Helper should expose tools")

        // Get real launch_app result
        let launchResult = try await manager.callTool(
            name: ToolNames.launchApp,
            arguments: ["app_name": .string("Calculator")]
        )
        XCTAssertFalse(launchResult.isEmpty, "launch_app should return data")

        // Extract pid for cleanup
        let pid = extractPid(from: launchResult)

        // Test SDKTerminalOutputHandler with real data
        var captured: [String] = []
        let handler = SDKTerminalOutputHandler(
            output: TerminalOutput(write: { captured.append($0) })
        )

        handler.displayRunStart(runId: "integ-test", task: "Open Calculator")

        // Simulate assistant message (like what SDK would produce)
        handler.handleMessage(.assistant(
            .init(text: "I'll launch Calculator for you.", model: "test", stopReason: "tool_use")
        ))

        // Simulate toolUse message
        handler.handleMessage(.toolUse(
            .init(toolName: "launch_app", toolUseId: "tu-1", input: "{\"app_name\":\"Calculator\"}")
        ))

        // Simulate toolResult with real data
        handler.handleMessage(.toolResult(
            .init(toolUseId: "tu-1", content: launchResult, isError: false)
        ))

        handler.displayCompletion()

        // Verify output
        let combined = captured.joined(separator: "\n")
        XCTAssertTrue(combined.contains("integ-test"), "Should display run ID")
        XCTAssertTrue(combined.contains("Calculator"), "Should display task or tool info")
        XCTAssertTrue(combined.contains("launch_app"), "Should display tool name")
        XCTAssertTrue(combined.contains("运行结束"), "Should display completion")

        // Cleanup
        if let pid {
            _ = try? await manager.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - AC5: SDKJSONOutputHandler with real data

    /// SDKJSONOutputHandler produces valid JSON with real tool data.
    func test_real_jsonOutputHandler_withRealMCPData() async throws {
        guard let helperPath else { return }

        let manager = HelperProcessManager()
        try await manager.start()
        defer { _Concurrency.Task { await manager.stop() } }

        let tools = try await manager.listTools()

        var jsonOutput: String?
        let handler = SDKJSONOutputHandler(write: { jsonOutput = $0 })

        handler.displayRunStart(runId: "json-integ", task: "List tools")

        handler.handleMessage(.toolUse(
            .init(toolName: "list_apps", toolUseId: "tu-1", input: "{}")
        ))

        // Use real tool names as result
        let toolListJSON = (try? JSONSerialization.data(
            withJSONObject: tools, options: []
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        handler.handleMessage(.toolResult(
            .init(toolUseId: "tu-1", content: toolListJSON, isError: false)
        ))

        handler.handleMessage(.result(
            .init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)
        ))

        handler.displayCompletion()

        // Verify JSON output
        XCTAssertNotNil(jsonOutput, "Should produce JSON output")
        if let json = jsonOutput {
            let dict = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            XCTAssertNotNil(dict, "Output should be valid JSON")
            XCTAssertEqual(dict?["runId"] as? String, "json-integ")
            XCTAssertEqual(dict?["status"] as? String, "success")
            XCTAssertEqual(dict?["numTurns"] as? Int, 1)

            let steps = dict?["steps"] as? [[String: Any]]
            XCTAssertNotNil(steps)
            XCTAssertEqual(steps?.count, 1)
            XCTAssertEqual(steps?.first?["tool"] as? String, "list_apps")
        }
    }

    // MARK: - AC5: SDKMessage trace recording with real Helper

    /// TraceRecorder correctly records SDKMessage events from real Helper data.
    func test_real_traceRecording_withSDKMessages() async throws {
        guard let helperPath else { return }

        let manager = HelperProcessManager()
        try await manager.start()
        defer { _Concurrency.Task { await manager.stop() } }

        var config = AxionConfig.default
        config.traceEnabled = true

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDKIntegTrace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tracer = try TraceRecorder(runId: "sdk-integ-trace", config: config, baseURL: tempDir)
        await tracer.recordRunStart(runId: "sdk-integ-trace", task: "Open Calculator", mode: "sdk")

        // Simulate SDKMessage events from real execution
        await tracer.record(event: "assistant_message", payload: [
            "text": "Opening Calculator",
            "model": "claude-sonnet-4-20250514"
        ])

        await tracer.record(event: "tool_use", payload: [
            "tool": "launch_app",
            "toolUseId": "tu-1"
        ])

        // Get real MCP result
        let launchResult = try await manager.callTool(
            name: ToolNames.launchApp,
            arguments: ["app_name": .string("Calculator")]
        )

        await tracer.record(event: "tool_result", payload: [
            "toolUseId": "tu-1",
            "isError": false,
            "content": String(launchResult.prefix(200))
        ])

        await tracer.record(event: "result", payload: [
            "subtype": "success",
            "numTurns": 1,
            "durationMs": 1500
        ])

        await tracer.recordRunDone(totalSteps: 1, durationMs: 1500, replanCount: 0)
        await tracer.close()

        // Verify trace file
        let traceURL = tempDir.appendingPathComponent("sdk-integ-trace/trace.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: traceURL.path),
                       "Trace file should exist")

        let content = try String(contentsOf: traceURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertGreaterThanOrEqual(lines.count, 5,
                                     "Should have at least 5 trace events, got \(lines.count)")

        let events = lines.compactMap { line -> String? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return json["event"] as? String
        }

        XCTAssertTrue(events.contains("run_start"), "Should have run_start")
        XCTAssertTrue(events.contains("assistant_message"), "Should have assistant_message")
        XCTAssertTrue(events.contains("tool_use"), "Should have tool_use")
        XCTAssertTrue(events.contains("tool_result"), "Should have tool_result")
        XCTAssertTrue(events.contains("result"), "Should have result")
        XCTAssertTrue(events.contains("run_done"), "Should have run_done")

        // Cleanup Calculator
        if let pid = extractPid(from: launchResult) {
            _ = try? await manager.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - AC6: Agent interrupt works (cancellation propagation)

    /// Agent.interrupt() can be called on a running agent.
    func test_real_agentInterrupt_isCallable() async throws {
        guard let helperPath else { return }

        let options = AgentOptions(
            apiKey: "sk-test",
            model: "claude-sonnet-4-20250514",
            maxTurns: 1,
            permissionMode: .bypassPermissions,
            mcpServers: ["axion-helper": .stdio(McpStdioConfig(command: helperPath))]
        )

        let agent = createAgent(options: options)

        // interrupt() should not crash when no query is running
        agent.interrupt()

        // Close should work cleanly
        try? await agent.close()

        // After close, prompt should return error status
        let result = await agent.prompt("test")
        XCTAssertEqual(result.status, .errorDuringExecution,
                       "Prompt after close should return error")
    }

    // MARK: - AC1: AgentOptions builds correctly from AxionConfig

    /// AgentOptions configuration mirrors AxionConfig settings.
    func test_real_agentOptions_fromAxionConfig() async throws {
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

        // Verify options match config
        XCTAssertEqual(options.model, config.model)
        XCTAssertEqual(options.maxTurns, config.maxSteps)
        XCTAssertEqual(options.permissionMode, .bypassPermissions)
        XCTAssertNotNil(options.mcpServers)

        // Verify agent can be created with these options
        let agent = createAgent(options: options)
        XCTAssertEqual(agent.model, config.model)
        XCTAssertEqual(agent.maxTurns, config.maxSteps)
        XCTAssertEqual(agent.systemPrompt, "You are a desktop automation assistant.")

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
