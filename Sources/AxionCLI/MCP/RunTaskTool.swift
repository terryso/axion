import Foundation
import OpenAgentSDK

import AxionCore

/// Tool that submits a desktop automation task for async execution.
/// Returns a run ID immediately while the task executes in the background.
struct RunTaskTool: ToolProtocol {

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

    private let agent: Agent
    private let runTracker: RunTracker
    private let taskQueue: TaskQueue

    // MARK: - Init

    init(agent: Agent, runTracker: RunTracker, taskQueue: TaskQueue) {
        self.agent = agent
        self.runTracker = runTracker
        self.taskQueue = taskQueue
    }

    // MARK: - ToolProtocol.call

    func call(input: Any, context: ToolContext) async -> ToolResult {
        guard let params = input as? [String: Any],
              let task = params["task"] as? String,
              !task.isEmpty
        else {
            return errorResult(
                toolUseId: context.toolUseId,
                error: "missing_task",
                message: "Missing required 'task' parameter",
                suggestion: "Provide a non-empty 'task' string describing what to do"
            )
        }

        let runId = await runTracker.submitRun(task: task, options: RunOptions(task: task))

        let capturedAgent = agent
        let capturedTracker = runTracker

        await taskQueue.enqueue {
            let result = await capturedAgent.prompt(task)
            let status: APIRunStatus = result.status == .success ? .done : .failed
            await capturedTracker.updateRun(
                runId: runId, status: status, steps: [], durationMs: nil, replanCount: 0
            )
        }

        return encodeResult(toolUseId: context.toolUseId, isError: false) { encoder in
            let response = RunTaskSuccessResponse(runId: runId, status: "running")
            return try encoder.encode(response)
        }
    }

    // MARK: - Private Helpers

    private func errorResult(toolUseId: String, error: String, message: String, suggestion: String) -> ToolResult {
        encodeResult(toolUseId: toolUseId, isError: true) { encoder in
            let response = ToolErrorResponse(error: error, message: message, suggestion: suggestion)
            return try encoder.encode(response)
        }
    }

    private func encodeResult(toolUseId: String, isError: Bool, _ encode: (JSONEncoder) throws -> Data) -> ToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encode(encoder)) ?? Data()
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return ToolResult(toolUseId: toolUseId, content: content, isError: isError)
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

private struct ToolErrorResponse: Encodable {
    let error: String
    let message: String
    let suggestion: String
}
