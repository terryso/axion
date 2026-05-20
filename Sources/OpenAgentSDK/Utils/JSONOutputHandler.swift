import Foundation

/// JSON output handler that accumulates SDK message data and produces structured JSON.
///
/// Collects tool usage steps, errors, and result data throughout the run. When
/// ``displayCompletion()`` is called, it serializes the accumulated state via
/// ``finalize()`` and passes the JSON string to the `write` closure.
/// Optionally emits streaming pause/timeout events as JSON lines via `writeEvent`.
///
/// ```swift
/// var jsonOutput = ""
/// let handler = JSONOutputHandler(write: { jsonOutput = $0 })
/// handler.displayRunStart(runId: "run-1", task: "Analyze data")
/// for await message in agent.stream("Analyze the data") {
///     handler.handle(message)
/// }
/// handler.displayCompletion()
/// // jsonOutput now contains the full JSON result
/// ```
public struct JSONOutputHandler: SDKMessageOutputHandler, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        var runId = ""
        var task = ""
        var steps: [[String: Any]] = []
        var errors: [[String: String]] = []
        var resultData: SDKMessage.ResultData?
    }

    private let state = State()
    private let write: @Sendable (String) -> Void
    private let writeEvent: (@Sendable (String) -> Void)?

    /// Creates a JSON output handler.
    ///
    /// - Parameters:
    ///   - write: Closure receiving the final JSON string when the run completes.
    ///   - writeEvent: Optional closure for streaming JSON events (pause/timeout).
    public init(
        write: @escaping @Sendable (String) -> Void,
        writeEvent: (@Sendable (String) -> Void)? = nil
    ) {
        self.write = write
        self.writeEvent = writeEvent
    }

    public func displayRunStart(runId: String, task: String) {
        state.runId = runId
        state.task = task
    }

    public func handle(_ message: SDKMessage) {
        switch message {
        case .toolUse(let data):
            state.steps.append([
                "toolName": data.toolName,
                "toolUseId": data.toolUseId,
            ])

        case .toolResult(let data):
            if data.isError {
                state.errors.append([
                    "toolUseId": data.toolUseId,
                    "message": String(data.content.prefix(200)),
                ])
            }

        case .result(let data):
            state.resultData = data

        case .system(let data):
            switch data.subtype {
            case .paused:
                if let pausedData = data.pausedData {
                    emitEvent([
                        "type": "paused",
                        "reason": pausedData.reason,
                        "canResume": pausedData.canResume,
                        "sessionId": data.sessionId ?? "",
                    ])
                }
            case .pausedTimeout:
                var event: [String: Any] = [
                    "type": "pausedTimeout",
                    "canResume": false,
                    "sessionId": data.sessionId ?? "",
                ]
                if let reason = data.pausedData?.reason {
                    event["reason"] = reason
                }
                emitEvent(event)
            default:
                break
            }

        default:
            break
        }
    }

    public func displayCompletion() {
        let json = finalize()
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted]),
           let string = String(data: data, encoding: .utf8)
        {
            write(string)
        }
    }

    /// Builds the accumulated state into a JSON-compatible dictionary.
    ///
    /// Returns a `[String: Any]` dictionary containing: runId, task, status, text,
    /// numTurns, durationMs, steps, errors, and mode.
    public func finalize() -> [String: Any] {
        var result: [String: Any] = [:]
        result["runId"] = state.runId
        result["task"] = state.task

        if let data = state.resultData {
            result["status"] = data.subtype.rawValue
            result["text"] = data.text
            result["numTurns"] = data.numTurns
            result["durationMs"] = data.durationMs
        } else {
            result["status"] = "unknown"
        }

        result["steps"] = state.steps
        result["errors"] = state.errors
        result["mode"] = "default"

        return result
    }

    private func emitEvent(_ event: [String: Any]) {
        guard let writeEvent else { return }
        if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8)
        {
            writeEvent(string)
        }
    }
}
