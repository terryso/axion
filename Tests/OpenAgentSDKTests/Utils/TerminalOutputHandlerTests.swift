import XCTest
@testable import OpenAgentSDK

/// Thread-safe line collector for use with @Sendable closures.
private final class LineCollector: @unchecked Sendable {
    var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
}

final class TerminalOutputHandlerTests: XCTestCase {
    private func makeHandler() -> (TerminalOutputHandler, LineCollector) {
        let collector = LineCollector()
        let handler = TerminalOutputHandler(write: { collector.append($0) })
        return (handler, collector)
    }

    // MARK: - Step Counting

    func testStepCountingIncrementsOnToolUse() {
        let (handler, collector) = makeHandler()
        handler.handle(.toolUse(.init(toolName: "Read", toolUseId: "tu-1", input: "{}")))
        handler.handle(.toolUse(.init(toolName: "Write", toolUseId: "tu-2", input: "{}")))
        XCTAssertEqual(collector.lines, [
            "Step 1: Read — executing",
            "Step 2: Write — executing",
        ])
    }

    // MARK: - Streaming Buffer

    func testPartialMessageBufferingAndFlushOnToolUse() {
        let (handler, collector) = makeHandler()
        handler.handle(.partialMessage(.init(text: "Hello ")))
        handler.handle(.partialMessage(.init(text: "World")))
        XCTAssertTrue(collector.lines.isEmpty)

        handler.handle(.toolUse(.init(toolName: "Bash", toolUseId: "tu-1", input: "{}")))
        XCTAssertEqual(collector.lines.count, 2)
        XCTAssertEqual(collector.lines[0], "Assistant: Hello World")
        XCTAssertEqual(collector.lines[1], "Step 1: Bash — executing")
    }

    // MARK: - Result Formatting per Subtype

    func testResultSuccess() {
        let (handler, collector) = makeHandler()
        handler.displayRunStart(runId: "r1", task: "test")
        handler.handle(.toolUse(.init(toolName: "Read", toolUseId: "tu-1", input: "{}")))
        handler.handle(.result(.init(subtype: .success, text: "done", usage: nil, numTurns: 3, durationMs: 1500)))
        XCTAssertTrue(collector.lines[2].contains("Completed"))
        XCTAssertTrue(collector.lines[2].contains("1 steps"))
    }

    func testResultErrorMaxTurns() {
        let (handler, collector) = makeHandler()
        handler.handle(.result(.init(subtype: .errorMaxTurns, text: "", usage: nil, numTurns: 50, durationMs: 0)))
        XCTAssertTrue(collector.lines.first!.contains("Max turns reached"))
        XCTAssertTrue(collector.lines.first!.contains("50 turns"))
    }

    func testResultErrorMaxBudgetUsd() {
        let (handler, collector) = makeHandler()
        handler.handle(.result(.init(subtype: .errorMaxBudgetUsd, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(collector.lines.first!.contains("Budget limit exceeded"))
    }

    func testResultCancelled() {
        let (handler, collector) = makeHandler()
        handler.handle(.result(.init(subtype: .cancelled, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(collector.lines.first!.contains("Cancelled"))
    }

    func testResultErrorDuringExecution() {
        let (handler, collector) = makeHandler()
        handler.handle(.result(.init(subtype: .errorDuringExecution, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(collector.lines.first!.contains("Execution error"))
    }

    func testResultErrorMaxStructuredOutputRetries() {
        let (handler, collector) = makeHandler()
        handler.handle(.result(.init(subtype: .errorMaxStructuredOutputRetries, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(collector.lines.first!.contains("Structured output retries exceeded"))
    }

    func testResultErrorMaxModelCalls() {
        let (handler, collector) = makeHandler()
        handler.handle(.result(.init(subtype: .errorMaxModelCalls, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(collector.lines.first!.contains("Model call limit reached"))
    }

    // MARK: - Tool Result Handling

    func testToolResultErrorTruncation() {
        let (handler, collector) = makeHandler()
        let longError = String(repeating: "x", count: 200)
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: longError, isError: true)))
        XCTAssertTrue(collector.lines.first!.hasPrefix("Error: "))
        let errorContent = String(collector.lines.first!.dropFirst("Error: ".count))
        XCTAssertEqual(errorContent.count, 100)
    }

    func testToolResultSuccessSummarization() {
        let (handler, collector) = makeHandler()
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: "File contents here", isError: false)))
        XCTAssertTrue(collector.lines.first!.hasPrefix("Result: "))
        XCTAssertTrue(collector.lines.first!.contains("File contents here"))
    }

    func testToolResultBase64Detection() {
        let (handler, collector) = makeHandler()
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: "iVBORw0KGgo base64 encoded image data", isError: false)))
        XCTAssertTrue(collector.lines.first!.contains("[binary data]"))
    }

    // MARK: - System Paused

    func testSystemPausedDisplaysReason() {
        let (handler, collector) = makeHandler()
        handler.handle(.system(.init(
            subtype: .paused,
            message: "paused",
            pausedData: .init(reason: "Waiting for user input")
        )))
        XCTAssertTrue(collector.lines.first!.contains("Paused: Waiting for user input"))
    }

    func testSystemPausedTimeout() {
        let (handler, collector) = makeHandler()
        handler.handle(.system(.init(subtype: .pausedTimeout, message: "timeout")))
        XCTAssertTrue(collector.lines.first!.contains("Pause timeout"))
    }

    // MARK: - Assistant Message

    func testAssistantFlushesBufferAndOutputsText() {
        let (handler, collector) = makeHandler()
        handler.handle(.partialMessage(.init(text: "Thinking...")))
        handler.handle(.assistant(.init(text: "Final answer", model: "claude-3", stopReason: "end_turn")))
        XCTAssertEqual(collector.lines.count, 2)
        XCTAssertEqual(collector.lines[0], "Assistant: Thinking...")
        XCTAssertEqual(collector.lines[1], "Assistant: Final answer")
    }

    func testAssistantWithEmptyTextDoesNotOutput() {
        let (handler, collector) = makeHandler()
        handler.handle(.assistant(.init(text: "", model: "claude-3", stopReason: "end_turn")))
        XCTAssertTrue(collector.lines.isEmpty)
    }

    // MARK: - Elapsed Time

    func testElapsedTimeComputation() {
        let (handler, collector) = makeHandler()
        // Without displayRunStart, elapsed should be 0
        handler.handle(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(collector.lines.first!.contains("0s"))

        // With displayRunStart, elapsed is computed
        let (handler2, collector2) = makeHandler()
        handler2.displayRunStart(runId: "r1", task: "test")
        handler2.handle(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(collector2.lines[1].contains("0s"))
    }

    // MARK: - displayRunStart / displayCompletion

    func testDisplayRunStart() {
        let (handler, collector) = makeHandler()
        handler.displayRunStart(runId: "run-abc", task: "Do something")
        XCTAssertEqual(collector.lines.first!, "Run run-abc started: Do something")
    }

    func testDisplayCompletion() {
        let (handler, collector) = makeHandler()
        handler.displayRunStart(runId: "r1", task: "test")
        handler.handle(.toolUse(.init(toolName: "Read", toolUseId: "tu-1", input: "{}")))
        handler.displayCompletion()
        let last = collector.lines.last!
        XCTAssertTrue(last.contains("Run complete"))
        XCTAssertTrue(last.contains("1 steps"))
    }

    func testDisplayCompletionFlushesBuffer() {
        let (handler, collector) = makeHandler()
        handler.handle(.partialMessage(.init(text: "buffered text")))
        handler.displayCompletion()
        XCTAssertTrue(collector.lines.contains("Assistant: buffered text"))
    }

    // MARK: - Buffer Flush on All Structured Events (AC4)

    func testBufferFlushOnToolResult() {
        let (handler, collector) = makeHandler()
        handler.handle(.partialMessage(.init(text: "streaming...")))
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: "ok", isError: false)))
        XCTAssertEqual(collector.lines.count, 2)
        XCTAssertEqual(collector.lines[0], "Assistant: streaming...")
        XCTAssertTrue(collector.lines[1].hasPrefix("Result: "))
    }

    func testBufferFlushOnResult() {
        let (handler, collector) = makeHandler()
        handler.handle(.partialMessage(.init(text: "almost done")))
        handler.handle(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertEqual(collector.lines.count, 2)
        XCTAssertEqual(collector.lines[0], "Assistant: almost done")
        XCTAssertTrue(collector.lines[1].contains("Completed"))
    }

    func testBufferFlushOnSystemPaused() {
        let (handler, collector) = makeHandler()
        handler.handle(.partialMessage(.init(text: "before pause")))
        handler.handle(.system(.init(
            subtype: .paused,
            message: "paused",
            pausedData: .init(reason: "Approval needed")
        )))
        XCTAssertEqual(collector.lines.count, 2)
        XCTAssertEqual(collector.lines[0], "Assistant: before pause")
        XCTAssertTrue(collector.lines[1].contains("Paused: Approval needed"))
    }

    // MARK: - Success Result Truncation (AC2)

    func testSuccessResultTruncationAt120() {
        let (handler, collector) = makeHandler()
        let longContent = String(repeating: "a", count: 200)
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: longContent, isError: false)))
        let resultLine = collector.lines.first!
        XCTAssertTrue(resultLine.hasPrefix("Result: "))
        let content = String(resultLine.dropFirst("Result: ".count))
        XCTAssertEqual(content.count, 120)
    }

    // MARK: - System Paused Edge Cases

    func testSystemPausedWithoutPausedDataProducesNoOutput() {
        let (handler, collector) = makeHandler()
        handler.handle(.system(.init(
            subtype: .paused,
            message: "paused"
        )))
        XCTAssertTrue(collector.lines.isEmpty)
    }

    // MARK: - Full Lifecycle Integration Test

    func testFullLifecycleTerminalOutput() {
        let (handler, collector) = makeHandler()

        // Start run
        handler.displayRunStart(runId: "run-e2e", task: "Analyze codebase")

        // Streaming text
        handler.handle(.partialMessage(.init(text: "Let me ")))
        handler.handle(.partialMessage(.init(text: "think about this...")))

        // Tool use flushes buffer
        handler.handle(.toolUse(.init(toolName: "Read", toolUseId: "tu-1", input: "{\"path\":\"main.swift\"}")))

        // Tool result
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: "file contents", isError: false)))

        // Another tool use
        handler.handle(.toolUse(.init(toolName: "Bash", toolUseId: "tu-2", input: "{\"cmd\":\"ls\"}")))

        // Tool result with error
        handler.handle(.toolResult(.init(toolUseId: "tu-2", content: "command failed", isError: true)))

        // Streaming text before result
        handler.handle(.partialMessage(.init(text: "Here is my analysis")))

        // Final result
        handler.handle(.result(.init(subtype: .success, text: "Analysis complete", usage: nil, numTurns: 2, durationMs: 5000)))

        // Completion
        handler.displayCompletion()

        // Verify all lines
        XCTAssertTrue(collector.lines[0].contains("Run run-e2e started"))
        XCTAssertEqual(collector.lines[1], "Assistant: Let me think about this...")
        XCTAssertEqual(collector.lines[2], "Step 1: Read — executing")
        XCTAssertTrue(collector.lines[3].contains("Result: file contents"))
        XCTAssertEqual(collector.lines[4], "Step 2: Bash — executing")
        XCTAssertTrue(collector.lines[5].contains("Error: command failed"))
        XCTAssertEqual(collector.lines[6], "Assistant: Here is my analysis")
        XCTAssertTrue(collector.lines[7].contains("Completed"))
        XCTAssertTrue(collector.lines[7].contains("2 steps"))
        XCTAssertTrue(collector.lines[8].contains("Run complete"))
        XCTAssertTrue(collector.lines[8].contains("2 steps"))
    }
}
