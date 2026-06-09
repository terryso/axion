import OpenAgentSDK

import AxionCore

extension AgentBuilder {

    // MARK: - Curator Infrastructure

    /// Result of creating curator infrastructure (IntelligentCurator + its dependencies).
    /// Used by AgentBuilder.build(), GatewayCommand, and CuratorCommand to avoid
    /// duplicating the 7-step curator creation pattern.
    struct CuratorDeps: Sendable {
        let intelligentCurator: IntelligentCurator
        let skillCurator: SkillCurator
        let usageStore: SkillUsageStore
        let curatorStore: SkillCuratorStore
        let factStore: FactStore
        let skillEvolver: LLMSkillEvolver
    }

    /// Creates the full IntelligentCurator with all dependencies.
    /// Consolidates the 7-step creation pattern (SkillUsageStore → SkillCuratorStore →
    /// SkillCuratorConfig → SkillCurator → AnthropicClient → LLMSkillEvolver → IntelligentCurator)
    /// previously duplicated across AgentBuilder, GatewayCommand, and CuratorCommand.
    ///
    /// - Parameters:
    ///   - config: AxionConfig for curator/evolver settings
    ///   - apiKey: Anthropic API key
    ///   - memoryDir: Directory for fact store
    ///   - skillsDir: Directory for skill stores
    ///   - skillRegistry: Registry of available skills
    ///   - intervalHours: Override for curator interval (nil = use config)
    ///   - dryRun: Override for dry-run mode (nil = use config)
    static func buildCuratorDeps(
        config: AxionConfig,
        apiKey: String,
        memoryDir: String,
        skillsDir: String,
        skillRegistry: SkillRegistry,
        intervalHours: Double? = nil,
        dryRun: Bool? = nil
    ) -> CuratorDeps {
        let usageStore = SkillUsageStore(skillsDir: skillsDir)
        let curatorStore = SkillCuratorStore(skillsDir: skillsDir)
        let factStore = FactStore(memoryDir: memoryDir)

        let curatorConfig = SkillCuratorConfig(
            intervalHours: intervalHours ?? config.curatorIntervalHours ?? 168.0,
            staleAfterDays: config.curatorStaleAfterDays ?? 30,
            archiveAfterDays: config.curatorArchiveAfterDays ?? 90,
            dryRun: dryRun ?? config.curatorDryRun ?? false,
            enabled: config.curatorEnabled ?? true
        )
        let skillCurator = SkillCurator(
            usageStore: usageStore,
            curatorStore: curatorStore,
            config: curatorConfig
        )

        let evolverClient = AnthropicClient(apiKey: apiKey, baseURL: config.baseURL)
        let skillEvolver = LLMSkillEvolver(
            client: evolverClient,
            evolutionModel: config.reviewModel ?? AxionConfig.defaultReviewModel
        )
        let intelligentCurator = IntelligentCurator(
            skillCurator: skillCurator,
            factStore: factStore,
            skillRegistry: skillRegistry,
            skillEvolver: skillEvolver,
            usageStore: usageStore,
            curatorStore: curatorStore,
            skillsDir: skillsDir
        )

        return CuratorDeps(
            intelligentCurator: intelligentCurator,
            skillCurator: skillCurator,
            usageStore: usageStore,
            curatorStore: curatorStore,
            factStore: factStore,
            skillEvolver: skillEvolver
        )
    }

    // MARK: - Review & Curator Infrastructure

    /// Result of creating review and curator infrastructure.
    struct ReviewInfrastructure: Sendable {
        let reviewOrchestrator: ReviewOrchestrator?
        let intelligentCurator: IntelligentCurator?
        let usageStore: SkillUsageStore?
    }

    /// Creates ReviewOrchestrator + IntelligentCurator when memory is enabled and not in dryrun mode.
    ///
    /// Returns `ReviewInfrastructure(reviewOrchestrator: nil, intelligentCurator: nil, usageStore: nil)`
    /// when memory is disabled or dryrun mode is active.
    static func buildReviewInfrastructure(
        config: AxionConfig,
        apiKey: String,
        memoryDir: String,
        skillsDir: String,
        skillRegistry: SkillRegistry,
        noMemory: Bool,
        dryrun: Bool
    ) -> ReviewInfrastructure {
        guard !noMemory, !dryrun else {
            return ReviewInfrastructure(
                reviewOrchestrator: nil,
                intelligentCurator: nil,
                usageStore: nil
            )
        }

        let usageStore = SkillUsageStore(skillsDir: skillsDir)

        let scheduleConfig = ReviewScheduleConfig(
            memoryReviewInterval: config.reviewMemoryInterval ?? ReviewScheduleConfig().memoryReviewInterval,
            skillReviewInterval: config.reviewSkillInterval ?? ReviewScheduleConfig().skillReviewInterval,
            minMessagesForReview: config.reviewMinMessages ?? ReviewScheduleConfig().minMessagesForReview,
            reviewModel: config.reviewModel
        )
        let reviewFactStore = FactStore(memoryDir: memoryDir)
        let evolverClient = AnthropicClient(
            apiKey: apiKey,
            baseURL: config.baseURL
        )
        let skillEvolver = LLMSkillEvolver(
            client: evolverClient,
            evolutionModel: config.reviewModel ?? AxionConfig.defaultReviewModel
        )
        let universalMemoryStore = UniversalMemoryStore(memoryDir: memoryDir)
        let reviewSaveMemoryTool = ReviewSaveUniversalMemoryTool(store: universalMemoryStore)
        let reviewOrchestrator = ReviewOrchestrator(
            scheduleConfig: scheduleConfig,
            factStore: reviewFactStore,
            skillRegistry: skillRegistry,
            skillEvolver: skillEvolver,
            usageStore: usageStore,
            skillsDir: skillsDir,
            additionalReviewTools: [reviewSaveMemoryTool]
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
            usageStore: usageStore,
            curatorStore: curatorStore,
            config: curatorConfig
        )
        let intelligentCurator = IntelligentCurator(
            skillCurator: skillCurator,
            factStore: reviewFactStore,
            skillRegistry: skillRegistry,
            skillEvolver: skillEvolver,
            usageStore: usageStore,
            curatorStore: curatorStore,
            skillsDir: skillsDir
        )

        return ReviewInfrastructure(
            reviewOrchestrator: reviewOrchestrator,
            intelligentCurator: intelligentCurator,
            usageStore: usageStore
        )
    }
}
