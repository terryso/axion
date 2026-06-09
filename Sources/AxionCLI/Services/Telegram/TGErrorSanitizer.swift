import Foundation

enum TGErrorSanitizer {

    static func sanitizeForTelegramError(_ raw: String) -> String {
        var result = raw

        // Redact API keys (sk-..., key=..., api_key=...)
        result = result.replacingOccurrences(
            of: "sk-[a-zA-Z0-9_\\-]{20,}",
            with: "[REDACTED_KEY]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?:api_key|apikey|key|token|secret)\\s*[=: ]+\\s*[a-zA-Z0-9_\\-]{8,}",
            with: "[REDACTED]",
            options: .regularExpression,
            range: nil
        )
        result = result.replacingOccurrences(
            of: "Bearer [a-zA-Z0-9_\\-\\.]{10,}",
            with: "[REDACTED_TOKEN]",
            options: .regularExpression
        )

        // Strip file system paths — keep only last component
        if let pathRegex = try? NSRegularExpression(pattern: "/(?:Users|home|var|tmp|etc|opt|usr)/[^\\s:]+", options: []) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let pathMatches = pathRegex.matches(in: result, range: nsRange)
            for match in pathMatches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let fullPath = String(result[range])
                let components = fullPath.split(separator: "/")
                let lastComponent = components.last.map { "/...\($0)" } ?? fullPath
                result.replaceSubrange(range, with: lastComponent)
            }
        }

        // Truncate stack traces — keep first line only
        let lines = result.components(separatedBy: "\n")
        var filtered: [String] = []
        var inStack = false
        for line in lines {
            if line.hasPrefix("  at ") || line.hasPrefix("\tat ") || line.hasPrefix("Stack:") {
                if !inStack {
                    filtered.append("  [...stack trace truncated]")
                    inStack = true
                }
                continue
            }
            if line.hasPrefix("Traceback") || line.hasPrefix("Fatal error") {
                if !inStack {
                    filtered.append(line)
                    inStack = true
                }
                continue
            }
            inStack = false
            filtered.append(line)
        }
        result = filtered.joined(separator: "\n")

        // Extract error message from HTTP JSON body
        if let json = parseJSONDict(from: result) {
            if let errorMsg = json["error"] as? [String: Any], let message = errorMsg["message"] as? String {
                result = message
            } else if let description = json["description"] as? String {
                result = description
            } else if let message = json["message"] as? String {
                result = message
            }
        }

        // Map common patterns to user-friendly Chinese summaries
        result = mapToFriendlyMessage(result)

        // Truncate if still too long for Telegram
        if result.count > 800 {
            result = String(result.prefix(800)) + "..."
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mapToFriendlyMessage(_ message: String) -> String {
        let lower = message.lowercased()

        if lower.contains("authentication") || lower.contains("unauthorized") || lower.contains("401") || lower.contains("invalid api key") {
            return "认证失败，请检查 API Key 配置"
        }
        if lower.contains("rate limit") || lower.contains("429") || lower.contains("too many requests") {
            return "请求过于频繁，请稍后重试"
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return "命令执行超时"
        }
        if lower.contains("connection") && (lower.contains("refused") || lower.contains("reset") || lower.contains("failed")) {
            return "网络连接失败，请检查网络"
        }
        if lower.contains("not found") || lower.contains("404") {
            return "请求的资源不存在"
        }
        if lower.contains("forbidden") || lower.contains("403") {
            return "权限不足，无法执行此操作"
        }
        if lower.contains("internal server error") || lower.contains("500") {
            return "服务器内部错误，请稍后重试"
        }
        if lower.contains("bad request") || lower.contains("400") {
            return "请求格式错误"
        }

        return message
    }
}
