import OpenAgentSDK

/// A structured profile summarizing accumulated experience with a specific App.
///
/// Produced by ``AppProfileAnalyzer`` from historical ``KnowledgeEntry`` records.
/// This is a pure data type — persistence is handled separately via KnowledgeEntry.
struct AppProfile {
    /// The App domain (bundle identifier or app name).
    let domain: String
    /// Total number of recorded runs.
    let totalRuns: Int
    /// Number of successful runs.
    let successfulRuns: Int
    /// Number of failed runs.
    let failedRuns: Int
    /// High-frequency operation patterns identified across runs.
    let commonPatterns: [OperationPattern]
    /// Known failure patterns with optional workarounds.
    let knownFailures: [FailurePattern]
    /// AX tree structure characteristics observed across runs (deduplicated).
    let axCharacteristics: [String]
    /// Whether the app is considered "familiar" (>= 3 successful runs).
    let isFamiliar: Bool
}

/// A recurring operation pattern identified across multiple runs.
struct OperationPattern {
    /// The tool sequence (e.g., ["launch_app", "click", "type_text"]).
    let sequence: [String]
    /// How many times this exact sequence appeared.
    let frequency: Int
    /// Success rate (0.0 to 1.0).
    let successRate: Double
    /// Human-readable description.
    let description: String
}

/// A known failure pattern with optional workaround.
struct FailurePattern {
    /// Description of the failed action.
    let failedAction: String
    /// Why the failure occurred.
    let reason: String
    /// Optional correction path that worked instead.
    let workaround: String?
}

/// Pure computation service that analyzes historical ``KnowledgeEntry`` records
/// for a specific App domain and produces a structured ``AppProfile``.
///
/// This is a struct with no side effects — it does not interact with MemoryStore
/// directly. The caller is responsible for persisting results.
struct AppProfileAnalyzer {

    // MARK: - Public API

    /// Analyze accumulated history and produce an AppProfile.
    ///
    /// - Parameters:
    ///   - domain: The App domain to analyze.
    ///   - history: All historical KnowledgeEntry records (may include entries from other domains).
    /// - Returns: A structured AppProfile summarizing the accumulated experience.
    func analyze(domain: String, history: [KnowledgeEntry]) -> AppProfile {
        // Filter to entries belonging to this domain
        let domainEntries = history.filter { entry in
            entry.tags.contains(where: { $0 == "app:\(domain)" })
        }

        // Only count actual run entries (tagged success or failure), not profile/familiar metadata
        let runEntries = domainEntries.filter { entry in
            entry.tags.contains("success") || entry.tags.contains("failure")
        }

        guard !domainEntries.isEmpty else {
            return AppProfile(
                domain: domain,
                totalRuns: 0,
                successfulRuns: 0,
                failedRuns: 0,
                commonPatterns: [],
                knownFailures: [],
                axCharacteristics: [],
                isFamiliar: false
            )
        }

        let successEntries = runEntries.filter { $0.tags.contains("success") }
        let failureEntries = runEntries.filter { $0.tags.contains("failure") }
        let successCount = successEntries.count
        let failureCount = failureEntries.count
        let isFamiliar = successCount >= 3

        // Extract AX characteristics from run entries (not profile/familiar metadata)
        let axCharacteristics = extractAxCharacteristics(from: runEntries)
        let commonPatterns = extractCommonPatterns(
            successEntries: successEntries,
            failureEntries: failureEntries
        )
        let knownFailures = extractKnownFailures(from: failureEntries)

        return AppProfile(
            domain: domain,
            totalRuns: runEntries.count,
            successfulRuns: successCount,
            failedRuns: failureCount,
            commonPatterns: commonPatterns,
            knownFailures: knownFailures,
            axCharacteristics: axCharacteristics,
            isFamiliar: isFamiliar
        )
    }

}
