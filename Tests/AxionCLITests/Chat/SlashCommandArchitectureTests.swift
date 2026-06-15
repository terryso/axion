import Testing

@testable import AxionCLI

@Suite("SlashCommand /arch")
struct SlashCommandArchitectureTests {
    @Test("parse /arch")
    func parseArch() {
        #expect(SlashCommand.parse("/arch") == .arch)
        #expect(SlashCommand.parse("/Arch") == .arch)
    }

    @Test("/arch accepts args and is unavailable while agent busy")
    func metadata() {
        #expect(SlashCommand.arch.acceptsArgs == true)
        #expect(SlashCommand.arch.availableDuringTask == false)
        #expect(SlashCommand.arch.helpText.contains("Intel-only"))
    }

    @Test("/arch argument parsing uses generic slash argument parser")
    func parseArgument() {
        #expect(SlashCommand.parseArgument("/arch chrome --all") == "chrome --all")
        #expect(SlashCommand.parseArgument("/arch --packages-only") == "--packages-only")
    }

    @Test("slash popup includes /arch")
    func popupIncludesArch() {
        let items = SlashPopup.filter(query: "/ar")
        #expect(items.map(\.kind.displayName).contains("/arch"))
        #expect(items.map(\.kind.displayName).contains("/archive"))
    }
}
