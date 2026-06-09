
// MARK: - Table Handling

extension TGMessageFormatter {

    enum RenderMode {
        case markdownV2, html, plain
    }

    static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty && line.contains("---")
    }

    static func parseTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let withoutBorders = trimmed.dropFirst().dropLast()
        return withoutBorders.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Detects a contiguous block of table rows starting at startIndex.
    /// Returns the parsed rows (excluding separator lines) and the index after the block.
    /// Returns nil if there are fewer than 2 non-separator data rows (not a multi-row table block).
    static func detectTableBlock(lines: [String], startIndex: Int) -> (rows: [[String]], endIndex: Int)? {
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

    static let boxDrawingChars: Set<Character> = [
        "─", "━", "│", "┃", "┌", "┐", "└", "┘",
        "├", "┤", "┬", "┴", "┼", "╋", "┠", "┨",
        "┯", "┷", "╂", "╀", "╁", "╃", "╅",
        "╔", "╗", "╚", "╝", "║", "═",
        "╠", "╣", "╦", "╩", "╬"
    ]

    static func isBoxDrawingBorder(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.hasPrefix("┌") || trimmed.hasPrefix("└")
    }

    static func isBoxDrawingSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.hasPrefix("├") || trimmed.hasPrefix("╠");
    }

    static func isBoxDrawingRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("│") || trimmed.hasPrefix("┃") || trimmed.hasPrefix("║") else { return false }
        guard trimmed.hasSuffix("│") || trimmed.hasSuffix("┃") || trimmed.hasSuffix("║") else { return false }
        return trimmed.count >= 3
    }

    static func parseBoxDrawingRow(_ line: String) -> [String] {
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

    static func detectBoxDrawingTable(lines: [String], startIndex: Int) -> (rows: [[String]], endIndex: Int)? {
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
    static func displayWidth(_ string: String) -> Int {
        var width = 0
        for scalar in string.unicodeScalars {
            if scalar.properties.isDefaultIgnorableCodePoint { continue }
            width += isWideScalar(scalar) ? 2 : 1
        }
        return width
    }

    static func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
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
    static func padToWidth(_ string: String, targetWidth: Int) -> String {
        let currentWidth = displayWidth(string)
        let padding = max(0, targetWidth - currentWidth)
        return string + String(repeating: " ", count: padding)
    }

    /// Renders a table block as space-aligned text in a code block (Hermes-style).
    /// No pipe separators — columns aligned by display width.
    static func renderTableBlock(rows: [[String]], mode: RenderMode) -> String {
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
    static func stripInlineMarkdown(_ text: String) -> String {
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
}
