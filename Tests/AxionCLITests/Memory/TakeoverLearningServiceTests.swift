import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

// Story 15.1: TakeoverLearningService tests (AC1, AC2, AC3, AC5, AC7, AC10)

@Suite("TakeoverLearningService")
struct TakeoverLearningServiceTests {

    private func makeService(dir: URL) -> TakeoverLearningService {
        TakeoverLearningService(
            factStore: AxionFactStore(memoryDir: dir),
            lifecycleService: OpenAgentSDK.MemoryLifecycleService()
        )
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axion-test-takeover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - AC2: Success outcome → affordance, confidence 0.72, cause "takeover_demonstration"

    @Test("success outcome creates affordance fact")
    func successOutcomeCreatesAffordance() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let store = AxionFactStore(memoryDir: dir)
        let service = makeService(dir: dir)

        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "文件选择对话框无法通过 AX 定位",
            summary: "使用 Cmd+Shift+G 直接输入路径",
            outcome: .success
        )

        let facts = try await store.query(domain: "com.apple.finder")
        #expect(facts.count == 1)
        let fact = facts[0]
        #expect(fact.kind == .affordance)
        #expect(fact.confidence == 0.72)
        #expect(fact.cause == "takeover_demonstration")
        #expect(fact.scope == "user takeover")
        #expect(fact.status == .candidate)
        #expect(fact.domain == "com.apple.finder")
    }

    // MARK: - AC3: Failed outcome → avoid, confidence 0.66, cause "takeover_unresolved"

    @Test("failed outcome creates avoid fact")
    func failedOutcomeCreatesAvoid() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let store = AxionFactStore(memoryDir: dir)
        let service = makeService(dir: dir)

        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "文件选择对话框无法通过 AX 定位",
            summary: "尝试点击取消按钮",
            outcome: .failed
        )

        let facts = try await store.query(domain: "com.apple.finder")
        #expect(facts.count == 1)
        let fact = facts[0]
        #expect(fact.kind == .avoid)
        #expect(fact.confidence == 0.66)
        #expect(fact.cause == "takeover_unresolved")
    }

    // MARK: - AC2: Description format

    @Test("success description format")
    func successDescriptionFormat() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let store = AxionFactStore(memoryDir: dir)
        let service = makeService(dir: dir)

        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "AX 元素不可见",
            summary: "使用快捷键 Cmd+N",
            outcome: .success
        )

        let facts = try await store.query(domain: "com.apple.finder")
        #expect(facts.count == 1)
        #expect(facts[0].description == "当被 AX 元素不可见 阻塞时，用户手动 使用快捷键 Cmd+N 成功")
    }

    @Test("failed description format")
    func failedDescriptionFormat() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let store = AxionFactStore(memoryDir: dir)
        let service = makeService(dir: dir)

        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "弹窗阻塞",
            summary: "点击确定按钮",
            outcome: .failed
        )

        let facts = try await store.query(domain: "com.apple.finder")
        #expect(facts.count == 1)
        #expect(facts[0].description == "当被 弹窗阻塞 阻塞时，点击确定按钮 未解决问题")
    }

    // MARK: - Evidence array construction (filters nil/empty)

    @Test("evidence array filters nil and empty values")
    func evidenceArrayFiltersNil() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let store = AxionFactStore(memoryDir: dir)
        let service = makeService(dir: dir)

        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "AX 问题",
            summary: "手动操作",
            outcome: .success,
            feedback: "有用的反馈"
        )

        let facts = try await store.query(domain: "com.apple.finder")
        #expect(facts.count == 1)
        let evidence = facts[0].evidence
        // Should NOT contain "task:" since task is nil
        #expect(!evidence.contains(where: { $0.hasPrefix("task:") }))
        // Should contain issue, outcome, takeover, and feedback
        #expect(evidence.contains(where: { $0.hasPrefix("issue:") }))
        #expect(evidence.contains(where: { $0.hasPrefix("outcome:") }))
        #expect(evidence.contains(where: { $0.hasPrefix("takeover:") }))
        #expect(evidence.contains(where: { $0.hasPrefix("feedback:") }))
    }

    @Test("evidence array includes all non-nil values")
    func evidenceArrayIncludesAll() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let store = AxionFactStore(memoryDir: dir)
        let service = makeService(dir: dir)

        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            appName: "Finder",
            task: "打开文件",
            issue: "对话框阻塞",
            summary: "Cmd+Shift+G",
            outcome: .success,
            reasonType: "ax_failure",
            feedback: "好用"
        )

        let facts = try await store.query(domain: "com.apple.finder")
        #expect(facts.count == 1)
        let evidence = facts[0].evidence
        #expect(evidence.contains("task: 打开文件"))
        #expect(evidence.contains("issue: 对话框阻塞"))
        #expect(evidence.contains("reason_type: ax_failure"))
        #expect(evidence.contains("outcome: success"))
        #expect(evidence.contains("takeover: Cmd+Shift+G"))
        #expect(evidence.contains("feedback: 好用"))
    }

    // MARK: - Merge: evidenceCount accumulation on duplicate

    @Test("duplicate takeover accumulates evidenceCount")
    func duplicateTakeoverAccumulatesEvidence() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let store = AxionFactStore(memoryDir: dir)
        let service = makeService(dir: dir)

        // Record same takeover twice (same issue + summary = same description = same factId)
        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "对话框阻塞",
            summary: "Cmd+Shift+G",
            outcome: .success
        )
        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "对话框阻塞",
            summary: "Cmd+Shift+G",
            outcome: .success
        )

        let facts = try await store.query(domain: "com.apple.finder")
        #expect(facts.count == 1, "Should merge into single fact")
        #expect(facts[0].evidenceCount >= 2, "evidenceCount should accumulate on merge")
    }

    // MARK: - AC7: Write failure does not throw

    @Test("write failure does not throw exception")
    func writeFailureDoesNotThrow() async throws {
        // Use an invalid directory path to force failure
        let service = TakeoverLearningService(
            factStore: AxionFactStore(memoryDir: "/dev/null/impossible/path"),
            lifecycleService: OpenAgentSDK.MemoryLifecycleService(),
            logWarning: { _ in }
        )

        // Should not crash or throw
        await service.recordTakeoverLearning(
            bundleId: "com.apple.finder",
            issue: "test",
            summary: "test",
            outcome: .success
        )
    }

    // MARK: - AC10: Codable round-trip for TakeoverOutcome

    @Test("TakeoverOutcome Codable round-trip")
    func takeoverOutcomeRoundTrip() throws {
        for outcome in [TakeoverOutcome.success, .failed, .cancelled] {
            let data = try JSONEncoder().encode(outcome)
            let decoded = try JSONDecoder().decode(TakeoverOutcome.self, from: data)
            #expect(decoded == outcome)
        }
    }

    @Test("TakeoverOutcome raw values")
    func takeoverOutcomeRawValues() {
        #expect(TakeoverOutcome.success.rawValue == "success")
        #expect(TakeoverOutcome.failed.rawValue == "failed")
        #expect(TakeoverOutcome.cancelled.rawValue == "cancelled")
    }

    // MARK: - cancelled outcome behaves like failed (avoid kind)

    @Test("cancelled outcome creates avoid fact")
    func cancelledOutcomeCreatesAvoid() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let store = AxionFactStore(memoryDir: dir)
        let service = makeService(dir: dir)

        await service.recordTakeoverLearning(
            bundleId: "com.apple.safari",
            issue: "弹窗阻塞",
            summary: "关闭窗口",
            outcome: .cancelled
        )

        let facts = try await store.query(domain: "com.apple.safari")
        #expect(facts.count == 1)
        let fact = facts[0]
        #expect(fact.kind == .avoid)
        #expect(fact.confidence == 0.66)
        #expect(fact.cause == "takeover_unresolved")
    }
}
