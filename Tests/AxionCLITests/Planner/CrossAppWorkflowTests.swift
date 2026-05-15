import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

// Story 8.2: Cross-Application Workflow Orchestration
// Tests cover AC1–AC5 acceptance criteria with mock LLM and MCP clients.

@Suite("CrossAppWorkflow")
struct CrossAppWorkflowTests {

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

    @Test("AC1: plan parser cross-app steps parse successfully")
    func planParserCrossAppStepsParseSuccessfully() throws {
        let plan = try PlanParser.parse(crossAppPlanJSON, task: "Copy Safari URL to TextEdit", maxSteps: 10)

        #expect(plan.steps.count == 6)
        #expect(plan.steps[0].tool == "list_windows")
        #expect(plan.steps[1].tool == "activate_window")
        #expect(plan.steps[3].tool == "hotkey")
        #expect(plan.steps[3].parameters["keys"] == .string("command+c"))
        #expect(plan.steps[4].tool == "activate_window")
        #expect(plan.steps[5].tool == "hotkey")
        #expect(plan.steps[5].parameters["keys"] == .string("command+v"))
    }

    @Test("AC1: system prompt contains cross-app guidance for cross-app tasks")
    func createPlanCrossAppTaskSystemPromptContainsCrossAppGuidance() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: crossAppPlanJSON)
        let mockMCP = MockPlannerMCPClient()
        let planner = makePlanner(mockLLM: mockLLM, mockMCP: mockMCP)

        _ = try await planner.createPlan(for: "Copy Safari URL to TextEdit", context: makeContext())

        let systemPrompt = try #require(mockLLM.lastSystemPrompt)
        #expect(systemPrompt.contains("Cross-Application Workflow Patterns"))
        #expect(systemPrompt.contains("activate_window"))
        #expect(systemPrompt.contains("clipboard") || systemPrompt.contains("command+c"))
    }

    @Test("AC1: user prompt contains cross-app task")
    func createPlanCrossAppTaskUserPromptContainsTask() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: crossAppPlanJSON)
        let mockMCP = MockPlannerMCPClient()
        let planner = makePlanner(mockLLM: mockLLM, mockMCP: mockMCP)

        _ = try await planner.createPlan(for: "Copy Safari URL to TextEdit", context: makeContext())

        let userMessage = try #require(mockLLM.lastUserMessage)
        #expect(userMessage.contains("Copy Safari URL to TextEdit"))
    }

    @Test("AC2: multi-app activate steps parsed correctly")
    func planParserMultiAppActivateStepsParsedCorrectly() throws {
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
        #expect(activateSteps.count == 2)
        #expect(activateSteps[0].parameters["pid"] == .int(100))
        #expect(activateSteps[1].parameters["pid"] == .int(200))
    }

    @Test("AC2: activate then verify pattern")
    func planParserActivateThenVerifyPattern() throws {
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

        #expect(plan.steps[0].tool == "activate_window")
        #expect(plan.steps[1].tool == "get_window_state")
        #expect(plan.steps[2].tool == "hotkey")
    }

    @Test("AC3: clipboard copy step parsed correctly")
    func planParserClipboardCopyStepParsedCorrectly() throws {
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
        #expect(hotkeySteps.count == 2)

        let copyStep = hotkeySteps.first { $0.parameters["keys"] == .string("command+c") }
        #expect(copyStep != nil)

        let pasteStep = hotkeySteps.first { $0.parameters["keys"] == .string("command+v") }
        #expect(pasteStep != nil)

        let copyIndex = plan.steps.firstIndex(where: { $0.parameters["keys"] == .string("command+c") })!
        let pasteIndex = plan.steps.firstIndex(where: { $0.parameters["keys"] == .string("command+v") })!
        #expect(copyIndex < pasteIndex)
    }

    @Test("AC3: clipboard with verify step parsed correctly")
    func planParserClipboardWithVerifyStepParsedCorrectly() throws {
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
        #expect(verifyStep != nil)
        #expect(verifyStep!.purpose.contains("Verify") || verifyStep!.purpose.contains("confirm"))
    }

    @Test("AC3: planner prompt contains clipboard verification guidance")
    func plannerPromptContainsClipboardVerificationGuidance() throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        #expect(content.contains("Clipboard verification") || content.contains("clipboard"))
        #expect(content.contains("command+c") || content.contains("command+v"))
    }

    @Test("AC4: replan when app not installed failure propagates")
    func replanAppNotInstalledFailurePropagates() async throws {
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

        #expect(replanned.task == "Copy URL from Chrome to Notes")
        #expect(!replanned.steps.isEmpty)
        #expect(replanned.steps.contains(where: { $0.tool == "launch_app" }))
    }

    @Test("AC4: replan cross-app failure user prompt contains error context")
    func replanCrossAppFailureUserPromptContainsErrorContext() async throws {
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

        let userMessage = try #require(mockLLM.lastUserMessage)
        #expect(userMessage.contains("REPLAN"))
        #expect(userMessage.contains("not installed"))
    }

    @Test("AC4: replan clipboard empty failure includes context")
    func replanClipboardEmptyFailureIncludesContext() async throws {
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

        #expect(!replanned.steps.isEmpty)
        #expect(replanned.steps.contains(where: { $0.tool == "activate_window" }))
    }

    @Test("AC5: full cross-app copy-paste workflow pipeline")
    func crossAppPipelineFullCopyPasteWorkflow() async throws {
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
        #expect(plan.steps.count == 6)
        #expect(plan.task == "Copy Safari page text to TextEdit")

        // Verify discover → source → copy → switch → paste pattern
        let tools = plan.steps.map(\.tool)
        #expect(tools[0] == "list_windows")
        #expect(tools.contains("activate_window"))
        #expect(tools.contains("hotkey"))

        let copyIndex = plan.steps.firstIndex(where: { $0.tool == "hotkey" && $0.parameters["keys"] == .string("command+c") })
        let pasteIndex = plan.steps.firstIndex(where: { $0.tool == "hotkey" && $0.parameters["keys"] == .string("command+v") })
        #expect(copyIndex != nil)
        #expect(pasteIndex != nil)
        if let copyIndex, let pasteIndex {
            #expect(copyIndex < pasteIndex)
        }

        // Phase 3: Verify system prompt had proper guidance
        let systemPrompt = try #require(mockLLM.lastSystemPrompt)
        #expect(systemPrompt.contains("Cross-Application"))
    }

    @Test("AC5: cross-app pipeline replan after app not found")
    func crossAppPipelineReplanAfterAppNotFound() async throws {
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
        #expect(replanned.task == "Copy URL from Safari to Notes")
        #expect(!replanned.steps.isEmpty)

        let launchSteps = replanned.steps.filter { $0.tool == "launch_app" }
        #expect(launchSteps.contains(where: { $0.parameters["app_name"]?.stringValue == "TextEdit" }))

        let userMessage = try #require(mockLLM.lastUserMessage)
        #expect(userMessage.contains("REPLAN"))
        #expect(userMessage.contains("not installed"))
    }

    @Test("planner prompt cross-app workflow contains six-step pattern")
    func plannerPromptCrossAppWorkflowContainsSixStepPattern() throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        #expect(content.contains("Discover") && content.contains("Source operation") && content.contains("Verify"))
    }

    @Test("planner prompt failure recovery contains app not found guidance")
    func plannerPromptFailureRecoveryContainsAppNotFoundGuidance() throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        #expect(content.contains("Application not found") || content.contains("alternative"))
        #expect(content.contains("AX tree") || content.contains("accessibility"))
    }
}

extension Value {
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}
