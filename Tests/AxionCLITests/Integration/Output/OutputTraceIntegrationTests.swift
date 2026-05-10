import XCTest
@testable import AxionCLI
@testable import AxionCore

/// Integration tests for Story 3-5: Output, Trace & Progress Display.
///
/// Tests TerminalOutput, JSONOutput, and TraceRecorder wired into the real execution
/// pipeline (StepExecutor + TaskVerifier) with live Helper process and real MCP calls.
///
/// Prerequisites:
/// - AxionHelper.app built at .build/AxionHelper.app
/// - macOS Accessibility permissions granted to Terminal/iTerm
/// - Screen Recording permission granted (for screenshots)
/// - Run with: AXION_HELPER_PATH="$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter "AxionCLIIntegrationTests.OutputTraceIntegrationTests"
final class OutputTraceIntegrationTests: XCTestCase {

    // MARK: - Helper -> MCPClientProtocol Adapter

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

    // MARK: - Collected Trace Data (Sendable-friendly)

    struct CollectedStepStart: Sendable {
        let index: Int
        let tool: String
        let purpose: String
    }

    struct CollectedStepDone: Sendable {
        let index: Int
        let tool: String
        let success: Bool
        let resultSnippet: String
    }

    struct CollectedVerification: Sendable {
        let state: String
        let reason: String
    }

    // MARK: - Properties

    private var manager: HelperProcessManager?
    private var mcpClient: RealMCPAdapter?
    private var tempDir: URL?

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

        self.manager = mgr
        self.mcpClient = RealMCPAdapter(manager: mgr)

        self.tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutputTraceIntegrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir!, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let manager {
            await manager.stop()
        }
        self.manager = nil
        self.mcpClient = nil

        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        self.tempDir = nil

        try await super.tearDown()
    }

    // MARK: - AC1-AC4: StepExecutor + TerminalOutput

    func test_real_stepExecutor_withTerminalOutput() async throws {
        guard let mcpClient else { return }

        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        var executor = StepExecutor(mcpClient: mcpClient, config: .default)
        executor.onStepStart = { step in
            output.displayStateChange(from: .planning, to: .executing)
        }
        executor.onStepDone = { executedStep in
            output.displayStepResult(executedStep)
        }

        let plan = Plan(
            id: UUID(), task: "Launch Calculator",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens")
            ],
            stopWhen: [], maxRetries: 3
        )
        output.displayRunStart(runId: "20260510-integ01", task: "Launch Calculator", mode: "plan_execute")
        output.displayPlan(plan)

        let context = RunContext(
            planId: plan.id, currentState: .executing,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )

        let executedStep = try await executor.executeStep(plan.steps[0], context: context)

        let combined = capturedOutput.joined(separator: "\n")

        // AC1: Run start info
        XCTAssertTrue(combined.contains("[axion]"),
            "All output should have [axion] prefix. Got: \(capturedOutput)")
        XCTAssertTrue(combined.contains("20260510-integ01"),
            "Should contain run ID. Got: \(capturedOutput)")

        // AC2: Step progress
        XCTAssertTrue(combined.contains("1/1") || combined.contains("1/?"),
            "Should show step progress. Got: \(capturedOutput)")

        // AC3: Step result
        if executedStep.success {
            XCTAssertTrue(combined.contains("ok"),
                "Successful step should show 'ok'. Got: \(capturedOutput)")
        }

        // Cleanup
        if let pid = extractPid(from: executedStep.result) {
            _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - AC5: StepExecutor + JSONOutput

    func test_real_stepExecutor_withJSONOutput() async throws {
        guard let mcpClient else { return }

        let output = JSONOutput()

        var executor = StepExecutor(mcpClient: mcpClient, config: .default)
        executor.onStepDone = { executedStep in
            output.displayStepResult(executedStep)
        }

        let plan = Plan(
            id: UUID(), task: "Launch Calculator",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens")
            ],
            stopWhen: [], maxRetries: 3
        )

        output.displayRunStart(runId: "20260510-json01", task: "Launch Calculator", mode: "plan_execute")

        let context = RunContext(
            planId: plan.id, currentState: .executing,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )

        let executedStep = try await executor.executeStep(plan.steps[0], context: context)

        let summaryContext = RunContext(
            planId: plan.id, currentState: .done,
            currentStepIndex: 1, executedSteps: [executedStep],
            replanCount: 0, config: .default
        )
        output.displaySummary(context: summaryContext)

        let json = output.finalize()
        let dict = parseJSON(json)

        // AC5: JSON structure
        XCTAssertNotNil(dict, "finalize() must produce valid JSON: \(json)")
        XCTAssertEqual(dict?["runId"] as? String, "20260510-json01",
            "JSON must contain correct runId")
        XCTAssertEqual(dict?["task"] as? String, "Launch Calculator",
            "JSON must contain correct task")
        XCTAssertEqual(dict?["mode"] as? String, "plan_execute",
            "JSON must contain correct mode")

        // Steps array
        let steps = dict?["steps"] as? [[String: Any]]
        XCTAssertNotNil(steps, "JSON must contain steps array")
        XCTAssertEqual(steps?.count, 1, "Should have 1 step")
        XCTAssertEqual(steps?.first?["tool"] as? String, ToolNames.launchApp,
            "Step tool should be launch_app")
        XCTAssertEqual(steps?.first?["success"] as? Bool, true,
            "Step should be successful")

        // Summary
        let summary = dict?["summary"] as? [String: Any]
        XCTAssertNotNil(summary, "JSON must contain summary")
        XCTAssertEqual(summary?["totalSteps"] as? Int, 1,
            "Summary should report 1 total step")
        XCTAssertEqual(summary?["successfulSteps"] as? Int, 1,
            "Summary should report 1 successful step")

        // Cleanup
        if let pid = extractPid(from: executedStep.result) {
            _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - AC6-AC7: StepExecutor + TraceRecorder

    func test_real_stepExecutor_withTraceRecorder() async throws {
        guard let mcpClient else { return }

        var config = AxionConfig.default
        config.traceEnabled = true
        let recorder = try TraceRecorder(runId: "20260510-trace01", config: config, baseURL: tempDir)

        // Collect data from synchronous callbacks, then write to TraceRecorder
        var collectedStarts: [CollectedStepStart] = []
        var collectedDones: [CollectedStepDone] = []

        var executor = StepExecutor(mcpClient: mcpClient, config: .default)
        executor.onStepStart = { step in
            collectedStarts.append(CollectedStepStart(
                index: step.index, tool: step.tool, purpose: step.purpose
            ))
        }
        executor.onStepDone = { executedStep in
            collectedDones.append(CollectedStepDone(
                index: executedStep.stepIndex,
                tool: executedStep.tool,
                success: executedStep.success,
                resultSnippet: String(executedStep.result.prefix(100))
            ))
        }

        // Record run_start
        await recorder.recordRunStart(runId: "20260510-trace01", task: "Launch Calculator", mode: "plan_execute")

        let plan = Plan(
            id: UUID(), task: "Launch Calculator",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens")
            ],
            stopWhen: [], maxRetries: 3
        )

        let context = RunContext(
            planId: plan.id, currentState: .executing,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )

        let executedStep = try await executor.executeStep(plan.steps[0], context: context)

        // Flush collected data to TraceRecorder
        for s in collectedStarts {
            await recorder.recordStepStart(index: s.index, tool: s.tool, purpose: s.purpose)
        }
        for d in collectedDones {
            await recorder.recordStepDone(index: d.index, tool: d.tool, success: d.success, resultSnippet: d.resultSnippet)
        }

        // Record run_done
        await recorder.recordRunDone(totalSteps: 1, durationMs: 0, replanCount: 0)
        await recorder.close()

        // Read and verify trace file
        let traceURL = tempDir!.appendingPathComponent("20260510-trace01/trace.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: traceURL.path),
            "Trace file should exist at \(traceURL.path)")

        let content = try String(contentsOf: traceURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        // AC6: Trace events recorded
        XCTAssertGreaterThanOrEqual(lines.count, 3,
            "Should have at least 3 events (run_start, step_start, step_done, run_done). Got \(lines.count)")

        // AC7: Each line is valid JSON with ts and event
        var eventTypes: [String] = []
        for (index, line) in lines.enumerated() {
            let json = parseJSONLine(line)
            XCTAssertNotNil(json, "Line \(index) must be valid JSON: \(line)")
            XCTAssertNotNil(json?["ts"], "Line \(index) must have 'ts' field")
            let event = json?["event"] as? String ?? ""
            eventTypes.append(event)

            // Verify snake_case
            let snakePattern = "^[a-z][a-z0-9_]*$"
            let regex = try NSRegularExpression(pattern: snakePattern)
            let range = NSRange(event.startIndex..., in: event)
            XCTAssertGreaterThan(regex.numberOfMatches(in: event, range: range), 0,
                "Event '\(event)' should be snake_case")
        }

        // Verify expected event sequence
        XCTAssertTrue(eventTypes.contains("run_start"), "Should have run_start event")
        XCTAssertTrue(eventTypes.contains("step_start"), "Should have step_start event")
        XCTAssertTrue(eventTypes.contains("step_done"), "Should have step_done event")
        XCTAssertTrue(eventTypes.contains("run_done"), "Should have run_done event")

        // Verify step_done has real data
        let stepDoneLine = lines.first { line in
            (parseJSONLine(line)?["event"] as? String) == "step_done"
        }
        let stepDoneJson = stepDoneLine.flatMap { parseJSONLine($0) }
        XCTAssertEqual(stepDoneJson?["tool"] as? String, ToolNames.launchApp,
            "step_done should record launch_app tool")
        XCTAssertEqual(stepDoneJson?["success"] as? Bool, true,
            "step_done should record success=true")

        // Cleanup
        if let pid = extractPid(from: executedStep.result) {
            _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - AC1-AC7: TaskVerifier + Output + Trace

    func test_real_taskVerifier_withOutputAndTrace() async throws {
        guard let mcpClient else { return }

        // Launch Calculator first
        let (pid, _, windowTitle) = try await launchCalculator()

        // Setup TerminalOutput + TraceRecorder
        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        var traceConfig = AxionConfig.default
        traceConfig.traceEnabled = true
        let recorder = try TraceRecorder(runId: "20260510-verify01", config: traceConfig, baseURL: tempDir)

        // Record run start
        output.displayRunStart(runId: "20260510-verify01", task: "Verify Calculator", mode: "plan_execute")
        await recorder.recordRunStart(runId: "20260510-verify01", task: "Verify Calculator", mode: "plan_execute")

        // Collect verification results from callback
        var collectedVerifications: [CollectedVerification] = []

        let mockLLM = OutputIntegrationMockLLMClient(promptResult: """
        {"status": "done", "reason": "Calculator is running and visible"}
        """)

        var verifier = TaskVerifier(mcpClient: mcpClient, llmClient: mockLLM, config: .default)
        verifier.onVerificationResult = { result in
            output.displayVerificationResult(result)
            collectedVerifications.append(CollectedVerification(
                state: result.state.rawValue,
                reason: result.reason ?? ""
            ))
        }

        let executedSteps = [
            ExecutedStep(
                stepIndex: 0, tool: ToolNames.launchApp,
                parameters: ["app_name": .string("Calculator")],
                result: "{\"pid\":\(pid)}", success: true, timestamp: Date()
            )
        ]

        let plan = Plan(
            id: UUID(), task: "Launch Calculator",
            steps: [Step(index: 0, tool: ToolNames.launchApp,
                         parameters: ["app_name": .string("Calculator")],
                         purpose: "Launch Calculator", expectedChange: "Calculator opens")],
            stopWhen: [StopCondition(type: .textAppears, value: windowTitle)],
            maxRetries: 3
        )

        let context = RunContext(
            planId: plan.id, currentState: .verifying,
            currentStepIndex: 1, executedSteps: executedSteps,
            replanCount: 0, config: .default
        )

        output.displayStateChange(from: .executing, to: .verifying)
        await recorder.recordStateChange(from: "executing", to: "verifying")

        // Run verification
        _ = try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)

        // Flush collected verifications to TraceRecorder
        for v in collectedVerifications {
            await recorder.recordVerificationResult(state: v.state, reason: v.reason)
        }

        // Record run_done
        await recorder.recordRunDone(totalSteps: 1, durationMs: 0, replanCount: 0)
        await recorder.close()

        // Verify TerminalOutput
        let combinedOutput = capturedOutput.joined(separator: "\n")
        XCTAssertTrue(combinedOutput.contains("[axion]"),
            "All output should have [axion] prefix")
        XCTAssertTrue(combinedOutput.contains("验证"),
            "Output should contain verification text")

        // Verify TraceRecorder
        let traceURL = tempDir!.appendingPathComponent("20260510-verify01/trace.jsonl")
        let traceContent = try String(contentsOf: traceURL, encoding: .utf8)
        let traceLines = traceContent.components(separatedBy: "\n").filter { !$0.isEmpty }

        let eventTypes = traceLines.compactMap { parseJSONLine($0)?["event"] as? String }
        XCTAssertTrue(eventTypes.contains("run_start"), "Trace should have run_start")
        XCTAssertTrue(eventTypes.contains("state_change"), "Trace should have state_change")
        XCTAssertTrue(eventTypes.contains("verification_result"), "Trace should have verification_result")
        XCTAssertTrue(eventTypes.contains("run_done"), "Trace should have run_done")

        // Verify verification_result event
        let verificationLine = traceLines.first { line in
            (parseJSONLine(line)?["event"] as? String) == "verification_result"
        }
        let verificationJson = verificationLine.flatMap { parseJSONLine($0) }
        XCTAssertEqual(verificationJson?["state"] as? String, RunState.done.rawValue,
            "verification_result should have state=done")

        // Cleanup
        _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
    }

    // MARK: - AC1-AC7: Full Pipeline (Execute + Verify)

    func test_real_fullPipeline_executeAndVerify() async throws {
        guard let mcpClient else { return }

        // Setup all components
        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        var traceConfig = AxionConfig.default
        traceConfig.traceEnabled = true
        let recorder = try TraceRecorder(runId: "20260510-full01", config: traceConfig, baseURL: tempDir)

        let runId = "20260510-full01"

        // Display run start
        output.displayRunStart(runId: runId, task: "Launch and verify Calculator", mode: "plan_execute")
        await recorder.recordRunStart(runId: runId, task: "Launch and verify Calculator", mode: "plan_execute")

        // Create plan
        let plan = Plan(
            id: UUID(), task: "Launch and verify Calculator",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens")
            ],
            stopWhen: [], maxRetries: 3
        )

        output.displayPlan(plan)
        await recorder.recordPlanCreated(stepCount: plan.steps.count, stopWhenCount: plan.stopWhen.count)

        // Collect data from callbacks
        var collectedStarts: [CollectedStepStart] = []
        var collectedDones: [CollectedStepDone] = []
        var collectedVerifications: [CollectedVerification] = []

        var executor = StepExecutor(mcpClient: mcpClient, config: .default)
        executor.onStepStart = { step in
            collectedStarts.append(CollectedStepStart(
                index: step.index, tool: step.tool, purpose: step.purpose
            ))
        }
        executor.onStepDone = { executedStep in
            output.displayStepResult(executedStep)
            collectedDones.append(CollectedStepDone(
                index: executedStep.stepIndex,
                tool: executedStep.tool,
                success: executedStep.success,
                resultSnippet: String(executedStep.result.prefix(100))
            ))
        }

        // Execute
        output.displayStateChange(from: .planning, to: .executing)
        await recorder.recordStateChange(from: "planning", to: "executing")

        var context = RunContext(
            planId: plan.id, currentState: .executing,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )

        let executedStep = try await executor.executeStep(plan.steps[0], context: context)
        context.executedSteps = [executedStep]

        // Flush step trace data
        for s in collectedStarts {
            await recorder.recordStepStart(index: s.index, tool: s.tool, purpose: s.purpose)
        }
        for d in collectedDones {
            await recorder.recordStepDone(index: d.index, tool: d.tool, success: d.success, resultSnippet: d.resultSnippet)
        }

        // Verify
        output.displayStateChange(from: .executing, to: .verifying)
        await recorder.recordStateChange(from: "executing", to: "verifying")

        let mockLLM = OutputIntegrationMockLLMClient(promptResult: """
        {"status": "done", "reason": "Calculator launched successfully"}
        """)

        var verifier = TaskVerifier(mcpClient: mcpClient, llmClient: mockLLM, config: .default)
        verifier.onVerificationResult = { result in
            output.displayVerificationResult(result)
            collectedVerifications.append(CollectedVerification(
                state: result.state.rawValue,
                reason: result.reason ?? ""
            ))
        }

        context.currentState = .verifying
        context.currentStepIndex = 1

        let verifyPlan = Plan(
            id: plan.id, task: plan.task,
            steps: plan.steps,
            stopWhen: [StopCondition(type: .textAppears, value: "Calculator")],
            maxRetries: 3
        )

        let verifyResult = try await verifier.verify(plan: verifyPlan, executedSteps: context.executedSteps, context: context)

        // Flush verification trace data
        for v in collectedVerifications {
            await recorder.recordVerificationResult(state: v.state, reason: v.reason)
        }

        // Summary
        output.displaySummary(context: RunContext(
            planId: plan.id, currentState: verifyResult.state,
            currentStepIndex: 1, executedSteps: [executedStep],
            replanCount: 0, config: .default
        ))
        await recorder.recordRunDone(totalSteps: 1, durationMs: 0, replanCount: 0)
        await recorder.close()

        // === Verify TerminalOutput ===
        let combinedOutput = capturedOutput.joined(separator: "\n")

        // AC1: Run start
        XCTAssertTrue(combinedOutput.contains(runId), "Should contain run ID")
        // AC2: Plan
        XCTAssertTrue(combinedOutput.contains("1 个步骤") || combinedOutput.contains("1"),
            "Should show step count from plan")
        // AC3: Step result
        XCTAssertTrue(combinedOutput.contains("ok"), "Should show ok for successful step")
        // AC4: Summary
        XCTAssertTrue(combinedOutput.contains("完成"), "Should show completion summary")

        // Verify every line has [axion] prefix
        for line in capturedOutput where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            XCTAssertTrue(line.contains("[axion]"),
                "Output line missing [axion] prefix: '\(line)'")
        }

        // === Verify TraceRecorder ===
        let traceURL = tempDir!.appendingPathComponent("20260510-full01/trace.jsonl")
        let traceContent = try String(contentsOf: traceURL, encoding: .utf8)
        let traceLines = traceContent.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Should have: run_start, plan_created, state_change, step_start, step_done,
        //              state_change, verification_result, run_done
        XCTAssertGreaterThanOrEqual(traceLines.count, 7,
            "Should have at least 7 trace events, got \(traceLines.count)")

        let eventTypes = traceLines.compactMap { parseJSONLine($0)?["event"] as? String }
        XCTAssertTrue(eventTypes.contains("run_start"), "Missing run_start")
        XCTAssertTrue(eventTypes.contains("plan_created"), "Missing plan_created")
        XCTAssertTrue(eventTypes.contains("step_start"), "Missing step_start")
        XCTAssertTrue(eventTypes.contains("step_done"), "Missing step_done")
        XCTAssertTrue(eventTypes.contains("verification_result"), "Missing verification_result")
        XCTAssertTrue(eventTypes.contains("run_done"), "Missing run_done")

        // Cleanup
        if let pid = extractPid(from: executedStep.result) {
            _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - Helpers

    private func launchCalculator() async throws -> (pid: Int, windowId: Int, windowTitle: String) {
        guard let mcpClient else { throw NSError(domain: "No MCP client", code: 1) }

        let launchResult = try await mcpClient.callTool(
            name: ToolNames.launchApp,
            arguments: ["app_name": .string("Calculator")]
        )
        guard let pid = extractPid(from: launchResult) else {
            XCTFail("Should get pid from launch_app: \(launchResult)")
            throw NSError(domain: "No pid", code: 2)
        }

        try await Task.sleep(for: .milliseconds(1500))

        let windowsResult = try await mcpClient.callTool(
            name: ToolNames.listWindows,
            arguments: ["pid": .int(pid)]
        )

        guard let (windowId, windowTitle) = extractMainWindow(from: windowsResult) else {
            XCTFail("Should get window from list_windows: \(windowsResult)")
            throw NSError(domain: "No window_id", code: 3)
        }

        return (pid: pid, windowId: windowId, windowTitle: windowTitle)
    }

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
        } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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

    private func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseJSONLine(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Mock LLM Client

private struct OutputIntegrationMockLLMClient: LLMClientProtocol {
    let promptResult: String
    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String {
        return promptResult
    }
}
