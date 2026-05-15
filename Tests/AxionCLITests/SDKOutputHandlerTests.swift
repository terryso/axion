import Foundation
import OpenAgentSDK
import Testing
@testable import AxionCLI

@Suite("SDKOutputHandler")
struct SDKOutputHandlerTests {

    @Test("terminal handler displayRunStart")
    func terminalHandlerDisplayRunStart() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.displayRunStart(runId: "20260511-abc123", task: "Open Calculator")
        #expect(lines.contains(where: { $0.contains("20260511-abc123") }))
        #expect(lines.contains(where: { $0.contains("Open Calculator") }))
    }

    @Test("terminal handler toolUse prints execution")
    func terminalHandlerToolUsePrintsExecution() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))
        #expect(lines.contains(where: { $0.contains("click") && $0.contains("执行") }))
    }

    @Test("terminal handler toolResult success")
    func terminalHandlerToolResultSuccess() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "{\"success\":true}", isError: false)))
        #expect(lines.contains(where: { $0.contains("结果") }))
    }

    @Test("terminal handler toolResult error")
    func terminalHandlerToolResultError() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "fail", isError: true)))
        #expect(lines.contains(where: { $0.contains("错误") }))
    }

    @Test("terminal handler toolResult screenshot summary")
    func terminalHandlerToolResultScreenshotSummary() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "{\"action\":\"screenshot\",\"image_data\":\"...\"}", isError: false)))
        #expect(lines.contains(where: { $0.contains("[screenshot captured]") }))
    }

    @Test("terminal handler result success with text")
    func terminalHandlerResultSuccessWithText() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .success, text: "All done", usage: nil, numTurns: 3, durationMs: 1000)))
        #expect(lines.contains(where: { $0.contains("完成") && $0.contains("All done") }))
    }

    @Test("terminal handler result success empty text")
    func terminalHandlerResultSuccessEmptyText() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 1, durationMs: 500)))
        #expect(!lines.contains(where: { $0.contains("完成:") }))
    }

    @Test("terminal handler result maxTurns")
    func terminalHandlerResultMaxTurns() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .errorMaxTurns, text: "", usage: nil, numTurns: 50, durationMs: 0)))
        #expect(lines.contains(where: { $0.contains("最大步数") }))
    }

    @Test("terminal handler result cancelled")
    func terminalHandlerResultCancelled() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .cancelled, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        #expect(lines.contains(where: { $0.contains("取消") }))
    }

    @Test("terminal handler result errorDuringExecution")
    func terminalHandlerResultErrorDuringExecution() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .errorDuringExecution, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        #expect(lines.contains(where: { $0.contains("执行错误") }))
    }

    @Test("terminal handler result maxBudget")
    func terminalHandlerResultMaxBudget() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .errorMaxBudgetUsd, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        #expect(lines.contains(where: { $0.contains("预算") }))
    }

    @Test("terminal handler result maxStructuredOutputRetries")
    func terminalHandlerResultMaxStructuredOutputRetries() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .errorMaxStructuredOutputRetries, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        #expect(lines.contains(where: { $0.contains("结构化输出") }))
    }

    @Test("terminal handler partialMessage buffers until flush")
    func terminalHandlerPartialMessageBuffersUntilFlush() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.partialMessage(.init(text: "Hello ")))
        handler.handleMessage(.partialMessage(.init(text: "World")))
        #expect(lines.count == 0)

        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))

        #expect(lines.contains(where: { $0.contains("Hello World") }))
        #expect(lines.contains(where: { $0.contains("执行") }))
    }

    @Test("terminal handler assistantText when no buffer")
    func terminalHandlerAssistantTextWhenNoBuffer() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.assistant(.init(text: "I will click the button", model: "m", stopReason: "r")))
        #expect(lines.contains(where: { $0.contains("click the button") }))
    }

    @Test("terminal handler assistantText flushes buffer")
    func terminalHandlerAssistantTextFlushesBuffer() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.partialMessage(.init(text: "Thinking")))
        handler.handleMessage(.assistant(.init(text: "Done thinking", model: "m", stopReason: "r")))

        #expect(lines.contains(where: { $0.contains("Thinking") }))
    }

    @Test("terminal handler assistantEmptyText no output")
    func terminalHandlerAssistantEmptyTextNoOutput() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.assistant(.init(text: "", model: "m", stopReason: "r")))
        #expect(lines.count == 0)
    }

    @Test("terminal handler displayCompletion flushes and writes")
    func terminalHandlerDisplayCompletionFlushesAndWrites() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.partialMessage(.init(text: "Final")))
        handler.displayCompletion()

        #expect(lines.contains(where: { $0.contains("Final") }))
        #expect(lines.contains(where: { $0.contains("运行结束") }))
    }

    @Test("terminal handler unknownMessage ignored")
    func terminalHandlerUnknownMessageIgnored() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.system(.init(subtype: .status, message: "sys")))
        #expect(lines.count == 0)
    }

    @Test("json handler displayRunStart")
    func jsonHandlerDisplayRunStart() {
        var output: String?
        let handler = SDKJSONOutputHandler(write: { output = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        #expect(output == nil)
    }

    @Test("json handler toolUse accumulates")
    func jsonHandlerToolUseAccumulates() {
        let handler = SDKJSONOutputHandler(write: { _ in })

        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))
        handler.handleMessage(.toolUse(.init(toolName: "type_text", toolUseId: "t2", input: "{}")))
    }

    @Test("json handler toolResult error accumulates")
    func jsonHandlerToolResultErrorAccumulates() {
        let handler = SDKJSONOutputHandler(write: { _ in })
        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "fail", isError: true)))
    }

    @Test("json handler result stores data")
    func jsonHandlerResultStoresData() {
        let handler = SDKJSONOutputHandler(write: { _ in })
        let resultData = SDKMessage.ResultData(subtype: .success, text: "Done", usage: nil, numTurns: 3, durationMs: 500)
        handler.handleMessage(.result(resultData))
    }

    @Test("json handler completion outputs JSON")
    func jsonHandlerCompletionOutputsJson() throws {
        var captured: String?
        let handler = SDKJSONOutputHandler(write: { captured = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))
        handler.displayCompletion()

        #expect(captured != nil)
        let capturedString = try #require(captured)
        let json = try JSONSerialization.jsonObject(with: capturedString.data(using: .utf8)!) as? [String: Any]
        #expect(json?["runId"] as? String == "r1")
        #expect(json?["task"] as? String == "Open Calc")
        #expect(json?["status"] as? String == "success")
        #expect(json?["steps"] != nil)
    }

    @Test("json handler completion without result outputs unknown")
    func jsonHandlerCompletionWithoutResultOutputsUnknown() throws {
        var captured: String?
        let handler = SDKJSONOutputHandler(write: { captured = $0 })

        handler.displayRunStart(runId: "r2", task: "Test")
        handler.displayCompletion()

        let capturedString = try #require(captured)
        let json = try JSONSerialization.jsonObject(with: capturedString.data(using: .utf8)!) as? [String: Any]
        #expect(json?["status"] as? String == "unknown")
    }

    @Test("json handler toolResult not error ignored")
    func jsonHandlerToolResultNotErrorIgnored() {
        let handler = SDKJSONOutputHandler(write: { _ in })
        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "ok", isError: false)))
    }

    @Test("json handler partialMessage ignored")
    func jsonHandlerPartialMessageIgnored() {
        let handler = SDKJSONOutputHandler(write: { _ in })
        handler.handleMessage(.partialMessage(.init(text: "thinking")))
    }

    @Test("terminal handler systemPaused displays paused reason")
    func terminalHandlerSystemPausedDisplaysPausedReason() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        let pausedData = SDKMessage.PausedData(reason: "无法找到目标按钮")
        handler.handleMessage(.system(.init(
            subtype: .paused,
            message: "Agent paused: 无法找到目标按钮",
            sessionId: "s1",
            pausedData: pausedData
        )))

        #expect(lines.contains(where: { $0.contains("暂停") && $0.contains("无法找到目标按钮") }))
    }

    @Test("terminal handler systemPausedTimeout displays timeout")
    func terminalHandlerSystemPausedTimeoutDisplaysTimeout() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.system(.init(
            subtype: .pausedTimeout,
            message: "Pause timed out",
            sessionId: "s1",
            pausedData: SDKMessage.PausedData(reason: "test", canResume: false)
        )))

        #expect(lines.contains(where: { $0.contains("超时") }))
    }

    @Test("json handler systemPaused outputs event JSON")
    func jsonHandlerSystemPausedOutputsEventJson() throws {
        var jsonOutputs: [String] = []
        let handler = SDKJSONOutputHandler(
            write: { _ in },
            writeEvent: { jsonOutputs.append($0) }
        )

        let pausedData = SDKMessage.PausedData(reason: "无法继续")
        handler.handleMessage(.system(.init(
            subtype: .paused,
            message: "Agent paused: 无法继续",
            sessionId: "s1",
            pausedData: pausedData
        )))

        #expect(jsonOutputs.count == 1)
        let json = try JSONSerialization.jsonObject(with: jsonOutputs[0].data(using: .utf8)!) as? [String: Any]
        #expect(json?["type"] as? String == "paused")
        #expect(json?["reason"] as? String == "无法继续")
        #expect(json?["sessionId"] as? String == "s1")
    }

    @Test("json handler systemPausedTimeout outputs event JSON")
    func jsonHandlerSystemPausedTimeoutOutputsEventJson() throws {
        var jsonOutputs: [String] = []
        let handler = SDKJSONOutputHandler(
            write: { _ in },
            writeEvent: { jsonOutputs.append($0) }
        )

        handler.handleMessage(.system(.init(
            subtype: .pausedTimeout,
            message: "Pause timed out",
            sessionId: "s1",
            pausedData: SDKMessage.PausedData(reason: "test", canResume: false)
        )))

        #expect(jsonOutputs.count == 1)
        let json = try JSONSerialization.jsonObject(with: jsonOutputs[0].data(using: .utf8)!) as? [String: Any]
        #expect(json?["type"] as? String == "pausedTimeout")
        #expect(json?["reason"] as? String == "test")
        #expect(json?["sessionId"] as? String == "s1")
    }

    @Test("json handler systemStatus ignored")
    func jsonHandlerSystemStatusIgnored() {
        var jsonOutputs: [String] = []
        let handler = SDKJSONOutputHandler(
            write: { _ in },
            writeEvent: { jsonOutputs.append($0) }
        )

        handler.handleMessage(.system(.init(subtype: .status, message: "ok")))
        #expect(jsonOutputs.count == 0)
    }
}
