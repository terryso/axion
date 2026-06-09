
extension TGStreamingController {

    // MARK: - Tool Preview Helpers

    static func toolEmoji(_ toolName: String) -> String {
        let lower = toolName.lowercased()
        if lower.contains("search") || lower.contains("websearch") { return "🔍" }
        if lower.contains("bash") || lower.contains("terminal") || lower.contains("shell") { return "💻" }
        if lower.contains("reader") || lower.contains("fetch") { return "🌐" }
        if lower.contains("read") { return "📖" }
        if lower.contains("write") { return "✍️" }
        if lower.contains("vision") || lower.contains("image") { return "👁️" }
        if lower.contains("edit") { return "📝" }
        if lower.contains("screenshot") || lower.contains("screen") { return "📸" }
        return "⚙️"
    }

    static func extractToolPreview(toolName: String, input: String?) -> String? {
        guard let input, !input.isEmpty else { return nil }

        guard let json = parseJSONDict(from: input) else {
            return String(input.prefix(40))
        }

        let lower = toolName.lowercased()

        if lower.contains("search") || lower.contains("websearch") {
            if let query = json["query"] as? String { return query }
            if let q = json["q"] as? String { return q }
        }
        if lower.contains("bash") || lower.contains("terminal") || lower.contains("shell") {
            if let cmd = json["command"] as? String { return cmd }
        }
        if lower.contains("read") || lower.contains("write") || lower.contains("file")
            || lower.contains("edit") || lower.contains("glob") || lower.contains("grep") {
            if let path = json["file_path"] as? String { return path }
            if let path = json["path"] as? String { return path }
            if let pattern = json["pattern"] as? String, let path = json["path"] as? String {
                return "\(path) — \(pattern)"
            }
        }
        if lower.contains("reader") || lower.contains("url") || lower.contains("fetch") {
            if let url = json["url"] as? String { return url }
        }
        if lower.contains("vision") || lower.contains("image") || lower.contains("analyze") {
            if let prompt = json["prompt"] as? String { return String(prompt.prefix(40)) }
        }

        for (_, value) in json.sorted(by: { $0.key < $1.key }) {
            if let str = value as? String, !str.isEmpty {
                return String(str.prefix(80))
            }
        }

        return nil
    }

    static func formatToolArgument(toolName: String, input: String?) -> String? {
        guard let preview = extractToolPreview(toolName: toolName, input: input)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !preview.isEmpty else {
            return nil
        }

        let lower = toolName.lowercased()
        if lower.contains("bash") || lower.contains("terminal") || lower.contains("shell") {
            return "`\(preview)`"
        }
        if lower.contains("search") || lower.contains("websearch") {
            return "query: \(preview)"
        }
        if lower.contains("reader") || lower.contains("fetch") || lower.contains("url") {
            return "url: \(preview)"
        }
        if lower.contains("read") || lower.contains("write") || lower.contains("file")
            || lower.contains("edit") || lower.contains("glob") || lower.contains("grep") {
            return "path: \(preview)"
        }
        return preview
    }

    static func formatToolStepMessage(toolName: String, input: String?) -> String {
        let emoji = toolEmoji(toolName)
        if let argument = formatToolArgument(toolName: toolName, input: input) {
            return "\(emoji) \(toolName): \(argument)"
        }
        return "\(emoji) \(toolName)"
    }
}
