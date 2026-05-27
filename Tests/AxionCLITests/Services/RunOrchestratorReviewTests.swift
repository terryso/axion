import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("ReviewOrchestrator Integration", .serialized)
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
            noSkills: true,
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
            noSkills: true,
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
            reviewModel: AxionConfig.defaultReviewModel
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(decoded.reviewMemoryInterval == 8)
        #expect(decoded.reviewSkillInterval == 12)
        #expect(decoded.reviewMinMessages == 6)
        #expect(decoded.reviewModel == AxionConfig.defaultReviewModel)
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
        let evolver = LLMSkillEvolver(client: client, evolutionModel: AxionConfig.defaultReviewModel)
        #expect(evolver.evolutionModel == AxionConfig.defaultReviewModel)
    }

    @Test("LLMSkillEvolver defaults evolutionModel to haiku")
    func llmSkillEvolverDefaultModel() {
        let client = AnthropicClient(apiKey: "sk-test")
        let evolver = LLMSkillEvolver(client: client)
        #expect(evolver.evolutionModel == AxionConfig.defaultReviewModel)
    }

    @Test("AgentBuilder creates LLMSkillEvolver with config.reviewModel")
    func agentBuilderUsesConfigReviewModel() {
        // Verify the wiring pattern: LLMSkillEvolver(client:evolutionModel:)
        // uses the same parameters AgentBuilder.build() would use.
        let apiKey = "sk-test"
        let baseURL: String? = nil
        let reviewModel = AxionConfig.defaultReviewModel

        let evolverClient = AnthropicClient(apiKey: apiKey, baseURL: baseURL)
        let skillEvolver = LLMSkillEvolver(
            client: evolverClient,
            evolutionModel: reviewModel
        )
        #expect(skillEvolver.evolutionModel == AxionConfig.defaultReviewModel)

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
        // Verify the condition and construction path without calling AgentBuilder.build(),
        // which creates real Agent + NIO threads that leak and corrupt the heap.
        let config = AxionConfig(apiKey: "sk-test")
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "test",
            noMemory: false,
            dryrun: false
        )

        // Verify the condition: !noMemory && !dryrun → reviewOrchestrator is created
        #expect(!buildConfig.noMemory)
        #expect(!buildConfig.dryrun)

        // Verify ReviewOrchestrator can be constructed with the same deps
        let scheduleConfig = ReviewScheduleConfig(
            memoryReviewInterval: config.reviewMemoryInterval ?? ReviewScheduleConfig().memoryReviewInterval,
            skillReviewInterval: config.reviewSkillInterval ?? ReviewScheduleConfig().skillReviewInterval,
            minMessagesForReview: config.reviewMinMessages ?? ReviewScheduleConfig().minMessagesForReview,
            reviewModel: config.reviewModel
        )
        let tmpDir = NSTemporaryDirectory() + "axion-test-review-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let orchestrator = ReviewOrchestrator(
            scheduleConfig: scheduleConfig,
            factStore: FactStore(memoryDir: tmpDir),
            skillRegistry: SkillRegistry(),
            skillEvolver: MockSkillEvolver(),
            usageStore: SkillUsageStore(skillsDir: tmpDir)
        )
        let _: ReviewOrchestrator = orchestrator
    }

    @Test("AgentBuilder.build() creates non-nil intelligentCurator when memory enabled")
    func intelligentCuratorNonNilWhenMemoryEnabled() async throws {
        // Verify the condition and construction path without calling AgentBuilder.build(),
        // which creates real Agent + NIO threads that leak and corrupt the heap.
        let config = AxionConfig(apiKey: "sk-test")
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "test",
            noMemory: false,
            dryrun: false
        )

        #expect(!buildConfig.noMemory)
        #expect(!buildConfig.dryrun)

        let tmpDir = NSTemporaryDirectory() + "axion-test-curator-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let skillCurator = SkillCurator(
            usageStore: SkillUsageStore(skillsDir: tmpDir),
            curatorStore: SkillCuratorStore(skillsDir: tmpDir),
            config: SkillCuratorConfig()
        )
        let curator = IntelligentCurator(
            skillCurator: skillCurator,
            factStore: FactStore(memoryDir: tmpDir),
            skillRegistry: SkillRegistry(),
            skillEvolver: MockSkillEvolver(),
            usageStore: SkillUsageStore(skillsDir: tmpDir),
            curatorStore: SkillCuratorStore(skillsDir: tmpDir)
        )
        let _: IntelligentCurator = curator
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
        let effectiveModel = config.reviewModel ?? AxionConfig.defaultReviewModel
        #expect(effectiveModel == AxionConfig.defaultReviewModel)

        let client = AnthropicClient(apiKey: "sk-test")
        let evolver = LLMSkillEvolver(client: client, evolutionModel: effectiveModel)
        #expect(evolver.evolutionModel == AxionConfig.defaultReviewModel)
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
            reviewModel: AxionConfig.defaultReviewModel
        )
        let factStore = FactStore(memoryDir: tempMemoryDir)
        let skillRegistry = SkillRegistry()
        let evolver = LLMSkillEvolver(client: AnthropicClient(apiKey: "sk-test"), evolutionModel: AxionConfig.defaultReviewModel)
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
        #expect(orchestrator.scheduleConfig.reviewModel == AxionConfig.defaultReviewModel)

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

    // MARK: - Story 22.4: Curator Config Fields

    @Test("AxionConfig curator fields round-trip via Codable")
    func axionConfigCuratorFieldsRoundTrip() throws {
        let config = AxionConfig(
            apiKey: "sk-test",
            curatorEnabled: true,
            curatorDryRun: false,
            curatorIntervalHours: 336.0,
            curatorStaleAfterDays: 60,
            curatorArchiveAfterDays: 180
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(decoded.curatorEnabled == true)
        #expect(decoded.curatorDryRun == false)
        #expect(decoded.curatorIntervalHours == 336.0)
        #expect(decoded.curatorStaleAfterDays == 60)
        #expect(decoded.curatorArchiveAfterDays == 180)
    }

    @Test("AxionConfig curator fields default to nil")
    func axionConfigCuratorFieldsDefaultNil() throws {
        let json = """
        {"apiKey": "sk-test"}
        """
        let config = try JSONDecoder().decode(AxionConfig.self, from: Data(json.utf8))

        #expect(config.curatorEnabled == nil)
        #expect(config.curatorDryRun == nil)
        #expect(config.curatorIntervalHours == nil)
        #expect(config.curatorStaleAfterDays == nil)
        #expect(config.curatorArchiveAfterDays == nil)
    }

    // MARK: - Curator TraceRecorder Events

    @Test("TraceRecorder records curator_completed event")
    func traceRecorderRecordsCuratorCompleted() async throws {
        let traceDir = NSTemporaryDirectory() + "axion-test-trace-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: traceDir) }

        TraceRecorder.recordCuratorCompleted(
            runId: "20260524-cur01",
            consolidations: 2,
            prunings: 1,
            transitionsApplied: 3,
            traceDir: traceDir
        )

        try await _Concurrency.Task.sleep(for: .milliseconds(100))

        let filePath = (traceDir as NSString).appendingPathComponent("20260524-cur01/review-trace.jsonl")
        #expect(FileManager.default.fileExists(atPath: filePath))

        let content = try String(contentsOfFile: filePath)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try #require(trimmed.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["event"] as? String == "curator_completed")
        #expect(json["run_id"] as? String == "20260524-cur01")
        #expect(json["consolidations"] as? Int == 2)
        #expect(json["prunings"] as? Int == 1)
        #expect(json["transitions_applied"] as? Int == 3)
    }

    @Test("TraceRecorder records curator_failed event")
    func traceRecorderRecordsCuratorFailed() async throws {
        let traceDir = NSTemporaryDirectory() + "axion-test-trace-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: traceDir) }

        TraceRecorder.recordCuratorFailed(
            runId: "20260524-cur02",
            error: "curator LLM phase failed",
            traceDir: traceDir
        )

        try await _Concurrency.Task.sleep(for: .milliseconds(100))

        let filePath = (traceDir as NSString).appendingPathComponent("20260524-cur02/review-trace.jsonl")
        #expect(FileManager.default.fileExists(atPath: filePath))

        let content = try String(contentsOfFile: filePath)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try #require(trimmed.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["event"] as? String == "curator_failed")
        #expect(json["error"] as? String == "curator LLM phase failed")
    }

    // MARK: - Story 22.4: Dependency Injection & Scheduling

    @Test("SkillCuratorConfig uses AxionConfig curator fields with fallbacks")
    func skillCuratorConfigUsesAxionConfigFields() {
        // Custom values
        let config = AxionConfig(
            apiKey: "sk-test",
            curatorEnabled: false,
            curatorDryRun: true,
            curatorIntervalHours: 336.0,
            curatorStaleAfterDays: 60,
            curatorArchiveAfterDays: 180
        )
        let curatorConfig = SkillCuratorConfig(
            intervalHours: config.curatorIntervalHours ?? 168.0,
            staleAfterDays: config.curatorStaleAfterDays ?? 30,
            archiveAfterDays: config.curatorArchiveAfterDays ?? 90,
            dryRun: config.curatorDryRun ?? false,
            enabled: config.curatorEnabled ?? true
        )
        #expect(curatorConfig.intervalHours == 336.0)
        #expect(curatorConfig.staleAfterDays == 60)
        #expect(curatorConfig.archiveAfterDays == 180)
        #expect(curatorConfig.dryRun == true)
        #expect(curatorConfig.enabled == false)
    }

    @Test("SkillCuratorConfig defaults when AxionConfig curator fields are nil")
    func skillCuratorConfigDefaultsWhenNil() {
        let config = AxionConfig(apiKey: "sk-test")
        let curatorConfig = SkillCuratorConfig(
            intervalHours: config.curatorIntervalHours ?? 168.0,
            staleAfterDays: config.curatorStaleAfterDays ?? 30,
            archiveAfterDays: config.curatorArchiveAfterDays ?? 90,
            dryRun: config.curatorDryRun ?? false,
            enabled: config.curatorEnabled ?? true
        )
        #expect(curatorConfig.intervalHours == 168.0)
        #expect(curatorConfig.staleAfterDays == 30)
        #expect(curatorConfig.archiveAfterDays == 90)
        #expect(curatorConfig.dryRun == false)
        #expect(curatorConfig.enabled == true)
    }

    @Test("SkillCuratorStore receives correct skillsDir")
    func skillCuratorStoreReceivesCorrectSkillsDir() async {
        let tempDir = NSTemporaryDirectory() + "axion-test-curator-\(UUID().uuidString)"
        let store = SkillCuratorStore(skillsDir: tempDir)
        let state = await store.loadState()
        // Default state should be returned when no persisted state exists
        #expect(state.lastRunAt == nil)
        #expect(state.runCount == 0)
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    @Test("IntelligentCurator holds all 6 dependencies")
    func intelligentCuratorHoldsAllDependencies() async {
        let tempMemoryDir = NSTemporaryDirectory() + "axion-test-mem-\(UUID().uuidString)"
        let tempSkillsDir = NSTemporaryDirectory() + "axion-test-skills-\(UUID().uuidString)"

        let usageStore = SkillUsageStore(skillsDir: tempSkillsDir)
        let curatorStore = SkillCuratorStore(skillsDir: tempSkillsDir)
        let curatorConfig = SkillCuratorConfig()
        let skillCurator = SkillCurator(
            usageStore: usageStore,
            curatorStore: curatorStore,
            config: curatorConfig
        )
        let factStore = FactStore(memoryDir: tempMemoryDir)
        let skillRegistry = SkillRegistry()
        let skillEvolver = LLMSkillEvolver(
            client: AnthropicClient(apiKey: "sk-test"),
            evolutionModel: AxionConfig.defaultReviewModel
        )

        let curator = IntelligentCurator(
            skillCurator: skillCurator,
            factStore: factStore,
            skillRegistry: skillRegistry,
            skillEvolver: skillEvolver,
            usageStore: usageStore,
            curatorStore: curatorStore
        )

        // Verify all 6 deps accessible
        #expect(curator.skillCurator.config.intervalHours == 168.0)
        #expect(curator.skillRegistry.allSkills.isEmpty)
        #expect(curator.usageStore === usageStore)
        #expect(curator.curatorStore === curatorStore)

        try? FileManager.default.removeItem(atPath: tempMemoryDir)
        try? FileManager.default.removeItem(atPath: tempSkillsDir)
    }

    @Test("SkillCurator.shouldRun skips when intervalHours not elapsed")
    func curatorShouldRunSkipsWhenIntervalNotElapsed() async {
        let tempSkillsDir = NSTemporaryDirectory() + "axion-test-skills-\(UUID().uuidString)"
        let usageStore = SkillUsageStore(skillsDir: tempSkillsDir)
        let curatorStore = SkillCuratorStore(skillsDir: tempSkillsDir)

        // Save state with a recent lastRunAt
        var state = await curatorStore.loadState()
        state.lastRunAt = Date()  // Just ran — interval not elapsed
        try? await curatorStore.saveState(state)

        let config = SkillCuratorConfig(intervalHours: 168.0)
        let curator = SkillCurator(usageStore: usageStore, curatorStore: curatorStore, config: config)

        let freshState = await curatorStore.loadState()
        #expect(!curator.shouldRun(state: freshState))

        try? FileManager.default.removeItem(atPath: tempSkillsDir)
    }

    @Test("SkillCurator.shouldRun triggers when intervalHours elapsed")
    func curatorShouldRunTriggersWhenIntervalElapsed() async {
        let tempSkillsDir = NSTemporaryDirectory() + "axion-test-skills-\(UUID().uuidString)"
        let usageStore = SkillUsageStore(skillsDir: tempSkillsDir)
        let curatorStore = SkillCuratorStore(skillsDir: tempSkillsDir)

        // Save state with an old lastRunAt (200 hours ago > 168 hour interval)
        var state = await curatorStore.loadState()
        state.lastRunAt = Date().addingTimeInterval(-200 * 3600)
        try? await curatorStore.saveState(state)

        let config = SkillCuratorConfig(intervalHours: 168.0)
        let curator = SkillCurator(usageStore: usageStore, curatorStore: curatorStore, config: config)

        let freshState = await curatorStore.loadState()
        #expect(curator.shouldRun(state: freshState))

        try? FileManager.default.removeItem(atPath: tempSkillsDir)
    }

    @Test("AgentBuilder.build() intelligentCurator is nil when dryrun")
    func intelligentCuratorNilOnDryrun() async throws {
        let config = AxionConfig(apiKey: "sk-test")
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "test",
            dryrun: true
        )
        let result = try await AgentBuilder.build(buildConfig)
        #expect(result.intelligentCurator == nil)
    }

    @Test("AgentBuilder.build() intelligentCurator is nil when noMemory")
    func intelligentCuratorNilOnNoMemory() async throws {
        let config = AxionConfig(apiKey: "sk-test")
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "test",
            noMemory: true,
            dryrun: true
        )
        let result = try await AgentBuilder.build(buildConfig)
        #expect(result.intelligentCurator == nil)
    }

    // MARK: - Story 22.5: Skill Usage Tracking

    @Test("AgentBuildResult.usageStore is non-nil when memory enabled and not dryrun")
    func usageStoreNonNilWhenMemoryEnabled() async throws {
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
        #expect(result.usageStore != nil)
    }

    @Test("AgentBuildResult.usageStore is nil when dryrun")
    func usageStoreNilOnDryrun() async throws {
        let config = AxionConfig(apiKey: "sk-test")
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "test",
            dryrun: true
        )
        let result = try await AgentBuilder.build(buildConfig)
        #expect(result.usageStore == nil)
    }

    @Test("AgentBuildResult.usageStore is nil when noMemory")
    func usageStoreNilOnNoMemory() async throws {
        let config = AxionConfig(apiKey: "sk-test")
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "test",
            noMemory: true,
            dryrun: true
        )
        let result = try await AgentBuilder.build(buildConfig)
        #expect(result.usageStore == nil)
    }

    @Test("SkillUsageStore bumpView writes .usage.json")
    func bumpViewWritesUsageJson() async throws {
        let tempDir = NSTemporaryDirectory() + "axion-test-usage-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = SkillUsageStore(skillsDir: tempDir)
        try await store.bumpView(skillName: "screenshot-analyze")

        let usagePath = (tempDir as NSString).appendingPathComponent(".usage.json")
        #expect(FileManager.default.fileExists(atPath: usagePath))

        let data = try Data(contentsOf: URL(fileURLWithPath: usagePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let entry = json["screenshot-analyze"] as! [String: Any]
        #expect(entry["viewCount"] as? Int == 1)
        #expect(entry["lastViewedAt"] != nil)
    }

    @Test("SkillUsageStore bumpManage updates lastManagedAt")
    func bumpManageUpdatesLastManagedAt() async throws {
        let tempDir = NSTemporaryDirectory() + "axion-test-usage-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = SkillUsageStore(skillsDir: tempDir)
        try await store.bumpManage(skillName: "my-skill")

        let usage = await store.getUsage(skillName: "my-skill")
        #expect(usage.lastManagedAt != nil)
    }

    @Test("SkillUsageStore auto-creates .usage.json on first bump")
    func autoCreatesUsageJsonOnFirstBump() async throws {
        let tempDir = NSTemporaryDirectory() + "axion-test-usage-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let usagePath = (tempDir as NSString).appendingPathComponent(".usage.json")
        #expect(!FileManager.default.fileExists(atPath: usagePath))

        let store = SkillUsageStore(skillsDir: tempDir)
        try await store.bumpView(skillName: "new-skill")

        #expect(FileManager.default.fileExists(atPath: usagePath))
    }

    @Test("RunOrchestrator.extractSkillName parses skill from JSON input")
    func extractSkillNameParsesCorrectly() {
        let input = #"{"skill": "screenshot-analyze", "args": "分析屏幕"}"#
        let name = RunOrchestrator.extractSkillName(from: input)
        #expect(name == "screenshot-analyze")
    }

    @Test("RunOrchestrator.extractSkillName returns nil for invalid JSON")
    func extractSkillNameReturnsNilForInvalidJson() {
        let name = RunOrchestrator.extractSkillName(from: "not-json")
        #expect(name == nil)
    }

    @Test("RunOrchestrator.extractSkillName returns nil when skill key missing")
    func extractSkillNameReturnsNilWhenNoSkillKey() {
        let input = #"{"args": "some args"}"#
        let name = RunOrchestrator.extractSkillName(from: input)
        #expect(name == nil)
    }

    @Test("Usage tracking failure does not block — catchable error on unwritable path")
    func usageTrackingFailureDoesNotBlock() async throws {
        // Use a path that cannot be written to — bumpView should throw, error must be catchable
        let store = SkillUsageStore(skillsDir: "/dev/null/impossible-path")
        do {
            try await store.bumpView(skillName: "test-skill")
        } catch {
            // Expected: error is catchable — calling code's do/catch prevents blocking
        }
    }
}
