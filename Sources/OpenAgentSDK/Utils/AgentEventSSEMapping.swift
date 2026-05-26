import Foundation

/// Maps ``AgentEvent`` instances to ``AgentSSEEvent`` for HTTP SSE forwarding.
///
/// Pure functions with no state — callers invoke ``map(_:stepIndex:)`` for each
/// event received from ``EventBus`` and forward non-nil results to the broadcaster.
public enum AgentEventSSEMapping {
    /// Convert an ``AgentEvent`` to an ``AgentSSEEvent``.
    ///
    /// Mapping:
    /// - ``AgentStartedEvent`` → `.runStarted`
    /// - ``ToolStartedEvent`` → `.stepStarted`
    /// - ``ToolCompletedEvent`` → `.stepCompleted`
    /// - ``AgentCompletedEvent`` → `.runCompleted`
    /// - ``LLMCostEvent`` → `.costUpdate`
    /// - All others → `nil`
    public static func map(_ event: any AgentEvent, stepIndex: Int = 0) -> AgentSSEEvent? {
        switch event {
        case let e as AgentStartedEvent:
            return .runStarted(RunStartedData(
                runId: e.sessionId ?? "",
                task: e.task
            ))
        case let e as ToolStartedEvent:
            return .stepStarted(StepStartedData(
                stepIndex: stepIndex,
                tool: e.toolName
            ))
        case let e as ToolCompletedEvent:
            return .stepCompleted(StepCompletedData(
                stepIndex: stepIndex,
                tool: e.toolName,
                success: !e.isError,
                durationMs: e.durationMs
            ))
        case let e as AgentCompletedEvent:
            return .runCompleted(RunCompletedData(
                runId: e.sessionId ?? "",
                finalStatus: "completed",
                totalSteps: e.totalSteps,
                durationMs: e.durationMs
            ))
        case let e as LLMCostEvent:
            return .costUpdate(CostUpdateData(
                model: e.model,
                inputTokens: e.inputTokens,
                outputTokens: e.outputTokens,
                cacheCreationInputTokens: e.cacheCreationInputTokens,
                cacheReadInputTokens: e.cacheReadInputTokens,
                estimatedCostUsd: e.estimatedCostUsd
            ))
        default:
            return nil
        }
    }
}
