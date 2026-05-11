import Foundation
import XCTest
import AxionCore
@testable import AxionCLI

// Tests for TerminalOutput and JSONOutput OutputProtocol implementations.

private final class LinesCollector {
    var lines: [String] = []
}

final class TerminalOutputImplementationTests: XCTestCase {

    private func makeOutput() -> (TerminalOutput, LinesCollector) {
        let collector = LinesCollector()
        let output = TerminalOutput(write: { collector.lines.append($0) })
        return (output, collector)
    }

    private let sampleStep = ExecutedStep(
        stepIndex: 0, tool: "click", parameters: [:],
        result: "ok", success: true, timestamp: Date()
    )

    // MARK: - displayRunStart

    func test_displayRunStart_printsModeRunIdTask() {
        let (output, collector) = makeOutput()
        output.displayRunStart(runId: "r1", task: "Open Calc", mode: "standard")
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("standard") }))
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("r1") }))
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("Open Calc") }))
    }

    // MARK: - displayPlan

    func test_displayPlan_printsStepCount() {
        let (output, collector) = makeOutput()
        let plan = Plan(
            id: UUID(), task: "t",
            steps: [Step(index: 0, tool: "click", parameters: [:], purpose: "p", expectedChange: "e")],
            stopWhen: [], maxRetries: 3
        )
        output.displayPlan(plan)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("1") && $0.contains("步骤") }))
    }

    // MARK: - displayStepResult

    func test_displayStepResult_success() {
        let (output, collector) = makeOutput()
        output.displayPlan(Plan(id: UUID(), task: "t", steps: [
            Step(index: 0, tool: "click", parameters: [:], purpose: "p", expectedChange: "e")
        ], stopWhen: [], maxRetries: 3))
        output.displayStepResult(sampleStep)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("click") && $0.contains("ok") }))
    }

    func test_displayStepResult_failure() {
        let (output, collector) = makeOutput()
        let failed = ExecutedStep(stepIndex: 0, tool: "click", parameters: [:], result: "error happened here", success: false, timestamp: Date())
        output.displayStepResult(failed)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("x") }))
    }

    // MARK: - displayStateChange

    func test_displayStateChange_planning() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .done, to: .planning)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("规划") }))
    }

    func test_displayStateChange_executing() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .planning, to: .executing)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("执行") }))
    }

    func test_displayStateChange_verifying() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .executing, to: .verifying)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("验证") }))
    }

    func test_displayStateChange_done() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .verifying, to: .done)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("完成") }))
    }

    func test_displayStateChange_failed() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .executing, to: .failed)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("失败") }))
    }

    func test_displayStateChange_cancelled() {
        let (output, collector) = makeOutput()
        output.displayStateChange(from: .executing, to: .cancelled)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("取消") }))
    }

    // MARK: - displayError

    func test_displayError_printsMessage() {
        let (output, collector) = makeOutput()
        output.displayError(.cancelled)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("错误") }))
    }

    // MARK: - displaySummary

    func test_displaySummary_withSteps() {
        let (output, collector) = makeOutput()
        let ctx = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 1,
            executedSteps: [sampleStep], replanCount: 0, config: .default
        )
        output.displaySummary(context: ctx)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("1") && $0.contains("步") }))
    }

    func test_displaySummary_noSteps() {
        let (output, collector) = makeOutput()
        let ctx = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: .default
        )
        output.displaySummary(context: ctx)
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("0") }))
    }

    // MARK: - displayReplan

    func test_displayReplan() {
        let (output, collector) = makeOutput()
        output.displayReplan(attempt: 2, maxRetries: 3, reason: "Step failed")
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("重规划") && $0.contains("2") }))
    }

    // MARK: - displayVerificationResult

    func test_displayVerificationResult_done() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.done(reason: "Complete"))
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("验证") && $0.contains("Complete") }))
    }

    func test_displayVerificationResult_blocked() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.blocked(reason: "Stuck"))
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("阻塞") }))
    }

    func test_displayVerificationResult_needsClarification() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.needsClarification(reason: "Unclear"))
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("说明") }))
    }

    func test_displayVerificationResult_done_defaultReason() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.done(reason: "任务完成"))
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("验证") }))
    }

    func test_displayVerificationResult_blocked_defaultReason() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.blocked(reason: "任务阻塞"))
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("阻塞") }))
    }

    func test_displayVerificationResult_needsClarification_defaultReason() {
        let (output, collector) = makeOutput()
        output.displayVerificationResult(.needsClarification(reason: "需要说明"))
        XCTAssertTrue(collector.lines.contains(where: { $0.contains("说明") }))
    }

    // MARK: - writeStream / endStream

    func test_writeStream_doesNotCrash() {
        let output = TerminalOutput(write: { _ in })
        output.writeStream("hello")
    }

    func test_endStream_doesNotCrash() {
        let output = TerminalOutput(write: { _ in })
        output.endStream()
    }
}

// MARK: - JSONOutput Tests

final class JSONOutputImplementationTests: XCTestCase {

    private func makeOutput() -> JSONOutput {
        JSONOutput()
    }

    // MARK: - displayRunStart

    func test_displayRunStart_storesData() {
        let output = makeOutput()
        output.displayRunStart(runId: "r1", task: "Open Calc", mode: "standard")
        let json = output.finalize()
        XCTAssertTrue(json.contains("r1"))
        XCTAssertTrue(json.contains("Open Calc"))
        XCTAssertTrue(json.contains("standard"))
    }

    // MARK: - displayStepResult

    func test_displayStepResult_accumulates() {
        let output = makeOutput()
        let step = ExecutedStep(stepIndex: 0, tool: "click", parameters: [:], result: "ok", success: true, timestamp: Date())
        output.displayStepResult(step)
        let json = output.finalize()
        XCTAssertTrue(json.contains("click"))
    }

    // MARK: - displayStateChange

    func test_displayStateChange_accumulates() {
        let output = makeOutput()
        output.displayStateChange(from: .planning, to: .executing)
        let json = output.finalize()
        XCTAssertTrue(json.contains("planning"))
        XCTAssertTrue(json.contains("executing"))
    }

    // MARK: - displayError

    func test_displayError_accumulates() {
        let output = makeOutput()
        output.displayError(.cancelled)
        let json = output.finalize()
        XCTAssertTrue(json.contains("cancelled"))
    }

    // MARK: - displayReplan

    func test_displayReplan_accumulates() {
        let output = makeOutput()
        output.displayReplan(attempt: 1, maxRetries: 3, reason: "fail")
        let json = output.finalize()
        XCTAssertTrue(json.contains("fail"))
    }

    // MARK: - displayVerificationResult

    func test_displayVerificationResult_done() {
        let output = makeOutput()
        output.displayVerificationResult(.done(reason: "ok"))
        let json = output.finalize()
        XCTAssertTrue(json.contains("done"))
    }

    func test_displayVerificationResult_withReason() {
        let output = makeOutput()
        output.displayVerificationResult(.blocked(reason: "stuck"))
        let json = output.finalize()
        XCTAssertTrue(json.contains("stuck"))
    }

    // MARK: - displaySummary

    func test_displaySummary_withSteps() {
        let output = makeOutput()
        let step = ExecutedStep(stepIndex: 0, tool: "click", parameters: [:], result: "ok", success: true, timestamp: Date())
        let ctx = RunContext(planId: UUID(), currentState: .done, currentStepIndex: 1, executedSteps: [step], replanCount: 2, config: .default)
        output.displaySummary(context: ctx)
        let json = output.finalize()
        XCTAssertTrue(json.contains("totalSteps"))
        XCTAssertTrue(json.contains("successfulSteps"))
        XCTAssertTrue(json.contains("replanCount"))
    }

    // MARK: - finalize without summary

    func test_finalize_withoutDisplaySummary_computesDefault() {
        let output = makeOutput()
        output.displayRunStart(runId: "r1", task: "t", mode: "m")
        let step = ExecutedStep(stepIndex: 0, tool: "click", parameters: [:], result: "ok", success: true, timestamp: Date())
        output.displayStepResult(step)
        let json = output.finalize()
        XCTAssertTrue(json.contains("summary"))
    }

    // MARK: - displayPlan

    func test_displayPlan_noOp() {
        let output = makeOutput()
        let plan = Plan(id: UUID(), task: "t", steps: [], stopWhen: [], maxRetries: 3)
        output.displayPlan(plan)
        let json = output.finalize()
        // Plan does not add data to JSON output
        XCTAssertFalse(json.contains("steps\":[]"))
    }
}
