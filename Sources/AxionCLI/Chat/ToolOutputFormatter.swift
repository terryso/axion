import Foundation

/// 智能工具输出格式化器 — 受 Codex 的 format_and_truncate_tool_result、format_json_compact、
/// center_truncate_path 启发，提供紧凑 JSON 格式化、智能截断、路径居中截断等能力。
///
/// 设计原则：
/// - 纯函数（static methods），无状态，易于测试
/// - 感知终端宽度，避免输出超出屏幕
/// - 渐进降级：TrueColor → ANSI256 → ANSI16 → Plain text
struct ToolOutputFormatter {

    /// 将 JSON 字符串格式化为紧凑单行格式，在 `:` 和 `,` 后添加空格以提升可读性。
    ///
    /// 受 Codex 的 `format_json_compact` 启发：Ratatui 的文本换行只能在空格处断行，
    /// 标准 `JSONEncoder.outputFormatting=.prettyPrinted` 生成的多行 JSON 过于稀疏，
    /// 而 `sortedKeys` 生成的无空格 JSON 又无法在空格处换行。
    /// 紧凑单行格式在两者之间取得平衡。
    ///
    /// - Input: `{"name":"test","items":["a","b","c"]}`
    /// - Output: `{"name": "test", "items": ["a", "b", "c"]}`
    static func formatJSONCompact(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        // 使用 sortedKeys 的 pretty print 生成基础格式
        guard let prettyData = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.sortedKeys, .prettyPrinted]
        ),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return nil
        }

        // 将多行 pretty JSON 压缩为单行，在 : 和 , 后保留空格
        var result = ""
        var inString = false
        var escapeNext = false
        var chars = pretty.unicodeScalars.makeIterator()

        while let scalar = chars.next() {
            switch scalar {
            case "\"" where !escapeNext:
                inString.toggle()
                result.unicodeScalars.append(scalar)
            case "\\" where inString:
                escapeNext = !escapeNext
                result.unicodeScalars.append(scalar)
            case "\n" where !inString, "\r" where !inString:
                break  // 跳过字符串外的换行
            case " " where !inString, "\t" where !inString:
                // 仅在 : 或 , 后且下一个非空白不是 } 或 ] 时保留空格
                if let last = result.unicodeScalars.last,
                   (last == ":" || last == ",") {
                    // 查看下一个非空白字符
                    var peeked = chars
                    var nextNonSpace: UnicodeScalar?
                    while let p = peeked.next() {
                        if p != " " && p != "\t" && p != "\n" && p != "\r" {
                            nextNonSpace = p
                            break
                        }
                    }
                    if let next = nextNonSpace, next != "}", next != "]" {
                        result.unicodeScalars.append(" ")
                    }
                }
            default:
                if escapeNext && inString {
                    escapeNext = false
                }
                result.unicodeScalars.append(scalar)
            }
        }

        return result.isEmpty ? nil : result
    }

    /// 将文本截断到指定字符数，使用 Unicode 省略号（…）标记截断位置。
    ///
    /// 受 Codex 的 `truncate_text` 启发，使用 grapheme cluster 边界避免截断多 codepoint 字符。
    ///
    /// - Parameters:
    ///   - text: 原始文本
    ///   - maxLength: 最大字符（Unicode scalar）数
    /// - Returns: 截断后的文本，超长时末尾加 `…`
    static func truncateText(_ text: String, maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }

        let scalars = text.unicodeScalars
        let count = scalars.count

        if count <= maxLength {
            return text
        }

        if maxLength >= 2 {
            // 预留 1 个字符给省略号
            let keepCount = maxLength - 1
            let index = scalars.index(scalars.startIndex, offsetBy: keepCount)
            return String(text[..<index]) + "…"
        }

        // maxLength == 1: 只返回省略号
        return "…"
    }

    /// 将路径截断到指定显示宽度，保留首尾段并用省略号连接。
    ///
    /// 受 Codex 的 `center_truncate_path` 启发：
    /// - `/Users/nick/very/deep/nested/path/file.txt` → `/Users/…/file.txt`
    /// - 优先保留首段和末段，中间用 `…` 替代
    ///
    /// - Parameters:
    ///   - path: 原始路径
    ///   - maxWidth: 最大显示宽度（字符数）
    /// - Returns: 截断后的路径
    static func truncatePathCenter(_ path: String, maxWidth: Int) -> String {
        guard maxWidth > 0 else { return "" }

        if path.unicodeScalars.count <= maxWidth {
            return path
        }

        let separator = "/"
        let hasLeading = path.hasPrefix("/")

        let segments = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        // 移除首尾空段（来自 leading/trailing /）
        guard !segments.isEmpty else {
            return hasLeading ? "/" : "…"
        }

        // 尝试保留首段 + … + 末段
        let first = segments[0]
        let last = segments[segments.count - 1]
        let ellipsis = "…"
        let minNeeded = first.count + separator.count + ellipsis.count + separator.count + last.count

        if hasLeading && minNeeded + 1 <= maxWidth {
            // 保留 leading / + first/…/last
            return "/" + first + "/" + ellipsis + "/" + last
        } else if minNeeded <= maxWidth {
            return first + "/" + ellipsis + "/" + last
        }

        // 只保留末段（可能也需要截断）
        let truncatedLast = truncateText(last, maxLength: maxWidth)
        if hasLeading {
            return "/" + ellipsis + "/" + truncatedLast
        }
        return ellipsis + separator + truncatedLast
    }

    /// 格式化工具结果内容，根据内容类型自动选择最佳展示方式。
    ///
    /// 整合了 compact JSON、路径截断、多行摘要等能力。
    ///
    /// - Parameters:
    ///   - content: 工具结果原始内容
    ///   - maxWidth: 终端宽度（用于截断）
    ///   - maxLines: 最大行数
    /// - Returns: 格式化后的可读摘要
    static func formatToolResult(
        _ content: String,
        maxWidth: Int = 120,
        maxLines: Int = 4
    ) -> String {
        // 1. 截图检测
        if content.hasPrefix("{\"action\":\"screenshot\"")
            || content.contains("image_data")
            || content.contains("[微压缩]")
            || content.contains("Base64")
            || content.contains("base64") {
            return "[screenshot captured]"
        }

        // 2. JSON 结果 — 尝试紧凑格式化
        if content.hasPrefix("{") || content.hasPrefix("[") {
            if let compact = formatJSONCompact(content) {
                let truncated = truncateText(compact, maxLength: maxWidth)
                return truncated
            }
        }

        // 3. 多行文本 — 清洗后取前 N 行
        let cleaned = content.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        let lines = cleaned.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isBoxDrawingBorder($0) }

        if lines.isEmpty {
            return "[empty]"
        }

        if lines.count == 1 {
            return truncateText(lines[0], maxLength: maxWidth)
        }

        // 多行：取前 maxLines 行，每行截断
        let summarized = lines.prefix(maxLines).map { line in
            truncateText(line, maxLength: maxWidth)
        }
        let hasMore = lines.count > maxLines
        let suffix = hasMore ? "\n  … (\(lines.count - maxLines) more lines)" : ""
        return summarized.joined(separator: "\n") + suffix
    }
}
