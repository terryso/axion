import Foundation
import OpenAgentSDK


/// Encapsulates all memory-related operations for a single agent run.
///
/// Handles pre-run cleanup (expired entries, fact demotion) and post-run
/// processing (memory extraction, fact extraction/merge, profile analysis,
/// familiarity tracking, takeover learning).
///
/// Post-run processing helpers live in `RunMemoryProcessor+PostRunProcessing`.
struct RunMemoryProcessor {

    /// Demotion interval: 30 days in seconds.
    private static let demotionInterval: TimeInterval = 30 * 24 * 60 * 60

    /// Clean up expired memory entries and demote retired facts before a run starts.
    static func preRunCleanup(memoryStore: FileBasedMemoryStore, memoryDir: String) async {
        do {
            let cutoffDate = Date().addingTimeInterval(-demotionInterval)
            let factStore = AxionFactStore(memoryDir: memoryDir)
            let lifecycleService = SDKMemoryLifecycleService()
            let domains = try await factStore.listDomains()
            for domain in domains {
                let facts = try await factStore.query(domain: domain)
                let sdkFacts = facts.map { $0.toSDKFact() }
                let demoted = lifecycleService.demoteRetired(facts: sdkFacts, lastVerifiedBefore: cutoffDate)
                let demotedById = Dictionary(uniqueKeysWithValues: demoted.map { ($0.id, $0) })
                for fact in facts {
                    guard let sdkFact = demotedById[fact.id] else { continue }
                    var updated = fact
                    updated.status = MemoryFactStatus(rawValue: sdkFact.status.rawValue) ?? fact.status
                    updated.confidence = sdkFact.confidence
                    updated.updatedAt = sdkFact.lastVerifiedAt
                    try await factStore.save(domain: domain, fact: updated)
                }
            }
        } catch {
            fputs("[axion] warning: memory fact lifecycle demotion failed: \(error.localizedDescription)\n", stderr)
        }
    }

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
    /// Delegates to helper methods in `RunMemoryProcessor+PostRunProcessing`:
    /// - `saveKnowledgeEntries` — persist extracted knowledge entries
    /// - `extractAndMergeFacts` — extract and merge facts via lifecycle service
    /// - `analyzeProfilesAndFamiliarity` — profile analysis and familiarity tracking
    /// - `processTakeoverLearning` — record takeover learning events
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
        runCompleted: Bool
    ) async {
        if noMemory { return }

        if externallyModified {
            fputs("[axion] \u{68C0}\u{6D4B}\u{5230}\u{5916}\u{90E8}\u{684C}\u{9762}\u{64CD}\u{4F5C}\u{FF0C}\u{672C}\u{6B21}\u{8FD0}\u{884C}\u{7684}\u{7ECF}\u{9A8C}\u{4E0D}\u{4F1A}\u{88AB}\u{8BB0}\u{5FC6}\n", stderr)
            return
        }

        // Convert SDK pairs to the ToolPair typealias used by AppMemoryExtractor
        let pairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = toolPairs.map { pair in
            (toolUse: pair.toolUse, toolResult: pair.toolResult)
        }

        do {
            let extractor = AppMemoryExtractor()
            let entries = extractor.extractKnowledgeEntries(from: pairs, task: task, runId: runId)
            let processedDomains = try await saveKnowledgeEntries(entries, to: memoryStore)

            await extractAndMergeFacts(
                extractor: extractor, pairs: pairs, task: task,
                runId: runId, memoryDir: memoryDir
            )

            await analyzeProfilesAndFamiliarity(
                processedDomains: processedDomains, memoryStore: memoryStore
            )
        } catch {
            fputs("[axion] warning: memory extraction failed: \(error.localizedDescription)\n", stderr)
        }

        // Takeover learning (independent from memory extraction failures)
        if let event = takeoverEvent {
            await processTakeoverLearning(
                event: event, runId: runId, task: task,
                memoryDir: memoryDir, runSucceeded: runSucceeded,
                runCompleted: runCompleted, pairs: pairs
            )
        }
    }

    /// Infer the active app domain from collected tool-use pairs.
    static func inferDomain(
        from pairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)]
    ) -> String {
        for (toolUse, result) in pairs.reversed() {
            if toolUse.toolName.contains("launch") {
                if let json = parseJSONDict(from: result.content) {
                    if let bundleId = json["bundle_id"] as? String ?? json["bundleId"] as? String {
                        return bundleId
                    }
                }
            }
        }
        return "unknown"
    }
}
