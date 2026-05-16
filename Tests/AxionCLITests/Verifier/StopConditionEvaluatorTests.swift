import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

/// ATDD red-phase tests for StopConditionEvaluator (Story 3-4 AC2).
/// Tests the local rule-matching evaluation of stop conditions against
/// AX tree text and executed step history.
///
/// TDD RED PHASE: These tests will not compile until StopConditionEvaluator and
/// StopEvaluationResult are implemented in Sources/AxionCLI/Verifier/StopConditionEvaluator.swift.
@Suite("StopConditionEvaluator")
struct StopConditionEvaluatorTests {

    @Test("StopEvaluationResult has expected cases")
    func stopEvaluationResultHasExpectedCases() {
        let satisfied = StopEvaluationResult.satisfied
        let notSatisfied = StopEvaluationResult.notSatisfied
        let uncertain = StopEvaluationResult.uncertain

        #expect(satisfied != notSatisfied)
        #expect(satisfied != uncertain)
        #expect(notSatisfied != uncertain)
    }

    @Test("textAppears — text found in AX tree returns satisfied")
    func evaluateTextAppearsTextFoundInAxTreeReturnsSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .textAppears, value: "391")]
        let axTree = """
        {"role": "AXWindow", "children": [{"role": "AXStaticText", "value": "391"}]}
        """
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: axTree,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .satisfied)
    }

    @Test("textAppears — text not found returns notSatisfied")
    func evaluateTextAppearsTextNotFoundReturnsNotSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .textAppears, value: "999")]
        let axTree = """
        {"role": "AXWindow", "children": [{"role": "AXStaticText", "value": "391"}]}
        """
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: axTree,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .notSatisfied)
    }

    @Test("textAppears is case insensitive")
    func evaluateTextAppearsCaseInsensitive() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .textAppears, value: "calculator")]
        let axTree = """
        {"role": "AXWindow", "title": "Calculator", "children": []}
        """
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: axTree,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .satisfied)
    }

    @Test("textAppears with nil AX tree returns uncertain")
    func evaluateTextAppearsNilAxTreeReturnsUncertain() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .textAppears, value: "391")]
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .uncertain)
    }

    @Test("windowAppears — window title found returns satisfied")
    func evaluateWindowAppearsWindowTitleFoundReturnsSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .windowAppears, value: "Calculator")]
        let axTree = """
        {"role": "AXApplication", "children": [{"role": "AXWindow", "title": "Calculator"}]}
        """
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: axTree,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .satisfied)
    }

    @Test("windowAppears — window not found returns notSatisfied")
    func evaluateWindowAppearsWindowNotFoundReturnsNotSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .windowAppears, value: "TextEdit")]
        let axTree = """
        {"role": "AXApplication", "children": [{"role": "AXWindow", "title": "Calculator"}]}
        """
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: axTree,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .notSatisfied)
    }

    @Test("windowAppears with nil AX tree returns uncertain")
    func evaluateWindowAppearsNilAxTreeReturnsUncertain() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .windowAppears, value: "Calculator")]
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .uncertain)
    }

    @Test("windowDisappears — window gone returns satisfied")
    func evaluateWindowDisappearsWindowGoneReturnsSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .windowDisappears, value: "Dialog")]
        let axTree = """
        {"role": "AXApplication", "children": [{"role": "AXWindow", "title": "Calculator"}]}
        """
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: axTree,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .satisfied)
    }

    @Test("windowDisappears — window still present returns notSatisfied")
    func evaluateWindowDisappearsWindowStillPresentReturnsNotSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .windowDisappears, value: "Calculator")]
        let axTree = """
        {"role": "AXApplication", "children": [{"role": "AXWindow", "title": "Calculator"}]}
        """
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: axTree,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .notSatisfied)
    }

    @Test("maxStepsReached — steps equal max returns satisfied")
    func evaluateMaxStepsReachedStepsEqualMaxReturnsSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .maxStepsReached, value: nil)]
        let steps = (0..<20).map { i in
            ExecutedStep(
                stepIndex: i,
                tool: "click",
                parameters: [:],
                result: "{\"success\": true}",
                success: true,
                timestamp: Date()
            )
        }
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: nil,
            executedSteps: steps,
            maxSteps: 20
        )
        #expect(result == .satisfied)
    }

    @Test("maxStepsReached — steps below max returns notSatisfied")
    func evaluateMaxStepsReachedStepsBelowMaxReturnsNotSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .maxStepsReached, value: nil)]
        let steps = (0..<10).map { i in
            ExecutedStep(
                stepIndex: i,
                tool: "click",
                parameters: [:],
                result: "{\"success\": true}",
                success: true,
                timestamp: Date()
            )
        }
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: nil,
            executedSteps: steps,
            maxSteps: 20
        )
        #expect(result == .notSatisfied)
    }

    @Test("custom type returns uncertain")
    func evaluateCustomTypeReturnsUncertain() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .custom, value: "Calculator displays the correct result")]
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: "{\"role\": \"AXWindow\"}",
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .uncertain)
    }

    @Test("fileExists returns uncertain")
    func evaluateFileExistsReturnsUncertain() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .fileExists, value: "/tmp/output.txt")]
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .uncertain)
    }

    @Test("empty conditions returns satisfied")
    func evaluateEmptyConditionsReturnsSatisfied() {
        let evaluator = StopConditionEvaluator()
        let result = evaluator.evaluate(
            stopConditions: [],
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .satisfied)
    }

    @Test("multiple conditions all satisfied returns satisfied")
    func evaluateMultipleConditionsAllSatisfiedReturnsSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [
            StopCondition(type: .textAppears, value: "391"),
            StopCondition(type: .windowAppears, value: "Calculator")
        ]
        let axTree = """
        {"role": "AXApplication", "children": [
            {"role": "AXWindow", "title": "Calculator", "children": [
                {"role": "AXStaticText", "value": "391"}
            ]}
        ]}
        """
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: axTree,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .satisfied)
    }

    @Test("multiple conditions one not satisfied returns notSatisfied")
    func evaluateMultipleConditionsOneNotSatisfiedReturnsNotSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [
            StopCondition(type: .textAppears, value: "391"),
            StopCondition(type: .textAppears, value: "999")
        ]
        let axTree = """
        {"role": "AXWindow", "children": [{"role": "AXStaticText", "value": "391"}]}
        """
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: axTree,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .notSatisfied)
    }

    @Test("processExits — process gone returns satisfied")
    func evaluateProcessExitsProcessGoneReturnsSatisfied() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .processExits, value: "Calculator")]
        // Simulate: last list_apps result does not contain Calculator
        let steps = [
            ExecutedStep(
                stepIndex: 0,
                tool: "launch_app",
                parameters: ["app_name": .string("Calculator")],
                result: "{\"pid\": 1234, \"app_name\": \"Calculator\", \"status\": \"launched\"}",
                success: true,
                timestamp: Date()
            ),
            ExecutedStep(
                stepIndex: 1,
                tool: "quit_app",
                parameters: ["pid": .int(1234)],
                result: "{\"success\": true}",
                success: true,
                timestamp: Date()
            ),
            ExecutedStep(
                stepIndex: 2,
                tool: "list_apps",
                parameters: [:],
                result: "{\"apps\": [{\"pid\": 5678, \"app_name\": \"Finder\"}]}",
                success: true,
                timestamp: Date()
            )
        ]
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: nil,
            executedSteps: steps,
            maxSteps: 20
        )
        #expect(result == .satisfied)
    }
}
