import Foundation
import Testing
@testable import AxionCLI
@testable import AxionCore

@Suite("Output & Trace Integration")
struct OutputTraceIntegrationTests {

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

    // MARK: - Setup Helper

    private func setUpMCPClient() async throws -> (HelperProcessManager, RealMCPAdapter, URL) {
        let mgr = HelperProcessManager()
        do {
            try await mgr.start()
        } catch {
            throw NSError(domain: "AxionHelper not available", code: 1)
        }

        let running = await mgr.isRunning()
        #expect(running, "Helper should be running after start()")

        let mcpClient = RealMCPAdapter(manager: mgr)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutputTraceIntegrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        return (mgr, mcpClient, tempDir)
    }

    // MARK: - AC1-AC4: StepExecutor + TerminalOutput

    @Test("real stepExecutor with TerminalOutput")
    func realStepExecutorWithTerminalOutput() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

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

        #expect(combined.contains("[axion]"),
                "All output should have [axion] prefix. Got: \(capturedOutput)")
        #expect(combined.contains("20260510-integ01"),
                "Should contain run ID. Got: \(capturedOutput)")
        #expect(combined.contains("1/1") || combined.contains("1/?"),
                "Should show step progress. Got: \(capturedOutput)")

        if executedStep.success {
            #expect(combined.contains("ok"),
                    "Successful step should show 'ok'. Got: \(capturedOutput)")
        }

        if let pid = extractPid(from: executedStep.result) {
            _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - AC5: StepExecutor + JSONOutput

    @Test("real stepExecutor with JSONOutput")
    func realStepExecutorWithJSONOutput() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

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

        #expect(dict != nil, "finalize() must produce valid JSON: \(json)")
        #expect(dict?["runId"] as? String == "20260510-json01",
                "JSON must contain correct runId")
        #expect(dict?["task"] as? String == "Launch Calculator",
                "JSON must contain correct task")
        #expect(dict?["mode"] as? String == "plan_execute",
                "JSON must contain correct mode")

        let steps = dict?["steps"] as? [[String: Any]]
        #expect(steps != nil, "JSON must contain steps array")
        #expect(steps?.count == 1, "Should have 1 step")
        #expect(steps?.first?["tool"] as? String == ToolNames.launchApp,
                "Step tool should be launch_app")
        #expect(steps?.first?["success"] as? Bool == true,
                "Step should be successful")

        let summary = dict?["summary"] as? [String: Any]
        #expect(summary != nil, "JSON must contain summary")
        #expect(summary?["totalSteps"] as? Int == 1,
                "Summary should report 1 total step")
        #expect(summary?["successfulSteps"] as? Int == 1,
                "Summary should report 1 successful step")

        if let pid = extractPid(from: executedStep.result) {
            _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - AC6-AC7: StepExecutor + TraceRecorder

    @Test("real stepExecutor with TraceRecorder")
    func realStepExecutorWithTraceRecorder() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        var config = AxionConfig.default
        config.traceEnabled = true
        let recorder = try TraceRecorder(runId: "20260510-trace01", config: config, baseURL: tempDir)

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

        for s in collectedStarts {
            await recorder.recordStepStart(index: s.index, tool: s.tool, purpose: s.purpose)
        }
        for d in collectedDones {
            await recorder.recordStepDone(index: d.index, tool: d.tool, success: d.success, resultSnippet: d.resultSnippet)
        }

        await recorder.recordRunDone(totalSteps: 1, durationMs: 0, replanCount: 0)
        await recorder.close()

        let traceURL = tempDir.appendingPathComponent("20260510-trace01/trace.jsonl")
        #expect(FileManager.default.fileExists(atPath: traceURL.path),
                "Trace file should exist at \(traceURL.path)")

        let content = try String(contentsOf: traceURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        #expect(lines.count >= 3,
                "Should have at least 3 events (run_start, step_start, step_done, run_done). Got \(lines.count)")

        var eventTypes: [String] = []
        for (index, line) in lines.enumerated() {
            let json = parseJSONLine(line)
            #expect(json != nil, "Line \(index) must be valid JSON: \(line)")
            #expect(json?["ts"] != nil, "Line \(index) must have 'ts' field")
            let event = json?["event"] as? String ?? ""
            eventTypes.append(event)

            let snakePattern = "^[a-z][a-z0-9_]*$"
            let regex = try NSRegularExpression(pattern: snakePattern)
            let range = NSRange(event.startIndex..., in: event)
            #expect(regex.numberOfMatches(in: event, range: range) > 0,
                    "Event '\(event)' should be snake_case")
        }

        #expect(eventTypes.contains("run_start"), "Should have run_start event")
        #expect(eventTypes.contains("step_start"), "Should have step_start event")
        #expect(eventTypes.contains("step_done"), "Should have step_done event")
        #expect(eventTypes.contains("run_done"), "Should have run_done event")

        let stepDoneLine = lines.first { line in
            (parseJSONLine(line)?["event"] as? String) == "step_done"
        }
        let stepDoneJson = stepDoneLine.flatMap { parseJSONLine($0) }
        #expect(stepDoneJson?["tool"] as? String == ToolNames.launchApp,
                "step_done should record launch_app tool")
        #expect(stepDoneJson?["success"] as? Bool == true,
                "step_done should record success=true")

        if let pid = extractPid(from: executedStep.result) {
            _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - AC1-AC7: TaskVerifier + Output + Trace

    @Test("real taskVerifier with output and trace")
    func realTaskVerifierWithOutputAndTrace() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let (pid, _, windowTitle) = try await launchCalculator(mcpClient: mcpClient)

        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        var traceConfig = AxionConfig.default
        traceConfig.traceEnabled = true
        let recorder = try TraceRecorder(runId: "20260510-verify01", config: traceConfig, baseURL: tempDir)

        output.displayRunStart(runId: "20260510-verify01", task: "Verify Calculator", mode: "plan_execute")
        await recorder.recordRunStart(runId: "20260510-verify01", task: "Verify Calculator", mode: "plan_execute")

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

        _ = try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)

        for v in collectedVerifications {
            await recorder.recordVerificationResult(state: v.state, reason: v.reason)
        }

        await recorder.recordRunDone(totalSteps: 1, durationMs: 0, replanCount: 0)
        await recorder.close()

        let combinedOutput = capturedOutput.joined(separator: "\n")
        #expect(combinedOutput.contains("[axion]"),
                "All output should have [axion] prefix")
        #expect(combinedOutput.contains("验证"),
                "Output should contain verification text")

        let traceURL = tempDir.appendingPathComponent("20260510-verify01/trace.jsonl")
        let traceContent = try String(contentsOf: traceURL, encoding: .utf8)
        let traceLines = traceContent.components(separatedBy: "\n").filter { !$0.isEmpty }

        let eventTypes = traceLines.compactMap { parseJSONLine($0)?["event"] as? String }
        #expect(eventTypes.contains("run_start"), "Trace should have run_start")
        #expect(eventTypes.contains("state_change"), "Trace should have state_change")
        #expect(eventTypes.contains("verification_result"), "Trace should have verification_result")
        #expect(eventTypes.contains("run_done"), "Trace should have run_done")

        let verificationLine = traceLines.first { line in
            (parseJSONLine(line)?["event"] as? String) == "verification_result"
        }
        let verificationJson = verificationLine.flatMap { parseJSONLine($0) }
        #expect(verificationJson?["state"] as? String == RunState.done.rawValue,
                "verification_result should have state=done")

        _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
    }

    // MARK: - AC1-AC7: Full Pipeline (Execute + Verify)

    @Test("real full pipeline execute and verify")
    func realFullPipelineExecuteAndVerify() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        var traceConfig = AxionConfig.default
        traceConfig.traceEnabled = true
        let recorder = try TraceRecorder(runId: "20260510-full01", config: traceConfig, baseURL: tempDir)

        let runId = "20260510-full01"

        output.displayRunStart(runId: runId, task: "Launch and verify Calculator", mode: "plan_execute")
        await recorder.recordRunStart(runId: runId, task: "Launch and verify Calculator", mode: "plan_execute")

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

        output.displayStateChange(from: .planning, to: .executing)
        await recorder.recordStateChange(from: "planning", to: "executing")

        var context = RunContext(
            planId: plan.id, currentState: .executing,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )

        let executedStep = try await executor.executeStep(plan.steps[0], context: context)
        context.executedSteps = [executedStep]

        for s in collectedStarts {
            await recorder.recordStepStart(index: s.index, tool: s.tool, purpose: s.purpose)
        }
        for d in collectedDones {
            await recorder.recordStepDone(index: d.index, tool: d.tool, success: d.success, resultSnippet: d.resultSnippet)
        }

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

        for v in collectedVerifications {
            await recorder.recordVerificationResult(state: v.state, reason: v.reason)
        }

        output.displaySummary(context: RunContext(
            planId: plan.id, currentState: verifyResult.state,
            currentStepIndex: 1, executedSteps: [executedStep],
            replanCount: 0, config: .default
        ))
        await recorder.recordRunDone(totalSteps: 1, durationMs: 0, replanCount: 0)
        await recorder.close()

        // === Verify TerminalOutput ===
        let combinedOutput = capturedOutput.joined(separator: "\n")

        #expect(combinedOutput.contains(runId), "Should contain run ID")
        #expect(combinedOutput.contains("1 个步骤") || combinedOutput.contains("1"),
                "Should show step count from plan")
        #expect(combinedOutput.contains("ok"), "Should show ok for successful step")
        #expect(combinedOutput.contains("完成"), "Should show completion summary")

        for line in capturedOutput where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            #expect(line.contains("[axion]"),
                    "Output line missing [axion] prefix: '\(line)'")
        }

        // === Verify TraceRecorder ===
        let traceURL = tempDir.appendingPathComponent("20260510-full01/trace.jsonl")
        let traceContent = try String(contentsOf: traceURL, encoding: .utf8)
        let traceLines = traceContent.components(separatedBy: "\n").filter { !$0.isEmpty }

        #expect(traceLines.count >= 7,
                "Should have at least 7 trace events, got \(traceLines.count)")

        let eventTypes = traceLines.compactMap { parseJSONLine($0)?["event"] as? String }
        #expect(eventTypes.contains("run_start"), "Missing run_start")
        #expect(eventTypes.contains("plan_created"), "Missing plan_created")
        #expect(eventTypes.contains("step_start"), "Missing step_start")
        #expect(eventTypes.contains("step_done"), "Missing step_done")
        #expect(eventTypes.contains("verification_result"), "Missing verification_result")
        #expect(eventTypes.contains("run_done"), "Missing run_done")

        if let pid = extractPid(from: executedStep.result) {
            _ = try? await mcpClient.callTool(name: ToolNames.quitApp, arguments: ["pid": .int(pid)])
        }
    }

    // MARK: - Helpers

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

        guard let (windowId, windowTitle) = extractMainWindow(from: windowsResult) else {
            Issue.record("Should get window from list_windows: \(windowsResult)")
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
