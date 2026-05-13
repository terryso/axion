import XCTest
import OpenAgentSDK
@testable import AxionCLI

// [P0] ATDD GREEN-PHASE — Story 6.1 AC3

final class RunTaskToolTests: XCTestCase {

    // MARK: - ToolProtocol properties

    func test_runTaskTool_nameIsCorrect() {
        let (tool, _, _) = createTool()
        XCTAssertEqual(tool.name, "run_task")
    }

    func test_runTaskTool_descriptionIsNonEmpty() {
        let (tool, _, _) = createTool()
        XCTAssertFalse(tool.description.isEmpty)
    }

    func test_runTaskTool_inputSchemaContainsTask() {
        let (tool, _, _) = createTool()
        guard let props = tool.inputSchema["properties"] as? [String: Any] else {
            XCTFail("inputSchema should have 'properties'")
            return
        }
        XCTAssertNotNil(props["task"], "inputSchema should have 'task' property")
    }

    func test_runTaskTool_inputSchemaRequiresTask() {
        let (tool, _, _) = createTool()
        guard let required = tool.inputSchema["required"] as? [String] else {
            XCTFail("inputSchema should have 'required' array")
            return
        }
        XCTAssertTrue(required.contains("task"), "'task' should be required")
    }

    func test_runTaskTool_isReadOnlyIsFalse() {
        let (tool, _, _) = createTool()
        XCTAssertFalse(tool.isReadOnly)
    }

    // MARK: - call() behavior

    func test_runTaskTool_call_returnsRunId() async throws {
        let (tool, tracker, _) = createTool()
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["task": "open calculator"], context: context)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("run_id"), "Response should contain run_id")
        XCTAssertTrue(result.content.contains("running"), "Response should contain 'running' status")
    }

    func test_runTaskTool_call_missingTask_returnsError() async throws {
        let (tool, _, _) = createTool()
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: [:], context: context)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("missing_task"))
    }

    func test_runTaskTool_call_emptyTask_returnsError() async throws {
        let (tool, _, _) = createTool()
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["task": ""], context: context)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("missing_task"))
    }

    func test_runTaskTool_call_submitsRunToTracker() async throws {
        let (tool, tracker, _) = createTool()
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["task": "open calculator"], context: context)

        // Extract run_id from JSON response
        let content = result.content
        let range = content.range(of: #"(?<=run_id":")([^"]+)"#, options: .regularExpression)
        XCTAssertNotNil(range, "Should find run_id in response")
        if let range = range {
            let runId = String(content[range])
            let run = await tracker.getRun(runId: runId)
            XCTAssertNotNil(run, "Run should be tracked")
            XCTAssertEqual(run?.task, "open calculator")
        }
    }

    // MARK: - Helpers

    private func createTool() -> (RunTaskTool, RunTracker, TaskQueue) {
        let tracker = RunTracker()
        let queue = TaskQueue()
        // Create a mock agent — for unit tests we don't need a real agent
        // The RunTaskTool stores the agent but we're only testing immediate response
        let agent = createAgent(options: AgentOptions(
            apiKey: "test-key",
            model: "test-model",
            systemPrompt: "test",
            maxTurns: 1,
            maxTokens: 100,
            permissionMode: .bypassPermissions
        ))
        let tool = RunTaskTool(agent: agent, runTracker: tracker, taskQueue: queue)
        return (tool, tracker, queue)
    }
}
