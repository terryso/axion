import Foundation
import OpenAgentSDK

extension AppMemoryExtractor {

    // MARK: - Deprecated Entry Building

    /// Build a single KnowledgeEntry from a set of tool pairs.
    func buildEntry(
        pairs: [ToolPair],
        task: String,
        runId: String,
        appName: String?,
        bundleId: String?
    ) -> KnowledgeEntry {
        let summary = summarizePairs(pairs)
        let content = buildPairDescription(summary: summary, task: task, appName: appName, bundleId: bundleId)

        let toolNames = pairs.map { stripMcpPrefix($0.toolUse.toolName) }
        let tags = buildTags(
            appName: appName ?? "unknown",
            bundleId: bundleId,
            toolNames: toolNames,
            hasError: summary.hasError
        )

        return KnowledgeEntry(
            id: UUID().uuidString,
            content: content,
            tags: tags,
            createdAt: Date(),
            sourceRunId: runId
        )
    }

    /// Build tags array for a knowledge entry.
    func buildTags(
        appName: String,
        bundleId: String?,
        toolNames: [String],
        hasError: Bool
    ) -> [String] {
        var tags: [String] = []

        // App tag
        let appTag = bundleId ?? appName.lowercased()
        tags.append("app:\(appTag)")

        // Success/failure tag
        tags.append(hasError ? "failure" : "success")

        // Tools tag
        let uniqueTools = Array(Set(toolNames)).sorted()
        tags.append("tools:\(uniqueTools.joined(separator: ","))")

        return tags
    }
}
