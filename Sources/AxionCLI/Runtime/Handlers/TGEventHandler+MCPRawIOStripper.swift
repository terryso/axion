import Foundation

// MARK: - MCP Raw IO Stripping
//
// Stateless text-processing utilities that detect and remove raw MCP tool I/O
// blocks (Input/Output/Executing sections) from agent response text, preserving
// only the narrative prose and [结果] summary lines.

extension TGEventHandler {

    /// Strips raw MCP tool I/O sections from text.
    /// Detects blocks by "Input:" marker and strips the preceding header + entire I/O section.
    static func stripMCPRawIO(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var cleanedLines: [String] = []
        var index = 0
        var phase: MCPBlockPhase?
        var sawOutputSeparator = false

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let markerRange = line.range(of: "Built-in Tool:"), isLikelyMCPHeader(in: lines, at: index) {
                let prefix = preservedProsePrefix(before: markerRange.lowerBound, in: line)
                if !prefix.isEmpty {
                    cleanedLines.append(prefix)
                }
                phase = .header
                sawOutputSeparator = false
                index += 1
                continue
            }

            if phase == nil, isLikelyMCPInputStart(in: lines, at: index) {
                phase = .input
                sawOutputSeparator = false
                index += 1
                continue
            }

            guard let currentPhase = phase else {
                cleanedLines.append(line)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                if currentPhase == .output {
                    sawOutputSeparator = true
                }
                index += 1
                continue
            }

            if isExecutingLine(trimmed) {
                index += 1
                continue
            }

            if isInputHeader(trimmed) {
                phase = .input
                sawOutputSeparator = false
                index += 1
                continue
            }

            if isOutputHeader(trimmed) {
                phase = .output
                sawOutputSeparator = false
                index += 1
                continue
            }

            if currentPhase == .output,
               sawOutputSeparator,
               (trimmed.hasPrefix("[结果]") || isLikelyNarrativeLine(trimmed) || isTerminalContentLine(in: lines, at: index)) {
                phase = nil
                sawOutputSeparator = false
                continue
            }

            if isToolResultLine(trimmed) || isStructuredPayloadLine(trimmed) {
                index += 1
                continue
            }

            if trimmed.hasPrefix("[结果]") {
                phase = nil
                sawOutputSeparator = false
                continue
            }

            switch currentPhase {
            case .header:
                index += 1
            case .output:
                if sawOutputSeparator, (isLikelyNarrativeLine(trimmed) || isTerminalContentLine(in: lines, at: index)) {
                    phase = nil
                    sawOutputSeparator = false
                    continue
                }
                index += 1
            case .input:
                index += 1
            }
        }

        var cleaned = cleanedLines.joined(separator: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Phase Tracking

    enum MCPBlockPhase {
        case header
        case input
        case output
    }

    // MARK: - Detection Helpers

    static func isLikelyMCPInputStart(in lines: [String], at index: Int) -> Bool {
        guard index < lines.count else { return false }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard isInputHeader(trimmed) else { return false }

        let lookaheadEnd = min(index + 40, lines.count - 1)
        guard lookaheadEnd > index else { return false }

        for candidateIndex in (index + 1)...lookaheadEnd {
            let candidate = lines[candidateIndex].trimmingCharacters(in: .whitespaces)
            if candidate.contains("Built-in Tool:") { return true }
            if isExecutingLine(candidate) { return true }
            if isOutputHeader(candidate) { return true }
            if isToolResultLine(candidate) { return true }
        }

        return false
    }

    static func isLikelyMCPHeader(in lines: [String], at index: Int) -> Bool {
        guard index < lines.count else { return false }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("Built-in Tool:") else { return false }
        if trimmed.contains("Z.ai") { return true }

        let lookaheadEnd = min(index + 20, lines.count - 1)
        guard lookaheadEnd > index else { return false }

        for candidateIndex in (index + 1)...lookaheadEnd {
            let candidate = lines[candidateIndex].trimmingCharacters(in: .whitespaces)
            if isInputHeader(candidate) || isOutputHeader(candidate) || isExecutingLine(candidate) || isToolResultLine(candidate) {
                return true
            }
        }

        return false
    }

    static func isInputHeader(_ line: String) -> Bool {
        normalizedMCPMarkerLine(line).hasPrefix("Input:")
    }

    static func isOutputHeader(_ line: String) -> Bool {
        normalizedMCPMarkerLine(line).hasPrefix("Output:")
    }

    static func isExecutingLine(_ line: String) -> Bool {
        normalizedMCPMarkerLine(line).contains("Executing on server...")
    }

    static func isStructuredPayloadLine(_ line: String) -> Bool {
        guard !line.hasPrefix("[结果]") else { return false }
        if line.hasPrefix("{") || line.hasPrefix("}") { return true }
        if line == "[]" || line == "{}" { return true }
        if line.hasPrefix("[") && (line.contains(":") || line.hasSuffix("]")) { return true }
        if line.hasPrefix("]") { return true }
        if line.hasPrefix("\"") || line == "true" || line == "false" || line == "null" { return true }
        if Double(line) != nil { return true }
        if line.hasPrefix("```") { return true }
        return false
    }

    static func isToolResultLine(_ line: String) -> Bool {
        let normalized = normalizedMCPMarkerLine(line)
        if normalized.contains("_result_summary:") { return true }
        if normalized.contains("_result:") { return true }
        return false
    }

    static func normalizedMCPMarkerLine(_ line: String) -> String {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func preservedProsePrefix(before boundary: String.Index, in line: String) -> String {
        let trimmed = String(line[..<boundary]).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        if let punctuationIndex = trimmed.lastIndex(where: { "。！？!?".contains($0) }) {
            return String(trimmed[...punctuationIndex]).trimmingCharacters(in: .whitespaces)
        }

        if trimmed.contains("Z.ai") || trimmed.count <= 12 {
            return ""
        }

        return trimmed
    }

    static func isLikelyNarrativeLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        if line.hasPrefix("[结果]") { return true }
        if line.hasPrefix("#") || line.hasPrefix("- ") || line.hasPrefix("* ") { return true }

        let narrativePunctuation = CharacterSet(charactersIn: "，。：；！？!?")
        if line.rangeOfCharacter(from: narrativePunctuation) != nil {
            return true
        }

        let letterScalars = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return letterScalars.count >= 12
    }

    static func isTerminalContentLine(in lines: [String], at index: Int) -> Bool {
        guard index < lines.count else { return false }
        for candidateIndex in (index + 1)..<lines.count {
            if !lines[candidateIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
        }
        return true
    }
}
