import XCTest
import OpenAgentSDK
@testable import AxionCLI

// [P0] ATDD GREEN-PHASE — Story 6.1 AC4

final class QueryTaskStatusToolTests: XCTestCase {

    // MARK: - ToolProtocol properties

    func test_queryTool_nameIsCorrect() {
        let tool = createTool(tracker: RunTracker())
        XCTAssertEqual(tool.name, "query_task_status")
    }

    func test_queryTool_descriptionIsNonEmpty() {
        let tool = createTool(tracker: RunTracker())
        XCTAssertFalse(tool.description.isEmpty)
    }

    func test_queryTool_inputSchemaContainsRunId() {
        let tool = createTool(tracker: RunTracker())
        guard let props = tool.inputSchema["properties"] as? [String: Any] else {
            XCTFail("inputSchema should have 'properties'")
            return
        }
        XCTAssertNotNil(props["run_id"])
    }

    func test_queryTool_inputSchemaRequiresRunId() {
        let tool = createTool(tracker: RunTracker())
        guard let required = tool.inputSchema["required"] as? [String] else {
            XCTFail("inputSchema should have 'required' array")
            return
        }
        XCTAssertTrue(required.contains("run_id"))
    }

    func test_queryTool_isReadOnlyIsTrue() {
        let tool = createTool(tracker: RunTracker())
        XCTAssertTrue(tool.isReadOnly)
    }

    // MARK: - call() behavior — known runId

    func test_queryTool_knownRunId_returnsStatus() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))
        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["run_id": runId], context: context)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains(runId))
        XCTAssertTrue(result.content.contains("running"))
        XCTAssertTrue(result.content.contains("open calculator"))
    }

    func test_queryTool_completedRun_returnsDone() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))
        await tracker.updateRun(runId: runId, status: .done, steps: [], durationMs: 500, replanCount: 0)

        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["run_id": runId], context: context)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("done"))
        XCTAssertTrue(result.content.contains("500"))
    }

    // MARK: - call() behavior — unknown runId

    func test_queryTool_unknownRunId_returnsNotFound() async throws {
        let tracker = RunTracker()
        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["run_id": "fake-id"], context: context)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("not_found"))
    }

    // MARK: - call() behavior — missing parameter

    func test_queryTool_missingRunId_returnsError() async throws {
        let tracker = RunTracker()
        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: [:], context: context)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("missing_run_id"))
    }

    func test_queryTool_emptyRunId_returnsError() async throws {
        let tracker = RunTracker()
        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["run_id": ""], context: context)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("missing_run_id"))
    }

    // MARK: - Helpers

    private func createTool(tracker: RunTracker) -> QueryTaskStatusTool {
        QueryTaskStatusTool(runTracker: tracker)
    }
}
