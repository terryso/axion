import Foundation
import OpenAgentSDK

import AxionCore

public actor AxionRuntime: AxionRuntimeRunning, AxionRuntimeResuming, SessionListing {
    let eventBus: EventBus?
    let executor: RunExecuting
    let builder: AgentBuilding
    let sessionStore: SessionStore
    let sessionsDir: String
    var currentState: AxionRunState = .created
    var sessionId: String?
    var createdAt: Date?
    var externallyModified: Bool = false
    internal var externallyModifiedFlag = ExternallyModifiedFlag()
    private(set) var takeoverEvent: RunMemoryProcessor.TakeoverEventContext?
    internal var runCompleteBox: RunCompleteContextBox?
    var contextChatId: Int64?
    var contextShouldReviewMemory: Bool = false
    var contextShouldReviewSkills: Bool = false
    var handlers: [any EventHandler] = []
    var eventSubscriptionId: UUID?

    init(eventBus: EventBus? = nil, executor: RunExecuting = DefaultRunExecutor(), builder: AgentBuilding = DefaultAgentBuilder(), sessionStore: SessionStore? = nil) {
        self.eventBus = eventBus
        self.executor = executor
        self.builder = builder
        let dir = ConfigManager.sessionsDirectory
        self.sessionsDir = dir
        self.sessionStore = sessionStore ?? SessionStore(sessionsDir: dir)
    }

    struct RunOverrides: Sendable {
        let json: Bool
        let noVisualDelta: Bool
        let noReview: Bool
        let onReviewCompleted: (@Sendable (String) -> Void)?
        let reviewDataContext: ReviewDataContext?
        let nonInteractivePause: Bool
        let registerResumeHandle: (@Sendable (String, @Sendable @escaping (String) async -> Void) async -> Void)?

        static let `default` = RunOverrides(
            json: false, noVisualDelta: false, noReview: false, onReviewCompleted: nil, reviewDataContext: nil,
            nonInteractivePause: false, registerResumeHandle: nil
        )
    }

    public nonisolated var state: AxionRunState {
        get async { await currentState }
    }

    static func collectSkillResponseText(from messages: [SDKMessage]) -> String? {
        RunOrchestrator.collectVisibleResponseText(from: messages)
    }

    // MARK: - Build Config Helpers

    /// Inject sessionId + sessionStore into a BuildConfig so SDK writes transcript.json.
    func injectSessionIntoBuildConfig(_ buildConfig: AgentBuilder.BuildConfig, sessionId: String) -> AgentBuilder.BuildConfig {
        AgentBuilder.BuildConfig(
            config: buildConfig.config,
            task: buildConfig.task,
            noMemory: buildConfig.noMemory,
            noSkills: buildConfig.noSkills,
            includePlaywright: buildConfig.includePlaywright,
            allowForeground: buildConfig.allowForeground,
            maxSteps: buildConfig.maxSteps,
            maxTokens: buildConfig.maxTokens,
            verbose: buildConfig.verbose,
            dryrun: buildConfig.dryrun,
            fast: buildConfig.fast,
            runId: sessionId,
            sessionId: sessionId,
            sessionStore: sessionStore,
            emitTokenStream: buildConfig.emitTokenStream,
            mode: buildConfig.mode,
            permissionMode: buildConfig.permissionMode,
            canUseTool: buildConfig.canUseTool,
            jsonOutput: buildConfig.jsonOutput
        )
    }

    /// Build a RunOrchestrator.RunConfig from BuildConfig + RunOverrides.
    func makeRunConfig(from buildConfig: AgentBuilder.BuildConfig, overrides: RunOverrides) -> RunOrchestrator.RunConfig {
        RunOrchestrator.RunConfig(
            task: buildConfig.task,
            fast: buildConfig.fast,
            dryrun: buildConfig.dryrun,
            json: overrides.json,
            noMemory: buildConfig.noMemory,
            noVisualDelta: overrides.noVisualDelta,
            allowForeground: buildConfig.allowForeground,
            maxSteps: buildConfig.maxSteps,
            config: buildConfig.config,
            noReview: overrides.noReview,
            onReviewCompleted: overrides.onReviewCompleted,
            eventBus: eventBus,
            reviewDataContext: overrides.reviewDataContext,
            nonInteractivePause: overrides.nonInteractivePause,
            registerResumeHandle: overrides.registerResumeHandle
        )
    }

    // MARK: - Run Lifecycle Helpers

    /// Attempt to transition to `.running` state. Returns a failure result if the
    /// transition is invalid, or `nil` on success (caller should proceed with execution).
    func beginRun(sid: String, task: String, startedAt: Date) -> AxionRunResult? {
        sessionId = sid
        createdAt = startedAt

        guard currentState.isValidTransition(to: .running) else {
            currentState = .failed
            return .failedRun(
                sessionId: sid,
                task: task,
                error: "Invalid state transition from \(currentState) to running",
                createdAt: startedAt
            )
        }
        currentState = .running
        externallyModifiedFlag = ExternallyModifiedFlag()
        try? writeAxionState(
            sessionId: sid, status: AxionRunState.running.rawValue,
            totalSteps: 0, durationMs: 0
        )
        return nil
    }

    /// Record a failed run: set state to `.failed`, write state file, return failure result.
    func failRun(sid: String, task: String, error: String, startedAt: Date) -> AxionRunResult {
        currentState = .failed
        try? writeAxionState(
            sessionId: sid, status: AxionRunState.failed.rawValue,
            totalSteps: 0, durationMs: 0
        )
        return .failedRun(sessionId: sid, task: task, error: error, createdAt: startedAt)
    }

    // MARK: - Core Run

    func run(
        task: String,
        buildResult: AgentBuildResult,
        runConfig: RunOrchestrator.RunConfig,
        resumeSessionId: String? = nil
    ) async throws -> AxionRunResult {
        let sid = resumeSessionId ?? executor.generateRunId()
        let startedAt = Date()

        if let failure = beginRun(sid: sid, task: task, startedAt: startedAt) {
            return failure
        }

        runCompleteBox = buildResult.runCompleteBox

        do {
            let result = try await executor.execute(
                buildResult: buildResult,
                runConfig: runConfig
            )
            externallyModified = result.externallyModified
            takeoverEvent = result.takeoverEvent

            // Output cost summary — printed here because AgentCompletedEvent fires
            // before lastRunCompleteContext is set, making event-handler-based logging impossible.
            if let ctx = result.runCompleteContext {
                let tokens = ctx.usage.inputTokens + ctx.usage.outputTokens
                fputs("[axion] LLM 调用: \(ctx.numTurns)轮, Tokens: \(tokens), 预估成本: $\(String(format: "%.4f", ctx.totalCostUsd))\n", stderr)
            }
            currentState = .completed
            let ctxWrapper = result.runCompleteContext.map { ctx in
                RunCompleteContextWrapper(
                    task: ctx.task,
                    status: ctx.status.rawValue,
                    totalCostUsd: ctx.totalCostUsd,
                    durationMs: ctx.durationMs,
                    numTurns: ctx.numTurns,
                    inputTokens: ctx.usage.inputTokens,
                    outputTokens: ctx.usage.outputTokens
                )
            }
            try? writeAxionState(
                sessionId: sid, status: AxionRunState.completed.rawValue,
                totalSteps: result.totalSteps, durationMs: result.durationMs
            )
            try? await saveSessionFirstPrompt(sessionId: sid, task: task)
            return AxionRunResult(
                sessionId: sid,
                task: task,
                state: .completed,
                totalSteps: result.totalSteps,
                durationMs: result.durationMs,
                runSucceeded: result.runSucceeded,
                runCompleteContext: ctxWrapper,
                responseText: result.responseText,
                createdAt: startedAt
            )
        } catch {
            try? await saveSessionFirstPrompt(sessionId: sid, task: task)
            return failRun(sid: sid, task: task, error: error.localizedDescription, startedAt: startedAt)
        }
    }

    func execute(
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: RunOverrides = .default,
        sessionId: String? = nil
    ) async throws -> AxionRunResult {
        let sid = (sessionId?.isEmpty == false) ? sessionId! : executor.generateRunId()
        let startedAt = Date()
        self.sessionId = sid
        createdAt = startedAt

        let sessionedBuildConfig = injectSessionIntoBuildConfig(buildConfig, sessionId: sid)

        let buildResult: AgentBuildResult
        do {
            let buildStart = ContinuousClock.now
            buildResult = try await builder.build(sessionedBuildConfig, eventBus: eventBus)
            let buildElapsed = ContinuousClock.now - buildStart
            let buildMs = durationToMs(buildElapsed)
            fputs("[axion] 构建完成 [\(formatDurationMs(buildMs))]\n", stderr)
        } catch {
            return failRun(sid: sid, task: buildConfig.task, error: error.localizedDescription, startedAt: startedAt)
        }

        let runConfig = makeRunConfig(from: buildConfig, overrides: runOverrides)

        return try await run(task: buildConfig.task, buildResult: buildResult, runConfig: runConfig, resumeSessionId: sid)
    }

    // MARK: - Handler Management

    func registerHandler(_ handler: any EventHandler) {
        handlers.append(handler)
    }

    func setContextOverrides(chatId: Int64?, shouldReviewMemory: Bool, shouldReviewSkills: Bool) async {
        contextChatId = chatId
        contextShouldReviewMemory = shouldReviewMemory
        contextShouldReviewSkills = shouldReviewSkills
    }

    func startEventLoop() async {
        guard let bus = eventBus, eventSubscriptionId == nil else { return }
        let (id, stream) = await bus.subscribe()
        eventSubscriptionId = id
        for await event in stream {
            await dispatchToHandlers(event)
        }
    }

    func stopEventLoop() async {
        guard let bus = eventBus, let id = eventSubscriptionId else { return }
        await bus.unsubscribe(id)
        eventSubscriptionId = nil
    }
}

func formatDurationMs(_ ms: Int) -> String {
    if ms < 1000 {
        return "\(ms)ms"
    }
    return String(format: "%.1fs", Double(ms) / 1000.0)
}
