import Foundation
import OpenAgentSDK

import AxionCore

/// Tool that queries the status of a previously submitted task.
struct QueryTaskStatusTool: ToolProtocol {

    // MARK: - ToolProtocol

    let name = "query_task_status"
    let description = "Query the status of a previously submitted task."
    nonisolated(unsafe) let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": [
            "run_id": [
                "type": "string",
                "description": "Run ID returned by run_task",
            ],
        ],
        "required": ["run_id"],
    ]
    let isReadOnly = true

    // MARK: - Dependencies

    private let runTracker: RunTracker

    // MARK: - Init

    init(runTracker: RunTracker) {
        self.runTracker = runTracker
    }

    // MARK: - ToolProtocol.call

    func call(input: Any, context: ToolContext) async -> ToolResult {
        guard let params = input as? [String: Any],
              let runId = params["run_id"] as? String,
              !runId.isEmpty
        else {
            return errorResult(
                toolUseId: context.toolUseId,
                error: "missing_run_id",
                message: "Missing required 'run_id' parameter",
                suggestion: "Provide the 'run_id' returned by a previous run_task call"
            )
        }

        guard let run = await runTracker.getRun(runId: runId) else {
            return errorResult(
                toolUseId: context.toolUseId,
                error: "not_found",
                message: "Run ID '\(runId)' not found",
                suggestion: "Check that the run_id is correct and the run hasn't expired"
            )
        }

        let response = TaskStatusResponse(
            runId: run.runId,
            status: run.status.rawValue,
            task: run.task,
            totalSteps: run.totalSteps,
            durationMs: run.durationMs,
            steps: run.steps
        )
        return encodeResult(toolUseId: context.toolUseId, isError: false) { encoder in
            try encoder.encode(response)
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

private struct TaskStatusResponse: Encodable {
    let runId: String
    let status: String
    let task: String
    let totalSteps: Int
    let durationMs: Int?
    let steps: [StepSummary]

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case task
        case totalSteps = "total_steps"
        case durationMs = "duration_ms"
        case steps
    }
}

private struct ToolErrorResponse: Encodable {
    let error: String
    let message: String
    let suggestion: String
}
