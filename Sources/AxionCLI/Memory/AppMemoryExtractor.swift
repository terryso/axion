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

    static let mcpPrefix = "mcp__axion-helper__"

    // MARK: - Shared Grouping

    /// A pre-processed app group with extracted metadata, ready for fact/entry building.
    struct AppGroup {
        let domain: String
        let pairs: [ToolPair]
        let appName: String?
        let bundleId: String?
    }

    /// Group tool pairs by app domain with pre-extracted metadata.
    /// Returns an empty array only when `pairs` is empty.
    /// When no app-specific domain is found, returns a single "unknown" group.
    func buildAppGroups(from pairs: [ToolPair]) -> [AppGroup] {
        guard !pairs.isEmpty else { return [] }

        let appGroups = groupByAppDomain(pairs: pairs)

        var groups: [AppGroup] = []
        for (domain, groupPairs) in appGroups {
            let appName = extractAppName(from: groupPairs) ?? domain
            let bundleId = extractBundleId(from: groupPairs)
            groups.append(AppGroup(domain: domain, pairs: groupPairs, appName: appName, bundleId: bundleId))
        }

        if groups.isEmpty {
            groups.append(AppGroup(domain: "unknown", pairs: pairs, appName: nil, bundleId: nil))
        }

        return groups
    }

    // MARK: - Public API

    /// Extract memory facts from a sequence of tool-use/result pairs.
    func extractFacts(
        from pairs: [ToolPair],
        task: String,
        runId: String
    ) -> [AppMemoryFact] {
        buildAppGroups(from: pairs).map { group in
            buildFact(
                pairs: group.pairs, task: task, runId: runId,
                domain: group.domain, appName: group.appName, bundleId: group.bundleId
            )
        }
    }

    /// Extract knowledge entries from a sequence of tool-use/result pairs.
    @available(*, deprecated, message: "Use extractFacts(for:task:runId:) instead")
    func extract(
        from pairs: [ToolPair],
        task: String,
        runId: String
    ) async throws -> [KnowledgeEntry] {
        buildAppGroups(from: pairs).map { group in
            buildEntry(
                pairs: group.pairs, task: task, runId: runId,
                appName: group.appName, bundleId: group.bundleId
            )
        }
    }

    // MARK: - Grouping

    /// Group tool pairs by the App domain extracted from launch_app results.
    ///
    /// Tools that appear before the first `launch_app` are attached to the
    /// first domain when it appears. If no `launch_app` exists, returns empty.
    func groupByAppDomain(pairs: [ToolPair]) -> [(String, [ToolPair])] {
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

    // MARK: - Shared Pair Processing

    /// Computed summary of tool-use/result pairs, shared between `buildFact` and `buildEntry`.
    struct ToolPairSummary {
        let hasError: Bool
        let workaround: String?
        let stepCount: Int
        let successLabel: String
        let toolSequenceWithParams: String
        let axSummary: String
        let keyControls: String
        let failureMarker: String?
    }

    /// Compute shared summary fields from tool pairs.
    func summarizePairs(_ pairs: [ToolPair]) -> ToolPairSummary {
        let hasError = pairs.contains { pair in
            if pair.toolResult.isError { return true }
            return contentContainsErrorPayload(pair.toolResult.content)
        }
        let workaround = extractWorkaround(from: pairs)
        let stepCount = pairs.count
        let successLabel = hasError ? "failure" : "success"
        let toolSequenceWithParams = pairs.map { pair -> String in
            let name = stripMcpPrefix(pair.toolUse.toolName)
            let param = extractToolParamSummary(name: name, input: pair.toolUse.input)
            return param != nil ? "\(name)(\(param!))" : name
        }.joined(separator: " -> ")
        let axSummary = extractAxTreeSummary(from: pairs)
        let keyControls = extractKeyControls(from: pairs)
        let failureMarker = extractFailureMarker(from: pairs)

        return ToolPairSummary(
            hasError: hasError,
            workaround: workaround,
            stepCount: stepCount,
            successLabel: successLabel,
            toolSequenceWithParams: toolSequenceWithParams,
            axSummary: axSummary,
            keyControls: keyControls,
            failureMarker: failureMarker
        )
    }

    /// Build the common description string shared between `buildFact` and `buildEntry`.
    func buildPairDescription(
        summary: ToolPairSummary,
        task: String,
        appName: String?,
        bundleId: String?
    ) -> String {
        var description = ""
        if let appName, let bundleId {
            description += "App: \(appName) (\(bundleId))\n"
        } else if let appName {
            description += "App: \(appName)\n"
        }
        description += """
        任务: \(task)
        结果: \(summary.successLabel)
        工具序列: \(summary.toolSequenceWithParams)
        步骤数: \(summary.stepCount)
        """
        if !summary.axSummary.isEmpty {
            description += "\nAX特征: \(summary.axSummary)"
        }
        if !summary.keyControls.isEmpty {
            description += "\n关键控件: \(summary.keyControls)"
        }
        if let failure = summary.failureMarker {
            description += "\n失败标记: \(failure)"
        }
        if let workaround = summary.workaround {
            description += "\n修正路径: \(workaround)"
        }
        return description
    }

    // MARK: - Fact Building

    /// Build a single AppMemoryFact from a set of tool pairs.
    func buildFact(
        pairs: [ToolPair],
        task: String,
        runId: String,
        domain: String,
        appName: String?,
        bundleId: String?
    ) -> AppMemoryFact {
        let summary = summarizePairs(pairs)
        let classification = classifyKind(pairs: pairs, hasError: summary.hasError, workaround: summary.workaround)

        var description = ""

        // Affordance facts get a concise summary line first (Task 1.5)
        if classification.kind == .affordance {
            let effectiveAppName = appName ?? domain
            let directOps = pairs.compactMap { pair -> String? in
                let name = stripMcpPrefix(pair.toolUse.toolName)
                return Self.directOpNames.contains(name) ? name : nil
            }
            if let primaryOp = directOps.first {
                let paramSummary = extractToolParamSummary(name: primaryOp, input: pairs.first { stripMcpPrefix($0.toolUse.toolName) == primaryOp }?.toolUse.input ?? "")
                let opDesc = paramSummary.map { "\(primaryOp)(\($0))" } ?? primaryOp
                description += "在 \(effectiveAppName) 中使用 \(opDesc) 可高效完成任务\n"
            } else {
                description += "在 \(effectiveAppName) 中发现高效操作路径\n"
            }
        }

        description += buildPairDescription(summary: summary, task: task, appName: appName, bundleId: bundleId)

        return AppMemoryFact.create(
            domain: domain,
            kind: classification.kind,
            description: description,
            confidence: classification.confidence,
            cause: classification.cause,
            evidence: [runId]
        )
    }

    // MARK: - JSON Extraction Helpers

    /// Extract bundle identifier from a launch_app tool result JSON.
    func extractDomainFromLaunchResult(_ content: String) -> String? {
        guard let json = parseJSONDict(from: content) else { return nil }
        return json["bundle_id"] as? String
    }

    /// Extract app_name from a launch_app tool input JSON.
    func extractAppNameFromInput(_ input: String) -> String? {
        guard let json = parseJSONDict(from: input) else { return nil }
        return json["app_name"] as? String
    }

    /// Extract the display name of the first app encountered.
    func extractAppName(from pairs: [ToolPair]) -> String? {
        for pair in pairs {
            if stripMcpPrefix(pair.toolUse.toolName) == "launch_app" {
                return extractAppNameFromInput(pair.toolUse.input)
            }
        }
        return nil
    }

    /// Extract bundle_id from the first launch_app result in the pairs.
    func extractBundleId(from pairs: [ToolPair]) -> String? {
        for pair in pairs {
            if stripMcpPrefix(pair.toolUse.toolName) == "launch_app" {
                return extractDomainFromLaunchResult(pair.toolResult.content)
            }
        }
        return nil
    }

    /// Strip the MCP prefix from tool names.
    func stripMcpPrefix(_ toolName: String) -> String {
        if toolName.hasPrefix(Self.mcpPrefix) {
            return String(toolName.dropFirst(Self.mcpPrefix.count))
        }
        return toolName
    }

    /// Extract a brief parameter summary for a tool call.
    func extractToolParamSummary(name: String, input: String) -> String? {
        guard let json = parseJSONDict(from: input) else { return nil }

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
}
