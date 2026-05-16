import Foundation
import Testing
@testable import AxionCLI
@testable import AxionCore

@Suite("Verifier Integration")
struct VerifierIntegrationTests {

    // MARK: - Helper → MCPClientProtocol Adapter

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

    // MARK: - Setup Helper

    private func setUpMCPClient() async throws -> (HelperProcessManager, RealMCPAdapter) {
        let mgr = HelperProcessManager()
        do {
            try await mgr.start()
        } catch {
            throw NSError(domain: "AxionHelper not available", code: 1)
        }

        let running = await mgr.isRunning()
        #expect(running, "Helper should be running after start()")

        let tools = try await mgr.listTools()
        #expect(tools.contains(ToolNames.screenshot), "Helper should expose 'screenshot' tool")
        #expect(tools.contains(ToolNames.getAccessibilityTree), "Helper should expose 'get_accessibility_tree' tool")

        return (mgr, RealMCPAdapter(manager: mgr))
    }

    // MARK: - Helper: Launch Calculator and return (pid, windowId, windowTitle)

    private func launchCalculator(mcpClient: RealMCPAdapter) async throws -> (pid: Int, windowId: Int, windowTitle: String) {
        let launchResult = try await mcpClient.callTool(
            name: ToolNames.launchApp,
            arguments: ["app_name": .string("Calculator")]
        )
        guard let pid = extractPid(from: launchResult) else {
            Issue.record("Should get pid from launch_app: \(launchResult)")
            throw NSError(domain: "No pid", code: 2)
        }

        try await Task.sleep(for: .milliseconds(1500))

        let windowsResult = try await mcpClient.callTool(
            name: ToolNames.listWindows,
            arguments: ["pid": .int(pid)]
        )
        print("🪟 list_windows: \(String(windowsResult.prefix(300)))")

        guard let (windowId, windowTitle) = extractMainWindow(from: windowsResult) else {
            Issue.record("Should get window_id from list_windows: \(windowsResult)")
            throw NSError(domain: "No window_id", code: 3)
        }

        return (pid: pid, windowId: windowId, windowTitle: windowTitle)
    }

    // MARK: - AC1 & AC2: Real screenshot + AX tree capture, stop condition evaluation

    @Test("real capture screenshot and AX tree")
    func realCaptureScreenshotAndAxTree() async throws {
        let (manager, mcpClient) = try await setUpMCPClient()
        defer { Task { await manager.stop() } }

        let (pid, windowId, windowTitle) = try await launchCalculator(mcpClient: mcpClient)
        print("🖥️ Calculator: pid=\(pid), windowId=\(windowId), title=\"\(windowTitle)\"")

        let screenshotResult = try await mcpClient.callTool(
            name: ToolNames.screenshot,
            arguments: ["window_id": .int(windowId)]
        )
        print("📸 Screenshot: \(screenshotResult.count) bytes")

        let axTreeResult = try await mcpClient.callTool(
            name: ToolNames.getAccessibilityTree,
            arguments: ["pid": .int(pid), "window_id": .int(windowId)]
        )
        #expect(!axTreeResult.isEmpty, "AX tree should not be empty")
        print("🌳 AX tree captured: \(axTreeResult.count) chars")

        let evaluator = StopConditionEvaluator()
        let textResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .textAppears, value: windowTitle)],
            screenshot: nil, axTree: axTreeResult, executedSteps: [], maxSteps: 20
        )
        #expect(textResult == StopEvaluationResult.satisfied,
                "textAppears '\(windowTitle)' should be found in AX tree.")

        let wrongResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .windowAppears, value: "TextEdit")],
            screenshot: nil, axTree: axTreeResult, executedSteps: [], maxSteps: 20
        )
        #expect(wrongResult == StopEvaluationResult.notSatisfied,
                "windowAppears 'TextEdit' should NOT be satisfied")

        let customResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .custom, value: "Calculator is working")],
            screenshot: nil, axTree: axTreeResult, executedSteps: [], maxSteps: 20
        )
        #expect(customResult == StopEvaluationResult.uncertain,
                "Custom condition should return uncertain")

        _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
    }

    // MARK: - AC1-AC5: Full TaskVerifier flow with real MCP context capture

    @Test("real taskVerifier with real MCP")
    func realTaskVerifierWithRealMCP() async throws {
        let (manager, mcpClient) = try await setUpMCPClient()
        defer { Task { await manager.stop() } }

        let (pid, windowId, windowTitle) = try await launchCalculator(mcpClient: mcpClient)

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

        let result = try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)

        print("✅ TaskVerifier: state=\(result.state), reason=\(result.reason ?? "nil")")
        print("   screenshot: \(result.screenshotBase64 != nil), AX tree: \(result.axTreeSnapshot != nil)")

        #expect(result.screenshotBase64 != nil, "Should have captured a real screenshot")
        #expect(result.axTreeSnapshot != nil, "Should have captured a real AX tree")
        #expect(result.state == RunState.done,
                "TaskVerifier should return .done. Got: \(result.state), reason: \(result.reason ?? "nil")")

        _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
    }

    // MARK: - AC2: StopConditionEvaluator with real AX tree

    @Test("real stop condition evaluator with real AX tree")
    func realStopConditionEvaluatorWithRealAxTree() async throws {
        let (manager, mcpClient) = try await setUpMCPClient()
        defer { Task { await manager.stop() } }

        let (pid, windowId, windowTitle) = try await launchCalculator(mcpClient: mcpClient)

        let axTree = try await mcpClient.callTool(
            name: ToolNames.getAccessibilityTree,
            arguments: ["pid": .int(pid), "window_id": .int(windowId)]
        )
        #expect(!axTree.isEmpty, "AX tree should not be empty")

        let evaluator = StopConditionEvaluator()

        let textResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .textAppears, value: windowTitle)],
            screenshot: nil, axTree: axTree, executedSteps: [], maxSteps: 20
        )
        #expect(textResult == StopEvaluationResult.satisfied,
                "Real AX tree should contain '\(windowTitle)' text")

        let windowResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .windowAppears, value: windowTitle)],
            screenshot: nil, axTree: axTree, executedSteps: [], maxSteps: 20
        )
        #expect(windowResult == StopEvaluationResult.satisfied,
                "Real Calculator AX tree should contain AXWindow with title '\(windowTitle)'")

        let wrongResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .windowAppears, value: "TextEdit")],
            screenshot: nil, axTree: axTree, executedSteps: [], maxSteps: 20
        )
        #expect(wrongResult == StopEvaluationResult.notSatisfied,
                "Real AX tree should NOT contain TextEdit window")

        let customResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .custom, value: "Calculator shows 0")],
            screenshot: nil, axTree: axTree, executedSteps: [], maxSteps: 20
        )
        #expect(customResult == StopEvaluationResult.uncertain,
                "Custom condition should return uncertain")

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

    private func extractMainWindow(from json: String) -> (windowId: Int, title: String)? {
        guard let data = json.data(using: .utf8) else { return nil }

        var windows: [[String: Any]]?

        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            windows = arr
        }
        else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let arr = obj["windows"] as? [[String: Any]] {
            windows = arr
        }

        guard let windows else { return nil }

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
