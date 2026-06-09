import Foundation

extension AxionError: LocalizedError {
    public var errorDescription: String? {
        errorPayload.message
    }
}

public enum AxionError: Error, Equatable {
    case planningFailed(reason: String)
    case executionFailed(step: Int, reason: String)
    case verificationFailed(step: Int, reason: String)
    case helperNotRunning
    case helperConnectionFailed(reason: String)
    case configError(reason: String)
    case mcpError(tool: String, reason: String)
    case invalidPlan(reason: String)
    case maxRetriesExceeded(retries: Int)
    case stepBudgetExceeded(steps: Int, limit: Int)
    case batchBudgetExceeded(batches: Int, limit: Int)
    case timeout(operation: String, seconds: Double)
    case cancelled
    case unknown(reason: String)
    case missingApiKey(suggestion: String)
    case helperNotFound(suggestion: String)
    case runLocked(runId: String, pid: Int32)
    case modelCallBudgetExceeded(calls: Int, limit: Int)
    case screenshotBudgetExceeded(count: Int, limit: Int)
    case sessionNotFound(id: String)
    case sessionAlreadyRunning(id: String)

    public struct MCPErrorPayload: Codable, Equatable {
        public let error: String
        public let message: String
        public let suggestion: String
    }

    public var errorPayload: MCPErrorPayload {
        switch self {
        case .planningFailed(let reason):
            return MCPErrorPayload(
                error: "planning_failed",
                message: "Plan generation failed: \(reason)",
                suggestion: "Try rephrasing the task or breaking it into smaller steps."
            )
        case .executionFailed(let step, let reason):
            return MCPErrorPayload(
                error: "execution_failed",
                message: "Step \(step) failed: \(reason)",
                suggestion: "Check if the target application is accessible and retry."
            )
        case .verificationFailed(let step, let reason):
            return MCPErrorPayload(
                error: "verification_failed",
                message: "Verification of step \(step) failed: \(reason)",
                suggestion: "The step may not have produced the expected result. Consider replanning."
            )
        case .helperNotRunning:
            return MCPErrorPayload(
                error: "helper_not_running",
                message: "AxionHelper is not running.",
                suggestion: "Start AxionHelper before running tasks."
            )
        case .helperConnectionFailed(let reason):
            return MCPErrorPayload(
                error: "helper_connection_failed",
                message: "Failed to connect to AxionHelper: \(reason)",
                suggestion: "Ensure AxionHelper is running and the MCP server is accessible."
            )
        case .configError(let reason):
            return MCPErrorPayload(
                error: "config_error",
                message: "Configuration error: \(reason)",
                suggestion: "Run 'axion setup' to configure or check your settings."
            )
        case .mcpError(let tool, let reason):
            return MCPErrorPayload(
                error: "mcp_error",
                message: "MCP tool '\(tool)' error: \(reason)",
                suggestion: "Check the tool parameters and try again."
            )
        case .invalidPlan(let reason):
            return MCPErrorPayload(
                error: "invalid_plan",
                message: "Invalid plan: \(reason)",
                suggestion: "Regenerate the plan with clearer instructions."
            )
        case .maxRetriesExceeded(let retries):
            return MCPErrorPayload(
                error: "max_retries_exceeded",
                message: "Maximum replan retries (\(retries)) exceeded.",
                suggestion: "The task may be too complex. Try breaking it down."
            )
        case .stepBudgetExceeded(let steps, let limit):
            return MCPErrorPayload(
                error: "step_budget_exceeded",
                message: "Step budget exceeded: \(steps)/\(limit) steps used.",
                suggestion: "Increase --max-steps or simplify the task."
            )
        case .batchBudgetExceeded(let batches, let limit):
            return MCPErrorPayload(
                error: "batch_budget_exceeded",
                message: "Batch budget exceeded: \(batches)/\(limit) batches used.",
                suggestion: "Increase --max-batches or simplify the task."
            )
        case .timeout(let operation, let seconds):
            return MCPErrorPayload(
                error: "timeout",
                message: "Operation '\(operation)' timed out after \(seconds)s.",
                suggestion: "Increase timeout or check if the target application is responding."
            )
        case .cancelled:
            return MCPErrorPayload(
                error: "cancelled",
                message: "Task was cancelled.",
                suggestion: "No action needed."
            )
        case .unknown(let reason):
            return MCPErrorPayload(
                error: "unknown",
                message: reason,
                suggestion: "Check logs for more details."
            )
        case .missingApiKey(let suggestion):
            return MCPErrorPayload(
                error: "missing_api_key",
                message: "API key is required but not configured.",
                suggestion: suggestion
            )
        case .helperNotFound(let suggestion):
            return MCPErrorPayload(
                error: "helper_not_found",
                message: "AxionHelper.app could not be found.",
                suggestion: suggestion
            )
        case .runLocked(let runId, let pid):
            return MCPErrorPayload(
                error: "run_locked",
                message: "另一个 live run（run_id: \(runId), pid: \(pid)）正在执行，请等待其完成或使用 `axion cancel \(runId)` 取消",
                suggestion: "等待当前 run 完成或取消它后再试"
            )
        case .modelCallBudgetExceeded(let calls, let limit):
            return MCPErrorPayload(
                error: "model_call_budget_exceeded",
                message: "已达到模型调用上限（\(calls)/\(limit)次）",
                suggestion: "增加 --max-model-calls 或简化任务。"
            )
        case .screenshotBudgetExceeded(let count, let limit):
            return MCPErrorPayload(
                error: "screenshot_budget_exceeded",
                message: "已达到截图上限（\(count)/\(limit)次）",
                suggestion: "增加 --max-screenshots 或简化任务。"
            )
        case .sessionNotFound(let id):
            return MCPErrorPayload(
                error: "session_not_found",
                message: "Session not found: \(id)",
                suggestion: "Run 'axion sessions' to see available sessions."
            )
        case .sessionAlreadyRunning(let id):
            return MCPErrorPayload(
                error: "session_already_running",
                message: "Session is already running: \(id)",
                suggestion: "Wait for the current session to complete or cancel it first."
            )
        }
    }

}
