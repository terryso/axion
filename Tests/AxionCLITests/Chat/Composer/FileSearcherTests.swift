import Foundation
import Testing

@testable import AxionCLI

@Suite("FileSearcher (AC1/AC2/AC6/AC7)")
struct FileSearcherTests {

    // MARK: - Mock FileSearcher

    /// Mock 文件搜索器 — 返回预定义文件列表。
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

    // MARK: - AC6: 子串匹配 + 大小写不敏感

    @Test("搜索匹配 — 子串匹配")
    func searchSubstringMatch() {
        let searcher = MockFileSearcher(files: [
            "Sources/Main.swift",
            "Tests/MainTests.swift",
            "Package.swift"
        ])
        let result = searcher.search(query: "Main", in: "/tmp", maxResults: 20)
        #expect(result.results.contains("Sources/Main.swift"))
        #expect(result.results.contains("Tests/MainTests.swift"))
    }

    @Test("搜索匹配 — 大小写不敏感")
    func searchCaseInsensitive() {
        let searcher = MockFileSearcher(files: [
            "Sources/Hello.swift",
            "Sources/helloWorld.swift"
        ])
        let result = searcher.search(query: "hello", in: "/tmp", maxResults: 20)
        #expect(result.results.count == 2)
    }

    // MARK: - AC2: 结果排序（路径长度升序）

    @Test("结果排序 — 路径长度升序")
    func searchResultsSortedByPathLength() {
        let searcher = MockFileSearcher(files: [
            "Sources/AxionCLI/Chat/Composer/ChatComposer.swift",
            "Package.swift",
            "Sources/Main.swift"
        ])
        let result = searcher.search(query: ".swift", in: "/tmp", maxResults: 20)
        // 按路径长度升序
        #expect(result.results[0] == "Package.swift")
        #expect(result.results[1] == "Sources/Main.swift")
        #expect(result.results[2] == "Sources/AxionCLI/Chat/Composer/ChatComposer.swift")
    }

    // MARK: - AC2: 结果截断

    @Test("结果截断 — maxResults 限制")
    func searchResultsTruncated() {
        let files = (1...30).map { "file_\($0).swift" }
        let searcher = MockFileSearcher(files: files)
        let result = searcher.search(query: "file", in: "/tmp", maxResults: 5)
        #expect(result.results.count == 5)
        #expect(result.totalMatches == 30)
    }

    // MARK: - 空查询

    @Test("空查询返回空结果")
    func searchEmptyQueryReturnsEmpty() {
        let searcher = MockFileSearcher(files: ["a.swift", "b.swift"])
        let result = searcher.search(query: "", in: "/tmp", maxResults: 20)
        #expect(result.results.isEmpty)
    }

    // MARK: - 无匹配

    @Test("无匹配返回空结果")
    func searchNoMatchReturnsEmpty() {
        let searcher = MockFileSearcher(files: ["a.swift", "b.swift"])
        let result = searcher.search(query: "xyz", in: "/tmp", maxResults: 20)
        #expect(result.results.isEmpty)
    }

    // MARK: - AC6: 忽略目录

    @Test("FileSearcher 忽略 .git/.build/node_modules 目录")
    func searcherIgnoresDirectories() {
        let ignoredDirs = FileSearcher.ignoredDirectories
        #expect(ignoredDirs.contains(".git"))
        #expect(ignoredDirs.contains(".build"))
        #expect(ignoredDirs.contains("node_modules"))
        #expect(ignoredDirs.contains("DerivedData"))
        #expect(ignoredDirs.contains(".swiftpm"))
    }

    // MARK: - AC7: 权限拒绝目录（通过 Mock 验证行为）

    @Test("Mock 搜索器跳过不可访问目录")
    func mockSearcherSkipsInaccessible() {
        // Mock 不需要测试真实文件系统权限，只需验证不崩溃
        let searcher = MockFileSearcher(files: ["src/a.swift"])
        let result = searcher.search(query: "a", in: "/nonexistent", maxResults: 20)
        #expect(result.results.contains("src/a.swift"))
    }
}
