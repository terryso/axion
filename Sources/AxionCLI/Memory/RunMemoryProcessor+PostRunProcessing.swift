import Foundation
import OpenAgentSDK


extension RunMemoryProcessor {

    // MARK: - Knowledge Extraction

    /// Save extracted knowledge entries to the memory store and return the set of processed domains.
    static func saveKnowledgeEntries(
        _ entries: [KnowledgeEntry],
        to memoryStore: FileBasedMemoryStore
    ) async throws -> Set<String> {
        var processedDomains: Set<String> = []
        for entry in entries {
            let domain = entry.tags.first(where: { $0.hasPrefix("app:") })?
                .dropFirst("app:".count).description ?? "unknown"
            try await memoryStore.save(domain: domain, knowledge: entry)
            processedDomains.insert(domain)
        }
        return processedDomains
    }

    // MARK: - Fact Extraction & Merge

    /// Extract facts from tool pairs, merge with existing facts via lifecycle service, and save.
    static func extractAndMergeFacts(
        extractor: AppMemoryExtractor,
        pairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)],
        task: String,
        runId: String,
        memoryDir: String
    ) async {
        let factStore = AxionFactStore(memoryDir: memoryDir)
        let lifecycleService = SDKMemoryLifecycleService()
        let facts = extractor.extractFacts(
            from: pairs,
            task: task,
            runId: runId
        )
        for fact in facts {
            do {
                try await AppMemoryFact.mergeAndPersist(
                    fact: fact,
                    into: factStore,
                    lifecycleService: lifecycleService
                )
            } catch {
                fputs("[axion] warning: memory fact save failed for \(fact.domain): \(error.localizedDescription)\n", stderr)
            }
        }
    }

    // MARK: - Profile Analysis & Familiarity

    /// Analyze domain profiles and track familiarity for all processed domains.
    static func analyzeProfilesAndFamiliarity(
        processedDomains: Set<String>,
        memoryStore: FileBasedMemoryStore
    ) async {
        for domain in processedDomains {
            do {
                let history = try await memoryStore.query(domain: domain, filter: nil)
                let analyzer = AppProfileAnalyzer()
                let profile = analyzer.analyze(domain: domain, history: history)

                if profile.totalRuns > 0 {
                    let profileContent = RunOrchestrator.buildProfileContent(profile: profile)
                    let profileEntry = KnowledgeEntry(
                        id: UUID().uuidString,
                        content: profileContent,
                        tags: ["app:\(domain)", "profile"],
                        createdAt: Date(),
                        sourceRunId: nil
                    )
                    try await memoryStore.save(domain: domain, knowledge: profileEntry)
                }

                // Familiarity tracking — inline from merged FamiliarityTracker
                if profile.isFamiliar {
                    let existingFamiliar = try await memoryStore.query(
                        domain: domain,
                        filter: KnowledgeQueryFilter(tags: ["familiar"])
                    )
                    if existingFamiliar.isEmpty {
                        let familiarEntry = KnowledgeEntry(
                            id: UUID().uuidString,
                            content: "App \(domain) 已熟悉（累计 \(profile.successfulRuns) 次成功操作）",
                            tags: ["app:\(domain)", "familiar"],
                            createdAt: Date(),
                            sourceRunId: nil
                        )
                        try await memoryStore.save(domain: domain, knowledge: familiarEntry)
                    }
                }
            } catch {
                fputs("[axion] warning: profile analysis failed for \(domain): \(error.localizedDescription)\n", stderr)
            }
        }
    }

    // MARK: - Takeover Learning

    /// Record takeover learning if a takeover event occurred and the run completed.
    static func processTakeoverLearning(
        event: TakeoverEventContext,
        runId: String,
        task: String,
        memoryDir: String,
        runSucceeded: Bool,
        runCompleted: Bool,
        pairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)]
    ) async {
        guard runCompleted else { return }

        let takeoverFactStore = AxionFactStore(memoryDir: memoryDir)
        let takeoverService = TakeoverLearningService(
            factStore: takeoverFactStore,
            lifecycleService: SDKMemoryLifecycleService()
        )
        let domain = inferDomain(from: pairs)
        let outcome: TakeoverOutcome = runSucceeded ? .success : .failed
        let reasonType = InterventionReason.classifyReason(event.reason)

        let _ = TakeoverMarker.create(
            runId: runId,
            outcome: outcome,
            issue: event.issue,
            summary: event.summary,
            reasonType: reasonType,
            feedback: event.feedback,
            duration: event.duration,
            bundleId: domain,
            task: task
        )

        await takeoverService.recordTakeoverLearning(
            bundleId: domain,
            task: task,
            issue: event.issue,
            summary: event.summary,
            outcome: outcome,
            reasonType: reasonType.rawValue,
            feedback: event.feedback
        )
    }
}
