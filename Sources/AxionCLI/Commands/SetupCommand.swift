import ArgumentParser

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "首次配置 Axion"
    )

    func run() throws {
        throw CleanExit.message("Setup command not yet implemented")
    }
}
