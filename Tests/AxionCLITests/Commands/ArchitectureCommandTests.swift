import ArgumentParser
import Testing

@testable import AxionCLI

@Suite("ArchitectureCommand")
struct ArchitectureCommandTests {
    @Test("AxionCLI registers arch command")
    func archCommandRegistered() {
        let names = AxionCLI.configuration.subcommands.map { $0.configuration.commandName }
        #expect(names.contains("arch"))
    }

    @Test("parses scan options")
    func parsesScanOptions() throws {
        let command = try ArchitectureCommand.parse([
            "chrome",
            "--all",
            "--system",
            "--packages-only",
            "--limit",
            "12",
        ])

        let options = command.scanOptions()
        #expect(options.filter == "chrome")
        #expect(options.includeAllArchitectures)
        #expect(options.includeSystemApps)
        #expect(options.scope == .packagesOnly)
        #expect(options.limit == 12)
    }

    @Test("rejects invalid option combinations")
    func rejectsInvalidOptionCombinations() {
        #expect(throws: (any Error).self) {
            _ = try ArchitectureCommand.parse(["--apps-only", "--packages-only"])
        }
        #expect(throws: (any Error).self) {
            _ = try ArchitectureCommand.parse(["--limit", "0"])
        }
    }
}
