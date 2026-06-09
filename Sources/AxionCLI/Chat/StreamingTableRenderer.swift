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

    init(profile: TerminalColorProfile, isTTY: Bool) {
        self.profile = isTTY ? profile : .unknown
        self.isTTY = isTTY
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
            write(renderTable(headerCells: headerCells, bodyRows: bodyRows))
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
            write(renderTable(headerCells: headerCells, bodyRows: bodyRows))
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
    private func renderTable(headerCells: [String], bodyRows: [[String]]) -> String {
        let columnCount = headerCells.count
        guard columnCount > 0 else { return "" }

        // 计算每列最大宽度
        var columnWidths = headerCells.map { visualWidth($0) }
        for row in bodyRows {
            for (i, cell) in row.enumerated() {
                if i < columnWidths.count {
                    columnWidths[i] = max(columnWidths[i], visualWidth(cell))
                }
            }
        }
        // 最小列宽 1
        columnWidths = columnWidths.map { max($0, 1) }

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
        lines.append(renderCellRow(
            cells: headerCells, widths: columnWidths,
            borderColor: borderColor, resetColor: resetColor,
            cellStyleOn: boldOn, cellStyleOff: boldOff
        ))

        // 分隔线: ├───┼───┤
        lines.append(renderBorderLine(
            widths: columnWidths,
            left: "├", mid: "┼", right: "┤", fill: "─",
            borderColor: borderColor, resetColor: resetColor
        ))

        // 表体行: │ id │ Int │
        for row in bodyRows {
            let padded = padRow(row, toCount: columnCount)
            lines.append(renderCellRow(
                cells: padded, widths: columnWidths,
                borderColor: borderColor, resetColor: resetColor,
                cellStyleOn: "", cellStyleOff: ""
            ))
        }

        // 底部边框: ╰─────┴─────╯
        lines.append(renderBorderLine(
            widths: columnWidths,
            left: "╰", mid: "┴", right: "╯", fill: "─",
            borderColor: borderColor, resetColor: resetColor
        ))

        return lines.joined(separator: "\n")
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

    /// 渲染单元格行（表头或表体）。
    private func renderCellRow(
        cells: [String],
        widths: [Int],
        borderColor: String, resetColor: String,
        cellStyleOn: String, cellStyleOff: String
    ) -> String {
        var parts: [String] = []
        parts.append(borderColor + "│" + resetColor)

        for (i, width) in widths.enumerated() {
            let cell = i < cells.count ? cells[i] : ""
            let padded = padCell(cell, toWidth: width)
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

    /// 计算字符串的视觉宽度（CJK 字符计为 2，其余计为 1）。
    private func visualWidth(_ s: String) -> Int {
        var width = 0
        for char in s {
            width += char.isCJKCharacter ? 2 : 1
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
