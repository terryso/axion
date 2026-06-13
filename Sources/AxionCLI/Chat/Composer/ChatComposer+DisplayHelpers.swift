import Darwin
import Foundation

// MARK: - Display & Buffer Helpers

extension ChatComposer {

    /// 清除终端中已渲染的弹窗行。
    /// popup 和 fileSearch 的清除逻辑共用此方法。
    ///
    /// 前提：光标已在输入行（由渲染函数的 `\e[N A` 保证）。
    /// 使用 `\e[J`（Erase Display）清除光标到屏幕末尾的所有弹窗内容。
    func clearRenderedOutput(lineCount: Int) {
        guard lineCount > 0 else { return }
        // 光标在输入行，\e[J 清除从光标到屏幕末尾的所有内容
        writeStdout("\u{1B}[J")
    }

    /// 在光标位置插入字符。
    mutating func insertChar(_ char: String) {
        let index = buffer.index(buffer.startIndex, offsetBy: cursor)
        buffer.insert(contentsOf: char, at: index)
        cursor += char.count
    }

    /// 删除光标前一个完整字符（处理 UTF-8 多字节边界）。
    mutating func deleteCharBackward() {
        guard cursor > 0 else { return }
        let index = buffer.index(buffer.startIndex, offsetBy: cursor - 1)
        buffer.remove(at: index)
        cursor -= 1
    }

    /// 删除光标后一个完整字符。
    mutating func deleteCharForward() {
        guard cursor < buffer.count else { return }
        let index = buffer.index(buffer.startIndex, offsetBy: cursor)
        buffer.remove(at: index)
    }

    /// 获取或创建 ChatTheme（lazy 初始化）。
    mutating func ensureTheme() -> ChatTheme {
        if let theme = chatTheme { return theme }
        let profile = TerminalColorProfile.detect()
        let theme = ChatTheme(profile: profile, isTTY: isTTY)
        chatTheme = theme
        return theme
    }

    /// 刷新终端显示 — 多行感知重绘。
    ///
    /// 当 prompt + buffer 超过终端宽度换行时：
    /// 1. 上移到第一行
    /// 2. 清除旧内容
    /// 3. 重写 prompt + buffer
    /// 4. 定位光标到正确位置
    mutating func refreshDisplay(prompt: String) {
        let newLineCount = Self.calculateDisplayLines(prompt: prompt, buffer: buffer)
        let termWidth = max(1, Self.terminalColumns())

        // 1. 上移到第一行（基于光标当前所在行）
        if previousCursorRow > 0 {
            writeStdout("\u{1B}[\(previousCursorRow)A")
        }

        // 2. 回到第 0 列 + 清除到屏幕末尾（清除旧内容）
        writeStdout("\r\u{1B}[J")

        // 3. 重写 prompt + buffer
        // OPOST 在 raw 模式下被禁用（KeyEventReader），\n 不会自动转为 \r\n，
        // 所以必须显式替换，确保每行从列 0 开始。
        let displayBuffer = buffer.replacingOccurrences(of: "\n", with: "\r\n")
        writeStdout("\(prompt)\(displayBuffer)")

        // 4. 光标定位
        let curPos = Self.cursorVisualPosition(
            prompt: prompt, buffer: buffer, cursor: cursor, termWidth: termWidth)

        if cursor != buffer.count {
            let endPos = Self.cursorVisualPosition(
                prompt: prompt, buffer: buffer, cursor: buffer.count, termWidth: termWidth)
            let rowsUp = endPos.row - curPos.row
            if rowsUp > 0 {
                writeStdout("\u{1B}[\(rowsUp)A")
            }
            writeStdout("\r")
            if curPos.col > 0 {
                writeStdout("\u{1B}[\(curPos.col)C")
            }
        }

        // 5. 更新状态
        previousCursorRow = curPos.row
        previousDisplayLines = newLineCount
    }

    /// 计算光标当前所在行号（0-based）。
    ///
    /// buffer 中的 `\n` 分隔逻辑行。光标在某行的 `\n` 之前算在该行。
    static func currentLineIndex(cursor: Int, buffer: String) -> Int {
        let clamped = max(0, min(cursor, buffer.count))
        let idx = buffer.index(buffer.startIndex, offsetBy: clamped)
        let prefix = buffer[..<idx]
        return prefix.filter { $0 == "\n" }.count
    }

    /// 计算 buffer 中逻辑行的总数。
    static func lineCount(in buffer: String) -> Int {
        if buffer.isEmpty { return 1 }
        return buffer.filter { $0 == "\n" }.count + 1
    }

    /// 返回 buffer 中第 lineIndex 行的起始字符偏移（0-based）。
    static func lineStartOffset(lineIndex: Int, buffer: String) -> Int {
        guard lineIndex > 0 else { return 0 }
        var currentLine = 0
        var offset = 0
        for char in buffer {
            if currentLine == lineIndex { return offset }
            if char == "\n" { currentLine += 1 }
            offset += 1
        }
        return offset
    }

    /// 返回 buffer 中第 lineIndex 行的结束字符偏移（不含 `\n`）。
    static func lineEndOffset(lineIndex: Int, buffer: String) -> Int {
        let start = lineStartOffset(lineIndex: lineIndex, buffer: buffer)
        let startIndex = buffer.index(buffer.startIndex, offsetBy: start)
        let rest = buffer[startIndex...]
        if let newlineIdx = rest.firstIndex(of: "\n") {
            return start + buffer.distance(from: startIndex, to: newlineIdx)
        }
        return buffer.count
    }

    /// 返回 buffer 中第 lineIndex 行的文本内容（不含 `\n`）。
    static func lineContent(lineIndex: Int, buffer: String) -> String {
        let start = lineStartOffset(lineIndex: lineIndex, buffer: buffer)
        let end = lineEndOffset(lineIndex: lineIndex, buffer: buffer)
        let startIdx = buffer.index(buffer.startIndex, offsetBy: start)
        let endIdx = buffer.index(buffer.startIndex, offsetBy: end)
        return String(buffer[startIdx..<endIdx])
    }

    /// 纯光标移动（不清屏不重绘）— 用于 Up/Down/Home/End/Left/Right。
    ///
    /// 前提：终端光标当前在 `oldCursor` 对应的视觉位置（由 refreshDisplay 或
    /// 上一次 moveCursorOnly 保证）。
    /// 计算旧/新视觉位置差，只发射光标移动 ANSI 序列。
    mutating func moveCursorOnly(oldCursor: Int, newCursor: Int, prompt: String) {
        guard oldCursor != newCursor else { return }

        let termWidth = max(1, Self.terminalColumns())
        let oldPos = Self.cursorVisualPosition(
            prompt: prompt, buffer: buffer, cursor: oldCursor, termWidth: termWidth)
        let newPos = Self.cursorVisualPosition(
            prompt: prompt, buffer: buffer, cursor: newCursor, termWidth: termWidth)

        let rowDelta = newPos.row - oldPos.row
        if rowDelta > 0 {
            writeStdout("\u{1B}[\(rowDelta)B")
        } else if rowDelta < 0 {
            writeStdout("\u{1B}[\(-rowDelta)A")
        }

        // 列定位：\r 回列 0，再右移
        writeStdout("\r")
        if newPos.col > 0 {
            writeStdout("\u{1B}[\(newPos.col)C")
        }

        // 更新光标行追踪
        previousCursorRow = newPos.row
    }

    /// 将光标移到 buffer 中第 lineIndex 行的对应列位置。
    ///
    /// 保留原光标在当前行的列位置（如果目标行更短则截断到行尾）。
    mutating func moveCursorToLine(_ targetLine: Int, prompt: String) {
        let curLine = Self.currentLineIndex(cursor: cursor, buffer: buffer)
        let curLineStart = Self.lineStartOffset(lineIndex: curLine, buffer: buffer)
        // 当前列内偏移（字符数）
        let colInLine = cursor - curLineStart

        let targetStart = Self.lineStartOffset(lineIndex: targetLine, buffer: buffer)
        let targetEnd = Self.lineEndOffset(lineIndex: targetLine, buffer: buffer)
        let targetLen = targetEnd - targetStart

        // 保持列位置，但不超过目标行长度
        let newColInLine = min(colInLine, targetLen)
        let newCursor = targetStart + newColInLine

        moveCursorOnly(oldCursor: cursor, newCursor: newCursor, prompt: prompt)
        cursor = newCursor
    }

    /// 将光标移到当前行的行首。
    mutating func moveCursorToLineStart(prompt: String) {
        let curLine = Self.currentLineIndex(cursor: cursor, buffer: buffer)
        let start = Self.lineStartOffset(lineIndex: curLine, buffer: buffer)
        if cursor != start {
            moveCursorOnly(oldCursor: cursor, newCursor: start, prompt: prompt)
            cursor = start
        }
    }

    /// 将光标移到当前行的行尾。
    mutating func moveCursorToLineEnd(prompt: String) {
        let curLine = Self.currentLineIndex(cursor: cursor, buffer: buffer)
        let end = Self.lineEndOffset(lineIndex: curLine, buffer: buffer)
        if cursor != end {
            moveCursorOnly(oldCursor: cursor, newCursor: end, prompt: prompt)
            cursor = end
        }
    }

    /// 保存当前编辑状态为 draft。
    mutating func saveDraft() {
        savedDraft = ComposerDraft.snapshot(text: buffer, cursor: cursor)
    }

    // MARK: - Multi-line Display Helpers

    /// 获取终端宽度（列数）。
    ///
    /// 使用 `ioctl(TIOCGWINSZ)` 查询，fallback 到 80 列。
    static func terminalColumns() -> Int {
        var ws = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 else {
            return 80
        }
        return Int(ws.ws_col)
    }

    /// 获取终端高度（行数）。
    ///
    /// 使用 `ioctl(TIOCGWINSZ)` 查询，fallback 到 24 行。
    static func terminalRows() -> Int {
        var ws = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_row > 0 else {
            return 24
        }
        return Int(ws.ws_row)
    }

    /// 剥离字符串中的 ANSI 转义序列。
    ///
    /// 支持 CSI (`\e[...字母`) 和 OSC (`\e]...BEL/ST`) 序列。
    static func stripAnsi(_ s: String) -> String {
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}" {
                let next = s.index(after: i)
                if next < s.endIndex {
                    let c = s[next]
                    if c == "[" {
                        // CSI sequence: skip until final byte (0x40-0x7E)
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
                        // OSC sequence: skip until BEL (0x07) or ST (\e\\)
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
                        // Other: 2-char escape sequence
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

    /// 计算字符串的终端显示宽度。
    ///
    /// 先剥离 ANSI 转义码，然后统计：
    /// - CJK/wide 字符 → 2 列
    /// - 其他可打印字符 → 1 列
    /// - Default-ignorable code points → 0 列
    static func displayWidth(_ s: String) -> Int {
        let stripped = stripAnsi(s)
        var width = 0
        for scalar in stripped.unicodeScalars {
            if scalar.properties.isDefaultIgnorableCodePoint { continue }
            width += isWideScalar(scalar) ? 2 : 1
        }
        return width
    }

    /// 判断 Unicode scalar 是否为宽字符（CJK/全角等）。
    ///
    /// 与 `TGMessageFormatter+Tables.isWideScalar` 逻辑一致。
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

    /// 计算已渲染文本（popup / fileSearch 列表）占用的终端物理行数。
    ///
    /// 与 `calculateDisplayLines` 类似，但不需要 prompt 宽度偏移，
    /// 纯粹按每行的 display width 和终端宽度计算物理行数。
    /// 用于光标上移 `\e[N A` 的 N 值计算 — 必须用物理行数，
    /// 否则当弹出行超宽折行时，光标上移量不足，导致重绘位置错误。
    static func calculatePhysicalLines(rendered: String, termWidth: Int) -> Int {
        let logicalLines = rendered.components(separatedBy: "\n")
        var total = 0
        for line in logicalLines {
            let width = displayWidth(line)
            total += max(1, (width + termWidth - 1) / termWidth)
        }
        return total
    }

    /// 计算 prompt + buffer 占用的终端物理行数。
    ///
    /// 正确处理 buffer 中的 `\n`（如 bracket paste 多行内容）：
    /// 每个 `\n` 在终端中产生真正的换行，需要按段分别计算行数。
    /// - 第一段: prompt 宽度 + 第一段 buffer 宽度 → 向上取整
    /// - 后续段: 纯 buffer 段宽度 → 向上取整
    /// - 空段也占 1 行（终端中 `\n` 后的空行）
    static func calculateDisplayLines(prompt: String, buffer: String) -> Int {
        let cols = max(1, terminalColumns())
        let bufferLines = buffer.components(separatedBy: "\n")

        var totalLines = 0
        for (i, line) in bufferLines.enumerated() {
            let lineWidth = (i == 0 ? displayWidth(prompt) : 0) + displayWidth(line)
            totalLines += max(1, (lineWidth + cols - 1) / cols)
        }
        return totalLines
    }

    /// 计算光标在终端中的视觉 (行, 列) 位置。
    ///
    /// 行从 0 开始（第一行 = prompt 所在行），列为该行内的偏移。
    /// 正确处理 buffer 中的 `\n`：每个 `\n` 分隔独立的终端行。
    ///
    /// - Parameters:
    ///   - prompt: 提示符字符串（第一行独占）
    ///   - buffer: 编辑缓冲区（可能含 `\n`）
    ///   - cursor: 光标在 buffer 中的字符偏移
    ///   - termWidth: 终端宽度（列数）
    /// - Returns: (row, col) — row 是从第一行起的行号，col 是行内列号
    static func cursorVisualPosition(
        prompt: String, buffer: String, cursor: Int, termWidth: Int
    ) -> (row: Int, col: Int) {
        let clampedCursor = max(0, min(cursor, buffer.count))
        let cursorIndex = buffer.index(buffer.startIndex, offsetBy: clampedCursor)
        let textBeforeCursor = String(buffer[..<cursorIndex])
        let segments = textBeforeCursor.components(separatedBy: "\n")

        var row = 0
        for (i, seg) in segments.enumerated() {
            let lineW = (i == 0 ? displayWidth(prompt) : 0) + displayWidth(seg)
            if i < segments.count - 1 {
                // 完整行（光标不在此段末尾）
                row += max(1, (lineW + termWidth - 1) / termWidth)
            } else {
                // 光标所在行
                row += lineW / termWidth
                return (row: row, col: lineW % termWidth)
            }
        }
        return (row: 0, col: displayWidth(prompt) % termWidth)
    }
}
