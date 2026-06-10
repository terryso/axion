
// MARK: - History Navigation (AC1)

extension ChatComposer {

    /// 历史导航方向
    enum HistoryDirection {
        case older  // Up → 更旧
        case newer  // Down → 更新
    }

    /// 执行历史导航 — AC1。
    ///
    /// 显示策略（仿 bash/zsh）：
    /// - 单行 → 单行：行内替换（\r + \e[K + 重写 prompt + buffer）
    /// - 涉及多行（旧或新 buffer 含 \n 或超宽换行）：完整 refreshDisplay
    mutating func navigateHistory(direction: HistoryDirection, prompt: String) {
        // 首次进入历史浏览时保存当前 draft
        if historyIndex == -1 {
            preHistoryDraft = buffer
        }

        let oldBuffer = buffer
        let oldDisplayLines = Self.calculateDisplayLines(prompt: prompt, buffer: oldBuffer)

        // 更新 historyIndex 和 buffer
        switch direction {
        case .older:
            guard !history.isEmpty else { return }
            if historyIndex == -1 {
                historyIndex = history.count - 1
            } else if historyIndex > 0 {
                historyIndex -= 1
            } else {
                return  // 已在最老的历史，不变
            }
            buffer = history[historyIndex]

        case .newer:
            if historyIndex < history.count - 1 {
                historyIndex += 1
                buffer = history[historyIndex]
            } else {
                // 回到浏览前的状态
                historyIndex = -1
                buffer = preHistoryDraft
            }
        }
        cursor = buffer.count

        let newDisplayLines = Self.calculateDisplayLines(prompt: prompt, buffer: buffer)

        // 单行 → 单行：行内替换（\r\e[K] 重写，不用 cursor-up/\e[J]）
        // 否则 → 完整 refreshDisplay（处理多行折叠/展开）
        if oldDisplayLines == 1 && newDisplayLines == 1 {
            replaceBufferInline(oldBuffer: oldBuffer, prompt: prompt)
        } else {
            // previousCursorRow 已由 moveCursorOnly / moveCursorToLine / refreshDisplay 维护，
            // 直接调用 refreshDisplay，它会根据 previousCursorRow 正确上移光标
            refreshDisplay(prompt: prompt)
        }
    }

    /// 行内替换 buffer — bash/zsh 风格。
    ///
    /// 完全模仿 bash/zsh 历史导航：\r 回列 0 → \e[K 清到行尾 → 重写整行。
    /// 不使用 cursor-up 或 \e[J]，因此永远不会产生行偏移。
    private mutating func replaceBufferInline(oldBuffer: String, prompt: String) {
        // \r → 列 0；\e[K → 清除从光标到行尾（整行清空）
        writeStdout("\r\u{1B}[K")
        // 重写 prompt + 新 buffer
        let displayBuffer = buffer.replacingOccurrences(of: "\n", with: "\r\n")
        writeStdout("\(prompt)\(displayBuffer)")
        previousDisplayLines = 1
        previousCursorRow = 0  // 单行替换，光标在末尾 = row 0
    }
}
