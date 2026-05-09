import ArgumentParser

@main
struct AxionCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "axion",
        abstract: "Axion — macOS 桌面自动化 CLI",
        version: AxionVersion.current,
        subcommands: [RunCommand.self, SetupCommand.self, DoctorCommand.self]
    )
}
