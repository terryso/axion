import Foundation
import OpenAgentSDK

import AxionCore

/// Result of building an Agent via the shared ``AgentBuilder``.
///
/// Contains the created Agent plus all resolved configuration so callers
/// (RunCommand, ApiRunner) can access helper paths, memory directories,
/// and system prompts for their own post-build logic.
struct AgentBuildResult: Sendable {
    let agent: Agent
    let helperPath: String
    let memoryDir: String
    let systemPrompt: String
    let agentOptions: AgentOptions
    let skillRegistry: SkillRegistry
    let explicitSkill: OpenAgentSDK.Skill?
}

/// Single source of truth for constructing an Agent used by both CLI (RunCommand)
/// and API (ApiRunner). Handles API key resolution, helper path, memory store,
/// system prompt, MCP servers, safety hooks, tools, and AgentOptions — but NOT
/// any caller-specific concerns like TakeoverIO, SSE broadcasting, or cost tracking.
enum AgentBuilder {

    // MARK: - Configuration

    struct BuildConfig: Sendable {
        let config: AxionConfig
        let task: String
        let skillRegistry: SkillRegistry
        let explicitSkill: OpenAgentSDK.Skill?
        let noMemory: Bool
        let noSkills: Bool
        let includePlaywright: Bool
        let allowForeground: Bool
        let maxSteps: Int?
        let maxTokens: Int?
        let verbose: Bool
        let dryrun: Bool
        let fast: Bool

        static func forCLI(
            config: AxionConfig,
            task: String,
            skillRegistry: SkillRegistry,
            explicitSkill: OpenAgentSDK.Skill?,
            noMemory: Bool = false,
            noSkills: Bool = false,
            allowForeground: Bool = false,
            maxSteps: Int? = nil,
            maxTokens: Int? = nil,
            verbose: Bool = false,
            dryrun: Bool = false,
            fast: Bool = false
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: task,
                skillRegistry: skillRegistry,
                explicitSkill: explicitSkill,
                noMemory: noMemory,
                noSkills: noSkills,
                includePlaywright: true,
                allowForeground: allowForeground,
                maxSteps: maxSteps,
                maxTokens: maxTokens,
                verbose: verbose,
                dryrun: dryrun,
                fast: fast
            )
        }

        static func forAPI(
            config: AxionConfig,
            task: String,
            options: RunOptions
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: task,
                skillRegistry: SkillRegistry(),
                explicitSkill: nil,
                noMemory: false,
                noSkills: false,
                includePlaywright: false,
                allowForeground: options.allowForeground ?? false,
                maxSteps: options.maxSteps,
                maxTokens: nil,
                verbose: false,
                dryrun: false,
                fast: false
            )
        }

        static func forAPISkill(
            config: AxionConfig,
            task: String,
            skill: OpenAgentSDK.Skill,
            skillRegistry: SkillRegistry,
            verbose: Bool = false
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: task,
                skillRegistry: skillRegistry,
                explicitSkill: skill,
                noMemory: false,
                noSkills: false,
                includePlaywright: false,
                allowForeground: false,
                maxSteps: nil,
                maxTokens: nil,
                verbose: verbose,
                dryrun: false,
                fast: false
            )
        }
    }

    // MARK: - Build

    /// Constructs an Agent with all shared configuration applied.
    ///
    /// This is the single entry point for both CLI and API paths.
    /// - Returns: ``AgentBuildResult`` with the agent and resolved configuration.
    /// - Throws: Errors for missing API key or helper path.
    static func build(_ buildConfig: BuildConfig) async throws -> AgentBuildResult {
        let config = buildConfig.config
        let task = buildConfig.task

        // 1. Resolve API key
        let apiKey = config.apiKey
            ?? ProcessInfo.processInfo.environment["AXION_API_KEY"]

        guard let apiKey, !apiKey.isEmpty else {
            throw AxionError.missingApiKey(
                suggestion: "Run 'axion setup' to configure your API key, or set AXION_API_KEY environment variable."
            )
        }

        // 2. Resolve Helper path
        let resolvedHelperPath = HelperPathResolver.resolveHelperPath()
        guard resolvedHelperPath != nil || buildConfig.dryrun else {
            throw AxionError.helperNotFound(
                suggestion: "Ensure AxionHelper.app is installed. Run 'axion doctor' to diagnose."
            )
        }
        let helperPath = resolvedHelperPath ?? "/usr/bin/true"

        // 3. Create MemoryStore
        let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
        let memoryStore = FileBasedMemoryStore(memoryDir: memoryDir)

        // 4. Build system prompt (always generic planner — skill content is in user message)
        let systemPrompt = await buildSystemPrompt(
            config: config,
            task: task,
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            skillRegistry: buildConfig.skillRegistry,
            noMemory: buildConfig.noMemory,
            noSkills: buildConfig.noSkills,
            fast: buildConfig.fast,
            dryrun: buildConfig.dryrun
        )

        // 5. Configure MCP servers
        var mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath)),
        ]
        if buildConfig.includePlaywright {
            mcpServers["playwright"] = .stdio(McpStdioConfig(command: "npx", args: ["@playwright/mcp@latest"]))
        }

        // 6. Build safety hook registry
        let hookRegistry = await buildSafetyHookRegistry(
            sharedSeatMode: config.sharedSeatMode && !buildConfig.allowForeground
        )

        // 7. Build tools — always include SkillTool (SDK manages restrictions)
        let hasToolRestrictions = buildConfig.explicitSkill?.toolRestrictions != nil

        var agentTools: [ToolProtocol] = [createPauseForHumanTool()]
        if !buildConfig.noSkills {
            agentTools.append(createSkillTool(registry: buildConfig.skillRegistry))
        }

        // When explicitSkill has tool restrictions, exclude MCP servers
        let effectiveMcpServers: [String: McpServerConfig]? = hasToolRestrictions ? nil : mcpServers

        // 8. Determine effective model
        let effectiveModel = buildConfig.explicitSkill?.modelOverride ?? config.model

        // 9. Don't set allowedTools — let SDK's ToolRestrictionStack manage tool filtering

        // 10. Build AgentOptions — pass skillRegistry (unblocks SDK's ToolRestrictionStack)
        let effectiveMaxSteps = buildConfig.maxSteps ?? config.maxSteps
        let effectiveMaxTokens = buildConfig.maxTokens ?? 4096

        let agentOptions = AgentOptions(
            apiKey: apiKey,
            model: effectiveModel,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: effectiveMaxSteps,
            maxTokens: effectiveMaxTokens,
            permissionMode: .bypassPermissions,
            tools: agentTools,
            mcpServers: effectiveMcpServers,
            memoryStore: memoryStore,
            hookRegistry: hookRegistry,
            skillRegistry: buildConfig.skillRegistry,
            logLevel: buildConfig.verbose ? .debug : .info,
            pauseTimeoutMs: 300_000
        )

        // 11. Create Agent
        let agent = createAgent(options: agentOptions)

        return AgentBuildResult(
            agent: agent,
            helperPath: helperPath,
            memoryDir: memoryDir,
            systemPrompt: systemPrompt,
            agentOptions: agentOptions,
            skillRegistry: buildConfig.skillRegistry,
            explicitSkill: buildConfig.explicitSkill
        )
    }

    // MARK: - Skill Pre-Resolution

    /// Pre-resolves an explicit `/skill-name` invocation by calling the SDK's
    /// SkillTool directly (mirrors SwiftWork's `resolveExplicitSlashSkillRequest`).
    ///
    /// Instead of injecting `skill.promptTemplate` into the system prompt, this
    /// method extracts the resolved skill content so it can be passed as the
    /// **user message** to `agent.stream()`. The SDK's `ToolRestrictionStack` is
    /// managed internally when SkillTool.call() executes.
    ///
    /// - Returns: The resolved user message string (skill prompt content), or nil
    ///   if resolution failed.
    static func resolveExplicitSlashSkillRequest(
        skill: OpenAgentSDK.Skill,
        args: String?,
        skillRegistry: SkillRegistry
    ) async -> String? {
        let tool = createSkillTool(registry: skillRegistry)
        let context = ToolContext(
            cwd: "/",
            toolUseId: UUID().uuidString,
            skillRegistry: skillRegistry,
            restrictionStack: ToolRestrictionStack()
        )

        let inputPayload: [String: String] = [
            "skill": skill.name,
            "args": args ?? ""
        ]

        let result = await tool.call(input: inputPayload, context: context)

        guard !result.isError else { return nil }

        // Parse the JSON result to extract the prompt field
        guard let data = result.content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prompt = json["prompt"] as? String else {
            return nil
        }

        return prompt
    }

    // MARK: - System Prompt

    /// Builds the full system prompt — always uses generic planner prompt.
    /// Skill content is now passed as user message via pre-resolution, not injected here.
    private static func buildSystemPrompt(
        config: AxionConfig,
        task: String,
        memoryStore: FileBasedMemoryStore,
        memoryDir: String,
        skillRegistry: SkillRegistry,
        noMemory: Bool,
        noSkills: Bool,
        fast: Bool,
        dryrun: Bool
    ) async -> String {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let mcpPrefixedToolNames = ToolNames.allToolNames.map { "mcp__axion-helper__\($0)" }

        // Memory context
        var memoryContext: String? = nil
        if !noMemory {
            let contextProvider = MemoryContextProvider()
            let factStore = MemoryFactStore(memoryDir: memoryDir)
            do {
                if let factContext = await contextProvider.buildFactMemoryContext(
                    task: task,
                    factStore: factStore
                ) {
                    memoryContext = factContext
                } else {
                    memoryContext = try await contextProvider.buildMemoryContext(
                        task: task,
                        store: memoryStore
                    )
                }
            } catch {
                // Non-fatal: continue without memory context
            }
        }

        // Always load generic planner prompt (skill content is in user message)
        let baseSystemPrompt = (try? PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: mcpPrefixedToolNames),
                "max_steps": String(config.maxSteps),
            ],
            fromDirectory: promptDir
        )) ?? ""

        let skillsPrompt = noSkills ? "" : skillRegistry.formatSkillsForPrompt()

        var prompt = buildFullSystemPrompt(
            basePrompt: baseSystemPrompt,
            memoryContext: memoryContext,
            skillsPrompt: skillsPrompt
        )

        // CLI mode-specific instructions (fast/dryrun)
        if fast {
            prompt += """

            IMPORTANT: You are in FAST mode. Generate the MINIMUM steps needed (1-3 steps max).
            - Skip discovery steps (list_apps, list_windows, get_accessibility_tree) when the target app is obvious
            - Do NOT call screenshot for verification — trust tool results
            - Prefer direct actions (launch_app, type_text, hotkey) over exploration
            - If a step fails, do NOT retry with alternative approaches — report failure immediately
            """
        }

        if dryrun {
            prompt += "\n\nIMPORTANT: You are in DRYRUN mode. Generate a plan but do NOT execute any tools. Return a plan JSON with status 'done' and the steps you would execute."
        }

        return prompt
    }

    /// Builds the full system prompt with skills section appended.
    static func buildFullSystemPrompt(
        basePrompt: String,
        memoryContext: String? = nil,
        skillsPrompt: String = ""
    ) -> String {
        var prompt = basePrompt

        if let memoryContext, !memoryContext.isEmpty {
            prompt += "\n\n\(memoryContext)"
        }

        if !skillsPrompt.isEmpty {
            prompt += """

            ## Available Skills

            When the user's task matches a skill's TRIGGER condition, call the `Skill` tool with the skill name and arguments. Parameters: `skill` (skill name, required) and `args` (user arguments, optional). The tool returns a JSON with `prompt` (the skill's prompt template) — follow that prompt as your operating instructions for the rest of the task.

            \(skillsPrompt)
            """
        }

        return prompt
    }

    /// Builds the full system prompt with CLI mode instructions (fast/dryrun) appended.
    /// Used for testing the prompt construction pipeline.
    static func buildCLISystemPrompt(
        basePrompt: String,
        fast: Bool = false,
        dryrun: Bool = false,
        memoryContext: String? = nil,
        skillsPrompt: String = ""
    ) -> String {
        var prompt = buildFullSystemPrompt(
            basePrompt: basePrompt,
            memoryContext: memoryContext,
            skillsPrompt: skillsPrompt
        )

        if fast {
            prompt += """

            IMPORTANT: You are in FAST mode. Generate the MINIMUM steps needed (1-3 steps max).
            - Skip discovery steps (list_apps, list_windows, get_accessibility_tree) when the target app is obvious
            - Do NOT call screenshot for verification — trust tool results
            - Prefer direct actions (launch_app, type_text, hotkey) over exploration
            - If a step fails, do NOT retry with alternative approaches — report failure immediately
            """
        }

        if dryrun {
            prompt += "\n\nIMPORTANT: You are in DRYRUN mode. Generate a plan but do NOT execute any tools. Return a plan JSON with status 'done' and the steps you would execute."
        }

        return prompt
    }

    // MARK: - Safety Hook

    /// Creates a HookRegistry with preToolUse hook implementing SafetyChecker logic.
    /// Uses MCP-prefixed tool names (e.g., "mcp__axion-helper__click") since that's
    /// what the SDK passes through hooks.
    static func buildSafetyHookRegistry(sharedSeatMode: Bool) async -> HookRegistry {
        let registry = HookRegistry()

        if sharedSeatMode {
            let foregroundTools = ToolNames.foregroundToolNames.map { "mcp__axion-helper__\($0)" }
            let safetyHook = HookDefinition(handler: { input in
                guard let toolName = input.toolName else { return HookOutput(decision: .approve) }

                if foregroundTools.contains(toolName) {
                    return HookOutput(
                        decision: .block,
                        reason: "Tool '\(toolName)' requires foreground interaction and is blocked in shared seat mode for safety. Use --allow-foreground to enable."
                    )
                }
                return HookOutput(decision: .approve)
            })

            await registry.register(.preToolUse, definition: safetyHook)
        }

        return registry
    }
}
