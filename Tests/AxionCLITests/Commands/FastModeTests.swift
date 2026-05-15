import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

@Suite("FastMode")
struct FastModeTests {

    // MARK: - Task 1: --fast Flag Registration (AC#1)

    @Test("fast flag exists in RunCommand")
    func fastFlagExistsInRunCommand() throws {
        let command = try RunCommand.parse(["test-task", "--fast"])
        #expect(command.fast)
    }

    @Test("fast flag defaults to false")
    func fastFlagDefaultsToFalse() throws {
        let command = try RunCommand.parse(["test-task"])
        #expect(!command.fast)
    }

    // MARK: - Task 2: Fast Mode System Prompt (AC#2)

    @Test("fast mode system prompt includes fast instructions")
    func buildFullSystemPromptFastModeIncludesFastInstructions() throws {
        let command = try RunCommand.parse(["test-task", "--fast"])
        let prompt = command.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            fast: true,
            dryrun: false,
            verbose: false
        )
        #expect(prompt.contains("FAST mode"))
        #expect(prompt.contains("1-3 steps max"))
        #expect(prompt.contains("Skip discovery steps"))
        #expect(prompt.contains("screenshot for verification"))
        #expect(prompt.contains("report failure immediately"))
    }

    @Test("fast mode system prompt appears before dryrun")
    func buildFullSystemPromptFastModeBeforeDryrun() throws {
        let command = try RunCommand.parse(["test-task", "--fast", "--dryrun"])
        let prompt = command.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            fast: true,
            dryrun: true,
            verbose: false
        )
        let fastRange = prompt.range(of: "FAST mode")!
        let dryrunRange = prompt.range(of: "DRYRUN mode")!
        #expect(fastRange.lowerBound < dryrunRange.lowerBound)
    }

    @Test("standard mode has no fast instructions")
    func buildFullSystemPromptStandardModeNoFastInstructions() throws {
        let command = try RunCommand.parse(["test-task"])
        let prompt = command.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            fast: false,
            dryrun: false,
            verbose: false
        )
        #expect(!prompt.contains("FAST mode"))
    }

    // MARK: - Task 3: AgentOptions Configuration (AC#3, #4, #6)

    @Test("computeEffectiveMaxSteps fast mode caps at 5")
    func computeEffectiveMaxStepsFastModeCapsAt5() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: true, maxSteps: nil, configMaxSteps: 20)
        #expect(result == 5)
    }

    @Test("computeEffectiveMaxSteps fast mode caps explicit value at 5")
    func computeEffectiveMaxStepsFastModeCapsExplicitValueAt5() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: true, maxSteps: 10, configMaxSteps: 20)
        #expect(result == 5)
    }

    @Test("computeEffectiveMaxSteps fast mode respects explicit below 5")
    func computeEffectiveMaxStepsFastModeRespectsExplicitBelow5() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: true, maxSteps: 3, configMaxSteps: 20)
        #expect(result == 3)
    }

    @Test("computeEffectiveMaxSteps standard mode uses config default")
    func computeEffectiveMaxStepsStandardModeUsesConfigDefault() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: false, maxSteps: nil, configMaxSteps: 20)
        #expect(result == 20)
    }

    @Test("computeEffectiveMaxSteps standard mode respects explicit override")
    func computeEffectiveMaxStepsStandardModeRespectsExplicitOverride() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: false, maxSteps: 30, configMaxSteps: 20)
        #expect(result == 30)
    }

    @Test("computeEffectiveMaxTokens fast mode")
    func computeEffectiveMaxTokensFastMode() {
        #expect(RunCommand.computeEffectiveMaxTokens(fast: true) == 2048)
    }

    @Test("computeEffectiveMaxTokens standard mode")
    func computeEffectiveMaxTokensStandardMode() {
        #expect(RunCommand.computeEffectiveMaxTokens(fast: false) == 4096)
    }

    // MARK: - Task 4-5: Output Handler Fast Mode (AC#5, #7)

    @Test("terminal handler fast mode success shows fast completion")
    func terminalHandlerFastModeSuccessShowsFastCompletion() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "fast")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")
        handler.handleMessage(.toolUse(.init(toolName: "launch_app", toolUseId: "t1", input: "{}")))
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))

        let combined = lines.joined(separator: "\n")
        #expect(combined.contains("Fast mode 完成"))
        #expect(combined.contains("1 步"))
        #expect(combined.contains("秒"))
    }

    @Test("terminal handler fast mode error max turns shows retry suggestion")
    func terminalHandlerFastModeErrorMaxTurnsShowsRetrySuggestion() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "fast")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")
        handler.handleMessage(.result(.init(subtype: .errorMaxTurns, text: "", usage: nil, numTurns: 5, durationMs: 0)))

        let combined = lines.joined(separator: "\n")
        #expect(combined.contains("最大步数"))
        #expect(combined.contains("去掉 --fast"))
    }

    @Test("terminal handler fast mode error during execution shows retry suggestion")
    func terminalHandlerFastModeErrorDuringExecutionShowsRetrySuggestion() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "fast")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")
        handler.handleMessage(.result(.init(subtype: .errorDuringExecution, text: "", usage: nil, numTurns: 0, durationMs: 0)))

        let combined = lines.joined(separator: "\n")
        #expect(combined.contains("执行错误"))
        #expect(combined.contains("去掉 --fast"))
    }

    @Test("terminal handler standard mode success no fast message")
    func terminalHandlerStandardModeSuccessNoFastMessage() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "standard")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))

        let combined = lines.joined(separator: "\n")
        #expect(!combined.contains("Fast mode 完成"))
    }

    @Test("terminal handler fast mode displayRunStart shows fast mode")
    func terminalHandlerFastModeDisplayRunStartShowsFastMode() {
        var lines: [String] = []
        let output = TerminalOutput(write: { lines.append($0) })
        let handler = SDKTerminalOutputHandler(output: output, mode: "fast")

        handler.displayRunStart(runId: "r1", task: "Open Calculator")

        let combined = lines.joined(separator: "\n")
        #expect(combined.contains("fast"))
    }

    // MARK: SDKJSONOutputHandler — Fast Mode (AC#7)

    @Test("JSON handler fast mode includes mode field")
    func jsonHandlerFastModeIncludesModeField() {
        var captured: String?
        let handler = SDKJSONOutputHandler(mode: "fast", write: { captured = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))
        handler.displayCompletion()

        #expect(captured != nil)
        let json = try? JSONSerialization.jsonObject(with: captured!.data(using: .utf8)!) as? [String: Any]
        #expect(json?["mode"] as? String == "fast")
    }

    @Test("JSON handler standard mode includes mode field")
    func jsonHandlerStandardModeIncludesModeField() {
        var captured: String?
        let handler = SDKJSONOutputHandler(mode: "standard", write: { captured = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        handler.displayCompletion()

        #expect(captured != nil)
        let json = try? JSONSerialization.jsonObject(with: captured!.data(using: .utf8)!) as? [String: Any]
        #expect(json?["mode"] as? String == "standard")
    }

    @Test("JSON handler fast mode preserves other fields")
    func jsonHandlerFastModePreservesOtherFields() {
        var captured: String?
        let handler = SDKJSONOutputHandler(mode: "fast", write: { captured = $0 })

        handler.displayRunStart(runId: "r1", task: "Open Calc")
        handler.handleMessage(.toolUse(.init(toolName: "click", toolUseId: "t1", input: "{}")))
        handler.handleMessage(.result(.init(subtype: .success, text: "Done", usage: nil, numTurns: 1, durationMs: 100)))
        handler.displayCompletion()

        #expect(captured != nil)
        let json = try? JSONSerialization.jsonObject(with: captured!.data(using: .utf8)!) as? [String: Any]
        #expect(json?["runId"] as? String == "r1")
        #expect(json?["task"] as? String == "Open Calc")
        #expect(json?["status"] as? String == "success")
        #expect(json?["numTurns"] as? Int == 1)
        #expect(json?["mode"] as? String == "fast")
        #expect(json?["steps"] != nil)
    }

    // MARK: - Task 6: Trace Recording (AC#8)

    @Test("trace mode fast value")
    func traceModeFastValue() {
        let mode = RunCommand.traceMode(fast: true, dryrun: false)
        #expect(mode == "fast")
    }

    @Test("trace mode fast with dryrun takes priority")
    func traceModeFastWithDryrunFastTakesPriority() {
        let mode = RunCommand.traceMode(fast: true, dryrun: true)
        #expect(mode == "fast")
    }

    @Test("trace mode standard value")
    func traceModeStandardValue() {
        let mode = RunCommand.traceMode(fast: false, dryrun: false)
        #expect(mode == "standard")
    }

    @Test("trace mode dryrun value")
    func traceModeDryrunValue() {
        let mode = RunCommand.traceMode(fast: false, dryrun: true)
        #expect(mode == "dryrun")
    }
}
