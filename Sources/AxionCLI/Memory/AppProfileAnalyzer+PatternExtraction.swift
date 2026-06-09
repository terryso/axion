import Foundation
import OpenAgentSDK

// MARK: - AX Characteristics Extraction

extension AppProfileAnalyzer {

    /// Extract and deduplicate AX tree characteristics from entry content.
    func extractAxCharacteristics(from entries: [KnowledgeEntry]) -> [String] {
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
    func extractCommonPatterns(
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
    func extractToolSequence(from content: String) -> [String]? {
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
    func stripToolParams(_ toolName: String) -> String {
        if let parenIndex = toolName.firstIndex(of: "(") {
            return String(toolName[..<parenIndex])
        }
        return toolName
    }
}
