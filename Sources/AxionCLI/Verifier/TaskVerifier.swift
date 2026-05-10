import Foundation

import AxionCore

// MARK: - TaskVerifier

/// Verifies whether a task has been completed after executing a batch of steps.
///
/// Workflow:
/// 1. Capture verification context (screenshot + AX tree) via MCP
/// 2. Run local stop condition evaluation (StopConditionEvaluator)
/// 3. If uncertain, delegate to LLM for semantic evaluation
/// 4. Return VerificationResult with the determined state
///
/// Graceful degradation:
/// - Screenshot failure -> verify with AX tree only
/// - AX tree failure -> skip local evaluation, go straight to LLM
/// - LLM failure -> default to .blocked (safe degradation, triggers replan)
struct TaskVerifier: VerifierProtocol {
    let mcpClient: MCPClientProtocol
    let llmClient: LLMClientProtocol
    let config: AxionConfig
    let stopConditionEvaluator: StopConditionEvaluator

    /// Callback invoked after verification completes (for output/trace integration).
    var onVerificationResult: ((VerificationResult) -> Void)?

    init(mcpClient: MCPClientProtocol, llmClient: LLMClientProtocol, config: AxionConfig) {
        self.mcpClient = mcpClient
        self.llmClient = llmClient
        self.config = config
        self.stopConditionEvaluator = StopConditionEvaluator()
        self.onVerificationResult = nil
    }

    // MARK: - VerifierProtocol Conformance

    func verify(
        plan: Plan,
        executedSteps: [ExecutedStep],
        context: RunContext
    ) async throws -> VerificationResult {
        // Step 1: Rebuild execution context to get pid/windowId
        let execContext = buildExecutionContext(from: executedSteps)

        // Step 2: Capture verification context via MCP
        let (screenshot, axTree) = await captureVerificationContext(
            pid: execContext.pid,
            windowId: execContext.windowId
        )

        // Step 3: Evaluate stop conditions locally
        let evaluationResult = stopConditionEvaluator.evaluate(
            stopConditions: plan.stopWhen,
            screenshot: screenshot,
            axTree: axTree,
            executedSteps: executedSteps,
            maxSteps: config.maxSteps
        )

        switch evaluationResult {
        case .satisfied:
            let result = VerificationResult.done(
                reason: "All stop conditions satisfied",
                screenshotBase64: screenshot,
                axTreeSnapshot: axTree
            )
            onVerificationResult?(result)
            return result
        case .notSatisfied:
            let result = VerificationResult.blocked(
                reason: "Stop conditions not met",
                screenshotBase64: screenshot,
                axTreeSnapshot: axTree
            )
            onVerificationResult?(result)
            return result
        case .uncertain:
            // Step 4: Delegate to LLM for semantic evaluation
            let result = await evaluateWithLLM(
                task: plan.task,
                stopConditions: plan.stopWhen,
                screenshot: screenshot,
                axTree: axTree,
                executedSteps: executedSteps,
                planSteps: plan.steps
            )
            onVerificationResult?(result)
            return result
        }
    }

    // MARK: - Verification Context Capture

    /// Captures screenshot and AX tree via MCP calls for verification.
    /// Degrades gracefully: if one fails, continues with the other.
    private func captureVerificationContext(
        pid: Int?,
        windowId: Int?
    ) async -> (screenshot: String?, axTree: String?) {
        // Sequential calls to avoid Swift 6.1 Sendability issues with async let + self
        let screenshot = await captureScreenshot(windowId: windowId)
        let axTree = await captureAXTree(pid: pid, windowId: windowId)

        return (screenshot: screenshot, axTree: axTree)
    }

    /// Captures a screenshot via MCP, returning base64 data or nil on failure.
    private func captureScreenshot(windowId: Int?) async -> String? {
        var arguments: [String: Value] = [:]
        if let windowId = windowId {
            arguments["window_id"] = .int(windowId)
        }

        do {
            let result = try await mcpClient.callTool(
                name: ToolNames.screenshot,
                arguments: arguments
            )
            // Try to extract base64 from result
            if let data = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["error"] != nil {
                    return nil
                }
                return result
            }
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    /// Captures the AX accessibility tree via MCP, returning the JSON string or nil on failure.
    private func captureAXTree(pid: Int?, windowId: Int?) async -> String? {
        var arguments: [String: Value] = [:]
        if let pid = pid {
            arguments["pid"] = .int(pid)
        }
        if let windowId = windowId {
            arguments["window_id"] = .int(windowId)
        }

        do {
            let result = try await mcpClient.callTool(
                name: ToolNames.getAccessibilityTree,
                arguments: arguments
            )
            if result.isEmpty { return nil }
            // Check for error responses in JSON
            if let data = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["error"] != nil {
                return nil
            }
            return result
        } catch {
            return nil
        }
    }

    // MARK: - LLM Evaluation

    /// Sends verification context to the LLM for semantic evaluation.
    /// On failure, returns .blocked as a safe degradation.
    private func evaluateWithLLM(
        task: String,
        stopConditions: [StopCondition],
        screenshot: String?,
        axTree: String?,
        executedSteps: [ExecutedStep],
        planSteps: [Step]
    ) async -> VerificationResult {
        do {
            let systemPrompt = try loadVerifierPrompt()
            let userMessage = buildVerifierUserMessage(
                task: task,
                stopConditions: stopConditions,
                axTree: axTree,
                executedSteps: executedSteps,
                planSteps: planSteps
            )

            let rawResponse = try await llmClient.prompt(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                imagePaths: []
            )

            return parseLLMResponse(rawResponse, screenshot: screenshot, axTree: axTree)
        } catch {
            // LLM failure -> safe degradation to blocked
            return VerificationResult.blocked(
                reason: "LLM evaluation failed: \(error.localizedDescription)",
                screenshotBase64: screenshot,
                axTreeSnapshot: axTree
            )
        }
    }

    /// Loads the verifier system prompt from the Prompts directory.
    private func loadVerifierPrompt() throws -> String {
        let promptDirectory = PromptBuilder.resolvePromptDirectory()
        return try PromptBuilder.load(
            name: "verifier-system",
            variables: [:],
            fromDirectory: promptDirectory
        )
    }

    /// Builds the user message for the verifier LLM call.
    private func buildVerifierUserMessage(
        task: String,
        stopConditions: [StopCondition],
        axTree: String?,
        executedSteps: [ExecutedStep],
        planSteps: [Step]
    ) -> String {
        var sections: [String] = []

        sections.append("User task:")
        sections.append(task)
        sections.append("")

        if !stopConditions.isEmpty {
            sections.append("Stop conditions (stopWhen):")
            for condition in stopConditions {
                let valueStr = condition.value.map { " \($0)" } ?? ""
                sections.append("  - \(condition.type.rawValue)\(valueStr)")
            }
            sections.append("")
        }

        if let axTree = axTree {
            sections.append("Current AX tree:")
            let maxLen = 8000
            if axTree.count > maxLen {
                sections.append(String(axTree.prefix(maxLen)))
                sections.append("[AX tree truncated to \(maxLen) characters]")
            } else {
                sections.append(axTree)
            }
            sections.append("")
        }

        if !executedSteps.isEmpty {
            sections.append("Executed steps:")
            for step in executedSteps {
                let status = step.success ? "OK" : "FAIL"
                let purpose = planSteps.first(where: { $0.index == step.stepIndex })?.purpose
                var line = "  \(step.stepIndex). [\(status)] \(step.tool)"
                if let purpose = purpose {
                    line += " — \(purpose)"
                }
                sections.append(line)

                if !step.parameters.isEmpty {
                    let params = step.parameters.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    sections.append("     Parameters: \(params)")
                }

                let resultSnippet = String(step.result.prefix(200))
                sections.append("     Result: \(resultSnippet)")
            }
            sections.append("")
        }

        sections.append("Based on the above information, determine the task status. Output ONLY a JSON object with no markdown formatting.")

        return sections.joined(separator: "\n")
    }

    /// Parses the LLM response JSON into a VerificationResult.
    /// On parse failure, returns .blocked as safe degradation.
    private func parseLLMResponse(_ response: String, screenshot: String?, axTree: String?) -> VerificationResult {
        // Strip markdown fences if present
        let cleaned = stripFences(response)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusStr = json["status"] as? String else {
            return VerificationResult.blocked(
                reason: "Failed to parse LLM verification response",
                screenshotBase64: screenshot,
                axTreeSnapshot: axTree
            )
        }

        let reason = json["reason"] as? String

        switch statusStr {
        case "done":
            return VerificationResult.done(
                reason: reason,
                screenshotBase64: screenshot,
                axTreeSnapshot: axTree
            )
        case "blocked":
            return VerificationResult.blocked(
                reason: reason ?? "Task blocked",
                screenshotBase64: screenshot,
                axTreeSnapshot: axTree
            )
        case "needs_clarification":
            return VerificationResult.needsClarification(
                reason: reason ?? "Clarification needed",
                screenshotBase64: screenshot,
                axTreeSnapshot: axTree
            )
        default:
            return VerificationResult.blocked(
                reason: "Unknown LLM status: \(statusStr)",
                screenshotBase64: screenshot,
                axTreeSnapshot: axTree
            )
        }
    }

    // MARK: - ExecutionContext Rebuild

    /// Rebuilds execution context from executed steps using PlaceholderResolver's absorbResult logic.
    private func buildExecutionContext(from executedSteps: [ExecutedStep]) -> ExecutionContext {
        var context = ExecutionContext()
        let resolver = PlaceholderResolver()
        for step in executedSteps where step.success {
            resolver.absorbResult(tool: step.tool, result: step.result, context: &context)
        }
        return context
    }

    // MARK: - Markdown Fence Stripping

    /// Removes markdown code fences and surrounding text from LLM response.
    /// Extracts the JSON object by finding the first { and last }.
    private func stripFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```json") {
            result = String(result.dropFirst(7))
        } else if result.hasPrefix("```") {
            result = String(result.dropFirst(3))
        }
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // Extract JSON object even if there's surrounding text
        if let firstBrace = result.firstIndex(of: "{"),
           let lastBrace = result.lastIndex(of: "}") {
            return String(result[firstBrace...lastBrace])
        }
        return result
    }
}
