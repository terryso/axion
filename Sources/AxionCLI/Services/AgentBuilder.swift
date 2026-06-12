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

    // MARK: - Shared Helpers

    /// Tool names excluded from all agent builds — ToolSearch confuses GLM models,
    /// AskUser is handled by the system prompt.
    static let excludedToolNames: Set<String> = ["ToolSearch", "AskUser"]

    /// Resolves the API key from config or environment, throwing if neither is available.
    static func resolveApiKey(from config: AxionConfig) throws -> String {
        let apiKey = config.apiKey
            ?? ProcessInfo.processInfo.environment["AXION_API_KEY"]

        guard let apiKey, !apiKey.isEmpty else {
            throw AxionError.missingApiKey(
                suggestion: "Run 'axion setup' to configure your API key, or set AXION_API_KEY environment variable."
            )
        }
        return apiKey
    }

    // MARK: - Build

    /// Constructs an Agent with all shared configuration applied.
    ///
    /// This is the single entry point for both CLI and API paths.
    /// - Returns: ``AgentBuildResult`` with the agent and resolved configuration.
    /// - Throws: Errors for missing API key or helper path.
    static func build(_ buildConfig: BuildConfig, eventBus: EventBus? = nil) async throws -> AgentBuildResult {
        let config = buildConfig.config
        let task = buildConfig.task

        // 1. Resolve API key
        let apiKey = try resolveApiKey(from: config)

        // 2. Resolve Helper path (only required for desktop automation mode)
        let resolvedHelperPath = HelperPathResolver.resolveHelperPath()
        guard resolvedHelperPath != nil || buildConfig.dryrun else {
            throw AxionError.helperNotFound(
                suggestion: "Ensure AxionHelper.app is installed. Run 'axion doctor' to diagnose."
            )
        }
        let helperPath = resolvedHelperPath ?? "/usr/bin/true"

        // 3. Create MemoryStore
        let memoryDir = ConfigManager.memoryDirectory
        let memoryStore = FileBasedMemoryStore(memoryDir: memoryDir)

        // 3b. Prepare skillsDir
        let skillsDir = ConfigManager.skillsDirectory

        // 4. Discover and register skills (owned by AgentBuilder)
        let skillRegistry = SkillRegistry()
        var skillRegisteredCount = 0
        if !buildConfig.noSkills {
            AxionBuiltInSkills.registerAll(into: skillRegistry)
            _ = skillRegistry.registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)
            skillRegisteredCount = skillRegistry.allSkills.count
        }

        // 5. Build system prompt (branch by mode)
        let noMemory = buildConfig.noMemory
        let noSkills = buildConfig.noSkills
        let dryrun = buildConfig.dryrun
        let includeSaveSkillGuidance = !noMemory && !dryrun

        let systemPrompt = await buildSystemPrompt(
            config: config,
            task: task,
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            skillRegistry: skillRegistry,
            noMemory: noMemory,
            noSkills: noSkills,
            fast: buildConfig.fast,
            dryrun: dryrun,
            includeSaveSkillGuidance: includeSaveSkillGuidance
        )

        // 6. Configure MCP servers (skip in dryrun and coding agent — no side-effect tools allowed)
        let mcpServers: [String: McpServerConfig]?
        if dryrun {
            mcpServers = nil
        } else {
            mcpServers = MCPConfigResolver.resolveMCPServers(
                helperPath: helperPath,
                includePlaywright: buildConfig.includePlaywright
            )
        }

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
        //
        // In dryrun mode, strip side-effect tools (Bash, Skill) so the agent
        // can only plan — never execute.
        let dryrunExcludedToolNames: Set<String> = ["Bash", "Skill"]
        var agentTools: [ToolProtocol] = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
            .filter { !excludedToolNames.contains($0.name) }
            .filter { !dryrun || !dryrunExcludedToolNames.contains($0.name) }
        if !noSkills, !dryrun {
            agentTools.append(createSkillTool(registry: skillRegistry))
        }

        // Memory tool — Agent can actively read/write MEMORY.md and USER.md
        if !noMemory, !dryrun {
            let universalStore = UniversalMemoryStore(memoryDir: memoryDir)
            agentTools.append(MemoryTool(store: universalStore))
        }

        // Storage tools (Story 39.1 scan + propose [read-only]; Story 39.2 execute + undo [side-effect]).
        // Registered under !dryrun to match the storage-ops lifecycle. Execute/undo write manifests
        // to ~/.axion/storage-ops/ (draft-first, re-validated, recoverable via system Trash).
        if !dryrun {
            let storageScanner = StorageScanService()
            agentTools.append(StorageScanTool(scanner: storageScanner, config: config.storage))
            agentTools.append(ProposeStoragePlanTool(config: config.storage))

            // Story 39.2: shared manifest store so execute + undo read/write the same operation files.
            let manifestStore = StorageManifestStore(storageOpsDir: config.storage.storageOpsDir)
            agentTools.append(ExecuteStoragePlanTool(
                executor: StorageExecutor(manifestStore: manifestStore),
                config: config.storage
            ))
            agentTools.append(UndoStorageOpTool(
                undoer: StorageUndoService(manifestStore: manifestStore),
                config: config.storage
            ))

            // Story 39.3: App uninstall (scan = read-only; execute = side-effect, draft-first manifest,
            // re-validated bundle/support, recoverable via system Trash — never permanent delete).
            // Shares the same manifestStore so execute + undo read/write the same operation files.
            let appPlanBuilder = AppUninstallPlanBuilder(
                supportDataScanner: SupportDataScanService(),
                appDiscoverer: AppDiscoveryService(),
                hintReader: ExternalHintReader()
            )
            agentTools.append(ScanAppUninstallTool(planBuilder: appPlanBuilder))
            agentTools.append(ExecuteAppUninstallTool(
                executor: AppUninstallExecutor(
                    manifestStore: manifestStore,
                    appQuitter: AppQuitter()
                ),
                config: config.storage
            ))
        }

        // 8b. Create review infrastructure (ReviewOrchestrator + IntelligentCurator + SkillUsageStore)
        let infra = buildReviewInfrastructure(
            config: config,
            apiKey: apiKey,
            memoryDir: memoryDir,
            skillsDir: skillsDir,
            skillRegistry: skillRegistry,
            noMemory: noMemory,
            dryrun: dryrun
        )
        let reviewOrchestrator = infra.reviewOrchestrator
        let intelligentCurator = infra.intelligentCurator
        let usageStore = infra.usageStore

        // save_skill tool — Agent can persist reusable skills to disk
        if let usageStore {
            agentTools.append(createSaveSkillTool(
                skillRegistry: skillRegistry,
                usageStore: usageStore,
                skillsDir: skillsDir
            ))
        }

        // 9. Build AgentOptions
        let effectiveMaxSteps = buildConfig.dryrun ? 1 : (buildConfig.maxSteps ?? config.maxSteps)
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
        agentOptions.todoStore = TodoStore()
        agentOptions.maxModelCalls = config.maxModelCalls
        agentOptions.env = config.env
        agentOptions.runId = buildConfig.runId
        agentOptions.traceEnabled = true
        agentOptions.traceBaseURL = ConfigManager.traceDirectory

        // Wire EventBus so SDK publishes events (AgentCompletedEvent etc.)
        agentOptions.eventBus = eventBus

        // Session resume: inject sessionId + sessionStore into SDK AgentOptions
        // Permission: inject canUseTool from ChatCommand (interactive chat only).
        // Story 39.4: run 入口（desktopAutomation）接入存储审批门（storage execute 工具走门，其余放行）。
        if let canUseTool = buildConfig.canUseTool {
            agentOptions.canUseTool = canUseTool
        } else if buildConfig.mode == .desktopAutomation, !buildConfig.dryrun, !buildConfig.emitTokenStream {
            let runCollector = RunApprovalCollector(
                writeStdout: { msg in fputs(msg, stdout) },
                readLine: { Swift.readLine() }
            )
            agentOptions.canUseTool = StorageApprovalGate.makeRunCanUseTool(
                collector: runCollector,
                isInteractiveFn: { isatty(fileno(stdin)) != 0 },
                jsonOutput: buildConfig.jsonOutput
            )
        }
        if let sid = buildConfig.sessionId {
            agentOptions.sessionId = sid
            agentOptions.sessionStore = buildConfig.sessionStore
        }

        // Token streaming: enable for TG tasks that need edit-based streaming
        if buildConfig.emitTokenStream {
            agentOptions.emitTokenStream = true
        }

        // Hook onRunComplete — captures context for post-run processing
        let runCompleteBox = RunCompleteContextBox()
        agentOptions.onRunComplete = { context in
            runCompleteBox.context = context
        }

        // 10. Create Agent
        let agent = createAgent(options: agentOptions)

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
    ) async throws -> (agent: Agent, runCompleteBox: RunCompleteContextBox) {
        let apiKey = try resolveApiKey(from: config)

        let registry = SkillRegistry()
        registry.register(skill)

        // Core tools only — exclude ToolSearch/AskUser to avoid confusing the LLM
        let tools = getAllBaseTools(tier: .core).filter { !excludedToolNames.contains($0.name) }

        let effectiveMaxSteps = maxSteps ?? config.maxSteps
        let effectiveModel = skill.modelOverride ?? config.model

        let cwd = FileManager.default.currentDirectoryPath
        var agentOptions = AgentOptions(
            apiKey: apiKey,
            model: effectiveModel,
            baseURL: config.baseURL,
            systemPrompt: "All filesystem and terminal operations must use \(cwd) as the working directory. Do NOT invent or guess paths — always resolve relative paths against \(cwd).\n\n# Task Summary — MANDATORY\n\nEVERY response MUST end with exactly one summary line in this format:\n[结果] <one-line summary, max 100 chars>\nThis is NOT optional. Even if the task failed, you MUST include this line.",
            maxTurns: effectiveMaxSteps,
            maxTokens: 16384,
            permissionMode: .bypassPermissions,
            tools: tools,
            mcpServers: nil,
            skillRegistry: registry,
            logLevel: verbose ? .debug : .info
        )
        agentOptions.eventBus = eventBus
        agentOptions.env = config.env

        let runCompleteBox = RunCompleteContextBox()
        agentOptions.onRunComplete = { context in
            runCompleteBox.context = context
        }

        let agent = createAgent(options: agentOptions)
        return (agent, runCompleteBox)
    }
}
