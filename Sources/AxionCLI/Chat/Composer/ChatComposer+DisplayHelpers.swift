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

    /// 刷新终端显示：回车 + prompt + buffer + 清除行尾。
    func refreshDisplay(prompt: String) {
        if cursor == buffer.count {
            // 光标在末尾
            writeStdout("\r\(prompt)\(buffer)\u{1B}[K")
        } else {
            // 光标在中间 — 显示全部内容后移动光标
            writeStdout("\r\(prompt)\(buffer)\u{1B}[K")
            // 将光标移回正确位置
            let charsAfterCursor = buffer.count - cursor
            if charsAfterCursor > 0 {
                writeStdout("\u{1B}[\(charsAfterCursor)D")
            }
        }
    }

    /// 保存当前编辑状态为 draft。
    mutating func saveDraft() {
        savedDraft = ComposerDraft.snapshot(text: buffer, cursor: cursor)
    }
}
