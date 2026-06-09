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
/// Enhanced with compact JSON formatting (Codex-inspired format_json_compact).
func summarizeContentJSON(_ content: String) -> String {
    if let json = parseJSONDict(from: content) {
        if let commandName = json["commandName"] as? String {
            return "[skill loaded: \(commandName)]"
        }
        if let success = json["success"] as? Bool {
            return "[JSON result: \(success ? "success" : "failed")]"
        }
    }
    // Codex-inspired: 尝试紧凑 JSON 格式化（在 : 和 , 后加空格，提升可读性）
    if let compact = ToolOutputFormatter.formatJSONCompact(content) {
        return ToolOutputFormatter.truncateText(compact, maxLength: 120)
    }
    return ToolOutputFormatter.truncateText(content, maxLength: 120)
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
/// Enhanced with ToolOutputFormatter for compact JSON and smart truncation (Codex-inspired).
func summarizeToolContent(_ content: String, maxLines: Int = 4) -> String {
    // 委托给 ToolOutputFormatter — 统一截图检测、JSON 紧凑化、多行摘要逻辑
    return ToolOutputFormatter.formatToolResult(content, maxWidth: 120, maxLines: maxLines)
}

// MARK: - ChatOutputFormatter Extension

extension ChatOutputFormatter {

    /// Summarizes tool input JSON by extracting the most relevant parameter.
    /// Enhanced with path-aware truncation (Codex-inspired center_truncate_path)
    /// and OSC 8 hyperlinks for file paths (Codex-inspired terminal_hyperlinks).
    func summarizeInput(_ input: String) -> String {
        // 尝试提取工具输入的关键参数
        guard let json = parseJSONDict(from: input) else {
            return ToolOutputFormatter.truncateText(input, maxLength: 80)
        }

        // 常见工具参数提取 — 路径类参数使用居中截断 + OSC 8 超链接
        if let command = json["command"] as? String {
            return ToolOutputFormatter.truncateText(command, maxLength: 80)
        }
        if let filePath = json["file_path"] as? String {
            let truncated = ToolOutputFormatter.truncatePathCenter(filePath, maxWidth: 80)
            let linker = TerminalHyperlinkFormatter()
            return linker.formatFilePath(filePath, visibleText: truncated)
        }
        if let path = json["path"] as? String {
            let truncated = ToolOutputFormatter.truncatePathCenter(path, maxWidth: 80)
            let linker = TerminalHyperlinkFormatter()
            return linker.formatFilePath(path, visibleText: truncated)
        }
        if let content = json["content"] as? String {
            let preview = ToolOutputFormatter.truncateText(content, maxLength: 60)
            return "\"\(preview)\""
        }

        // 通用：取第一个值
        if let first = json.values.first {
            let str = String(describing: first)
            return ToolOutputFormatter.truncateText(str, maxLength: 80)
        }

        return ToolOutputFormatter.truncateText(input, maxLength: 80)
    }
}
