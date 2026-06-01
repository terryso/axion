import Foundation

enum TGMessageFormatter {

    // MARK: - MarkdownV2 Escape

    private static let mdV2SpecialChars: Set<Character> = [
        "_", "*", "[", "]", "(", ")", "~", "`", ">", "#", "+", "-", "=", "|", "{", "}", ".", "!", "\\"
    ]

    private static func escapeMarkdownV2(_ text: String) -> String {
        var result = String()
        result.reserveCapacity(text.count * 2)
        for char in text {
            if mdV2SpecialChars.contains(char) {
                result.append("\\")
            }
            result.append(char)
        }
        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Format

    static func format(_ text: String) -> (String, TGParseMode) {
        let formatted = renderMarkdownV2(text)
        return (formatted, .markdownV2)
    }

    static func formatAsHTML(_ text: String) -> (String, TGParseMode) {
        let formatted = renderHTML(text)
        return (formatted, .html)
    }

    static func formatAsPlain(_ text: String) -> (String, TGParseMode) {
        let formatted = renderPlain(text)
        return (formatted, .plain)
    }

    // MARK: - MarkdownV2 Rendering

    private static func renderMarkdownV2(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var inCodeBlock = false
        var codeBlockLines: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    codeBlockLines.append("```")
                    result.append(codeBlockLines.joined(separator: "\n"))
                    codeBlockLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    let lang = String(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
                    codeBlockLines = ["```" + lang]
                }
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                continue
            }

            result.append(renderLineMarkdownV2(line))
        }

        if inCodeBlock {
            // Unclosed code block — close it
            codeBlockLines.append("```")
            result.append(codeBlockLines.joined(separator: "\n"))
        }

        return result.joined(separator: "\n")
    }

    private static func renderLineMarkdownV2(_ line: String) -> String {
        // Heading: ### Title → **Title**
        if let heading = parseHeading(line) {
            return "**" + escapeMarkdownV2(heading) + "**"
        }

        if let quote = parseBlockQuote(line) {
            return "> " + renderInlineMarkdownV2(quote)
        }

        // Unordered list: - item or * item
        if let listContent = parseUnorderedList(line) {
            let indent = listContent.indent
            let content = listContent.text
            return String(repeating: "  ", count: indent) + "• " + renderInlineMarkdownV2(content)
        }

        // Ordered list: 1. item
        if let listContent = parseOrderedList(line) {
            let indent = listContent.indent
            let number = listContent.number
            let content = listContent.text
            return String(repeating: "  ", count: indent) + "\(number)\\. " + renderInlineMarkdownV2(content)
        }

        // Table row
        if isTableRow(line) {
            return renderTableRowMarkdownV2(line)
        }

        // Regular text
        return renderInlineMarkdownV2(line)
    }

    private static func renderInlineMarkdownV2(_ text: String) -> String {
        // Strategy: process text left-to-right, identifying inline patterns
        // and escaping non-pattern text. This avoids double-processing.

        var result = ""
        var i = text.startIndex

        while i < text.endIndex {
            // Check for inline code: `code`
            if text[i] == "`" {
                let closeStart = text.index(after: i)
                if let closeIdx = text.range(of: "`", range: closeStart..<text.endIndex) {
                    // Inline code: content NOT escaped, just pass through
                    result.append(contentsOf: text[i..<closeIdx.upperBound])
                    i = closeIdx.upperBound
                    continue
                } else {
                    result.append("\\`")
                    i = text.index(after: i)
                    continue
                }
            }

            // Check for bold: **text**
            if text[i] == "*" && i < text.index(before: text.endIndex) && text[text.index(after: i)] == "*" {
                let afterStars = text.index(i, offsetBy: 2)
                if let closeRange = text.range(of: "**", range: afterStars..<text.endIndex) {
                    let content = String(text[afterStars..<closeRange.lowerBound])
                    result.append("*")
                    result.append(contentsOf: escapeMarkdownV2(content))
                    result.append("*")
                    i = closeRange.upperBound
                    continue
                }
            }

            // Check for link: [label](url)
            if text[i] == "[" {
                if let closeBracket = text.range(of: "]", range: text.index(after: i)..<text.endIndex),
                   text[closeBracket.upperBound] == "(",
                   let closeParen = text.range(of: ")", range: text.index(after: closeBracket.upperBound)..<text.endIndex) {
                    let label = String(text[text.index(after: i)..<closeBracket.lowerBound])
                    let url = String(text[text.index(after: closeBracket.upperBound)..<closeParen.lowerBound])
                    result.append("[")
                    result.append(contentsOf: escapeMarkdownV2(label))
                    result.append("](")
                    result.append(contentsOf: escapeMarkdownV2(url))
                    result.append(")")
                    i = closeParen.upperBound
                    continue
                }
            }

            // Regular character — escape if special
            let char = text[i]
            if mdV2SpecialChars.contains(char) && char != "`" {
                result.append("\\")
            }
            result.append(char)
            i = text.index(after: i)
        }

        return result
    }

    // MARK: - HTML Rendering

    private static func renderHTML(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var inCodeBlock = false
        var codeBlockLines: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    let content = codeBlockLines.joined(separator: "\n")
                    result.append("<pre><code>\(escapeHTML(content))</code></pre>")
                    codeBlockLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    let _ = String(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
                    codeBlockLines = []
                }
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                continue
            }

            result.append(renderLineHTML(line))
        }

        if inCodeBlock {
            let content = codeBlockLines.joined(separator: "\n")
            result.append("<pre><code>\(escapeHTML(content))</code></pre>")
        }

        return result.joined(separator: "\n")
    }

    private static func renderLineHTML(_ line: String) -> String {
        if let heading = parseHeading(line) {
            return "<b>\(escapeHTML(heading))</b>"
        }
        if let quote = parseBlockQuote(line) {
            return "<blockquote>\(renderInlineHTML(quote))</blockquote>"
        }
        if let listContent = parseUnorderedList(line) {
            return String(repeating: "  ", count: listContent.indent) + "• " + renderInlineHTML(listContent.text)
        }
        if let listContent = parseOrderedList(line) {
            return String(repeating: "  ", count: listContent.indent) + "\(listContent.number). " + renderInlineHTML(listContent.text)
        }
        if isTableRow(line) {
            return renderTableRowHTML(line)
        }
        return renderInlineHTML(line)
    }

    private static func renderInlineHTML(_ text: String) -> String {
        // Escape HTML entities first, then wrap patterns with tags.
        // Reversing the order would escape the tags we insert.
        var result = escapeHTML(text)

        result = replacePattern(result, pattern: "`([^`]+)`") { match in
            "<code>\(match)</code>"
        }
        result = replacePattern(result, pattern: "\\*\\*(.+?)\\*\\*") { match in
            "<b>\(match)</b>"
        }
        result = replacePattern(result, pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") { label, url in
            "<a href=\"\(url)\">\(label)</a>"
        }

        return result
    }

    // MARK: - Plain Rendering

    private static func renderPlain(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var inCodeBlock = false
        var codeBlockLines: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // Indent code block
                    let content = codeBlockLines.joined(separator: "\n")
                    let indented = content.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n")
                    result.append(indented)
                    codeBlockLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    let _ = String(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
                    codeBlockLines = []
                }
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                continue
            }

            result.append(renderLinePlain(line))
        }

        if inCodeBlock {
            let content = codeBlockLines.joined(separator: "\n")
            let indented = content.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n")
            result.append(indented)
        }

        return result.joined(separator: "\n")
    }

    private static func renderLinePlain(_ line: String) -> String {
        if let heading = parseHeading(line) {
            return heading.uppercased()
        }
        if let quote = parseBlockQuote(line) {
            return "> " + stripInlineFormatting(quote)
        }
        // Keep list markers as-is for plain
        if let listContent = parseUnorderedList(line) {
            return String(repeating: "  ", count: listContent.indent) + "• " + stripInlineFormatting(listContent.text)
        }
        if let listContent = parseOrderedList(line) {
            return String(repeating: "  ", count: listContent.indent) + "\(listContent.number). " + stripInlineFormatting(listContent.text)
        }
        if isTableRow(line) {
            return renderTableRowPlain(line)
        }
        return stripInlineFormatting(line)
    }

    private static func stripInlineFormatting(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "$1: $2", options: .regularExpression)
        return result
    }

    // MARK: - Table Handling

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty && line.contains("---")
    }

    private static func parseTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let withoutBorders = trimmed.dropFirst().dropLast()
        return withoutBorders.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Split

    static func split(formattedText: String, parseMode: TGParseMode, maxRenderedLength: Int = 4096) -> [String] {
        guard formattedText.utf8.count > maxRenderedLength else { return [formattedText] }

        var chunks: [String] = []
        var remaining = formattedText[...]

        while !remaining.isEmpty {
            if remaining.utf8.count <= maxRenderedLength {
                chunks.append(String(remaining))
                break
            }

            // Walk from max UTF-8 offset backwards to find a valid String.Index
            let utf8Start = remaining.utf8.startIndex
            let utf8Target = remaining.utf8.index(utf8Start, offsetBy: maxRenderedLength)
            let cutIndex = remaining.index(utf8Target, offsetBy: 0) // clamps to nearest Character boundary
            let searchRange = remaining[..<cutIndex]

            // Try to split at paragraph boundary (double newline)
            if let paraBreak = searchRange.range(of: "\n\n", options: .backwards) {
                let splitPoint = paraBreak.upperBound
                chunks.append(String(remaining[..<paraBreak.lowerBound]))
                remaining = remaining[splitPoint...]
                continue
            }

            // Try single newline
            if let newline = searchRange.range(of: "\n", options: .backwards) {
                let splitPoint = newline.upperBound
                chunks.append(String(remaining[..<newline.lowerBound]))
                remaining = remaining[splitPoint...]
                continue
            }

            // Hard split at max length
            chunks.append(String(remaining[..<cutIndex]))
            remaining = remaining[cutIndex...]
        }

        // Ensure each chunk is independently renderable (balance code blocks)
        return balanceCodeBlocks(chunks)
    }

    private static func balanceCodeBlocks(_ chunks: [String]) -> [String] {
        var result: [String] = []
        var insideCodeBlock = false

        for chunk in chunks {
            var current = chunk

            if insideCodeBlock {
                // This chunk continues a code block — prepend opening fence
                current = "```\n" + current
            }

            // Count net fence state after potential prepend
            let adjustedFenceCount = current.components(separatedBy: "```").count - 1
            if adjustedFenceCount % 2 != 0 {
                // Odd number — unclosed code block at end of chunk
                if !current.hasSuffix("\n") { current += "\n" }
                current += "```"
                insideCodeBlock = true
            } else {
                insideCodeBlock = false
            }

            result.append(current)
        }

        return result
    }

    // MARK: - Parsing Helpers

    private struct ListContent {
        let indent: Int
        let text: String
    }

    private struct OrderedListContent {
        let indent: Int
        let number: Int
        let text: String
    }

    private static func parseHeading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var hashCount = 0
        for char in trimmed {
            if char == "#" { hashCount += 1 } else { break }
        }
        guard hashCount > 0, hashCount <= 6 else { return nil }
        let content = String(trimmed.dropFirst(hashCount)).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return content
    }

    private static func parseBlockQuote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return content
    }

    private static func parseUnorderedList(_ line: String) -> ListContent? {
        let trimmed = line // preserve leading spaces for indent calculation
        var spaces = 0
        for char in trimmed {
            if char == " " { spaces += 1 } else { break }
        }
        let indent = spaces / 2
        let afterSpaces = String(trimmed.dropFirst(spaces))
        if afterSpaces.hasPrefix("- ") || afterSpaces.hasPrefix("* ") {
            return ListContent(indent: indent, text: String(afterSpaces.dropFirst(2)))
        }
        return nil
    }

    private static func parseOrderedList(_ line: String) -> OrderedListContent? {
        var spaces = 0
        for char in line {
            if char == " " { spaces += 1 } else { break }
        }
        let indent = spaces / 2
        let afterSpaces = String(line.dropFirst(spaces))

        // Match: 1. text
        let pattern = /^(\d+)\.\s(.+)/
        guard let match = afterSpaces.firstMatch(of: pattern),
              let number = Int(match.1) else { return nil }
        return OrderedListContent(indent: indent, number: number, text: String(match.2))
    }

    // MARK: - Regex Helpers

    private static func replacePattern(_ text: String, pattern: String, handler: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let captured = String(text[range])
            let fullRange = Range(match.range, in: text)!
            result.replaceSubrange(fullRange, with: handler(captured))
        }
        return result
    }

    private static func replacePattern(_ text: String, pattern: String, handler: (String, String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        var result = text
        for match in matches.reversed() {
            guard let range1 = Range(match.range(at: 1), in: text),
                  let range2 = Range(match.range(at: 2), in: text) else { continue }
            let captured1 = String(text[range1])
            let captured2 = String(text[range2])
            let fullRange = Range(match.range, in: text)!
            result.replaceSubrange(fullRange, with: handler(captured1, captured2))
        }
        return result
    }

    private static func renderTableRowMarkdownV2(_ line: String) -> String {
        let cells = parseTableRow(line)
        if isTableSeparator(line) { return "" }
        guard cells.count >= 2 else { return escapeMarkdownV2(line) }
        let key = cells[0]
        let value = cells.dropFirst().joined(separator: " | ")
        return "**\(escapeMarkdownV2(key))**: \(escapeMarkdownV2(value))"
    }

    private static func renderTableRowHTML(_ line: String) -> String {
        let cells = parseTableRow(line)
        if isTableSeparator(line) { return "" }
        guard cells.count >= 2 else { return escapeHTML(line) }
        let key = cells[0]
        let value = cells.dropFirst().joined(separator: " | ")
        return "<b>\(escapeHTML(key))</b>: \(escapeHTML(value))"
    }

    private static func renderTableRowPlain(_ line: String) -> String {
        let cells = parseTableRow(line)
        if isTableSeparator(line) { return "" }
        guard cells.count >= 2 else { return line }
        let key = cells[0]
        let value = cells.dropFirst().joined(separator: " | ")
        return "\(key): \(value)"
    }
}
