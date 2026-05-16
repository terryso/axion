import Foundation
import Testing

import AxionCore
import OpenAgentSDK
@testable import AxionCLI

/// E2E smoke tests with real Claude API + real Helper process.
///
/// These tests call the actual LLM and execute real desktop operations.
/// Only run manually via `make test-e2e-real`.
///
/// Prerequisites:
/// - `~/.axion/config.json` configured with valid API key (via `axion setup`)
/// - AxionHelper.app built and AX permissions granted
@Suite("Real LLM E2E")
struct RealLLME2ETests {

    private func setUpFixture() async throws -> E2EHelperFixture? {
        let fixture = try E2EHelperFixture()
        let started = try await fixture.setUpHelper()
        guard started else { return nil }
        return fixture
    }

    // MARK: - Smoke Test: Launch Calculator

    @Test("real launch Calculator")
    func realLaunchCalculator() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard fixture.mcpClient != nil else {
            await fixture.tearDown()
            return
        }

        let config = try await ConfigManager.loadConfig()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            await fixture.tearDown()
            return
        }

        guard let helperPath = HelperPathResolver.resolveHelperPath() else {
            await fixture.tearDown()
            return
        }

        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        let promptDir = PromptBuilder.resolvePromptDirectory()
        let systemPrompt = try PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: ToolNames.allToolNames),
                "max_steps": "5",
            ],
            fromDirectory: promptDir
        )

        let options = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: 5,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers,
            logLevel: .info
        )

        let agent = createAgent(options: options)

        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(output: capturing.output)

        handler.displayRunStart(runId: "real-e2e-001", task: "启动计算器")

        var toolCalls: [String] = []
        var finalResult: SDKMessage.ResultData?

        let stream = agent.stream("启动计算器")
        for await message in stream {
            if case .toolUse(let data) = message {
                toolCalls.append(data.toolName)
            }
            if case .result(let data) = message {
                finalResult = data
            }
            handler.handleMessage(message)
        }

        handler.displayCompletion()
        try? await agent.close()

        // Verify at least one tool was called (e.g., launch_app)
        #expect(!toolCalls.isEmpty, "Agent should have called at least one tool")

        // Verify the result is success
        if let result = finalResult {
            #expect(result.subtype == .success, "Task should complete successfully, got: \(result.subtype)")
        }

        // Clean up: quit Calculator
        if let mcpClient = fixture.mcpClient {
            _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": AxionCore.Value.string("Calculator")])
        }
        await fixture.tearDown()
    }

    // MARK: - Smoke Test: Open URL

    @Test("real open URL")
    func realOpenURL() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard fixture.mcpClient != nil else {
            await fixture.tearDown()
            return
        }

        let config = try await ConfigManager.loadConfig()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            await fixture.tearDown()
            return
        }
        guard let helperPath = HelperPathResolver.resolveHelperPath() else {
            await fixture.tearDown()
            return
        }

        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        let promptDir = PromptBuilder.resolvePromptDirectory()
        let systemPrompt = try PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: ToolNames.allToolNames),
                "max_steps": "3",
            ],
            fromDirectory: promptDir
        )

        let options = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: 3,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers,
            logLevel: .info
        )

        let agent = createAgent(options: options)

        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(output: capturing.output)

        handler.displayRunStart(runId: "real-e2e-002", task: "打开 https://example.com")

        var toolCalls: [String] = []
        var finalResult: SDKMessage.ResultData?

        let stream = agent.stream("打开 https://example.com")
        for await message in stream {
            if case .toolUse(let data) = message {
                toolCalls.append(data.toolName)
            }
            if case .result(let data) = message {
                finalResult = data
            }
            handler.handleMessage(message)
        }

        handler.displayCompletion()
        try? await agent.close()

        #expect(!toolCalls.isEmpty, "Agent should have called at least one tool")

        if let result = finalResult {
            #expect(result.subtype == .success, "Task should complete successfully, got: \(result.subtype)")
        }
        await fixture.tearDown()
    }

    // MARK: - Helper for building real agent

    private func buildAgent(maxTurns: Int = 5) async throws -> (OpenAgentSDK.Agent, SDKTerminalOutputHandler, CapturingOutput)? {
        let config = try await ConfigManager.loadConfig()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            return nil
        }

        guard let helperPath = HelperPathResolver.resolveHelperPath() else {
            return nil
        }

        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        let promptDir = PromptBuilder.resolvePromptDirectory()
        let systemPrompt = try PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: ToolNames.allToolNames),
                "max_steps": String(maxTurns),
            ],
            fromDirectory: promptDir
        )

        let options = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: maxTurns,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers,
            logLevel: .info
        )

        let agent = createAgent(options: options)
        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(output: capturing.output)

        return (agent, handler, capturing)
    }

    private func runAgent(_ agent: OpenAgentSDK.Agent, handler: SDKTerminalOutputHandler, task: String) async throws -> (toolCalls: [String], result: SDKMessage.ResultData?) {
        var toolCalls: [String] = []
        var finalResult: SDKMessage.ResultData?

        let stream = agent.stream(task)
        for await message in stream {
            if case .toolUse(let data) = message {
                toolCalls.append(data.toolName)
            }
            if case .result(let data) = message {
                finalResult = data
            }
            handler.handleMessage(message)
        }

        handler.displayCompletion()
        try? await agent.close()

        return (toolCalls, finalResult)
    }

    // MARK: - Smoke Test: TextEdit

    @Test("real TextEdit")
    func realTextEdit() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard fixture.mcpClient != nil else {
            await fixture.tearDown()
            return
        }

        guard let (agent, handler, _) = try await buildAgent(maxTurns: 5) else {
            await fixture.tearDown()
            return
        }
        handler.displayRunStart(runId: "real-e2e-003", task: "打开 TextEdit，输入 Hello World")

        let (toolCalls, finalResult) = try await runAgent(agent, handler: handler, task: "打开 TextEdit，输入 Hello World")

        #expect(!toolCalls.isEmpty, "Agent should have called at least one tool")
        let shortNames = toolCalls.map { $0.replacingOccurrences(of: "mcp__axion-helper__", with: "") }
        #expect(
            shortNames.contains("launch_app") || shortNames.contains("type_text"),
            "Should use launch_app and/or type_text, got: \(toolCalls)"
        )

        if let result = finalResult {
            #expect(result.subtype == .success, "Task should complete successfully, got: \(result.subtype)")
        }

        // Clean up: quit TextEdit
        if let mcpClient = fixture.mcpClient {
            _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("TextEdit")])
        }
        await fixture.tearDown()
    }

    // MARK: - Smoke Test: Finder

    @Test("real Finder")
    func realFinder() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard fixture.mcpClient != nil else {
            await fixture.tearDown()
            return
        }

        guard let (agent, handler, _) = try await buildAgent(maxTurns: 8) else {
            await fixture.tearDown()
            return
        }
        handler.displayRunStart(runId: "real-e2e-004", task: "打开 Finder，进入下载目录")

        let (toolCalls, finalResult) = try await runAgent(agent, handler: handler, task: "打开 Finder，进入下载目录")

        #expect(!toolCalls.isEmpty, "Agent should have called at least one tool")
        let shortNames = toolCalls.map { $0.replacingOccurrences(of: "mcp__axion-helper__", with: "") }
        #expect(
            shortNames.contains("launch_app") || shortNames.contains("hotkey"),
            "Should use launch_app and/or hotkey for Finder navigation, got: \(toolCalls)"
        )

        if let result = finalResult {
            #expect(result.subtype == .success, "Task should complete successfully, got: \(result.subtype)")
        }
        await fixture.tearDown()
    }

    // MARK: - Smoke Test: Safari

    @Test("real Safari")
    func realSafari() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard fixture.mcpClient != nil else {
            await fixture.tearDown()
            return
        }

        guard let (agent, handler, _) = try await buildAgent(maxTurns: 3) else {
            await fixture.tearDown()
            return
        }
        handler.displayRunStart(runId: "real-e2e-005", task: "打开 Safari，访问 example.com")

        let (toolCalls, finalResult) = try await runAgent(agent, handler: handler, task: "打开 Safari，访问 example.com")

        #expect(!toolCalls.isEmpty, "Agent should have called at least one tool")
        let shortNames = toolCalls.map { $0.replacingOccurrences(of: "mcp__axion-helper__", with: "") }
        #expect(
            shortNames.contains("open_url") || shortNames.contains("launch_app"),
            "Should use open_url or launch_app, got: \(toolCalls)"
        )

        if let result = finalResult {
            #expect(result.subtype == .success, "Task should complete successfully, got: \(result.subtype)")
        }
        await fixture.tearDown()
    }
}
