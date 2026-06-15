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

    /// Tool names stripped from base tools in dry-run mode (side-effect tools).
    ///
    /// Story 40.3: extended to include `Agent`/`Task` as intent documentation. These are SDK
    /// factory tools (`createAgentTool()`/`createTaskTool()`) and are never present in
    /// `getAllBaseTools(tier:)`, so the dry-run filter has no actual effect on them — their
    /// exclusion is governed by the separate `if !dryrun { ... }` registration branch in
    /// ``buildToolProfile``. Listing them here declares the intent ("dry-run plans, never
    /// spawns child agents") and future-proofs against the SDK adding them to a base tier.
    static let dryrunExcludedToolNames: Set<String> = ["Bash", "Skill", "Agent", "Task"]

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
                includePlaywright: buildConfig.includePlaywright,
                userServers: config.mcpServers
            )
        }

        // 7. Build safety hook registry
        let hookRegistry = await SafetyHookFactory.buildSafetyHookRegistry(
            sharedSeatMode: config.sharedSeatMode && !buildConfig.allowForeground
        )

        // 8b. Create review infrastructure (ReviewOrchestrator + IntelligentCurator + SkillUsageStore)
        // NOTE (Story 40.2): buildReviewInfrastructure stays in build() — it produces usageStore,
        // which the tool profile needs, plus reviewOrchestrator/intelligentCurator that are
        // AgentBuildResult fields (not tools). buildToolProfile receives usageStore as a param.
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

        // 8. Build tools via the shared tool profile helper (Story 40.2 parity extraction).
        // buildReviewInfrastructure runs first so usageStore is available to the helper.
        let agentTools = buildToolProfile(
            noSkills: noSkills,
            noMemory: noMemory,
            dryrun: dryrun,
            skillRegistry: skillRegistry,
            memoryDir: memoryDir,
            config: config,
            usageStore: usageStore,
            skillsDir: skillsDir
        )

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

    /// Builds the tool pool for an ordinary chat/run agent (Story 40.2 parity extraction).
    ///
    /// This helper is a **parity-only** extraction: it is a line-for-line lift of the tool-assembly
    /// logic that previously lived inline in `build()` (former lines 140–189 + 206–212). It does
    /// NOT introduce any new tool behavior — registering `createAgentTool()`/`createTaskTool()`
    /// belongs to Story 40.3, and `buildSkillAgent()` tool-pool parity belongs to Story 40.4/40.5.
    ///
    /// **Pure function contract:** this helper does not resolve API keys, connect to MCP, spawn the
    /// Helper process, or call `buildReviewInfrastructure`. It receives already-constructed
    /// dependencies (`skillRegistry`, `config`, `usageStore`). The Storage/Memory tool constructors
    /// invoked below are lazy — their real side effects occur only inside each tool's `perform()`,
    /// so constructing them here does not violate the pure-function contract.
    ///
    /// **`usageStore` semantics:** `build()` runs `buildReviewInfrastructure(... dryrun: dryrun)`
    /// first and passes the resulting `usageStore` (which may be `nil`) into this helper. The
    /// `save_skill` tool is registered only when `usageStore != nil` (`if let usageStore`), matching
    /// the original inline behavior exactly. There is no separate `!dryrun` guard on `save_skill` —
    /// parity is preserved by the `usageStore` nil-ness being the gating condition.
    ///
    /// - Parameters:
    ///   - noSkills: When `true`, the Skill tool is omitted.
    ///   - noMemory: When `true`, the Memory tool is omitted.
    ///   - dryrun: When `true`, side-effect tools (Bash, Skill, Memory, Storage, save_skill) are excluded.
    ///   - skillRegistry: The already-constructed skill registry.
    ///   - memoryDir: Memory directory for the UniversalMemoryStore.
    ///   - config: AxionConfig (its `.storage` drives Storage tool config).
    ///   - usageStore: Optional SkillUsageStore produced by `buildReviewInfrastructure`; gates `save_skill`.
    ///   - skillsDir: Root skill directory passed to `save_skill`.
    /// - Returns: The assembled `[ToolProtocol]` (caller may read `.name` for assertions).
    static func buildToolProfile(
        noSkills: Bool,
        noMemory: Bool,
        dryrun: Bool,
        skillRegistry: SkillRegistry,
        memoryDir: String,
        config: AxionConfig,
        usageStore: SkillUsageStore?,
        skillsDir: String
    ) -> [ToolProtocol] {
        // Build tools: base SDK tools + Skill
        // Include core + specialist base tools explicitly so the streaming path
        // (agent.stream()) sends them in the API request. The non-streaming
        // query() path deduplicates via assembleToolPool.
        // Exclude ToolSearch and AskUser — GLM models get confused by ToolSearch
        // ("No deferred tools" kills the model's reasoning), and the system prompt
        // already lists all available tools.
        //
        // In dryrun mode, strip side-effect tools (Bash, Skill) so the agent
        // can only plan — never execute.
        var agentTools: [ToolProtocol] = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
            .filter { !excludedToolNames.contains($0.name) }
            .filter { !dryrun || !dryrunExcludedToolNames.contains($0.name) }
        if !noSkills, !dryrun {
            agentTools.append(createSkillTool(registry: skillRegistry))
        }

        // Story 40.3: Register the Agent and Task subagent launchers (Claude Code `Task`
        // compatibility). Both names map to the same SDK SubAgentSpawner; registering both lets
        // workflow skills emit either `Task(subagent_type:, prompt:)` or `Agent(...)` snippets.
        // Gated by `!dryrun` ONLY (NOT `!noSkills`) — `--no-skills` controls the Skill tool and
        // `/skill-name` routing, not generic subagent capability (Agent/Task are orthogonal to the
        // skill system). Dry-run excludes them as side-effect tools (they launch child agents).
        if !dryrun {
            agentTools.append(createAgentTool())
            agentTools.append(createTaskTool())
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

        // save_skill tool — Agent can persist reusable skills to disk.
        // Registered only when usageStore is non-nil (gated by `if let`). This preserves the
        // original inline behavior; there is no separate !dryrun guard on save_skill.
        if let usageStore {
            agentTools.append(createSaveSkillTool(
                skillRegistry: skillRegistry,
                usageStore: usageStore,
                skillsDir: skillsDir
            ))
        }

        return agentTools
    }

    /// Builds the tool pool for a direct skill-execution agent (Story 40.3).
    ///
    /// This is the skill-path parallel of ``buildToolProfile``: a **pure function** that assembles
    /// core-tier tools (excluding `ToolSearch`/`AskUser`) and appends the `Skill`, `Agent`, and
    /// `Task` tools so a pipeline skill (e.g. `bmad-story-pipeline`) running via
    /// `axion run /skill-name` or API skill execution can spawn child agents, and those children
    /// can invoke other `/skill-name` single-step skills via the `Skill` tool.
    ///
    /// **Pure function contract:** no API-key resolution, no MCP connection, no Helper process.
    /// The tool constructors (`createSkillTool`/`createAgentTool`/`createTaskTool`) are lazy —
    /// their side effects occur only inside each tool's `perform()`, so constructing them here
    /// does not violate the pure-function contract.
    ///
    /// **Scope (Stories 40.3 / 40.4):**
    /// - The `registry` passed in is the **full discovered registry** (Story 40.4): built-in skills
    ///   + filesystem discovery + the ensured current skill. `buildSkillAgent` builds it via
    ///   ``makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)`` and passes the SAME
    ///   instance to both this helper and `AgentOptions.skillRegistry`, so SDK
    ///   `DefaultSubAgentSpawner` inherits the full registry to child agents.
    /// - This helper does NOT add MCP / ToolSearch beyond the `.core` tier (that inheritance
    ///   policy is Story 40.5's scope). Web tools (`WebSearch`/`WebFetch`) are part of the
    ///   `.core` tier, so they are present here exactly as before 40.3.
    /// - `buildSkillAgent` has no `dryrun` parameter because skill execution is inherently
    ///   side-effect-bearing (writes files, calls the LLM); all three appended tools are always
    ///   registered.
    ///
    /// - Parameter registry: The already-constructed skill registry (the full discovered set).
    /// - Returns: The assembled `[ToolProtocol]` (caller may read `.name` for assertions).
    static func buildSkillToolProfile(registry: SkillRegistry) -> [ToolProtocol] {
        // Core tools only — exclude ToolSearch/AskUser to avoid confusing the LLM.
        var tools = getAllBaseTools(tier: .core).filter { !excludedToolNames.contains($0.name) }

        // Story 40.3: Direct skill path registers Skill + Agent + Task so pipeline skills can
        // spawn children and those children can invoke other /skill-name single-step skills.
        // Story 40.4: the registry is now the full discovered set (built by
        // `makeDiscoveredSkillRegistry`), so a pipeline skill's child agents can resolve sibling
        // skills like /bmad-create-story via the inherited registry.
        tools.append(createSkillTool(registry: registry))
        tools.append(createAgentTool())
        tools.append(createTaskTool())

        return tools
    }

    /// Builds the full discovered `SkillRegistry` used by both normal chat/run (`build()`) and
    /// direct skill execution (`buildSkillAgent()`). This is the registry the `Skill` tool and
    /// `AgentOptions.skillRegistry` must share so that (a) an orchestrator skill can invoke
    /// sub-skills, and (b) SDK `DefaultSubAgentSpawner` inherits the full registry to child agents.
    ///
    /// Mirrors the registry construction in `build()` (lines 96-102): built-in skills + filesystem
    /// discovery, then ensures the currently-executing `skill` is present (idempotent `register` —
    /// `SkillRegistry.register` replaces in place if the name already exists, so re-registering a
    /// discovered skill is safe and uses the exact passed instance).
    ///
    /// **Pure-ish contract:** no API-key resolution, no MCP, no Helper. `registerDiscoveredSkills`
    /// does filesystem discovery on `discoveryDirectories` (read-only scan). Tests inject a temp
    /// fixture dir for determinism; production passes `ConfigManager.skillDiscoveryDirectories`.
    ///
    /// - Parameters:
    ///   - skill: The skill currently being executed; guaranteed present in the returned registry.
    ///   - discoveryDirectories: Directories scanned by `SkillLoader`. Defaults to the configured set.
    /// - Returns: A `SkillRegistry` containing built-ins + discovered skills + the ensured skill.
    static func makeDiscoveredSkillRegistry(
        ensuring skill: OpenAgentSDK.Skill,
        discoveryDirectories: [String] = ConfigManager.skillDiscoveryDirectories
    ) -> SkillRegistry {
        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        _ = registry.registerDiscoveredSkills(from: discoveryDirectories)
        registry.register(skill) // ensure the currently-executing skill is present (idempotent)
        return registry
    }

    /// Builds a minimal agent for skill execution via SDK's `executeSkillStream()`.
    ///
    /// Unlike `build()`, this creates a lightweight agent:
    /// - No MCP servers (no desktop automation tools)
    /// - Skill/Agent/Task tools registered (Story 40.3) so pipeline skills can spawn children
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

        // Story 40.4: use the full discovered registry (built-in + filesystem discovery + ensured
        // current skill), not a single-skill registry. This same registry feeds both
        // `buildSkillToolProfile(registry:)` and `agentOptions.skillRegistry`, so SDK
        // `DefaultSubAgentSpawner` inherits the full registry to child agents (CAP-3) — letting a
        // pipeline skill's Task children resolve sub-skills like /bmad-create-story.
        let registry = AgentBuilder.makeDiscoveredSkillRegistry(ensuring: skill)

        // Story 40.3: tools assembled via the testable pure helper (Skill + Agent + Task added).
        let tools = buildSkillToolProfile(registry: registry)

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
