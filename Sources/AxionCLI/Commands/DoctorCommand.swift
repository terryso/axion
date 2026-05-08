import ArgumentParser

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "检查系统环境和配置状态"
    )

    func run() throws {
        throw CleanExit.message("Doctor command not yet implemented")
    }
}
