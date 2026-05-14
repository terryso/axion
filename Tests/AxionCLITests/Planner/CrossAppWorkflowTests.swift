import XCTest
@testable import AxionCLI
@testable import AxionCore

// Story 8.2: Cross-Application Workflow Orchestration
// Tests cover AC1–AC5 acceptance criteria with mock LLM and MCP clients.

final class CrossAppWorkflowTests: XCTestCase {

    // MARK: - Helpers

    private func makePlanner(mockLLM: MockLLMClient, mockMCP: MockPlannerMCPClient) -> LLMPlanner {
        LLMPlanner(
            config: AxionConfig.default,
            llmClient: mockLLM,
            mcpClient: mockMCP,
            retryDelay: { _ in }
        )
    }

    private func makeContext() -> RunContext {
        RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: AxionConfig.default
        )
    }

    private let crossAppPlanJSON = """
    {
        "steps": [
            {"tool": "list_windows", "args": {}, "purpose": "Discover all open windows", "expected_change": "Window list obtained"},
            {"tool": "activate_window", "args": {"pid": 1234}, "purpose": "Activate Safari window", "expected_change": "Safari is focused"},
            {"tool": "hotkey", "args": {"keys": "command+l"}, "purpose": "Focus Safari address bar", "expected_change": "Address bar focused"},
            {"tool": "hotkey", "args": {"keys": "command+c"}, "purpose": "Copy URL from address bar", "expected_change": "URL copied to clipboard"},
            {"tool": "activate_window", "args": {"pid": 5678}, "purpose": "Switch to TextEdit", "expected_change": "TextEdit is focused"},
            {"tool": "hotkey", "args": {"keys": "command+v"}, "purpose": "Paste URL into TextEdit", "expected_change": "URL appears in document"}
        ],
        "stopWhen": "URL is visible in TextEdit document"
    }
    """

    // MARK: - AC1: Planner generates cross-app plans

    func test_planParser_crossAppSteps_parseSuccessfully() throws {
        let plan = try PlanParser.parse(crossAppPlanJSON, task: "Copy Safari URL to TextEdit", maxSteps: 10)

        XCTAssertEqual(plan.steps.count, 6)
        XCTAssertEqual(plan.steps[0].tool, "list_windows")
        XCTAssertEqual(plan.steps[1].tool, "activate_window")
        XCTAssertEqual(plan.steps[3].tool, "hotkey")
        XCTAssertEqual(plan.steps[3].parameters["keys"], .string("command+c"))
        XCTAssertEqual(plan.steps[4].tool, "activate_window")
        XCTAssertEqual(plan.steps[5].tool, "hotkey")
        XCTAssertEqual(plan.steps[5].parameters["keys"], .string("command+v"))
    }

    func test_createPlan_crossAppTask_systemPromptContainsCrossAppGuidance() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: crossAppPlanJSON)
        let mockMCP = MockPlannerMCPClient()
        let planner = makePlanner(mockLLM: mockLLM, mockMCP: mockMCP)

        _ = try await planner.createPlan(for: "Copy Safari URL to TextEdit", context: makeContext())

        let systemPrompt = try XCTUnwrap(mockLLM.lastSystemPrompt)
        XCTAssertTrue(systemPrompt.contains("Cross-Application Workflow Patterns"),
            "System prompt should contain cross-app workflow guidance for cross-app tasks")
        XCTAssertTrue(systemPrompt.contains("activate_window"),
            "System prompt should mention activate_window tool")
        XCTAssertTrue(systemPrompt.contains("clipboard") || systemPrompt.contains("command+c"),
            "System prompt should mention clipboard operations")
    }

    func test_createPlan_crossAppTask_userPromptContainsTask() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: crossAppPlanJSON)
        let mockMCP = MockPlannerMCPClient()
        let planner = makePlanner(mockLLM: mockLLM, mockMCP: mockMCP)

        _ = try await planner.createPlan(for: "Copy Safari URL to TextEdit", context: makeContext())

        let userMessage = try XCTUnwrap(mockLLM.lastUserMessage)
        XCTAssertTrue(userMessage.contains("Copy Safari URL to TextEdit"),
            "User prompt should contain the original cross-app task")
    }

    // MARK: - AC2: Executor window switching ensures focus

    func test_planParser_multiAppActivateSteps_parsedCorrectly() throws {
        let json = """
        {
            "steps": [
                {"tool": "activate_window", "args": {"pid": 100}, "purpose": "Focus Safari", "expected_change": "Safari focused"},
                {"tool": "click", "args": {"x": 200, "y": 300}, "purpose": "Click link", "expected_change": "Link clicked"},
                {"tool": "activate_window", "args": {"pid": 200}, "purpose": "Switch to Notes", "expected_change": "Notes focused"},
                {"tool": "type_text", "args": {"text": "saved text"}, "purpose": "Paste into note", "expected_change": "Text typed"}
            ],
            "stopWhen": "Text appears in Notes"
        }
        """
        let plan = try PlanParser.parse(json, task: "Copy link to Notes", maxSteps: 10)

        let activateSteps = plan.steps.filter { $0.tool == "activate_window" }
        XCTAssertEqual(activateSteps.count, 2, "Should have 2 activate_window steps for source and target apps")
        XCTAssertEqual(activateSteps[0].parameters["pid"], .int(100))
        XCTAssertEqual(activateSteps[1].parameters["pid"], .int(200))
    }

    func test_planParser_activateThenVerify_pattern() throws {
        let json = """
        {
            "steps": [
                {"tool": "activate_window", "args": {"pid": 100}, "purpose": "Focus Safari", "expected_change": "Safari focused"},
                {"tool": "get_window_state", "args": {"window_id": "win1"}, "purpose": "Verify Safari has focus", "expected_change": "Confirmed focus"},
                {"tool": "hotkey", "args": {"keys": "command+c"}, "purpose": "Copy content", "expected_change": "Content copied"}
            ],
            "stopWhen": "Content copied"
        }
        """
        let plan = try PlanParser.parse(json, task: "Copy from Safari", maxSteps: 10)

        XCTAssertEqual(plan.steps[0].tool, "activate_window")
        XCTAssertEqual(plan.steps[1].tool, "get_window_state",
            "After activate_window, next step should verify focus via get_window_state")
        XCTAssertEqual(plan.steps[2].tool, "hotkey")
    }

    // MARK: - AC3: Clipboard cross-app data transfer

    func test_planParser_clipboardCopyStep_parsedCorrectly() throws {
        let json = """
        {
            "steps": [
                {"tool": "activate_window", "args": {"pid": 100}, "purpose": "Focus source app", "expected_change": "Focused"},
                {"tool": "hotkey", "args": {"keys": "command+c"}, "purpose": "Copy text to clipboard", "expected_change": "Text in clipboard"},
                {"tool": "activate_window", "args": {"pid": 200}, "purpose": "Focus target app", "expected_change": "Focused"},
                {"tool": "hotkey", "args": {"keys": "command+v"}, "purpose": "Paste from clipboard", "expected_change": "Text pasted"}
            ],
            "stopWhen": "Text appears in target"
        }
        """
        let plan = try PlanParser.parse(json, task: "Transfer text via clipboard", maxSteps: 10)

        let hotkeySteps = plan.steps.filter { $0.tool == "hotkey" }
        XCTAssertEqual(hotkeySteps.count, 2)

        let copyStep = hotkeySteps.first { $0.parameters["keys"] == .string("command+c") }
        XCTAssertNotNil(copyStep, "Should have a command+c copy step")

        let pasteStep = hotkeySteps.first { $0.parameters["keys"] == .string("command+v") }
        XCTAssertNotNil(pasteStep, "Should have a command+v paste step")

        let copyIndex = plan.steps.firstIndex(where: { $0.parameters["keys"] == .string("command+c") })!
        let pasteIndex = plan.steps.firstIndex(where: { $0.parameters["keys"] == .string("command+v") })!
        XCTAssertLessThan(copyIndex, pasteIndex, "Copy step should come before paste step")
    }

    func test_planParser_clipboardWithVerifyStep_parsedCorrectly() throws {
        let json = """
        {
            "steps": [
                {"tool": "hotkey", "args": {"keys": "command+c"}, "purpose": "Copy text", "expected_change": "Copied"},
                {"tool": "get_window_state", "args": {"window_id": "win1"}, "purpose": "Verify clipboard content via AX tree", "expected_change": "Content confirmed"},
                {"tool": "activate_window", "args": {"pid": 200}, "purpose": "Switch to target", "expected_change": "Target focused"},
                {"tool": "hotkey", "args": {"keys": "command+v"}, "purpose": "Paste", "expected_change": "Pasted"}
            ],
            "stopWhen": "Done"
        }
        """
        let plan = try PlanParser.parse(json, task: "Copy-paste with verification", maxSteps: 10)

        let verifyStep = plan.steps.first { $0.tool == "get_window_state" }
        XCTAssertNotNil(verifyStep, "Plan should include a verification step after clipboard copy")
        XCTAssertTrue(verifyStep!.purpose.contains("Verify") || verifyStep!.purpose.contains("confirm"),
            "Verification step purpose should mention verification")
    }

    func test_plannerPrompt_containsClipboardVerificationGuidance() throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        XCTAssertTrue(content.contains("Clipboard verification") || content.contains("clipboard"),
            "System prompt should include clipboard verification guidance")
        XCTAssertTrue(content.contains("command+c") || content.contains("command+v"),
            "System prompt should reference cmd+c/v keyboard shortcuts")
    }

    // MARK: - AC4: Cross-app failure replanning

    func test_replan_appNotInstalled_failurePropagates() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [
                {"tool": "launch_app", "args": {"app_name": "TextEdit"}, "purpose": "Launch alternative app TextEdit", "expected_change": "TextEdit opens"},
                {"tool": "type_text", "args": {"text": "content"}, "purpose": "Type content", "expected_change": "Text entered"}
            ],
            "stopWhen": "Content in TextEdit"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        let planner = makePlanner(mockLLM: mockLLM, mockMCP: mockMCP)

        let currentPlan = Plan(
            id: UUID(),
            task: "Copy URL from Chrome to Notes",
            steps: [
                Step(index: 0, tool: "activate_window", parameters: ["pid": .int(100)], purpose: "Focus Chrome", expectedChange: "Chrome focused"),
                Step(index: 1, tool: "hotkey", parameters: ["keys": .string("command+c")], purpose: "Copy URL", expectedChange: "URL copied"),
                Step(index: 2, tool: "launch_app", parameters: ["app_name": .string("Notes")], purpose: "Launch Notes", expectedChange: "Notes opens"),
                Step(index: 3, tool: "hotkey", parameters: ["keys": .string("command+v")], purpose: "Paste URL", expectedChange: "URL pasted"),
            ],
            stopWhen: [StopCondition(type: .custom, value: "URL in Notes")],
            maxRetries: 3
        )

        let executedSteps = [
            ExecutedStep(stepIndex: 0, tool: "activate_window", parameters: ["pid": .int(100)], result: "Chrome activated", success: true, timestamp: Date()),
            ExecutedStep(stepIndex: 1, tool: "hotkey", parameters: ["keys": .string("command+c")], result: "Copied", success: true, timestamp: Date()),
        ]

        let context = RunContext(
            planId: currentPlan.id,
            currentState: .replanning,
            currentStepIndex: 2,
            executedSteps: executedSteps,
            replanCount: 1,
            config: AxionConfig.default
        )

        let replanned = try await planner.replan(
            from: currentPlan,
            executedSteps: executedSteps,
            failureReason: "Application 'Notes' is not installed or not found",
            context: context
        )

        XCTAssertEqual(replanned.task, "Copy URL from Chrome to Notes")
        XCTAssertFalse(replanned.steps.isEmpty)
        XCTAssertTrue(replanned.steps.contains(where: { $0.tool == "launch_app" }),
            "Replanned steps should include launching an alternative app")
    }

    func test_replan_crossAppFailure_userPromptContainsErrorContext() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [{"tool": "launch_app", "args": {"app_name": "TextEdit"}, "purpose": "Use TextEdit instead", "expected_change": "TextEdit opens"}],
            "stopWhen": "Done"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        let planner = makePlanner(mockLLM: mockLLM, mockMCP: mockMCP)

        let currentPlan = Plan(
            id: UUID(),
            task: "Copy from Safari to Notes",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Notes")], purpose: "Launch Notes", expectedChange: "Notes opens"),
            ],
            stopWhen: [StopCondition(type: .custom, value: "Done")],
            maxRetries: 3
        )

        let context = RunContext(
            planId: currentPlan.id,
            currentState: .replanning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 1,
            config: AxionConfig.default
        )

        _ = try await planner.replan(
            from: currentPlan,
            executedSteps: [],
            failureReason: "Application 'Notes' is not installed",
            context: context
        )

        let userMessage = try XCTUnwrap(mockLLM.lastUserMessage)
        XCTAssertTrue(userMessage.contains("REPLAN"), "Replan prompt should contain REPLAN marker")
        XCTAssertTrue(userMessage.contains("not installed"),
            "Replan prompt should contain the original failure reason about app not installed")
    }

    func test_replan_clipboardEmpty_failureIncludesContext() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [
                {"tool": "get_accessibility_tree", "args": {"window_id": "win1"}, "purpose": "Read content directly from AX tree", "expected_change": "Content read"},
                {"tool": "activate_window", "args": {"pid": 200}, "purpose": "Switch to target", "expected_change": "Target focused"},
                {"tool": "type_text", "args": {"text": "read content"}, "purpose": "Type content instead of paste", "expected_change": "Content entered"}
            ],
            "stopWhen": "Content in target"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        let planner = makePlanner(mockLLM: mockLLM, mockMCP: mockMCP)

        let currentPlan = Plan(
            id: UUID(),
            task: "Copy text from Safari to TextEdit",
            steps: [
                Step(index: 0, tool: "activate_window", parameters: ["pid": .int(100)], purpose: "Focus Safari", expectedChange: "Safari focused"),
                Step(index: 1, tool: "hotkey", parameters: ["keys": .string("command+c")], purpose: "Copy text", expectedChange: "Text copied"),
                Step(index: 2, tool: "activate_window", parameters: ["pid": .int(200)], purpose: "Focus TextEdit", expectedChange: "TextEdit focused"),
                Step(index: 3, tool: "hotkey", parameters: ["keys": .string("command+v")], purpose: "Paste text", expectedChange: "Text pasted"),
            ],
            stopWhen: [StopCondition(type: .custom, value: "Text in TextEdit")],
            maxRetries: 3
        )

        let executedSteps = [
            ExecutedStep(stepIndex: 0, tool: "activate_window", parameters: ["pid": .int(100)], result: "OK", success: true, timestamp: Date()),
            ExecutedStep(stepIndex: 1, tool: "hotkey", parameters: ["keys": .string("command+c")], result: "OK", success: true, timestamp: Date()),
            ExecutedStep(stepIndex: 2, tool: "activate_window", parameters: ["pid": .int(200)], result: "OK", success: true, timestamp: Date()),
        ]

        let context = RunContext(
            planId: currentPlan.id,
            currentState: .replanning,
            currentStepIndex: 3,
            executedSteps: executedSteps,
            replanCount: 1,
            config: AxionConfig.default
        )

        let replanned = try await planner.replan(
            from: currentPlan,
            executedSteps: executedSteps,
            failureReason: "Clipboard is empty or paste produced no visible change",
            context: context
        )

        XCTAssertFalse(replanned.steps.isEmpty)
        XCTAssertTrue(replanned.steps.contains(where: { $0.tool == "activate_window" }),
            "Replanned steps should handle clipboard failure with alternative approach")
    }

    // MARK: - AC5: End-to-end cross-app pipeline simulation

    func test_crossAppPipeline_fullCopyPasteWorkflow() async throws {
        // Phase 1: Plan generation
        let planJSON = """
        {
            "steps": [
                {"tool": "list_windows", "args": {}, "purpose": "Discover windows", "expected_change": "Window list obtained"},
                {"tool": "activate_window", "args": {"pid": 100}, "purpose": "Focus Safari", "expected_change": "Safari focused"},
                {"tool": "hotkey", "args": {"keys": "command+a"}, "purpose": "Select all text", "expected_change": "Text selected"},
                {"tool": "hotkey", "args": {"keys": "command+c"}, "purpose": "Copy text to clipboard", "expected_change": "Text copied"},
                {"tool": "activate_window", "args": {"pid": 200}, "purpose": "Focus TextEdit", "expected_change": "TextEdit focused"},
                {"tool": "hotkey", "args": {"keys": "command+v"}, "purpose": "Paste text into TextEdit", "expected_change": "Text pasted"}
            ],
            "stopWhen": "Text visible in TextEdit"
        }
        """
        let mockLLM = MockLLMClient(stubbedResponse: planJSON)
        let mockMCP = MockPlannerMCPClient()
        let planner = makePlanner(mockLLM: mockLLM, mockMCP: mockMCP)

        let plan = try await planner.createPlan(for: "Copy Safari page text to TextEdit", context: makeContext())

        // Phase 2: Validate plan structure
        XCTAssertEqual(plan.steps.count, 6, "Cross-app plan should have multi-step workflow")
        XCTAssertEqual(plan.task, "Copy Safari page text to TextEdit")

        // Verify discover → source → copy → switch → paste pattern
        let tools = plan.steps.map(\.tool)
        XCTAssertEqual(tools[0], "list_windows", "First step should discover windows")
        XCTAssertTrue(tools.contains("activate_window"), "Plan should include window activation")
        XCTAssertTrue(tools.contains("hotkey"), "Plan should include hotkey operations")

        let copyIndex = plan.steps.firstIndex(where: { $0.tool == "hotkey" && $0.parameters["keys"] == .string("command+c") })
        let pasteIndex = plan.steps.firstIndex(where: { $0.tool == "hotkey" && $0.parameters["keys"] == .string("command+v") })
        XCTAssertNotNil(copyIndex, "Plan should include a command+c copy step")
        XCTAssertNotNil(pasteIndex, "Plan should include a command+v paste step")
        if let copyIndex, let pasteIndex {
            XCTAssertLessThan(copyIndex, pasteIndex, "Copy step should come before paste step")
        }

        // Phase 3: Verify system prompt had proper guidance
        let systemPrompt = try XCTUnwrap(mockLLM.lastSystemPrompt)
        XCTAssertTrue(systemPrompt.contains("Cross-Application"),
            "System prompt should have cross-app guidance for cross-app tasks")
    }

    func test_crossAppPipeline_replanAfterAppNotFound() async throws {
        // Phase 1: Initial plan fails because target app is missing
        let initialPlan = Plan(
            id: UUID(),
            task: "Copy URL from Safari to Notes",
            steps: [
                Step(index: 0, tool: "activate_window", parameters: ["pid": .int(100)], purpose: "Focus Safari", expectedChange: "Safari focused"),
                Step(index: 1, tool: "hotkey", parameters: ["keys": .string("command+c")], purpose: "Copy URL", expectedChange: "URL copied"),
                Step(index: 2, tool: "launch_app", parameters: ["app_name": .string("Notes")], purpose: "Launch Notes", expectedChange: "Notes opens"),
            ],
            stopWhen: [StopCondition(type: .custom, value: "URL in Notes")],
            maxRetries: 3
        )

        let executedSteps = [
            ExecutedStep(stepIndex: 0, tool: "activate_window", parameters: ["pid": .int(100)], result: "OK", success: true, timestamp: Date()),
            ExecutedStep(stepIndex: 1, tool: "hotkey", parameters: ["keys": .string("command+c")], result: "OK", success: true, timestamp: Date()),
        ]

        let context = RunContext(
            planId: initialPlan.id,
            currentState: .replanning,
            currentStepIndex: 2,
            executedSteps: executedSteps,
            replanCount: 1,
            config: AxionConfig.default
        )

        // Phase 2: Replan with alternative app
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [
                {"tool": "launch_app", "args": {"app_name": "TextEdit"}, "purpose": "Launch TextEdit as alternative", "expected_change": "TextEdit opens"},
                {"tool": "hotkey", "args": {"keys": "command+v"}, "purpose": "Paste URL", "expected_change": "URL pasted"}
            ],
            "stopWhen": "URL in TextEdit"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        let planner = makePlanner(mockLLM: mockLLM, mockMCP: mockMCP)

        let replanned = try await planner.replan(
            from: initialPlan,
            executedSteps: executedSteps,
            failureReason: "Application 'Notes' is not installed",
            context: context
        )

        // Phase 3: Verify recovery plan uses alternative approach
        XCTAssertEqual(replanned.task, "Copy URL from Safari to Notes")
        XCTAssertFalse(replanned.steps.isEmpty)

        let launchSteps = replanned.steps.filter { $0.tool == "launch_app" }
        XCTAssertTrue(launchSteps.contains(where: { $0.parameters["app_name"]?.stringValue == "TextEdit" }),
            "Recovery plan should launch alternative app (TextEdit)")

        let userMessage = try XCTUnwrap(mockLLM.lastUserMessage)
        XCTAssertTrue(userMessage.contains("REPLAN"))
        XCTAssertTrue(userMessage.contains("not installed"))
    }

    // MARK: - Prompt content validation

    func test_plannerPrompt_crossAppWorkflow_containsSixStepPattern() throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        XCTAssertTrue(content.contains("Discover") && content.contains("Source operation") && content.contains("Verify"),
            "Cross-Application Workflow Patterns should include the 6-step pattern (Discover, Source, Verify, Switch, Target, Verify)")
    }

    func test_plannerPrompt_failureRecovery_containsAppNotFoundGuidance() throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        XCTAssertTrue(content.contains("Application not found") || content.contains("alternative"),
            "Failure recovery should include guidance for when application is not found")
        XCTAssertTrue(content.contains("AX tree") || content.contains("accessibility"),
            "Failure recovery should mention AX tree fallback for clipboard failures")
    }
}

// MARK: - Value helper extension

extension Value {
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}
