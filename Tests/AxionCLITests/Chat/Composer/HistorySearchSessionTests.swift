import Testing
@testable import AxionCLI

@Suite("HistorySearchSession")
struct HistorySearchSessionTests {

    // MARK: - 搜索匹配

    @Test("搜索匹配：输入 query → 找到匹配")
    func searchMatch() {
        let history = ["hello world", "git commit", "git push"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("g")
        #expect(session.currentMatch != nil)
        #expect(session.currentMatch?.contains("git") == true)
    }

    @Test("搜索不匹配：输入 query → noMatch")
    func searchNoMatch() {
        let history = ["hello world", "git commit"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("zzz")
        #expect(session.currentMatch == nil)
        if case .noMatch = session.status {
            // expected
        } else {
            Issue.record("Expected noMatch, got \(session.status)")
        }
    }

    // MARK: - Ctrl+R/Ctrl+S 翻页

    @Test("Ctrl+R 翻页：多个匹配间跳转")
    func searchOlder() {
        let history = ["git commit", "git push", "git pull"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("git")

        // 初始匹配应该是最新的（index 2）
        #expect(session.currentMatch == "git pull")

        // Ctrl+R → 跳到更旧
        let older = session.searchOlder()
        #expect(older.currentMatch == "git push")

        // 再 Ctrl+R → 更旧
        let older2 = older.searchOlder()
        #expect(older2.currentMatch == "git commit")
    }

    @Test("Ctrl+S 翻页：反向跳转")
    func searchNewer() {
        let history = ["git commit", "git push", "git pull"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("git")

        // 初始匹配应该是最新的（index 2）
        #expect(session.currentMatch == "git pull")

        // 先 Ctrl+R 两次到最旧
        let atOldest = session.searchOlder().searchOlder()
        #expect(atOldest.currentMatch == "git commit")

        // Ctrl+S → 跳到更新（不检查 seen，允许回溯）
        let newer = atOldest.searchNewer()
        #expect(newer.currentMatch == "git push")

        // 再 Ctrl+S → 跳到最新
        let newer2 = newer.searchNewer()
        #expect(newer2.currentMatch == "git pull")
    }

    // MARK: - 去重

    @Test("去重：相同内容只匹配一次")
    func deduplication() {
        let history = ["hello", "hello", "world"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("hello")

        // 初始匹配
        #expect(session.currentMatch == "hello")

        // Ctrl+R → 由于去重，重复的 "hello" 被跳过，无更旧匹配
        // 行为：保持在当前匹配（因为已是最旧可用的）
        let older = session.searchOlder()
        if case .match(let idx) = older.status {
            // 去重后应保持在原位
            // 初始匹配在 index 1（history=["hello"(0), "hello"(1), "world"(2)]，
            // "world" 不匹配，所以首个匹配是 index 1）
            #expect(older.currentMatch == "hello")
            #expect(idx == 1)  // 保持在初始匹配
        }
    }

    // MARK: - 大小写不敏感

    @Test("大小写不敏感匹配")
    func caseInsensitive() {
        let history = ["Git Commit", "GIT PUSH"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("git")
        #expect(session.currentMatch != nil)
        #expect(session.currentMatch?.lowercased().contains("git") == true)
    }

    // MARK: - 空历史

    @Test("空历史 → 搜索直接 noMatch")
    func emptyHistory() {
        let session = HistorySearchSession.enterSearch(history: [])
            .appendingQuery("anything")
        #expect(session.currentMatch == nil)
        if case .noMatch = session.status {
            // expected
        } else {
            Issue.record("Expected noMatch, got \(session.status)")
        }
    }

    // MARK: - Backspace

    @Test("backspace 删除 query → 重新搜索")
    func backspaceResets() {
        let history = ["hello world"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("hellox")

        // "hellox" 不匹配 → noMatch
        #expect(session.currentMatch == nil)

        // 删除 "x" → "hello" → 匹配
        let afterBackspace = session.removingLastQueryChar()
        #expect(afterBackspace.currentMatch == "hello world")
    }

    @Test("backspace 删光 query → 搜索状态重置")
    func backspaceAll() {
        let history = ["hello"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("h")
        let afterBackspace = session.removingLastQueryChar()
        if case .searching = afterBackspace.status {
            // expected
        } else {
            Issue.record("Expected searching, got \(afterBackspace.status)")
        }
        #expect(afterBackspace.query == "")
    }

    // MARK: - 边界

    @Test("Ctrl+R 到达边界不再移动")
    func olderBoundary() {
        let history = ["only one"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("only")
        #expect(session.currentMatch == "only one")

        // Ctrl+R → 无更旧匹配，保持当前
        let older = session.searchOlder()
        if case .match(let idx) = older.status {
            #expect(idx == 0)
        } else {
            Issue.record("Expected match at boundary, got \(older.status)")
        }
    }

    @Test("Ctrl+S 在最新位置无更新匹配")
    func newerBoundary() {
        let history = ["only one"]
        let session = HistorySearchSession.enterSearch(history: history)
            .appendingQuery("only")

        let newer = session.searchNewer()
        // 无更旧匹配，保持当前
        if case .match(let idx) = newer.status {
            #expect(idx == 0)
        } else {
            Issue.record("Expected match at boundary, got \(newer.status)")
        }
    }
}
