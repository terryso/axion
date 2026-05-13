import Foundation
import OpenAgentSDK

import AxionCore

/// AgentRunner — independent Agent execution function.
/// References RunCommand logic but does not modify RunCommand.
/// Shared between ServerCommand (HTTP API) and RunCommand (CLI).
enum AgentRunner {

    // MARK: - Public API

    /// Run an agent task and return execution results.
    /// This is an independent implementation that mirrors RunCommand's logic
    /// without modifying RunCommand's behavior.
    ///
    /// - Parameters:
    ///   - config: The loaded AxionConfig.
    ///   - task: The task description to execute.
    ///   - options: Run options from the API request.
    ///   - runId: The run ID assigned by RunTracker (for SSE events).
    ///   - eventBroadcaster: Optional broadcaster for SSE streaming (nil in CLI mode).
    ///   - verbose: Whether to enable verbose logging.
    ///   - completion: Callback invoked with execution results.
    /// - Returns: Tuple of execution metrics.
    static func runAgent(
        config: AxionConfig,
        task: String,
        options: RunOptions,
        runId: String = "",
        eventBroadcaster: EventBroadcaster? = nil,
        verbose: Bool = false,
        completion: @escaping (String, APIRunStatus, [StepSummary], Int?, Int) -> Void
    ) async -> (totalSteps: Int, durationMs: Int, replanCount: Int, finalStatus: APIRunStatus, stepSummaries: [StepSummary]) {
        // 1. Resolve API key
        let apiKey = config.apiKey
            ?? ProcessInfo.processInfo.environment["AXION_API_KEY"]

        guard let apiKey, !apiKey.isEmpty else {
            completion("", .failed, [], nil, 0)
            return (0, 0, 0, .failed, [])
        }

        // 2. Resolve Helper path
        guard let helperPath = HelperPathResolver.resolveHelperPath() else {
            completion("", .failed, [], nil, 0)
            return (0, 0, 0, .failed, [])
        }

        // 3. Create MemoryStore
        let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
        let memoryStore = FileBasedMemoryStore(memoryDir: memoryDir)

        // 4. Load system prompt
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
            completion("", .failed, [], nil, 0)
            return (0, 0, 0, .failed, [])
        }

        // Build full system prompt with memory context
        var memoryContext: String? = nil
        do {
            let contextProvider = MemoryContextProvider()
            memoryContext = try await contextProvider.buildMemoryContext(
                task: task,
                store: memoryStore
            )
        } catch {
            // Non-fatal: continue without memory context
        }

        let systemPrompt = buildFullSystemPrompt(
            basePrompt: baseSystemPrompt,
            memoryContext: memoryContext
        )

        // 5. Configure MCP server for Helper
        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        // 6. Build safety hook registry
        let allowForeground = options.allowForeground ?? false
        let hookRegistry = await buildSafetyHookRegistry(
            sharedSeatMode: config.sharedSeatMode && !allowForeground
        )

        // 7. Build AgentOptions
        let effectiveMaxSteps = options.maxSteps ?? config.maxSteps

        let agentOptions = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: effectiveMaxSteps,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers,
            memoryStore: memoryStore,
            hookRegistry: hookRegistry,
            logLevel: verbose ? .debug : .info
        )

        // 8. Create and run Agent
        let agent = createAgent(options: agentOptions)

        var totalSteps = 0
        var stepSummaries: [StepSummary] = []
        var pendingToolUses: [String: SDKMessage.ToolUseData] = [:]
        var resultSubtype: SDKMessage.ResultData.Subtype? = nil
        let startTime = ContinuousClock.now

        let messageStream = agent.stream(task)
        for await message in messageStream {
            if _Concurrency.Task.isCancelled { break }

            switch message {
            case .toolUse(let data):
                totalSteps += 1
                pendingToolUses[data.toolUseId] = data

                // Emit step_started SSE event (Story 5.2)
                if let broadcaster = eventBroadcaster, !runId.isEmpty {
                    let stepIndex = totalSteps - 1
                    let event = SSEEvent.stepStarted(StepStartedData(
                        stepIndex: stepIndex,
                        tool: data.toolName
                    ))
                    await broadcaster.emit(runId: runId, event: event)
                }

            case .toolResult(let data):
                if let toolUse = pendingToolUses.removeValue(forKey: data.toolUseId) {
                    let stepIndex = stepSummaries.count
                    stepSummaries.append(StepSummary(
                        index: stepIndex,
                        tool: toolUse.toolName,
                        purpose: extractPurpose(from: toolUse),
                        success: !data.isError
                    ))

                    // Emit step_completed SSE event (Story 5.2)
                    if let broadcaster = eventBroadcaster, !runId.isEmpty {
                        let event = SSEEvent.stepCompleted(StepCompletedData(
                            stepIndex: stepIndex,
                            tool: toolUse.toolName,
                            purpose: extractPurpose(from: toolUse),
                            success: !data.isError,
                            durationMs: nil
                        ))
                        await broadcaster.emit(runId: runId, event: event)
                    }
                }

            case .result(let data):
                resultSubtype = data.subtype

            default:
                break
            }
        }

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(
            elapsed.components.seconds * 1000 +
            elapsed.components.attoseconds / 1_000_000_000_000
        )

        // Cleanup
        try? await agent.close()

        let finalStatus: APIRunStatus
        switch resultSubtype {
        case .success:
            finalStatus = .done
        case .none:
            finalStatus = .done
        default:
            finalStatus = .failed
        }

        return (totalSteps: totalSteps, durationMs: durationMs, replanCount: 0, finalStatus: finalStatus, stepSummaries: stepSummaries)
    }

    // MARK: - Private Helpers

    private static func buildFullSystemPrompt(basePrompt: String, memoryContext: String? = nil) -> String {
        var prompt = basePrompt
        if let memoryContext, !memoryContext.isEmpty {
            prompt += "\n\n\(memoryContext)"
        }
        return prompt
    }

    /// Creates a HookRegistry with preToolUse hook implementing SafetyChecker logic.
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

    /// Extract a purpose description from a toolUse message.
    private static func extractPurpose(from data: SDKMessage.ToolUseData) -> String {
        // Use tool name as a basic purpose; in the future,
        // this could be enriched with LLM-provided purpose metadata
        return data.toolName
    }
}
