import ArgumentParser

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "执行桌面自动化任务"
    )

    @Argument(help: "任务描述")
    var task: String

    @Flag(name: .long, help: "实际执行模式（默认为干跑模式）")
    var live: Bool = false

    @Option(name: .long, help: "单次运行最大步骤数")
    var maxSteps: Int?

    @Option(name: .long, help: "最大批次")
    var maxBatches: Int?

    @Flag(name: .long, help: "允许前台操作")
    var allowForeground: Bool = false

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    @Flag(name: .long, help: "JSON 格式输出")
    var json: Bool = false

    func run() throws {
        throw CleanExit.message("Run command not yet implemented (Epic 3)")
    }
}
