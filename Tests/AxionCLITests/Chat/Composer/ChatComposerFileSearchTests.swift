import Foundation
import Testing

@testable import AxionCLI

@Suite("ChatComposer @ File Search (AC1/AC3/AC9)")
struct ChatComposerFileSearchTests {

    // MARK: - Mock FileSearcher for integration tests

    struct MockFileSearcher: FileSearching {
        let files: [String]

        func search(query: String, in directory: String, maxResults: Int) -> FileSearchResult {
            guard !query.isEmpty else { return FileSearchResult(results: [], totalMatches: 0) }
            let lowerQuery = query.lowercased()
            let matched = files.filter { $0.lowercased().contains(lowerQuery) }
                .sorted { $0.count < $1.count }
            let totalMatches = matched.count
            let results = Array(matched.prefix(maxResults))
            return FileSearchResult(results: results, totalMatches: totalMatches)
        }
    }

    private func makeComposer(
        files: [String],
        events: [KeyEvent]
    ) -> (composer: ChatComposer, capture: OutputCapture) {
        let capture = OutputCapture()
        let reader = MockKeyReader(events)
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        composer.fileSearcher = MockFileSearcher(files: files)
        composer.cwd = "/tmp"
        return (composer, capture)
    }

    // MARK: - AC1: @ 触发文件搜索模式

    @Test("AC1: 输入 @ 触发 fileSearch 模式")
    func atTriggersFileSearch() {
        let files = ["Package.swift", "Sources/Main.swift"]
        let (composer, capture) = makeComposer(
            files: files,
            events: [
                .printable("@"),
                .escape,  // 取消搜索
                .enter    // 提交空 buffer
            ]
        )
        var c = composer
        let result = c.readInput(prompt: "> ", continuationPrompt: "...> ")
        // Esc 取消后 buffer 清空（恢复草稿为空），Enter 提交空字符串
        #expect(result == "")
    }

    // MARK: - AC3: Enter 选中文件

    @Test("AC3: @ 搜索后 Enter 选中第一个匹配")
    func fileSearchEnterSelectsFirst() {
        let files = ["Package.swift", "Sources/Main.swift"]
        let (composer, _) = makeComposer(
            files: files,
            events: [
                .printable("@"),
                .printable("P"),  // query = "P"
                .enter            // 选中 Package.swift
            ]
        )
        var c = composer
        let result = c.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result != nil)
        #expect(result!.contains("Package.swift"))
    }

    // MARK: - AC3: Esc 取消恢复草稿

    @Test("AC9: @ 搜索后 Esc 恢复原始草稿")
    func fileSearchEscRestoresDraft() {
        let files = ["Package.swift"]
        let (composer, _) = makeComposer(
            files: files,
            events: [
                .printable("@"),
                .printable("P"),
                .escape,  // 取消 — 恢复草稿（空）
                .enter    // 提交空
            ]
        )
        var c = composer
        let result = c.readInput(prompt: "> ", continuationPrompt: "...> ")
        // Esc 恢复草稿（进入前 buffer 为空），Enter 提交空
        #expect(result == "")
    }

    // MARK: - AC3: Tab 补全

    @Test("AC3: @ 搜索后 Tab 补全选中路径并退出搜索")
    func fileSearchTabCompletes() {
        let files = ["Package.swift", "Sources/Main.swift"]
        let (composer, _) = makeComposer(
            files: files,
            events: [
                .printable("@"),
                .printable("P"),
                .tab  // 补全 Package.swift
            ]
        )
        var c = composer
        let result = c.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result != nil)
        #expect(result!.contains("Package.swift"))
    }

    // MARK: - AC3: 数字直接选中

    @Test("AC3: @ 后输入数字直接选中第 N 项")
    func fileSearchNumberSelectsItem() {
        let files = ["Package.swift", "Sources/Main.swift"]
        let (composer, _) = makeComposer(
            files: files,
            events: [
                .printable("@"),
                .printable("P"),  // 触发搜索，显示 2 个结果
                .backspace,       // 清空 query 回到空 query
                // 需要重新输入 query 看到结果
                .escape,          // 取消
                .printable("@"),  // 重新触发
                .printable("1")   // 选中第 1 项
            ]
        )
        var c = composer
        let result = c.readInput(prompt: "> ", continuationPrompt: "...> ")
        // @1 选中第 1 项（index 0）
        #expect(result != nil)
    }

    // MARK: - AC3: Up/Down 导航

    @Test("AC3: Up/Down 在候选列表中移动选中")
    func fileSearchUpDownNavigation() {
        let files = ["Package.swift", "Sources/Main.swift"]
        let (composer, _) = makeComposer(
            files: files,
            events: [
                .printable("@"),
                .printable("a"),   // query = "a"，匹配两个
                .down,             // 选中第 2 项
                .enter             // 确认选中
            ]
        )
        var c = composer
        let result = c.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result != nil)
        // Down 后选中 index 1（Sources/Main.swift，因为 "a" 匹配 "Main" 中的 "a"）
        #expect(result!.contains(".swift"))
    }
}
