
// MARK: - Slash Popup Mode Handling (AC1/AC2/AC5/AC6/AC7)

/// Result of handling a slash popup event in the main event loop.
/// Tells the caller whether to continue processing or return from readRawLoop.
enum SlashPopupEventResult: Sendable {
    /// Event was handled; continue the event loop.
    case handled
    /// Return this value from readRawLoop.
    case returnInput(String?)
}

extension ChatComposer {

    /// 进入 slashPopup 模式 — AC1。
    mutating func enterSlashPopup(prompt: String) {
        // Save draft as the state BEFORE "/" was typed.
        // Trigger condition is buffer == "/", so pre-slash was empty.
        savedDraft = ComposerDraft.snapshot(text: "", cursor: 0)
        mode = .slashPopup(query: buffer)
        selectedPopupIndex = 0
        let theme = ensureTheme()
        popupItems = SlashPopup.filter(query: buffer, context: slashContext)
        let rendered = SlashPopup.render(items: popupItems, selectedIndex: selectedPopupIndex, theme: theme)
        let lines = rendered.components(separatedBy: "\n")
        popupRenderedLines = lines.count
        // 写入弹窗内容到输入行下方
        // 注意：raw mode 关闭了 OPOST，\n 不会自动转 \r\n，
        // 必须手动确保每行 \r\n 以回到第 0 列
        let terminalRendered = rendered.replacingOccurrences(of: "\n", with: "\r\n")
        writeStdout("\r\n\(terminalRendered)")
        // 光标移回输入行（弹窗 N 行在下方，上移 N 行）
        writeStdout("\u{1B}[\(popupRenderedLines)A")
        // 在输入行上写 prompt + buffer（\e[K 清除行尾残留）
        writeStdout("\r\(prompt)\(buffer)\u{1B}[K")
    }

    /// 刷新 slashPopup 过滤和渲染 — AC2。
    mutating func refreshSlashPopup(prompt: String) {
        if case .slashPopup = mode {
            mode = .slashPopup(query: buffer)
        }
        // clamp selectedPopupIndex
        let theme = ensureTheme()
        popupItems = SlashPopup.filter(query: buffer, context: slashContext)
        if popupItems.isEmpty {
            selectedPopupIndex = -1
        } else if selectedPopupIndex >= popupItems.count {
            selectedPopupIndex = popupItems.count - 1
        } else if selectedPopupIndex < 0 {
            selectedPopupIndex = 0
        }
        let rendered = SlashPopup.render(items: popupItems, selectedIndex: selectedPopupIndex, theme: theme)
        let newLines = rendered.components(separatedBy: "\n").count

        // 清除旧 popup 输出
        clearPopupOutput()
        popupRenderedLines = newLines

        // 输出新 popup（\n → \r\n，确保 raw mode 下每行回到第 0 列）
        let terminalRendered = rendered.replacingOccurrences(of: "\n", with: "\r\n")
        writeStdout("\r\n\(terminalRendered)")
        // 光标移回输入行
        writeStdout("\u{1B}[\(popupRenderedLines)A")
        writeStdout("\r\(prompt)\(buffer)\u{1B}[K")
    }

    /// 仅重新渲染 popup 列表（选中变化时，不重新过滤）— AC6。
    mutating func refreshSlashPopupRender(prompt: String) {
        let theme = ensureTheme()
        let rendered = SlashPopup.render(items: popupItems, selectedIndex: selectedPopupIndex, theme: theme)
        let newLines = rendered.components(separatedBy: "\n").count

        clearPopupOutput()
        popupRenderedLines = newLines

        // 重新渲染 popup（\n → \r\n，确保 raw mode 下每行回到第 0 列）
        let terminalRendered = rendered.replacingOccurrences(of: "\n", with: "\r\n")
        writeStdout("\r\n\(terminalRendered)")
        // 光标移回输入行
        writeStdout("\u{1B}[\(popupRenderedLines)A")
        writeStdout("\r\(prompt)\(buffer)\u{1B}[K")
    }

    /// 补全选中的命令 — AC5。
    /// 返回补全的 SlashCommand（nil 表示无匹配）。
    mutating func completeSelectedCommand() -> SlashCommand? {
        let idx = selectedPopupIndex
        guard idx >= 0 && idx < popupItems.count else { return nil }
        let cmd = popupItems[idx].command
        buffer = cmd.rawValue
        if cmd.acceptsArgs {
            buffer += " "
        }
        cursor = buffer.count
        return cmd
    }

    /// 取消 slashPopup 模式，恢复原始 draft — AC7。
    mutating func cancelSlashPopup(prompt: String) {
        clearPopupOutput()
        popupRenderedLines = 0
        if let draft = savedDraft {
            let restored = draft.restore()
            buffer = restored.text
            cursor = restored.cursor
            savedDraft = nil
        }
        mode = .normal
        refreshDisplay(prompt: prompt)
    }

    /// 清除 popup 渲染的终端输出（上移 + 清行）。
    func clearPopupOutput() {
        clearRenderedOutput(lineCount: popupRenderedLines)
    }

    // MARK: - Slash Popup Event Dispatch

    /// 处理 slashPopup 模式下的按键事件。
    /// 返回 `.handled` 表示事件已消费，`.returnInput` 表示需要从 readRawLoop 返回。
    mutating func handleSlashPopupEvent(_ event: KeyEvent, prompt: String) -> SlashPopupEventResult {
        switch event {
        // AC2: 可打印 → 追加到 query → 重新过滤 → 重新渲染
        case .printable(let char):
            if buffer.utf8.count < ChatComposer.maxInputLength {
                insertChar(char)
                refreshSlashPopup(prompt: prompt)
            }

        // AC7: backspace → 退格 query
        case .backspace:
            if buffer == "/" {
                // 只有 "/" 时 backspace → 取消 popup，恢复 draft
                cancelSlashPopup(prompt: prompt)
            } else {
                deleteCharBackward()
                refreshSlashPopup(prompt: prompt)
            }

        // AC6: up/down → 移动选中
        case .up:
            if !popupItems.isEmpty && selectedPopupIndex > 0 {
                selectedPopupIndex -= 1
                refreshSlashPopupRender(prompt: prompt)
            }

        case .down:
            if !popupItems.isEmpty && selectedPopupIndex < popupItems.count - 1 {
                selectedPopupIndex += 1
                refreshSlashPopupRender(prompt: prompt)
            }

        // AC5: Tab → 仅补全命令名，始终留在编辑模式
        case .tab:
            if let _ = completeSelectedCommand() {
                clearPopupOutput()
                popupRenderedLines = 0
                mode = .normal
                refreshDisplay(prompt: prompt)
            }
            // 无选中或无匹配 → tab 忽略

        // AC5: Enter → 补全选中命令并执行（不接受参数时直接提交）
        case .enter:
            if let completed = completeSelectedCommand() {
                clearPopupOutput()
                popupRenderedLines = 0
                if completed.acceptsArgs {
                    // 留在编辑模式，光标在命令名后空格处
                    mode = .normal
                    refreshDisplay(prompt: prompt)
                } else {
                    // 不接受参数 → 直接提交
                    writeStdout("\r\n")
                    return .returnInput(buffer)
                }
            }
            // 无选中或无匹配 → enter 忽略

        // AC7: Esc → 取消 popup，恢复原始草稿
        case .escape:
            cancelSlashPopup(prompt: prompt)

        // Bracket paste — slashPopup 模式下取消 popup 并回到 normal
        case .bracketPasteStart, .bracketPasteEnd:
            cancelSlashPopup(prompt: prompt)

        // EOF
        case .eof:
            clearPopupOutput()
            return .returnInput(buffer.isEmpty ? nil : buffer)

        // Ctrl+C → 取消并退出输入
        case .ctrl("c"):
            clearPopupOutput()
            writeStdout("\r\n")
            return .returnInput(nil)

        // 其他键 — 忽略
        default:
            break
        }
        return .handled
    }
}
