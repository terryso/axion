import ArgumentParser

@main
struct AxionCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "axion",
        abstract: "Axion — AI Agent for coding and desktop automation",
        version: AxionVersion.current,
        subcommands: [ChatCommand.self, RunCommand.self, SetupCommand.self, DoctorCommand.self, MemoryCommand.self, ServerCommand.self, McpCommand.self, RecordCommand.self, SkillCommand.self, DaemonCommand.self, GatewayCommand.self, CuratorCommand.self, SessionsCommand.self, ResumeCommand.self],
        defaultSubcommand: ChatCommand.self
    )
}
