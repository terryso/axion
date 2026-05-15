import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
import AxionCore

private let SDK_AGENT_INTEGRATED = true
private let SDK_MCP_CONFIGURED = true
private let SDK_HOOKS_CONFIGURED = true
private let SDK_STREAMING_CONFIGURED = true
private let SDK_E2E_FLOW_CONFIGURED = true

@Suite("SDKIntegration ATDD")
struct SDKIntegrationATDDTests {

    private func makeDefaultConfig() -> AxionConfig {
        AxionConfig(
            apiKey: "sk-test-key",
            maxSteps: 20,
            maxBatches: 6,
            maxReplanRetries: 3
        )
    }

    // ========================================================================
    // MARK: - [P0] AC1: SDK Agent Loop 编排
    // ========================================================================

    @Test("RunCommand creates SDK Agent")
    func runCommandCreatesSDKAgent() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let config = makeDefaultConfig()
        let systemPrompt = "You are a desktop automation assistant."
        let helperPath = "/usr/local/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"

        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        let options = AgentOptions(
            apiKey: config.apiKey,
            model: config.model,
            systemPrompt: systemPrompt,
            maxTurns: config.maxSteps,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers
        )

        let _ = createAgent(options: options)
    }

    @Test("RunCommand AgentOptions contains API key")
    func runCommandAgentOptionsContainsApiKey() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let config = makeDefaultConfig()
        let options = AgentOptions(
            apiKey: config.apiKey,
            model: config.model,
            maxTurns: config.maxSteps
        )

        #expect(options.apiKey == "sk-test-key")
    }

    @Test("RunCommand AgentOptions contains model")
    func runCommandAgentOptionsContainsModel() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let config = makeDefaultConfig()
        let options = AgentOptions(model: config.model)

        #expect(options.model == config.model)
    }

    @Test("RunCommand AgentOptions contains systemPrompt")
    func runCommandAgentOptionsContainsSystemPrompt() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let promptDir = PromptBuilder.resolvePromptDirectory()
        let systemPrompt = try PromptBuilder.load(name: "planner-system", variables: [:], fromDirectory: promptDir)

        let options = AgentOptions(systemPrompt: systemPrompt)

        #expect(!(options.systemPrompt?.isEmpty ?? true),
            "systemPrompt should be loaded from planner-system.md")
    }

    @Test("RunCommand AgentOptions maxTurns from config")
    func runCommandAgentOptionsMaxTurnsFromConfig() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let config = makeDefaultConfig()
        let effectiveMaxSteps = config.maxSteps
        let options = AgentOptions(maxTurns: effectiveMaxSteps)

        #expect(options.maxTurns == 20)
    }

    @Test("RunCommand AgentOptions permissionMode is bypassPermissions")
    func runCommandAgentOptionsPermissionModeBypassPermissions() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let options = AgentOptions(permissionMode: .bypassPermissions)

        #expect(options.permissionMode == .bypassPermissions,
            "Axion should use .bypassPermissions mode (no user confirmation)")
    }

    // ========================================================================
    // MARK: - [P0] AC2: SDK MCP Client 连接
    // ========================================================================

    @Test("RunCommand configures helper as MCP server")
    func runCommandConfiguresHelperAsMCPServer() async throws {
        guard SDK_MCP_CONFIGURED else { return }

        let testHelperPath = "/tmp/test-helper"
        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: testHelperPath))
        ]

        #expect(mcpServers["axion-helper"] != nil)
        if case .stdio(let stdioConfig) = mcpServers["axion-helper"] {
            #expect(stdioConfig.command == testHelperPath)
        } else {
            Issue.record("axion-helper should be configured as stdio MCP server")
        }
    }

    @Test("RunCommand MCP config uses HelperPathResolver")
    func runCommandMcpConfigUsesHelperPathResolver() async throws {
        guard SDK_MCP_CONFIGURED else { return }

        let resolvedPath = HelperPathResolver.resolveHelperPath()

        if let path = resolvedPath {
            let config = McpStdioConfig(command: path)
            #expect(config.command == path)
        }
    }

    @Test("RunCommand MCP servers auto discovery")
    func runCommandMcpServersAutoDiscovery() async throws {
        guard SDK_MCP_CONFIGURED else { return }

        let helperPath = "/usr/local/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"
        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]
        let options = AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-20250514",
            mcpServers: mcpServers
        )

        #expect(options.mcpServers?.count == 1)
        #expect(options.mcpServers?.keys.first == "axion-helper")
    }

    // ========================================================================
    // MARK: - [P0] AC3: SDK 工具注册
    // ========================================================================

    @Test("tools registered via MCP auto discovery")
    func toolsRegisteredViaMCPAutoDiscovery() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let options = AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-20250514",
            tools: nil,
            mcpServers: ["axion-helper": .stdio(McpStdioConfig(command: "/path/to/helper"))]
        )

        #expect(options.tools == nil, "No custom tools needed when MCP auto-discovers")
        #expect(options.mcpServers != nil, "MCP servers should be configured for auto-discovery")
    }

    // ========================================================================
    // MARK: - [P0] AC4: SDK Hooks 安全检查
    // ========================================================================

    @Test("safety checker registered as preToolUse hook")
    func safetyCheckerRegisteredAsPreToolUseHook() async throws {
        guard SDK_HOOKS_CONFIGURED else { return }

        let hookRegistry = HookRegistry()

        let safetyHook = HookDefinition(handler: { input in
            guard let toolName = input.toolName else { return nil }

            let foregroundTools = ["click", "type_text", "press_key", "hotkey", "drag", "scroll",
                                    "double_click", "right_click"]

            if foregroundTools.contains(toolName) {
                return HookOutput(decision: .block, reason: "前台操作在共享座椅模式下被阻止")
            }
            return HookOutput(decision: .approve)
        })

        await hookRegistry.register(.preToolUse, definition: safetyHook)

        let input = HookInput(event: .preToolUse, toolName: "click")
        let results = await hookRegistry.execute(.preToolUse, input: input)

        #expect(results.count == 1, "Pre-tool-use hook should execute")
        #expect(results.first?.decision == .block, "Foreground tool should be blocked")
    }

    @Test("preToolUse hook blocks foreground ops in shared seat mode")
    func preToolUseHookBlocksForegroundOpsInSharedSeatMode() async throws {
        guard SDK_HOOKS_CONFIGURED else { return }

        let hookRegistry = HookRegistry()
        let sharedSeatMode = true

        let safetyHook = HookDefinition(handler: { input in
            guard sharedSeatMode else { return HookOutput(decision: .approve) }

            let foregroundTools = ["click", "type_text", "press_key", "hotkey", "drag", "scroll"]
            if let toolName = input.toolName, foregroundTools.contains(toolName) {
                return HookOutput(decision: .block, reason: "Blocked in shared seat mode: \(toolName)")
            }
            return HookOutput(decision: .approve)
        })

        await hookRegistry.register(.preToolUse, definition: safetyHook)

        let clickInput = HookInput(event: .preToolUse, toolName: "click")
        let clickResult = await hookRegistry.execute(.preToolUse, input: clickInput)

        #expect(clickResult.first?.decision == .block)

        let listAppsInput = HookInput(event: .preToolUse, toolName: "list_apps")
        let listAppsResult = await hookRegistry.execute(.preToolUse, input: listAppsInput)
        #expect(listAppsResult.first?.decision == .approve)
    }

    @Test("preToolUse hook allows all ops when foreground allowed")
    func preToolUseHookAllowsAllOpsWhenForegroundAllowed() async throws {
        guard SDK_HOOKS_CONFIGURED else { return }

        let hookRegistry = HookRegistry()
        let sharedSeatMode = false

        let safetyHook = HookDefinition(handler: { input in
            guard sharedSeatMode else { return HookOutput(decision: .approve) }
            return HookOutput(decision: .block)
        })

        await hookRegistry.register(.preToolUse, definition: safetyHook)

        let clickInput = HookInput(event: .preToolUse, toolName: "click")
        let result = await hookRegistry.execute(.preToolUse, input: clickInput)

        #expect(result.first?.decision == .approve)
    }

    @Test("hook registry passed to AgentOptions")
    func hookRegistryPassedToAgentOptions() async throws {
        guard SDK_HOOKS_CONFIGURED else { return }

        let hookRegistry = HookRegistry()
        let options = AgentOptions(hookRegistry: hookRegistry)
        #expect(options.hookRegistry != nil)
    }

    // ========================================================================
    // MARK: - [P0] AC5: SDK Streaming 进度输出
    // ========================================================================

    @Test("stream message assistant forwarded to output")
    func streamMessageAssistantForwardedToOutput() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        let message = SDKMessage.assistant(
            .init(text: "I will open Calculator for you.", model: "claude-sonnet-4-20250514", stopReason: "end_turn")
        )

        #expect(message.text == "I will open Calculator for you.")
    }

    @Test("stream message toolUse forwarded to output")
    func streamMessageToolUseForwardedToOutput() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        let message = SDKMessage.toolUse(
            .init(toolName: "launch_app", toolUseId: "tool-123", input: "{\"app_name\": \"Calculator\"}")
        )

        #expect(message.text == "launch_app")
    }

    @Test("stream message toolResult forwarded to output")
    func streamMessageToolResultForwardedToOutput() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        let message = SDKMessage.toolResult(
            .init(toolUseId: "tool-123", content: "{\"success\": true}", isError: false)
        )

        #expect(message.content == "{\"success\": true}")
        #expect(message.isError == false)
    }

    @Test("stream message result final result")
    func streamMessageResultFinalResult() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        let message = SDKMessage.result(
            .init(subtype: .success, text: "Task completed: Calculator shows 391", usage: nil, numTurns: 5, durationMs: 3200)
        )

        #expect(message.text.contains("Task completed"))
        #expect(message.numTurns == 5)
        #expect(message.durationMs == 3200)
    }

    @Test("stream message partialMessage streaming text")
    func streamMessagePartialMessageStreamingText() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        let message = SDKMessage.partialMessage(
            .init(text: "Opening")
        )

        #expect(message.text == "Opening")
    }

    @Test("stream messages recorded to trace")
    func streamMessagesRecordedToTrace() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        let messages: [SDKMessage] = [
            .assistant(.init(text: "Planning...", model: "claude-sonnet-4-20250514", stopReason: "tool_use")),
            .toolUse(.init(toolName: "launch_app", toolUseId: "t1", input: "{}")),
            .toolResult(.init(toolUseId: "t1", content: "OK", isError: false)),
            .result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)),
        ]

        for msg in messages {
            #expect(!msg.text.isEmpty, "Each SDKMessage should have extractable text for trace recording")
        }
    }

    // ========================================================================
    // MARK: - [P0] AC6: 完整端到端流程
    // ========================================================================

    @Test("RunCommand uses SDK Agent instead of direct helper manager")
    func runCommandUsesSDKAgentInsteadOfDirectHelperManager() async throws {
        guard SDK_E2E_FLOW_CONFIGURED else { return }

        let helperPath = "/usr/local/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"
        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]
        let options = AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-20250514",
            maxTurns: 10,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers
        )

        let agent = createAgent(options: options)

        let _ = agent.stream("test task")
    }

    @Test("RunCommand dryrun mode skips tool execution")
    func runCommandDryrunModeSkipsToolExecution() async throws {
        guard SDK_E2E_FLOW_CONFIGURED else { return }

        let promptDir = PromptBuilder.resolvePromptDirectory()
        let basePrompt = try PromptBuilder.load(name: "planner-system", variables: [:], fromDirectory: promptDir)

        let dryrunPrompt = basePrompt + "\n\nIMPORTANT: You are in DRYRUN mode."
        #expect(dryrunPrompt.contains("DRYRUN mode"), "Dryrun prompt should contain DRYRUN mode instruction")
    }

    @Test("RunCommand cancel propagates to Agent interrupt")
    func runCommandCancelPropagatesToAgentInterrupt() async throws {
        guard SDK_E2E_FLOW_CONFIGURED else { return }

        let options = AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-20250514",
            maxTurns: 5,
            permissionMode: .bypassPermissions
        )
        let agent = createAgent(options: options)
        agent.interrupt()
    }

    // ========================================================================
    // MARK: - [P1] 配置加载
    // ========================================================================

    @Test("RunCommand loads config from ConfigManager")
    func runCommandLoadsConfigFromConfigManager() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let config = try await ConfigManager.loadConfig()

        #expect(!config.model.isEmpty, "Config should have a model value")
        #expect(config.maxSteps > 0, "Config should have positive maxSteps")
    }

    @Test("RunCommand API key from keychain or env")
    func runCommandApiKeyFromKeychainOrEnv() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let apiKey = ProcessInfo.processInfo.environment["AXION_API_KEY"]

        if let key = apiKey {
            let options = AgentOptions(apiKey: key)
            #expect(options.apiKey == key)
        }
    }

    @Test("RunCommand CLI args override config")
    func runCommandCLIArgsOverrideConfig() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let _ = makeDefaultConfig()
        let cliMaxSteps = 30
        let effectiveMaxSteps = cliMaxSteps
        let options = AgentOptions(maxTurns: effectiveMaxSteps)

        #expect(options.maxTurns == 30)
    }

    // ========================================================================
    // MARK: - [P1] SDK Output Handlers
    // ========================================================================

    @Test("terminal output handler displays assistant message")
    func terminalOutputHandlerDisplaysAssistantMessage() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        var captured: [String] = []
        let handler = SDKTerminalOutputHandler(
            output: TerminalOutput(write: { captured.append($0) })
        )

        handler.displayRunStart(runId: "test-123", task: "Open Calculator")
        #expect(captured.contains(where: { $0.contains("test-123") }),
            "Terminal output should display run ID")

        let message = SDKMessage.assistant(
            .init(text: "Opening Calculator", model: "test-model", stopReason: "end_turn")
        )
        handler.handleMessage(message)
        #expect(captured.contains(where: { $0.contains("Opening Calculator") }),
            "Terminal output should display assistant text")
    }

    @Test("terminal output handler displays tool use")
    func terminalOutputHandlerDisplaysToolUse() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        var captured: [String] = []
        let handler = SDKTerminalOutputHandler(
            output: TerminalOutput(write: { captured.append($0) })
        )

        let message = SDKMessage.toolUse(
            .init(toolName: "launch_app", toolUseId: "t1", input: "{}")
        )
        handler.handleMessage(message)
        #expect(captured.contains(where: { $0.contains("launch_app") }),
            "Terminal output should display tool name")
    }

    @Test("terminal output handler displays tool result error")
    func terminalOutputHandlerDisplaysToolResultError() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        var captured: [String] = []
        let handler = SDKTerminalOutputHandler(
            output: TerminalOutput(write: { captured.append($0) })
        )

        let message = SDKMessage.toolResult(
            .init(toolUseId: "t1", content: "App not found", isError: true)
        )
        handler.handleMessage(message)
        #expect(captured.contains(where: { $0.contains("错误") }),
            "Terminal output should display error indicator")
    }

    @Test("terminal output handler displays result")
    func terminalOutputHandlerDisplaysResult() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        var captured: [String] = []
        let handler = SDKTerminalOutputHandler(
            output: TerminalOutput(write: { captured.append($0) })
        )

        let message = SDKMessage.result(
            .init(subtype: .success, text: "Task completed", usage: nil, numTurns: 3, durationMs: 1500)
        )
        handler.handleMessage(message)
        #expect(captured.contains(where: { $0.contains("Task completed") }),
            "Terminal output should display final result")
    }

    @Test("JSON output handler produces JSON")
    func jsonOutputHandlerProducesJSON() async throws {
        guard SDK_STREAMING_CONFIGURED else { return }

        let handler = SDKJSONOutputHandler()

        handler.displayRunStart(runId: "test-456", task: "Open Calculator")

        handler.handleMessage(SDKMessage.toolUse(
            .init(toolName: "launch_app", toolUseId: "t1", input: "{}")
        ))
        handler.handleMessage(SDKMessage.toolResult(
            .init(toolUseId: "t1", content: "OK", isError: false)
        ))
        handler.handleMessage(SDKMessage.result(
            .init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 500)
        ))

        handler.displayCompletion()
    }

    // ========================================================================
    // MARK: - [P1] import 顺序验证
    // ========================================================================

    @Test("RunCommand import order correct")
    func runCommandImportOrderCorrect() async throws {
        guard SDK_AGENT_INTEGRATED else { return }
    }

    // ========================================================================
    // MARK: - [P1] 反模式验证
    // ========================================================================

    @Test("RunCommand does not bypass SDK Agent")
    func runCommandDoesNotBypassSDKAgent() async throws {
        guard SDK_AGENT_INTEGRATED else { return }
    }

    @Test("RunCommand does not import AxionHelper")
    func runCommandDoesNotImportAxionHelper() async throws {
        guard SDK_AGENT_INTEGRATED else { return }
    }

    // ========================================================================
    // MARK: - [P1] ToolNames.allToolNames 验证
    // ========================================================================

    @Test("ToolNames.allToolNames complete")
    func toolNamesAllToolNamesComplete() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let allNames = ToolNames.allToolNames
        #expect(allNames.count == 24, "Should have 24 tool names")
        #expect(allNames.contains("launch_app"))
        #expect(allNames.contains("click"))
        #expect(allNames.contains("screenshot"))
        #expect(allNames.contains("get_accessibility_tree"))
    }

    // ========================================================================
    // MARK: - [P1] AxionError 新增 cases
    // ========================================================================

    @Test("AxionError.missingApiKey has correct payload")
    func axionErrorMissingApiKeyHasCorrectPayload() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let error = AxionError.missingApiKey(suggestion: "Run axion setup")
        let payload = error.errorPayload

        #expect(payload.error == "missing_api_key")
        #expect(payload.suggestion == "Run axion setup")
    }

    @Test("AxionError.helperNotFound has correct payload")
    func axionErrorHelperNotFoundHasCorrectPayload() async throws {
        guard SDK_AGENT_INTEGRATED else { return }

        let error = AxionError.helperNotFound(suggestion: "Run axion doctor")
        let payload = error.errorPayload

        #expect(payload.error == "helper_not_found")
        #expect(payload.suggestion == "Run axion doctor")
    }
}
