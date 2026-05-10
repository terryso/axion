import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] Built-in condition evaluation
// [P1] Edge cases and multi-condition logic

// MARK: - StopConditionEvaluator ATDD Tests

/// ATDD red-phase tests for StopConditionEvaluator (Story 3-4 AC2).
/// Tests the local rule-matching evaluation of stop conditions against
/// AX tree text and executed step history.
///
/// TDD RED PHASE: These tests will not compile until StopConditionEvaluator and
/// StopEvaluationResult are implemented in Sources/AxionCLI/Verifier/StopConditionEvaluator.swift.
final class StopConditionEvaluatorTests: XCTestCase {

    // MARK: - P0 Type Existence

    func test_stopEvaluationResult_hasExpectedCases() {
        // StopEvaluationResult must have: .satisfied, .notSatisfied, .uncertain
        let satisfied = StopEvaluationResult.satisfied
        let notSatisfied = StopEvaluationResult.notSatisfied
        let uncertain = StopEvaluationResult.uncertain

        // Verify they are distinct
        XCTAssertNotEqual(satisfied, notSatisfied)
        XCTAssertNotEqual(satisfied, uncertain)
        XCTAssertNotEqual(notSatisfied, uncertain)
    }

    // MARK: - P0 textAppears (AC2)

    func test_evaluate_textAppears_textFoundInAxTree_returnsSatisfied() {
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
        XCTAssertEqual(result, .satisfied)
    }

    func test_evaluate_textAppears_textNotFound_returnsNotSatisfied() {
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
        XCTAssertEqual(result, .notSatisfied)
    }

    // MARK: - P1 textAppears edge cases

    func test_evaluate_textAppears_caseInsensitive() {
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
        XCTAssertEqual(result, .satisfied)
    }

    func test_evaluate_textAppears_nilAxTree_returnsUncertain() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .textAppears, value: "391")]
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        XCTAssertEqual(result, .uncertain)
    }

    // MARK: - P0 windowAppears (AC2)

    func test_evaluate_windowAppears_windowTitleFound_returnsSatisfied() {
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
        XCTAssertEqual(result, .satisfied)
    }

    func test_evaluate_windowAppears_windowNotFound_returnsNotSatisfied() {
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
        XCTAssertEqual(result, .notSatisfied)
    }

    func test_evaluate_windowAppears_nilAxTree_returnsUncertain() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .windowAppears, value: "Calculator")]
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        XCTAssertEqual(result, .uncertain)
    }

    // MARK: - P0 windowDisappears (AC2)

    func test_evaluate_windowDisappears_windowGone_returnsSatisfied() {
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
        XCTAssertEqual(result, .satisfied)
    }

    func test_evaluate_windowDisappears_windowStillPresent_returnsNotSatisfied() {
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
        XCTAssertEqual(result, .notSatisfied)
    }

    // MARK: - P0 maxStepsReached (AC2)

    func test_evaluate_maxStepsReached_stepsEqualMax_returnsSatisfied() {
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
        XCTAssertEqual(result, .satisfied)
    }

    func test_evaluate_maxStepsReached_stepsBelowMax_returnsNotSatisfied() {
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
        XCTAssertEqual(result, .notSatisfied)
    }

    // MARK: - P0 custom and fileExists (AC2)

    func test_evaluate_customType_returnsUncertain() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .custom, value: "Calculator displays the correct result")]
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: "{\"role\": \"AXWindow\"}",
            executedSteps: [],
            maxSteps: 20
        )
        XCTAssertEqual(result, .uncertain)
    }

    func test_evaluate_fileExists_returnsUncertain() {
        let evaluator = StopConditionEvaluator()
        let conditions = [StopCondition(type: .fileExists, value: "/tmp/output.txt")]
        let result = evaluator.evaluate(
            stopConditions: conditions,
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        XCTAssertEqual(result, .uncertain)
    }

    // MARK: - P1 Multi-Condition Logic

    func test_evaluate_emptyConditions_returnsSatisfied() {
        let evaluator = StopConditionEvaluator()
        let result = evaluator.evaluate(
            stopConditions: [],
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        XCTAssertEqual(result, .satisfied)
    }

    func test_evaluate_multipleConditions_allSatisfied_returnsSatisfied() {
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
        XCTAssertEqual(result, .satisfied)
    }

    func test_evaluate_multipleConditions_oneNotSatisfied_returnsNotSatisfied() {
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
        XCTAssertEqual(result, .notSatisfied)
    }

    // MARK: - P1 processExits

    func test_evaluate_processExits_processGone_returnsSatisfied() {
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
        XCTAssertEqual(result, .satisfied)
    }
}
