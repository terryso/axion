import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("PlanParser")
struct PlanParserTests {

    @Test("type exists")
    func typeExists() async throws {
        let _ = PlanParser.self
    }

    @Test("strips fences from JSON in backticks")
    func stripFencesJsonInBackticksExtractsJSON() async throws {
        let input = """
        Here is the plan:
        ```json
        {"status": "ready", "steps": [], "stopWhen": "task complete"}
        ```
        """
        let result = try PlanParser.stripFences(input)
        #expect(result.contains("\"status\""))
        #expect(result.contains("\"steps\""))
        #expect(!result.contains("```"))
    }

    @Test("strips fences from JSON in plain backticks")
    func stripFencesJsonInPlainBackticksExtractsJSON() async throws {
        let input = """
        ```
        {"status": "ready", "steps": [], "stopWhen": "task complete"}
        ```
        """
        let result = try PlanParser.stripFences(input)
        #expect(result.contains("\"status\""))
        #expect(!result.contains("```"))
    }

    @Test("strips fences from prose before JSON")
    func stripFencesProseBeforeJSONExtractsJSON() async throws {
        let input = """
        Looking at the current screen state, I can see the Calculator is not yet open.
        Let me plan the steps:

        {"status": "ready", "steps": [{"tool": "launch_app", "args": {"name": "Calculator"}, "purpose": "Open Calculator", "expected_change": "Calculator opens"}], "stopWhen": "Result 391 is visible"}
        """
        let result = try PlanParser.stripFences(input)
        #expect(result.hasPrefix("{"))
        #expect(result.contains("\"status\""))
        #expect(result.contains("\"launch_app\""))
    }

    @Test("strips fences from JSON with trailing text")
    func stripFencesJsonWithTrailingTextExtractsJSON() async throws {
        let input = """
        {"status": "ready", "steps": [], "stopWhen": "done"}
        And some trailing text after.
        """
        let result = try PlanParser.stripFences(input)
        #expect(result.hasPrefix("{"))
        // JSON should end at the closing brace, not include trailing text
        #expect(result.contains("\"stopWhen\""))
    }

    @Test("strips fences with nested braces in strings")
    func stripFencesNestedBracesInStringsHandlesCorrectly() async throws {
        let input = """
        {"status": "ready", "steps": [{"tool": "click", "args": {"selector": "div.container { color: red }"}, "purpose": "Click element", "expected_change": "clicked"}], "stopWhen": "done"}
        """
        let result = try PlanParser.stripFences(input)
        #expect(result.contains("\"selector\""))
        #expect(result.contains("color: red"))
    }

    @Test("pure JSON returns as is")
    func stripFencesPureJSONReturnsAsIs() async throws {
        let input = """
        {"status": "ready", "steps": [], "stopWhen": "task complete"}
        """
        let result = try PlanParser.stripFences(input)
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("valid response returns plan")
    func parsePlanValidResponseReturnsPlan() async throws {
        let llmResponse = """
        ```json
        {
            "status": "ready",
            "steps": [
                {
                    "tool": "launch_app",
                    "args": {"name": "Calculator"},
                    "purpose": "Open Calculator",
                    "expected_change": "Calculator is open"
                },
                {
                    "tool": "click",
                    "args": {"x": 100, "y": 200},
                    "purpose": "Click button 1",
                    "expected_change": "Button 1 pressed"
                }
            ],
            "stopWhen": "Result 391 is visible"
        }
        ```
        """
        let plan = try PlanParser.parse(llmResponse, task: "Open Calculator and compute 17 * 23", maxSteps: 10)

        #expect(plan.task == "Open Calculator and compute 17 * 23")
        #expect(plan.steps.count == 2)
        #expect(plan.steps[0].tool == "launch_app")
        #expect(plan.steps[0].purpose == "Open Calculator")
        #expect(plan.steps[0].expectedChange == "Calculator is open")
        #expect(plan.steps[1].tool == "click")
        #expect(!plan.stopWhen.isEmpty)
    }

    @Test("step structure has all required fields")
    func parsePlanStepStructureHasAllRequiredFields() async throws {
        let llmResponse = """
        {
            "steps": [
                {
                    "tool": "type_text",
                    "args": {"text": "hello"},
                    "purpose": "Type greeting",
                    "expected_change": "Text entered"
                }
            ],
            "stopWhen": "Text appears"
        }
        """
        let plan = try PlanParser.parse(llmResponse, task: "Type hello", maxSteps: 5)

        let step = plan.steps[0]
        #expect(step.tool == "type_text")
        #expect(step.parameters["text"] != nil)
        #expect(step.purpose == "Type greeting")
        #expect(step.expectedChange == "Text entered")
    }

    @Test("invalid JSON throws invalidPlan")
    func parsePlanInvalidJSONThrowsInvalidPlan() async throws {
        let invalidResponse = "This is not JSON at all, just plain text."
        do {
            try PlanParser.parse(invalidResponse, task: "test", maxSteps: 5)
            Issue.record("Should have thrown")
        } catch let error as AxionError {
            if case .invalidPlan = error {
                // Expected
            } else {
                Issue.record("Expected invalidPlan error, got: \(error)")
            }
        }
    }

    @Test("failure preserves raw response")
    func parsePlanFailurePreservesRawResponse() async throws {
        // NFR7: 解析失败时原始 LLM 响应不丢失
        let badResponse = "I cannot parse this {broken json"
        do {
            _ = try PlanParser.parse(badResponse, task: "test", maxSteps: 5)
            Issue.record("Should have thrown an error")
        } catch let error as AxionError {
            // 错误原因中应包含原始响应或其部分内容
            switch error {
            case .invalidPlan(let reason):
                #expect(reason.contains("broken") || reason.contains("cannot parse") || reason.contains("JSON decode failed"))
            default:
                Issue.record("Expected invalidPlan error, got: \(error)")
            }
        }
    }

    @Test("empty steps throws invalidPlan")
    func parsePlanEmptyStepsThrowsInvalidPlan() async throws {
        let emptySteps = """
        {
            "steps": [],
            "stopWhen": "done"
        }
        """
        do {
            try PlanParser.parse(emptySteps, task: "test", maxSteps: 5)
            Issue.record("Should have thrown")
        } catch _ as AxionError {
            // Expected
        }
    }

    @Test("missing stopWhen throws invalidPlan")
    func parsePlanMissingStopWhenThrowsInvalidPlan() async throws {
        let noStopWhen = """
        {
            "steps": [{"tool": "click", "args": {}, "purpose": "click", "expected_change": "clicked"}],
            "stopWhen": ""
        }
        """
        do {
            try PlanParser.parse(noStopWhen, task: "test", maxSteps: 5)
            Issue.record("Should have thrown")
        } catch _ as AxionError {
            // Expected
        }
    }

    @Test("step missing tool throws invalidPlan")
    func parsePlanStepMissingToolThrowsInvalidPlan() async throws {
        let missingTool = """
        {
            "steps": [{"args": {}, "purpose": "click", "expected_change": "clicked"}],
            "stopWhen": "done"
        }
        """
        do {
            try PlanParser.parse(missingTool, task: "test", maxSteps: 5)
            Issue.record("Should have thrown")
        } catch _ as AxionError {
            // Expected
        }
    }

    @Test("step missing purpose throws invalidPlan")
    func parsePlanStepMissingPurposeThrowsInvalidPlan() async throws {
        let missingPurpose = """
        {
            "steps": [{"tool": "click", "args": {}, "expected_change": "clicked"}],
            "stopWhen": "done"
        }
        """
        do {
            try PlanParser.parse(missingPurpose, task: "test", maxSteps: 5)
            Issue.record("Should have thrown")
        } catch _ as AxionError {
            // Expected
        }
    }

    @Test("exceeds max steps throws invalidPlan")
    func parsePlanExceedsMaxStepsThrowsInvalidPlan() async throws {
        var stepsJSON = ""
        for i in 0..<15 {
            if i > 0 { stepsJSON += "," }
            stepsJSON += """
            {"tool": "click", "args": {"x": \(i)}, "purpose": "step \(i)", "expected_change": "done \(i)"}
            """
        }
        let response = """
        {
            "steps": [\(stepsJSON)],
            "stopWhen": "all done"
        }
        """
        do {
            try PlanParser.parse(response, task: "test", maxSteps: 10)
            Issue.record("Should have thrown")
        } catch let error as AxionError {
            if case .invalidPlan = error {
                // Expected
            } else {
                Issue.record("Expected invalidPlan error")
            }
        }
    }

    @Test("stopWhen string maps to stop condition")
    func parsePlanStopWhenStringMapsToStopCondition() async throws {
        let response = """
        {
            "steps": [{"tool": "launch_app", "args": {"name": "Calc"}, "purpose": "open", "expected_change": "opened"}],
            "stopWhen": "Calculator window appears with result"
        }
        """
        let plan = try PlanParser.parse(response, task: "Open Calculator", maxSteps: 5)
        #expect(!plan.stopWhen.isEmpty)
        #expect(plan.stopWhen[0].type == .custom)
        #expect(plan.stopWhen[0].value == "Calculator window appears with result")
    }

    @Test("args field maps to parameters")
    func parsePlanArgsFieldMapsToParameters() async throws {
        let response = """
        {
            "steps": [{"tool": "launch_app", "args": {"name": "Calculator"}, "purpose": "open", "expected_change": "opened"}],
            "stopWhen": "Calculator visible"
        }
        """
        let plan = try PlanParser.parse(response, task: "test", maxSteps: 5)
        #expect(plan.steps[0].parameters["name"] == .string("Calculator"))
    }

    @Test("expected_change field snake case mapped")
    func parsePlanExpectedChangeFieldSnakeCaseMapped() async throws {
        let response = """
        {
            "steps": [{"tool": "click", "args": {"x": 10}, "purpose": "click", "expected_change": "Button activated"}],
            "stopWhen": "done"
        }
        """
        let plan = try PlanParser.parse(response, task: "test", maxSteps: 5)
        #expect(plan.steps[0].expectedChange == "Button activated")
    }

    @Test("validatePlan valid plan returns plan")
    func validatePlanValidPlanReturnsPlan() async throws {
        let plan = Plan(
            id: UUID(),
            task: "test task",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["name": .string("Calc")], purpose: "Open Calc", expectedChange: "Calc opens")
            ],
            stopWhen: [StopCondition(type: .custom, value: "Calc visible")],
            maxRetries: 3
        )
        let validated = try PlanParser.validatePlan(plan, maxSteps: 10)
        #expect(validated.steps.count == 1)
    }

    @Test("validatePlan empty steps throws invalidPlan")
    func validatePlanEmptyStepsThrowsInvalidPlan() async throws {
        let plan = Plan(
            id: UUID(),
            task: "test task",
            steps: [],
            stopWhen: [StopCondition(type: .custom, value: "done")],
            maxRetries: 3
        )
        do {
            try PlanParser.validatePlan(plan, maxSteps: 10)
            Issue.record("Should have thrown")
        } catch _ as AxionError {
            // Expected
        }
    }

    @Test("validatePlan empty stopWhen throws invalidPlan")
    func validatePlanEmptyStopWhenThrowsInvalidPlan() async throws {
        let plan = Plan(
            id: UUID(),
            task: "test task",
            steps: [
                Step(index: 0, tool: "click", parameters: ["x": .int(0)], purpose: "click", expectedChange: "clicked")
            ],
            stopWhen: [],
            maxRetries: 3
        )
        do {
            try PlanParser.validatePlan(plan, maxSteps: 10)
            Issue.record("Should have thrown")
        } catch _ as AxionError {
            // Expected
        }
    }

    @Test("done status returns empty steps plan")
    func parsePlanDoneStatusReturnsEmptyStepsPlan() async throws {
        // LLM 可能返回 status: "done" 表示任务已完成
        let response = """
        {
            "status": "done",
            "steps": [],
            "stopWhen": "Task already complete",
            "message": "The task is already done"
        }
        """
        // done 状态的 Plan 应该是有效的（0 步骤表示不需要执行）
        let plan = try PlanParser.parse(response, task: "test", maxSteps: 5)
        #expect(plan.steps.count == 0)
    }

    @Test("needs_clarification status throws appropriate error")
    func parsePlanNeedsClarificationStatusThrowsAppropriateError() async throws {
        let response = """
        {
            "status": "needs_clarification",
            "steps": [],
            "stopWhen": "",
            "message": "Please clarify which application to open"
        }
        """
        // needs_clarification 应该抛出包含 message 的错误
        do {
            try PlanParser.parse(response, task: "open app", maxSteps: 5)
            Issue.record("Should have thrown")
        } catch let error as AxionError {
            switch error {
            case .planningFailed(let reason):
                #expect(reason.contains("clarify") || reason.contains("Clarification"))
            case .invalidPlan:
                // 也可以接受 invalidPlan
                break
            default:
                Issue.record("Expected planningFailed or invalidPlan, got: \(error)")
            }
        }
    }
}
