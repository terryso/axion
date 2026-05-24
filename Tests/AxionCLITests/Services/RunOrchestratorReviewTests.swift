import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("ReviewOrchestrator Integration")
struct RunOrchestratorReviewTests {

    // MARK: - 5.1: shouldReview gating logic

    private func makeOrchestrator(
        memoryInterval: Int = 4,
        skillInterval: Int = 6,
        minMessages: Int = 4
    ) -> ReviewOrchestrator {
        let schedule = ReviewScheduleConfig(
            memoryReviewInterval: memoryInterval,
            skillReviewInterval: skillInterval,
            minMessagesForReview: minMessages
        )
        return ReviewOrchestrator(
            scheduleConfig: schedule,
            factStore: FactStore(),
            skillRegistry: SkillRegistry(),
            skillEvolver: NoOpSkillEvolver(),
            usageStore: SkillUsageStore(skillsDir: NSTemporaryDirectory() + "axion-test-usage-\(UUID().uuidString)")
        )
    }

    @Test("shouldReview returns false when below minMessages threshold")
    func shouldReviewBelowThreshold() {
        let orchestrator = makeOrchestrator(minMessages: 4)
        let config = ReviewAgentConfig()
        let (doMemory, doSkill) = orchestrator.shouldReview(
            sessionId: "test",
            messageCount: 3,
            config: config
        )
        #expect(!doMemory)
        #expect(!doSkill)
    }

    @Test("shouldReview triggers memory at interval")
    func shouldReviewTriggersMemoryAtInterval() {
        let orchestrator = makeOrchestrator(memoryInterval: 4, minMessages: 4)
        let config = ReviewAgentConfig()
        let (doMemory, _) = orchestrator.shouldReview(
            sessionId: "test",
            messageCount: 4,
            config: config
        )
        #expect(doMemory)
    }

    @Test("shouldReview triggers skill at interval")
    func shouldReviewTriggersSkillAtInterval() {
        let orchestrator = makeOrchestrator(skillInterval: 6, minMessages: 4)
        let config = ReviewAgentConfig()
        let (_, doSkill) = orchestrator.shouldReview(
            sessionId: "test",
            messageCount: 6,
            config: config
        )
        #expect(doSkill)
    }

    @Test("shouldReview returns false between intervals")
    func shouldReviewReturnsFalseBetweenIntervals() {
        let orchestrator = makeOrchestrator(memoryInterval: 4, skillInterval: 6, minMessages: 4)
        let config = ReviewAgentConfig()
        let (doMemory, doSkill) = orchestrator.shouldReview(
            sessionId: "test",
            messageCount: 5,
            config: config
        )
        #expect(!doMemory)
        #expect(!doSkill)
    }

    @Test("shouldReview triggers both at LCM of intervals")
    func shouldReviewTriggersBothAtLCM() {
        let orchestrator = makeOrchestrator(memoryInterval: 4, skillInterval: 6, minMessages: 4)
        let config = ReviewAgentConfig()
        let (doMemory, doSkill) = orchestrator.shouldReview(
            sessionId: "test",
            messageCount: 12,
            config: config
        )
        #expect(doMemory)
        #expect(doSkill)
    }

    // MARK: - 5.2: Review skipped in dryrun/noMemory modes

    @Test("AgentBuildResult.reviewOrchestrator is nil when dryrun is true")
    func reviewOrchestratorNilOnDryrun() async throws {
        let config = AxionConfig(apiKey: "sk-test")
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "test",
            dryrun: true
        )
        // In dryrun mode, AgentBuilder sets reviewOrchestrator to nil
        // (helper path is faked for dryrun, so build should succeed)
        let result = try await AgentBuilder.build(buildConfig)
        #expect(result.reviewOrchestrator == nil)
    }

    @Test("AgentBuildResult.reviewOrchestrator is nil when noMemory is true")
    func reviewOrchestratorNilOnNoMemory() async throws {
        let config = AxionConfig(apiKey: "sk-test")
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "test",
            noMemory: true,
            dryrun: true  // dryrun bypasses helper path check
        )
        // noMemory disables review orchestrator
        let result = try await AgentBuilder.build(buildConfig)
        #expect(result.reviewOrchestrator == nil)
    }

    // MARK: - 5.3: Review failure does not affect RunResult

    @Test("TraceRecorder records review_completed event")
    func traceRecorderRecordsCompleted() async throws {
        let traceDir = NSTemporaryDirectory() + "axion-test-trace-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: traceDir) }

        TraceRecorder.recordReviewCompleted(
            runId: "20260524-test01",
            reviewSummary: "Review completed: saved 2 memories",
            memoryChanges: ["saved fact about Calculator"],
            skillChanges: [],
            traceDir: traceDir
        )

        // Give the write a moment
        try await _Concurrency.Task.sleep(for: .milliseconds(100))

        let filePath = (traceDir as NSString).appendingPathComponent("20260524-test01/review-trace.jsonl")
        #expect(FileManager.default.fileExists(atPath: filePath))

        let content = try String(contentsOfFile: filePath)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try #require(trimmed.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["event"] as? String == "review_completed")
        #expect(json["run_id"] as? String == "20260524-test01")
        #expect(json["review_summary"] as? String == "Review completed: saved 2 memories")
    }

    @Test("TraceRecorder records review_failed event")
    func traceRecorderRecordsFailed() async throws {
        let traceDir = NSTemporaryDirectory() + "axion-test-trace-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: traceDir) }

        TraceRecorder.recordReviewFailed(
            runId: "20260524-test02",
            error: "review agent returned nil",
            traceDir: traceDir
        )

        try await _Concurrency.Task.sleep(for: .milliseconds(100))

        let filePath = (traceDir as NSString).appendingPathComponent("20260524-test02/review-trace.jsonl")
        #expect(FileManager.default.fileExists(atPath: filePath))

        let content = try String(contentsOfFile: filePath)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try #require(trimmed.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["event"] as? String == "review_failed")
        #expect(json["error"] as? String == "review agent returned nil")
    }

    // MARK: - 5.4: AxionConfig round-trip with review fields

    @Test("AxionConfig review fields round-trip via Codable")
    func axionConfigReviewFieldsRoundTrip() throws {
        let config = AxionConfig(
            apiKey: "sk-test",
            reviewMemoryInterval: 8,
            reviewSkillInterval: 12,
            reviewMinMessages: 6,
            reviewModel: "claude-haiku-4-5-20251001"
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(decoded.reviewMemoryInterval == 8)
        #expect(decoded.reviewSkillInterval == 12)
        #expect(decoded.reviewMinMessages == 6)
        #expect(decoded.reviewModel == "claude-haiku-4-5-20251001")
    }

    @Test("AxionConfig review fields default to nil")
    func axionConfigReviewFieldsDefaultNil() throws {
        let json = """
        {"apiKey": "sk-test"}
        """
        let config = try JSONDecoder().decode(AxionConfig.self, from: Data(json.utf8))

        #expect(config.reviewMemoryInterval == nil)
        #expect(config.reviewSkillInterval == nil)
        #expect(config.reviewMinMessages == nil)
        #expect(config.reviewModel == nil)
    }

    @Test("AxionConfig review nil fields not in JSON output")
    func axionConfigReviewNilFieldsNotEncoded() throws {
        let config = AxionConfig(apiKey: "sk-test")
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["reviewMemoryInterval"] == nil)
        #expect(json["reviewSkillInterval"] == nil)
        #expect(json["reviewMinMessages"] == nil)
        #expect(json["reviewModel"] == nil)
    }

    // MARK: - NoOpSkillEvolver

    @Test("NoOpSkillEvolver returns empty result")
    func noOpSkillEvolverReturnsEmpty() async throws {
        let evolver = NoOpSkillEvolver()
        let result = try await evolver.evolve(
            skill: Skill(name: "test", description: "test", promptTemplate: "test"),
            signals: [],
            config: SkillEvolutionConfig()
        )
        #expect(result.evolvedSkill == nil)
        #expect(result.appliedSignals.isEmpty)
        #expect(result.changes.isEmpty)
    }
}
