import Testing
@testable import AxionCLI

@Suite("SlashPopup windowing")
struct SlashPopupWindowTests {
    private var nonTTYTheme: ChatTheme {
        ChatTheme(profile: .unknown, isTTY: false)
    }

    @Test("P0: scrolled render window keeps absolute candidate numbering")
    func scrolledRenderWindowKeepsAbsoluteNumbering() {
        let items = (1...60).map { index in
            SlashPopupItem(
                kind: .skill(SkillInfo(name: "skill-\(index)", description: "Skill \(index)", aliases: [])),
                matchRange: nil
            )
        }

        let output = SlashPopup.render(
            items: items,
            selectedIndex: 24,
            theme: nonTTYTheme,
            termWidth: 80,
            maxItems: 20,
            startIndex: 5
        )
        let lines = output.split(separator: "\n").map(String.init)

        #expect(lines.count == 20)
        #expect(lines.first?.contains("6.") == true)
        #expect(lines.last?.contains("25.") == true)
        #expect(lines.contains { line in
            line.contains(SlashPopup.selectedMarker)
                && line.contains("25.")
                && line.contains("/skill-25")
        })
    }

    @Test("P1: empty query ranking includes skill alias recent usage")
    func emptyQueryRankingIncludesSkillAliasRecentUsage() {
        let skill = SkillInfo(name: "bmad-quick-dev", description: "Quick dev workflow", aliases: ["qd"])
        let items = SlashPopup.filter(
            query: "/",
            skills: [skill],
            recentUsageCounts: ["/qd": 10]
        )

        #expect(items.first?.kind.displayName == "/bmad-quick-dev")
    }
}
