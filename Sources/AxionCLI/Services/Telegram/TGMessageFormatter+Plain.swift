
// MARK: - Plain Rendering

extension TGMessageFormatter {

    static func renderPlain(_ text: String) -> String {
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

    static func renderLinePlain(_ line: String) -> String {
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

    static func stripInlineFormatting(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "$1: $2", options: .regularExpression)
        return result
    }

    static func renderTableRowPlain(_ line: String) -> String {
        let cells = parseTableRow(line)
        if isTableSeparator(line) { return "" }
        guard cells.count >= 2 else { return line }
        let key = cells[0]
        let value = cells.dropFirst().joined(separator: " | ")
        return "\(key): \(value)"
    }
}
