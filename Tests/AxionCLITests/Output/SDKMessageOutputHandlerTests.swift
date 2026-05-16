import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

private func makeResult(subtype: SDKMessage.ResultData.Subtype, text: String = "", numTurns: Int = 0, durationMs: Int = 0) -> SDKMessage.ResultData {
    .init(subtype: subtype, text: text, usage: nil, numTurns: numTurns, durationMs: durationMs)
}

/// Collects output strings for test assertions.
private final class OutputCollector: @unchecked Sendable {
    var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
}

@Suite("SDKTerminalOutputHandler")
struct SDKTerminalOutputHandlerTests {

    private func makeHandler(collector: OutputCollector, mode: String = "standard") -> SDKTerminalOutputHandler {
        SDKTerminalOutputHandler(
            output: TerminalOutput(write: { collector.append($0) }),
            mode: mode
        )
    }

    // MARK: - Tool Use Message

    @Test("handleMessage toolUse writes tool name")
    func handleMessageToolUseWritesToolName() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.displayRunStart(runId: "test-123", task: "open calculator")
        handler.handleMessage(.toolUse(.init(
            toolName: "launch_app",
            toolUseId: "tu-1",
            input: "{\"app_name\":\"Calculator\"}"
        )))

        #expect(collector.lines.contains(where: { $0.contains("launch_app") }))
    }

    @Test("handleMessage toolResult success writes result snippet")
    func handleMessageToolResultSuccessWritesSnippet() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.toolResult(.init(
            toolUseId: "tu-1",
            content: "{\"pid\":12345,\"app_name\":\"Calculator\"}",
            isError: false
        )))

        #expect(collector.lines.contains(where: { $0.contains("Calculator") }))
    }

    @Test("handleMessage toolResult error writes error prefix")
    func handleMessageToolResultErrorWritesErrorPrefix() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.toolResult(.init(
            toolUseId: "tu-1",
            content: "App not found",
            isError: true
        )))

        #expect(collector.lines.contains(where: { $0.contains("错误") }))
    }

    // MARK: - Result Messages

    @Test("result success writes completion")
    func handleMessageResultSuccessWritesCompletion() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.result(makeResult(
            subtype: .success,
            text: "Task completed successfully",
            numTurns: 3,
            durationMs: 5000
        )))

        #expect(collector.lines.contains(where: { $0.contains("完成") }))
    }

    @Test("result cancelled writes cancellation")
    func handleMessageResultCancelledWritesCancellation() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.result(makeResult(subtype: .cancelled, numTurns: 2, durationMs: 3000)))

        #expect(collector.lines.contains(where: { $0.contains("取消") }))
    }

    @Test("result maxTurns writes limit message")
    func handleMessageResultMaxTurnsWritesLimitMessage() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.result(makeResult(subtype: .errorMaxTurns, numTurns: 20, durationMs: 30000)))

        #expect(collector.lines.contains(where: { $0.contains("20") }))
    }

    @Test("result budget exceeded writes budget message")
    func handleMessageResultBudgetExceededWritesBudgetMessage() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.result(makeResult(subtype: .errorMaxBudgetUsd, numTurns: 5, durationMs: 10000)))

        #expect(collector.lines.contains(where: { $0.contains("预算") }))
    }

    @Test("result errorDuringExecution writes error")
    func handleMessageResultErrorDuringExecution() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.result(makeResult(subtype: .errorDuringExecution, numTurns: 3, durationMs: 5000)))

        #expect(collector.lines.contains(where: { $0.contains("执行错误") }))
    }

    @Test("result structuredOutputRetries writes retry message")
    func handleMessageResultStructuredOutputRetries() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.result(makeResult(subtype: .errorMaxStructuredOutputRetries, numTurns: 1, durationMs: 1000)))

        #expect(collector.lines.contains(where: { $0.contains("结构化输出") }))
    }

    // MARK: - Fast Mode

    @Test("fast mode success writes fast mode completion")
    func fastModeSuccessWritesFastModeCompletion() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector, mode: "fast")
        handler.displayRunStart(runId: "test", task: "task")

        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "tu-1", input: "{}")))
        handler.handleMessage(.result(makeResult(subtype: .success, text: "done", numTurns: 2, durationMs: 1500)))

        #expect(collector.lines.contains(where: { $0.contains("Fast mode") }))
        #expect(collector.lines.contains(where: { $0.contains("--fast") }))
    }

    @Test("fast mode maxTurns suggests removing --fast")
    func fastModeMaxTurnsSuggestsRemovingFast() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector, mode: "fast")

        handler.handleMessage(.result(makeResult(subtype: .errorMaxTurns, numTurns: 5, durationMs: 3000)))

        #expect(collector.lines.contains(where: { $0.contains("--fast") }))
    }

    @Test("fast mode errorDuringExecution suggests removing --fast")
    func fastModeErrorSuggestsRemovingFast() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector, mode: "fast")

        handler.handleMessage(.result(makeResult(subtype: .errorDuringExecution, numTurns: 3, durationMs: 2000)))

        #expect(collector.lines.contains(where: { $0.contains("--fast") }))
    }

    // MARK: - Stream Buffering

    @Test("partialMessage is buffered and flushed on next structured message")
    func partialMessageBufferedAndFlushed() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.partialMessage(.init(text: "Thinking")))
        handler.handleMessage(.partialMessage(.init(text: " about task")))
        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "tu-1", input: "{}")))

        #expect(collector.lines.contains(where: { $0.contains("Thinking about task") }))
    }

    @Test("displayCompletion flushes buffer")
    func displayCompletionFlushesBuffer() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.partialMessage(.init(text: "Streaming text")))
        handler.displayCompletion()

        #expect(collector.lines.contains(where: { $0.contains("Streaming text") }))
        #expect(collector.lines.contains(where: { $0.contains("运行结束") }))
    }

    // MARK: - System Messages

    @Test("system paused displays takeover prompt")
    func systemPausedDisplaysTakeoverPrompt() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.system(.init(
            subtype: .paused,
            message: "需要手动操作",
            pausedData: .init(reason: "需要手动操作", canResume: true)
        )))

        #expect(collector.lines.contains(where: { $0.contains("暂停") }))
        #expect(collector.lines.contains(where: { $0.contains("手动操作") }))
    }

    @Test("system pausedTimeout displays timeout message")
    func systemPausedTimeoutDisplaysTimeout() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.system(.init(
            subtype: .pausedTimeout,
            message: "timeout"
        )))

        #expect(collector.lines.contains(where: { $0.contains("超时") }))
    }

    // MARK: - Screenshot Summarization

    @Test("screenshot results are summarized")
    func screenshotResultsAreSummarized() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.toolResult(.init(
            toolUseId: "tu-1",
            content: "{\"action\":\"screenshot\",\"image_data\":\"base64data...\"}",
            isError: false
        )))

        #expect(collector.lines.contains(where: { $0.contains("screenshot captured") }))
    }

    @Test("base64 results are summarized as screenshot")
    func base64ResultsAreSummarized() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.toolResult(.init(
            toolUseId: "tu-1",
            content: "Result with Base64 encoded image data here",
            isError: false
        )))

        #expect(collector.lines.contains(where: { $0.contains("screenshot captured") }))
    }

    // MARK: - Run Start

    @Test("displayRunStart writes run start message")
    func displayRunStartWritesMessage() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.displayRunStart(runId: "20240101-abcdef", task: "open calculator")

        #expect(collector.lines.contains(where: { $0.contains("20240101-abcdef") }))
    }

    // MARK: - Assistant Message

    @Test("assistant message with text writes it")
    func assistantMessageWritesText() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.assistant(.init(
            text: "I will open Calculator for you",
            model: "claude-sonnet-4-20250514",
            stopReason: "end_turn"
        )))

        #expect(collector.lines.contains(where: { $0.contains("Calculator") }))
    }

    @Test("assistant message flushes stream buffer (but does not write assistant text when buffer was flushed)")
    func assistantMessageFlushesStreamBuffer() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.partialMessage(.init(text: "partial text")))
        handler.handleMessage(.assistant(.init(text: "Real message", model: "model", stopReason: "end_turn")))

        #expect(collector.lines.contains(where: { $0.contains("partial text") }))
        // When buffer is flushed, assistant text is NOT written (else if branch)
    }

    @Test("assistant message without buffer writes text directly")
    func assistantMessageWithoutBufferWritesText() {
        let collector = OutputCollector()
        let handler = makeHandler(collector: collector)

        handler.handleMessage(.assistant(.init(text: "Direct message", model: "model", stopReason: "end_turn")))

        #expect(collector.lines.contains(where: { $0.contains("Direct message") }))
    }
}

@Suite("SDKJSONOutputHandler")
struct SDKJSONOutputHandlerTests {

    private func makeHandler(output: OutputCollector, events: OutputCollector, mode: String = "standard") -> SDKJSONOutputHandler {
        SDKJSONOutputHandler(
            mode: mode,
            write: { output.append($0) },
            writeEvent: { events.append($0) }
        )
    }

    @Test("toolUse appends step")
    func toolUseAppendsStep() {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events)

        handler.displayRunStart(runId: "test-123", task: "open calculator")
        handler.handleMessage(.toolUse(.init(toolName: "launch_app", toolUseId: "tu-1", input: "{}")))
        handler.displayCompletion()

        #expect(output.lines.count == 1)
        #expect(output.lines[0].contains("launch_app"))
        #expect(output.lines[0].contains("tu-1"))
    }

    @Test("toolResult error appends error entry")
    func toolResultErrorAppendsError() {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events)

        handler.displayRunStart(runId: "test-123", task: "open calculator")
        handler.handleMessage(.toolResult(.init(toolUseId: "tu-1", content: "App not found", isError: true)))
        handler.displayCompletion()

        #expect(output.lines[0].contains("App not found"))
    }

    @Test("result stores result data")
    func resultStoresResultData() {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events)

        handler.displayRunStart(runId: "test-123", task: "open calculator")
        handler.handleMessage(.result(makeResult(subtype: .success, text: "Done", numTurns: 3, durationMs: 5000)))
        handler.displayCompletion()

        #expect(output.lines[0].contains("success"))
        #expect(output.lines[0].contains("Done"))
    }

    @Test("no result sets unknown status")
    func noResultSetUnknownStatus() {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events)

        handler.displayRunStart(runId: "test-123", task: "open calculator")
        handler.displayCompletion()

        #expect(output.lines[0].contains("unknown"))
    }

    @Test("completion output is valid JSON with required fields")
    func completionOutputIsValidJSON() throws {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events)

        handler.displayRunStart(runId: "test-123", task: "open calc")
        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "tu-1", input: "{}")))
        handler.handleMessage(.result(makeResult(subtype: .success, text: "OK", numTurns: 1, durationMs: 1000)))
        handler.displayCompletion()

        let data = Data(output.lines[0].utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["runId"] as? String == "test-123")
        #expect(json?["task"] as? String == "open calc")
        #expect(json?["status"] as? String == "success")
        #expect(json?["mode"] as? String == "standard")
        #expect(json?["steps"] != nil)
    }

    @Test("system paused emits JSON event")
    func systemPausedEmitsJSONEvent() {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events)

        handler.handleMessage(.system(.init(
            subtype: .paused,
            message: "need action",
            pausedData: .init(reason: "Need manual action", canResume: true)
        )))

        #expect(events.lines.count == 1)
        #expect(events.lines[0].contains("paused"))
        #expect(events.lines[0].contains("Need manual action"))
        #expect(events.lines[0].contains("canResume"))
    }

    @Test("system pausedTimeout emits JSON event")
    func systemPausedTimeoutEmitsJSONEvent() {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events)

        handler.handleMessage(.system(.init(
            subtype: .pausedTimeout,
            message: "timeout",
            pausedData: .init(reason: "Timed out", canResume: false)
        )))

        #expect(events.lines.count == 1)
        #expect(events.lines[0].contains("pausedTimeout"))
    }

    @Test("fast mode sets mode field")
    func fastModeSetsModeField() {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events, mode: "fast")

        handler.displayRunStart(runId: "test", task: "task")
        handler.displayCompletion()

        #expect(output.lines[0].contains("fast"))
    }

    @Test("displayRunStart stores runId and task")
    func displayRunStartStoresIdAndTask() {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events)

        handler.displayRunStart(runId: "run-abc", task: "my task")
        handler.displayCompletion()

        #expect(output.lines[0].contains("run-abc"))
        #expect(output.lines[0].contains("my task"))
    }

    @Test("multiple tool uses tracked correctly")
    func multipleToolUsesTracked() throws {
        let output = OutputCollector()
        let events = OutputCollector()
        let handler = makeHandler(output: output, events: events)

        handler.displayRunStart(runId: "test", task: "task")
        handler.handleMessage(.toolUse(.init(toolName: "step1", toolUseId: "t1", input: "{}")))
        handler.handleMessage(.toolUse(.init(toolName: "step2", toolUseId: "t2", input: "{}")))
        handler.handleMessage(.toolUse(.init(toolName: "step3", toolUseId: "t3", input: "{}")))
        handler.displayCompletion()

        let data = Data(output.lines[0].utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let steps = json?["steps"] as? [[String: Any]]
        #expect(steps?.count == 3)
    }
}
