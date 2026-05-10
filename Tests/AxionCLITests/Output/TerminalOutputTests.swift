import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] Core output format: [axion] prefix, step progress, summary
// [P1] State change text, replan info, verification display

// MARK: - TerminalOutput ATDD Tests

/// ATDD red-phase tests for TerminalOutput (Story 3-5 AC1-4).
/// Tests that TerminalOutput produces correctly formatted terminal output
/// via an injectable write closure (not direct print).
///
/// TDD RED PHASE: These tests will not compile until TerminalOutput is implemented
/// in Sources/AxionCLI/Output/TerminalOutput.swift.
final class TerminalOutputTests: XCTestCase {

    // MARK: - P0 Type Existence

    func test_terminalOutput_typeExists() {
        let _ = TerminalOutput.self
    }

    func test_terminalOutput_conformsToOutputProtocol() {
        // TerminalOutput must conform to OutputProtocol
        let output = TerminalOutput()
        let _: OutputProtocol = output
    }

    // MARK: - P0 AC1: Run Start Info Display

    func test_terminalOutput_displayRunStart_showsRunIdAndTask() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        // At least one line must contain the run ID
        let hasRunId = captured.contains { $0.contains("20260510-abc123") }
        XCTAssertTrue(hasRunId, "Expected run ID '20260510-abc123' in output: \(captured)")

        // At least one line must contain the task
        let hasTask = captured.contains { $0.contains("Open Calculator") }
        XCTAssertTrue(hasTask, "Expected task 'Open Calculator' in output: \(captured)")
    }

    func test_terminalOutput_displayRunStart_allThreeLines() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        // Should output at least 3 lines: mode, run ID, task
        XCTAssertGreaterThanOrEqual(captured.count, 3,
            "displayRunStart should output at least 3 lines, got \(captured.count): \(captured)")

        // One line should contain mode info
        let hasMode = captured.contains { $0.contains("plan_execute") || $0.lowercased().contains("mode") || $0.contains("模式") }
        XCTAssertTrue(hasMode, "Expected mode info in output: \(captured)")
    }

    // MARK: - P0 AC2: Step Execution Progress Display

    func test_terminalOutput_displayPlan_showsStepCount() {
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
        XCTAssertTrue(combined.contains("3"),
            "Expected step count '3' in plan output: \(captured)")
    }

    // MARK: - P0 AC3: Step Result Feedback

    func test_terminalOutput_displayStepResult_success_showsOk() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        // First display plan to set step count
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
        XCTAssertTrue(combined.contains("ok"),
            "Expected 'ok' status for successful step: \(captured)")
    }

    func test_terminalOutput_displayStepResult_failure_showsError() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        // First display plan to set step count
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
        // Failure should show "x" marker or error indication
        let hasFailureIndicator = combined.contains("x") || combined.lowercased().contains("fail") || combined.contains("App not found")
        XCTAssertTrue(hasFailureIndicator,
            "Expected failure indicator for failed step: \(captured)")
    }

    func test_terminalOutput_displayStepResult_showsStepIndex() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        // Create plan with 3 steps
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
        // Should show step 2 of 3 (1-indexed) or step index 1
        let hasStepInfo = combined.contains("2") || combined.contains("1/3") || combined.contains("2/3")
        XCTAssertTrue(hasStepInfo,
            "Expected step index info in output: \(captured)")
    }

    // MARK: - P1 AC4: State Change Display

    func test_terminalOutput_displayStateChange_planning() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayStateChange(from: .planning, to: .executing)

        let combined = captured.joined(separator: "\n")
        // Should indicate state transition to executing
        let hasTransition = combined.count > 0
        XCTAssertTrue(hasTransition,
            "Expected non-empty state change output for planning -> executing: \(captured)")
    }

    func test_terminalOutput_displayStateChange_executing() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayStateChange(from: .executing, to: .verifying)

        let combined = captured.joined(separator: "\n")
        XCTAssertTrue(combined.count > 0,
            "Expected non-empty state change output for executing -> verifying: \(captured)")
    }

    // MARK: - P0 AC3: Error Display

    func test_terminalOutput_displayError_showsUserFriendlyMessage() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayError(.planningFailed(reason: "LLM timeout"))

        let combined = captured.joined(separator: "\n")
        // Should contain the error message
        XCTAssertTrue(combined.contains("LLM timeout") || combined.contains("Plan generation failed") || combined.contains("planning"),
            "Expected error message in output: \(captured)")
    }

    // MARK: - P0 AC4: Task Completion Summary

    func test_terminalOutput_displaySummary_showsStepCountAndDuration() {
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
        // Should show step count
        XCTAssertTrue(combined.contains("1") || combined.contains("步"),
            "Expected step count in summary: \(captured)")
    }

    func test_terminalOutput_displaySummary_showsReplanCount() {
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
        // Should show replan count
        XCTAssertTrue(combined.contains("2") || combined.contains("replan") || combined.contains("重规划"),
            "Expected replan count in summary: \(captured)")
    }

    // MARK: - P1 AC4: Replan Display

    func test_terminalOutput_displayReplan_showsAttemptInfo() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayReplan(attempt: 2, maxRetries: 3, reason: "Step 1 failed")

        let combined = captured.joined(separator: "\n")
        // Should show attempt number and reason
        let hasAttempt = combined.contains("2") || combined.contains("attempt")
        let hasReason = combined.contains("Step 1 failed")
        XCTAssertTrue(hasAttempt || hasReason,
            "Expected attempt info and/or reason in replan output: \(captured)")
    }

    // MARK: - P1 AC4: Verification Result Display

    func test_terminalOutput_displayVerificationResult_done() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let result = VerificationResult.done(reason: "All conditions met")
        output.displayVerificationResult(result)

        let combined = captured.joined(separator: "\n")
        XCTAssertTrue(combined.count > 0,
            "Expected non-empty verification result output: \(captured)")
    }

    func test_terminalOutput_displayVerificationResult_blocked() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        let result = VerificationResult.blocked(reason: "Element not found")
        output.displayVerificationResult(result)

        let combined = captured.joined(separator: "\n")
        XCTAssertTrue(combined.count > 0,
            "Expected non-empty verification result output: \(captured)")
    }

    // MARK: - P0 [axion] Prefix Consistency

    func test_terminalOutput_allOutputs_haveAxionPrefix() {
        var allOutput: [String] = []
        let output = TerminalOutput { allOutput.append($0) }

        // Call every method
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

        // Every non-empty line should start with [axion]
        for line in allOutput where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            XCTAssertTrue(line.contains("[axion]"),
                "Output line missing [axion] prefix: '\(line)'")
        }
    }

    // MARK: - P1 No Emoji

    func test_terminalOutput_noEmojiInOutput() {
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
        // Check for emoji in output - should not contain emoji characters
        // Chinese/ASCII characters are fine, but emoji (Unicode scalar > 0x1F000) are not
        let hasEmoji = combined.unicodeScalars.contains { scalar in
            let v = scalar.value
            // Emoji ranges
            return (v >= 0x1F600 && v <= 0x1F64F) ||  // Emoticons
                   (v >= 0x1F300 && v <= 0x1F5FF) ||  // Misc Symbols and Pictographs
                   (v >= 0x1F680 && v <= 0x1F6FF) ||  // Transport and Map
                   (v >= 0x1F1E0 && v <= 0x1F1FF) ||  // Flags
                   (v >= 0x2600 && v <= 0x26FF) ||     // Misc symbols
                   (v >= 0x2700 && v <= 0x27BF) ||     // Dingbats
                   (v >= 0xFE00 && v <= 0xFE0F) ||     // Variation Selectors
                   (v >= 0x1F900 && v <= 0x1F9FF) ||   // Supplemental Symbols and Pictographs
                   (v >= 0x1FA00 && v <= 0x1FA6F) ||   // Chess Symbols
                   (v >= 0x1FA70 && v <= 0x1FAFF) ||   // Symbols and Pictographs Extended-A
                   (v >= 0x231A && v <= 0x231B) ||     // Watch, Hourglass
                   (v >= 0x23E9 && v <= 0x23F3) ||     // Media control
                   (v >= 0x23F8 && v <= 0x23FA) ||     // Media control
                   (v >= 0x25AA && v <= 0x25AB) ||     // Squares
                   (v >= 0x25B6 && v <= 0x25C0) ||     // Triangles
                   (v >= 0x25FB && v <= 0x25FE) ||     // Squares
                   (v >= 0x2614 && v <= 0x2615) ||     // Umbrella, hot beverage
                   (v >= 0x2648 && v <= 0x2653) ||     // Zodiac
                   (v >= 0x267F && v <= 0x267F) ||     // Wheelchair
                   (v >= 0x2693 && v <= 0x2693) ||     // Anchor
                   (v >= 0x26A1 && v <= 0x26A1) ||     // High voltage
                   (v >= 0x26AA && v <= 0x26AB) ||     // Circles
                   (v >= 0x26BD && v <= 0x26BE) ||     // Sports
                   (v >= 0x26C4 && v <= 0x26C5) ||     // Snowman, sun
                   (v >= 0x26CE && v <= 0x26CE) ||     // Ophiuchus
                   (v >= 0x26D4 && v <= 0x26D4) ||     // No entry
                   (v >= 0x26EA && v <= 0x26EA) ||     // Church
                   (v >= 0x26F2 && v <= 0x26F3) ||     // Fountain, golf
                   (v >= 0x26F5 && v <= 0x26F5) ||     // Sailboat
                   (v >= 0x26FA && v <= 0x26FA) ||     // Tent
                   (v >= 0x26FD && v <= 0x26FD) ||     // Fuel pump
                   (v >= 0x2702 && v <= 0x2702) ||     // Scissors
                   (v >= 0x2705 && v <= 0x2705) ||     // Check mark
                   (v >= 0x2708 && v <= 0x270D) ||     // Transport
                   (v >= 0x270F && v <= 0x270F) ||     // Pencil
                   (v >= 0x2712 && v <= 0x2712) ||     // Black nib
                   (v >= 0x2714 && v <= 0x2714) ||     // Check mark
                   (v >= 0x2716 && v <= 0x2716) ||     // X mark
                   (v >= 0x271D && v <= 0x271D) ||     // Cross
                   (v >= 0x2721 && v <= 0x2721) ||     // Star of David
                   (v >= 0x2728 && v <= 0x2728) ||     // Sparkles
                   (v >= 0x2733 && v <= 0x2734) ||     // Eight-pointed star
                   (v >= 0x2744 && v <= 0x2744) ||     // Snowflake
                   (v >= 0x2747 && v <= 0x2747) ||     // Sparkle
                   (v >= 0x274C && v <= 0x274C) ||     // Cross mark
                   (v >= 0x274E && v <= 0x274E) ||     // Cross mark
                   (v >= 0x2753 && v <= 0x2755) ||     // Question marks
                   (v >= 0x2757 && v <= 0x2757) ||     // Exclamation mark
                   (v >= 0x2763 && v <= 0x2764) ||     // Heart exclamation, heart
                   (v >= 0x2795 && v <= 0x2797) ||     // Math symbols
                   (v >= 0x27A1 && v <= 0x27A1) ||     // Right arrow
                   (v >= 0x27B0 && v <= 0x27B0) ||     // Curly loop
                   (v >= 0x27BF && v <= 0x27BF) ||     // Double curly loop
                   (v >= 0x2934 && v <= 0x2935) ||     // Arrows
                   (v >= 0x2B05 && v <= 0x2B07) ||     // Arrows
                   (v >= 0x2B1B && v <= 0x2B1C) ||     // Squares
                   (v >= 0x2B50 && v <= 0x2B50) ||     // Star
                   (v >= 0x2B55 && v <= 0x2B55) ||     // Circle
                   (v >= 0x3030 && v <= 0x3030) ||     // Wavy dash
                   (v >= 0x303D && v <= 0x303D) ||     // Part alternation mark
                   (v >= 0x3297 && v <= 0x3297) ||     // Circled ideograph congratulation
                   (v >= 0x3299 && v <= 0x3299)         // Circled ideograph secret
        }
        XCTAssertFalse(hasEmoji, "Output should not contain emoji or non-ASCII characters")
    }
}
