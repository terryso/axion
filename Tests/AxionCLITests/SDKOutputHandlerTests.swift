import Foundation
import OpenAgentSDK
import XCTest
@testable import AxionCLI

// Tests for SDKTerminalOutputHandler and SDKJSONOutputHandler in RunCommand.swift.

final class SDKOutputHandlerTests: XCTestCase {

    // MARK: - SDKTerminalOutputHandler

    func test_terminalHandler_displayRunStart() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.displayRunStart(runId: "20260511-abc123", task: "Open Calculator")
        XCTAssertTrue(lines.contains(where: { $0.contains("20260511-abc123") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Open Calculator") }))
    }

    func test_terminalHandler_toolUse_printsExecution() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))
        XCTAssertTrue(lines.contains(where: { $0.contains("click") && $0.contains("执行") }))
    }

    func test_terminalHandler_toolResult_success() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "{\"success\":true}", isError: false)))
        XCTAssertTrue(lines.contains(where: { $0.contains("结果") }))
    }

    func test_terminalHandler_toolResult_error() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "fail", isError: true)))
        XCTAssertTrue(lines.contains(where: { $0.contains("错误") }))
    }

    func test_terminalHandler_toolResult_screenshot_summary() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "{\"action\":\"screenshot\",\"image_data\":\"...\"}", isError: false)))
        XCTAssertTrue(lines.contains(where: { $0.contains("[screenshot captured]") }))
    }

    func test_terminalHandler_result_success_withText() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .success, text: "All done", usage: nil, numTurns: 3, durationMs: 1000)))
        XCTAssertTrue(lines.contains(where: { $0.contains("完成") && $0.contains("All done") }))
    }

    func test_terminalHandler_result_success_emptyText() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 1, durationMs: 500)))
        XCTAssertFalse(lines.contains(where: { $0.contains("完成:") }))
    }

    func test_terminalHandler_result_maxTurns() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .errorMaxTurns, text: "", usage: nil, numTurns: 50, durationMs: 0)))
        XCTAssertTrue(lines.contains(where: { $0.contains("最大步数") }))
    }

    func test_terminalHandler_result_cancelled() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .cancelled, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(lines.contains(where: { $0.contains("取消") }))
    }

    func test_terminalHandler_result_errorDuringExecution() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .errorDuringExecution, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(lines.contains(where: { $0.contains("执行错误") }))
    }

    func test_terminalHandler_result_maxBudget() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .errorMaxBudgetUsd, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(lines.contains(where: { $0.contains("预算") }))
    }

    func test_terminalHandler_result_maxStructuredOutputRetries() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.result(.init(subtype: .errorMaxStructuredOutputRetries, text: "", usage: nil, numTurns: 0, durationMs: 0)))
        XCTAssertTrue(lines.contains(where: { $0.contains("结构化输出") }))
    }

    func test_terminalHandler_partialMessage_buffersUntilFlush() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.partialMessage(.init(text: "Hello ")))
        handler.handleMessage(.partialMessage(.init(text: "World")))
        // Nothing written yet — buffered
        XCTAssertEqual(lines.count, 0)

        // Flush triggered by toolUse
        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))

        // Should have buffered text + tool use line
        XCTAssertTrue(lines.contains(where: { $0.contains("Hello World") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("执行") }))
    }

    func test_terminalHandler_assistantText_whenNoBuffer() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.assistant(.init(text: "I will click the button", model: "m", stopReason: "r")))
        XCTAssertTrue(lines.contains(where: { $0.contains("click the button") }))
    }

    func test_terminalHandler_assistantText_flushesBuffer() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.partialMessage(.init(text: "Thinking")))
        handler.handleMessage(.assistant(.init(text: "Done thinking", model: "m", stopReason: "r")))

        // Buffer is flushed (contains "Thinking"), but "Done thinking" is NOT printed
        // because the handler only prints assistant text when streamBuffer was empty
        XCTAssertTrue(lines.contains(where: { $0.contains("Thinking") }))
    }

    func test_terminalHandler_assistantEmptyText_noOutput() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.assistant(.init(text: "", model: "m", stopReason: "r")))
        XCTAssertEqual(lines.count, 0)
    }

    func test_terminalHandler_displayCompletion_flushesAndWrites() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.partialMessage(.init(text: "Final")))
        handler.displayCompletion()

        XCTAssertTrue(lines.contains(where: { $0.contains("Final") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("运行结束") }))
    }

    func test_terminalHandler_unknownMessage_ignored() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.system(.init(subtype: .status, message: "sys")))
        XCTAssertEqual(lines.count, 0)
    }

    // MARK: - SDKJSONOutputHandler

    func test_jsonHandler_displayRunStart() {
        var output: String?
        let handler = SDKJSONOutputHandler(write: { output = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        // Should not write yet — accumulates
        XCTAssertNil(output)
    }

    func test_jsonHandler_toolUse_accumulates() {
        let handler = SDKJSONOutputHandler(write: { _ in })

        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))
        handler.handleMessage(.toolUse(.init(toolName: "type_text", toolUseId: "t2", input: "{}")))
        // No crash = passes
    }

    func test_jsonHandler_toolResult_error_accumulates() {
        let handler = SDKJSONOutputHandler(write: { _ in })
        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "fail", isError: true)))
    }

    func test_jsonHandler_result_storesData() {
        let handler = SDKJSONOutputHandler(write: { _ in })
        let resultData = SDKMessage.ResultData(subtype: .success, text: "Done", usage: nil, numTurns: 3, durationMs: 500)
        handler.handleMessage(.result(resultData))
    }

    func test_jsonHandler_completion_outputsJson() {
        var captured: String?
        let handler = SDKJSONOutputHandler(write: { captured = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))
        handler.displayCompletion()

        XCTAssertNotNil(captured)
        let json = try? JSONSerialization.jsonObject(with: captured!.data(using: .utf8)!) as? [String: Any]
        XCTAssertEqual(json?["runId"] as? String, "r1")
        XCTAssertEqual(json?["task"] as? String, "Open Calc")
        XCTAssertEqual(json?["status"] as? String, "success")
        XCTAssertNotNil(json?["steps"])
    }

    func test_jsonHandler_completion_withoutResult_outputsUnknown() {
        var captured: String?
        let handler = SDKJSONOutputHandler(write: { captured = $0 })

        handler.displayRunStart(runId: "r2", task: "Test")
        handler.displayCompletion()

        let json = try? JSONSerialization.jsonObject(with: captured!.data(using: .utf8)!) as? [String: Any]
        XCTAssertEqual(json?["status"] as? String, "unknown")
    }

    func test_jsonHandler_toolResult_notError_ignored() {
        let handler = SDKJSONOutputHandler(write: { _ in })
        handler.handleMessage(.toolResult(.init(toolUseId: "t1", content: "ok", isError: false)))
        // Non-error tool results are accumulated in steps via toolUse
    }

    func test_jsonHandler_partialMessage_ignored() {
        let handler = SDKJSONOutputHandler(write: { _ in })
        handler.handleMessage(.partialMessage(.init(text: "thinking")))
        // Should not crash
    }

    // MARK: - SDKTerminalOutputHandler — Paused Events

    func test_terminalHandler_systemPaused_displaysPausedReason() {
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

        XCTAssertTrue(lines.contains(where: { $0.contains("暂停") && $0.contains("无法找到目标按钮") }))
    }

    func test_terminalHandler_systemPausedTimeout_displaysTimeout() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output)

        handler.handleMessage(.system(.init(
            subtype: .pausedTimeout,
            message: "Pause timed out",
            sessionId: "s1",
            pausedData: SDKMessage.PausedData(reason: "test", canResume: false)
        )))

        XCTAssertTrue(lines.contains(where: { $0.contains("超时") }))
    }

    // MARK: - SDKJSONOutputHandler — Paused Events

    func test_jsonHandler_systemPaused_outputsEventJson() {
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

        XCTAssertEqual(jsonOutputs.count, 1)
        let json = try? JSONSerialization.jsonObject(with: jsonOutputs[0].data(using: .utf8)!) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "paused")
        XCTAssertEqual(json?["reason"] as? String, "无法继续")
        XCTAssertEqual(json?["sessionId"] as? String, "s1")
    }

    func test_jsonHandler_systemPausedTimeout_outputsEventJson() {
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

        XCTAssertEqual(jsonOutputs.count, 1)
        let json = try? JSONSerialization.jsonObject(with: jsonOutputs[0].data(using: .utf8)!) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "pausedTimeout")
        XCTAssertEqual(json?["reason"] as? String, "test")
        XCTAssertEqual(json?["sessionId"] as? String, "s1")
    }

    func test_jsonHandler_systemStatus_ignored() {
        var jsonOutputs: [String] = []
        let handler = SDKJSONOutputHandler(
            write: { _ in },
            writeEvent: { jsonOutputs.append($0) }
        )

        handler.handleMessage(.system(.init(subtype: .status, message: "ok")))
        XCTAssertEqual(jsonOutputs.count, 0)
    }
}
