import Foundation

import AxionCore

// MARK: - RunEngineOptions

/// Options for configuring RunEngine behavior.
/// Constructed from RunCommand CLI arguments.
public struct RunEngineOptions: Sendable {
    public var dryrun: Bool
    public var allowForeground: Bool
    public var maxSteps: Int?
    public var maxBatches: Int?
    public var verbose: Bool

    public init(
        dryrun: Bool = false,
        allowForeground: Bool = false,
        maxSteps: Int? = nil,
        maxBatches: Int? = nil,
        verbose: Bool = false
    ) {
        self.dryrun = dryrun
        self.allowForeground = allowForeground
        self.maxSteps = maxSteps
        self.maxBatches = maxBatches
        self.verbose = verbose
    }
}

// MARK: - RunEngine

/// The core state machine orchestrator for Axion's execution loop.
/// Manages the plan -> execute -> verify -> replan cycle.
///
/// RunEngine is a plain struct (not an Actor) because:
/// - run() is a one-shot async call
/// - Internal state is only mutated within that single call
/// - Concurrency safety is handled by internal Actors (TraceRecorder, MCPConnection)
public struct RunEngine {

    private let planner: PlannerProtocol
    private let executor: ExecutorProtocol
    private let verifier: VerifierProtocol
    private let output: OutputProtocol

    public init(
        planner: PlannerProtocol,
        executor: ExecutorProtocol,
        verifier: VerifierProtocol,
        output: OutputProtocol
    ) {
        self.planner = planner
        self.executor = executor
        self.verifier = verifier
        self.output = output
    }

    // MARK: - Run ID Generation

    /// Generates a unique run ID in the format `YYYYMMDD-{6random}`.
    private static func generateRunId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let datePart = formatter.string(from: Date())
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomPart = String((0..<6).map { _ in chars.randomElement()! })
        return "\(datePart)-\(randomPart)"
    }

    // MARK: - Main Entry Point

    /// Main entry point — runs the plan -> execute -> verify -> replan loop.
    /// Returns the final RunContext with the terminal state.
    ///
    /// - Parameters:
    ///   - task: The natural language task description
    ///   - config: Configuration for this run
    ///   - options: CLI-derived options (dryrun, maxSteps, etc.)
    /// - Returns: RunContext with the terminal state (.done, .failed, .cancelled, or .needsClarification)
    public func run(task: String, config: AxionConfig, options: RunEngineOptions) async -> RunContext {
        let runId = Self.generateRunId()
        let tracer = try? TraceRecorder(runId: runId, config: config)
        let effectiveMaxSteps = options.maxSteps ?? config.maxSteps
        let effectiveMaxBatches = options.maxBatches ?? config.maxBatches

        var replanCount = 0
        var batchesUsed = 0
        var totalStepsExecuted = 0
        var isFirstPlan = true
        var currentPlan: Plan?
        var lastExecutedSteps: [ExecutedStep] = []

        // Determine mode string
        let mode = options.dryrun ? "dryrun" : (options.allowForeground ? "foreground" : "standard")

        // Initial context
        var context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        // Display run start
        output.displayRunStart(runId: runId, task: task, mode: mode)
        await tracer?.recordRunStart(runId: runId, task: task, mode: mode)

        // Outer batch loop
        while batchesUsed < effectiveMaxBatches {
            // Check cancellation
            if Task.isCancelled {
                context.currentState = .cancelled
                output.displaySummary(context: context)
                return context
            }

            // 1. Planning
            output.displayStateChange(from: context.currentState, to: .planning)
            await tracer?.recordStateChange(from: context.currentState.rawValue, to: RunState.planning.rawValue)
            context.currentState = .planning

            let plan: Plan
            do {
                if isFirstPlan {
                    plan = try await planner.createPlan(for: task, context: context)
                    isFirstPlan = false
                } else {
                    guard let existingPlan = currentPlan else {
                        context.currentState = .failed
                        output.displayError(.planningFailed(reason: "No plan to replan from"))
                        output.displaySummary(context: context)
                        return context
                    }
                    let failureReason = lastExecutedSteps.contains(where: { !$0.success })
                        ? "Step execution failed"
                        : (context.currentState == .blocked ? "Task blocked" : "Verification blocked")
                    output.displayStateChange(from: context.currentState, to: .replanning)
                    context.currentState = .replanning
                    plan = try await planner.replan(
                        from: existingPlan,
                        executedSteps: lastExecutedSteps,
                        failureReason: failureReason,
                        context: context
                    )
                }
            } catch let error as AxionError {
                if error == .cancelled {
                    context.currentState = .cancelled
                } else {
                    context.currentState = .failed
                    output.displayError(error)
                }
                output.displaySummary(context: context)
                return context
            } catch {
                if Task.isCancelled {
                    context.currentState = .cancelled
                } else {
                    context.currentState = .failed
                    output.displayError(.planningFailed(reason: error.localizedDescription))
                }
                output.displaySummary(context: context)
                return context
            }

            currentPlan = plan

            // Display the generated plan
            output.displayPlan(plan)
            await tracer?.recordPlanCreated(stepCount: plan.steps.count, stopWhenCount: plan.stopWhen.count)

            // 2. Dryrun mode — skip execution and verification
            if options.dryrun {
                context.currentState = .done
                output.displayStateChange(from: .planning, to: .done)
                await tracer?.recordStateChange(from: RunState.planning.rawValue, to: RunState.done.rawValue)
                output.displaySummary(context: context)
                return context
            }

            // Check cancellation before execution phase
            if Task.isCancelled {
                context.currentState = .cancelled
                output.displaySummary(context: context)
                return context
            }

            // 3. Executing
            output.displayStateChange(from: .planning, to: .executing)
            await tracer?.recordStateChange(from: RunState.planning.rawValue, to: RunState.executing.rawValue)
            context.currentState = .executing

            batchesUsed += 1

            let (executedSteps, updatedContext): ([ExecutedStep], RunContext)
            do {
                (executedSteps, updatedContext) = try await executor.executePlan(plan, context: context)
                context = updatedContext
            } catch let error as AxionError {
                if error == .cancelled {
                    context.currentState = .cancelled
                } else {
                    context.currentState = .failed
                    output.displayError(error)
                }
                output.displaySummary(context: context)
                return context
            } catch {
                if Task.isCancelled {
                    context.currentState = .cancelled
                } else {
                    context.currentState = .failed
                    output.displayError(.executionFailed(step: 0, reason: error.localizedDescription))
                }
                output.displaySummary(context: context)
                return context
            }

            lastExecutedSteps = executedSteps
            totalStepsExecuted += executedSteps.count

            // Check step budget
            if totalStepsExecuted >= effectiveMaxSteps {
                context.currentState = .failed
                output.displayError(.stepBudgetExceeded(steps: totalStepsExecuted, limit: effectiveMaxSteps))
                output.displaySummary(context: context)
                return context
            }

            // 4. Check for step execution failures
            let hasFailure = executedSteps.contains { !$0.success }

            if hasFailure {
                // Step failure -> replanning (skip verification)
                replanCount += 1
                if replanCount > config.maxReplanRetries {
                    context.currentState = .failed
                    output.displayError(.maxRetriesExceeded(retries: config.maxReplanRetries))
                    await tracer?.recordError(error: "max_replan_exceeded", message: "Exceeded \(config.maxReplanRetries) replan retries after step failure")
                    output.displaySummary(context: context)
                    return context
                }

                context.replanCount = replanCount
                output.displayReplan(attempt: replanCount, maxRetries: config.maxReplanRetries, reason: "Step execution failed")
                await tracer?.recordReplan(attempt: replanCount, maxRetries: config.maxReplanRetries, reason: "Step execution failed")
                // Loop back to replanning
                continue
            }

            // Check cancellation before verification phase
            if Task.isCancelled {
                context.currentState = .cancelled
                output.displaySummary(context: context)
                return context
            }

            // 5. Verifying
            output.displayStateChange(from: .executing, to: .verifying)
            await tracer?.recordStateChange(from: RunState.executing.rawValue, to: RunState.verifying.rawValue)
            context.currentState = .verifying

            let verification: VerificationResult
            do {
                verification = try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)
            } catch let error as AxionError {
                if error == .cancelled {
                    context.currentState = .cancelled
                } else {
                    context.currentState = .failed
                    output.displayError(error)
                }
                output.displaySummary(context: context)
                return context
            } catch {
                if Task.isCancelled {
                    context.currentState = .cancelled
                } else {
                    context.currentState = .failed
                    output.displayError(.verificationFailed(step: 0, reason: error.localizedDescription))
                }
                output.displaySummary(context: context)
                return context
            }

            output.displayVerificationResult(verification)
            await tracer?.recordVerificationResult(state: verification.state.rawValue, reason: verification.reason ?? "")

            // 6. Handle verification result
            switch verification.state {
            case .done:
                output.displayStateChange(from: .verifying, to: .done)
                await tracer?.recordStateChange(from: RunState.verifying.rawValue, to: RunState.done.rawValue)
                context.currentState = .done
                await tracer?.recordRunDone(totalSteps: totalStepsExecuted, durationMs: 0, replanCount: replanCount)
                output.displaySummary(context: context)
                return context

            case .needsClarification:
                output.displayStateChange(from: .verifying, to: .needsClarification)
                await tracer?.recordStateChange(from: RunState.verifying.rawValue, to: RunState.needsClarification.rawValue)
                context.currentState = .needsClarification
                output.displaySummary(context: context)
                return context

            case .blocked:
                replanCount += 1
                if replanCount > config.maxReplanRetries {
                    context.currentState = .failed
                    output.displayError(.maxRetriesExceeded(retries: config.maxReplanRetries))
                    await tracer?.recordError(error: "max_replan_exceeded", message: "Exceeded \(config.maxReplanRetries) replan retries")
                    output.displaySummary(context: context)
                    return context
                }

                context.replanCount = replanCount
                let reason = verification.reason ?? "Task blocked"
                output.displayReplan(attempt: replanCount, maxRetries: config.maxReplanRetries, reason: reason)
                await tracer?.recordReplan(attempt: replanCount, maxRetries: config.maxReplanRetries, reason: reason)
                output.displayStateChange(from: .verifying, to: .replanning)
                context.currentState = .blocked
                // Loop back to replanning
                continue

            default:
                // Unexpected verification state
                context.currentState = .failed
                output.displayError(.verificationFailed(step: 0, reason: "Unexpected verification state: \(verification.state)"))
                output.displaySummary(context: context)
                return context
            }
        }

        // Batch limit exceeded
        context.currentState = .failed
        output.displayError(.batchBudgetExceeded(batches: batchesUsed, limit: effectiveMaxBatches))
        output.displaySummary(context: context)
        return context
    }
}
