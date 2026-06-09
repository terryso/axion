import Foundation

// MARK: - HTML Rendering

extension TGMessageFormatter {

    static func renderHTML(_ text: String) -> String {
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

    static func renderLineHTML(_ line: String) -> String {
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

    static func renderInlineHTML(_ text: String) -> String {
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

    static func renderTableRowHTML(_ line: String) -> String {
        let cells = parseTableRow(line)
        if isTableSeparator(line) { return "" }
        guard cells.count >= 2 else { return escapeHTML(line) }
        let key = cells[0]
        let value = cells.dropFirst().joined(separator: " | ")
        return "<b>\(escapeHTML(key))</b>: \(escapeHTML(value))"
    }
}
