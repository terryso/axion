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

    private static let mcpPrefix = "mcp__axion-helper__"

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

        let appGroups = groupByAppDomain(pairs: pairs)

        var entries: [KnowledgeEntry] = []

        for (domain, groupPairs) in appGroups {
            let appName = extractAppName(from: groupPairs) ?? domain
            let bundleId = extractBundleId(from: groupPairs)
            entries.append(buildEntry(
                pairs: groupPairs,
                task: task,
                runId: runId,
                appName: appName,
                bundleId: bundleId
            ))
        }

        // If no app-specific domain was found (no launch_app), create a single
        // generic entry so the tool sequence is still captured.
        if entries.isEmpty {
            entries.append(buildEntry(
                pairs: pairs,
                task: task,
                runId: runId,
                appName: nil,
                bundleId: nil
            ))
        }

        return entries
    }

    // MARK: - Private Helpers

    /// Group tool pairs by the App domain extracted from launch_app results.
    ///
    /// Tools that appear before the first `launch_app` are attached to the
    /// first domain when it appears. If no `launch_app` exists, returns empty.
    private func groupByAppDomain(pairs: [ToolPair]) -> [(String, [ToolPair])] {
        var groups: [(domain: String, pairs: [ToolPair])] = []
        var domainIndex: [String: Int] = [:]
        var currentDomain: String?
        var orphanPairs: [ToolPair] = []

        for pair in pairs {
            let toolName = stripMcpPrefix(pair.toolUse.toolName)

            if toolName == "launch_app" {
                let domain = extractDomainFromLaunchResult(pair.toolResult.content)
                    ?? extractAppNameFromInput(pair.toolUse.input)
                    ?? "unknown"
                currentDomain = domain
                if let idx = domainIndex[domain] {
                    groups[idx].pairs.append(contentsOf: orphanPairs)
                    groups[idx].pairs.append(pair)
                } else {
                    domainIndex[domain] = groups.count
                    var groupPairs = orphanPairs
                    groupPairs.append(pair)
                    groups.append((domain: domain, pairs: groupPairs))
                }
                orphanPairs = []
            } else if let domain = currentDomain, let idx = domainIndex[domain] {
                groups[idx].pairs.append(pair)
            } else {
                orphanPairs.append(pair)
            }
        }

        return groups.map { ($0.domain, $0.pairs) }
    }

    /// Build a single KnowledgeEntry from a set of tool pairs.
    private func buildEntry(
        pairs: [ToolPair],
        task: String,
        runId: String,
        appName: String?,
        bundleId: String?
    ) -> KnowledgeEntry {
        let toolNames = pairs.map { stripMcpPrefix($0.toolUse.toolName) }
        let hasError = pairs.contains { pair in
            if pair.toolResult.isError { return true }
            // Some tools catch errors and return structured JSON instead of throwing,
            // so isError is false even when the result is an error. Detect these by
            // checking for error payload fields in the content.
            return contentContainsErrorPayload(pair.toolResult.content)
        }
        let stepCount = pairs.count
        let effectiveAppName = appName ?? "unknown"
        let successLabel = hasError ? "failure" : "success"

        let toolSequenceWithParams = pairs.map { pair -> String in
            let name = stripMcpPrefix(pair.toolUse.toolName)
            let param = extractToolParamSummary(name: name, input: pair.toolUse.input)
            return param != nil ? "\(name)(\(param!))" : name
        }.joined(separator: " -> ")

        var content = ""
        if let appName, let bundleId {
            content += "App: \(appName) (\(bundleId))\n"
        } else if let appName {
            content += "App: \(appName)\n"
        }
        content += """
        任务: \(task)
        结果: \(successLabel)
        工具序列: \(toolSequenceWithParams)
        步骤数: \(stepCount)
        """

        let axSummary = extractAxTreeSummary(from: pairs)
        let keyControls = extractKeyControls(from: pairs)
        let failureMarker = extractFailureMarker(from: pairs)
        let workaround = extractWorkaround(from: pairs)

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
            appName: effectiveAppName,
            bundleId: bundleId,
            toolNames: toolNames,
            hasError: hasError
        )

        return KnowledgeEntry(
            id: UUID().uuidString,
            content: content,
            tags: tags,
            createdAt: Date(),
            sourceRunId: runId
        )
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

    /// Strip the MCP prefix from tool names.
    private func stripMcpPrefix(_ toolName: String) -> String {
        if toolName.hasPrefix(Self.mcpPrefix) {
            return String(toolName.dropFirst(Self.mcpPrefix.count))
        }
        return toolName
    }

    // MARK: - AX Tree & Failure Extraction

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
            let isFailure = pair.toolResult.isError || contentContainsErrorPayload(pair.toolResult.content)
            if isFailure {
                let toolName = stripMcpPrefix(pair.toolUse.toolName)
                let paramSummary = extractToolParamSummary(name: toolName, input: pair.toolUse.input)
                let toolDesc = paramSummary != nil ? "\(toolName)(\(paramSummary!))" : toolName

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
    /// Prefers a successful tool of the same type as the failed tool, falling back
    /// to the first successful tool of any type.
    private func extractWorkaround(from pairs: [ToolPair]) -> String? {
        // Find first error pair
        var errorIndex: Int?
        for (i, pair) in pairs.enumerated() {
            if pair.toolResult.isError || contentContainsErrorPayload(pair.toolResult.content) {
                errorIndex = i
                break
            }
        }

        guard let errorIdx = errorIndex else { return nil }

        let failedTool = stripMcpPrefix(pairs[errorIdx].toolUse.toolName)
        var firstSuccessFallback: String?

        // Look for a successful pair after the failure, preferring same tool type
        for i in (errorIdx + 1)..<pairs.count {
            let nextPair = pairs[i]
            let nextIsSuccess = !nextPair.toolResult.isError && !contentContainsErrorPayload(nextPair.toolResult.content)
            if nextIsSuccess {
                let nextTool = stripMcpPrefix(nextPair.toolUse.toolName)
                let nextParam = extractToolParamSummary(name: nextTool, input: nextPair.toolUse.input)
                let desc = nextParam != nil ? "\(nextTool)(\(nextParam!))" : nextTool

                if nextTool == failedTool {
                    // Same tool type — best match
                    return nextParam != nil
                        ? "使用 \(nextTool)(\(nextParam!)) 代替失败的操作"
                        : "使用 \(nextTool) 重新尝试"
                }

                // Remember first successful tool as fallback
                if firstSuccessFallback == nil {
                    firstSuccessFallback = nextParam != nil
                        ? "使用 \(desc) 代替失败的操作"
                        : "使用 \(nextTool) 重新尝试"
                }
            }
        }

        return firstSuccessFallback
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

    /// Check if tool result content contains a structured error payload.
    ///
    /// Some tools (e.g., launch_app) catch errors and return structured JSON
    /// with "error" and "message" fields instead of throwing. This makes the
    /// MCP framework set `isError: false` even though the result is an error.
    private func contentContainsErrorPayload(_ content: String) -> Bool {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        // ToolErrorPayload has both "error" and "message" keys
        return json["error"] != nil && json["message"] != nil
    }
}
