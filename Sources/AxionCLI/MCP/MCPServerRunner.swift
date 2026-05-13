import Foundation
import OpenAgentSDK

import AxionCore

/// Orchestrator that creates an Agent, assembles tools, and runs
/// an AgentMCPServer exposing Axion's capabilities via MCP stdio.
struct MCPServerRunner {

    // MARK: - Properties

    let config: AxionConfig
    let verbose: Bool

    // MARK: - Public API

    func run() async throws {
        // 1. Resolve API key
        let apiKey = config.apiKey
            ?? ProcessInfo.processInfo.environment["AXION_API_KEY"]

        guard let apiKey, !apiKey.isEmpty else {
            fputs("Error: API key not configured. Run `axion setup`.\n", stderr)
            return
        }

        // 2. Resolve Helper path
        guard let helperPath = HelperPathResolver.resolveHelperPath() else {
            fputs("Error: AxionHelper not found.\n", stderr)
            return
        }

        // 3. Build system prompt (reuse AgentRunner logic)
        let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
        let memoryStore = FileBasedMemoryStore(memoryDir: memoryDir)

        let promptDir = PromptBuilder.resolvePromptDirectory()
        let mcpPrefixedToolNames = ToolNames.allToolNames.map { "mcp__axion-helper__\($0)" }

        let baseSystemPrompt: String
        do {
            baseSystemPrompt = try PromptBuilder.load(
                name: "planner-system",
                variables: [
                    "tools": PromptBuilder.buildToolListDescription(from: mcpPrefixedToolNames),
                    "max_steps": String(config.maxSteps),
                ],
                fromDirectory: promptDir
            )
        } catch {
            fputs("Error: Failed to load planner prompt: \(error)\n", stderr)
            return
        }

        // Build full system prompt with memory context
        var memoryContext: String?
        do {
            let contextProvider = MemoryContextProvider()
            memoryContext = try await contextProvider.buildMemoryContext(
                task: "",
                store: memoryStore
            )
        } catch {
            // Non-fatal: continue without memory context
        }

        let systemPrompt = Self.buildFullSystemPrompt(basePrompt: baseSystemPrompt, memoryContext: memoryContext)

        // 4. Configure MCP server for Helper
        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath)),
        ]

        // 5. Build safety hook registry
        let hookRegistry = await Self.buildSafetyHookRegistry(
            sharedSeatMode: config.sharedSeatMode
        )

        // 6. Create Agent
        let agentOptions = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: config.maxSteps,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers,
            memoryStore: memoryStore,
            hookRegistry: hookRegistry,
            logLevel: verbose ? .debug : .info
        )
        let agent = createAgent(options: agentOptions)

        // 7. Assemble tool pool (connects to Helper, discovers tools)
        let (helperTools, _) = await agent.assembleFullToolPool()

        // 8. Create RunTracker and custom tools
        let runTracker = RunTracker()
        let taskQueue = TaskQueue()
        let runTaskTool = RunTaskTool(agent: agent, runTracker: runTracker, taskQueue: taskQueue)
        let queryTool = QueryTaskStatusTool(runTracker: runTracker)

        // 9. Merge all tools
        var allTools = helperTools
        allTools.append(runTaskTool)
        allTools.append(queryTool)

        // 10. Create and run MCP server
        let version = AxionVersion.current
        let server = AgentMCPServer(name: "axion", version: version, tools: allTools)

        fputs("Axion MCP server running (version \(version))\n", stderr)
        try await server.run(agent: agent)

        // 11. Cleanup — wait for in-flight tasks before closing agent
        await taskQueue.gracefulShutdown()
        try? await agent.close()
        fputs("Axion MCP server stopped.\n", stderr)
    }

    // MARK: - Private Helpers

    private static func buildFullSystemPrompt(basePrompt: String, memoryContext: String?) -> String {
        var prompt = basePrompt
        if let memoryContext, !memoryContext.isEmpty {
            prompt += "\n\n\(memoryContext)"
        }
        return prompt
    }

    private static func buildSafetyHookRegistry(sharedSeatMode: Bool) async -> HookRegistry {
        let registry = HookRegistry()

        if sharedSeatMode {
            let foregroundTools = ToolNames.foregroundToolNames
            let safetyHook = HookDefinition(handler: { input in
                guard let toolName = input.toolName else { return HookOutput(decision: .approve) }

                if foregroundTools.contains(toolName) {
                    return HookOutput(
                        decision: .block,
                        reason: "Tool '\(toolName)' requires foreground interaction and is blocked in shared seat mode for safety."
                    )
                }
                return HookOutput(decision: .approve)
            })

            await registry.register(.preToolUse, definition: safetyHook)
        }

        return registry
    }
}
