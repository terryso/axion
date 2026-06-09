import ArgumentParser
import OpenAgentSDK

/// `axion memory learn-takeover` — manually record a takeover experience as Memory.
///
/// Creates an `AppMemoryFact` directly without waiting for a run to trigger it.
/// Useful for seeding the Memory store with known workarounds.
struct MemoryLearnTakeoverCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "learn-takeover",
        abstract: "手动记录 Takeover 经验到 Memory"
    )

    @Option(name: .long, help: "目标 App 的 Bundle ID（必需）")
    var bundleId: String

    @Option(name: .long, help: "阻塞原因描述（必需）")
    var issue: String

    @Option(name: .long, help: "用户手动操作描述（必需）")
    var summary: String

    @Option(name: .long, help: "App 名称（可选）")
    var appName: String?

    @Option(name: .long, help: "任务描述（可选）")
    var task: String?

    @Option(name: .long, help: "结果类型：success 或 failed（默认 success）")
    var outcome: TakeoverOutcome = .success

    func run() async throws {
        let factStore = AxionFactStore(memoryDir: ConfigManager.memoryDirectory)
        let lifecycleService = OpenAgentSDK.MemoryLifecycleService()
        let service = TakeoverLearningService(
            factStore: factStore,
            lifecycleService: lifecycleService
        )

        await service.recordTakeoverLearning(
            bundleId: bundleId,
            appName: appName,
            task: task,
            issue: issue,
            summary: summary,
            outcome: outcome
        )

        print("[axion] 已保存 takeover 学习到 \(bundleId)")
    }

}
