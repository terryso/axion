import OpenAgentSDK


/// Tool that submits a desktop automation task for async execution.
/// Returns a run ID immediately while the task executes in the background.
struct RunTaskTool: ToolProtocol {
    typealias TaskExecutor = @Sendable (String) async -> QueryResult

    // MARK: - ToolProtocol

    let name = "run_task"
    let description = "Submit a desktop automation task for async execution. Returns a run ID for tracking status."
    nonisolated(unsafe) let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": [
            "task": [
                "type": "string",
                "description": "Natural language task description for the agent to execute",
            ],
        ],
        "required": ["task"],
    ]
    let isReadOnly = false

    // MARK: - Dependencies

    private let executeTask: TaskExecutor
    private let runTracker: RunCoordinator
    private let taskQueue: TaskQueue
    private let runLockService: RunLockService?

    // MARK: - Init

    init(agent: Agent, runTracker: RunCoordinator, taskQueue: TaskQueue, runLockService: RunLockService? = nil) {
        self.init(
            runTracker: runTracker,
            taskQueue: taskQueue,
            runLockService: runLockService,
            executeTask: { task in
                await agent.prompt(task)
            }
        )
    }

    init(
        runTracker: RunCoordinator,
        taskQueue: TaskQueue,
        runLockService: RunLockService? = nil,
        executeTask: @escaping TaskExecutor
    ) {
        self.executeTask = executeTask
        self.runTracker = runTracker
        self.taskQueue = taskQueue
        self.runLockService = runLockService
    }

    // MARK: - ToolProtocol.call

    func call(input: Any, context: ToolContext) async -> ToolResult {
        guard let params = input as? [String: Any],
              let task = params["task"] as? String,
              !task.isEmpty
        else {
            return ToolResultHelper.errorResult(
                toolUseId: context.toolUseId,
                error: "missing_task",
                message: "Missing required 'task' parameter",
                suggestion: "Provide a non-empty 'task' string describing what to do"
            )
        }

        let runId = await runTracker.submitRun(task: task)

        // Check run lock (desktop-level exclusive access)
        let runLockService = self.runLockService ?? RunLockService()
        let lockAcquired = await runLockService.acquire(runId: runId)
        if !lockAcquired {
            let existingLock = await runLockService.readExistingLock()
            return ToolResultHelper.errorResult(
                toolUseId: context.toolUseId,
                error: "run_locked",
                message: "另一个 live run（run_id: \(existingLock?.runId ?? "unknown")）正在执行",
                suggestion: "等待当前 run 完成后再试"
            )
        }

        let capturedExecuteTask = executeTask
        let capturedTracker = runTracker

        await taskQueue.enqueue {
            let result = await capturedExecuteTask(task)
            let status: APIRunStatus = result.status == .success ? .completed : .failed
            await capturedTracker.updateRun(
                runId: runId, status: status, steps: [], durationMs: nil, replanCount: 0
            )
            await runLockService.release()
        }

        return ToolResultHelper.encodeResult(toolUseId: context.toolUseId, isError: false) { encoder in
            let response = RunTaskSuccessResponse(runId: runId, status: "running")
            return try encoder.encode(response)
        }
    }
}

// MARK: - Response Types

private struct RunTaskSuccessResponse: Encodable {
    let runId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
    }
}
