
// MARK: - MarkdownV2 Rendering

extension TGMessageFormatter {

    static func renderMarkdownV2(_ text: String) -> String {
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

    static func renderLineMarkdownV2(_ line: String) -> String {
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

    static func renderInlineMarkdownV2(_ text: String) -> String {
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

    static func renderTableRowMarkdownV2(_ line: String) -> String {
        let cells = parseTableRow(line)
        if isTableSeparator(line) { return "" }
        guard cells.count >= 2 else { return escapeMarkdownV2(line) }
        let key = cells[0]
        let value = cells.dropFirst().joined(separator: " | ")
        return "**\(escapeMarkdownV2(key))**: \(escapeMarkdownV2(value))"
    }
}
