import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "执行桌面自动化任务"
    )

    @Argument(help: "任务描述")
    var task: String

    @Flag(name: .long, help: "干跑模式（仅生成计划不实际执行）")
    var dryrun: Bool = false

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

    mutating func run() async throws {
        let manager = HelperProcessManager()

        do {
            try await withTaskCancellationHandler {
                try await manager.start()

                // 后续 Story 在此处添加 RunEngine 编排
                throw CleanExit.message("Run command partially implemented (Story 3.1)")
            } onCancel: {
                Task { await manager.stop() }
            }
        } catch {
            await manager.stop()
            throw error
        }
    }
}
