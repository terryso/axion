import XCTest
@testable import OpenAgentSDK

final class CuratorRunReportTests: XCTestCase {

    // MARK: - Test Data Helpers

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

    private func makeConsolidations() -> [CuratorConsolidation] {
        [
            CuratorConsolidation(
                from: "debug-login-issue",
                into: "debugging-workflow",
                reason: "login debugging is a subsection of general debugging"
            ),
        ]
    }

    private func makePrunings() -> [CuratorPruning] {
        [
            CuratorPruning(
                name: "temp-analysis-2026",
                reason: "one-off analysis, no reusable pattern"
            ),
        ]
    }

    private func makeToolCallMessages() -> [SDKMessage] {
        [
            .toolUse(SDKMessage.ToolUseData(
                toolName: "skill_archive",
                toolUseId: "tu_001",
                input: "{\"name\": \"temp-analysis-2026\"}"
            )),
            .toolResult(SDKMessage.ToolResultData(
                toolUseId: "tu_001",
                content: "Archived temp-analysis-2026",
                isError: false
            )),
            .toolUse(SDKMessage.ToolUseData(
                toolName: "skill_manage",
                toolUseId: "tu_002",
                input: "{\"action\": \"merge\", \"from\": \"debug-login-issue\", \"into\": \"debugging-workflow\"}"
            )),
            .toolResult(SDKMessage.ToolResultData(
                toolUseId: "tu_002",
                content: "Merged successfully",
                isError: false
            )),
        ]
    }

    private func makeToolCalls() -> [CuratorToolCall] {
        [
            CuratorToolCall(
                toolName: "skill_archive",
                input: "{\"name\": \"temp-analysis-2026\"}",
                result: "Archived temp-analysis-2026",
                isError: false
            ),
            CuratorToolCall(
                toolName: "skill_manage",
                input: "{\"action\": \"merge\"}",
                result: "Merged successfully",
                isError: false
            ),
        ]
    }

    // MARK: - init(from:) Field Extraction (AC3)

    func testInitFromIntelligentCuratorResult() {
        let ranAt = Date(timeIntervalSince1970: 1700000000)
        let transitions = makeTransitions()
        let consolidations = makeConsolidations()
        let prunings = makePrunings()
        let reviewMessages = makeToolCallMessages()

        let mechanicalResult = CuratorRunResult(
            transitionsApplied: transitions,
            skillsEvaluated: 10,
            skillsSkipped: 5,
            errors: [],
            durationMs: 500,
            dryRun: false,
            ranAt: ranAt
        )

        let llmResult = ReviewAgentResult(
            memoryChanges: [],
            skillChanges: [],
            summary: "Consolidated 1 skill and pruned 1.",
            reviewMessages: reviewMessages
        )

        let curatorResult = IntelligentCuratorResult(
            mechanicalResult: mechanicalResult,
            llmResult: llmResult,
            consolidations: consolidations,
            prunings: prunings,
            durationMs: 3500,
            dryRun: false,
            error: nil
        )

        let report = CuratorRunReport(from: curatorResult)

        XCTAssertEqual(report.startedAt, ranAt)
        XCTAssertEqual(report.durationMs, 3500)
        XCTAssertEqual(report.autoTransitions.count, 2)
        XCTAssertEqual(report.consolidations.count, 1)
        XCTAssertEqual(report.prunings.count, 1)
        XCTAssertEqual(report.toolCalls.count, 2)
        XCTAssertNil(report.error)
        XCTAssertFalse(report.dryRun)
    }

    // MARK: - renderMarkdown — Full Report (AC4)

    func testRenderMarkdownFullReport() {
        let startedAt = Date(timeIntervalSince1970: 1700000000)
        let report = CuratorRunReport(
            startedAt: startedAt,
            durationMs: 3500,
            autoTransitions: makeTransitions(),
            consolidations: makeConsolidations(),
            prunings: makePrunings(),
            toolCalls: makeToolCalls(),
            error: nil,
            dryRun: false,
            skillsBefore: 15,
            skillsAfter: 13
        )

        let md = report.renderMarkdown()

        XCTAssertTrue(md.contains("# Curator run —"))
        XCTAssertTrue(md.contains("Duration: 3s"))
        XCTAssertTrue(md.contains("Skills: 15 → 13 (-2)"))
        XCTAssertTrue(md.contains("## Auto-transitions"))
        XCTAssertTrue(md.contains("transitions applied: 2"))
        XCTAssertTrue(md.contains("## LLM consolidation pass"))
        XCTAssertTrue(md.contains("consolidated into umbrellas: 1"))
        XCTAssertTrue(md.contains("archived for staleness: 1"))
        XCTAssertTrue(md.contains("### Consolidated into umbrella skills (1)"))
        XCTAssertTrue(md.contains("`debug-login-issue` → merged into `debugging-workflow`"))
        XCTAssertTrue(md.contains("### Pruned — archived for staleness (1)"))
        XCTAssertTrue(md.contains("`temp-analysis-2026` — archived: one-off analysis, no reusable pattern"))
    }

    // MARK: - renderMarkdown — Empty Results (AC8)

    func testRenderMarkdownEmptyResults() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 100,
            autoTransitions: [],
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: false
        )

        let md = report.renderMarkdown()

        XCTAssertTrue(md.contains("No changes — skill library is already well-organized."))
        XCTAssertFalse(md.contains("## Auto-transitions"))
        XCTAssertFalse(md.contains("## LLM consolidation pass"))
    }

    // MARK: - renderMarkdown — Dry Run (AC6)

    func testRenderMarkdownDryRun() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 2000,
            autoTransitions: [],
            consolidations: makeConsolidations(),
            prunings: makePrunings(),
            toolCalls: makeToolCalls(),
            error: nil,
            dryRun: true
        )

        let md = report.renderMarkdown()

        XCTAssertTrue(md.contains("[DRY RUN] # Curator run —"))
        XCTAssertTrue(md.contains("would merge"))
        XCTAssertTrue(md.contains("would archive"))
        XCTAssertTrue(md.contains("would consolidate"))
    }

    // MARK: - renderMarkdown — With Error (AC7)

    func testRenderMarkdownWithError() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 500,
            autoTransitions: [],
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: "Curator agent reached max turns (200)",
            dryRun: false
        )

        let md = report.renderMarkdown()

        XCTAssertTrue(md.contains("> Error: Curator agent reached max turns (200)"))
    }

    // MARK: - renderYAML — Full Output (AC5)

    func testRenderYAMLFullOutput() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 3000,
            autoTransitions: [],
            consolidations: makeConsolidations(),
            prunings: makePrunings(),
            toolCalls: [],
            error: nil,
            dryRun: false
        )

        let yaml = report.renderYAML()

        XCTAssertTrue(yaml.contains("consolidations:"))
        XCTAssertTrue(yaml.contains("from: debug-login-issue"))
        XCTAssertTrue(yaml.contains("into: debugging-workflow"))
        XCTAssertTrue(yaml.contains("reason:"))
        XCTAssertTrue(yaml.contains("login debugging is a subsection of general debugging"))
        XCTAssertTrue(yaml.contains("prunings:"))
        XCTAssertTrue(yaml.contains("name: temp-analysis-2026"))
        XCTAssertFalse(yaml.contains("dry_run:"))
        XCTAssertFalse(yaml.contains("error:"))
    }

    // MARK: - renderYAML — Empty (AC8)

    func testRenderYAMLEmpty() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 100,
            autoTransitions: [],
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: false
        )

        let yaml = report.renderYAML()

        XCTAssertTrue(yaml.contains("consolidations:"))
        XCTAssertTrue(yaml.contains("  []"))
        XCTAssertTrue(yaml.contains("prunings:"))
    }

    // MARK: - renderYAML — Dry Run (AC6)

    func testRenderYAMLDryRun() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 100,
            autoTransitions: [],
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: true
        )

        let yaml = report.renderYAML()

        XCTAssertTrue(yaml.contains("dry_run: true"))
    }

    // MARK: - renderYAML — With Error (AC7)

    func testRenderYAMLWithError() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 100,
            autoTransitions: [],
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: "Something went wrong",
            dryRun: false
        )

        let yaml = report.renderYAML()

        XCTAssertTrue(yaml.contains("error: \"Something went wrong\""))
    }

    // MARK: - Tool Call Extraction (AC3)

    func testCuratorToolCallExtraction() {
        let ranAt = Date(timeIntervalSince1970: 1700000000)
        let mechanicalResult = CuratorRunResult(
            transitionsApplied: [],
            skillsEvaluated: 5,
            skillsSkipped: 2,
            errors: [],
            durationMs: 100,
            dryRun: false,
            ranAt: ranAt
        )

        let llmResult = ReviewAgentResult(
            memoryChanges: [],
            skillChanges: [],
            summary: "Done",
            reviewMessages: makeToolCallMessages()
        )

        let curatorResult = IntelligentCuratorResult(
            mechanicalResult: mechanicalResult,
            llmResult: llmResult,
            consolidations: [],
            prunings: [],
            durationMs: 1500,
            dryRun: false,
            error: nil
        )

        let report = CuratorRunReport(from: curatorResult)

        XCTAssertEqual(report.toolCalls.count, 2)
        XCTAssertEqual(report.toolCalls[0].toolName, "skill_archive")
        XCTAssertEqual(report.toolCalls[0].input, "{\"name\": \"temp-analysis-2026\"}")
        XCTAssertEqual(report.toolCalls[0].result, "Archived temp-analysis-2026")
        XCTAssertFalse(report.toolCalls[0].isError)
        XCTAssertEqual(report.toolCalls[1].toolName, "skill_manage")
    }

    func testCuratorToolCallNoLLMResult() {
        let ranAt = Date(timeIntervalSince1970: 1700000000)
        let mechanicalResult = CuratorRunResult(
            transitionsApplied: [],
            skillsEvaluated: 5,
            skillsSkipped: 2,
            errors: [],
            durationMs: 100,
            dryRun: false,
            ranAt: ranAt
        )

        let curatorResult = IntelligentCuratorResult(
            mechanicalResult: mechanicalResult,
            llmResult: nil,
            consolidations: [],
            prunings: [],
            durationMs: 500,
            dryRun: false,
            error: nil
        )

        let report = CuratorRunReport(from: curatorResult)

        XCTAssertTrue(report.toolCalls.isEmpty)
    }

    // MARK: - Equatable Conformance (AC1)

    func testEquatableConformance() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let transitions = makeTransitions()

        let report1 = CuratorRunReport(
            startedAt: date,
            durationMs: 3000,
            autoTransitions: transitions,
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: false
        )

        let report2 = CuratorRunReport(
            startedAt: date,
            durationMs: 3000,
            autoTransitions: transitions,
            consolidations: [],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: false
        )

        XCTAssertEqual(report1, report2)
    }

    // MARK: - YAML Special Characters (AC5)

    func testRenderYAMLWithSpecialCharacters() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 100,
            autoTransitions: [],
            consolidations: [
                CuratorConsolidation(
                    from: "skill-with:colon",
                    into: "target-skill",
                    reason: "reason with \"quotes\" and: colons"
                ),
            ],
            prunings: [],
            toolCalls: [],
            error: nil,
            dryRun: false
        )

        let yaml = report.renderYAML()

        XCTAssertTrue(yaml.contains("\"skill-with:colon\""))
        XCTAssertTrue(yaml.contains("reason with \\\"quotes\\\" and: colons"))
    }

    // MARK: - Duration Formatting

    func testRenderMarkdownDurationFormatting() {
        let reportShort = CuratorRunReport(
            startedAt: Date(),
            durationMs: 500,
            consolidations: makeConsolidations(),
            toolCalls: makeToolCalls(),
            skillsBefore: 10,
            skillsAfter: 9
        )
        let shortMd = reportShort.renderMarkdown()
        XCTAssertTrue(shortMd.contains("Duration: 0s"))
        XCTAssertTrue(shortMd.contains("Skills: 10 → 9 (-1)"))

        let reportLong = CuratorRunReport(
            startedAt: Date(),
            durationMs: 125_000,
            consolidations: makeConsolidations(),
            toolCalls: makeToolCalls(),
            skillsBefore: 10,
            skillsAfter: 9
        )
        XCTAssertTrue(reportLong.renderMarkdown().contains("Duration: 2m 5s"))
    }

    // MARK: - Error Tool Call Extraction

    func testToolCallExtractionWithErrorResult() {
        let messages: [SDKMessage] = [
            .toolUse(SDKMessage.ToolUseData(
                toolName: "skill_archive",
                toolUseId: "tu_err",
                input: "{\"name\": \"bad-skill\"}"
            )),
            .toolResult(SDKMessage.ToolResultData(
                toolUseId: "tu_err",
                content: "Skill not found",
                isError: true
            )),
        ]

        let ranAt = Date(timeIntervalSince1970: 1700000000)
        let mechanicalResult = CuratorRunResult(
            transitionsApplied: [],
            skillsEvaluated: 5,
            skillsSkipped: 2,
            errors: [],
            durationMs: 100,
            dryRun: false,
            ranAt: ranAt
        )

        let llmResult = ReviewAgentResult(
            memoryChanges: [],
            skillChanges: [],
            summary: "Done",
            reviewMessages: messages
        )

        let curatorResult = IntelligentCuratorResult(
            mechanicalResult: mechanicalResult,
            llmResult: llmResult,
            consolidations: [],
            prunings: [],
            durationMs: 500,
            dryRun: false,
            error: nil
        )

        let report = CuratorRunReport(from: curatorResult)

        XCTAssertEqual(report.toolCalls.count, 1)
        XCTAssertTrue(report.toolCalls[0].isError)
        XCTAssertEqual(report.toolCalls[0].toolName, "skill_archive")
        XCTAssertEqual(report.toolCalls[0].result, "Skill not found")
    }

    // MARK: - YAML Reserved Word Quoting

    func testRenderYAMLReservedWordsQuoted() {
        let report = CuratorRunReport(
            startedAt: Date(),
            durationMs: 100,
            autoTransitions: [],
            consolidations: [
                CuratorConsolidation(from: "true", into: "false", reason: "boolean-like names")
            ],
            prunings: [
                CuratorPruning(name: "null", reason: "reserved word name")
            ],
            toolCalls: [],
            error: nil,
            dryRun: false
        )

        let yaml = report.renderYAML()
        XCTAssertTrue(yaml.contains("from: \"true\""), "YAML boolean 'true' should be quoted")
        XCTAssertTrue(yaml.contains("into: \"false\""), "YAML boolean 'false' should be quoted")
        XCTAssertTrue(yaml.contains("name: \"null\""), "YAML null should be quoted")
    }

    // MARK: - Tool Call Orphan Handling

    func testToolCallOrphanToolUseWithoutResult() {
        let messages: [SDKMessage] = [
            .toolUse(SDKMessage.ToolUseData(
                toolName: "skill_archive",
                toolUseId: "tu_orphan",
                input: "{\"name\": \"some-skill\"}"
            )),
            .assistant(SDKMessage.AssistantData(
                text: "Let me think...",
                model: "test-model",
                stopReason: "end_turn"
            )),
        ]

        let ranAt = Date(timeIntervalSince1970: 1700000000)
        let mechanicalResult = CuratorRunResult(
            transitionsApplied: [],
            skillsEvaluated: 5,
            skillsSkipped: 2,
            errors: [],
            durationMs: 100,
            dryRun: false,
            ranAt: ranAt
        )

        let llmResult = ReviewAgentResult(
            memoryChanges: [],
            skillChanges: [],
            summary: "Done",
            reviewMessages: messages
        )

        let curatorResult = IntelligentCuratorResult(
            mechanicalResult: mechanicalResult,
            llmResult: llmResult,
            consolidations: [],
            prunings: [],
            durationMs: 500,
            dryRun: false,
            error: nil
        )

        let report = CuratorRunReport(from: curatorResult)

        XCTAssertTrue(report.toolCalls.isEmpty)
    }
}
