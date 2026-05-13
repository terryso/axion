import Foundation
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

    // MARK: - AX Characteristics Extraction

    /// Extract and deduplicate AX tree characteristics from entry content.
    private func extractAxCharacteristics(from entries: [KnowledgeEntry]) -> [String] {
        var allCharacteristics: [String] = []

        for entry in entries {
            let lines = entry.content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("AX特征:") {
                    let value = String(trimmed.dropFirst("AX特征:".count))
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty {
                        // Split by comma to get individual characteristics
                        let parts = value.components(separatedBy: "，")
                            .flatMap { $0.components(separatedBy: ",") }
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        allCharacteristics.append(contentsOf: parts)
                    }
                }
                if trimmed.hasPrefix("关键控件:") {
                    let value = String(trimmed.dropFirst("关键控件:".count))
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty {
                        let parts = value.components(separatedBy: ",")
                            .flatMap { $0.components(separatedBy: "，") }
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        allCharacteristics.append(contentsOf: parts)
                    }
                }
            }
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        var deduped: [String] = []
        for characteristic in allCharacteristics {
            if seen.insert(characteristic).inserted {
                deduped.append(characteristic)
            }
        }
        return deduped
    }

    // MARK: - Common Patterns Extraction

    /// Extract high-frequency operation patterns using sliding window approach.
    private func extractCommonPatterns(
        successEntries: [KnowledgeEntry],
        failureEntries: [KnowledgeEntry]
    ) -> [OperationPattern] {
        // Extract tool sequences from all entries
        struct SequenceInfo {
            let sequence: [String]
            let isSuccess: Bool
        }

        var allSequences: [SequenceInfo] = []

        for entry in successEntries {
            if let seq = extractToolSequence(from: entry.content) {
                allSequences.append(SequenceInfo(sequence: seq, isSuccess: true))
            }
        }
        for entry in failureEntries {
            if let seq = extractToolSequence(from: entry.content) {
                allSequences.append(SequenceInfo(sequence: seq, isSuccess: false))
            }
        }

        guard !allSequences.isEmpty else { return [] }

        // Use sliding windows of sizes 2, 3, 4 to find patterns
        var patternCounts: [String: (count: Int, successCount: Int)] = [:]

        for info in allSequences {
            let seq = info.sequence
            let maxWindowSize = min(4, seq.count)
            guard maxWindowSize >= 2 else { continue }
            for windowSize in 2...maxWindowSize {
                for i in 0...(seq.count - windowSize) {
                    let window = Array(seq[i..<(i + windowSize)])
                    let key = window.joined(separator: " -> ")
                    if patternCounts[key] == nil {
                        patternCounts[key] = (count: 0, successCount: 0)
                    }
                    patternCounts[key]!.count += 1
                    if info.isSuccess {
                        patternCounts[key]!.successCount += 1
                    }
                }
            }
        }

        // Filter to frequency >= 2 and build OperationPattern
        let patterns = patternCounts
            .filter { $0.value.count >= 2 }
            .map { (key, value) -> OperationPattern in
                let sequence = key.components(separatedBy: " -> ")
                let successRate = Double(value.successCount) / Double(value.count)
                let description = "\(sequence.joined(separator: " → ")) (appeared \(value.count) times, \(Int(round(successRate * 100)))% success)"
                return OperationPattern(
                    sequence: sequence,
                    frequency: value.count,
                    successRate: successRate,
                    description: description
                )
            }
            .sorted { $0.frequency > $1.frequency }

        return patterns
    }

    /// Extract the tool sequence from entry content (parse "工具序列:" line).
    /// Strips parameter suffixes (parenthesized parts) for pattern matching consistency,
    /// so "click(x:100,y:200)" and "click(x:300,y:400)" both match as "click".
    private func extractToolSequence(from content: String) -> [String]? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("工具序列:") {
                let value = String(trimmed.dropFirst("工具序列:".count))
                    .trimmingCharacters(in: .whitespaces)
                let tools = value.components(separatedBy: " -> ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .map { stripToolParams($0) }
                    .filter { !$0.isEmpty }
                if !tools.isEmpty {
                    return tools
                }
            }
        }
        return nil
    }

    /// Strip parenthesized parameter suffix from a tool name for pattern matching.
    /// e.g., "click(x:100,y:200)" -> "click", "type_text(\"hello\")" -> "type_text"
    private func stripToolParams(_ toolName: String) -> String {
        if let parenIndex = toolName.firstIndex(of: "(") {
            return String(toolName[..<parenIndex])
        }
        return toolName
    }

    // MARK: - Failure Patterns Extraction

    /// Extract failure patterns from entries with failure tags.
    private func extractKnownFailures(from failureEntries: [KnowledgeEntry]) -> [FailurePattern] {
        var failures: [FailurePattern] = []

        for entry in failureEntries {
            let content = entry.content
            let failedAction = extractField(from: content, prefix: "失败标记:") ?? "Unknown failure"
            let reason: String

            // Try to extract more specific reason from the failure marker
            if failedAction.contains("不可靠") {
                reason = "坐标或元素定位不可靠"
            } else if failedAction.contains("未安装") {
                reason = "应用未安装"
            } else if failedAction.contains("未找到") {
                reason = "目标元素未找到"
            } else {
                reason = "操作失败"
            }

            let workaround = extractField(from: content, prefix: "修正路径:")

            failures.append(FailurePattern(
                failedAction: failedAction,
                reason: reason,
                workaround: workaround
            ))
        }

        return failures
    }

    /// Extract a specific field value from content text by prefix.
    private func extractField(from content: String, prefix: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                let value = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
