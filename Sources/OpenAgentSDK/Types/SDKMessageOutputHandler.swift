import Foundation

/// Protocol for handling SDK message streams during agent execution.
///
/// Implementations receive each ``SDKMessage`` event from the agent's streaming loop,
/// allowing apps to format output for different destinations (terminal, JSON, custom).
///
/// ```swift
/// struct MyHandler: SDKMessageOutputHandler {
///     func displayRunStart(runId: String, task: String) {
///         print("Starting: \(task)")
///     }
///     func handle(_ message: SDKMessage) {
///         switch message {
///         case .toolUse(let data): print("Tool: \(data.toolName)")
///         default: break
///         }
///     }
///     func displayCompletion() {
///         print("Done")
///     }
/// }
/// ```
public protocol SDKMessageOutputHandler: Sendable {
    /// Called at the start of a run with the run identifier and task description.
    func displayRunStart(runId: String, task: String)

    /// Process a single SDK message event.
    func handle(_ message: SDKMessage)

    /// Called at the end of a run after all messages have been processed.
    func displayCompletion()
}
