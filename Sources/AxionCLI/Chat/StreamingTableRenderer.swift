import Foundation

/// 流式管道表格渲染器 — Codex holdback 模式启发，在 LLM 流式输出中检测 Markdown pipe tables，
/// 并用 Unicode box-drawing 字符渲染对齐表格，替代原始 `| cell |` 文本。
///
/// 设计原则：
/// - 纯状态机，不持有 I/O（写入由调用方控制）
/// - 使用 holdback 模式：缓冲表格行直到表格完成，一次性渲染（避免列宽计算不准）
/// - 支持 TrueColor/ANSI256/ANSI16/unknown 全部颜色 profile 降级
/// - 非 TTY 环境下原样输出（不渲染表格边框）
/// - 与 StreamingCodeBlockRenderer 互补：代码块内的 pipe table 不由本组件处理
///
/// 状态机：
/// ```
/// idle ──(检测到 | cell | 行)──► potentialHeader(buffered)
///   ▲                                    │
///   │                    ┌───────────────┤
///   │                    │               │
///   │              (下一行是分隔符)   (下一行不是分隔符)
///   │                    │               │
///   │                    ▼               ▼
///   │              inTable          输出缓冲行
///   │               (body rows)     + 处理当前行
///   │                    │
///   │    (非表格行 或 flush)
///   │          渲染完整表格
///   └────────────────────┘
/// ```
struct StreamingTableRenderer: Sendable {

    private enum Phase: Sendable {
        case idle
        case potentialHeader
        case inTable
    }

    private var phase: Phase = .idle

    /// 缓冲的潜在表头行
    private var bufferedHeaderLine: String = ""

    /// 已确认的表头单元格
    private var headerCells: [String] = []

    /// 缓冲的表体行
    private var bodyRows: [[String]] = []

    /// 终端颜色 profile
    private let profile: TerminalColorProfile

    /// 是否为 TTY 环境
    private let isTTY: Bool

    /// 终端宽度（列数）。0 表示不限制，向后兼容。
    private let terminalWidth: Int

    /// 每列最小宽度（至少放 1 字符 + `…`）
    private static let minColumnWidth = 3

    init(profile: TerminalColorProfile, isTTY: Bool, terminalWidth: Int = 0) {
        self.profile = isTTY ? profile : .unknown
        self.isTTY = isTTY
        self.terminalWidth = terminalWidth
    }

    // MARK: - Public API

    /// 是否正在缓冲表格行（调用方可据此决定是否追加换行）。
    var isBuffering: Bool {
        return phase != .idle
    }

    /// 处理一行文本，检测是否属于 pipe table 并缓冲/渲染。
    ///
    /// - Parameters:
    ///   - line: 完整行文本（不含末尾换行）
    ///   - write: 输出闭包
    ///   - formatPlain: 非 table 文本的格式化闭包（即 StreamingMarkdownFormatter.formatLine）
    /// - Returns: `true` 表示调用方应追加 `\n`；`false` 表示行被 holdback（不输出）
    @discardableResult
    mutating func processLine(
        _ line: String,
        write: (String) -> Void,
        formatPlain: @Sendable (String) -> String
    ) -> Bool {
        guard isTTY else {
            write(formatPlain(line))
            return true
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if isPipeTableRow(trimmed) {
            return handleTableRow(trimmed, write: write, formatPlain: formatPlain)
        } else {
            return handleNonTableRow(line, write: write, formatPlain: formatPlain)
        }
    }

    /// 在 turn 结束时刷新：如果正在缓冲表格，渲染并输出。
    mutating func flush(
        write: (String) -> Void,
        formatPlain: @Sendable (String) -> String
    ) {
        switch phase {
        case .idle:
            break
        case .potentialHeader:
            // 只有一行 pipe text，不是表格 → 作为普通文本输出
            write(formatPlain(bufferedHeaderLine))
            write("\n")
        case .inTable:
            // 表格未关闭（流结束）→ 渲染已收集的行
            write(renderTable(headerCells: headerCells, bodyRows: bodyRows, formatPlain: formatPlain))
            write("\n")
        }
        resetState()
    }

    /// 重置所有状态。
    mutating func reset() {
        resetState()
    }

    // MARK: - State Machine

    private mutating func handleTableRow(
        _ trimmed: String,
        write: (String) -> Void,
        formatPlain: @Sendable (String) -> String
    ) -> Bool {
        switch phase {
        case .idle:
            // 可能是表头，holdback
            bufferedHeaderLine = trimmed
            phase = .potentialHeader
            return false

        case .potentialHeader:
            if isSeparatorRow(trimmed) {
                // 确认为表格：解析表头
                headerCells = parseCells(from: bufferedHeaderLine)
                bodyRows = []
                phase = .inTable
                return false
            } else {
                // 不是分隔符 → 缓冲行不是表头，输出并重新处理当前行
                write(formatPlain(bufferedHeaderLine))
                write("\n")
                bufferedHeaderLine = ""
                phase = .idle
                return handleTableRow(trimmed, write: write, formatPlain: formatPlain)
            }

        case .inTable:
            let cells = parseCells(from: trimmed)
            bodyRows.append(cells)
            return false
        }
    }

    private mutating func handleNonTableRow(
        _ line: String,
        write: (String) -> Void,
        formatPlain: @Sendable (String) -> String
    ) -> Bool {
        switch phase {
        case .idle:
            write(formatPlain(line))
            return true

        case .potentialHeader:
            // 缓冲的不是表格 → 输出缓冲行 + 当前行
            write(formatPlain(bufferedHeaderLine))
            write("\n")
            bufferedHeaderLine = ""
            phase = .idle
            write(formatPlain(line))
            return true

        case .inTable:
            // 表格完成 → 渲染完整表格 + 当前行
            write(renderTable(headerCells: headerCells, bodyRows: bodyRows, formatPlain: formatPlain))
            write("\n")
            resetState()
            write(formatPlain(line))
            return true
        }
    }

    private mutating func resetState() {
        phase = .idle
        headerCells = []
        bodyRows = []
        bufferedHeaderLine = ""
    }

    // MARK: - Table Detection

    /// 检测一行是否为 pipe table 行（`| cell | cell |` 格式）。
    ///
    /// 规则：
    /// - 至少包含 2 个 `|` 字符（形成至少 1 个单元格）
    /// - 至少包含 1 个非空单元格
    /// - 支持 `| cell | cell |` 格式（含单列 `| cell |`）
    private func isPipeTableRow(_ trimmed: String) -> Bool {
        // 至少 2 个 pipe 字符（形成至少 1 个单元格边界）
        let pipeCount = trimmed.filter { $0 == "|" }.count
        guard pipeCount >= 2 else { return false }

        // 至少 1 个非空段
        let segments = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        let nonEmptyCount = segments.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }.count

        return nonEmptyCount >= 1
    }

    /// 检测一行是否为表格分隔符行（`| --- | --- |` 格式）。
    ///
    /// 支持对齐指示符：`:---`, `---:`, `:---:`
    private func isSeparatorRow(_ trimmed: String) -> Bool {
        let segments = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        let nonEmptySegments = segments.compactMap { seg -> String? in
            let s = seg.trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? nil : s
        }

        guard nonEmptySegments.count >= 1 else { return false }

        // 每个非空段必须是 :---:, ---:, :---, 或 --- (至少 1 个 -)
        return nonEmptySegments.allSatisfy { seg in
            let stripped = seg.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return stripped.allSatisfy({ $0 == "-" }) && stripped.count >= 1
        }
    }

    /// 从 pipe table 行解析单元格内容。
    ///
    /// `| Name | Type |` → ["Name", "Type"]
    /// `| a | b | c |` → ["a", "b", "c"]
    private func parseCells(from line: String) -> [String] {
        var content = line
        if content.hasPrefix("|") { content = String(content.dropFirst()) }
        if content.hasSuffix("|") { content = String(content.dropLast()) }

        return content.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Table Rendering

    /// 渲染完整表格（含边框），返回不带末尾 `\n` 的字符串。
    ///
    /// 单元格内容先经 `formatPlain` 格式化（处理 **bold**、`code` 等 Markdown），
    /// 再基于 ANSI-stripped 视觉宽度计算列宽和对齐。
    private func renderTable(
        headerCells: [String],
        bodyRows: [[String]],
        formatPlain: @Sendable (String) -> String
    ) -> String {
        let columnCount = headerCells.count
        guard columnCount > 0 else { return "" }

        // 先格式化所有单元格内容（Markdown → ANSI styled）
        let styledHeaders = headerCells.map { formatPlain($0) }
        let styledBodyRows = bodyRows.map { row in row.map { formatPlain($0) } }

        // 基于 ANSI-stripped 视觉宽度计算每列最大宽度
        var columnWidths = styledHeaders.map { styledVisualWidth($0) }
        for row in styledBodyRows {
            for (i, cell) in row.enumerated() {
                if i < columnWidths.count {
                    columnWidths[i] = max(columnWidths[i], styledVisualWidth(cell))
                }
            }
        }
        // 最小列宽 1
        columnWidths = columnWidths.map { max($0, 1) }
        let naturalColumnWidths = columnWidths
        let naturalPathColumnIndex = pathLikeColumnIndex(in: headerCells).flatMap { index in
            index < columnWidths.count ? index : nil
        }

        // 终端宽度限制：确保表格不超出终端
        if terminalWidth > 0 {
            let constrainedWidths = constrainColumnWidths(columnWidths, to: terminalWidth)
            if shouldRenderAsDetailList(
                naturalWidths: naturalColumnWidths,
                constrainedWidths: constrainedWidths,
                columnCount: columnCount,
                hasPathColumn: naturalPathColumnIndex != nil,
                rowCount: bodyRows.count
            ) {
                return renderDetailList(
                    headers: headerCells,
                    bodyRows: bodyRows,
                    formatPlain: formatPlain
                )
            }
            columnWidths = constrainedWidths
        }

        let (borderColor, resetColor) = borderCodes()
        let (boldOn, boldOff) = headerStyleCodes()

        var lines: [String] = []

        // 顶部边框: ╭─────┬─────╮
        lines.append(renderBorderLine(
            widths: columnWidths,
            left: "╭", mid: "┬", right: "╮", fill: "─",
            borderColor: borderColor, resetColor: resetColor
        ))

        // 表头行: │ Name │ Type │
        lines.append(renderStyledCellRow(
            cells: styledHeaders, widths: columnWidths,
            borderColor: borderColor, resetColor: resetColor,
            cellStyleOn: boldOn, cellStyleOff: boldOff
        ))

        // 分隔线: ├───┼───┤
        lines.append(renderBorderLine(
            widths: columnWidths,
            left: "├", mid: "┼", right: "┤", fill: "─",
            borderColor: borderColor, resetColor: resetColor
        ))

        let pathColumnIndex = naturalPathColumnIndex.flatMap { index in
            index < columnWidths.count ? index : nil
        }
        let tableWidth = tableVisualWidth(columnWidths)

        // 表体行: │ id │ Int │
        for (rowIndex, row) in styledBodyRows.enumerated() {
            let padded = padRow(row, toCount: columnCount)
            lines.append(renderStyledCellRow(
                cells: padded, widths: columnWidths,
                borderColor: borderColor, resetColor: resetColor,
                cellStyleOn: "", cellStyleOff: ""
            ))
            if let pathColumnIndex,
               rowIndex < bodyRows.count,
               let pathLine = renderPathContinuationIfNeeded(
                   rawRow: bodyRows[rowIndex],
                   columnIndex: pathColumnIndex,
                   columnWidth: columnWidths[pathColumnIndex],
                   tableWidth: tableWidth,
                   borderColor: borderColor,
                   resetColor: resetColor
               ) {
                lines.append(contentsOf: pathLine)
            }
        }

        // 底部边框: ╰─────┴─────╯
        lines.append(renderBorderLine(
            widths: columnWidths,
            left: "╰", mid: "┴", right: "╯", fill: "─",
            borderColor: borderColor, resetColor: resetColor
        ))

        return lines.joined(separator: "\n")
    }

    /// 宽表在窄终端里硬压列会把多个字段都变成 `…`，比原始 Markdown 更难读。
    /// 对非路径类的 4+ 列宽表，信息损失明显时改成逐行详情块，优先保全文本。
    private func shouldRenderAsDetailList(
        naturalWidths: [Int],
        constrainedWidths: [Int],
        columnCount: Int,
        hasPathColumn: Bool,
        rowCount: Int
    ) -> Bool {
        guard terminalWidth > 0,
              columnCount >= 4,
              rowCount > 0,
              !hasPathColumn else { return false }

        let naturalTableWidth = tableVisualWidth(naturalWidths)
        guard naturalTableWidth > terminalWidth else { return false }

        let naturalContentWidth = max(1, naturalWidths.reduce(0, +))
        let lostContentWidth = zip(naturalWidths, constrainedWidths).reduce(0) { acc, pair in
            acc + max(0, pair.0 - pair.1)
        }
        let lossRatio = Double(lostContentWidth) / Double(naturalContentWidth)
        let severelyCompressed = zip(naturalWidths, constrainedWidths).contains { natural, constrained in
            natural >= 12 && constrained <= 6
        }

        return lossRatio >= 0.45 || severelyCompressed
    }

    private func renderDetailList(
        headers: [String],
        bodyRows: [[String]],
        formatPlain: @Sendable (String) -> String
    ) -> String {
        let maxWidth = max(30, terminalWidth)
        var lines: [String] = []
        lines.append("表格（\(bodyRows.count) 行，已改为详情模式显示）")

        for (rowIndex, rawRow) in bodyRows.enumerated() {
            lines.append("\(rowIndex + 1).")
            let row = padRow(rawRow, toCount: headers.count)
            for index in 0..<headers.count {
                let label = headers[index].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty || !value.isEmpty else { continue }
                lines.append(contentsOf: wrapDetailField(
                    label: label.isEmpty ? "列 \(index + 1)" : label,
                    value: value.isEmpty ? "-" : value,
                    maxWidth: maxWidth
                ))
            }
        }

        return lines.map { formatPlain($0) }.joined(separator: "\n")
    }

    private func wrapDetailField(label: String, value: String, maxWidth: Int) -> [String] {
        let firstPrefix = "  \(label): "
        let nextPrefix = "    "
        let firstWidth = max(6, maxWidth - visualWidth(firstPrefix))
        let nextWidth = max(6, maxWidth - visualWidth(nextPrefix))
        let chunks = wrapText(value, firstLineWidth: firstWidth, nextLineWidth: nextWidth)

        guard let first = chunks.first else {
            return [firstPrefix]
        }

        var lines = [firstPrefix + first]
        lines.append(contentsOf: chunks.dropFirst().map { nextPrefix + $0 })
        return lines
    }

    private func wrapText(_ text: String, firstLineWidth: Int, nextLineWidth: Int) -> [String] {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var maxWidth = max(1, firstLineWidth)
        let nextWidth = max(1, nextLineWidth)
        var lines: [String] = []

        while visualWidth(remaining) > maxWidth {
            let cut = preferredTextBreakIndex(in: remaining, maxWidth: maxWidth)
            let piece = String(remaining[..<cut])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                lines.append(piece)
            }
            remaining = String(remaining[cut...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            maxWidth = nextWidth
        }

        if !remaining.isEmpty || lines.isEmpty {
            lines.append(remaining)
        }
        return lines
    }

    private func preferredTextBreakIndex(in text: String, maxWidth: Int) -> String.Index {
        var width = 0
        var index = text.startIndex
        var lastSoftBreak: String.Index?

        while index < text.endIndex {
            let char = text[index]
            let charWidth = char.isCJKCharacter ? 2 : 1
            if width + charWidth > maxWidth {
                if let lastSoftBreak, lastSoftBreak > text.startIndex {
                    return lastSoftBreak
                }
                return index == text.startIndex ? text.index(after: index) : index
            }
            width += charWidth
            index = text.index(after: index)
            if isSoftBreakCharacter(char) {
                lastSoftBreak = index
            }
        }
        return text.endIndex
    }

    private func isSoftBreakCharacter(_ char: Character) -> Bool {
        char == " "
            || char == "/"
            || char == "\\"
            || char == ","
            || char == "，"
            || char == "、"
            || char == ";"
            || char == "；"
            || char == ")"
            || char == "）"
            || char == "]"
            || char == "】"
    }

    /// 表格存在路径列且该单元格会被终端宽度压缩时，在下一行补充完整路径。
    private func renderPathContinuationIfNeeded(
        rawRow: [String],
        columnIndex: Int,
        columnWidth: Int,
        tableWidth: Int,
        borderColor: String,
        resetColor: String
    ) -> [String]? {
        guard columnIndex < rawRow.count else { return nil }
        let rawPath = rawRow[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikePath(rawPath), visualWidth(rawPath) > columnWidth else { return nil }

        let contentWidth = max(1, tableWidth - 4)
        let wrapped = wrapPathContinuation(label: "路径", path: rawPath, maxWidth: contentWidth)
        return wrapped.map {
            renderSpanningCellRow(
                $0,
                contentWidth: contentWidth,
                borderColor: borderColor,
                resetColor: resetColor
            )
        }
    }

    private func renderSpanningCellRow(
        _ content: String,
        contentWidth: Int,
        borderColor: String,
        resetColor: String
    ) -> String {
        let padded = padCell(content, toWidth: contentWidth)
        return borderColor + "│" + resetColor + " " + padded + " " + borderColor + "│" + resetColor
    }

    private func pathLikeColumnIndex(in headers: [String]) -> Int? {
        headers.firstIndex { header in
            let normalized = stripAnsiFromCell(header)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return normalized == "path"
                || normalized == "路径"
                || normalized.contains(" path")
                || normalized.contains("路径")
        }
    }

    private func looksLikePath(_ value: String) -> Bool {
        value.hasPrefix("/")
            || value.hasPrefix("~/")
            || value.contains("/Library/")
            || value.contains("\\")
    }

    private func tableVisualWidth(_ widths: [Int]) -> Int {
        widths.reduce(0, +) + widths.count * 2 + widths.count + 1
    }

    private func wrapPathContinuation(label: String, path: String, maxWidth: Int) -> [String] {
        let prefix = "\(label): "
        let firstLineWidth = max(1, maxWidth - visualWidth(prefix))
        let chunks = wrapPath(path, firstLineWidth: firstLineWidth, nextLineWidth: maxWidth)
        return chunks.enumerated().map { index, chunk in
            index == 0 ? prefix + chunk : chunk
        }
    }

    private func wrapPath(_ path: String, firstLineWidth: Int, nextLineWidth: Int) -> [String] {
        var remaining = path
        var maxWidth = firstLineWidth
        var lines: [String] = []

        while visualWidth(remaining) > maxWidth {
            let cut = preferredPathBreakIndex(in: remaining, maxWidth: maxWidth)
            lines.append(String(remaining[..<cut]))
            remaining = String(remaining[cut...])
            maxWidth = nextLineWidth
        }

        if !remaining.isEmpty || lines.isEmpty {
            lines.append(remaining)
        }
        return lines
    }

    private func preferredPathBreakIndex(in text: String, maxWidth: Int) -> String.Index {
        var width = 0
        var index = text.startIndex
        var lastSlashBreak: String.Index?

        while index < text.endIndex {
            let char = text[index]
            let charWidth = char.isCJKCharacter ? 2 : 1
            if width + charWidth > maxWidth {
                if let lastSlashBreak, lastSlashBreak > text.startIndex {
                    return lastSlashBreak
                }
                return index == text.startIndex ? text.index(after: index) : index
            }
            width += charWidth
            index = text.index(after: index)
            if char == "/" || char == "\\" {
                lastSlashBreak = index
            }
        }
        return text.endIndex
    }

    /// 渲染水平边框线。
    private func renderBorderLine(
        widths: [Int],
        left: String, mid: String, right: String, fill: String,
        borderColor: String, resetColor: String
    ) -> String {
        var parts: [String] = []
        parts.append(borderColor + left + resetColor)

        for (i, w) in widths.enumerated() {
            // +2 for padding spaces around cell content
            parts.append(borderColor + String(repeating: fill, count: w + 2) + resetColor)
            if i < widths.count - 1 {
                parts.append(borderColor + mid + resetColor)
            }
        }

        parts.append(borderColor + right + resetColor)
        return parts.joined()
    }

    /// 渲染单元格行（表头或表体）— 支持 ANSI styled 内容。
    ///
    /// 使用 `styledVisualWidth` 计算 padding，确保含 ANSI 转义码的单元格正确对齐。
    /// 超宽单元格会被截断到目标宽度。
    private func renderStyledCellRow(
        cells: [String],
        widths: [Int],
        borderColor: String, resetColor: String,
        cellStyleOn: String, cellStyleOff: String
    ) -> String {
        var parts: [String] = []
        parts.append(borderColor + "│" + resetColor)

        for (i, width) in widths.enumerated() {
            let cell = i < cells.count ? cells[i] : ""
            let truncated = truncateStyledCell(cell, toWidth: width)
            let padded = padStyledCell(truncated, toWidth: width)
            parts.append(" " + cellStyleOn + padded + cellStyleOff + " ")
            if i < widths.count - 1 {
                parts.append(borderColor + "│" + resetColor)
            }
        }

        parts.append(borderColor + "│" + resetColor)
        return parts.joined()
    }

    /// 补齐行到指定列数（不足的列用空字符串填充，超出的列截断）。
    private func padRow(_ row: [String], toCount: Int) -> [String] {
        if row.count >= toCount {
            return Array(row.prefix(toCount))
        }
        return row + Array(repeating: "", count: toCount - row.count)
    }

    /// 补齐单元格到指定视觉宽度（左对齐）。
    private func padCell(_ cell: String, toWidth: Int) -> String {
        let currentWidth = visualWidth(cell)
        if currentWidth >= toWidth { return cell }
        return cell + String(repeating: " ", count: toWidth - currentWidth)
    }

    /// 补齐含 ANSI 转义码的单元格到指定视觉宽度（左对齐）。
    ///
    /// 先剥离 ANSI 码计算视觉宽度，然后在末尾补空格。
    private func padStyledCell(_ cell: String, toWidth: Int) -> String {
        let currentWidth = styledVisualWidth(cell)
        if currentWidth >= toWidth { return cell }
        return cell + String(repeating: " ", count: toWidth - currentWidth)
    }

    // MARK: - Width Constraint

    /// 将列宽限制在终端宽度内。
    ///
    /// 策略：
    /// 1. 计算表格总宽度（内容 + padding + 边框）
    /// 2. 如果超出，按比例缩减各列
    /// 3. 每列不低于 `minColumnWidth`
    /// 4. 极端情况（列数太多导致最小宽度总和已超限）从右向左截断列
    private func constrainColumnWidths(_ widths: [Int], to maxWidth: Int) -> [Int] {
        let colCount = widths.count
        guard colCount > 0 else { return widths }

        // 边框/分隔符占用：每列 2 padding (" " + " ") + (列数+1) 个 │
        let borderOverhead = colCount * 2 + colCount + 1
        let totalWidth = widths.reduce(0, +) + borderOverhead

        if totalWidth <= maxWidth { return widths }

        // 可用内容宽度
        let availableContent = max(0, maxWidth - borderOverhead)
        let minTotal = Self.minColumnWidth * colCount

        if availableContent < minTotal {
            // 极端情况：连最小宽度都放不下 → 从右向左砍列
            let maxCols = max(1, availableContent / Self.minColumnWidth)
            let keptWidths = Array(widths.prefix(maxCols))
            return constrainColumnWidths(keptWidths, to: maxWidth)
        }

        // 按比例缩减
        let total = widths.reduce(0, +)
        var result = widths.map { width -> Int in
            let scaled = Int(Double(width) * Double(availableContent) / Double(total))
            return max(Self.minColumnWidth, scaled)
        }

        // 修正舍入误差：确保总和不超过 availableContent
        let resultTotal = result.reduce(0, +)
        if resultTotal > availableContent {
            var excess = resultTotal - availableContent
            var idx = result.count - 1
            while excess > 0 && idx >= 0 {
                let reduction = min(excess, result[idx] - Self.minColumnWidth)
                result[idx] -= reduction
                excess -= reduction
                idx -= 1
            }
        }

        return result
    }

    /// 截断含 ANSI 转义码的单元格到指定视觉宽度，末尾加 `…`。
    ///
    /// 策略：剥离 ANSI 码 → 按视觉宽度逐字符截断 → 加 `…` → ANSI 码丢弃
    /// （截断后内容已不完整，丢弃 ANSI 样式是合理的简化）。
    private func truncateStyledCell(_ cell: String, toWidth: Int) -> String {
        let currentWidth = styledVisualWidth(cell)
        if currentWidth <= toWidth { return cell }

        guard toWidth > 1 else {
            // 极窄：只放省略号
            return "…"
        }

        // 剥离 ANSI 码，按视觉宽度截断纯文本
        let plain = stripAnsiFromCell(cell)
        var result = ""
        var width = 0
        let targetWidth = toWidth - 1  // 留 1 给 …

        for char in plain {
            let charWidth = char.isCJKCharacter ? 2 : 1
            if width + charWidth > targetWidth { break }
            result.append(char)
            width += charWidth
        }

        return result + "…"
    }

    /// 剥离字符串中的 ANSI 转义序列（单元格级别）。
    private func stripAnsiFromCell(_ s: String) -> String {
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}" {
                let next = s.index(after: i)
                if next < s.endIndex {
                    let c = s[next]
                    if c == "[" {
                        i = s.index(after: next)
                        while i < s.endIndex {
                            let b = s[i]
                            if let ascii = b.asciiValue, ascii >= 0x40 && ascii <= 0x7E {
                                i = s.index(after: i)
                                break
                            }
                            i = s.index(after: i)
                        }
                    } else if c == "]" {
                        i = s.index(after: next)
                        while i < s.endIndex {
                            if s[i] == "\u{07}" {
                                i = s.index(after: i)
                                break
                            }
                            if s[i] == "\u{1B}" {
                                let afterEsc = s.index(after: i)
                                if afterEsc < s.endIndex && s[afterEsc] == "\\" {
                                    i = s.index(after: afterEsc)
                                    break
                                }
                            }
                            i = s.index(after: i)
                        }
                    } else {
                        i = s.index(after: next)
                    }
                } else {
                    i = next
                }
            } else {
                result.append(s[i])
                i = s.index(after: i)
            }
        }
        return result
    }

    /// 计算字符串的视觉宽度（CJK 字符计为 2，其余计为 1）。
    private func visualWidth(_ s: String) -> Int {
        var width = 0
        for char in s {
            width += char.isCJKCharacter ? 2 : 1
        }
        return width
    }

    /// 计算含 ANSI 转义码的字符串的视觉宽度（先剥离 ANSI 码，再计 CJK 宽度）。
    ///
    /// CSI 序列 (`\e[...字母`) 和 OSC 序列 (`\e]...BEL/ST`) 均计为 0 宽度。
    private func styledVisualWidth(_ s: String) -> Int {
        var width = 0
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}" {
                // ANSI escape sequence — skip without counting width
                let next = s.index(after: i)
                if next < s.endIndex {
                    let c = s[next]
                    if c == "[" {
                        // CSI: skip until final byte (0x40–0x7E)
                        i = s.index(after: next)
                        while i < s.endIndex {
                            let b = s[i]
                            if let ascii = b.asciiValue, ascii >= 0x40 && ascii <= 0x7E {
                                i = s.index(after: i)
                                break
                            }
                            i = s.index(after: i)
                        }
                    } else if c == "]" {
                        // OSC: skip until BEL (0x07) or ST (\e\\)
                        i = s.index(after: next)
                        while i < s.endIndex {
                            if s[i] == "\u{07}" {
                                i = s.index(after: i)
                                break
                            }
                            if s[i] == "\u{1B}" {
                                let afterEsc = s.index(after: i)
                                if afterEsc < s.endIndex && s[afterEsc] == "\\" {
                                    i = s.index(after: afterEsc)
                                    break
                                }
                            }
                            i = s.index(after: i)
                        }
                    } else {
                        // Other 2-char escape
                        i = s.index(after: next)
                    }
                } else {
                    i = next
                }
            } else {
                width += s[i].isCJKCharacter ? 2 : 1
                i = s.index(after: i)
            }
        }
        return width
    }

    // MARK: - ANSI Code Helpers

    /// 边框颜色代码（dim 色）。
    private func borderCodes() -> (color: String, reset: String) {
        switch profile {
        case .trueColor:
            return ("\u{1B}[38;2;100;100;120m", "\u{1B}[0m")
        case .ansi256:
            return ("\u{1B}[38;5;243m", "\u{1B}[0m")
        case .ansi16:
            return ("\u{1B}[2m", "\u{1B}[0m")
        case .unknown:
            return ("", "")
        }
    }

    /// 表头样式代码（bold）。
    private func headerStyleCodes() -> (on: String, off: String) {
        switch profile {
        case .trueColor, .ansi256, .ansi16:
            return ("\u{1B}[1m", "\u{1B}[0m")
        case .unknown:
            return ("", "")
        }
    }
}

// MARK: - Character Extension for CJK Detection

private extension Character {
    /// 是否为 CJK 字符（中日韩统一表意文字、全角字符、假名等）。
    var isCJKCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let value = scalar.value
        return (value >= 0x4E00 && value <= 0x9FFF)    // CJK Unified Ideographs
            || (value >= 0xF900 && value <= 0xFAFF)    // CJK Compatibility Ideographs
            || (value >= 0x3400 && value <= 0x4DBF)    // CJK Unified Ideographs Extension A
            || (value >= 0xFF01 && value <= 0xFF60)    // Fullwidth Forms
            || (value >= 0x3040 && value <= 0x309F)    // Hiragana
            || (value >= 0x30A0 && value <= 0x30FF)    // Katakana
    }
}
