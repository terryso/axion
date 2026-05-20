import Foundation

/// Terminal-friendly output handler that formats SDK messages as human-readable text.
///
/// Buffers streaming text from `.partialMessage` events and flushes when a structured
/// event (`.toolUse`, `.toolResult`, `.result`, `.system`) arrives, preventing
/// interleaved output. Uses a `ContinuousClock` for monotonic elapsed time tracking.
///
/// ```swift
/// let handler = TerminalOutputHandler()
/// handler.displayRunStart(runId: "run-1", task: "Summarize docs")
/// for await message in agent.stream("Summarize the docs") {
///     handler.handle(message)
/// }
/// handler.displayCompletion()
/// ```
public struct TerminalOutputHandler: SDKMessageOutputHandler, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        var streamBuffer = ""
        var startTime: ContinuousClock.Instant?
        var totalSteps = 0
    }

    private let state = State()
    private let write: @Sendable (String) -> Void

    /// Creates a handler that writes lines via the given closure.
    ///
    /// - Parameter write: Receives each formatted output line. Defaults to stdout.
    public init(write: @escaping @Sendable (String) -> Void = { line in
        FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
    }) {
        self.write = write
    }

    public func displayRunStart(runId: String, task: String) {
        state.startTime = ContinuousClock.now
        write("Run \(runId) started: \(task)")
    }

    public func handle(_ message: SDKMessage) {
        switch message {
        case .assistant(let data):
            flushBuffer()
            if !data.text.isEmpty {
                write("Assistant: \(data.text)")
            }

        case .toolUse(let data):
            flushBuffer()
            state.totalSteps += 1
            write("Step \(state.totalSteps): \(data.toolName) — executing")

        case .toolResult(let data):
            flushBuffer()
            if data.isError {
                let truncated = String(data.content.prefix(100))
                write("Error: \(truncated)")
            } else {
                let summary = summarizeResult(data.content)
                write("Result: \(summary)")
            }

        case .result(let data):
            flushBuffer()
            let elapsed = computeElapsedSeconds()
            switch data.subtype {
            case .success:
                write("Completed: \(state.totalSteps) steps in \(elapsed)s")
            case .errorMaxTurns:
                write("Max turns reached (\(data.numTurns) turns). Consider increasing the limit.")
            case .errorMaxBudgetUsd:
                write("Budget limit exceeded")
            case .cancelled:
                write("Cancelled")
            case .errorDuringExecution:
                write("Execution error")
            case .errorMaxStructuredOutputRetries:
                write("Structured output retries exceeded")
            case .errorMaxModelCalls:
                write("Model call limit reached")
            }

        case .partialMessage(let data):
            state.streamBuffer += data.text

        case .system(let data):
            switch data.subtype {
            case .paused:
                flushBuffer()
                if let pausedData = data.pausedData {
                    write("Paused: \(pausedData.reason)")
                }
            case .pausedTimeout:
                flushBuffer()
                write("Pause timeout — run terminated")
            default:
                break
            }

        default:
            break
        }
    }

    public func displayCompletion() {
        flushBuffer()
        let elapsed = computeElapsedSeconds()
        write("Run complete. \(state.totalSteps) steps, \(elapsed)s elapsed.")
    }

    private func flushBuffer() {
        if !state.streamBuffer.isEmpty {
            write("Assistant: \(state.streamBuffer)")
            state.streamBuffer = ""
        }
    }

    private func summarizeResult(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("iVBOR") || trimmed.hasPrefix("/9j/") ||
            trimmed.hasPrefix("R0lGOD") || trimmed.hasPrefix("data:image") {
            return "[binary data]"
        }
        return String(content.prefix(120))
    }

    private func computeElapsedSeconds() -> Int {
        guard let startTime = state.startTime else { return 0 }
        let elapsed = ContinuousClock.now - startTime
        return Int(elapsed.components.seconds)
    }
}
