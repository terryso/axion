import Foundation
import OpenAgentSDK
import XCTest

@testable import AxionCLI

/// Story 7.2: Tests for --fast mode in RunCommand.
final class FastModeTests: XCTestCase {

    // MARK: - Task 1: --fast Flag Registration (AC#1)

    func test_fastFlag_existsInRunCommand() throws {
        let command = try RunCommand.parse(["test-task", "--fast"])
        XCTAssertTrue(command.fast)
    }

    func test_fastFlag_defaultsToFalse() throws {
        let command = try RunCommand.parse(["test-task"])
        XCTAssertFalse(command.fast)
    }

    // MARK: - Task 2: Fast Mode System Prompt (AC#2)

    func test_buildFullSystemPrompt_fastMode_includesFastInstructions() throws {
        let command = try RunCommand.parse(["test-task", "--fast"])
        let prompt = command.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            fast: true,
            dryrun: false,
            verbose: false
        )
        XCTAssertTrue(prompt.contains("FAST mode"))
        XCTAssertTrue(prompt.contains("1-3 steps max"))
        XCTAssertTrue(prompt.contains("Skip discovery steps"))
        XCTAssertTrue(prompt.contains("screenshot for verification"))
        XCTAssertTrue(prompt.contains("report failure immediately"))
    }

    func test_buildFullSystemPrompt_fastMode_beforeDryrun() throws {
        let command = try RunCommand.parse(["test-task", "--fast", "--dryrun"])
        let prompt = command.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            fast: true,
            dryrun: true,
            verbose: false
        )
        let fastRange = prompt.range(of: "FAST mode")!
        let dryrunRange = prompt.range(of: "DRYRUN mode")!
        XCTAssertLessThan(fastRange.lowerBound, dryrunRange.lowerBound)
    }

    func test_buildFullSystemPrompt_standardMode_noFastInstructions() throws {
        let command = try RunCommand.parse(["test-task"])
        let prompt = command.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            fast: false,
            dryrun: false,
            verbose: false
        )
        XCTAssertFalse(prompt.contains("FAST mode"))
    }

    // MARK: - Task 3: AgentOptions Configuration (AC#3, #4, #6)

    func test_computeEffectiveMaxSteps_fastMode_capsAt5() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: true, maxSteps: nil, configMaxSteps: 20)
        XCTAssertEqual(result, 5)
    }

    func test_computeEffectiveMaxSteps_fastMode_capsExplicitValueAt5() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: true, maxSteps: 10, configMaxSteps: 20)
        XCTAssertEqual(result, 5)
    }

    func test_computeEffectiveMaxSteps_fastMode_respectsExplicitBelow5() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: true, maxSteps: 3, configMaxSteps: 20)
        XCTAssertEqual(result, 3)
    }

    func test_computeEffectiveMaxSteps_standardMode_usesConfigDefault() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: false, maxSteps: nil, configMaxSteps: 20)
        XCTAssertEqual(result, 20)
    }

    func test_computeEffectiveMaxSteps_standardMode_respectsExplicitOverride() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: false, maxSteps: 30, configMaxSteps: 20)
        XCTAssertEqual(result, 30)
    }

    func test_computeEffectiveMaxTokens_fastMode() {
        XCTAssertEqual(RunCommand.computeEffectiveMaxTokens(fast: true), 2048)
    }

    func test_computeEffectiveMaxTokens_standardMode() {
        XCTAssertEqual(RunCommand.computeEffectiveMaxTokens(fast: false), 4096)
    }

    // MARK: - Task 4-5: Output Handler Fast Mode (AC#5, #7)

    func test_terminalHandler_fastMode_successShowsFastCompletion() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "fast")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")
        handler.handleMessage(.toolUse(.init(toolName: "launch_app", toolUseId: "t1", input: "{}")))
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))

        let combined = lines.joined(separator: "\n")
        XCTAssertTrue(combined.contains("Fast mode 完成"))
        XCTAssertTrue(combined.contains("1 步"))
        XCTAssertTrue(combined.contains("秒"))
    }

    func test_terminalHandler_fastMode_errorMaxTurnsShowsRetrySuggestion() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "fast")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")
        handler.handleMessage(.result(.init(subtype: .errorMaxTurns, text: "", usage: nil, numTurns: 5, durationMs: 0)))

        let combined = lines.joined(separator: "\n")
        XCTAssertTrue(combined.contains("最大步数"))
        XCTAssertTrue(combined.contains("去掉 --fast"))
    }

    func test_terminalHandler_fastMode_errorDuringExecutionShowsRetrySuggestion() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "fast")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")
        handler.handleMessage(.result(.init(subtype: .errorDuringExecution, text: "", usage: nil, numTurns: 0, durationMs: 0)))

        let combined = lines.joined(separator: "\n")
        XCTAssertTrue(combined.contains("执行错误"))
        XCTAssertTrue(combined.contains("去掉 --fast"))
    }

    func test_terminalHandler_standardMode_successNoFastMessage() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "standard")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))

        let combined = lines.joined(separator: "\n")
        XCTAssertFalse(combined.contains("Fast mode 完成"))
    }

    func test_terminalHandler_fastMode_displayRunStartShowsFastMode() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "fast")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")

        let combined = lines.joined(separator: "\n")
        XCTAssertTrue(combined.contains("fast"))
    }

    // MARK: SDKJSONOutputHandler — Fast Mode (AC#7)

    func test_jsonHandler_fastMode_includesModeField() {
        var captured: String?
        let handler = SDKJSONOutputHandler(mode: "fast", write: { captured = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))
        handler.displayCompletion()

        XCTAssertNotNil(captured)
        let json = try? JSONSerialization.jsonObject(with: captured!.data(using: .utf8)!) as? [String: Any]
        XCTAssertEqual(json?["mode"] as? String, "fast")
    }

    func test_jsonHandler_standardMode_includesModeField() {
        var captured: String?
        let handler = SDKJSONOutputHandler(mode: "standard", write: { captured = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        handler.displayCompletion()

        XCTAssertNotNil(captured)
        let json = try? JSONSerialization.jsonObject(with: captured!.data(using: .utf8)!) as? [String: Any]
        XCTAssertEqual(json?["mode"] as? String, "standard")
    }

    func test_jsonHandler_fastMode_preservesOtherFields() {
        var captured: String?
        let handler = SDKJSONOutputHandler(mode: "fast", write: { captured = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))
        handler.displayCompletion()

        XCTAssertNotNil(captured)
        let json = try? JSONSerialization.jsonObject(with: captured!.data(using: .utf8)!) as? [String: Any]
        XCTAssertEqual(json?["runId"] as? String, "r1")
        XCTAssertEqual(json?["task"] as? String, "Open Calc")
        XCTAssertEqual(json?["status"] as? String, "success")
        XCTAssertEqual(json?["numTurns"] as? Int, 1)
        XCTAssertEqual(json?["mode"] as? String, "fast")
        XCTAssertNotNil(json?["steps"])
    }

    // MARK: - Task 6: Trace Recording (AC#8)

    func test_traceMode_fastValue() {
        let mode = RunCommand.traceMode(fast: true, dryrun: false)
        XCTAssertEqual(mode, "fast")
    }

    func test_traceMode_fastWithDryrun_fastTakesPriority() {
        let mode = RunCommand.traceMode(fast: true, dryrun: true)
        XCTAssertEqual(mode, "fast")
    }

    func test_traceMode_standardValue() {
        let mode = RunCommand.traceMode(fast: false, dryrun: false)
        XCTAssertEqual(mode, "standard")
    }

    func test_traceMode_dryrunValue() {
        let mode = RunCommand.traceMode(fast: false, dryrun: true)
        XCTAssertEqual(mode, "dryrun")
    }
}
