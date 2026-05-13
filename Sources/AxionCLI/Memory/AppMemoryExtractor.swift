import Foundation
import OpenAgentSDK

/// Extracts App operation summaries from SDK message streams and produces
/// ``KnowledgeEntry`` objects organized by App domain (bundle identifier).
///
/// Used by ``RunCommand`` after a task completes to persist cross-run
/// experience into the SDK's MemoryStore.
struct AppMemoryExtractor {

    // MARK: - Types

    /// A paired toolUse + toolResult from the SDK message stream.
    typealias ToolPair = (toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)

    // MARK: - Public API

    /// Extract knowledge entries from a sequence of tool-use/result pairs.
    ///
    /// - Parameters:
    ///   - pairs: The collected toolUse/toolResult pairs from the SDK message stream.
    ///   - task: The original task description provided by the user.
    ///   - runId: The run ID for this execution (used as `sourceRunId`).
    /// - Returns: An array of ``KnowledgeEntry`` objects, one per distinct App domain encountered.
    func extract(
        from pairs: [ToolPair],
        task: String,
        runId: String
    ) async throws -> [KnowledgeEntry] {
        guard !pairs.isEmpty else { return [] }

        // Group pairs by App domain
        let appGroups = groupByAppDomain(pairs: pairs)

        var entries: [KnowledgeEntry] = []

        for (domain, groupPairs) in appGroups {
            let toolNames = groupPairs.map { stripMcpPrefix($0.toolUse.toolName) }
            let hasError = groupPairs.contains { $0.toolResult.isError }
            let stepCount = groupPairs.count
            let appName = extractAppName(from: groupPairs) ?? domain
            let bundleId = extractBundleId(from: groupPairs)

            let successLabel = hasError ? "failure" : "success"
            let toolSequence = toolNames.joined(separator: " -> ")

            let content = """
            App: \(appName)\(bundleId != nil ? " (\(bundleId!))" : "")
            任务: \(task)
            结果: \(successLabel)
            工具序列: \(toolSequence)
            步骤数: \(stepCount)
            """

            let tags = buildTags(
                appName: appName,
                bundleId: bundleId,
                toolNames: toolNames,
                hasError: hasError
            )

            let entry = KnowledgeEntry(
                id: UUID().uuidString,
                content: content,
                tags: tags,
                createdAt: Date(),
                sourceRunId: runId
            )
            entries.append(entry)
        }

        // If no app-specific domain was found (no launch_app), create a single
        // generic entry so the tool sequence is still captured.
        if entries.isEmpty && !pairs.isEmpty {
            let toolNames = pairs.map { stripMcpPrefix($0.toolUse.toolName) }
            let hasError = pairs.contains { $0.toolResult.isError }
            let successLabel = hasError ? "failure" : "success"
            let toolSequence = toolNames.joined(separator: " -> ")

            let content = """
            任务: \(task)
            结果: \(successLabel)
            工具序列: \(toolSequence)
            步骤数: \(pairs.count)
            """

            let tags = buildTags(
                appName: "unknown",
                bundleId: nil,
                toolNames: toolNames,
                hasError: hasError
            )

            entries.append(KnowledgeEntry(
                id: UUID().uuidString,
                content: content,
                tags: tags,
                createdAt: Date(),
                sourceRunId: runId
            ))
        }

        return entries
    }

    // MARK: - Private Helpers

    /// Group tool pairs by the App domain extracted from launch_app results.
    ///
    /// Pairs that are NOT launch_app are associated with the most recently
    /// seen app domain (or dropped if no app has been launched yet).
    private func groupByAppDomain(pairs: [ToolPair]) -> [(String, [ToolPair])] {
        var groups: [(domain: String, pairs: [ToolPair])] = []
        var domainIndex: [String: Int] = [:]
        var currentDomain: String?

        for pair in pairs {
            let toolName = stripMcpPrefix(pair.toolUse.toolName)

            if toolName == "launch_app" {
                let domain = extractDomainFromLaunchResult(pair.toolResult.content)
                    ?? extractAppNameFromInput(pair.toolUse.input)
                    ?? "unknown"
                currentDomain = domain
                if let idx = domainIndex[domain] {
                    groups[idx].pairs.append(pair)
                } else {
                    domainIndex[domain] = groups.count
                    groups.append((domain: domain, pairs: [pair]))
                }
            } else if let domain = currentDomain, let idx = domainIndex[domain] {
                groups[idx].pairs.append(pair)
            }
        }

        return groups.map { ($0.domain, $0.pairs) }
    }

    /// Extract bundle identifier from a launch_app tool result JSON.
    private func extractDomainFromLaunchResult(_ content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["bundle_id"] as? String
    }

    /// Extract app_name from a launch_app tool input JSON.
    private func extractAppNameFromInput(_ input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["app_name"] as? String
    }

    /// Extract the display name of the first app encountered.
    private func extractAppName(from pairs: [ToolPair]) -> String? {
        for pair in pairs {
            if stripMcpPrefix(pair.toolUse.toolName) == "launch_app" {
                return extractAppNameFromInput(pair.toolUse.input)
            }
        }
        return nil
    }

    /// Extract bundle_id from the first launch_app result in the pairs.
    private func extractBundleId(from pairs: [ToolPair]) -> String? {
        for pair in pairs {
            if stripMcpPrefix(pair.toolUse.toolName) == "launch_app" {
                return extractDomainFromLaunchResult(pair.toolResult.content)
            }
        }
        return nil
    }

    /// Build tags array for a knowledge entry.
    private func buildTags(
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

    /// Strip the MCP prefix `mcp__axion-helper__` from tool names.
    private func stripMcpPrefix(_ toolName: String) -> String {
        if toolName.hasPrefix("mcp__axion-helper__") {
            return String(toolName.dropFirst("mcp__axion-helper__".count))
        }
        return toolName
    }
}
