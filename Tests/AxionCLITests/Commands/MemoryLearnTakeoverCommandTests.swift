import Foundation
import Testing

@testable import AxionCLI

// Story 15.1 AC5: MemoryLearnTakeoverCommand tests

@Suite("MemoryLearnTakeoverCommand")
struct MemoryLearnTakeoverCommandTests {

    private func makeTempDir() throws -> String {
        let dir = "/tmp/axion-test-learn-takeover-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - P0: Type existence

    @Test("MemoryLearnTakeoverCommand type exists")
    func typeExists() {
        let _ = MemoryLearnTakeoverCommand.self
    }

    // MARK: - P0 AC5: CLI with required args creates affordance

    @Test("default outcome creates affordance fact")
    func defaultOutcomeCreatesAffordance() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let store = MemoryFactStore(memoryDir: dir)
        let service = TakeoverLearningService(
            factStore: store,
            lifecycleService: MemoryLifecycleService()
        )

        // Simulate what the CLI command does
        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "文件选择对话框无法通过 AX 定位",
            summary: "使用 Cmd+Shift+G 直接输入路径"
        )

        let facts = try await store.query(domain: "com.apple.finder")
        #expect(facts.count == 1)
        #expect(facts[0].kind == .affordance)
        #expect(facts[0].confidence == 0.72)
        #expect(facts[0].cause == "takeover_demonstration")
    }

    // MARK: - P0 AC5: --outcome failed creates avoid

    @Test("outcome failed creates avoid fact")
    func outcomeFailedCreatesAvoid() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let store = MemoryFactStore(memoryDir: dir)
        let service = TakeoverLearningService(
            factStore: store,
            lifecycleService: MemoryLifecycleService()
        )

        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "弹窗阻塞",
            summary: "点击确定",
            outcome: .failed
        )

        let facts = try await store.query(domain: "com.apple.finder")
        #expect(facts.count == 1)
        #expect(facts[0].kind == .avoid)
        #expect(facts[0].confidence == 0.66)
        #expect(facts[0].cause == "takeover_unresolved")
    }

    // MARK: - P0: Optional parameters work

    @Test("optional parameters are accepted")
    func optionalParameters() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let store = MemoryFactStore(memoryDir: dir)
        let service = TakeoverLearningService(
            factStore: store,
            lifecycleService: MemoryLifecycleService()
        )

        await service.recordTakeoverLearning(
            bundleId: "com.apple.safari",
            appName: "Safari",
            task: "打开网页",
            issue: "输入框无法定位",
            summary: "使用 Tab 键导航",
            outcome: .success,
            reasonType: "ax_element_hidden",
            feedback: "有效"
        )

        let facts = try await store.query(domain: "com.apple.safari")
        #expect(facts.count == 1)
        #expect(facts[0].evidence.count >= 5, "Should contain task, issue, reason_type, outcome, takeover, feedback")
    }

    // MARK: - P0: Command registered as subcommand

    @Test("learn-takeover is registered as subcommand of memory")
    func registeredAsSubcommand() {
        let config = MemoryCommand.configuration
        let hasSubcommand = config.subcommands.contains(where: { $0 == MemoryLearnTakeoverCommand.self })
        #expect(hasSubcommand, "MemoryLearnTakeoverCommand should be a subcommand of MemoryCommand")
    }
}
