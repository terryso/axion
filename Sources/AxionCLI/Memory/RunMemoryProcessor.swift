import Foundation
import OpenAgentSDK

import AxionCore

/// Encapsulates all memory-related operations for a single agent run.
///
/// Handles pre-run cleanup (expired entries, fact demotion) and post-run
/// processing (memory extraction, fact extraction/merge, profile analysis,
/// familiarity tracking, takeover learning).
struct RunMemoryProcessor {

    // MARK: - Pre-run

    /// Clean up expired memory entries and demote retired facts before a run starts.
    static func preRunCleanup(memoryStore: FileBasedMemoryStore, memoryDir: String) async {
        do {
            let cleanupService = MemoryCleanupService()
            _ = try await cleanupService.cleanupExpired(in: memoryStore)
        } catch {
            fputs("[axion] warning: memory cleanup failed: \(error.localizedDescription)\n", stderr)
        }

        do {
            let factStore = MemoryFactStore(memoryDir: memoryDir)
            let lifecycleService = MemoryLifecycleService()
            let cutoffDate = Date().addingTimeInterval(-MemoryLifecycleService.demotionInterval)
            let domains = try await factStore.listDomains()
            for domain in domains {
                let facts = try await factStore.query(domain: domain)
                let demoted = lifecycleService.demoteRetired(facts: facts, lastVerifiedBefore: cutoffDate)
                let changed = zip(facts, demoted).filter { $0.status != $1.status }
                for (_, demotedFact) in changed {
                    try await factStore.save(domain: domain, fact: demotedFact)
                }
            }
        } catch {
            fputs("[axion] warning: memory fact lifecycle demotion failed: \(error.localizedDescription)\n", stderr)
        }
    }

    // MARK: - Post-run

    /// Context for a completed takeover event.
    struct TakeoverEventContext: Sendable {
        let issue: String
        let summary: String
        let feedback: String?
        let reason: String
        let duration: TimeInterval?
    }

    /// Process all memory operations after a run completes.
    ///
    /// Includes: knowledge extraction, fact extraction/merge, profile analysis,
    /// familiarity tracking, and takeover learning. All operations are non-fatal.
    static func processRunResult(
        toolPairs: [SDKMessage.ToolExecutionPair],
        task: String,
        runId: String,
        memoryStore: FileBasedMemoryStore,
        memoryDir: String,
        noMemory: Bool,
        externallyModified: Bool,
        takeoverEvent: TakeoverEventContext?,
        runSucceeded: Bool,
        runCompleted: Bool,
        tracer: TraceRecorder?
    ) async {
        if noMemory { return }

        if externallyModified {
            fputs("[axion] 检测到外部桌面操作，本次运行的经验不会被记忆\n", stderr)
            return
        }

        // Convert SDK pairs to the ToolPair typealias used by AppMemoryExtractor
        let pairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = toolPairs.map { pair in
            (toolUse: pair.toolUse, toolResult: pair.toolResult)
        }

        do {
            let extractor = AppMemoryExtractor()
            let entries = try await extractor.extract(
                from: pairs,
                task: task,
                runId: runId
            )
            var processedDomains: Set<String> = []
            for entry in entries {
                let domain = entry.tags.first(where: { $0.hasPrefix("app:") })?
                    .dropFirst("app:".count).description ?? "unknown"
                try await memoryStore.save(domain: domain, knowledge: entry)
                processedDomains.insert(domain)
            }

            // Extract AppMemoryFact entries
            let factStore = MemoryFactStore(memoryDir: memoryDir)
            let lifecycleService = MemoryLifecycleService()
            let facts = extractor.extractFacts(
                from: pairs,
                task: task,
                runId: runId
            )
            for fact in facts {
                do {
                    let existing = try await factStore.query(domain: fact.domain)
                    let result = lifecycleService.addFact(fact, mergingWith: existing)
                    try await factStore.save(domain: fact.domain, fact: result)
                } catch {
                    fputs("[axion] warning: memory fact save failed for \(fact.domain): \(error.localizedDescription)\n", stderr)
                }
            }

            // Profile analysis and familiarity tracking
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

                    let tracker = FamiliarityTracker()
                    try await tracker.checkAndUpdateFamiliarity(domain: domain, store: memoryStore)
                } catch {
                    fputs("[axion] warning: profile analysis failed for \(domain): \(error.localizedDescription)\n", stderr)
                }
            }

        } catch {
            fputs("[axion] warning: memory extraction failed: \(error.localizedDescription)\n", stderr)
        }

        // Takeover learning (independent from memory extraction failures)
        if let event = takeoverEvent, runCompleted {
            let takeoverFactStore = MemoryFactStore(memoryDir: memoryDir)
            let takeoverService = TakeoverLearningService(
                factStore: takeoverFactStore,
                lifecycleService: MemoryLifecycleService()
            )
            let domain = inferDomain(from: pairs)
            let outcome: TakeoverOutcome = runSucceeded ? .success : .failed
            let reasonType = InterventionReason.classifyReason(event.reason)

            let marker = TakeoverMarker.create(
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
            await tracer?.record(event: TraceRecorder.TraceEventType.takeover, payload: marker.toDictionary())

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

    // MARK: - Helpers

    /// Infer the active app domain from collected tool-use pairs.
    static func inferDomain(
        from pairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)]
    ) -> String {
        for (toolUse, result) in pairs.reversed() {
            if toolUse.toolName.contains("launch") {
                if let data = result.content.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let bundleId = json["bundle_id"] as? String ?? json["bundleId"] as? String {
                        return bundleId
                    }
                }
            }
        }
        return "unknown"
    }
}
