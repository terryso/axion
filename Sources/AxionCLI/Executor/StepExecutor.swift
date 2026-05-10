import Foundation

import AxionCore

// MARK: - StepExecutor

/// Executes the steps of a Plan sequentially through MCP tool calls to the Helper process.
/// Each step goes through: PlaceholderResolver -> AX refresh (if needed) -> SafetyChecker ->
/// MCP call -> absorbResult.
///
/// This is the execution phase of the plan -> execute -> verify loop.
/// StepExecutor does NOT use the OpenAgentSDK Agent Loop — it directly calls MCPClientProtocol
/// because it executes a pre-generated step sequence that requires no LLM reasoning.
public struct StepExecutor: ExecutorProtocol {

    private let mcpClient: MCPClientProtocol
    private let config: AxionConfig
    private let placeholderResolver: PlaceholderResolver
    private let safetyChecker: SafetyChecker

    public init(mcpClient: MCPClientProtocol, config: AxionConfig) {
        self.mcpClient = mcpClient
        self.config = config
        self.placeholderResolver = PlaceholderResolver()
        self.safetyChecker = SafetyChecker()
    }

    // MARK: - ExecutorProtocol

    /// Executes a single step within the given run context.
    /// Resolves placeholders, checks safety, refreshes AX state if needed, then calls MCP.
    public func executeStep(_ step: Step, context: RunContext) async throws -> ExecutedStep {
        // Build execution context from prior executed steps
        var executionContext = buildExecutionContext(from: context.executedSteps)

        // 1. AX refresh before foreground operations (must happen BEFORE resolve
        //    so that $window_id from the refresh result is available for resolution)
        if shouldRefreshBeforeAXOp(step.tool) {
            await refreshWindowState(context: &executionContext)
        }

        // 2. Resolve placeholders ($pid, $window_id)
        let resolvedStep = placeholderResolver.resolve(step: step, context: executionContext)

        // 3. Safety check
        let safetyResult = safetyChecker.check(
            tool: resolvedStep.tool,
            sharedSeatMode: config.sharedSeatMode
        )
        guard safetyResult.allowed else {
            return ExecutedStep(
                stepIndex: resolvedStep.index,
                tool: resolvedStep.tool,
                parameters: resolvedStep.parameters,
                result: safetyResult.errorMessage,
                success: false,
                timestamp: Date()
            )
        }

        // 4. MCP call
        let result: String
        do {
            result = try await mcpClient.callTool(
                name: resolvedStep.tool,
                arguments: resolvedStep.parameters
            )
        } catch let error as AxionError {
            throw AxionError.executionFailed(
                step: resolvedStep.index,
                reason: error.errorPayload.message
            )
        } catch {
            throw AxionError.executionFailed(
                step: resolvedStep.index,
                reason: error.localizedDescription
            )
        }

        // 5. Absorb result into execution context
        placeholderResolver.absorbResult(
            tool: resolvedStep.tool,
            result: result,
            context: &executionContext
        )

        // 6. Build executed step
        return ExecutedStep(
            stepIndex: resolvedStep.index,
            tool: resolvedStep.tool,
            parameters: resolvedStep.parameters,
            result: result,
            success: true,
            timestamp: Date()
        )
    }

    // MARK: - Plan Execution

    /// Executes all steps in a Plan sequentially, stopping on the first failure.
    /// Returns the executed steps and the updated run context.
    public func executePlan(_ plan: Plan, context: RunContext) async throws -> (executedSteps: [ExecutedStep], context: RunContext) {
        var executionContext = buildExecutionContext(from: context.executedSteps)
        var executedSteps: [ExecutedStep] = []
        var updatedContext = context

        for step in plan.steps {
            // 1. AX refresh before foreground operations (must happen BEFORE resolve
            //    so that $window_id from the refresh result is available for resolution)
            if shouldRefreshBeforeAXOp(step.tool) {
                await refreshWindowState(context: &executionContext)
            }

            // 2. Resolve placeholders ($pid, $window_id)
            let resolvedStep = placeholderResolver.resolve(step: step, context: executionContext)

            // 3. Safety check
            let safetyResult = safetyChecker.check(
                tool: resolvedStep.tool,
                sharedSeatMode: config.sharedSeatMode
            )
            guard safetyResult.allowed else {
                let failedStep = ExecutedStep(
                    stepIndex: resolvedStep.index,
                    tool: resolvedStep.tool,
                    parameters: resolvedStep.parameters,
                    result: safetyResult.errorMessage,
                    success: false,
                    timestamp: Date()
                )
                executedSteps.append(failedStep)
                updatedContext.executedSteps = executedSteps
                updatedContext.currentStepIndex = resolvedStep.index
                return (executedSteps, updatedContext)
            }

            // 4. MCP call
            let result: String
            do {
                result = try await mcpClient.callTool(
                    name: resolvedStep.tool,
                    arguments: resolvedStep.parameters
                )
            } catch {
                let failedStep = ExecutedStep(
                    stepIndex: resolvedStep.index,
                    tool: resolvedStep.tool,
                    parameters: resolvedStep.parameters,
                    result: error.localizedDescription,
                    success: false,
                    timestamp: Date()
                )
                executedSteps.append(failedStep)
                updatedContext.executedSteps = executedSteps
                updatedContext.currentStepIndex = resolvedStep.index
                return (executedSteps, updatedContext)
            }

            // 5. Absorb result into execution context
            placeholderResolver.absorbResult(
                tool: resolvedStep.tool,
                result: result,
                context: &executionContext
            )

            // 6. Record successful step
            let executedStep = ExecutedStep(
                stepIndex: resolvedStep.index,
                tool: resolvedStep.tool,
                parameters: resolvedStep.parameters,
                result: result,
                success: true,
                timestamp: Date()
            )
            executedSteps.append(executedStep)
        }

        updatedContext.executedSteps = executedSteps
        updatedContext.currentStepIndex = executedSteps.count - 1
        return (executedSteps, updatedContext)
    }

    // MARK: - Internal Helpers

    /// Builds an ExecutionContext by replaying absorbResult over prior executed steps.
    private func buildExecutionContext(from executedSteps: [ExecutedStep]) -> ExecutionContext {
        var context = ExecutionContext()
        for step in executedSteps where step.success {
            placeholderResolver.absorbResult(
                tool: step.tool,
                result: step.result,
                context: &context
            )
        }
        return context
    }

    /// Returns true for tools that perform AX-targeted operations (clicks, typing, etc.)
    /// and need a fresh window state to avoid stale element indices.
    private func shouldRefreshBeforeAXOp(_ tool: String) -> Bool {
        let axTargetedTools: Set<String> = [
            ToolNames.click,
            ToolNames.doubleClick,
            ToolNames.rightClick,
            ToolNames.typeText,
            ToolNames.pressKey,
            ToolNames.hotkey,
            ToolNames.scroll,
            ToolNames.drag
        ]
        return axTargetedTools.contains(tool)
    }

    /// Calls `get_window_state` on the MCP client to refresh the AX element tree.
    /// Calls `get_window_state` on the MCP client to refresh the AX element tree.
    /// Requires a windowId in the execution context; skips silently if unavailable.
    private func refreshWindowState(context: inout ExecutionContext) async {
        guard let windowId = context.windowId else { return }

        do {
            let result = try await mcpClient.callTool(
                name: ToolNames.getWindowState,
                arguments: ["window_id": .int(windowId)]
            )
            placeholderResolver.absorbResult(
                tool: ToolNames.getWindowState,
                result: result,
                context: &context
            )
        } catch {
            // AX refresh failure is non-fatal; execution continues with stale state.
            // Logging will be integrated in Story 3-5 (OutputProtocol).
        }
    }
}
