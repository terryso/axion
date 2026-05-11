import Foundation

import AxionCore

/// 抽象 SDK Agent 的 LLM 调用，使 LLMPlanner 可测试
protocol LLMClientProtocol {
    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String
}

/// 重规划上下文
struct ReplanContext {
    let failedStepIndex: Int
    let failedStep: Step
    let errorMessage: String
    let executedSteps: [Step]
    let liveAxTree: String?
    let runHistory: String?
}

/// LLM Planner 实现 PlannerProtocol
struct LLMPlanner: PlannerProtocol {
    let config: AxionConfig
    let llmClient: LLMClientProtocol
    let mcpClient: MCPClientProtocol
    let retryDelay: @Sendable (UInt64) async throws -> Void

    /// Callback invoked after a plan is created (for output/trace integration).
    var onPlanCreated: ((Plan) -> Void)?

    init(config: AxionConfig, llmClient: LLMClientProtocol, mcpClient: MCPClientProtocol,
         retryDelay: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.config = config
        self.llmClient = llmClient
        self.mcpClient = mcpClient
        self.retryDelay = retryDelay
        self.onPlanCreated = nil
    }

    // MARK: - PlannerProtocol conformance

    func createPlan(for task: String, context: RunContext) async throws -> Plan {
        let currentStateSummary = await captureCurrentStateSafely()
        let screenshotPath = await captureScreenshotSafely()

        let (systemPrompt, userPrompt) = try await buildPrompts(
            task: task,
            currentStateSummary: currentStateSummary,
            replanContext: nil,
            maxStepsPerPlan: context.config.maxSteps
        )

        let imagePaths = screenshotPath.map { [$0] } ?? []
        defer { cleanupScreenshot(screenshotPath) }

        let rawResponse = try await callLLMWithRetry(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            imagePaths: imagePaths
        )

        let plan = try PlanParser.parse(rawResponse, task: task, maxSteps: context.config.maxSteps)
        onPlanCreated?(plan)
        return plan
    }

    func replan(
        from currentPlan: Plan,
        executedSteps: [ExecutedStep],
        failureReason: String,
        context: RunContext
    ) async throws -> Plan {
        // Find the failed step from the current plan
        let failedStepIndex = context.currentStepIndex
        let failedStep: Step
        if failedStepIndex < currentPlan.steps.count {
            failedStep = currentPlan.steps[failedStepIndex]
        } else {
            failedStep = currentPlan.steps.last ?? Step(
                index: 0, tool: "unknown", parameters: [:],
                purpose: "Unknown step", expectedChange: ""
            )
        }

        // Build list of successfully executed steps
        // Use the original plan's steps to preserve purpose, falling back to result summary
        let executedPlanSteps = executedSteps
            .filter { $0.success }
            .map { exec -> Step in
                let originalPurpose: String
                if exec.stepIndex < currentPlan.steps.count {
                    originalPurpose = currentPlan.steps[exec.stepIndex].purpose
                } else {
                    originalPurpose = "Executed: \(exec.tool)"
                }
                return Step(
                    index: exec.stepIndex,
                    tool: exec.tool,
                    parameters: exec.parameters,
                    purpose: originalPurpose,
                    expectedChange: String(exec.result.prefix(100))
                )
            }

        let replanContext = ReplanContext(
            failedStepIndex: failedStepIndex,
            failedStep: failedStep,
            errorMessage: failureReason,
            executedSteps: executedPlanSteps,
            liveAxTree: await captureAXTreeSafely(),
            runHistory: nil
        )

        let currentStateSummary = await captureCurrentStateSafely()
        let screenshotPath = await captureScreenshotSafely()

        let (systemPrompt, userPrompt) = try await buildPrompts(
            task: currentPlan.task,
            currentStateSummary: currentStateSummary,
            replanContext: replanContext,
            maxStepsPerPlan: context.config.maxSteps
        )

        let imagePaths = screenshotPath.map { [$0] } ?? []
        defer { cleanupScreenshot(screenshotPath) }

        let rawResponse = try await callLLMWithRetry(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            imagePaths: imagePaths
        )

        let plan = try PlanParser.parse(rawResponse, task: currentPlan.task, maxSteps: context.config.maxSteps)
        onPlanCreated?(plan)
        return plan
    }

    // MARK: - Internal Methods

    /// Safely capture current screen state (screenshot + AX tree), degrading gracefully on failure
    private func captureCurrentStateSafely() async -> String {
        var components: [String] = []

        if let axTree = await captureAXTreeSafely() {
            components.append("AX Tree:")
            components.append(axTree)
        }

        return components.joined(separator: "\n")
    }

    /// Capture a screenshot via MCP and save to a temp file. Returns the file path, or nil on failure.
    private func captureScreenshotSafely() async -> String? {
        do {
            let result = try await mcpClient.callTool(
                name: ToolNames.screenshot,
                arguments: [:]
            )
            // Parse JSON response to extract image_data (base64)
            guard let data = result.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let base64 = json["image_data"] as? String,
                  let imageData = Data(base64Encoded: base64) else {
                return nil
            }

            let tempDir = NSTemporaryDirectory()
            let path = (tempDir as NSString).appendingPathComponent("axion-planner-\(UUID().uuidString).png")
            try imageData.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }

    /// Safely capture AX tree, returning nil on failure
    private func captureAXTreeSafely() async -> String? {
        do {
            let result = try await mcpClient.callTool(
                name: ToolNames.getAccessibilityTree,
                arguments: [:]
            )
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    /// Clean up temp screenshot file
    private func cleanupScreenshot(_ path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Build system and user prompts for the planner
    private func buildPrompts(
        task: String,
        currentStateSummary: String?,
        replanContext: ReplanContext?,
        maxStepsPerPlan: Int
    ) async throws -> (systemPrompt: String, userPrompt: String) {
        // Get tool list from MCP client
        let toolList: [String]
        do {
            toolList = try await mcpClient.listTools()
        } catch {
            toolList = Self.defaultToolList
        }

        let toolListDescription = PromptBuilder.buildToolListDescription(from: toolList)
        let promptDirectory = PromptBuilder.resolvePromptDirectory()

        // Load system prompt
        let systemPrompt = try PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": toolListDescription,
                "max_steps": "\(maxStepsPerPlan)",
            ],
            fromDirectory: promptDirectory
        )

        // Build user prompt
        let userPrompt = PromptBuilder.buildPlannerPrompt(
            task: task,
            currentStateSummary: currentStateSummary ?? "",
            maxStepsPerPlan: maxStepsPerPlan,
            replanContext: replanContext
        )

        return (systemPrompt, userPrompt)
    }

    /// Call LLM with retry logic (exponential backoff: 1s -> 2s -> 4s, max 3 retries)
    /// Only retries on transient network errors (AxionError.planningFailed), not on parse errors
    private func callLLMWithRetry(
        systemPrompt: String,
        userPrompt: String,
        imagePaths: [String]
    ) async throws -> String {
        let maxRetries = 3
        let baseDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000] // 1s, 2s, 4s in nanoseconds

        var lastError: Error?

        for attempt in 0...(maxRetries) {
            do {
                return try await llmClient.prompt(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    imagePaths: imagePaths
                )
            } catch let error as AxionError {
                // Parse errors (invalidPlan) should not be retried
                if case .invalidPlan = error {
                    throw error
                }
                lastError = error
                if attempt < maxRetries {
                    try await retryDelay(baseDelays[attempt])
                }
            } catch {
                lastError = error
                if attempt < maxRetries {
                    try await retryDelay(baseDelays[attempt])
                }
            }
        }

        throw lastError ?? AxionError.maxRetriesExceeded(retries: maxRetries)
    }

    /// Default tool list used when MCP client is unavailable
    private static let defaultToolList = [
        ToolNames.launchApp,
        ToolNames.listApps,
        ToolNames.quitApp,
        ToolNames.activateWindow,
        ToolNames.listWindows,
        ToolNames.getWindowState,
        ToolNames.click,
        ToolNames.doubleClick,
        ToolNames.rightClick,
        ToolNames.typeText,
        ToolNames.pressKey,
        ToolNames.hotkey,
        ToolNames.scroll,
        ToolNames.drag,
        ToolNames.screenshot,
        ToolNames.getAccessibilityTree,
        ToolNames.openUrl,
    ]
}
