import Foundation

// MARK: - Shared Content Summarization Helpers
// Used by both ChatOutputFormatter and SDKTerminalOutputHandler.

/// Formats a ContinuousClock.Duration as a human-readable string (e.g. "350ms" or "1.2s").
func formatDuration(_ duration: ContinuousClock.Duration) -> String {
    let ms = durationToMs(duration)
    if ms < 1000 {
        return "\(ms)ms"
    }
    return String(format: "%.1fs", Double(ms) / 1000.0)
}

/// Summarizes JSON content by detecting skill results and success/failure status.
func summarizeContentJSON(_ content: String) -> String {
    if let json = parseJSONDict(from: content) {
        if let commandName = json["commandName"] as? String {
            return "[skill loaded: \(commandName)]"
        }
        if let success = json["success"] as? Bool {
            return "[JSON result: \(success ? "success" : "failed")]"
        }
    }
    return String(content.prefix(100)) + "…"
}

/// Detects whether a line is primarily composed of box-drawing border characters.
func isBoxDrawingBorder(_ line: String) -> Bool {
    let borderChars = CharacterSet(charactersIn: "─━┌┐└┘├┤┬┴┼╋┠┨┯┷╂╀╁╃╅╔╗╚╝║═╠╣╦╩╬")
    let nonBorder = line.unicodeScalars.filter {
        !borderChars.contains($0) && !CharacterSet.whitespaces.contains($0)
    }
    return line.unicodeScalars.contains(where: { borderChars.contains($0) }) && nonBorder.count <= 2
}

/// Summarizes tool result content, detecting screenshots, JSON results, and multi-line output.
func summarizeToolContent(_ content: String, maxLines: Int = 4) -> String {
    if content.hasPrefix("{\"action\":\"screenshot\"") || content.contains("image_data") || content.contains("[微压缩]") {
        return "[screenshot captured]"
    }
    if content.contains("Base64") || content.contains("base64") {
        return "[screenshot captured]"
    }
    if content.hasPrefix("{") && content.hasSuffix("}") {
        return summarizeContentJSON(content)
    }
    let cleaned = content.replacingOccurrences(
        of: "\u{001B}\\[[0-9;]*[A-Za-z]",
        with: "",
        options: .regularExpression
    )
    let lines = cleaned.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !isBoxDrawingBorder($0) }
    return lines.prefix(maxLines).map { line in
        line.count > 100 ? String(line.prefix(100)) + "…" : line
    }.joined(separator: "\n")
}

// MARK: - ChatOutputFormatter Extension

extension ChatOutputFormatter {

    /// Summarizes tool input JSON by extracting the most relevant parameter.
    func summarizeInput(_ input: String) -> String {
        // 尝试提取工具输入的关键参数
        guard let json = parseJSONDict(from: input) else {
            return String(input.prefix(80))
        }

        // 常见工具参数提取
        if let command = json["command"] as? String {
            return String(command.prefix(80))
        }
        if let filePath = json["file_path"] as? String {
            return String(filePath.prefix(80))
        }
        if let path = json["path"] as? String {
            return String(path.prefix(80))
        }
        if let content = json["content"] as? String {
            let preview = String(content.prefix(60))
            return "\"\(preview)…\""
        }

        // 通用：取第一个值
        if let first = json.values.first {
            let str = String(describing: first)
            return String(str.prefix(80))
        }

        return String(input.prefix(80))
    }
}
