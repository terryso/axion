import Testing
import OpenAgentSDK
@testable import AxionCLI

@Suite("QueryTaskStatusTool")
struct QueryTaskStatusToolTests {

    @Test("name is correct")
    func nameIsCorrect() {
        let tool = createTool(tracker: RunTracker())
        #expect(tool.name == "query_task_status")
    }

    @Test("description is non-empty")
    func descriptionIsNonEmpty() {
        let tool = createTool(tracker: RunTracker())
        #expect(!tool.description.isEmpty)
    }

    @Test("inputSchema contains run_id")
    func inputSchemaContainsRunId() {
        let tool = createTool(tracker: RunTracker())
        guard let props = tool.inputSchema["properties"] as? [String: Any] else {
            Issue.record("inputSchema should have 'properties'")
            return
        }
        #expect(props["run_id"] != nil)
    }

    @Test("inputSchema requires run_id")
    func inputSchemaRequiresRunId() {
        let tool = createTool(tracker: RunTracker())
        guard let required = tool.inputSchema["required"] as? [String] else {
            Issue.record("inputSchema should have 'required' array")
            return
        }
        #expect(required.contains("run_id"))
    }

    @Test("isReadOnly is true")
    func isReadOnlyIsTrue() {
        let tool = createTool(tracker: RunTracker())
        #expect(tool.isReadOnly)
    }

    @Test("known runId returns status")
    func knownRunIdReturnsStatus() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))
        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["run_id": runId], context: context)

        #expect(!result.isError)
        #expect(result.content.contains(runId))
        #expect(result.content.contains("running"))
        #expect(result.content.contains("open calculator"))
    }

    @Test("completed run returns done")
    func completedRunReturnsDone() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))
        await tracker.updateRun(runId: runId, status: .done, steps: [], durationMs: 500, replanCount: 0)

        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["run_id": runId], context: context)

        #expect(!result.isError)
        #expect(result.content.contains("done"))
        #expect(result.content.contains("500"))
    }

    @Test("unknown runId returns not_found")
    func unknownRunIdReturnsNotFound() async throws {
        let tracker = RunTracker()
        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["run_id": "fake-id"], context: context)

        #expect(result.isError)
        #expect(result.content.contains("not_found"))
    }

    @Test("missing runId returns error")
    func missingRunIdReturnsError() async throws {
        let tracker = RunTracker()
        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: [:], context: context)

        #expect(result.isError)
        #expect(result.content.contains("missing_run_id"))
    }

    @Test("empty runId returns error")
    func emptyRunIdReturnsError() async throws {
        let tracker = RunTracker()
        let tool = createTool(tracker: tracker)
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["run_id": ""], context: context)

        #expect(result.isError)
        #expect(result.content.contains("missing_run_id"))
    }

    private func createTool(tracker: RunTracker) -> QueryTaskStatusTool {
        QueryTaskStatusTool(runTracker: tracker)
    }
}
