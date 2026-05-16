import Foundation
import Testing
@testable import AxionCLI
@testable import AxionCore

/// ATDD red-phase tests for TerminalOutput (Story 3-5 AC1-4).
/// Tests that TerminalOutput produces correctly formatted terminal output
/// via an injectable write closure (not direct print).
@Suite("TerminalOutput")
struct TerminalOutputTests {

    @Test("type exists")
    func terminalOutputTypeExists() {
        let _ = TerminalOutput.self
    }

    @Test("conforms to OutputProtocol")
    func terminalOutputConformsToOutputProtocol() {
        let output = TerminalOutput()
        let _: OutputProtocol = output
    }

    @Test("displayRunStart shows runId and task")
    func terminalOutputDisplayRunStartShowsRunIdAndTask() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let hasRunId = captured.contains { $0.contains("20260510-abc123") }
        #expect(hasRunId)

        let hasTask = captured.contains { $0.contains("Open Calculator") }
        #expect(hasTask)
    }

    @Test("displayRunStart outputs at least 3 lines")
    func terminalOutputDisplayRunStartAllThreeLines() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        #expect(captured.count >= 3)

        let hasMode = captured.contains { $0.contains("plan_execute") || $0.lowercased().contains("mode") || $0.contains("模式") }
        #expect(hasMode)
    }

    @Test("displayPlan shows step count")
    func terminalOutputDisplayPlanShowsStepCount() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let plan = Plan(
            id: UUID(),
            task: "test",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")], purpose: "Launch Calculator", expectedChange: "App opens"),
                Step(index: 1, tool: "click", parameters: ["x": .int(100), "y": .int(200)], purpose: "Click button", expectedChange: "Button pressed"),
                Step(index: 2, tool: "type_text", parameters: ["text": .string("17*23")], purpose: "Type expression", expectedChange: "Text entered")
            ],
            stopWhen: [],
            maxRetries: 3
        )
        output.displayPlan(plan)

        let combined = captured.joined(separator: "\n")
        #expect(combined.contains("3"))
    }

    @Test("displayStepResult success shows ok")
    func terminalOutputDisplayStepResultSuccessShowsOk() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let plan = Plan(
            id: UUID(), task: "test",
            steps: [Step(index: 0, tool: "launch_app", parameters: [:], purpose: "Launch", expectedChange: "none")],
            stopWhen: [], maxRetries: 3
        )
        output.displayPlan(plan)

        captured.removeAll()
        let step = ExecutedStep(
            stepIndex: 0, tool: "launch_app", parameters: [:],
            result: "{\"pid\": 1234}", success: true, timestamp: Date()
        )
        output.displayStepResult(step)

        let combined = captured.joined(separator: "\n")
        #expect(combined.contains("ok"))
    }

    @Test("displayStepResult failure shows error")
    func terminalOutputDisplayStepResultFailureShowsError() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let plan = Plan(
            id: UUID(), task: "test",
            steps: [Step(index: 0, tool: "launch_app", parameters: [:], purpose: "Launch", expectedChange: "none")],
            stopWhen: [], maxRetries: 3
        )
        output.displayPlan(plan)

        captured.removeAll()
        let step = ExecutedStep(
            stepIndex: 0, tool: "launch_app", parameters: [:],
            result: "App not found", success: false, timestamp: Date()
        )
        output.displayStepResult(step)

        let combined = captured.joined(separator: "\n")
        let hasFailureIndicator = combined.contains("x") || combined.lowercased().contains("fail") || combined.contains("App not found")
        #expect(hasFailureIndicator)
    }

    @Test("displayStepResult shows step index")
    func terminalOutputDisplayStepResultShowsStepIndex() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let plan = Plan(
            id: UUID(), task: "test",
            steps: [
                Step(index: 0, tool: "a", parameters: [:], purpose: "Step A", expectedChange: ""),
                Step(index: 1, tool: "b", parameters: [:], purpose: "Step B", expectedChange: ""),
                Step(index: 2, tool: "c", parameters: [:], purpose: "Step C", expectedChange: "")
            ],
            stopWhen: [], maxRetries: 3
        )
        output.displayPlan(plan)

        captured.removeAll()
        let step = ExecutedStep(
            stepIndex: 1, tool: "b", parameters: [:],
            result: "ok", success: true, timestamp: Date()
        )
        output.displayStepResult(step)

        let combined = captured.joined(separator: "\n")
        let hasStepInfo = combined.contains("2") || combined.contains("1/3") || combined.contains("2/3")
        #expect(hasStepInfo)
    }

    @Test("displayStateChange planning produces output")
    func terminalOutputDisplayStateChangePlanning() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayStateChange(from: .planning, to: .executing)

        let combined = captured.joined(separator: "\n")
        #expect(combined.count > 0)
    }

    @Test("displayStateChange executing produces output")
    func terminalOutputDisplayStateChangeExecuting() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayStateChange(from: .executing, to: .verifying)

        let combined = captured.joined(separator: "\n")
        #expect(combined.count > 0)
    }

    @Test("displayError shows user friendly message")
    func terminalOutputDisplayErrorShowsUserFriendlyMessage() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayError(.planningFailed(reason: "LLM timeout"))

        let combined = captured.joined(separator: "\n")
        #expect(combined.contains("LLM timeout") || combined.contains("Plan generation failed") || combined.contains("planning"))
    }

    @Test("displaySummary shows step count and duration")
    func terminalOutputDisplaySummaryShowsStepCountAndDuration() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let executedStep = ExecutedStep(
            stepIndex: 0, tool: "click", parameters: [:],
            result: "ok", success: true, timestamp: Date()
        )
        let context = RunContext(
            planId: UUID(),
            currentState: .done,
            currentStepIndex: 1,
            executedSteps: [executedStep],
            replanCount: 0,
            config: .default
        )
        output.displaySummary(context: context)

        let combined = captured.joined(separator: "\n")
        #expect(combined.contains("1") || combined.contains("步"))
    }

    @Test("displaySummary shows replan count")
    func terminalOutputDisplaySummaryShowsReplanCount() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let executedStep = ExecutedStep(
            stepIndex: 0, tool: "click", parameters: [:],
            result: "ok", success: true, timestamp: Date()
        )
        let context = RunContext(
            planId: UUID(),
            currentState: .done,
            currentStepIndex: 1,
            executedSteps: [executedStep],
            replanCount: 2,
            config: .default
        )
        output.displaySummary(context: context)

        let combined = captured.joined(separator: "\n")
        #expect(combined.contains("2") || combined.contains("replan") || combined.contains("重规划"))
    }

    @Test("displayReplan shows attempt info")
    func terminalOutputDisplayReplanShowsAttemptInfo() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayReplan(attempt: 2, maxRetries: 3, reason: "Step 1 failed")

        let combined = captured.joined(separator: "\n")
        let hasAttempt = combined.contains("2") || combined.contains("attempt")
        let hasReason = combined.contains("Step 1 failed")
        #expect(hasAttempt || hasReason)
    }

    @Test("displayVerificationResult done produces output")
    func terminalOutputDisplayVerificationResultDone() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let result = VerificationResult.done(reason: "All conditions met")
        output.displayVerificationResult(result)

        let combined = captured.joined(separator: "\n")
        #expect(combined.count > 0)
    }

    @Test("displayVerificationResult blocked produces output")
    func terminalOutputDisplayVerificationResultBlocked() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let result = VerificationResult.blocked(reason: "Element not found")
        output.displayVerificationResult(result)

        let combined = captured.joined(separator: "\n")
        #expect(combined.count > 0)
    }

    @Test("all outputs have [axion] prefix")
    func terminalOutputAllOutputsHaveAxionPrefix() {
        var allOutput: [String] = []
        let output = TerminalOutput { allOutput.append($0) }

        output.displayRunStart(runId: "test-id", task: "task", mode: "mode")

        let plan = Plan(id: UUID(), task: "t", steps: [
            Step(index: 0, tool: "click", parameters: [:], purpose: "p", expectedChange: "e")
        ], stopWhen: [], maxRetries: 3)
        output.displayPlan(plan)

        output.displayStepResult(ExecutedStep(
            stepIndex: 0, tool: "click", parameters: [:],
            result: "ok", success: true, timestamp: Date()
        ))
        output.displayStateChange(from: .planning, to: .executing)
        output.displayError(.cancelled)

        let context = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: .default
        )
        output.displaySummary(context: context)
        output.displayReplan(attempt: 1, maxRetries: 3, reason: "test")
        output.displayVerificationResult(.done())

        for line in allOutput where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            #expect(line.contains("[axion]"))
        }
    }

    @Test("no emoji in output")
    func terminalOutputNoEmojiInOutput() {
        var allOutput: [String] = []
        let output = TerminalOutput { allOutput.append($0) }

        output.displayRunStart(runId: "test-id", task: "task", mode: "mode")
        let plan = Plan(id: UUID(), task: "t", steps: [
            Step(index: 0, tool: "click", parameters: [:], purpose: "p", expectedChange: "e")
        ], stopWhen: [], maxRetries: 3)
        output.displayPlan(plan)
        output.displayStepResult(ExecutedStep(
            stepIndex: 0, tool: "click", parameters: [:],
            result: "ok", success: true, timestamp: Date()
        ))
        output.displayStateChange(from: .planning, to: .executing)
        output.displayError(.cancelled)
        let context = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: .default
        )
        output.displaySummary(context: context)

        let combined = allOutput.joined()
        let hasEmoji = combined.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (v >= 0x1F600 && v <= 0x1F64F) ||
                   (v >= 0x1F300 && v <= 0x1F5FF) ||
                   (v >= 0x1F680 && v <= 0x1F6FF) ||
                   (v >= 0x1F1E0 && v <= 0x1F1FF) ||
                   (v >= 0x2600 && v <= 0x26FF) ||
                   (v >= 0x2700 && v <= 0x27BF) ||
                   (v >= 0xFE00 && v <= 0xFE0F) ||
                   (v >= 0x1F900 && v <= 0x1F9FF) ||
                   (v >= 0x1FA00 && v <= 0x1FA6F) ||
                   (v >= 0x1FA70 && v <= 0x1FAFF) ||
                   (v >= 0x231A && v <= 0x231B) ||
                   (v >= 0x23E9 && v <= 0x23F3) ||
                   (v >= 0x23F8 && v <= 0x23FA) ||
                   (v >= 0x25AA && v <= 0x25AB) ||
                   (v >= 0x25B6 && v <= 0x25C0) ||
                   (v >= 0x25FB && v <= 0x25FE) ||
                   (v >= 0x2614 && v <= 0x2615) ||
                   (v >= 0x2648 && v <= 0x2653) ||
                   (v >= 0x267F && v <= 0x267F) ||
                   (v >= 0x2693 && v <= 0x2693) ||
                   (v >= 0x26A1 && v <= 0x26A1) ||
                   (v >= 0x26AA && v <= 0x26AB) ||
                   (v >= 0x26BD && v <= 0x26BE) ||
                   (v >= 0x26C4 && v <= 0x26C5) ||
                   (v >= 0x26CE && v <= 0x26CE) ||
                   (v >= 0x26D4 && v <= 0x26D4) ||
                   (v >= 0x26EA && v <= 0x26EA) ||
                   (v >= 0x26F2 && v <= 0x26F3) ||
                   (v >= 0x26F5 && v <= 0x26F5) ||
                   (v >= 0x26FA && v <= 0x26FA) ||
                   (v >= 0x26FD && v <= 0x26FD) ||
                   (v >= 0x2702 && v <= 0x2702) ||
                   (v >= 0x2705 && v <= 0x2705) ||
                   (v >= 0x2708 && v <= 0x270D) ||
                   (v >= 0x270F && v <= 0x270F) ||
                   (v >= 0x2712 && v <= 0x2712) ||
                   (v >= 0x2714 && v <= 0x2714) ||
                   (v >= 0x2716 && v <= 0x2716) ||
                   (v >= 0x271D && v <= 0x271D) ||
                   (v >= 0x2721 && v <= 0x2721) ||
                   (v >= 0x2728 && v <= 0x2728) ||
                   (v >= 0x2733 && v <= 0x2734) ||
                   (v >= 0x2744 && v <= 0x2744) ||
                   (v >= 0x2747 && v <= 0x2747) ||
                   (v >= 0x274C && v <= 0x274C) ||
                   (v >= 0x274E && v <= 0x274E) ||
                   (v >= 0x2753 && v <= 0x2755) ||
                   (v >= 0x2757 && v <= 0x2757) ||
                   (v >= 0x2763 && v <= 0x2764) ||
                   (v >= 0x2795 && v <= 0x2797) ||
                   (v >= 0x27A1 && v <= 0x27A1) ||
                   (v >= 0x27B0 && v <= 0x27B0) ||
                   (v >= 0x27BF && v <= 0x27BF) ||
                   (v >= 0x2934 && v <= 0x2935) ||
                   (v >= 0x2B05 && v <= 0x2B07) ||
                   (v >= 0x2B1B && v <= 0x2B1C) ||
                   (v >= 0x2B50 && v <= 0x2B50) ||
                   (v >= 0x2B55 && v <= 0x2B55) ||
                   (v >= 0x3030 && v <= 0x3030) ||
                   (v >= 0x303D && v <= 0x303D) ||
                   (v >= 0x3297 && v <= 0x3297) ||
                   (v >= 0x3299 && v <= 0x3299)
        }
        #expect(!hasEmoji)
    }
}
