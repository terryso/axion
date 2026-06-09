import Foundation
import Testing

@testable import AxionCLI

@Suite("SlashPopup (AC1/AC2/AC5/AC6/AC9)")
struct SlashPopupTests {

    /// 测试用 theme（TTY enabled）
    private var ttyTheme: ChatTheme {
        ChatTheme(profile: .ansi16, isTTY: true)
    }

    /// 测试用 theme（非 TTY）
    private var nonTTYTheme: ChatTheme {
        ChatTheme(profile: .unknown, isTTY: false)
    }

    // MARK: - Filter: 空查询

    @Test("空查询 '/' 返回所有可用命令")
    func emptyQueryReturnsAll() {
        let items = SlashPopup.filter(query: "/")
        #expect(items.count == SlashCommand.allCases.count)
    }

    @Test("空查询返回所有命令（按 rawValue 排序）")
    func emptyQuerySorted() {
        let items = SlashPopup.filter(query: "/")
        let names = items.map(\.command.rawValue)
        let sorted = names.sorted()
        #expect(names == sorted)
    }

    // MARK: - Filter: 前缀匹配

    @Test("/re 过滤返回 /resume")
    func queryReReturnsResume() {
        let items = SlashPopup.filter(query: "/re")
        #expect(items.count == 1)
        #expect(items[0].command == .resume)
    }

    @Test("/c 返回 /clear, /compact, /cost, /config")
    func queryCReturnsFour() {
        let items = SlashPopup.filter(query: "/c")
        let names = items.map(\.command.rawValue)
        #expect(names.contains("/clear"))
        #expect(names.contains("/compact"))
        #expect(names.contains("/cost"))
        #expect(names.contains("/config"))
        #expect(items.count == 4)
    }

    @Test("/h 返回 /help")
    func queryHReturnsHelp() {
        let items = SlashPopup.filter(query: "/h")
        #expect(items.count == 1)
        #expect(items[0].command == .help)
    }

    @Test("/co 返回 /compact, /cost, /config")
    func queryCoReturnsThree() {
        let items = SlashPopup.filter(query: "/co")
        let names = items.map(\.command.rawValue)
        #expect(names.contains("/compact"))
        #expect(names.contains("/cost"))
        #expect(names.contains("/config"))
        #expect(items.count == 3)
    }

    @Test("/xyz 无匹配返回空")
    func queryNoMatch() {
        let items = SlashPopup.filter(query: "/xyz")
        #expect(items.isEmpty)
    }

    // MARK: - Filter: 大小写不敏感

    @Test("/RE 大小写不敏感匹配 /resume")
    func caseInsensitive() {
        let items = SlashPopup.filter(query: "/RE")
        #expect(items.count == 1)
        #expect(items[0].command == .resume)
    }

    @Test("/Help 大小写不敏感匹配 /help")
    func caseInsensitiveHelp() {
        let items = SlashPopup.filter(query: "/Help")
        #expect(items.count == 1)
        #expect(items[0].command == .help)
    }

    // MARK: - Filter: 精确匹配优先

    @Test("精确匹配优先排列 — /help 在 /h* 结果中排第一")
    func exactMatchPriority() {
        let items = SlashPopup.filter(query: "/help")
        #expect(items.count == 1)
        #expect(items[0].command == .help)
    }

    // MARK: - Filter: 别名匹配

    @Test("/qu 匹配 quit 别名 → /exit")
    func aliasMatchQuit() {
        let items = SlashPopup.filter(query: "/qu")
        #expect(items.count == 1)
        #expect(items[0].command == .exit)
    }

    @Test("/q 匹配 /quit 别名 → /exit（无 /q 开头的 rawValue 命令）")
    func aliasMatchQ() {
        let items = SlashPopup.filter(query: "/q")
        #expect(items.count == 1)
        #expect(items[0].command == .exit)
    }

    // MARK: - Filter: 上下文过滤

    @Test("agent 忙碌时 /re 过滤掉 /resume")
    func agentBusyFilterWithQuery() {
        let ctx = SlashCommandContext(isAgentBusy: true, isSideSession: false)
        let items = SlashPopup.filter(query: "/re", context: ctx)
        #expect(items.isEmpty)
    }

    @Test("agent 忙碌时 /c 不包含 /resume 但包含其他")
    func agentBusyFilterCQuery() {
        let ctx = SlashCommandContext(isAgentBusy: true, isSideSession: false)
        let items = SlashPopup.filter(query: "/c", context: ctx)
        let names = items.map(\.command.rawValue)
        #expect(!names.contains("/resume"))
        #expect(names.contains("/clear"))
        #expect(names.contains("/compact"))
        #expect(names.contains("/cost"))
        #expect(names.contains("/config"))
    }

    @Test("agent 忙碌时空查询 '/' 不包含 /resume")
    func agentBusyEmptyQueryFiltersResume() {
        let ctx = SlashCommandContext(isAgentBusy: true, isSideSession: false)
        let items = SlashPopup.filter(query: "/", context: ctx)
        let names = items.map(\.command.rawValue)
        #expect(!names.contains("/resume"), "/resume should be filtered when agent busy")
        #expect(items.count == 9, "Should have 9 commands (all except /resume)")
    }

    // MARK: - Filter: matchRange

    @Test("前缀匹配时 matchRange 不为 nil")
    func matchRangeNotNil() {
        let items = SlashPopup.filter(query: "/he")
        #expect(items.count == 1)
        #expect(items[0].matchRange != nil)
    }

    @Test("空查询时 matchRange 为 nil")
    func matchRangeNilOnEmptyQuery() {
        let items = SlashPopup.filter(query: "/")
        for item in items {
            #expect(item.matchRange == nil)
        }
    }

    // MARK: - Render

    @Test("render 输出包含编号")
    func renderContainsNumbers() {
        let items = SlashPopup.filter(query: "/")
        let output = SlashPopup.render(items: Array(items.prefix(3)), selectedIndex: -1, theme: nonTTYTheme)
        #expect(output.contains("1."))
        #expect(output.contains("2."))
        #expect(output.contains("3."))
    }

    @Test("render 输出包含命令名")
    func renderContainsCommandNames() {
        let items = SlashPopup.filter(query: "/")
        let output = SlashPopup.render(items: Array(items.prefix(3)), selectedIndex: -1, theme: nonTTYTheme)
        // 至少应包含前几个命令的 rawValue
        for item in items.prefix(3) {
            #expect(output.contains(item.command.rawValue))
        }
    }

    @Test("render 输出包含描述")
    func renderContainsDescriptions() {
        let items = SlashPopup.filter(query: "/")
        let output = SlashPopup.render(items: Array(items.prefix(3)), selectedIndex: -1, theme: nonTTYTheme)
        // 每个命令的 helpText 应出现在输出中
        for item in items.prefix(3) {
            #expect(output.contains(item.command.helpText))
        }
    }

    @Test("render 选中标记 ▶ 出现在 selectedIndex 位置")
    func renderSelectedMarker() {
        let items = SlashPopup.filter(query: "/")
        let output = SlashPopup.render(items: Array(items.prefix(3)), selectedIndex: 1, theme: nonTTYTheme)
        #expect(output.contains(SlashPopup.selectedMarker))
    }

    @Test("render 无选中时不包含 ▶")
    func renderNoSelection() {
        let items = SlashPopup.filter(query: "/")
        let output = SlashPopup.render(items: Array(items.prefix(3)), selectedIndex: -1, theme: nonTTYTheme)
        #expect(!output.contains(SlashPopup.selectedMarker))
    }

    @Test("render TTY 模式匹配高亮包含 ANSI 码")
    func renderTTYHighlight() {
        let items = SlashPopup.filter(query: "/he")
        let output = SlashPopup.render(items: items, selectedIndex: -1, theme: ttyTheme)
        // ANSI cyan + bold: \u{1B}[1;36m
        #expect(output.contains("\u{1B}[1;36m"))
    }

    @Test("render 非 TTY 模式无 ANSI 码在匹配中")
    func renderNonTTYNoANSI() {
        let items = SlashPopup.filter(query: "/he")
        let output = SlashPopup.render(items: items, selectedIndex: -1, theme: nonTTYTheme)
        #expect(!output.contains("\u{1B}[1;36m"))
    }

    @Test("render 无匹配时输出'无匹配命令'")
    func renderNoMatch() {
        let output = SlashPopup.render(items: [], selectedIndex: -1, theme: nonTTYTheme)
        #expect(output.contains("无匹配命令"))
    }

    // MARK: - Performance (AC9)

    @Test("filter + render < 50ms（CaseIterable 遍历）")
    func performanceUnder50ms() {
        let start = ContinuousClock.now
        for _ in 0..<1000 {
            let items = SlashPopup.filter(query: "/c")
            _ = SlashPopup.render(items: items, selectedIndex: 0, theme: ttyTheme)
        }
        let elapsed = ContinuousClock.now - start
        let ms = Int(elapsed.components.seconds) * 1000
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        // 1000 次迭代应在 100ms 内完成（单次 < 0.1ms，远低于 50ms NFR）
        #expect(ms < 100, "1000 iterations took \(ms)ms, should be under 100ms")
    }
}
