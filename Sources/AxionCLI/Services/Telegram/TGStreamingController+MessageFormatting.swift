import Foundation

extension TGStreamingController {

    // MARK: - Message Formatting

    static func normalizeQuotedTask(_ task: String?) -> String? {
        guard let task else { return nil }

        let filtered = task
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("[附件图片:")
                    && !line.hasPrefix("[用户发送了一张图片")
            }

        guard !filtered.isEmpty else { return nil }

        let joined = filtered.joined(separator: "\n")
        return String(joined.prefix(280))
    }

    static func formatQuotedFinalAnswer(task: String?, answer: String) -> String {
        guard let normalizedTask = normalizeQuotedTask(task) else {
            return answer
        }

        let quotedTask = normalizedTask
            .components(separatedBy: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n")

        return "\(quotedTask)\n\n\(answer)"
    }

    /// Summarize tool output for TG display: basic cleanup, truncate to maxLines.
    static func summarizeOutput(_ output: String, maxLines: Int = 4) -> String {
        // Tool output is raw data, not agent prose — do NOT apply stripMCPRawIO
        // (which would strip everything inside MCP I/O blocks).
        // Strip ANSI escape codes and clean up box-drawing table noise.
        let cleaned = output
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        let lines = cleaned.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isBoxDrawingBorderLine($0) }
        let truncated = lines.prefix(maxLines)
        let suffix = lines.count > maxLines ? "\n… (\(lines.count - maxLines) 行省略)" : ""
        return truncated.joined(separator: "\n") + suffix
    }

    static func isBoxDrawingBorderLine(_ line: String) -> Bool {
        let borderChars = CharacterSet(charactersIn: "─━┌┐└┘├┤┬┴┼╋┠┨┯┷╂╀╁╃╅╔╗╚╝║═╠╣╦╩╬")
        let stripped = line.unicodeScalars.filter { !borderChars.contains($0) && !CharacterSet.whitespaces.contains($0) }
        return line.unicodeScalars.contains(where: { borderChars.contains($0) }) && stripped.count <= 2
    }
}
