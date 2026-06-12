import Testing

@testable import AxionCLI

@Suite("SlashCommand /apps")
struct SlashCommandAppsTests {
    @Test("parse /apps")
    func parseApps() {
        #expect(SlashCommand.parse("/apps") == .apps)
        #expect(SlashCommand.parse("/Apps") == .apps)
    }

    @Test("/apps accepts args and is unavailable while agent busy")
    func metadata() {
        #expect(SlashCommand.apps.acceptsArgs == true)
        #expect(SlashCommand.apps.availableDuringTask == false)
        #expect(SlashCommand.apps.helpText.contains("App"))
    }

    @Test("/apps argument parsing uses generic slash argument parser")
    func parseArgument() {
        #expect(SlashCommand.parseArgument("/apps slack") == "slack")
        #expect(SlashCommand.parseArgument("/apps --all") == "--all")
    }

    @Test("slash popup includes /apps")
    func popupIncludesApps() {
        let items = SlashPopup.filter(query: "/app")
        #expect(items.count == 1)
        #expect(items.first?.kind.displayName == "/apps")
    }
}
