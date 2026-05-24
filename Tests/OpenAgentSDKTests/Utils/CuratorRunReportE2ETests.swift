// CuratorRunReportE2ETests.swift
// Story 25.4: CuratorRunReport — E2E Pipeline Integration Tests
//
// Full pipeline tests verifying:
// IntelligentCurator.execute() → IntelligentCuratorResult → CuratorRunReport(from:) → renderMarkdown()/renderYAML()
// Uses mock LLMClient (no real API calls per project convention).

import XCTest
@testable import OpenAgentSDK

final class CuratorRunReportE2ETests: XCTestCase {

    // MARK: - Mock LLM Client

    private struct MockLLMClient: LLMClient, Sendable {
        let responseText: String
        let shouldThrow: Bool

        init(responseText: String = "Review complete", shouldThrow: Bool = false) {
            self.responseText = responseText
            self.shouldThrow = shouldThrow
        }

        nonisolated func sendMessage(
            model: String,
            messages: [[String: Any]],
            maxTokens: Int,
            system: String?,
            tools: [[String: Any]]?,
            toolChoice: [String: Any]?,
            thinking: [String: Any]?,
            temperature: Double?
        ) async throws -> [String: Any] {
            if shouldThrow {
                throw NSError(domain: "MockLLMClient", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Simulated API error"
                ])
            }
            return [
                "content": [["type": "text", "text": responseText]],
                "stop_reason": "end_turn",
                "usage": ["input_tokens": 10, "output_tokens": 5],
            ]
        }

        nonisolated func streamMessage(
            model: String,
            messages: [[String: Any]],
            maxTokens: Int,
            system: String?,
            tools: [[String: Any]]?,
            toolChoice: [String: Any]?,
            thinking: [String: Any]?,
            temperature: Double?
        ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    // MARK: - Mock Skill Evolver

    private struct MockSkillEvolver: SkillEvolver, Sendable {
        func evolve(skill: Skill, signals: [SkillSignal], config: SkillEvolutionConfig) async throws -> SkillEvolutionResult {
            SkillEvolutionResult(
                evolvedSkill: skill,
                appliedSignals: signals,
                skippedSignals: [],
                changes: []
            )
        }
    }

    // MARK: - Helpers

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("curator-report-e2e-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        super.tearDown()
    }

    private func makeUsageStore() -> SkillUsageStore {
        SkillUsageStore(skillsDir: tempDir)
    }

    private func makeCuratorStore() -> SkillCuratorStore {
        SkillCuratorStore(skillsDir: tempDir)
    }

    private func makeCurator(
        usageStore: SkillUsageStore? = nil,
        curatorStore: SkillCuratorStore? = nil,
        config: SkillCuratorConfig = SkillCuratorConfig()
    ) -> IntelligentCurator {
        let us = usageStore ?? makeUsageStore()
        let cs = curatorStore ?? makeCuratorStore()
        return IntelligentCurator(
            skillCurator: SkillCurator(usageStore: us, curatorStore: cs, config: config),
            factStore: FactStore(),
            skillRegistry: SkillRegistry(),
            skillEvolver: MockSkillEvolver(),
            usageStore: us,
            curatorStore: cs
        )
    }

    private func makeParentAgent(
        responseText: String = "Review complete",
        shouldThrow: Bool = false
    ) -> Agent {
        let client = MockLLMClient(responseText: responseText, shouldThrow: shouldThrow)
        return Agent(
            options: AgentOptions(
                apiKey: "test-key",
                model: "claude-sonnet-4-6",
                systemPrompt: "You are a test assistant.",
                maxTurns: 10,
                sessionId: "test-session"
            ),
            client: client
        )
    }

    private func seedAgentCreatedSkill(
        store: SkillUsageStore,
        name: String,
        viewCount: Int = 5,
        lastViewedAt: Date? = Date()
    ) async throws {
        let data = SkillUsageData(
            skillName: name,
            viewCount: viewCount,
            lastViewedAt: lastViewedAt,
            provenance: .agentCreated
        )
        try await store.setUsage(skillName: name, data: data)
    }

    // MARK: - E2E: Full Pipeline — Consolidations + Prunings → Report

    func testE2E_FullPipeline_ConsolidationsAndPrunings_ReportRendered() async throws {
        let usageStore = makeUsageStore()
        let curatorStore = makeCuratorStore()
        try await seedAgentCreatedSkill(store: usageStore, name: "config-alpha")
        try await seedAgentCreatedSkill(store: usageStore, name: "config-beta")

        let yamlResponse = """
        Merged config skills.

        ```yaml
        consolidations:
          - from: config-alpha
            into: config-umbrella
            reason: Both handle config patterns
          - from: config-beta
            into: config-umbrella
            reason: Subset of config-umbrella
        prunings:
          - name: dead-skill
            reason: No usage and no recoverable content
        ```
        """

        let curator = makeCurator(usageStore: usageStore, curatorStore: curatorStore)
        let parent = makeParentAgent(responseText: yamlResponse)

        // Phase 1: Run curator
        let curatorResult = try await curator.execute(parentAgent: parent)

        // Phase 2: Build report from result
        let report = CuratorRunReport(from: curatorResult)

        // Phase 3: Render markdown
        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("# Curator run —"), "Markdown should contain header")
        XCTAssertTrue(md.contains("## LLM consolidation pass"), "Markdown should contain LLM section")
        XCTAssertTrue(md.contains("merged into `config-umbrella`"), "Markdown should contain consolidation detail")
        XCTAssertTrue(md.contains("`dead-skill`"), "Markdown should contain pruned skill")
        XCTAssertFalse(md.contains("[DRY RUN]"), "Should not be dry run")
        XCTAssertFalse(md.contains("> Error:"), "Should not have error")

        // Phase 4: Render YAML
        let yaml = report.renderYAML()
        XCTAssertTrue(yaml.contains("consolidations:"))
        XCTAssertTrue(yaml.contains("from: config-alpha"))
        XCTAssertTrue(yaml.contains("into: config-umbrella"))
        XCTAssertTrue(yaml.contains("prunings:"))
        XCTAssertTrue(yaml.contains("name: dead-skill"))
        XCTAssertFalse(yaml.contains("dry_run:"))
        XCTAssertFalse(yaml.contains("error:"))

        // Verify field extraction
        XCTAssertEqual(report.consolidations.count, 2)
        XCTAssertEqual(report.prunings.count, 1)
        XCTAssertGreaterThanOrEqual(report.durationMs, 0)
        XCTAssertNil(report.error)
        XCTAssertFalse(report.dryRun)
    }

    // MARK: - E2E: No Candidates → Empty Report

    func testE2E_FullPipeline_NoCandidates_EmptyReport() async throws {
        let usageStore = makeUsageStore()
        let curatorStore = makeCuratorStore()
        let curator = makeCurator(usageStore: usageStore, curatorStore: curatorStore)
        let parent = makeParentAgent()

        let curatorResult = try await curator.execute(parentAgent: parent)
        let report = CuratorRunReport(from: curatorResult)

        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("No changes — skill library is already well-organized."),
            "Empty result should show 'no changes' message")

        let yaml = report.renderYAML()
        XCTAssertTrue(yaml.contains("consolidations:\n  []"), "YAML should have empty consolidations")
        XCTAssertTrue(yaml.contains("prunings:\n  []"), "YAML should have empty prunings")
    }

    // MARK: - E2E: Dry Run → [DRY RUN] Prefix

    func testE2E_FullPipeline_DryRun_DryRunReport() async throws {
        let usageStore = makeUsageStore()
        let curatorStore = makeCuratorStore()
        try await seedAgentCreatedSkill(store: usageStore, name: "dry-skill-1")

        let yamlResponse = """
        Dry run summary.

        ```yaml
        consolidations:
          - from: dry-skill-1
            into: umbrella
            reason: Would merge
        prunings: []
        ```
        """

        let curator = makeCurator(usageStore: usageStore, curatorStore: curatorStore)
        let parent = makeParentAgent(responseText: yamlResponse)

        let curatorResult = try await curator.execute(parentAgent: parent, dryRun: true)
        let report = CuratorRunReport(from: curatorResult)

        XCTAssertTrue(report.dryRun)

        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("[DRY RUN] # Curator run —"), "Markdown should have [DRY RUN] prefix")
        XCTAssertTrue(md.contains("would merge"), "Markdown should use 'would' verbs")

        let yaml = report.renderYAML()
        XCTAssertTrue(yaml.contains("dry_run: true"), "YAML should have dry_run: true")
    }

    // MARK: - E2E: Phase 2 Error → Error Report

    func testE2E_FullPipeline_Phase2Error_ErrorReport() async throws {
        let usageStore = makeUsageStore()
        let curatorStore = makeCuratorStore()
        try await seedAgentCreatedSkill(store: usageStore, name: "failing-skill")

        let curator = makeCurator(usageStore: usageStore, curatorStore: curatorStore)
        let parent = makeParentAgent(shouldThrow: true)

        let curatorResult = try await curator.execute(parentAgent: parent)
        let report = CuratorRunReport(from: curatorResult)

        XCTAssertNotNil(report.error, "Report should capture error from Phase 2")
        XCTAssertTrue(report.consolidations.isEmpty)
        XCTAssertTrue(report.prunings.isEmpty)
        XCTAssertTrue(report.toolCalls.isEmpty)

        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("> Error:"), "Markdown should have error blockquote")

        let yaml = report.renderYAML()
        XCTAssertTrue(yaml.contains("error:"), "YAML should have error field")
    }

    // MARK: - E2E: Tool Call Extraction from LLM Phase

    func testE2E_FullPipeline_ToolCalls_ExtractedFromReviewMessages() async throws {
        let ranAt = Date(timeIntervalSince1970: 1700000000)
        let mechanicalResult = CuratorRunResult(
            transitionsApplied: [],
            skillsEvaluated: 3,
            skillsSkipped: 1,
            errors: [],
            durationMs: 100,
            dryRun: false,
            ranAt: ranAt
        )

        let reviewMessages: [SDKMessage] = [
            .toolUse(SDKMessage.ToolUseData(
                toolName: "curator_archive_skill",
                toolUseId: "tu_e2e_001",
                input: "{\"name\": \"old-skill\"}"
            )),
            .toolResult(SDKMessage.ToolResultData(
                toolUseId: "tu_e2e_001",
                content: "Archived old-skill",
                isError: false
            )),
            .toolUse(SDKMessage.ToolUseData(
                toolName: "review_update_skill",
                toolUseId: "tu_e2e_002",
                input: "{\"skill\": \"debugging-workflow\", \"action\": \"update\"}"
            )),
            .toolResult(SDKMessage.ToolResultData(
                toolUseId: "tu_e2e_002",
                content: "Updated skill",
                isError: false
            )),
        ]

        let llmResult = ReviewAgentResult(
            memoryChanges: [],
            skillChanges: [],
            summary: "Archived 1, updated 1",
            reviewMessages: reviewMessages
        )

        let curatorResult = IntelligentCuratorResult(
            mechanicalResult: mechanicalResult,
            llmResult: llmResult,
            consolidations: [
                CuratorConsolidation(from: "debug-login", into: "debugging-workflow", reason: "subset")
            ],
            prunings: [
                CuratorPruning(name: "old-skill", reason: "stale")
            ],
            durationMs: 2500,
            dryRun: false,
            error: nil
        )

        let report = CuratorRunReport(from: curatorResult)

        XCTAssertEqual(report.toolCalls.count, 2, "Should extract 2 tool calls from review messages")
        XCTAssertEqual(report.toolCalls[0].toolName, "curator_archive_skill")
        XCTAssertEqual(report.toolCalls[0].result, "Archived old-skill")
        XCTAssertFalse(report.toolCalls[0].isError)
        XCTAssertEqual(report.toolCalls[1].toolName, "review_update_skill")

        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("Skills: 4 → 2 (-2)"), "Markdown should show skill count delta")
    }

    // MARK: - E2E: Markdown Duration Formatting

    func testE2E_FullPipeline_DurationFormatting() async throws {
        let shortReport = CuratorRunReport(
            startedAt: Date(),
            durationMs: 800,
            autoTransitions: makeTransitions(),
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: false,
            skillsBefore: 5,
            skillsAfter: 5
        )
        XCTAssertTrue(shortReport.renderMarkdown().contains("Duration: 0s"))
        XCTAssertTrue(shortReport.renderMarkdown().contains("Skills: 5 → 5 (0)"))

        let longReport = CuratorRunReport(
            startedAt: Date(),
            durationMs: 185_000,
            autoTransitions: makeTransitions(),
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: false,
            skillsBefore: 5,
            skillsAfter: 5
        )
        XCTAssertTrue(longReport.renderMarkdown().contains("Duration: 3m 5s"))
    }

    // MARK: - E2E: Auto-Transitions Section

    func testE2E_FullPipeline_AutoTransitions_RenderedInReport() async throws {
        let transitions = makeTransitions()
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 2000,
            autoTransitions: transitions,
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: false
        )

        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("## Auto-transitions"))
        XCTAssertTrue(md.contains("transitions applied: 2"))
        XCTAssertTrue(md.contains("marked stale: 1"))
        XCTAssertTrue(md.contains("archived: 1"))
    }

    // MARK: - E2E: Equatable Across Pipeline

    func testE2E_FullPipeline_Equatable_TwoReportsFromSameResult() async throws {
        let usageStore = makeUsageStore()
        let curatorStore = makeCuratorStore()
        let curator = makeCurator(usageStore: usageStore, curatorStore: curatorStore)
        let parent = makeParentAgent()

        let curatorResult = try await curator.execute(parentAgent: parent)

        let report1 = CuratorRunReport(from: curatorResult)
        let report2 = CuratorRunReport(from: curatorResult)

        XCTAssertEqual(report1, report2, "Two reports from same result should be equal")
    }

    // MARK: - E2E: CuratorToolCall Codable Round-Trip

    func testE2E_CuratorToolCall_CodableRoundTrip() throws {
        let call = CuratorToolCall(
            toolName: "curator_archive_skill",
            input: "{\"name\": \"test\"}",
            result: "Archived",
            isError: false
        )
        let data = try JSONEncoder().encode(call)
        let decoded = try JSONDecoder().decode(CuratorToolCall.self, from: data)
        XCTAssertEqual(decoded, call)
    }

    // MARK: - E2E: YAML Special Characters Escaping

    func testE2E_FullPipeline_YAMLSpecialCharacters_ProperlyEscaped() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 100,
            autoTransitions: [],
            consolidations: [
                CuratorConsolidation(
                    from: "skill:with:colons",
                    into: "target",
                    reason: "reason with \"quotes\" and: colons"
                )
            ],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: false
        )

        let yaml = report.renderYAML()
        XCTAssertTrue(yaml.contains("\"skill:with:colons\""), "Colons in names should be quoted")
        XCTAssertTrue(yaml.contains("\\\"quotes\\\""), "Embedded quotes should be escaped")
    }

    // MARK: - E2E: Combined Error + Dry-Run

    func testE2E_FullPipeline_ErrorWithDryRun_BothRendered() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 500,
            autoTransitions: [],
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: "Timeout during LLM phase",
            dryRun: true
        )

        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("[DRY RUN]"), "Should have dry-run prefix")
        XCTAssertTrue(md.contains("> Error: Timeout during LLM phase"), "Should have error blockquote")

        let yaml = report.renderYAML()
        XCTAssertTrue(yaml.contains("dry_run: true"))
        XCTAssertTrue(yaml.contains("error: \"Timeout during LLM phase\""))
    }

    // MARK: - Helpers

    private func makeTransitions() -> [SkillLifecycleTransition] {
        [
            SkillLifecycleTransition(
                skillName: "old-skill-1",
                from: .active,
                to: .deprecated,
                reason: "Not used in 30 days",
                evaluatedAt: Date(timeIntervalSince1970: 1700000000)
            ),
            SkillLifecycleTransition(
                skillName: "old-skill-2",
                from: .deprecated,
                to: .retired,
                reason: "Not used in 90 days",
                evaluatedAt: Date(timeIntervalSince1970: 1700000000)
            ),
        ]
    }
}
