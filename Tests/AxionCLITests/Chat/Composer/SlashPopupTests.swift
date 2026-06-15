import Foundation
import Testing

@testable import AxionCLI

@Suite("SlashPopup (AC1/AC2/AC5/AC6/AC9 + Skill 补全)")
struct SlashPopupTests {

    /// 测试用 theme（TTY enabled）
    private var ttyTheme: ChatTheme {
        ChatTheme(profile: .ansi16, isTTY: true)
    }

    /// 测试用 theme（非 TTY）
    private var nonTTYTheme: ChatTheme {
        ChatTheme(profile: .unknown, isTTY: false)
    }

    // MARK: - Test Helpers

    /// 示例 skill 列表
    private var sampleSkills: [SkillInfo] {
        [
            SkillInfo(name: "screenshot-analyze", description: "Capture and analyze the current screen, combining visual screenshot with accessibility tree data to produce a structured description of UI elements.", aliases: ["sa", "analyze", "screen"]),
            SkillInfo(name: "data-extract", description: "Extract structured data (tables, lists, text content) from the current application window's UI elements.", aliases: ["extract", "de"]),
            SkillInfo(name: "form-fill", description: "Identify form fields in the current window and automatically fill them with user-provided data.", aliases: ["fill", "ff"]),
        ]
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
        let names = items.map(\.kind.displayName)
        let sorted = names.sorted()
        #expect(names == sorted)
    }

    // MARK: - Filter: 前缀匹配

    @Test("/re 过滤返回 /resume")
    func queryReReturnsResume() {
        let items = SlashPopup.filter(query: "/re")
        #expect(!items.isEmpty)
        if case .command(let cmd) = items[0].kind {
            #expect(cmd == .resume)
        } else {
            Issue.record("Expected command, got skill")
        }
    }

    @Test("/c 返回前缀和模糊匹配的命令")
    func queryCReturnsPrefixAndFuzzyMatches() {
        let items = SlashPopup.filter(query: "/c")
        let names = items.map(\.kind.displayName)
        #expect(names.contains("/archive"))
        #expect(names.contains("/clear"))
        #expect(names.contains("/compact"))
        #expect(names.contains("/cost"))
        #expect(names.contains("/config"))
        #expect(names.contains("/copy"))
        #expect(names.contains("/arch"))
        #expect(names.contains("/mcp"))
        #expect(items.count == 8)
    }

    @Test("/h 返回 /help")
    func queryHReturnsHelp() {
        let items = SlashPopup.filter(query: "/h")
        #expect(!items.isEmpty)
        if case .command(let cmd) = items[0].kind {
            #expect(cmd == .help)
        } else {
            Issue.record("Expected command, got skill")
        }
    }

    @Test("/mc 优先返回 /mcp")
    func queryMCReturnsMCP() {
        let items = SlashPopup.filter(query: "/mc")
        let names = items.map(\.kind.displayName)
        #expect(names.first == "/mcp")
    }

    @Test("/co 返回 /compact, /cost, /config, /copy")
    func queryCoReturnsFour() {
        let items = SlashPopup.filter(query: "/co")
        let names = items.map(\.kind.displayName)
        #expect(names.contains("/compact"))
        #expect(names.contains("/cost"))
        #expect(names.contains("/config"))
        #expect(names.contains("/copy"))
        #expect(items.count == 4)
    }

    @Test("/xyz 无匹配返回空")
    func queryNoMatch() {
        let items = SlashPopup.filter(query: "/xyz")
        #expect(items.isEmpty)
    }

    @Test("模糊包含匹配 — /opy 返回 /copy")
    func fuzzyContainsMatch() {
        let items = SlashPopup.filter(query: "/opy")
        let names = items.map(\.kind.displayName)
        #expect(names == ["/copy"])
    }

    @Test("模糊子序列匹配 — /cnf 返回 /config")
    func fuzzySubsequenceMatch() {
        let items = SlashPopup.filter(query: "/cnf")
        let names = items.map(\.kind.displayName)
        #expect(names == ["/config"])
    }

    // MARK: - Filter: 大小写不敏感

    @Test("/RE 大小写不敏感匹配 /resume")
    func caseInsensitive() {
        let items = SlashPopup.filter(query: "/RE")
        #expect(!items.isEmpty)
        if case .command(let cmd) = items[0].kind {
            #expect(cmd == .resume)
        } else {
            Issue.record("Expected command, got skill")
        }
    }

    @Test("/Help 大小写不敏感匹配 /help")
    func caseInsensitiveHelp() {
        let items = SlashPopup.filter(query: "/Help")
        #expect(items.count == 1)
        if case .command(let cmd) = items[0].kind {
            #expect(cmd == .help)
        } else {
            Issue.record("Expected command, got skill")
        }
    }

    // MARK: - Filter: 精确匹配优先

    @Test("精确匹配优先排列 — /help 在 /h* 结果中排第一")
    func exactMatchPriority() {
        let items = SlashPopup.filter(query: "/help")
        #expect(items.count == 1)
        if case .command(let cmd) = items[0].kind {
            #expect(cmd == .help)
        } else {
            Issue.record("Expected command, got skill")
        }
    }

    // MARK: - Filter: 别名匹配（命令）

    @Test("/qu 匹配 quit 别名 → /exit")
    func aliasMatchQuit() {
        let items = SlashPopup.filter(query: "/qu")
        #expect(items.count == 1)
        if case .command(let cmd) = items[0].kind {
            #expect(cmd == .exit)
        } else {
            Issue.record("Expected command, got skill")
        }
    }

    @Test("/q 匹配 /quit 别名 → /exit（无 /q 开头的 rawValue 命令）")
    func aliasMatchQ() {
        let items = SlashPopup.filter(query: "/q")
        #expect(items.count == 1)
        if case .command(let cmd) = items[0].kind {
            #expect(cmd == .exit)
        } else {
            Issue.record("Expected command, got skill")
        }
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
        let names = items.map(\.kind.displayName)
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
        let names = items.map(\.kind.displayName)
        #expect(!names.contains("/resume"), "/resume should be filtered when agent busy")
        #expect(!names.contains("/arch"), "/arch should be filtered when agent busy")
        #expect(!names.contains("/storage"), "/storage should be filtered when agent busy")
        #expect(names.contains("/mcp"), "/mcp should remain available when agent busy")
        #expect(items.count == 11, "Should have 11 commands (all except /resume, /new, /fork, /archive, /skills, /apps, /arch, /storage)")
    }

    // MARK: - Filter: matchRange

    @Test("前缀匹配时 matchRange 不为 nil")
    func matchRangeNotNil() {
        let items = SlashPopup.filter(query: "/he")
        #expect(!items.isEmpty)
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
        for item in items.prefix(3) {
            #expect(output.contains(item.kind.displayName))
        }
    }

    @Test("render 输出包含描述")
    func renderContainsDescriptions() {
        let items = SlashPopup.filter(query: "/")
        let output = SlashPopup.render(items: Array(items.prefix(3)), selectedIndex: -1, theme: nonTTYTheme)
        for item in items.prefix(3) {
            if case .command(let cmd) = item.kind {
                #expect(output.contains(cmd.helpText))
            }
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

    @Test("render 大列表时只显示第一页 20 个候选，初始编号从 1 开始")
    func renderLargeListShowsFirstPageOnly() {
        let manySkills = (1...60).map {
            SkillInfo(name: "skill-\($0)", description: "Skill \($0)", aliases: [])
        }
        let items = SlashPopup.filter(query: "/", skills: manySkills)
        let output = SlashPopup.render(
            items: items,
            selectedIndex: 0,
            theme: nonTTYTheme,
            maxItems: 20,
            startIndex: 0
        )

        #expect(output.contains("1."))
        #expect(output.contains("20."))
        #expect(!output.contains("21."))
        #expect(!output.contains("49."))
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
        // 1000 次迭代应在 300ms 内完成。阈值留 3 倍余量：并行测试/CI 负载下渲染会变慢，
        // 100ms 边界阈值会偶发 flaky（实测并行下可达 ~100ms）。NFR 单次 <0.1ms 不变。
        #expect(ms < 300, "1000 iterations took \(ms)ms, should be under 300ms")
    }

    // MARK: - Skill: 空查询包含 skill (AC1)

    @Test("AC1: 空 '/' 查询包含 skill")
    func skillAppearsInEmptyQuery() {
        let items = SlashPopup.filter(query: "/", skills: sampleSkills)
        let names = items.map(\.kind.displayName)
        #expect(names.contains("/screenshot-analyze"))
        #expect(names.contains("/data-extract"))
        #expect(names.contains("/form-fill"))
    }

    @Test("AC1: 空 '/' 查询未使用项时内置命令排在 skill 前面")
    func unusedCommandsSortBeforeUnusedSkills() {
        let items = SlashPopup.filter(query: "/", skills: sampleSkills)
        let names = items.map(\.kind.displayName)
        #expect(names.prefix(SlashCommand.allCases.count).allSatisfy { name in
            SlashCommand.allCases.contains { $0.rawValue == name }
        })
        #expect(Array(names.suffix(sampleSkills.count)) == ["/data-extract", "/form-fill", "/screenshot-analyze"])
    }

    @Test("空 '/' 查询按最近 7 天使用次数排序")
    func emptyQuerySortsByRecentUsageCount() {
        let items = SlashPopup.filter(
            query: "/",
            skills: sampleSkills,
            recentUsageCounts: ["/screenshot-analyze": 3, "/help": 2, "/cost": 1]
        )
        let names = items.map(\.kind.displayName)
        #expect(Array(names.prefix(3)) == ["/screenshot-analyze", "/help", "/cost"])
    }

    @Test("非空查询同匹配质量下按最近使用次数排序")
    func querySortsByRecentUsageCountAfterMatchQuality() {
        let items = SlashPopup.filter(
            query: "/co",
            recentUsageCounts: ["/copy": 4, "/cost": 2]
        )
        let names = items.map(\.kind.displayName)
        #expect(Array(names.prefix(2)) == ["/copy", "/cost"])
    }

    // MARK: - Skill: 前缀过滤 (AC2)

    @Test("AC2: /sc 匹配 /screenshot-analyze skill")
    func skillPrefixFilter() {
        let items = SlashPopup.filter(query: "/sc", skills: sampleSkills)
        let names = items.map(\.kind.displayName)
        #expect(names.contains("/screenshot-analyze"))
    }

    @Test("AC2: /d 匹配 /data-extract skill")
    func skillPrefixFilterDataExtract() {
        let items = SlashPopup.filter(query: "/d", skills: sampleSkills)
        let names = items.map(\.kind.displayName)
        #expect(names.contains("/data-extract"))
    }

    // MARK: - Skill: 别名匹配 (AC4)

    @Test("AC4: /an 通过别名匹配 screenshot-analyze")
    func skillAliasMatch() {
        let items = SlashPopup.filter(query: "/an", skills: sampleSkills)
        let names = items.map(\.kind.displayName)
        #expect(names.contains("/screenshot-analyze"))
    }

    @Test("AC4: /sa 通过别名匹配 screenshot-analyze")
    func skillAliasMatchSa() {
        let items = SlashPopup.filter(query: "/sa", skills: sampleSkills)
        let names = items.map(\.kind.displayName)
        #expect(names.contains("/screenshot-analyze"))
    }

    @Test("AC4: 多个别名匹配只出现一次")
    func skillNoDuplicate() {
        // /s 匹配 screen alias + screenshot-analyze name → 只出现一次
        let items = SlashPopup.filter(query: "/s", skills: sampleSkills)
        let skillCount = items.filter {
            if case .skill(let info) = $0.kind { return info.name == "screenshot-analyze" }
            return false
        }.count
        #expect(skillCount == 1, "screenshot-analyze should appear exactly once")
    }

    // MARK: - Skill: 渲染样式 (AC3)

    @Test("AC3: skill 渲染包含 [skill] 标签")
    func skillRenderWithTag() {
        let items = SlashPopup.filter(query: "/sc", skills: sampleSkills)
        let output = SlashPopup.render(items: items, selectedIndex: -1, theme: nonTTYTheme)
        #expect(output.contains("[skill]"), "Should contain [skill] tag")
    }

    @Test("AC3: skill 描述折行截断含省略号")
    func skillDescriptionTruncation() {
        // 创建一个长描述 skill，确保描述超出 2 行宽度
        let longDesc = String(repeating: "测试描述内容", count: 20)  // 120 CJK chars → 240 display cols
        let longDescSkill = SkillInfo(name: "test-skill", description: longDesc, aliases: [])
        let items = SlashPopup.filter(query: "/te", skills: [longDescSkill])
        let output = SlashPopup.render(items: items, selectedIndex: -1, theme: nonTTYTheme, termWidth: 60)
        #expect(output.contains("..."), "Long description should be truncated with ...")
    }

    // MARK: - Skill: agent 忙碌时过滤 (AC7)

    @Test("AC7: agent 忙碌时 skill 不可用")
    func agentBusyHidesSkills() {
        let ctx = SlashCommandContext(isAgentBusy: true, isSideSession: false)
        let items = SlashPopup.filter(query: "/", context: ctx, skills: sampleSkills)
        let skillItems = items.filter {
            if case .skill = $0.kind { return true }
            return false
        }
        #expect(skillItems.isEmpty, "No skills should appear when agent is busy")
    }

    // MARK: - Skill: 空列表无影响 (AC6)

    @Test("AC6: 无 skill 时行为不变")
    func emptySkillListNoChange() {
        let items = SlashPopup.filter(query: "/")
        let itemsWithEmptySkills = SlashPopup.filter(query: "/", skills: [])
        #expect(items.count == itemsWithEmptySkills.count)
    }

    // MARK: - Skill: 选中并执行 (AC5)

    @Test("AC5: skill 的 acceptsArgs 为 true")
    func skillAcceptsArgs() {
        let kind = SlashPopupItemKind.skill(SkillInfo(name: "test", description: "", aliases: []))
        #expect(kind.acceptsArgs == true)
    }

    @Test("AC5: skill displayName 格式正确")
    func skillDisplayName() {
        let kind = SlashPopupItemKind.skill(SkillInfo(name: "screenshot-analyze", description: "", aliases: []))
        #expect(kind.displayName == "/screenshot-analyze")
    }

    // MARK: - Skill: 匹配高亮 (AC8)

    @Test("AC8: TTY 模式 skill 名称匹配高亮包含 ANSI 码")
    func skillTTYHighlight() {
        let items = SlashPopup.filter(query: "/sc", skills: sampleSkills)
        let output = SlashPopup.render(items: items, selectedIndex: -1, theme: ttyTheme)
        #expect(output.contains("\u{1B}[1;36m"), "Should contain ANSI highlight for matched part")
    }
}
