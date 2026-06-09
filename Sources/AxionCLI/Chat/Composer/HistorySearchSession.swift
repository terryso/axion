
/// 历史搜索状态 — 表示 HistorySearchSession 的当前搜索阶段。
enum HistorySearchStatus: Equatable {
    /// 空闲（未进入搜索）
    case idle
    /// 搜索中（已输入 query 但尚未搜索，或正在输入）
    case searching
    /// 找到匹配项（index 为在 history 数组中的位置）
    case match(index: Int)
    /// 无匹配
    case noMatch
}

/// 历史搜索会话 — 管理当前会话历史搜索的完整生命周期。
///
/// 纯 struct，零外部依赖，零 I/O。
/// 搜索算法：大小写不敏感子串匹配 + 去重（通过 seen 集合）。
/// 搜索方向：Ctrl+R 向旧方向翻页（更旧匹配），Ctrl+S 向新方向翻页（更新匹配）。
struct HistorySearchSession: Equatable {

    /// 会话历史（由外部注入，最新消息在前/后）
    private let history: [String]
    /// 当前搜索查询字符串
    private(set) var query: String
    /// 当前搜索状态
    private(set) var status: HistorySearchStatus
    /// 已见过的匹配内容（去重：相同内容只匹配一次）
    private var seen: Set<String>

    // MARK: - Factory

    /// 初始化搜索会话。
    /// - Parameter history: 会话历史（顺序为 [旧 → 新]）
    /// - Returns: 新的搜索会话实例
    static func enterSearch(history: [String]) -> HistorySearchSession {
        HistorySearchSession(
            history: history,
            query: "",
            status: .idle,
            seen: []
        )
    }

    // MARK: - Query Operations

    /// 追加搜索字符 + 重新搜索。
    /// - Parameter char: 追加到 query 的字符
    /// - Returns: 更新后的搜索会话
    func appendingQuery(_ char: String) -> HistorySearchSession {
        var session = self
        session.query.append(char)
        session.searchFromStart()
        return session
    }

    /// 删除搜索字符末尾 + 重新搜索。
    /// - Returns: 更新后的搜索会话
    func removingLastQueryChar() -> HistorySearchSession {
        var session = self
        if !session.query.isEmpty {
            session.query.removeLast()
        }
        if session.query.isEmpty {
            session.status = .searching
            session.seen = []
        } else {
            session.seen = []
            session.searchFromStart()
        }
        return session
    }

    // MARK: - Navigation

    /// Ctrl+R: 跳到更旧的匹配。
    /// - Returns: 更新后的搜索会话
    func searchOlder() -> HistorySearchSession {
        var session = self
        session.findNextMatch(from: currentIndex, direction: .older)
        return session
    }

    /// Ctrl+S: 跳到更新的匹配。
    /// - Returns: 更新后的搜索会话
    func searchNewer() -> HistorySearchSession {
        var session = self
        session.findNextMatch(from: currentIndex, direction: .newer)
        return session
    }

    // MARK: - Current Match

    /// 当前匹配项的文本内容。
    var currentMatch: String? {
        guard case .match(let index) = status, index >= 0, index < history.count else {
            return nil
        }
        return history[index]
    }

    /// 当前匹配索引（-1 表示无匹配）。
    private var currentIndex: Int {
        guard case .match(let index) = status else { return -1 }
        return index
    }

    // MARK: - Private Search Logic

    /// 搜索方向
    private enum SearchDirection {
        case older  // 从当前位置向旧方向（index 递减）
        case newer  // 从当前位置向新方向（index 递增）
    }

    /// 从起始位置重新搜索（query 变化时）。
    /// 搜索方向：从最新的历史开始向前搜索（反向遍历 history）。
    private mutating func searchFromStart() {
        guard !query.isEmpty else {
            status = .searching
            seen = []
            return
        }

        let lowerQuery = query.lowercased()

        // 从最新的历史开始向前搜索（反向遍历）
        for i in stride(from: history.count - 1, through: 0, by: -1) {
            let entry = history[i]
            if entry.lowercased().contains(lowerQuery) && !seen.contains(entry) {
                status = .match(index: i)
                seen = [entry]
                return
            }
        }

        status = .noMatch
    }

    /// 从当前位置搜索下一个匹配。
    /// - Parameters:
    ///   - from: 当前匹配索引（-1 表示从头开始）
    ///   - direction: 搜索方向
    private mutating func findNextMatch(from currentIndex: Int, direction: SearchDirection) {
        guard !query.isEmpty else {
            status = .searching
            return
        }

        let lowerQuery = query.lowercased()

        switch direction {
        case .older:
            // Ctrl+R: 从当前位置向前搜索（更旧）
            let startIndex = currentIndex > 0 ? currentIndex - 1 : -1
            for i in stride(from: startIndex, through: 0, by: -1) {
                let entry = history[i]
                if entry.lowercased().contains(lowerQuery) && !seen.contains(entry) {
                    status = .match(index: i)
                    seen.insert(entry)
                    return
                }
            }
        case .newer:
            // Ctrl+S: 从当前位置向后搜索（更新）
            // 注意：不检查 seen，允许回溯之前找到的匹配
            let startIndex = currentIndex >= 0 ? currentIndex + 1 : 0
            for i in startIndex..<history.count {
                let entry = history[i]
                if entry.lowercased().contains(lowerQuery) {
                    status = .match(index: i)
                    return
                }
            }
        }

        // 无更多匹配 — 如果当前有匹配则保持，否则 noMatch
        if case .match = status {
            // 有当前匹配但无更多 → 保持当前匹配不变
            return
        }
        status = .noMatch
    }
}
