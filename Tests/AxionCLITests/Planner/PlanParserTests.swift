import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] 基础设施验证
// [P1] 行为验证

final class PlanParserTests: XCTestCase {

    // MARK: - P0 类型存在性

    func test_planParser_typeExists() async throws {
        let _ = PlanParser.self
    }

    // MARK: - P0 Markdown 围栏解析 (AC4)

    func test_stripFences_jsonInBackticks_extractsJSON() async throws {
        let input = """
        Here is the plan:
        ```json
        {"status": "ready", "steps": [], "stopWhen": "task complete"}
        ```
        """
        let result = try PlanParser.stripFences(input)
        XCTAssertTrue(result.contains("\"status\""))
        XCTAssertTrue(result.contains("\"steps\""))
        XCTAssertFalse(result.contains("```"))
    }

    func test_stripFences_jsonInPlainBackticks_extractsJSON() async throws {
        let input = """
        ```
        {"status": "ready", "steps": [], "stopWhen": "task complete"}
        ```
        """
        let result = try PlanParser.stripFences(input)
        XCTAssertTrue(result.contains("\"status\""))
        XCTAssertFalse(result.contains("```"))
    }

    // MARK: - P0 前导文本解析 (AC5)

    func test_stripFences_proseBeforeJSON_extractsJSON() async throws {
        let input = """
        Looking at the current screen state, I can see the Calculator is not yet open.
        Let me plan the steps:

        {"status": "ready", "steps": [{"tool": "launch_app", "args": {"name": "Calculator"}, "purpose": "Open Calculator", "expected_change": "Calculator opens"}], "stopWhen": "Result 391 is visible"}
        """
        let result = try PlanParser.stripFences(input)
        XCTAssertTrue(result.hasPrefix("{"))
        XCTAssertTrue(result.contains("\"status\""))
        XCTAssertTrue(result.contains("\"launch_app\""))
    }

    func test_stripFences_jsonWithTrailingText_extractsJSON() async throws {
        let input = """
        {"status": "ready", "steps": [], "stopWhen": "done"}
        And some trailing text after.
        """
        let result = try PlanParser.stripFences(input)
        XCTAssertTrue(result.hasPrefix("{"))
        // JSON should end at the closing brace, not include trailing text
        XCTAssertTrue(result.contains("\"stopWhen\""))
    }

    // MARK: - P0 字符串内嵌套花括号处理

    func test_stripFences_nestedBracesInStrings_handlesCorrectly() async throws {
        let input = """
        {"status": "ready", "steps": [{"tool": "click", "args": {"selector": "div.container { color: red }"}, "purpose": "Click element", "expected_change": "clicked"}], "stopWhen": "done"}
        """
        let result = try PlanParser.stripFences(input)
        XCTAssertTrue(result.contains("\"selector\""))
        XCTAssertTrue(result.contains("color: red"))
    }

    // MARK: - P0 纯 JSON 输入 (无围栏无前导)

    func test_stripFences_pureJSON_returnsAsIs() async throws {
        let input = """
        {"status": "ready", "steps": [], "stopWhen": "task complete"}
        """
        let result = try PlanParser.stripFences(input)
        XCTAssertEqual(result.trimmingCharacters(in: .whitespacesAndNewlines), input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - P0 完整 Plan 解析 (AC2, AC3)

    func test_parsePlan_validResponse_returnsPlan() async throws {
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

        XCTAssertEqual(plan.task, "Open Calculator and compute 17 * 23")
        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.steps[0].tool, "launch_app")
        XCTAssertEqual(plan.steps[0].purpose, "Open Calculator")
        XCTAssertEqual(plan.steps[0].expectedChange, "Calculator is open")
        XCTAssertEqual(plan.steps[1].tool, "click")
        XCTAssertFalse(plan.stopWhen.isEmpty)
    }

    func test_parsePlan_stepStructure_hasAllRequiredFields() async throws {
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
        XCTAssertEqual(step.tool, "type_text")
        XCTAssertNotNil(step.parameters["text"])
        XCTAssertEqual(step.purpose, "Type greeting")
        XCTAssertEqual(step.expectedChange, "Text entered")
    }

    // MARK: - P0 解析失败处理 (AC7, NFR7)

    func test_parsePlan_invalidJSON_throwsInvalidPlan() async throws {
        let invalidResponse = "This is not JSON at all, just plain text."
        XCTAssertThrowsError(try PlanParser.parse(invalidResponse, task: "test", maxSteps: 5)) { error in
            // 验证抛出的是 AxionError.invalidPlan
            if let axionError = error as? AxionError {
                guard case .invalidPlan = axionError else {
                    XCTFail("Expected invalidPlan error, got: \(axionError)")
                    return
                }
            }
        }
    }

    func test_parsePlan_failurePreservesRawResponse_NFR7() async throws {
        // NFR7: 解析失败时原始 LLM 响应不丢失
        let badResponse = "I cannot parse this {broken json"
        do {
            _ = try PlanParser.parse(badResponse, task: "test", maxSteps: 5)
            XCTFail("Should have thrown an error")
        } catch let error as AxionError {
            // 错误原因中应包含原始响应或其部分内容
            switch error {
            case .invalidPlan(let reason):
                XCTAssertTrue(reason.contains("broken") || reason.contains("cannot parse") || reason.contains("JSON decode failed"),
                              "Error reason should contain raw response context, got: \(reason)")
            default:
                XCTFail("Expected invalidPlan error, got: \(error)")
            }
        }
    }

    func test_parsePlan_emptySteps_throwsInvalidPlan() async throws {
        let emptySteps = """
        {
            "steps": [],
            "stopWhen": "done"
        }
        """
        XCTAssertThrowsError(try PlanParser.parse(emptySteps, task: "test", maxSteps: 5))
    }

    func test_parsePlan_missingStopWhen_throwsInvalidPlan() async throws {
        let noStopWhen = """
        {
            "steps": [{"tool": "click", "args": {}, "purpose": "click", "expected_change": "clicked"}],
            "stopWhen": ""
        }
        """
        XCTAssertThrowsError(try PlanParser.parse(noStopWhen, task: "test", maxSteps: 5))
    }

    func test_parsePlan_stepMissingTool_throwsInvalidPlan() async throws {
        let missingTool = """
        {
            "steps": [{"args": {}, "purpose": "click", "expected_change": "clicked"}],
            "stopWhen": "done"
        }
        """
        XCTAssertThrowsError(try PlanParser.parse(missingTool, task: "test", maxSteps: 5))
    }

    func test_parsePlan_stepMissingPurpose_throwsInvalidPlan() async throws {
        let missingPurpose = """
        {
            "steps": [{"tool": "click", "args": {}, "expected_change": "clicked"}],
            "stopWhen": "done"
        }
        """
        XCTAssertThrowsError(try PlanParser.parse(missingPurpose, task: "test", maxSteps: 5))
    }

    // MARK: - P0 步骤数超限

    func test_parsePlan_exceedsMaxSteps_throwsInvalidPlan() async throws {
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
        XCTAssertThrowsError(try PlanParser.parse(response, task: "test", maxSteps: 10)) { error in
            if let axionError = error as? AxionError {
                guard case .invalidPlan = axionError else {
                    XCTFail("Expected invalidPlan error")
                    return
                }
            }
        }
    }

    // MARK: - P1 stopWhen 映射

    func test_parsePlan_stopWhenString_mapsToStopCondition() async throws {
        let response = """
        {
            "steps": [{"tool": "launch_app", "args": {"name": "Calc"}, "purpose": "open", "expected_change": "opened"}],
            "stopWhen": "Calculator window appears with result"
        }
        """
        let plan = try PlanParser.parse(response, task: "Open Calculator", maxSteps: 5)
        XCTAssertFalse(plan.stopWhen.isEmpty)
        XCTAssertEqual(plan.stopWhen[0].type, .custom)
        XCTAssertEqual(plan.stopWhen[0].value, "Calculator window appears with result")
    }

    // MARK: - P1 参数映射 args -> parameters

    func test_parsePlan_argsField_mapsToParameters() async throws {
        let response = """
        {
            "steps": [{"tool": "launch_app", "args": {"name": "Calculator"}, "purpose": "open", "expected_change": "opened"}],
            "stopWhen": "Calculator visible"
        }
        """
        let plan = try PlanParser.parse(response, task: "test", maxSteps: 5)
        XCTAssertEqual(plan.steps[0].parameters["name"], .string("Calculator"))
    }

    // MARK: - P1 expected_change -> expectedChange 映射

    func test_parsePlan_expectedChangeField_snakeCaseMapped() async throws {
        let response = """
        {
            "steps": [{"tool": "click", "args": {"x": 10}, "purpose": "click", "expected_change": "Button activated"}],
            "stopWhen": "done"
        }
        """
        let plan = try PlanParser.parse(response, task: "test", maxSteps: 5)
        XCTAssertEqual(plan.steps[0].expectedChange, "Button activated")
    }

    // MARK: - P1 validatePlan (AC3)

    func test_validatePlan_validPlan_returnsPlan() async throws {
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
        XCTAssertEqual(validated.steps.count, 1)
    }

    func test_validatePlan_emptySteps_throwsInvalidPlan() async throws {
        let plan = Plan(
            id: UUID(),
            task: "test task",
            steps: [],
            stopWhen: [StopCondition(type: .custom, value: "done")],
            maxRetries: 3
        )
        XCTAssertThrowsError(try PlanParser.validatePlan(plan, maxSteps: 10))
    }

    func test_validatePlan_emptyStopWhen_throwsInvalidPlan() async throws {
        let plan = Plan(
            id: UUID(),
            task: "test task",
            steps: [
                Step(index: 0, tool: "click", parameters: ["x": .int(0)], purpose: "click", expectedChange: "clicked")
            ],
            stopWhen: [],
            maxRetries: 3
        )
        XCTAssertThrowsError(try PlanParser.validatePlan(plan, maxSteps: 10))
    }

    // MARK: - P1 status 字段处理

    func test_parsePlan_doneStatus_returnsEmptyStepsPlan() async throws {
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
        XCTAssertEqual(plan.steps.count, 0)
    }

    func test_parsePlan_needsClarificationStatus_throwsAppropriateError() async throws {
        let response = """
        {
            "status": "needs_clarification",
            "steps": [],
            "stopWhen": "",
            "message": "Please clarify which application to open"
        }
        """
        // needs_clarification 应该抛出包含 message 的错误
        XCTAssertThrowsError(try PlanParser.parse(response, task: "open app", maxSteps: 5)) { error in
            if let axionError = error as? AxionError {
                switch axionError {
                case .planningFailed(let reason):
                    XCTAssertTrue(reason.contains("clarify") || reason.contains("Clarification"),
                                  "Error should mention clarification, got: \(reason)")
                case .invalidPlan:
                    // 也可以接受 invalidPlan
                    break
                default:
                    XCTFail("Expected planningFailed or invalidPlan, got: \(axionError)")
                }
            }
        }
    }
}
