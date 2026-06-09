import Foundation
import Testing

@testable import AxionCLI

@Suite("FileSearchPopup (AC2/AC3)")
struct FileSearchPopupTests {

    // MARK: - Filter (AC2)

    @Test("filter — 空查询返回全部项")
    func filterEmptyQueryReturnsAll() {
        let results = ["a.swift", "b.swift", "c.swift"]
        let items = FileSearchPopup.filter(query: "", results: results)
        #expect(items.count == 3)
        #expect(items[0].path == "a.swift")
    }

    @Test("filter — 子串匹配过滤")
    func filterSubstringMatch() {
        let results = [
            "Sources/Main.swift",
            "Tests/MainTests.swift",
            "Package.swift"
        ]
        let items = FileSearchPopup.filter(query: "Main", results: results)
        #expect(items.count == 2)
        // 检查 matchRange 不为 nil（找到匹配高亮范围）
        #expect(items[0].matchRange != nil)
    }

    @Test("filter — 大小写不敏感")
    func filterCaseInsensitive() {
        let results = ["Sources/Hello.swift"]
        let items = FileSearchPopup.filter(query: "hello", results: results)
        #expect(items.count == 1)
        #expect(items[0].matchRange != nil)
    }

    @Test("filter — 无匹配返回空")
    func filterNoMatch() {
        let results = ["a.swift", "b.swift"]
        let items = FileSearchPopup.filter(query: "xyz", results: results)
        #expect(items.isEmpty)
    }

    // MARK: - Render (AC2)

    @Test("render — 编号列表格式验证")
    func renderNumberedList() {
        let items = [
            FileSearchPopupItem(path: "Package.swift", matchRange: nil),
            FileSearchPopupItem(path: "Sources/Main.swift", matchRange: nil)
        ]
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let rendered = FileSearchPopup.render(items: items, selectedIndex: -1, theme: theme)
        #expect(rendered.contains("1."))
        #expect(rendered.contains("Package.swift"))
        #expect(rendered.contains("2."))
        #expect(rendered.contains("Sources/Main.swift"))
    }

    @Test("render — 空结果显示无匹配提示")
    func renderEmptyResults() {
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let rendered = FileSearchPopup.render(items: [], selectedIndex: -1, theme: theme)
        #expect(rendered.contains("无匹配文件"))
    }

    @Test("render — 截断提示（totalMatches > items.count）")
    func renderTruncationHint() {
        let items = (1...5).map { FileSearchPopupItem(path: "file_\($0).swift", matchRange: nil) }
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let rendered = FileSearchPopup.render(items: items, selectedIndex: -1, theme: theme, totalMatches: 30)
        #expect(rendered.contains("显示前 5 条"))
        #expect(rendered.contains("共 30 个匹配"))
    }

    @Test("render — 选中项高亮（TTY 模式）")
    func renderSelectedHighlight() {
        let items = [
            FileSearchPopupItem(path: "a.swift", matchRange: nil),
            FileSearchPopupItem(path: "b.swift", matchRange: nil)
        ]
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let rendered = FileSearchPopup.render(items: items, selectedIndex: 0, theme: theme)
        // 选中项包含 ▶ marker
        #expect(rendered.contains(FileSearchPopup.selectedMarker))
    }
}
