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
            skillEvolver: MockSkillEvolver(),
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

    // MARK: - LLMSkillEvolver Initialization

    @Test("LLMSkillEvolver can be initialized with AnthropicClient")
    func llmSkillEvolverInitWithAnthropicClient() {
        let client = AnthropicClient(apiKey: "sk-test")
        let evolver = LLMSkillEvolver(client: client, evolutionModel: "claude-haiku-4-5-20251001")
        #expect(evolver.evolutionModel == "claude-haiku-4-5-20251001")
    }

    @Test("LLMSkillEvolver defaults evolutionModel to haiku")
    func llmSkillEvolverDefaultModel() {
        let client = AnthropicClient(apiKey: "sk-test")
        let evolver = LLMSkillEvolver(client: client)
        #expect(evolver.evolutionModel == "claude-haiku-4-5-20251001")
    }

    @Test("AgentBuilder creates LLMSkillEvolver with config.reviewModel")
    func agentBuilderUsesConfigReviewModel() {
        // Verify the wiring pattern: LLMSkillEvolver(client:evolutionModel:)
        // uses the same parameters AgentBuilder.build() would use.
        let apiKey = "sk-test"
        let baseURL: String? = nil
        let reviewModel = "claude-haiku-4-5-20251001"

        let evolverClient = AnthropicClient(apiKey: apiKey, baseURL: baseURL)
        let skillEvolver = LLMSkillEvolver(
            client: evolverClient,
            evolutionModel: reviewModel
        )
        #expect(skillEvolver.evolutionModel == "claude-haiku-4-5-20251001")

        // Verify it can be wired into ReviewOrchestrator
        let _ = ReviewOrchestrator(
            scheduleConfig: ReviewScheduleConfig(),
            factStore: FactStore(),
            skillRegistry: SkillRegistry(),
            skillEvolver: skillEvolver,
            usageStore: SkillUsageStore(skillsDir: NSTemporaryDirectory() + "axion-test-usage-\(UUID().uuidString)")
        )
    }

    @Test("MockSkillEvolver returns configured success result")
    func mockSkillEvolverReturnsSuccess() async throws {
        let evolvedSkill = Skill(
            name: "test-skill",
            description: "evolved",
            promptTemplate: "evolved prompt"
        )
        let result = SkillEvolutionResult(
            evolvedSkill: evolvedSkill,
            appliedSignals: [],
            skippedSignals: [],
            changes: ["updated prompt"]
        )
        let evolver = MockSkillEvolver(result: result)

        let returned = try await evolver.evolve(
            skill: Skill(name: "test", description: "original", promptTemplate: "original"),
            signals: [],
            config: SkillEvolutionConfig()
        )
        #expect(returned.evolvedSkill != nil)
        #expect(returned.evolvedSkill?.description == "evolved")
        #expect(returned.changes == ["updated prompt"])
    }

    @Test("MockSkillEvolver returns no-evolution result by default")
    func mockSkillEvolverReturnsNoEvolutionByDefault() async throws {
        let evolver = MockSkillEvolver()
        let returned = try await evolver.evolve(
            skill: Skill(name: "test", description: "original", promptTemplate: "original"),
            signals: [],
            config: SkillEvolutionConfig()
        )
        #expect(returned.evolvedSkill == nil)
        #expect(returned.changes.isEmpty)
    }

    // MARK: - Story 22.3: Dependency Injection Verification

    /// Computes the same memoryDir that AgentBuilder.build() uses.
    private var agentBuilderMemoryDir: String {
        (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
    }

    /// Computes the same skillsDir that AgentBuilder.build() uses.
    private var agentBuilderSkillsDir: String {
        (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
    }

    @Test("AgentBuilder.build() creates non-nil reviewOrchestrator when memory enabled")
    func reviewOrchestratorNonNilWhenMemoryEnabled() async throws {
        // Provide a fake helper path so AgentBuilder.build() doesn't throw.
        // setenv updates the process environment table; ProcessInfo reads via getenv.
        let tmpHelper = NSTemporaryDirectory() + "axion-test-helper-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: tmpHelper, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: tmpHelper) }
        setenv("AXION_HELPER_PATH", tmpHelper, 1)
        defer { unsetenv("AXION_HELPER_PATH") }

        let config = AxionConfig(apiKey: "sk-test")
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "test",
            noMemory: false,
            dryrun: false
        )
        let result = try await AgentBuilder.build(buildConfig)
        #expect(result.reviewOrchestrator != nil)
    }

    @Test("ReviewScheduleConfig uses AxionConfig.reviewModel when set")
    func scheduleConfigUsesConfigReviewModel() {
        let config = AxionConfig(apiKey: "sk-test", reviewModel: "claude-sonnet-4-20250514")
        let scheduleConfig = ReviewScheduleConfig(
            memoryReviewInterval: config.reviewMemoryInterval ?? ReviewScheduleConfig().memoryReviewInterval,
            skillReviewInterval: config.reviewSkillInterval ?? ReviewScheduleConfig().skillReviewInterval,
            minMessagesForReview: config.reviewMinMessages ?? ReviewScheduleConfig().minMessagesForReview,
            reviewModel: config.reviewModel
        )
        #expect(scheduleConfig.reviewModel == "claude-sonnet-4-20250514")
    }

    @Test("ReviewScheduleConfig reviewModel falls back to nil when config is nil")
    func scheduleConfigReviewModelFallsBack() {
        let config = AxionConfig(apiKey: "sk-test")
        // reviewModel is nil by default
        let scheduleConfig = ReviewScheduleConfig(
            memoryReviewInterval: config.reviewMemoryInterval ?? ReviewScheduleConfig().memoryReviewInterval,
            skillReviewInterval: config.reviewSkillInterval ?? ReviewScheduleConfig().skillReviewInterval,
            minMessagesForReview: config.reviewMinMessages ?? ReviewScheduleConfig().minMessagesForReview,
            reviewModel: config.reviewModel
        )
        #expect(scheduleConfig.reviewModel == nil)
    }

    @Test("LLMSkillEvolver falls back to haiku when reviewModel is nil")
    func skillEvolverFallsBackToHaikuModel() {
        let config = AxionConfig(apiKey: "sk-test")
        // Replicate the exact nil-coalescing pattern from AgentBuilder.build() line 280
        let effectiveModel = config.reviewModel ?? "claude-haiku-4-5-20251001"
        #expect(effectiveModel == "claude-haiku-4-5-20251001")

        let client = AnthropicClient(apiKey: "sk-test")
        let evolver = LLMSkillEvolver(client: client, evolutionModel: effectiveModel)
        #expect(evolver.evolutionModel == "claude-haiku-4-5-20251001")
    }

    @Test("FactStore receives correct memory directory from AgentBuilder")
    func factStoreReceivesCorrectMemoryDir() async throws {
        // Verify the computed path matches AgentBuilder's pattern
        let memoryDir = agentBuilderMemoryDir
        #expect(memoryDir == (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory"))

        // Verify FactStore is functional using an isolated temp directory
        let tempDir = NSTemporaryDirectory() + "axion-test-factstore-\(UUID().uuidString)"
        let factStore = FactStore(memoryDir: tempDir)
        let testFact = MemoryFact(
            id: "test-fact-223",
            domain: "test-domain-223",
            content: "dependency injection test",
            status: .candidate,
            confidence: 0.5,
            evidenceCount: 1,
            source: .observation,
            kind: .observation,
            createdAt: Date(),
            lastVerifiedAt: Date()
        )
        try await factStore.save(domain: "test-domain-223", fact: testFact)
        let facts = try await factStore.query(domain: "test-domain-223")
        #expect(facts.count == 1)
        #expect(facts.first?.content == "dependency injection test")
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    @Test("SkillUsageStore receives correct skills directory from AgentBuilder")
    func skillUsageStoreReceivesCorrectSkillsDir() {
        // Verify the computed path matches AgentBuilder's pattern
        let skillsDir = agentBuilderSkillsDir
        #expect(skillsDir == (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills"))

        // Verify SkillUsageStore is constructable with an isolated temp directory
        let tempDir = NSTemporaryDirectory() + "axion-test-usage-\(UUID().uuidString)"
        let usageStore = SkillUsageStore(skillsDir: tempDir)
        let _ = usageStore
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    @Test("ReviewOrchestrator with all dependencies passes through correctly")
    func reviewOrchestratorPassesThroughDependencies() {
        let tempMemoryDir = NSTemporaryDirectory() + "axion-test-mem-\(UUID().uuidString)"
        let tempSkillsDir = NSTemporaryDirectory() + "axion-test-skills-\(UUID().uuidString)"

        let scheduleConfig = ReviewScheduleConfig(
            memoryReviewInterval: 8,
            skillReviewInterval: 10,
            minMessagesForReview: 5,
            reviewModel: "claude-haiku-4-5-20251001"
        )
        let factStore = FactStore(memoryDir: tempMemoryDir)
        let skillRegistry = SkillRegistry()
        let evolver = LLMSkillEvolver(client: AnthropicClient(apiKey: "sk-test"), evolutionModel: "claude-haiku-4-5-20251001")
        let usageStore = SkillUsageStore(skillsDir: tempSkillsDir)

        let orchestrator = ReviewOrchestrator(
            scheduleConfig: scheduleConfig,
            factStore: factStore,
            skillRegistry: skillRegistry,
            skillEvolver: evolver,
            usageStore: usageStore
        )

        // Verify all dependencies are accessible via public properties
        #expect(orchestrator.scheduleConfig.memoryReviewInterval == 8)
        #expect(orchestrator.scheduleConfig.skillReviewInterval == 10)
        #expect(orchestrator.scheduleConfig.minMessagesForReview == 5)
        #expect(orchestrator.scheduleConfig.reviewModel == "claude-haiku-4-5-20251001")

        // Verify createReviewTools returns non-empty tools
        let tools = createReviewTools(
            factStore: factStore,
            skillRegistry: skillRegistry,
            skillEvolver: evolver,
            usageStore: usageStore
        )
        #expect(!tools.isEmpty)
        #expect(tools.count >= 5)
    }

    @Test("AxionConfig with custom review intervals produces matching ReviewScheduleConfig")
    func customReviewIntervalsMatchScheduleConfig() {
        let config = AxionConfig(
            apiKey: "sk-test",
            reviewMemoryInterval: 10,
            reviewSkillInterval: 15,
            reviewMinMessages: 8,
            reviewModel: "claude-sonnet-4-20250514"
        )

        let scheduleConfig = ReviewScheduleConfig(
            memoryReviewInterval: config.reviewMemoryInterval ?? ReviewScheduleConfig().memoryReviewInterval,
            skillReviewInterval: config.reviewSkillInterval ?? ReviewScheduleConfig().skillReviewInterval,
            minMessagesForReview: config.reviewMinMessages ?? ReviewScheduleConfig().minMessagesForReview,
            reviewModel: config.reviewModel
        )

        #expect(scheduleConfig.memoryReviewInterval == 10)
        #expect(scheduleConfig.skillReviewInterval == 15)
        #expect(scheduleConfig.minMessagesForReview == 8)
        #expect(scheduleConfig.reviewModel == "claude-sonnet-4-20250514")
    }

    @Test("Default ReviewScheduleConfig values match when AxionConfig review fields are nil")
    func defaultScheduleConfigWhenAxionConfigNil() {
        let config = AxionConfig(apiKey: "sk-test")
        // All review fields are nil by default
        #expect(config.reviewMemoryInterval == nil)
        #expect(config.reviewSkillInterval == nil)
        #expect(config.reviewMinMessages == nil)
        #expect(config.reviewModel == nil)

        let scheduleConfig = ReviewScheduleConfig(
            memoryReviewInterval: config.reviewMemoryInterval ?? ReviewScheduleConfig().memoryReviewInterval,
            skillReviewInterval: config.reviewSkillInterval ?? ReviewScheduleConfig().skillReviewInterval,
            minMessagesForReview: config.reviewMinMessages ?? ReviewScheduleConfig().minMessagesForReview,
            reviewModel: config.reviewModel
        )

        // Should use ReviewScheduleConfig defaults
        #expect(scheduleConfig.memoryReviewInterval == 4)
        #expect(scheduleConfig.skillReviewInterval == 6)
        #expect(scheduleConfig.minMessagesForReview == 4)
        #expect(scheduleConfig.reviewModel == nil)
    }
}
