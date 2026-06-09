
// MARK: - History Search Mode Handling (AC2/AC3/AC4/AC5)

extension ChatComposer {

    /// 进入历史搜索模式 — AC2。
    mutating func enterHistorySearch(prompt: String) {
        // AC2: 保存当前 draft
        saveDraft()
        searchSession = HistorySearchSession.enterSearch(history: history)
        mode = .historySearch(query: "")
        // AC2: 渲染搜索 footer
        renderSearchFooter(query: "", status: .idle, matchedText: nil, prompt: prompt)
    }

    /// 处理 historySearch 模式下的按键事件。
    mutating func handleHistorySearchEvent(_ event: KeyEvent, prompt: String) {
        guard let session = searchSession else {
            mode = .normal
            return
        }

        switch event {
        // AC2: 可打印字符 → 追加到 query + 重新搜索
        case .printable(let char):
            let newSession = session.appendingQuery(char)
            searchSession = newSession
            mode = .historySearch(query: newSession.query)
            renderSearchFooter(
                query: newSession.query,
                status: newSession.status,
                matchedText: newSession.currentMatch,
                prompt: prompt
            )

        // AC2: Backspace → 删除 query 字符
        case .backspace:
            if session.query.isEmpty {
                // 空 query 时 backspace → 取消搜索，恢复 draft
                cancelHistorySearch(prompt: prompt)
            } else {
                let newSession = session.removingLastQueryChar()
                searchSession = newSession
                mode = .historySearch(query: newSession.query)
                renderSearchFooter(
                    query: newSession.query,
                    status: newSession.status,
                    matchedText: newSession.currentMatch,
                    prompt: prompt
                )
            }

        // AC3: Ctrl+R → 跳到更旧匹配
        case .ctrl("r"):
            let newSession = session.searchOlder()
            searchSession = newSession
            renderSearchFooter(
                query: newSession.query,
                status: newSession.status,
                matchedText: newSession.currentMatch,
                prompt: prompt
            )

        // AC3: Ctrl+S → 跳到更新匹配
        case .ctrl("s"):
            let newSession = session.searchNewer()
            searchSession = newSession
            renderSearchFooter(
                query: newSession.query,
                status: newSession.status,
                matchedText: newSession.currentMatch,
                prompt: prompt
            )

        // AC4: Enter → 采纳匹配结果
        case .enter:
            if let match = session.currentMatch {
                buffer = match
                cursor = buffer.count
            }
            clearSearchFooter()
            searchSession = nil
            mode = .normal
            savedDraft = nil  // 采纳后不需要恢复
            refreshDisplay(prompt: prompt)

        // AC5: Esc/Ctrl+C → 取消搜索，恢复原始 draft
        case .escape, .ctrl("c"):
            cancelHistorySearch(prompt: prompt)

        // EOF
        case .eof:
            clearSearchFooter()
            searchSession = nil
            mode = .normal
            if let draft = savedDraft {
                let restored = draft.restore()
                buffer = restored.text
                cursor = restored.cursor
                savedDraft = nil
            }
            refreshDisplay(prompt: prompt)

        // 其他键在搜索模式下忽略
        default:
            break
        }
    }

    /// 取消历史搜索 — AC5。
    mutating func cancelHistorySearch(prompt: String) {
        clearSearchFooter()
        searchSession = nil
        mode = .normal
        // AC5: 恢复进入搜索前的原始草稿
        if let draft = savedDraft {
            let restored = draft.restore()
            buffer = restored.text
            cursor = restored.cursor
            savedDraft = nil
        }
        refreshDisplay(prompt: prompt)
    }

    /// 渲染历史搜索 footer — AC2。
    /// 输出到 stderr：`(reverse-i-search)'query': matched_text`
    /// 同时刷新 prompt + buffer 显示。
    mutating func renderSearchFooter(
        query: String,
        status: HistorySearchStatus,
        matchedText: String?,
        prompt: String
    ) {
        // 清除旧 footer
        clearSearchFooter()

        let useColor = isTTY
        let dimCode = "\u{1B}[2m"
        let boldCode = "\u{1B}[1m"
        let resetCode = "\u{1B}[0m"

        let footer: String
        switch status {
        case .idle, .searching:
            let styledQuery = useColor ? "\(dimCode)\(query)\(resetCode)" : query
            footer = "(reverse-i-search)'\(styledQuery)': "
        case .match:
            let styledQuery = useColor ? "\(dimCode)\(query)\(resetCode)" : query
            let styledMatch = useColor ? "\(boldCode)\(matchedText ?? "")\(resetCode)" : (matchedText ?? "")
            footer = "(reverse-i-search)'\(styledQuery)': \(styledMatch)"
        case .noMatch:
            let styledQuery = useColor ? "\(dimCode)\(query)\(resetCode)" : query
            footer = "(reverse-i-search)'\(styledQuery)': no match"
        }

        searchFooterLines = 1
        writeStderr("\r\n\(footer)")
        // 重新显示当前 prompt + buffer
        writeStdout("\r\(prompt)\(buffer)\u{1B}[K")
    }

    /// 清除搜索 footer 渲染。
    func clearSearchFooter() {
        guard searchFooterLines > 0 else { return }
        // 上移 searchFooterLines 行
        writeStderr("\u{1B}[\(searchFooterLines)A")
        // 清除行
        writeStderr("\r\u{1B}[K")
        // 注意：不写下移再上移，因为只有一行 footer
    }
}
