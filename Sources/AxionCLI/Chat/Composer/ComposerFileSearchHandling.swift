
// MARK: - File Search Mode Handling (Story 38.6, AC1/AC2/AC3/AC9)

extension ChatComposer {

    /// 进入文件搜索模式 — AC1。
    mutating func enterFileSearch(prompt: String) {
        // AC9: 保存草稿快照（@ 前的状态，此时 buffer == "@"）
        fileSearchDraftBackup = ComposerDraft.snapshot(text: "", cursor: 0)
        mode = .fileSearch(query: "")
        fileSearchSelectedIndex = 0
        // 执行初始搜索（空 query → 结果为空，显示提示）
        let initialResult = fileSearcher.search(query: "", in: cwd, maxResults: 20)
        cachedFileResults = initialResult.results
        totalFileMatches = initialResult.totalMatches
        refreshFileSearch(prompt: prompt)
    }

    /// 处理 fileSearch 模式下的按键事件。AC1/AC3/AC9。
    mutating func handleFileSearchEvent(_ event: KeyEvent, prompt: String) {
        switch event {
        // AC1: 可打印字符 → 追加到 query → 搜索 → 渲染
        case .printable(let char):
            if case .fileSearch(var query) = mode {
                // AC3: @ 后输入数字 → 直接选中第 N 项
                if let num = Int(String(char)), num >= 1 && num <= 9, query.isEmpty {
                    selectFileSearchItem(index: num - 1, prompt: prompt)
                    return
                }
                query.append(char)
                mode = .fileSearch(query: query)
                buffer = "@" + query
                cursor = buffer.count
                let searchResult = fileSearcher.search(query: query, in: cwd, maxResults: 20)
                cachedFileResults = searchResult.results
                totalFileMatches = searchResult.totalMatches
                fileSearchSelectedIndex = 0
                refreshFileSearch(prompt: prompt)
            }

        // AC3: Enter → 选中第一个匹配
        case .enter:
            if !cachedFileResults.isEmpty {
                selectFileSearchItem(index: fileSearchSelectedIndex, prompt: prompt)
            } else {
                // 无匹配时退出搜索，保留 @query 作为普通文本
                clearFileSearchOutput()
                fileSearchRenderedLines = 0
                mode = .normal
                fileSearchDraftBackup = nil
                refreshDisplay(prompt: prompt)
            }

        // AC3: Esc → 取消搜索，恢复草稿
        case .escape:
            cancelFileSearch(prompt: prompt)

        // AC3: Up/Down → 在候选列表中导航
        case .up:
            if !cachedFileResults.isEmpty && fileSearchSelectedIndex > 0 {
                fileSearchSelectedIndex -= 1
                refreshFileSearch(prompt: prompt)
            }

        case .down:
            if !cachedFileResults.isEmpty && fileSearchSelectedIndex < cachedFileResults.count - 1 {
                fileSearchSelectedIndex += 1
                refreshFileSearch(prompt: prompt)
            }

        // AC3: Tab → 补全当前选中项路径（继续在 fileSearch 模式）
        case .tab:
            if !cachedFileResults.isEmpty {
                let selected = cachedFileResults[fileSearchSelectedIndex]
                // 替换 buffer 为草稿文本 + 选中路径
                buffer = (fileSearchDraftBackup?.text ?? "") + selected + " "
                cursor = buffer.count
                // 退出搜索模式
                clearFileSearchOutput()
                fileSearchRenderedLines = 0
                mode = .normal
                fileSearchDraftBackup = nil
                refreshDisplay(prompt: prompt)
            }

        // Backspace → 删除 query 字符
        case .backspace:
            if case .fileSearch(var query) = mode {
                if query.isEmpty {
                    // 空 query 时 backspace → 取消搜索
                    cancelFileSearch(prompt: prompt)
                } else {
                    query.removeLast()
                    mode = .fileSearch(query: query)
                    buffer = "@" + query
                    cursor = buffer.count
                    let backspaceResult = fileSearcher.search(query: query, in: cwd, maxResults: 20)
                    cachedFileResults = backspaceResult.results
                    totalFileMatches = backspaceResult.totalMatches
                    fileSearchSelectedIndex = 0
                    refreshFileSearch(prompt: prompt)
                }
            }

        // Ctrl+C → 取消搜索
        case .ctrl("c"):
            cancelFileSearch(prompt: prompt)
            writeStdout("\r\n")
            // 不返回 nil — 只是取消搜索回到 normal
            // But to be consistent with other modes, let's just cancel
            mode = .normal

        // EOF
        case .eof:
            clearFileSearchOutput()
            if !cachedFileResults.isEmpty {
                selectFileSearchItem(index: 0, prompt: prompt)
            } else {
                mode = .normal
            }

        default:
            break
        }
    }

    /// 选中文件搜索结果中指定索引的项。AC3。
    mutating func selectFileSearchItem(index: Int, prompt: String) {
        guard !cachedFileResults.isEmpty && index >= 0 && index < cachedFileResults.count else { return }
        let idx = min(index, cachedFileResults.count - 1)
        let selected = cachedFileResults[idx]
        // 替换 @query 为路径，恢复到搜索前的草稿文本 + 路径
        let prefix = fileSearchDraftBackup?.text ?? ""
        buffer = prefix + selected + " "
        cursor = buffer.count
        clearFileSearchOutput()
        fileSearchRenderedLines = 0
        mode = .normal
        fileSearchDraftBackup = nil
        refreshDisplay(prompt: prompt)
    }

    /// 刷新文件搜索显示（搜索 + 渲染）。AC2。
    mutating func refreshFileSearch(prompt: String) {
        let theme = ensureTheme()
        let items = FileSearchPopup.filter(
            query: currentFileSearchQuery,
            results: cachedFileResults
        )
        let rendered = FileSearchPopup.render(
            items: items,
            selectedIndex: fileSearchSelectedIndex,
            theme: theme,
            totalMatches: totalFileMatches
        )
        let newLines = rendered.components(separatedBy: "\n").count

        clearFileSearchOutput()
        fileSearchRenderedLines = newLines

        // 渲染文件搜索 popup（\n → \r\n，确保 raw mode 下每行回到第 0 列）
        let terminalRendered = rendered.replacingOccurrences(of: "\n", with: "\r\n")
        writeStdout("\r\n\(terminalRendered)")
        // 光标移回输入行
        writeStdout("\u{1B}[\(fileSearchRenderedLines)A")
        writeStdout("\r\(prompt)\(buffer)\u{1B}[K")
    }

    /// 取消文件搜索，恢复草稿。AC9。
    mutating func cancelFileSearch(prompt: String) {
        clearFileSearchOutput()
        fileSearchRenderedLines = 0
        // AC9: restore_draft() 原子恢复
        if let draft = fileSearchDraftBackup {
            let restored = draft.restore()
            buffer = restored.text
            cursor = restored.cursor
            fileSearchDraftBackup = nil
        }
        mode = .normal
        refreshDisplay(prompt: prompt)
    }

    /// 清除文件搜索渲染的终端输出。
    func clearFileSearchOutput() {
        clearRenderedOutput(lineCount: fileSearchRenderedLines)
    }

    /// 当前 fileSearch query（从 mode 提取）。
    var currentFileSearchQuery: String {
        if case .fileSearch(let query) = mode {
            return query
        }
        return ""
    }
}
