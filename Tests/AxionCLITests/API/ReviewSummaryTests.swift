import Testing
import Foundation
@testable import AxionCLI

@Suite("Review Summary Integration")
struct ReviewSummaryTests {

    // MARK: - Task 5.1: TrackedRun encodes/decodes review_summary

    @Test("TrackedRun encodes/decodes review_summary field correctly")
    func trackedRunReviewSummaryRoundTrip() throws {
        let run = TrackedRun(
            runId: "20260524-test01",
            task: "test task",
            status: .completed,
            submittedAt: "2026-05-24T10:00:00+08:00",
            reviewSummary: "Review: 保存了 2 条记忆, 更新了 1 个技能"
        )

        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(TrackedRun.self, from: data)

        #expect(decoded.reviewSummary == "Review: 保存了 2 条记忆, 更新了 1 个技能")
        #expect(decoded.runId == "20260524-test01")
    }

    @Test("TrackedRun encodes review_summary as snake_case in JSON")
    func trackedRunReviewSummarySnakeCase() throws {
        let run = TrackedRun(
            runId: "test",
            task: "test",
            status: .running,
            submittedAt: "2026-05-24T10:00:00+08:00",
            reviewSummary: "some summary"
        )

        let data = try JSONEncoder().encode(run)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["review_summary"] as? String == "some summary")
    }

    // MARK: - Task 5.2: StandardTaskOutput with missing review_summary decodes as nil

    @Test("StandardTaskOutput with missing review_summary decodes as nil")
    func standardTaskOutputMissingReviewSummary() throws {
        let json = """
        {
            "run_id": "test-123",
            "task": "test task",
            "status": "completed",
            "ok": true,
            "live": true,
            "allow_foreground": false,
            "started_at": "2026-05-24T10:00:00+08:00"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(StandardTaskOutput.self, from: json)
        #expect(decoded.reviewSummary == nil)
    }

    @Test("StandardTaskOutput with review_summary decodes correctly")
    func standardTaskOutputWithReviewSummary() throws {
        let json = """
        {
            "run_id": "test-456",
            "task": "test task",
            "status": "completed",
            "ok": true,
            "live": true,
            "allow_foreground": false,
            "started_at": "2026-05-24T10:00:00+08:00",
            "review_summary": "Review completed. No actions taken."
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(StandardTaskOutput.self, from: json)
        #expect(decoded.reviewSummary == "Review completed. No actions taken.")
    }

    // MARK: - Task 5.3: Review result terminal output format (tests actual formatter)

    @Test("Review terminal output format with memory changes only")
    func reviewTerminalOutputMemoryOnly() {
        let output = RunOrchestrator.formatReviewSummary(
            memoryChanges: ["Saved memory: Calculator layout", "Saved memory: Browser tabs"],
            skillChanges: []
        )
        #expect(output == "[axion] Review: 保存了 2 条记忆")
    }

    @Test("Review terminal output format with both changes")
    func reviewTerminalOutputBoth() {
        let output = RunOrchestrator.formatReviewSummary(
            memoryChanges: ["Saved memory: X"],
            skillChanges: ["Updated skill: open_calculator", "Updated skill: close_calculator"]
        )
        #expect(output == "[axion] Review: 保存了 1 条记忆, 更新了 2 个技能")
    }

    @Test("Review skips output when no changes")
    func reviewSkipsOutputNoChanges() {
        let output = RunOrchestrator.formatReviewSummary(memoryChanges: [], skillChanges: [])
        #expect(output == nil)
    }

    // MARK: - Task 5.4: Curator result terminal output format (tests actual formatter)

    @Test("Curator terminal output format with consolidations and prunings")
    func curatorTerminalOutputBoth() {
        let output = RunOrchestrator.formatCuratorSummary(consolidationCount: 2, pruningCount: 1)
        #expect(output == "[axion] Curator: 合并 2 个技能, 归档 1 个技能")
    }

    @Test("Curator terminal output with consolidations only")
    func curatorTerminalOutputConsolidationsOnly() {
        let output = RunOrchestrator.formatCuratorSummary(consolidationCount: 3, pruningCount: 0)
        #expect(output == "[axion] Curator: 合并 3 个技能")
    }

    @Test("Curator skips output when no changes")
    func curatorSkipsOutputNoChanges() {
        let output = RunOrchestrator.formatCuratorSummary(consolidationCount: 0, pruningCount: 0)
        #expect(output == nil)
    }

    // MARK: - Task 5.5: RunCoordinator.updateRunReviewSummary persists the summary

    @Test("RunCoordinator.updateRunReviewSummary persists the summary")
    func runCoordinatorUpdateReviewSummary() async {
        let coordinator = RunCoordinator()
        let runId = await coordinator.submitRun(task: "test task")

        await coordinator.updateRunReviewSummary(runId: runId, reviewSummary: "Review: 保存了 3 条记忆")

        let run = await coordinator.getRun(runId: runId)
        #expect(run?.reviewSummary == "Review: 保存了 3 条记忆")
    }

    @Test("RunCoordinator.updateRunReviewSummary ignores unknown runId")
    func runCoordinatorUpdateReviewSummaryUnknownRun() async {
        let coordinator = RunCoordinator()

        await coordinator.updateRunReviewSummary(runId: "nonexistent", reviewSummary: "test")

        let run = await coordinator.getRun(runId: "nonexistent")
        #expect(run == nil)
    }
}
