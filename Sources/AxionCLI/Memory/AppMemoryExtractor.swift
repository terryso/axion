import Foundation
import OpenAgentSDK

/// Extracts App operation summaries from SDK message streams and produces
/// ``KnowledgeEntry`` objects organized by App domain (bundle identifier).
///
/// Used by ``RunCommand`` after a task completes to persist cross-run
/// experience into the SDK's MemoryStore.
///
/// Enhanced in Story 4.2 to include AX tree structure features, failure markers,
/// and workaround inference in extracted content.
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

            // Extract tool parameters for enhanced sequence display
            let toolSequenceWithParams = groupPairs.map { pair -> String in
                let name = stripMcpPrefix(pair.toolUse.toolName)
                let param = extractToolParamSummary(name: name, input: pair.toolUse.input)
                return param != nil ? "\(name)(\(param!))" : name
            }.joined(separator: " -> ")

            // Extract AX tree features
            let axSummary = extractAxTreeSummary(from: groupPairs)
            let keyControls = extractKeyControls(from: groupPairs)

            // Extract failure markers and workaround
            let failureMarker = extractFailureMarker(from: groupPairs)
            let workaround = extractWorkaround(from: groupPairs)

            // Build enhanced content
            var content = """
            App: \(appName)\(bundleId != nil ? " (\(bundleId!))" : "")
            任务: \(task)
            结果: \(successLabel)
            工具序列: \(toolSequenceWithParams)
            步骤数: \(stepCount)
            """

            if !axSummary.isEmpty {
                content += "\nAX特征: \(axSummary)"
            }
            if !keyControls.isEmpty {
                content += "\n关键控件: \(keyControls)"
            }
            if let failure = failureMarker {
                content += "\n失败标记: \(failure)"
            }
            if let workaround {
                content += "\n修正路径: \(workaround)"
            }

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

            let toolSequenceWithParams = pairs.map { pair -> String in
                let name = stripMcpPrefix(pair.toolUse.toolName)
                let param = extractToolParamSummary(name: name, input: pair.toolUse.input)
                return param != nil ? "\(name)(\(param!))" : name
            }.joined(separator: " -> ")

            // Extract AX tree features
            let axSummary = extractAxTreeSummary(from: pairs)
            let keyControls = extractKeyControls(from: pairs)
            let failureMarker = extractFailureMarker(from: pairs)
            let workaround = extractWorkaround(from: pairs)

            var content = """
            任务: \(task)
            结果: \(successLabel)
            工具序列: \(toolSequenceWithParams)
            步骤数: \(pairs.count)
            """

            if !axSummary.isEmpty {
                content += "\nAX特征: \(axSummary)"
            }
            if !keyControls.isEmpty {
                content += "\n关键控件: \(keyControls)"
            }
            if let failure = failureMarker {
                content += "\n失败标记: \(failure)"
            }
            if let workaround {
                content += "\n修正路径: \(workaround)"
            }

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

    // MARK: - Story 4.2: AX Tree & Failure Extraction

    /// Extract a brief parameter summary for a tool call.
    private func extractToolParamSummary(name: String, input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        switch name {
        case "click":
            // Show ax_selector if available, otherwise coordinates
            if let selector = json["ax_selector"] as? String {
                return selector
            }
            if let x = json["x"], let y = json["y"] {
                return "x:\(x),y:\(y)"
            }
            return nil
        case "type_text":
            return json["text"] as? String
        case "hotkey":
            if let key = json["key"] as? String {
                let mods = json["modifiers"] as? [String] ?? []
                if mods.isEmpty {
                    return key
                }
                return mods.joined(separator: "+") + "+\"\(key)\""
            }
            return nil
        default:
            return nil
        }
    }

    /// Extract AX tree structure summary from get_window_state / get_accessibility_tree tool results.
    private func extractAxTreeSummary(from pairs: [ToolPair]) -> String {
        var roleTypes: Set<String> = []

        for pair in pairs {
            let toolName = stripMcpPrefix(pair.toolUse.toolName)
            guard toolName == "get_window_state" || toolName == "get_accessibility_tree" else { continue }

            // Try to parse AX tree JSON from the result
            if let axInfo = parseAxRoles(from: pair.toolResult.content) {
                roleTypes.formUnion(axInfo)
            }
        }

        guard !roleTypes.isEmpty else { return "" }

        let sorted = roleTypes.sorted()
        if sorted.count <= 3 {
            return "窗口包含 \(sorted.joined(separator: "、")) 角色控件"
        } else {
            return "窗口包含 \(sorted.prefix(3).joined(separator: "、")) 等 \(sorted.count) 种角色控件"
        }
    }

    /// Extract key controls (AXButton, AXTextField with titles) from AX tree tool results.
    private func extractKeyControls(from pairs: [ToolPair]) -> String {
        var controls: [String] = []

        for pair in pairs {
            let toolName = stripMcpPrefix(pair.toolUse.toolName)
            guard toolName == "get_window_state" || toolName == "get_accessibility_tree" else { continue }

            if let titledControls = parseAxTitledControls(from: pair.toolResult.content) {
                controls.append(contentsOf: titledControls)
            }
        }

        guard !controls.isEmpty else { return "" }

        // Limit to most relevant controls (max 5)
        let limited = Array(controls.prefix(5))
        return limited.joined(separator: ", ")
    }

    /// Parse AX tree JSON to extract role types.
    private func parseAxRoles(from content: String) -> Set<String>? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var roles = Set<String>()
        collectRoles(from: json, into: &roles, depth: 0)
        return roles.isEmpty ? nil : roles
    }

    private static let maxAxDepth = 50

    /// Recursively collect AX role types from JSON tree with depth guard.
    private func collectRoles(from node: [String: Any], into roles: inout Set<String>, depth: Int) {
        guard depth <= Self.maxAxDepth else { return }
        if let role = node["role"] as? String, role.hasPrefix("AX") {
            roles.insert(role)
        }
        if let children = node["children"] as? [[String: Any]] {
            for child in children {
                collectRoles(from: child, into: &roles, depth: depth + 1)
            }
        }
        if let windows = node["windows"] as? [[String: Any]] {
            for window in windows {
                collectRoles(from: window, into: &roles, depth: depth + 1)
            }
        }
        if let root = node["root"] as? [String: Any] {
            collectRoles(from: root, into: &roles, depth: depth + 1)
        }
    }

    /// Parse AX tree JSON to extract titled controls (for "关键控件" summary).
    private func parseAxTitledControls(from content: String) -> [String]? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var controls: [String] = []
        collectTitledControls(from: json, into: &controls, depth: 0)
        return controls.isEmpty ? nil : controls
    }

    private func collectTitledControls(from node: [String: Any], into controls: inout [String], depth: Int) {
        guard depth <= Self.maxAxDepth else { return }
        let role = node["role"] as? String ?? ""
        let title = node["title"] as? String

        if let title, !title.isEmpty,
           role.hasPrefix("AX") && (role.contains("Button") || role.contains("TextField") || role.contains("Menu")) {
            controls.append("\(role)[title=\"\(title)\"]")
        }

        if let children = node["children"] as? [[String: Any]] {
            for child in children {
                collectTitledControls(from: child, into: &controls, depth: depth + 1)
            }
        }
        if let windows = node["windows"] as? [[String: Any]] {
            for window in windows {
                collectTitledControls(from: window, into: &controls, depth: depth + 1)
            }
        }
        if let root = node["root"] as? [String: Any] {
            collectTitledControls(from: root, into: &controls, depth: depth + 1)
        }
    }

    /// Extract failure marker from error tool results.
    private func extractFailureMarker(from pairs: [ToolPair]) -> String? {
        for pair in pairs {
            if pair.toolResult.isError {
                let toolName = stripMcpPrefix(pair.toolUse.toolName)
                let paramSummary = extractToolParamSummary(name: toolName, input: pair.toolUse.input)
                let toolDesc = paramSummary != nil ? "\(toolName)(\(paramSummary!))" : toolName

                // Try to extract error message from JSON result
                let errorMsg = extractErrorMessage(from: pair.toolResult.content)

                if let errorMsg {
                    return "\(toolDesc) 失败: \(errorMsg)"
                } else {
                    return "\(toolDesc) 操作不可靠"
                }
            }
        }
        return nil
    }

    /// Extract workaround when a failed tool is followed by a successful tool.
    private func extractWorkaround(from pairs: [ToolPair]) -> String? {
        // Find first error pair and the next successful pair
        var errorIndex: Int?
        for (i, pair) in pairs.enumerated() {
            if pair.toolResult.isError {
                errorIndex = i
                break
            }
        }

        guard let errorIdx = errorIndex else { return nil }

        // Look for the next successful pair after the failure
        for i in (errorIdx + 1)..<pairs.count {
            let nextPair = pairs[i]
            if !nextPair.toolResult.isError {
                let nextTool = stripMcpPrefix(nextPair.toolUse.toolName)
                let nextParam = extractToolParamSummary(name: nextTool, input: nextPair.toolUse.input)

                if let nextParam {
                    return "使用 \(nextTool)(\(nextParam)) 代替失败的操作"
                } else {
                    return "使用 \(nextTool) 重新尝试"
                }
            }
        }

        return nil
    }

    /// Extract error message from tool result content.
    private func extractErrorMessage(from content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let message = json["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }
        return nil
    }
}
