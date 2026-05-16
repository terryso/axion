import Foundation
import Testing
import AxionCore
@testable import AxionCLI

private final class LinesCollector {
    var lines: [String] = []
}

@Suite("TerminalOutputImplementation")
struct TerminalOutputImplementationTests {

    private func makeOutput() -> (TerminalOutput, LinesCollector) {
        let collector = LinesCollector()
        let output = TerminalOutput(write: { collector.lines.append($0) })
        return (output, collector)
    }

    private let sampleStep = ExecutedStep(
        stepIndex: 0, tool: "click", parameters: [:],
        result: "ok", success: true, timestamp: Date()
    )

    @Test("displayRunStart prints mode runId task")
    func displayRunStartPrintsModeRunIdTask() {
        let (output, collector) = makeOutput()
        output.displayRunStart(runId: "r1", task: "Open Calc", mode: "standard")
        #expect(collector.lines.contains(where: { $0.contains("standard") }))
        #expect(collector.lines.contains(where: { $0.contains("r1") }))
        #expect(collector.lines.contains(where: { $0.contains("Open Calc") }))
    }

    @Test("displayPlan prints step count")
    func displayPlanPrintsStepCount() {
        let (output, collector) = makeOutput()
        let plan = Plan(
            id: UUID(), task: "t",
            steps: [Step(index: 0, tool: "click", parameters: [:], purpose: "p", expectedChange: "e")],
            stopWhen: [], maxRetries: 3
        )
        output.displayPlan(plan)
        #expect(collector.lines.contains(where: { $0.contains("1") && $0.contains("步骤") }))
    }

    @Test("displayStepResult success")
    func displayStepResultSuccess() {
        let (output, collector) = makeOutput()
        output.displayPlan(Plan(id: UUID(), task: "t", steps: [
            Step(index: 0, tool: "click", parameters: [:], purpose: "p", expectedChange: "e")
        ], stopWhen: [], maxRetries: 3))
        output.displayStepResult(sampleStep)
        #expect(collector.lines.contains(where: { $0.contains("click") && $0.contains("ok") }))
    }

    @Test("displayStepResult failure")
    func displayStepResultFailure() {
        let (output, collector) = makeOutput()
        let failed = ExecutedStep(stepIndex: 0, tool: "click", parameters: [:], result: "error happened here", success: false, timestamp: Date())
        output.displayStepResult(failed)
        #expect(collector.lines.contains(where: { $0.contains("x") }))
    }

    @Test("displayStateChange planning")
    func displayStateChangePlanning() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .done, to: .planning)
        #expect(collector.lines.contains(where: { $0.contains("规划") }))
    }

    @Test("displayStateChange executing")
    func displayStateChangeExecuting() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .planning, to: .executing)
        #expect(collector.lines.contains(where: { $0.contains("执行") }))
    }

    @Test("displayStateChange verifying")
    func displayStateChangeVerifying() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .executing, to: .verifying)
        #expect(collector.lines.contains(where: { $0.contains("验证") }))
    }

    @Test("displayStateChange done")
    func displayStateChangeDone() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .verifying, to: .done)
        #expect(collector.lines.contains(where: { $0.contains("完成") }))
    }

    @Test("displayStateChange failed")
    func displayStateChangeFailed() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .executing, to: .failed)
        #expect(collector.lines.contains(where: { $0.contains("失败") }))
    }

    @Test("displayStateChange cancelled")
    func displayStateChangeCancelled() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .executing, to: .cancelled)
        #expect(collector.lines.contains(where: { $0.contains("取消") }))
    }

    @Test("displayError prints message")
    func displayErrorPrintsMessage() {
        let (output, collector) = makeOutput()
        output.displayError(.cancelled)
        #expect(collector.lines.contains(where: { $0.contains("错误") }))
    }

    @Test("displaySummary with steps")
    func displaySummaryWithSteps() {
        let (output, collector) = makeOutput()
        let ctx = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 1,
            executedSteps: [sampleStep], replanCount: 0, config: .default
        )
        output.displaySummary(context: ctx)
        #expect(collector.lines.contains(where: { $0.contains("1") && $0.contains("步") }))
    }

    @Test("displaySummary no steps")
    func displaySummaryNoSteps() {
        let (output, collector) = makeOutput()
        let ctx = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: .default
        )
        output.displaySummary(context: ctx)
        #expect(collector.lines.contains(where: { $0.contains("0") }))
    }

    @Test("displayReplan")
    func displayReplan() {
        let (output, collector) = makeOutput()
        output.displayReplan(attempt: 2, maxRetries: 3, reason: "Step failed")
        #expect(collector.lines.contains(where: { $0.contains("重规划") && $0.contains("2") }))
    }

    @Test("displayVerificationResult done")
    func displayVerificationResultDone() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.done(reason: "Complete"))
        #expect(collector.lines.contains(where: { $0.contains("验证") && $0.contains("Complete") }))
    }

    @Test("displayVerificationResult blocked")
    func displayVerificationResultBlocked() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.blocked(reason: "Stuck"))
        #expect(collector.lines.contains(where: { $0.contains("阻塞") }))
    }

    @Test("displayVerificationResult needsClarification")
    func displayVerificationResultNeedsClarification() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.needsClarification(reason: "Unclear"))
        #expect(collector.lines.contains(where: { $0.contains("说明") }))
    }

    @Test("displayVerificationResult done default reason")
    func displayVerificationResultDoneDefaultReason() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.done(reason: "任务完成"))
        #expect(collector.lines.contains(where: { $0.contains("验证") }))
    }

    @Test("displayVerificationResult blocked default reason")
    func displayVerificationResultBlockedDefaultReason() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.blocked(reason: "任务阻塞"))
        #expect(collector.lines.contains(where: { $0.contains("阻塞") }))
    }

    @Test("displayVerificationResult needsClarification default reason")
    func displayVerificationResultNeedsClarificationDefaultReason() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.needsClarification(reason: "需要说明"))
        #expect(collector.lines.contains(where: { $0.contains("说明") }))
    }

    @Test("writeStream does not crash")
    func writeStreamDoesNotCrash() {
        let output = TerminalOutput(write: { _ in })
        output.writeStream("hello")
    }

    @Test("endStream does not crash")
    func endStreamDoesNotCrash() {
        let output = TerminalOutput(write: { _ in })
        output.endStream()
    }
}

@Suite("JSONOutputImplementation")
struct JSONOutputImplementationTests {

    private func makeOutput() -> JSONOutput {
        JSONOutput()
    }

    @Test("displayRunStart stores data")
    func displayRunStartStoresData() {
        let output = makeOutput()
        output.displayRunStart(runId: "r1", task: "Open Calc", mode: "standard")
        let json = output.finalize()
        #expect(json.contains("r1"))
        #expect(json.contains("Open Calc"))
        #expect(json.contains("standard"))
    }

    @Test("displayStepResult accumulates")
    func displayStepResultAccumulates() {
        let output = makeOutput()
        let step = ExecutedStep(stepIndex: 0, tool: "click", parameters: [:], result: "ok", success: true, timestamp: Date())
        output.displayStepResult(step)
        let json = output.finalize()
        #expect(json.contains("click"))
    }

    @Test("displayStateChange accumulates")
    func displayStateChangeAccumulates() {
        let output = makeOutput()
        output.displayStateChange(from: .planning, to: .executing)
        let json = output.finalize()
        #expect(json.contains("planning"))
        #expect(json.contains("executing"))
    }

    @Test("displayError accumulates")
    func displayErrorAccumulates() {
        let output = makeOutput()
        output.displayError(.cancelled)
        let json = output.finalize()
        #expect(json.contains("cancelled"))
    }

    @Test("displayReplan accumulates")
    func displayReplanAccumulates() {
        let output = makeOutput()
        output.displayReplan(attempt: 1, maxRetries: 3, reason: "fail")
        let json = output.finalize()
        #expect(json.contains("fail"))
    }

    @Test("displayVerificationResult done")
    func displayVerificationResultDone() {
        let output = makeOutput()
        output.displayVerificationResult(.done(reason: "ok"))
        let json = output.finalize()
        #expect(json.contains("done"))
    }

    @Test("displayVerificationResult with reason")
    func displayVerificationResultWithReason() {
        let output = makeOutput()
        output.displayVerificationResult(.blocked(reason: "stuck"))
        let json = output.finalize()
        #expect(json.contains("stuck"))
    }

    @Test("displaySummary with steps")
    func displaySummaryWithSteps() {
        let output = makeOutput()
        let step = ExecutedStep(stepIndex: 0, tool: "click", parameters: [:], result: "ok", success: true, timestamp: Date())
        let ctx = RunContext(planId: UUID(), currentState: .done, currentStepIndex: 1, executedSteps: [step], replanCount: 2, config: .default)
        output.displaySummary(context: ctx)
        let json = output.finalize()
        #expect(json.contains("totalSteps"))
        #expect(json.contains("successfulSteps"))
        #expect(json.contains("replanCount"))
    }

    @Test("finalize without displaySummary computes default")
    func finalizeWithoutDisplaySummaryComputesDefault() {
        let output = makeOutput()
        output.displayRunStart(runId: "r1", task: "t", mode: "m")
        let step = ExecutedStep(stepIndex: 0, tool: "click", parameters: [:], result: "ok", success: true, timestamp: Date())
        output.displayStepResult(step)
        let json = output.finalize()
        #expect(json.contains("summary"))
    }

    @Test("displayPlan no op")
    func displayPlanNoOp() {
        let output = makeOutput()
        let plan = Plan(id: UUID(), task: "t", steps: [], stopWhen: [], maxRetries: 3)
        output.displayPlan(plan)
        let json = output.finalize()
        #expect(!json.contains("steps\":[]"))
    }
}
