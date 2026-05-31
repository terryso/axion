import Testing
import Foundation
@testable import AxionCLI

@Suite("TGCommandRegistry")
struct TGCommandRegistryTests {

    // MARK: - Registration

    @Test("Register and resolve a command")
    func registerAndResolve() async {
        let registry = TGCommandRegistry(commands: [
            TGCommandDef(name: "status", description: "查看状态", helpText: "status help", menuPriority: 1) { _ in "ok" }
        ])

        let resolved = registry.resolve("status")
        #expect(resolved != nil)
        #expect(resolved!.name == "status")

        let reply = await resolved!.handler(100)
        #expect(reply == "ok")
    }

    @Test("Resolve returns nil for unknown command")
    func resolveUnknownReturnsNil() {
        let registry = TGCommandRegistry(commands: [])
        #expect(registry.resolve("unknown") == nil)
    }

    @Test("Functional register adds command to new registry")
    func functionalRegister() async {
        let empty = TGCommandRegistry()
        let registry = empty.register(TGCommandDef(name: "help", description: "帮助", helpText: "help text", menuPriority: 1) { _ in "help reply" })

        let resolved = registry.resolve("help")
        #expect(resolved != nil)
        let reply = await resolved!.handler(100)
        #expect(reply == "help reply")

        // Original is unchanged
        #expect(empty.resolve("help") == nil)
    }

    // MARK: - Normalization

    @Test("Normalize strips leading slash")
    func normalizeStripSlash() {
        #expect(TGCommandRegistry.normalize("/status") == "status")
    }

    @Test("Normalize strips @botname suffix")
    func normalizeStripBotname() {
        #expect(TGCommandRegistry.normalize("/status@my_bot") == "status")
    }

    @Test("Normalize lowercases input")
    func normalizeLowercase() {
        #expect(TGCommandRegistry.normalize("/STATUS") == "status")
        #expect(TGCommandRegistry.normalize("/Queue") == "queue")
    }

    @Test("Normalize replaces hyphens with underscores")
    func normalizeHyphens() {
        #expect(TGCommandRegistry.normalize("/my-command") == "my_command")
    }

    @Test("Normalize handles combined transformations")
    func normalizeCombined() {
        #expect(TGCommandRegistry.normalize("/STATUS@my_bot") == "status")
        #expect(TGCommandRegistry.normalize("/My-Command@bot") == "my_command")
    }

    @Test("Normalize plain name without slash")
    func normalizePlainName() {
        #expect(TGCommandRegistry.normalize("status") == "status")
    }

    // MARK: - allCommands and menuCommands

    @Test("allCommands returns commands sorted by menuPriority")
    func allCommandsSorted() {
        let registry = TGCommandRegistry(commands: [
            TGCommandDef(name: "queue", description: "queue", helpText: "", menuPriority: 6) { _ in "" },
            TGCommandDef(name: "help", description: "help", helpText: "", menuPriority: 1) { _ in "" },
            TGCommandDef(name: "status", description: "status", helpText: "", menuPriority: 3) { _ in "" },
        ])

        let all = registry.allCommands()
        #expect(all.count == 3)
        #expect(all[0].name == "help")
        #expect(all[1].name == "status")
        #expect(all[2].name == "queue")
    }

    @Test("menuCommands trims to limit")
    func menuCommandsTrimsToLimit() {
        let commands = (1...10).map { i in
            TGCommandDef(name: "cmd\(i)", description: "cmd \(i)", helpText: "", menuPriority: i) { _ in "" }
        }
        let registry = TGCommandRegistry(commands: commands)

        let menu = registry.menuCommands(limit: 3)
        #expect(menu.count == 3)
        #expect(menu[0].name == "cmd1")
        #expect(menu[2].name == "cmd3")
    }

    @Test("menuCommands returns name and description tuples")
    func menuCommandsFormat() {
        let registry = TGCommandRegistry(commands: [
            TGCommandDef(name: "help", description: "入门指南", helpText: "", menuPriority: 1) { _ in "" },
            TGCommandDef(name: "status", description: "查看状态", helpText: "", menuPriority: 2) { _ in "" },
        ])

        let menu = registry.menuCommands()
        #expect(menu.count == 2)
        #expect(menu[0] == (name: "help", description: "入门指南"))
        #expect(menu[1] == (name: "status", description: "查看状态"))
    }

    @Test("Duplicate command name — last registration wins")
    func duplicateNameLastWins() async {
        let registry = TGCommandRegistry(commands: [
            TGCommandDef(name: "status", description: "old", helpText: "", menuPriority: 1) { _ in "old" },
            TGCommandDef(name: "status", description: "new", helpText: "", menuPriority: 2) { _ in "new" },
        ])

        let resolved = registry.resolve("status")
        #expect(resolved != nil)
        #expect(resolved!.description == "new")
        let reply = await resolved!.handler(100)
        #expect(reply == "new")

        // allCommands preserves insertion order (both entries)
        #expect(registry.allCommands().count == 2)
    }
}
