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

/// Structured tool-availability diagnostics for a skill execution path (Story 40.6).
///
/// Mirrors the diagnostics the SDK computes at runtime (`ToolFilterDiagnostics` /
/// `ToolDeclarationDiagnostics`) but that `DefaultSubAgentSpawner` currently discards
/// at the spawner boundary (SDK `DefaultSubAgentSpawner.swift:151-156`). This Axion-side
/// recomputation runs at build/route time using SDK pure helpers, making the signal
/// observable (CAP-8 / architecture §3 lines 104-105: unknown allowed-tools must not
/// silently become unrestricted).
struct ToolAvailabilityDiagnostics: Sendable, Equatable {
    /// Allowed-tool declarations that matched NO available tool — e.g. an MCP tool that
    /// isn't connected (`mcp__github__list_prs`) or a typo'd name. These affect availability.
    let unmatchedDeclarations: [OpenAgentSDK.ToolDeclaration]
    /// Explicitly-declared-but-unresolvable names (status == `.unknown`). The SDK parser
    /// still records these (non-nil) so the skill is never silently unrestricted.
    let unsupportedDeclarations: [OpenAgentSDK.ToolDeclaration]
    /// Declarations carrying a `Bash(git diff:*)`-style pattern — parsed but NOT enforced
    /// (fine-grained Bash pattern enforcement is a deferred epic item). Surfaced so the user
    /// knows the pattern was accepted but not honored.
    let patternDeclarations: [OpenAgentSDK.ToolDeclaration]
    /// Declarations requesting a tool the current Axion config policy disables — e.g.
    /// `ToolSearch` while `AxionConfig.enableToolSearch == false` (Story 40.5 config ceiling).
    let configDisabledDeclarations: [OpenAgentSDK.ToolDeclaration]

    init(
        unmatchedDeclarations: [OpenAgentSDK.ToolDeclaration] = [],
        unsupportedDeclarations: [OpenAgentSDK.ToolDeclaration] = [],
        patternDeclarations: [OpenAgentSDK.ToolDeclaration] = [],
        configDisabledDeclarations: [OpenAgentSDK.ToolDeclaration] = []
    ) {
        self.unmatchedDeclarations = unmatchedDeclarations
        self.unsupportedDeclarations = unsupportedDeclarations
        self.patternDeclarations = patternDeclarations
        self.configDisabledDeclarations = configDisabledDeclarations
    }

    /// `true` when no diagnostics of any kind were produced.
    var isEmpty: Bool {
        unmatchedDeclarations.isEmpty && unsupportedDeclarations.isEmpty
            && patternDeclarations.isEmpty && configDisabledDeclarations.isEmpty
    }

    /// `true` when any diagnostic affects actual tool availability (unmatched / unknown /
    /// config-disabled). Pattern-only diagnostics are informational and do not by themselves
    /// remove a tool.
    var affectsAvailability: Bool {
        !unmatchedDeclarations.isEmpty || !unsupportedDeclarations.isEmpty
            || !configDisabledDeclarations.isEmpty
    }
}

/// Single source of truth for constructing an Agent used by both CLI (RunCommand)
/// and API (ApiRunner). Handles API key resolution, helper path, memory store,
/// system prompt, MCP servers, safety hooks, tools, and AgentOptions — but NOT
/// any caller-specific concerns like TakeoverIO, SSE broadcasting, or cost tracking.
enum AgentBuilder {

    // MARK: - Shared Helpers

    /// The default ToolSearch-off tool-name exclusion set (Story 40.5).
    ///
    /// `AskUser` is always excluded (the system prompt handles user-confirmation prompts).
    /// `ToolSearch` is excluded here because, historically, it confuses GLM-class models'
    /// reasoning. As of Story 40.5 this constant is the **ToolSearch-off default** set — the
    /// live exclusion at build time is computed by ``effectiveExcludedToolNames(allowingToolSearch:)``
    /// driven by `AxionConfig.enableToolSearch`, so providers/users where ToolSearch degrades
    /// reasoning keep it off by default while others can opt in. The two are related by the
    /// identity `effectiveExcludedToolNames(allowingToolSearch: false) == excludedToolNames`.
    static let excludedToolNames: Set<String> = ["ToolSearch", "AskUser"]

    /// Returns the tool-name exclusion set honoring the ToolSearch config policy (Story 40.5).
    ///
    /// `AskUser` is always excluded (the system prompt handles user-confirmation prompts). `ToolSearch`
    /// is excluded only when the ToolSearch policy is OFF — previously this was a hard-coded global
    /// exclusion (``excludedToolNames``); it is now driven by `AxionConfig.enableToolSearch` so
    /// providers/users where ToolSearch degrades reasoning (e.g. GLM) keep it off by default, while
    /// others can opt in. Both ``buildToolProfile`` and ``buildSkillToolProfile`` call this helper so the
    /// two paths share a single source of truth (CAP-8).
    ///
    /// ``excludedToolNames`` (the no-arg constant) is preserved as the legacy "ToolSearch-off default"
    /// set — tests that iterate it (Story 40.2/40.3) keep passing under the default config.
    static func effectiveExcludedToolNames(allowingToolSearch: Bool) -> Set<String> {
        allowingToolSearch ? ["AskUser"] : excludedToolNames
    }

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
        // Exclude AskUser always (system prompt handles user-confirmation prompts), and
        // ToolSearch unless the config policy opts in — Story 40.5 makes the ToolSearch
        // exclusion config-driven via `AxionConfig.enableToolSearch` (default off keeps GLM
        // stable) instead of a hard-coded global exclusion.
        //
        // In dryrun mode, strip side-effect tools (Bash, Skill) so the agent
        // can only plan — never execute.
        let excluded = effectiveExcludedToolNames(allowingToolSearch: config.toolSearchEnabled)
        var agentTools: [ToolProtocol] = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
            .filter { !excluded.contains($0.name) }
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
    /// core-tier tools and appends the `Skill`, `Agent`, and `Task` tools so a pipeline skill
    /// (e.g. `bmad-story-pipeline`) running via `axion run /skill-name` or API skill execution
    /// can spawn child agents, and those children can invoke other `/skill-name` single-step
    /// skills via the `Skill` tool.
    ///
    /// **Pure function contract:** no API-key resolution, no MCP connection, no Helper process.
    /// The tool constructors (`createSkillTool`/`createAgentTool`/`createTaskTool`) are lazy —
    /// their side effects occur only inside each tool's `perform()`, so constructing them here
    /// does not violate the pure-function contract.
    ///
    /// **Scope (Stories 40.3 / 40.4 / 40.5):**
    /// - The `registry` passed in is the **full discovered registry** (Story 40.4): built-in skills
    ///   + filesystem discovery + the ensured current skill. `buildSkillAgent` builds it via
    ///   ``makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)`` and passes the SAME
    ///   instance to both this helper and `AgentOptions.skillRegistry`, so SDK
    ///   `DefaultSubAgentSpawner` inherits the full registry to child agents.
    /// - `AskUser` is always excluded (system-prompt-handled). `ToolSearch` is excluded unless
    ///   `enableToolSearch` is `true` (Story 40.5) — both paths share the single
    ///   ``effectiveExcludedToolNames(allowingToolSearch:)`` source of truth. `buildSkillAgent`
    ///   passes `config.toolSearchEnabled` so the skill path inherits the same ToolSearch policy as
    ///   normal chat. Web tools (`WebSearch`/`WebFetch`) are part of the `.core` tier and are
    ///   always present regardless of the ToolSearch policy.
    /// - MCP inheritance is handled in ``buildSkillAgent`` via ``resolveSkillMcpServers(from:)``
    ///   (Story 40.5) — this tool-pool helper stays scoped to base + Skill/Agent/Task tools.
    /// - `buildSkillAgent` has no `dryrun` parameter because skill execution is inherently
    ///   side-effect-bearing (writes files, calls the LLM); all three appended tools are always
    ///   registered.
    ///
    /// - Parameters:
    ///   - registry: The already-constructed skill registry (the full discovered set).
    ///   - enableToolSearch: Whether to keep `ToolSearch` in the pool (Story 40.5). Defaults to
    ///     `false` so existing `buildSkillToolProfile(registry:)` callers keep the ToolSearch-off
    ///     behavior; `buildSkillAgent` passes `config.toolSearchEnabled`.
    /// - Returns: The assembled `[ToolProtocol]` (caller may read `.name` for assertions).
    static func buildSkillToolProfile(registry: SkillRegistry, enableToolSearch: Bool = false) -> [ToolProtocol] {
        // Core tools only — exclude AskUser always, ToolSearch unless the config policy opts in
        // (Story 40.5: single source of truth via effectiveExcludedToolNames).
        let excluded = effectiveExcludedToolNames(allowingToolSearch: enableToolSearch)
        var tools = getAllBaseTools(tier: .core).filter { !excluded.contains($0.name) }

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

    /// Resolves the MCP server config for the direct skill-execution path (Story 40.5).
    ///
    /// Mirrors `build()`'s MCP step so a skill agent inherits the SAME configured MCP servers as a
    /// normal chat/run agent (CAP-8 / architecture §6) — previously `buildSkillAgent` hard-coded
    /// `mcpServers: nil`, silently dropping MCP tools that a Claude Code skill may require. Falls
    /// back to "/usr/bin/true" when AxionHelper isn't installed: skill execution does NOT throw on
    /// a missing helper (unlike `build()`), so the MCP config is always buildable; real connection
    /// (and any failure) happens lazily at agent run, same as the normal path.
    ///
    /// **Pure-ish contract (mirrors ``makeDiscoveredSkillRegistry``):** no API-key resolution, no MCP
    /// connection, no Helper process spawn. `helperPath` defaults to a real `HelperPathResolver`
    /// lookup (read-only FS check); tests inject a stub path for determinism. `MCPConfigResolver.resolveMCPServers`
    /// only builds the config dict — it does not connect.
    ///
    /// - Parameters:
    ///   - config: AxionConfig (its `.mcpServers` carries the user-configured MCP servers).
    ///   - helperPath: Optional resolved AxionHelper path. Defaults to `HelperPathResolver.resolveHelperPath()`;
    ///     falls back to "/usr/bin/true" when nil so the helper baseline key is always buildable.
    /// - Returns: A `[String: McpServerConfig]` containing the `axion-helper` baseline plus any
    ///   user-configured servers (same output shape as `build()`'s MCP step).
    static func resolveSkillMcpServers(
        from config: AxionConfig,
        helperPath: String? = HelperPathResolver.resolveHelperPath()
    ) -> [String: McpServerConfig] {
        let resolvedHelperPath = helperPath ?? "/usr/bin/true"
        return MCPConfigResolver.resolveMCPServers(
            helperPath: resolvedHelperPath,
            includePlaywright: false,
            userServers: config.mcpServers
        )
    }

    /// Computes tool-availability diagnostics for a skill's `allowed-tools` against an assembled
    /// tool pool + Axion config policy (Story 40.6 AC1–AC3).
    ///
    /// Reuses SDK pure helpers (`OpenAgentSDK.filterToolsByDeclarations`, `skill.toolDeclarations`,
    /// `skill.toolDeclarationDiagnostics`) — no SDK edits, no live model, no MCP connection, no API
    /// key resolution. The SDK computes equivalent diagnostics at runtime, but
    /// `DefaultSubAgentSpawner` discards the `ToolFilterDiagnostics` it returns (SDK
    /// `DefaultSubAgentSpawner.swift:151-156`); this helper mirrors that logic at Axion build/route
    /// time so the signal is observable (CAP-8).
    ///
    /// `enableToolSearch` is the SAME `AxionConfig.toolSearchEnabled` value that governs tool-pool
    /// assembly (Story 40.5), so a skill requesting ToolSearch under a disabled policy surfaces as
    /// `configDisabledDeclarations` rather than being silently dropped.
    ///
    /// - Parameters:
    ///   - skill: The skill whose `allowed-tools` (via `toolDeclarations` / `toolDeclarationDiagnostics`)
    ///     is being diagnosed. A skill with `toolDeclarations == nil` (no `allowed-tools` frontmatter)
    ///     yields empty diagnostics.
    ///   - availableToolNames: Lowercased names of the assembled tool pool (e.g. from
    ///     `buildSkillToolProfile(...).map { $0.name.lowercased() }`).
    ///   - enableToolSearch: Whether Axion config currently enables ToolSearch.
    /// - Returns: A `ToolAvailabilityDiagnostics` describing unmatched / unsupported / pattern /
    ///   config-disabled declarations.
    static func diagnoseToolAvailability(
        skill: OpenAgentSDK.Skill,
        availableToolNames: [String],
        enableToolSearch: Bool
    ) -> ToolAvailabilityDiagnostics {
        guard let declarations = skill.toolDeclarations, !declarations.isEmpty else {
            return ToolAvailabilityDiagnostics()  // no allowed-tools → no diagnostics
        }
        let availableLower = Set(availableToolNames.map { $0.lowercased() })

        // 1. unsupported (.unknown) — from parse-time diagnostics (SDK Story 29.4), with a filter
        //    fallback for programmatically-constructed Skills whose `toolDeclarationDiagnostics`
        //    is nil.
        let unsupported = skill.toolDeclarationDiagnostics?.unsupportedDeclarations
            ?? declarations.filter { $0.status == .unknown }

        // 2. config-disabled — currently only ToolSearch is config-gated (Story 40.5). A declaration
        //    requesting a tool that config policy disables (here: ToolSearch when enableToolSearch
        //    is false) is separated from generic `unmatched` so the user sees the *policy* reason.
        //    NOTE: `ToolRestriction.toolSearch.rawValue` is the camelCase enum name ("toolSearch");
        //    it must be lowercased to match `ToolDeclaration.normalizedName` ("toolsearch"), exactly
        //    as the SDK normalizes inside `restrictionByLowercasedName`.
        let configDisabled: [OpenAgentSDK.ToolDeclaration]
        if enableToolSearch {
            configDisabled = []
        } else {
            let toolSearchName = OpenAgentSDK.ToolRestriction.toolSearch.rawValue.lowercased()
            configDisabled = declarations.filter { $0.normalizedName == toolSearchName }
        }

        // 3. unmatched — a declaration whose normalizedName is in NEITHER the available pool NOR a
        //    more-specific category (unsupported / config-disabled). Declarations already surfaced
        //    under those categories are excluded so the same name is never reported twice: e.g.
        //    ToolSearch under a disabled config policy is reported only as config-disabled (the
        //    precise reason), not also as "未匹配". Mirrors SDK `filterToolsByDeclarations` →
        //    `ToolFilterDiagnostics.unmatchedDeclarations` minus the Axion-specific config-disabled
        //    refinement, keeping the four categories mutually exclusive.
        let specificallyCategorized = Set(
            unsupported.map { $0.normalizedName }
                + configDisabled.map { $0.normalizedName }
        )
        let unmatched = declarations.filter {
            !availableLower.contains($0.normalizedName)
                && !specificallyCategorized.contains($0.normalizedName)
        }

        // 4. pattern (parsed-not-enforced) — from parse-time diagnostics, with the same fallback.
        //    Informational and orthogonal to availability: a patterned declaration may also appear
        //    in `unmatched` if its base tool is absent from the pool, which is correct (two distinct
        //    facts — pattern accepted-but-not-enforced AND tool not available).
        let patterns = skill.toolDeclarationDiagnostics?.patternDeclarations
            ?? declarations.filter { $0.pattern != nil }

        return ToolAvailabilityDiagnostics(
            unmatchedDeclarations: unmatched,
            unsupportedDeclarations: unsupported,
            patternDeclarations: patterns,
            configDisabledDeclarations: configDisabled
        )
    }

    /// Emits `ToolAvailabilityDiagnostics` to stderr as user-visible warnings (Story 40.6).
    ///
    /// Shared emit point for the two skill-execution paths so the warning format stays identical:
    /// Path B (`buildSkillAgent`, non-interactive `axion run /skill-name` / API) and Path A
    /// (`ChatCommand` interactive `/skill-name`). Diagnostics that affect availability always emit
    /// (not gated by `verbose`); pattern-only diagnostics emit at informational level (parsed but
    /// not enforced). The four availability categories are mutually exclusive (see
    /// `diagnoseToolAvailability`), so each declaration is reported exactly once with its most
    /// specific reason — no dedup is needed here.
    static func emitToolAvailabilityDiagnostics(
        _ diagnostics: ToolAvailabilityDiagnostics,
        skillName: String
    ) {
        if diagnostics.affectsAvailability {
            fputs("[axion] ⚠️ skill \"\(skillName)\" 声明的部分工具当前不可用:\n", stderr)
            for d in diagnostics.unmatchedDeclarations {
                fputs("[axion]   - 未匹配: \(d.rawName)\n", stderr)
            }
            for d in diagnostics.unsupportedDeclarations {
                fputs("[axion]   - 未知工具名: \(d.rawName)\n", stderr)
            }
            for d in diagnostics.configDisabledDeclarations {
                fputs("[axion]   - 被 config 策略禁用: \(d.rawName)\n", stderr)
            }
        }
        if !diagnostics.patternDeclarations.isEmpty {
            fputs("[axion] ℹ️ skill \"\(skillName)\" 声明了 pattern 限制（已解析，暂不强制）:\n", stderr)
            for d in diagnostics.patternDeclarations {
                fputs("[axion]   - \(d.rawName)\n", stderr)
            }
        }
    }

    /// The effective tool pool after applying a skill's `allowed-tools` to the assembled pool
    /// (Story 40.6 AC5 — filtering order: allowed-tools narrow FIRST, then session/permission
    /// policy gates at runtime).
    ///
    /// Thin wrapper over SDK `filterToolsByDeclarations(available:allowed:disallowed:)` that
    /// surfaces the build-time intersection for testability. Returns all `available` when the
    /// skill declares no restrictions (`toolDeclarations` nil/empty AND `toolRestrictions`
    /// nil/empty). The runtime `canUseTool` gate (inherited by child agents, AC4) further
    /// restricts on top of this — orthogonal, not duplicated here.
    static func effectiveSkillToolPool(
        skill: OpenAgentSDK.Skill,
        available: [OpenAgentSDK.ToolProtocol]
    ) -> [OpenAgentSDK.ToolProtocol] {
        let declarations = skill.toolDeclarations?.isEmpty == false ? skill.toolDeclarations : nil
        // If no lossless declarations but legacy toolRestrictions exist, normalize them via
        // ToolDeclaration.fromToolNames so both forms share one filter path (SDK Story 29.5 unification).
        let allowed = declarations
            ?? skill.toolRestrictions.map { OpenAgentSDK.ToolDeclaration.fromToolNames($0.map(\.rawValue)) }
        guard let allowed, !allowed.isEmpty else { return available }
        let (filtered, _) = OpenAgentSDK.filterToolsByDeclarations(
            available: available, allowed: allowed, disallowed: nil
        )
        return filtered
    }

    /// Builds a minimal agent for skill execution via SDK's `executeSkillStream()`.
    ///
    /// Unlike `build()`, this creates a lightweight agent:
    /// - MCP servers inherited from config (Story 40.5) — was hard-coded `nil`; now resolves via
    ///   ``resolveSkillMcpServers(from:)`` so a skill declaring MCP tools receives them. Connection
    ///   is lazy (happens at agent run, not here), so this stays side-effect-free.
    /// - Skill/Agent/Task tools registered (Story 40.3) so pipeline skills can spawn children
    /// - No memory injection
    /// - Core tools only; AskUser always excluded, ToolSearch driven by `config.enableToolSearch`
    ///   (Story 40.5)
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
        // Story 40.5: pass `config.toolSearchEnabled` so the skill path shares the same ToolSearch
        // policy as normal chat (single source of truth via effectiveExcludedToolNames).
        let tools = buildSkillToolProfile(registry: registry, enableToolSearch: config.toolSearchEnabled)

        // Story 40.6: surface tool-availability diagnostics so a skill requesting an unavailable tool
        // (unknown name, unconnected MCP, config-disabled ToolSearch) is visible instead of silently
        // lost. Mirrors the SDK diagnostics that DefaultSubAgentSpawner discards at its boundary.
        // `diagnoseToolAvailability` is a pure helper (no side effects); the shared emit helper is the
        // observable exit (Path B). Diagnostics that affect availability always emit (not gated by
        // `verbose`); pattern-only diagnostics emit at informational level (parsed but not enforced).
        let diagnostics = diagnoseToolAvailability(
            skill: skill,
            availableToolNames: tools.map { $0.name.lowercased() },
            enableToolSearch: config.toolSearchEnabled
        )
        emitToolAvailabilityDiagnostics(diagnostics, skillName: skill.name)

        let effectiveMaxSteps = maxSteps ?? config.maxSteps
        let effectiveModel = skill.modelOverride ?? config.model

        let cwd = FileManager.default.currentDirectoryPath
        // Story 40.7: the skill path always registers Skill + Agent + Task
        // (`buildSkillToolProfile`:496-498, no dryrun/noSkills gating), so the Claude Code
        // skill/subagent guidance is always injected here. This is the PARENT agent prompt for a
        // pipeline skill (e.g. bmad-story-pipeline) running via `axion run` / API — it tells the
        // model to call the `Task` tool for `Task(...)` snippets (CAP-1/CAP-2) and to run `/<skill>`
        // via the `Skill` tool (CAP-3). The existing `[结果]` summary contract is preserved — the
        // guidance is appended after, never rewritten or pre-empted.
        let baseSkillPrompt = "All filesystem and terminal operations must use \(cwd) as the working directory. Do NOT invent or guess paths — always resolve relative paths against \(cwd).\n\n# Task Summary — MANDATORY\n\nEVERY response MUST end with exactly one summary line in this format:\n[结果] <one-line summary, max 100 chars>\nThis is NOT optional. Even if the task failed, you MUST include this line."
        let skillSystemPrompt = baseSkillPrompt
            + (slashSkillAndTaskGuidance(noSkills: false, dryrun: false).map { "\n\n\($0)" } ?? "")
        var agentOptions = AgentOptions(
            apiKey: apiKey,
            model: effectiveModel,
            baseURL: config.baseURL,
            systemPrompt: skillSystemPrompt,
            maxTurns: effectiveMaxSteps,
            maxTokens: 16384,
            permissionMode: .bypassPermissions,
            tools: tools,
            // Story 40.5: inherit configured MCP servers (was nil) so skill agents that need MCP tools
            // (e.g. a skill declaring mcp__github__list_prs) get them. Mirrors build()'s MCP step via the
            // testable resolveSkillMcpServers helper. Connection is lazy (happens at agent run, not here).
            mcpServers: resolveSkillMcpServers(from: config),
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
