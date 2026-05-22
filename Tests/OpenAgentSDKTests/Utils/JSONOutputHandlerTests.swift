import XCTest
@testable import OpenAgentSDK

/// Thread-safe line collector for use with @Sendable closures.
private final class LineCollector: @unchecked Sendable {
    var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
}

final class JSONOutputHandlerTests: XCTestCase {
    private func makeHandler() -> (JSONOutputHandler, LineCollector, LineCollector) {
        let output = LineCollector()
        let events = LineCollector()
        let handler = JSONOutputHandler(
            write: { output.append($0) },
            writeEvent: { events.append($0) }
        )
        return (handler, output, events)
    }

    // MARK: - Tool Use → Steps

    func testToolUseAppendsToStepsArray() {
        let (handler, _, _) = makeHandler()
        handler.handle(.toolUse(.init(toolName: "Read", toolUseId: "tu-1", input: "{}")))
        handler.handle(.toolUse(.init(toolName: "Write", toolUseId: "tu-2", input: "{}")))

        let result = handler.finalize()
        let steps = result["steps"] as! [[String: Any]]
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0]["toolName"] as? String, "Read")
        XCTAssertEqual(steps[0]["toolUseId"] as? String, "tu-1")
        XCTAssertEqual(steps[1]["toolName"] as? String, "Write")
    }

    // MARK: - Tool Result Error → Errors

    func testToolResultErrorAppendsToErrorsArray() {
        let (handler, _, _) = makeHandler()
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: "Something went wrong", isError: true)))

        let result = handler.finalize()
        let errors = result["errors"] as! [[String: String]]
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0]["toolUseId"], "tu-1")
        XCTAssertEqual(errors[0]["message"], "Something went wrong")
    }

    func testToolResultSuccessNotAddedToErrors() {
        let (handler, _, _) = makeHandler()
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: "OK", isError: false)))

        let result = handler.finalize()
        let errors = result["errors"] as! [[String: String]]
        XCTAssertTrue(errors.isEmpty)
    }

    func testToolResultErrorTruncatedAt200() {
        let (handler, _, _) = makeHandler()
        let longError = String(repeating: "e", count: 300)
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: longError, isError: true)))

        let result = handler.finalize()
        let errors = result["errors"] as! [[String: String]]
        XCTAssertEqual(errors[0]["message"]?.count, 200)
    }

    // MARK: - Result → ResultData

    func testResultStoresResultData() {
        let (handler, _, _) = makeHandler()
        handler.handle(.result(.init(subtype: .success, text: "done", usage: nil, numTurns: 5, durationMs: 2500)))

        let result = handler.finalize()
        XCTAssertEqual(result["status"] as? String, "success")
        XCTAssertEqual(result["text"] as? String, "done")
        XCTAssertEqual(result["numTurns"] as? Int, 5)
        XCTAssertEqual(result["durationMs"] as? Int, 2500)
    }

    // MARK: - Finalize JSON Structure

    func testFinalizeProducesCorrectJSONStructure() {
        let (handler, _, _) = makeHandler()
        handler.displayRunStart(runId: "run-42", task: "Test task")
        handler.handle(.toolUse(.init(toolName: "Read", toolUseId: "tu-1", input: "{}")))
        handler.handle(.result(.init(subtype: .success, text: "done", usage: nil, numTurns: 1, durationMs: 100)))

        let result = handler.finalize()
        XCTAssertEqual(result["runId"] as? String, "run-42")
        XCTAssertEqual(result["task"] as? String, "Test task")
        XCTAssertEqual(result["status"] as? String, "success")
        XCTAssertEqual(result["text"] as? String, "done")
        XCTAssertEqual(result["numTurns"] as? Int, 1)
        XCTAssertEqual(result["durationMs"] as? Int, 100)
        XCTAssertEqual(result["mode"] as? String, "default")

        let steps = result["steps"] as! [[String: Any]]
        XCTAssertEqual(steps.count, 1)

        let errors = result["errors"] as! [[String: String]]
        XCTAssertTrue(errors.isEmpty)
    }

    func testFinalizeProducesValidJSON() {
        let (handler, output, _) = makeHandler()
        handler.displayRunStart(runId: "r1", task: "test")
        handler.handle(.toolUse(.init(toolName: "Bash", toolUseId: "tu-1", input: "{}")))
        handler.displayCompletion()

        XCTAssertEqual(output.lines.count, 1)
        let json = output.lines.first!
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["runId"] as? String, "r1")
    }

    // MARK: - Empty Run

    func testFinalizeWithEmptyRun() {
        let (handler, _, _) = makeHandler()
        let result = handler.finalize()

        XCTAssertEqual(result["status"] as? String, "unknown")
        XCTAssertEqual(result["runId"] as? String, "")
        XCTAssertEqual(result["task"] as? String, "")
        XCTAssertTrue((result["steps"] as! [[String: Any]]).isEmpty)
        XCTAssertTrue((result["errors"] as! [[String: String]]).isEmpty)
    }

    // MARK: - System Paused → JSON Event

    func testSystemPausedEmitsJSONEvent() {
        let (handler, _, events) = makeHandler()
        handler.handle(.system(.init(
            subtype: .paused,
            message: "paused",
            sessionId: "sess-1",
            pausedData: .init(reason: "Need approval")
        )))

        XCTAssertEqual(events.lines.count, 1)
        let data = events.lines.first!.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(parsed["type"] as? String, "paused")
        XCTAssertEqual(parsed["reason"] as? String, "Need approval")
        XCTAssertEqual(parsed["canResume"] as? Bool, true)
        XCTAssertEqual(parsed["sessionId"] as? String, "sess-1")
    }

    func testSystemPausedTimeoutEmitsJSONEvent() {
        let (handler, _, events) = makeHandler()
        handler.handle(.system(.init(
            subtype: .pausedTimeout,
            message: "timeout",
            sessionId: "sess-2",
            pausedData: .init(reason: "Timed out")
        )))

        XCTAssertEqual(events.lines.count, 1)
        let data = events.lines.first!.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(parsed["type"] as? String, "pausedTimeout")
        XCTAssertEqual(parsed["canResume"] as? Bool, false)
        XCTAssertEqual(parsed["sessionId"] as? String, "sess-2")
    }

    // MARK: - displayRunStart

    func testDisplayRunStartStoresRunIdAndTask() {
        let (handler, _, _) = makeHandler()
        handler.displayRunStart(runId: "run-99", task: "My task")
        let result = handler.finalize()
        XCTAssertEqual(result["runId"] as? String, "run-99")
        XCTAssertEqual(result["task"] as? String, "My task")
    }

    // MARK: - Non-error tool results ignored

    func testNonErrorToolResultNotAccumulated() {
        let (handler, _, _) = makeHandler()
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: "success data", isError: false)))

        let result = handler.finalize()
        let errors = result["errors"] as! [[String: String]]
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - Multiple Errors in Single Run

    func testMultipleErrorsInSingleRun() {
        let (handler, _, _) = makeHandler()
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: "Error A", isError: true)))
        handler.handle(.toolResult(.init(toolUseId: "tu-2", content: "Error B", isError: true)))
        handler.handle(.toolResult(.init(toolUseId: "tu-3", content: "OK", isError: false)))

        let result = handler.finalize()
        let errors = result["errors"] as! [[String: String]]
        XCTAssertEqual(errors.count, 2)
        XCTAssertEqual(errors[0]["toolUseId"], "tu-1")
        XCTAssertEqual(errors[0]["message"], "Error A")
        XCTAssertEqual(errors[1]["toolUseId"], "tu-2")
        XCTAssertEqual(errors[1]["message"], "Error B")
    }

    // MARK: - System Paused without PausedData

    func testSystemPausedWithoutPausedDataEmitsNoEvent() {
        let (handler, _, events) = makeHandler()
        handler.handle(.system(.init(
            subtype: .paused,
            message: "paused"
        )))
        XCTAssertTrue(events.lines.isEmpty)
    }

    // MARK: - Full Lifecycle Integration Test

    func testFullLifecycleJSONOutput() {
        let (handler, output, events) = makeHandler()

        // Start run
        handler.displayRunStart(runId: "run-e2e", task: "Analyze codebase")

        // Simulate tool use + result
        handler.handle(.toolUse(.init(toolName: "Read", toolUseId: "tu-1", input: "{}")))
        handler.handle(.toolResult(.init(toolUseId: "tu-1", content: "file contents", isError: false)))
        handler.handle(.toolUse(.init(toolName: "Bash", toolUseId: "tu-2", input: "{}")))
        handler.handle(.toolResult(.init(toolUseId: "tu-2", content: "command failed", isError: true)))

        // Pause event
        handler.handle(.system(.init(
            subtype: .paused,
            message: "paused",
            sessionId: "sess-1",
            pausedData: .init(reason: "Need approval")
        )))

        // Final result
        handler.handle(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 2, durationMs: 5000)))

        // Completion
        handler.displayCompletion()

        // Verify streaming event
        XCTAssertEqual(events.lines.count, 1)
        let eventData = events.lines.first!.data(using: .utf8)!
        let eventParsed = try! JSONSerialization.jsonObject(with: eventData) as! [String: Any]
        XCTAssertEqual(eventParsed["type"] as? String, "paused")

        // Verify final JSON
        XCTAssertEqual(output.lines.count, 1)
        let jsonData = output.lines.first!.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        XCTAssertEqual(parsed["runId"] as? String, "run-e2e")
        XCTAssertEqual(parsed["task"] as? String, "Analyze codebase")
        XCTAssertEqual(parsed["status"] as? String, "success")
        XCTAssertEqual(parsed["text"] as? String, "Done")
        XCTAssertEqual(parsed["numTurns"] as? Int, 2)
        XCTAssertEqual(parsed["durationMs"] as? Int, 5000)
        XCTAssertEqual(parsed["mode"] as? String, "default")

        let steps = parsed["steps"] as! [[String: Any]]
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0]["toolName"] as? String, "Read")
        XCTAssertEqual(steps[1]["toolName"] as? String, "Bash")

        let errors = parsed["errors"] as! [[String: String]]
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0]["toolUseId"], "tu-2")
    }

    // MARK: - displayCompletion with nil writeEvent

    func testDisplayCompletionWithNilWriteEventDoesNotCrash() {
        let output = LineCollector()
        let handler = JSONOutputHandler(write: { output.append($0) }, writeEvent: nil)
        handler.displayRunStart(runId: "r1", task: "test")
        handler.handle(.system(.init(
            subtype: .paused,
            message: "paused",
            pausedData: .init(reason: "Need approval")
        )))
        handler.handle(.result(.init(subtype: .success, text: "ok", usage: nil, numTurns: 1, durationMs: 100)))
        handler.displayCompletion()

        // Should have written the final JSON even though writeEvent is nil
        XCTAssertEqual(output.lines.count, 1)
        let parsed = try! JSONSerialization.jsonObject(with: output.lines.first!.data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(parsed["status"] as? String, "success")
    }
}
