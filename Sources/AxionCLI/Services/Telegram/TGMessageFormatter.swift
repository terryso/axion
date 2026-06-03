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

    private static func stripANSIEscapeCodes(_ text: String) -> String {
        let pattern = "\u{001B}\\[[0-9;]*[A-Za-z]"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    // MARK: - Format

    static func format(_ text: String) -> (String, TGParseMode) {
        let cleaned = stripANSIEscapeCodes(text)
        let formatted = renderMarkdownV2(cleaned)
        return (formatted, .markdownV2)
    }

    static func formatAsHTML(_ text: String) -> (String, TGParseMode) {
        let cleaned = stripANSIEscapeCodes(text)
        let formatted = renderHTML(cleaned)
        return (formatted, .html)
    }

    static func formatAsPlain(_ text: String) -> (String, TGParseMode) {
        let cleaned = stripANSIEscapeCodes(text)
        let formatted = renderPlain(cleaned)
        return (formatted, .plain)
    }

    // MARK: - MarkdownV2 Rendering

    private static func renderMarkdownV2(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var inCodeBlock = false
        var codeBlockLines: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

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
                i += 1
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                i += 1
                continue
            }

            // Try block-level table detection: only for 3+ column tables
            if isTableRow(line) {
                if let block = detectTableBlock(lines: lines, startIndex: i) {
                    let colCount = block.rows.first?.count ?? 0
                    if colCount >= 3 {
                        result.append(renderTableBlock(rows: block.rows, mode: .markdownV2))
                        i = block.endIndex
                        continue
                    }
                    // 2-column table: fall through to per-line key/value (preserves bold)
                }
            }

            // Try Unicode box-drawing table detection
            if isBoxDrawingBorder(line) || isBoxDrawingRow(line) {
                if let block = detectBoxDrawingTable(lines: lines, startIndex: i) {
                    let colCount = block.rows.first?.count ?? 0
                    if colCount >= 3 {
                        result.append(renderTableBlock(rows: block.rows, mode: .markdownV2))
                        i = block.endIndex
                        continue
                    }
                    // 2-column: render as key/value
                    for row in block.rows {
                        let key = row.first ?? ""
                        let value = row.count > 1 ? row[1] : ""
                        result.append("**" + escapeMarkdownV2(key) + "**: " + escapeMarkdownV2(value))
                    }
                    i = block.endIndex
                    continue
                }
            }

            result.append(renderLineMarkdownV2(line))
            i += 1
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
            let afterCurrent = text.index(after: i)
            if text[i] == "*" && afterCurrent < text.endIndex && text[afterCurrent] == "*" {
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
                   closeBracket.upperBound < text.endIndex && text[closeBracket.upperBound] == "(",
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
        var i = 0

        while i < lines.count {
            let line = lines[i]

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
                i += 1
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                i += 1
                continue
            }

            // Try block-level table detection: only for 3+ column tables
            if isTableRow(line) {
                if let block = detectTableBlock(lines: lines, startIndex: i) {
                    let colCount = block.rows.first?.count ?? 0
                    if colCount >= 3 {
                        result.append(renderTableBlock(rows: block.rows, mode: .html))
                        i = block.endIndex
                        continue
                    }
                }
            }

            // Try Unicode box-drawing table detection
            if isBoxDrawingBorder(line) || isBoxDrawingRow(line) {
                if let block = detectBoxDrawingTable(lines: lines, startIndex: i) {
                    let colCount = block.rows.first?.count ?? 0
                    if colCount >= 3 {
                        result.append(renderTableBlock(rows: block.rows, mode: .html))
                        i = block.endIndex
                        continue
                    }
                    for row in block.rows {
                        let key = row.first ?? ""
                        let value = row.count > 1 ? row[1] : ""
                        result.append("<b>\(escapeHTML(key))</b>: \(escapeHTML(value))")
                    }
                    i = block.endIndex
                    continue
                }
            }

            result.append(renderLineHTML(line))
            i += 1
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
        var i = 0

        while i < lines.count {
            let line = lines[i]

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
                i += 1
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                i += 1
                continue
            }

            // Try block-level table detection: only for 3+ column tables
            if isTableRow(line) {
                if let block = detectTableBlock(lines: lines, startIndex: i) {
                    let colCount = block.rows.first?.count ?? 0
                    if colCount >= 3 {
                        result.append(renderTableBlock(rows: block.rows, mode: .plain))
                        i = block.endIndex
                        continue
                    }
                }
            }

            // Try Unicode box-drawing table detection
            if isBoxDrawingBorder(line) || isBoxDrawingRow(line) {
                if let block = detectBoxDrawingTable(lines: lines, startIndex: i) {
                    let colCount = block.rows.first?.count ?? 0
                    if colCount >= 3 {
                        result.append(renderTableBlock(rows: block.rows, mode: .plain))
                        i = block.endIndex
                        continue
                    }
                    for row in block.rows {
                        let key = row.first ?? ""
                        let value = row.count > 1 ? row[1] : ""
                        result.append("\(key): \(value)")
                    }
                    i = block.endIndex
                    continue
                }
            }

            result.append(renderLinePlain(line))
            i += 1
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

    private enum RenderMode {
        case markdownV2, html, plain
    }

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

    /// Detects a contiguous block of table rows starting at startIndex.
    /// Returns the parsed rows (excluding separator lines) and the index after the block.
    /// Returns nil if there are fewer than 2 non-separator data rows (not a multi-row table block).
    private static func detectTableBlock(lines: [String], startIndex: Int) -> (rows: [[String]], endIndex: Int)? {
        var dataRows: [[String]] = []
        var hasSeenSeparator = false
        var lastDataRowLineIndex = startIndex
        var i = startIndex

        while i < lines.count {
            let line = lines[i]
            if isTableRow(line) {
                if isTableSeparator(line) {
                    if hasSeenSeparator {
                        // Second separator — signals a new table boundary.
                        // The last data row before this separator is the new table's header.
                        dataRows.removeLast()
                        return dataRows.count >= 2 ? (rows: dataRows, endIndex: lastDataRowLineIndex) : nil
                    }
                    hasSeenSeparator = true
                } else {
                    dataRows.append(parseTableRow(line))
                    lastDataRowLineIndex = i
                }
                i += 1
            } else {
                break
            }
        }

        guard dataRows.count >= 2 else { return nil }
        return (rows: dataRows, endIndex: i)
    }

    // MARK: - Unicode Box-Drawing Table Detection

    private static let boxDrawingChars: Set<Character> = [
        "─", "━", "│", "┃", "┌", "┐", "└", "┘",
        "├", "┤", "┬", "┴", "┼", "╋", "┠", "┨",
        "┯", "┷", "╂", "╀", "╁", "╃", "╅",
        "╔", "╗", "╚", "╝", "║", "═",
        "╠", "╣", "╦", "╩", "╬"
    ]

    private static func isBoxDrawingBorder(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.hasPrefix("┌") || trimmed.hasPrefix("└")
    }

    private static func isBoxDrawingSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.hasPrefix("├") || trimmed.hasPrefix("╠");
    }

    private static func isBoxDrawingRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("│") || trimmed.hasPrefix("┃") || trimmed.hasPrefix("║") else { return false }
        guard trimmed.hasSuffix("│") || trimmed.hasSuffix("┃") || trimmed.hasSuffix("║") else { return false }
        return trimmed.count >= 3
    }

    private static func parseBoxDrawingRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let withoutBorders = String(trimmed.dropFirst().dropLast())
        var cells: [String] = []
        var current = ""
        for char in withoutBorders {
            if boxDrawingChars.contains(char) {
                let cell = current.trimmingCharacters(in: .whitespaces)
                if !cell.isEmpty { cells.append(cell) }
                current = ""
            } else {
                current.append(char)
            }
        }
        let lastCell = current.trimmingCharacters(in: .whitespaces)
        if !lastCell.isEmpty { cells.append(lastCell) }
        return cells
    }

    private static func detectBoxDrawingTable(lines: [String], startIndex: Int) -> (rows: [[String]], endIndex: Int)? {
        var dataRows: [[String]] = []
        var i = startIndex

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                // blank line could be part of table block or end of it
                if dataRows.isEmpty { i += 1; continue }
                break
            }

            if isBoxDrawingBorder(line) || isBoxDrawingSeparator(line) {
                // top/bottom border or separator — skip
                i += 1
                continue
            }

            if isBoxDrawingRow(line) {
                dataRows.append(parseBoxDrawingRow(line))
                i += 1
                continue
            }

            // Not a box-drawing line — end of table
            break
        }

        guard dataRows.count >= 2 else { return nil }
        return (rows: dataRows, endIndex: i)
    }

    /// Monospace display width: CJK/wide chars = 2, ASCII/narrow = 1
    private static func displayWidth(_ string: String) -> Int {
        var width = 0
        for scalar in string.unicodeScalars {
            if scalar.properties.isDefaultIgnorableCodePoint { continue }
            width += isWideScalar(scalar) ? 2 : 1
        }
        return width
    }

    private static func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        // CJK Unified Ideographs
        if v >= 0x4E00 && v <= 0x9FFF { return true }
        // CJK Extension A
        if v >= 0x3400 && v <= 0x4DBF { return true }
        // CJK Compatibility Ideographs
        if v >= 0xF900 && v <= 0xFAFF { return true }
        // CJK Radicals / Kangxi
        if v >= 0x2E80 && v <= 0x2FDF { return true }
        // CJK Symbols, Hiragana, Katakana
        if v >= 0x3000 && v <= 0x33FF { return true }
        // Hangul Syllables
        if v >= 0xAC00 && v <= 0xD7AF { return true }
        // Fullwidth Forms
        if v >= 0xFF01 && v <= 0xFF60 { return true }
        // CJK Compatibility Forms
        if v >= 0xFE30 && v <= 0xFE4F { return true }
        // Emoji ranges (common ones that render wide in monospace)
        if scalar.properties.isEmoji && v > 0x1F000 { return true }
        return false
    }

    /// Pads a string with trailing spaces so its display width equals targetWidth.
    private static func padToWidth(_ string: String, targetWidth: Int) -> String {
        let currentWidth = displayWidth(string)
        let padding = max(0, targetWidth - currentWidth)
        return string + String(repeating: " ", count: padding)
    }

    /// Renders a table block as space-aligned text in a code block (Hermes-style).
    /// No pipe separators — columns aligned by display width.
    private static func renderTableBlock(rows: [[String]], mode: RenderMode) -> String {
        let columnCount = rows.map { $0.count }.max() ?? 0
        guard columnCount > 0 else { return "" }

        let paddedRows = rows.map { row -> [String] in
            var padded = row.map { stripInlineMarkdown($0) }
            while padded.count < columnCount { padded.append("") }
            return padded
        }

        var columnWidths = Array(repeating: 0, count: columnCount)
        for row in paddedRows {
            for (col, cell) in row.enumerated() {
                columnWidths[col] = max(columnWidths[col], displayWidth(cell))
            }
        }

        let alignedLines = paddedRows.map { row in
            row.enumerated().map { (col, cell) in
                padToWidth(cell, targetWidth: columnWidths[col])
            }.joined(separator: "  ")
        }

        let alignedText = alignedLines.joined(separator: "\n")

        switch mode {
        case .markdownV2:
            return "```\n\(alignedText)\n```"
        case .html:
            return "<pre><code>\(escapeHTML(alignedText))</code></pre>"
        case .plain:
            return alignedText.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n")
        }
    }

    /// Strip markdown inline formatting markers that won't render inside code blocks.
    private static func stripInlineMarkdown(_ text: String) -> String {
        // Bold: **text** or __text__
        // Italic: *text* or _text_
        // Strikethrough: ~~text~~
        // Code: `text`
        // Links: [text](url)
        var result = text
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "__(.+?)__", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "_(.+?)_", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "~~(.+?)~~", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "`(.+?)`", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[(.+?)\\]\\(.+?\\)", with: "$1", options: .regularExpression)
        return result
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
                // Check that this doesn't split inside a code block
                let beforeBreak = String(remaining[..<paraBreak.lowerBound])
                if !isInsideCodeBlock(at: beforeBreak) {
                    chunks.append(beforeBreak)
                    remaining = remaining[paraBreak.upperBound...]
                    continue
                }
            }

            // Try single newline
            if let newline = searchRange.range(of: "\n", options: .backwards) {
                // Check that this doesn't split inside a code block
                let beforeNewline = String(remaining[..<newline.lowerBound])
                if !isInsideCodeBlock(at: beforeNewline) {
                    chunks.append(beforeNewline)
                    remaining = remaining[newline.upperBound...]
                    continue
                }
            }

            // Hard split at max length
            chunks.append(String(remaining[..<cutIndex]))
            remaining = remaining[cutIndex...]
        }

        // Ensure each chunk is independently renderable (balance code blocks)
        return balanceCodeBlocks(chunks)
    }

    /// Returns true if the text ends inside a code block (odd number of ``` fences).
    private static func isInsideCodeBlock(at text: String) -> Bool {
        let fenceCount = text.components(separatedBy: "```").count - 1
        return fenceCount % 2 != 0
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
