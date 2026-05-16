import Testing
import OpenAgentSDK
@testable import AxionCLI

@Suite("RunTaskTool")
struct RunTaskToolTests {

    @Test("name is correct")
    func nameIsCorrect() {
        let (tool, _, _) = createTool()
        #expect(tool.name == "run_task")
    }

    @Test("description is non-empty")
    func descriptionIsNonEmpty() {
        let (tool, _, _) = createTool()
        #expect(!tool.description.isEmpty)
    }

    @Test("inputSchema contains task")
    func inputSchemaContainsTask() {
        let (tool, _, _) = createTool()
        guard let props = tool.inputSchema["properties"] as? [String: Any] else {
            Issue.record("inputSchema should have 'properties'")
            return
        }
        #expect(props["task"] != nil)
    }

    @Test("inputSchema requires task")
    func inputSchemaRequiresTask() {
        let (tool, _, _) = createTool()
        guard let required = tool.inputSchema["required"] as? [String] else {
            Issue.record("inputSchema should have 'required' array")
            return
        }
        #expect(required.contains("task"))
    }

    @Test("isReadOnly is false")
    func isReadOnlyIsFalse() {
        let (tool, _, _) = createTool()
        #expect(!tool.isReadOnly)
    }

    @Test("call returns run_id")
    func callReturnsRunId() async throws {
        let (tool, _, _) = createTool()
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["task": "open calculator"], context: context)

        #expect(!result.isError)
        #expect(result.content.contains("run_id"))
        #expect(result.content.contains("running"))
    }

    @Test("call with missing task returns error")
    func callMissingTaskReturnsError() async throws {
        let (tool, _, _) = createTool()
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: [:], context: context)

        #expect(result.isError)
        #expect(result.content.contains("missing_task"))
    }

    @Test("call with empty task returns error")
    func callEmptyTaskReturnsError() async throws {
        let (tool, _, _) = createTool()
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["task": ""], context: context)

        #expect(result.isError)
        #expect(result.content.contains("missing_task"))
    }

    @Test("call submits run to tracker")
    func callSubmitsRunToTracker() async throws {
        let (tool, tracker, _) = createTool()
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["task": "open calculator"], context: context)

        let content = result.content
        let range = content.range(of: #"(?<=run_id":")([^"]+)"#, options: .regularExpression)
        #expect(range != nil)
        if let range = range {
            let runId = String(content[range])
            let run = await tracker.getRun(runId: runId)
            #expect(run != nil)
            #expect(run?.task == "open calculator")
        }
    }

    private func createTool() -> (RunTaskTool, RunTracker, TaskQueue) {
        let tracker = RunTracker()
        let queue = TaskQueue()
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
