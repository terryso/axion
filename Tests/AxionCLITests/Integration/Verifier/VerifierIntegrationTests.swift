import XCTest
@testable import AxionCLI
@testable import AxionCore

/// Real integration test for Story 3-4 Verifier.
/// Starts the actual Helper process, launches Calculator, captures real
/// screenshot + AX tree, and verifies through StopConditionEvaluator + TaskVerifier.
///
/// Prerequisites:
/// - AxionHelper.app built at .build/AxionHelper.app
/// - macOS Accessibility permissions granted to Terminal/iTerm
/// - Screen Recording permission granted (for screenshots)
final class VerifierIntegrationTests: XCTestCase {

    // MARK: - Helper → MCPClientProtocol Adapter

    /// Wraps HelperProcessManager to conform to MCPClientProtocol.
    struct RealMCPAdapter: MCPClientProtocol {
        private let manager: HelperProcessManager

        init(manager: HelperProcessManager) {
            self.manager = manager
        }

        func callTool(name: String, arguments: [String: AxionCore.Value]) async throws -> String {
            return try await manager.callTool(name: name, arguments: arguments)
        }

        func listTools() async throws -> [String] {
            return try await manager.listTools()
        }
    }

    // MARK: - Properties

    private var manager: HelperProcessManager?
    private var mcpClient: RealMCPAdapter?

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()

        let mgr = HelperProcessManager()
        do {
            try await mgr.start()
        } catch {
            XCTFail("Failed to start Helper process: \(error). " +
                    "Ensure AxionHelper.app is built and AX permissions are granted.")
            return
        }

        let running = await mgr.isRunning()
        XCTAssertTrue(running, "Helper should be running after start()")

        let tools = try await mgr.listTools()
        XCTAssertTrue(tools.contains(ToolNames.screenshot), "Helper should expose 'screenshot' tool")
        XCTAssertTrue(tools.contains(ToolNames.getAccessibilityTree), "Helper should expose 'get_accessibility_tree' tool")

        self.manager = mgr
        self.mcpClient = RealMCPAdapter(manager: mgr)
    }

    override func tearDown() async throws {
        if let manager {
            await manager.stop()
        }
        self.manager = nil
        self.mcpClient = nil
        try await super.tearDown()
    }

    // MARK: - Helper: Launch Calculator and return (pid, windowId, windowTitle)

    private func launchCalculator() async throws -> (pid: Int, windowId: Int, windowTitle: String) {
        guard let mcpClient else { throw NSError(domain: "No MCP client", code: 1) }

        // Launch
        let launchResult = try await mcpClient.callTool(
            name: ToolNames.launchApp,
            arguments: ["app_name": .string("Calculator")]
        )
        guard let pid = extractPid(from: launchResult) else {
            XCTFail("Should get pid from launch_app: \(launchResult)")
            throw NSError(domain: "No pid", code: 2)
        }

        try await Task.sleep(for: .milliseconds(1500))

        // List windows to get window_id and title
        let windowsResult = try await mcpClient.callTool(
            name: ToolNames.listWindows,
            arguments: ["pid": .int(pid)]
        )
        print("🪟 list_windows: \(String(windowsResult.prefix(300)))")

        guard let (windowId, windowTitle) = extractMainWindow(from: windowsResult) else {
            XCTFail("Should get window_id from list_windows: \(windowsResult)")
            throw NSError(domain: "No window_id", code: 3)
        }

        return (pid: pid, windowId: windowId, windowTitle: windowTitle)
    }

    // MARK: - AC1 & AC2: Real screenshot + AX tree capture, stop condition evaluation

    func test_real_captureScreenshotAndAxTree() async throws {
        guard let mcpClient else { return }

        let (pid, windowId, windowTitle) = try await launchCalculator()
        print("🖥️ Calculator: pid=\(pid), windowId=\(windowId), title=\"\(windowTitle)\"")

        // Capture real screenshot
        let screenshotResult = try await mcpClient.callTool(
            name: ToolNames.screenshot,
            arguments: ["window_id": .int(windowId)]
        )
        print("📸 Screenshot: \(screenshotResult.count) bytes")

        // Capture real AX tree
        let axTreeResult = try await mcpClient.callTool(
            name: ToolNames.getAccessibilityTree,
            arguments: ["pid": .int(pid), "window_id": .int(windowId)]
        )
        XCTAssertFalse(axTreeResult.isEmpty, "AX tree should not be empty")
        print("🌳 AX tree captured: \(axTreeResult.count) chars")

        // Evaluate: textAppears with dynamic title (should appear in AX tree text fields)
        let evaluator = StopConditionEvaluator()
        let textResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .textAppears, value: windowTitle)],
            screenshot: nil, axTree: axTreeResult, executedSteps: [], maxSteps: 20
        )
        XCTAssertEqual(textResult, StopEvaluationResult.satisfied,
                       "textAppears '\(windowTitle)' should be found in AX tree. " +
                       "AX tree first 300: \(String(axTreeResult.prefix(300)))")

        // Evaluate: windowAppears with wrong name → notSatisfied
        let wrongResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .windowAppears, value: "TextEdit")],
            screenshot: nil, axTree: axTreeResult, executedSteps: [], maxSteps: 20
        )
        XCTAssertEqual(wrongResult, StopEvaluationResult.notSatisfied,
                       "windowAppears 'TextEdit' should NOT be satisfied")

        // Evaluate: custom → uncertain
        let customResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .custom, value: "Calculator is working")],
            screenshot: nil, axTree: axTreeResult, executedSteps: [], maxSteps: 20
        )
        XCTAssertEqual(customResult, StopEvaluationResult.uncertain,
                       "Custom condition should return uncertain")

        // Cleanup
        _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
    }

    // MARK: - AC1-AC5: Full TaskVerifier flow with real MCP context capture

    func test_real_taskVerifier_withRealMCP() async throws {
        guard let mcpClient else { return }

        let (pid, windowId, windowTitle) = try await launchCalculator()

        // Build executed steps simulating what StepExecutor would produce
        let executedSteps = [
            ExecutedStep(
                stepIndex: 0,
                tool: "launch_app",
                parameters: ["app_name": .string("Calculator")],
                result: "{\"pid\":\(pid),\"app_name\":\"Calculator\",\"status\":\"launched\"}",
                success: true, timestamp: Date()
            ),
            ExecutedStep(
                stepIndex: 1,
                tool: "list_windows",
                parameters: ["pid": .int(pid)],
                result: "[{\"window_id\":\(windowId),\"pid\":\(pid),\"title\":\"\(windowTitle)\"}]",
                success: true, timestamp: Date()
            )
        ]

        // Use mock LLM that returns "done" as fallback
        let mockLLM = IntegrationMockLLMClient(promptResult: """
        {"status": "done", "reason": "Calculator launched and visible"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mcpClient, llmClient: mockLLM, config: config)

        let plan = Plan(
            id: UUID(),
            task: "Launch Calculator",
            steps: [Step(index: 0, tool: "launch_app",
                         parameters: ["app_name": .string("Calculator")],
                         purpose: "Launch Calculator", expectedChange: "Calculator opens")],
            stopWhen: [StopCondition(type: .textAppears, value: windowTitle)],
            maxRetries: 3
        )

        let context = RunContext(
            planId: plan.id, currentState: .verifying,
            currentStepIndex: executedSteps.count, executedSteps: executedSteps,
            replanCount: 0, config: config
        )

        // Run TaskVerifier.verify with REAL MCP calls
        let result = try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)

        print("✅ TaskVerifier: state=\(result.state), reason=\(result.reason ?? "nil")")
        print("   screenshot: \(result.screenshotBase64 != nil), AX tree: \(result.axTreeSnapshot != nil)")

        XCTAssertNotNil(result.screenshotBase64, "Should have captured a real screenshot")
        XCTAssertNotNil(result.axTreeSnapshot, "Should have captured a real AX tree")
        XCTAssertEqual(result.state, RunState.done,
                       "TaskVerifier should return .done. Got: \(result.state), reason: \(result.reason ?? "nil")")

        // Cleanup
        _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
    }

    // MARK: - AC2: StopConditionEvaluator with real AX tree

    func test_real_stopConditionEvaluator_withRealAxTree() async throws {
        guard let mcpClient else { return }

        let (pid, windowId, windowTitle) = try await launchCalculator()

        let axTree = try await mcpClient.callTool(
            name: ToolNames.getAccessibilityTree,
            arguments: ["pid": .int(pid), "window_id": .int(windowId)]
        )
        XCTAssertFalse(axTree.isEmpty, "AX tree should not be empty")

        let evaluator = StopConditionEvaluator()

        // textAppears with dynamic title → satisfied (Calculator title appears in AX tree)
        let textResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .textAppears, value: windowTitle)],
            screenshot: nil, axTree: axTree, executedSteps: [], maxSteps: 20
        )
        XCTAssertEqual(textResult, StopEvaluationResult.satisfied,
                       "Real AX tree should contain '\(windowTitle)' text")

        // windowAppears with dynamic title → notSatisfied (Calculator has no AXWindow role)
        let windowResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .windowAppears, value: windowTitle)],
            screenshot: nil, axTree: axTree, executedSteps: [], maxSteps: 20
        )
        XCTAssertEqual(windowResult, StopEvaluationResult.notSatisfied,
                       "Real Calculator has no AXWindow node, windowAppears should return notSatisfied")

        // windowAppears "TextEdit" → notSatisfied
        let wrongResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .windowAppears, value: "TextEdit")],
            screenshot: nil, axTree: axTree, executedSteps: [], maxSteps: 20
        )
        XCTAssertEqual(wrongResult, StopEvaluationResult.notSatisfied,
                       "Real AX tree should NOT contain TextEdit window")

        // custom → uncertain
        let customResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .custom, value: "Calculator shows 0")],
            screenshot: nil, axTree: axTree, executedSteps: [], maxSteps: 20
        )
        XCTAssertEqual(customResult, StopEvaluationResult.uncertain,
                       "Custom condition should return uncertain")

        // Cleanup
        _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
    }

    // MARK: - JSON Parsing Helpers

    private func extractPid(from json: String) -> Int? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj["pid"] as? Int
    }

    /// Extracts the main window (non-empty title, reasonable size) from list_windows result.
    /// Handles both real MCP array format and mock {"windows": [...]} format.
    private func extractMainWindow(from json: String) -> (windowId: Int, title: String)? {
        guard let data = json.data(using: .utf8) else { return nil }

        var windows: [[String: Any]]?

        // Real MCP format: JSON array
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            windows = arr
        }
        // Mock format: {"windows": [...]}
        else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let arr = obj["windows"] as? [[String: Any]] {
            windows = arr
        }

        guard let windows else { return nil }

        // Pick first window with non-empty title and reasonable height (>50px, not menu bar)
        let main = windows.first(where: { win in
            guard let title = win["title"] as? String, !title.isEmpty else { return false }
            if let bounds = win["bounds"] as? [String: Any],
               let h = bounds["height"] as? Int { return h > 50 }
            return true
        }) ?? windows.first

        guard let windowId = main?["window_id"] as? Int,
              let title = main?["title"] as? String else { return nil }
        return (windowId: windowId, title: title)
    }
}

// Dedicated mock to avoid redeclaration with TaskVerifierTests
private struct IntegrationMockLLMClient: LLMClientProtocol {
    let promptResult: String
    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String {
        return promptResult
    }
}
