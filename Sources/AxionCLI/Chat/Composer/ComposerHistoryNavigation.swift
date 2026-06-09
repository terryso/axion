
// MARK: - History Navigation (AC1)

extension ChatComposer {

    /// 历史导航方向
    enum HistoryDirection {
        case older  // Up → 更旧
        case newer  // Down → 更新
    }

    /// 执行历史导航 — AC1。
    mutating func navigateHistory(direction: HistoryDirection, prompt: String) {
        // 首次进入历史浏览时保存当前空 buffer
        if historyIndex == -1 {
            preHistoryDraft = buffer
        }

        switch direction {
        case .older:
            // Up: 向更旧方向移动
            guard !history.isEmpty else { return }
            if historyIndex == -1 {
                historyIndex = history.count - 1
            } else if historyIndex > 0 {
                historyIndex -= 1
            }
            // 到达边界不再移动

        case .newer:
            // Down: 向更新方向移动
            if historyIndex < history.count - 1 {
                historyIndex += 1
            } else {
                // 回到浏览前的状态
                historyIndex = -1
                buffer = preHistoryDraft
                cursor = buffer.count
                refreshDisplay(prompt: prompt)
                return
            }
        }

        buffer = history[historyIndex]
        cursor = buffer.count
        refreshDisplay(prompt: prompt)
    }
}
