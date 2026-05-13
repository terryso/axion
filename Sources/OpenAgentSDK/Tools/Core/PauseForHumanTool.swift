import Foundation

// MARK: - PauseResult

/// Result of a pause-for-human operation.
///
/// When the `pause_for_human` tool suspends execution, the agent eventually
/// resolves with one of these outcomes:
/// - ``resumed(context:)``: The human provided input and the agent continues.
/// - ``aborted``: The pause was cancelled (e.g., via ``Agent/interrupt()``).
/// - ``timedOut``: The pause exceeded the configured timeout.
public enum PauseResult: Sendable, Equatable {
    /// The human provided context and the agent should continue.
    case resumed(context: String)
    /// The pause was aborted (e.g., via interrupt()).
    case aborted
    /// The pause timed out.
    case timedOut
}

// MARK: - Pause Handler (module-level state)

/// Internal pause handler storage.
/// Set by the agent when it has an active stream/prompt session.
/// Uses `nonisolated(unsafe)` because access is serialized by the tool execution
/// lifecycle (handler set before agent loop, cleared after).
nonisolated(unsafe) private var _pauseHandler: (@Sendable (String) async -> PauseResult)?

/// Sets the pause handler for the pause_for_human tool.
///
/// Called by the agent when it starts a stream/prompt session.
/// The handler receives the reason string and returns the pause result.
///
/// - Parameter handler: A closure that takes a reason string and returns a ``PauseResult``.
public func setPauseHandler(
    _ handler: @Sendable @escaping (String) async -> PauseResult
) {
    _pauseHandler = handler
}

/// Clears the pause handler for the pause_for_human tool.
///
/// Called when the agent finishes a stream/prompt session.
public func clearPauseHandler() {
    _pauseHandler = nil
}

// MARK: - Input

/// Input type for the pause_for_human tool.
private struct PauseForHumanInput: Codable {
    let reason: String
}

// MARK: - Factory

/// Creates the pause_for_human tool for requesting human intervention during execution.
///
/// The pause_for_human tool allows an agent to pause its execution and request human
/// help when it cannot complete a task autonomously. Key behaviors:
///
/// - **Interactive mode**: When a pause handler is set (via `setPauseHandler`),
///   the tool suspends until the human provides input, aborts, or the pause times out.
/// - **Non-interactive mode**: When no handler is set, returns an informational
///   message indicating no handler is available, and the agent should continue autonomously.
/// - **Error handling**: Aborted and timed-out pauses return `isError: true`.
///
/// - Returns: A `ToolProtocol` instance for the pause_for_human tool.
public func createPauseForHumanTool() -> ToolProtocol {
    return defineTool(
        name: "pause_for_human",
        description:
            "Pause execution and request human intervention. " +
            "Use when you cannot complete the task autonomously and need a human to " +
            "perform an action (e.g., clicking a button, providing credentials, making a decision). " +
            "The human will be notified of the reason and can provide context when they resume.",
        inputSchema: [
            "type": "object",
            "properties": [
                "reason": [
                    "type": "string",
                    "description": "Why human help is needed. Be specific about what action the human should take."
                ]
            ],
            "required": ["reason"]
        ],
        isReadOnly: true
    ) { (input: PauseForHumanInput, context: ToolContext) async throws -> ToolExecuteResult in
        guard let handler = _pauseHandler else {
            // Non-interactive mode: no handler available
            return ToolExecuteResult(
                content: "[Non-interactive mode] Pause requested: \(input.reason). No handler available, continuing autonomously.",
                isError: false
            )
        }

        let result = await handler(input.reason)
        switch result {
        case .resumed(let context):
            return ToolExecuteResult(
                content: "Human completed: \(context)",
                isError: false
            )
        case .aborted:
            return ToolExecuteResult(
                content: "Agent was aborted while paused.",
                isError: true
            )
        case .timedOut:
            return ToolExecuteResult(
                content: "Pause timed out after configured duration.",
                isError: true
            )
        }
    }
}
