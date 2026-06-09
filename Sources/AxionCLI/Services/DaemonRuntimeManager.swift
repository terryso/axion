import OpenAgentSDK

import AxionCore

actor DaemonRuntimeManager: DaemonRuntimeManaging {
    private let traceDir: String
    private var sessionHistory: [String: DaemonSessionInfo] = [:]
    private let runtimeFactory: @Sendable (EventBus) -> any AxionRuntimeRunning

    /// Max completed sessions to retain in memory. Oldest evicted when exceeded.
    private let maxSessionHistory: Int

    init(
        traceDir: String,
        maxSessionHistory: Int = 100,
        runtimeFactory: @escaping @Sendable (EventBus) -> any AxionRuntimeRunning = { AxionRuntime(eventBus: $0) }
    ) {
        self.traceDir = traceDir
        self.maxSessionHistory = maxSessionHistory
        self.runtimeFactory = runtimeFactory
    }

    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides = .default,
        handlerProfile: HandlerProfile,
        extraHandlers: [any EventHandler] = [],
        sessionId: String? = nil,
        chatId: Int64? = nil,
        shouldReviewMemory: Bool = false,
        shouldReviewSkills: Bool = false
    ) async throws -> AxionRunResult {
        let handlers = handlerProfile.buildHandlers() + extraHandlers
        return try await withRuntime(
            task: task,
            eventBus: eventBus,
            handlers: handlers,
            chatId: chatId,
            shouldReviewMemory: shouldReviewMemory,
            shouldReviewSkills: shouldReviewSkills
        ) { runtime in
            try await runtime.execute(buildConfig: buildConfig, runOverrides: runOverrides, sessionId: sessionId)
        }
    }

    func resumeRun(
        sessionId: String,
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides = .default,
        handlerProfile: HandlerProfile,
        extraHandlers: [any EventHandler] = [],
        chatId: Int64? = nil,
        shouldReviewMemory: Bool = false,
        shouldReviewSkills: Bool = false
    ) async throws -> AxionRunResult {
        let handlers = handlerProfile.buildHandlers() + extraHandlers
        return try await withRuntime(
            task: task,
            eventBus: eventBus,
            handlers: handlers,
            chatId: chatId,
            shouldReviewMemory: shouldReviewMemory,
            shouldReviewSkills: shouldReviewSkills
        ) { runtime in
            try await runtime.resumeSession(sessionId, buildConfig: buildConfig, runOverrides: runOverrides)
        }
    }

    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides = .default
    ) async throws -> AxionRunResult {
        let profile = HandlerProfile(
            context: .api,
            config: config,
            memoryDir: ConfigManager.memoryDirectory,
            traceDir: traceDir,
            noMemory: true,
            noReview: true,
            noVisualDelta: true,
            reviewDataContext: nil
        )
        return try await withRuntime(
            task: task,
            eventBus: eventBus,
            handlers: profile.buildHandlers()
        ) { runtime in
            try await runtime.executeSkill(
                skill: skill,
                task: task,
                config: config,
                buildConfig: buildConfig,
                runOverrides: runOverrides
            )
        }
    }

    // MARK: - Shared Runtime Lifecycle

    /// Creates a runtime, registers handlers, runs the event loop, executes the
    /// given body, then tears down gracefully.  All three public methods delegate
    /// here so the runtime lifecycle (create → register → start loop → execute →
    /// stop loop → record session) lives in one place.
    private func withRuntime(
        task: String,
        eventBus: EventBus,
        handlers: [any EventHandler],
        chatId: Int64? = nil,
        shouldReviewMemory: Bool = false,
        shouldReviewSkills: Bool = false,
        execute: @Sendable @escaping (any AxionRuntimeRunning) async throws -> AxionRunResult
    ) async throws -> AxionRunResult {
        let runtime = runtimeFactory(eventBus)

        for handler in handlers {
            await runtime.registerHandler(handler)
        }

        if chatId != nil || shouldReviewMemory || shouldReviewSkills {
            await runtime.setContextOverrides(chatId: chatId, shouldReviewMemory: shouldReviewMemory, shouldReviewSkills: shouldReviewSkills)
        }

        let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

        let result: AxionRunResult
        do {
            result = try await execute(runtime)
        } catch {
            eventLoopTask.cancel()
            await runtime.stopEventLoop()
            throw error
        }

        // Stop the event loop gracefully: finish() on the AsyncStream lets
        // in-flight handler calls (e.g. TGEventHandler sending completion)
        // complete before the `for await` loop exits.
        await runtime.stopEventLoop()
        _ = await eventLoopTask.result

        sessionHistory[result.sessionId] = DaemonSessionInfo(
            sessionId: result.sessionId,
            task: task,
            startedAt: result.createdAt
        )

        evictOldestIfNeeded()

        return result
    }

    func listActiveSessions() -> [DaemonSessionInfo] {
        Array(sessionHistory.values)
    }

    func shutdown() async {
        sessionHistory.removeAll()
    }

    private func evictOldestIfNeeded() {
        guard sessionHistory.count > maxSessionHistory else { return }
        let sortedKeys = sessionHistory.keys.sorted {
            sessionHistory[$0]!.startedAt < sessionHistory[$1]!.startedAt
        }
        let excess = sessionHistory.count - maxSessionHistory
        for key in sortedKeys.prefix(excess) {
            sessionHistory.removeValue(forKey: key)
        }
    }
}
