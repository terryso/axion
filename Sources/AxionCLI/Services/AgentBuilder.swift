import Foundation
import OpenAgentSDK

import AxionCore

/// Result of building an Agent via the shared ``AgentBuilder``.
///
/// Contains the created Agent plus all resolved configuration so callers
/// (RunCommand, ApiRunner) can access helper paths, memory directories,
/// and system prompts for their own post-build logic.
/// Thread-safe box for capturing RunCompleteContext from SDK's onRunComplete callback.
final class RunCompleteContextBox: @unchecked Sendable {
    var context: RunCompleteContext?
}

struct AgentBuildResult: Sendable {
    let agent: Agent
    let helperPath: String
    let memoryDir: String
    let systemPrompt: String
    let agentOptions: AgentOptions
    let skillRegistry: SkillRegistry
    let skillRegisteredCount: Int
    let runCompleteBox: RunCompleteContextBox
    let reviewOrchestrator: ReviewOrchestrator?
    let intelligentCurator: IntelligentCurator?
    let usageStore: SkillUsageStore?
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
        let noMemory: Bool
        let noSkills: Bool
        let includePlaywright: Bool
        let allowForeground: Bool
        let maxSteps: Int?
        let maxTokens: Int?
        let verbose: Bool
        let dryrun: Bool
        let fast: Bool
        let runId: String?
        let sessionId: String?
        let sessionStore: SessionStore?

        static func forCLI(
            config: AxionConfig,
            task: String,
            noMemory: Bool = false,
            noSkills: Bool = false,
            allowForeground: Bool = false,
            maxSteps: Int? = nil,
            maxTokens: Int? = nil,
            verbose: Bool = false,
            dryrun: Bool = false,
            fast: Bool = false,
            runId: String? = nil,
            sessionId: String? = nil,
            sessionStore: SessionStore? = nil
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: task,
                noMemory: noMemory,
                noSkills: noSkills,
                includePlaywright: true,
                allowForeground: allowForeground,
                maxSteps: maxSteps,
                maxTokens: maxTokens,
                verbose: verbose,
                dryrun: dryrun,
                fast: fast,
                runId: runId,
                sessionId: sessionId,
                sessionStore: sessionStore
            )
        }

        static func forAPI(
            config: AxionConfig,
            task: String,
            request: CreateRunRequest
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: task,
                noMemory: false,
                noSkills: false,
                includePlaywright: false,
                allowForeground: request.allowForeground ?? false,
                maxSteps: request.maxSteps,
                maxTokens: nil,
                verbose: false,
                dryrun: false,
                fast: false,
                runId: nil,
                sessionId: nil,
                sessionStore: nil
            )
        }

        /// Build config for skill execution via SDK's `executeSkillStream()`.
        /// Creates a minimal agent: no MCP, no SkillTool, core tools only (no ToolSearch/AskUser).
        static func forSkillExecution(
            config: AxionConfig,
            skill: OpenAgentSDK.Skill,
            maxSteps: Int? = nil,
            verbose: Bool = false
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: "",
                noMemory: true,
                noSkills: true,
                includePlaywright: false,
                allowForeground: false,
                maxSteps: maxSteps,
                maxTokens: nil,
                verbose: verbose,
                dryrun: false,
                fast: false,
                runId: nil,
                sessionId: nil,
                sessionStore: nil
            )
        }

        /// Build config for MCP Server mode (`axion mcp`).
        /// No skills, no Playwright, no fast/dryrun modes. Memory context included.
        static func forMCP(
            config: AxionConfig,
            verbose: Bool = false
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: "",
                noMemory: false,
                noSkills: true,
                includePlaywright: false,
                allowForeground: false,
                maxSteps: nil,
                maxTokens: nil,
                verbose: verbose,
                dryrun: false,
                fast: false,
                runId: nil,
                sessionId: nil,
                sessionStore: nil
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

        // 4. Discover and register skills (owned by AgentBuilder)
        let skillRegistry = SkillRegistry()
        var skillRegisteredCount = 0
        if !buildConfig.noSkills {
            AxionBuiltInSkills.registerAll(into: skillRegistry)
            _ = skillRegistry.registerDiscoveredSkills()
            skillRegisteredCount = skillRegistry.allSkills.count
        }

        // 5. Build system prompt
        let systemPrompt = await buildSystemPrompt(
            config: config,
            task: task,
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            skillRegistry: skillRegistry,
            noMemory: buildConfig.noMemory,
            noSkills: buildConfig.noSkills,
            fast: buildConfig.fast,
            dryrun: buildConfig.dryrun
        )

        // 6. Configure MCP servers
        let mcpServers = MCPConfigResolver.resolveMCPServers(
            helperPath: helperPath,
            includePlaywright: buildConfig.includePlaywright
        )

        // 7. Build safety hook registry
        let hookRegistry = await SafetyHookFactory.buildSafetyHookRegistry(
            sharedSeatMode: config.sharedSeatMode && !buildConfig.allowForeground
        )

        // 8. Build tools: base SDK tools + Skill
        // Include core + specialist base tools explicitly so the streaming path
        // (agent.stream()) sends them in the API request. The non-streaming
        // query() path deduplicates via assembleToolPool.
        // Exclude ToolSearch and AskUser — GLM models get confused by ToolSearch
        // ("No deferred tools" kills the model's reasoning), and the system prompt
        // already lists all available tools.
        let excludedToolNames: Set<String> = ["ToolSearch", "AskUser"]
        var agentTools: [ToolProtocol] = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
            .filter { !excludedToolNames.contains($0.name) }
        if !buildConfig.noSkills {
            agentTools.append(createSkillTool(registry: skillRegistry))
        }

        // 9. Build AgentOptions
        let effectiveMaxSteps = buildConfig.maxSteps ?? config.maxSteps
        let effectiveMaxTokens = buildConfig.maxTokens ?? 4096

        var agentOptions = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: effectiveMaxSteps,
            maxTokens: effectiveMaxTokens,
            permissionMode: .bypassPermissions,
            tools: agentTools,
            mcpServers: mcpServers,
            memoryStore: memoryStore,
            hookRegistry: hookRegistry,
            skillRegistry: skillRegistry,
            logLevel: buildConfig.verbose ? .debug : .info,
            pauseTimeoutMs: 300_000
        )
        agentOptions.maxModelCalls = config.maxModelCalls
        agentOptions.runId = buildConfig.runId
        agentOptions.traceEnabled = true
        agentOptions.traceBaseURL = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("runs")

        // Session resume: inject sessionId + sessionStore into SDK AgentOptions
        if let sid = buildConfig.sessionId {
            agentOptions.sessionId = sid
            agentOptions.sessionStore = buildConfig.sessionStore
        }

        // Hook onRunComplete — captures context for post-run processing
        let runCompleteBox = RunCompleteContextBox()
        agentOptions.onRunComplete = { context in
            runCompleteBox.context = context
        }

        // 10. Create Agent
        let agent = createAgent(options: agentOptions)

        // 11. Create ReviewOrchestrator + IntelligentCurator (when memory is on and not dryrun)
        let reviewOrchestrator: ReviewOrchestrator?
        let intelligentCurator: IntelligentCurator?
        let usageStore: SkillUsageStore?
        if !buildConfig.noMemory, !buildConfig.dryrun {
            let scheduleConfig = ReviewScheduleConfig(
                memoryReviewInterval: config.reviewMemoryInterval ?? ReviewScheduleConfig().memoryReviewInterval,
                skillReviewInterval: config.reviewSkillInterval ?? ReviewScheduleConfig().skillReviewInterval,
                minMessagesForReview: config.reviewMinMessages ?? ReviewScheduleConfig().minMessagesForReview,
                reviewModel: config.reviewModel
            )
            let reviewFactStore = FactStore(memoryDir: memoryDir)
            let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
            let concreteStore = SkillUsageStore(skillsDir: skillsDir)
            usageStore = concreteStore
            let evolverClient = AnthropicClient(
                apiKey: apiKey,
                baseURL: config.baseURL
            )
            let skillEvolver = LLMSkillEvolver(
                client: evolverClient,
                evolutionModel: config.reviewModel ?? AxionConfig.defaultReviewModel
            )
            reviewOrchestrator = ReviewOrchestrator(
                scheduleConfig: scheduleConfig,
                factStore: reviewFactStore,
                skillRegistry: skillRegistry,
                skillEvolver: skillEvolver,
                usageStore: concreteStore
            )

            // IntelligentCurator — reuses deps from ReviewOrchestrator block
            let curatorStore = SkillCuratorStore(skillsDir: skillsDir)
            let curatorConfig = SkillCuratorConfig(
                intervalHours: config.curatorIntervalHours ?? 168.0,
                staleAfterDays: config.curatorStaleAfterDays ?? 30,
                archiveAfterDays: config.curatorArchiveAfterDays ?? 90,
                dryRun: config.curatorDryRun ?? false,
                enabled: config.curatorEnabled ?? true
            )
            let skillCurator = SkillCurator(
                usageStore: concreteStore,
                curatorStore: curatorStore,
                config: curatorConfig
            )
            intelligentCurator = IntelligentCurator(
                skillCurator: skillCurator,
                factStore: reviewFactStore,
                skillRegistry: skillRegistry,
                skillEvolver: skillEvolver,
                usageStore: concreteStore,
                curatorStore: curatorStore
            )
        } else {
            reviewOrchestrator = nil
            intelligentCurator = nil
            usageStore = nil
        }

        return AgentBuildResult(
            agent: agent,
            helperPath: helperPath,
            memoryDir: memoryDir,
            systemPrompt: systemPrompt,
            agentOptions: agentOptions,
            skillRegistry: skillRegistry,
            skillRegisteredCount: skillRegisteredCount,
            runCompleteBox: runCompleteBox,
            reviewOrchestrator: reviewOrchestrator,
            intelligentCurator: intelligentCurator,
            usageStore: usageStore
        )
    }

    /// Builds a minimal agent for skill execution via SDK's `executeSkillStream()`.
    ///
    /// Unlike `build()`, this creates a lightweight agent:
    /// - No MCP servers (no desktop automation tools)
    /// - No SkillTool (skill is already resolved)
    /// - No memory injection
    /// - Core tools only (ToolSearch/AskUser excluded)
    /// - Model overridden by skill if specified
    static func buildSkillAgent(
        config: AxionConfig,
        skill: OpenAgentSDK.Skill,
        maxSteps: Int? = nil,
        verbose: Bool = false,
        eventBus: EventBus? = nil
    ) async throws -> Agent {
        let apiKey = config.apiKey
            ?? ProcessInfo.processInfo.environment["AXION_API_KEY"]

        guard let apiKey, !apiKey.isEmpty else {
            throw AxionError.missingApiKey(
                suggestion: "Run 'axion setup' to configure your API key, or set AXION_API_KEY environment variable."
            )
        }

        let registry = SkillRegistry()
        registry.register(skill)

        // Core tools only — exclude ToolSearch/AskUser to avoid confusing the LLM
        let excludedTools: Set<String> = ["ToolSearch", "AskUser"]
        let tools = getAllBaseTools(tier: .core).filter { !excludedTools.contains($0.name) }

        let effectiveMaxSteps = maxSteps ?? config.maxSteps
        let effectiveModel = skill.modelOverride ?? config.model

        var agentOptions = AgentOptions(
            apiKey: apiKey,
            model: effectiveModel,
            baseURL: config.baseURL,
            systemPrompt: "All filesystem and terminal operations should use the current working directory.\n\n# Task Summary — MANDATORY\n\nEVERY response MUST end with exactly one summary line in this format:\n[结果] <one-line summary, max 100 chars>\nThis is NOT optional. Even if the task failed, you MUST include this line.",
            maxTurns: effectiveMaxSteps,
            maxTokens: 16384,
            permissionMode: .bypassPermissions,
            tools: tools,
            mcpServers: nil,
            skillRegistry: registry,
            logLevel: verbose ? .debug : .info
        )
        agentOptions.eventBus = eventBus

        return createAgent(options: agentOptions)
    }

    // MARK: - System Prompt

    /// Builds the full system prompt for desktop automation.
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
            let factStore = AxionFactStore(memoryDir: memoryDir)
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

        let baseSystemPrompt = (try? PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: mcpPrefixedToolNames),
                "max_steps": String(config.maxSteps),
            ],
            fromDirectory: promptDir
        )) ?? ""

        let skillsPrompt = noSkills ? "" : skillRegistry.formatSkillsForPrompt()

        let prompt = buildFullSystemPrompt(
            basePrompt: baseSystemPrompt,
            memoryContext: memoryContext,
            skillsPrompt: skillsPrompt
        )

        return appendModeInstructions(to: prompt, fast: fast, dryrun: dryrun)
    }

    /// Appends fast/dryrun mode instructions to a system prompt.
    static func appendModeInstructions(to prompt: String, fast: Bool, dryrun: Bool) -> String {
        var prompt = prompt
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

}
