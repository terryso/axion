import Foundation
import OpenAgentSDK

import AxionCore

public actor AxionRuntime: AxionRuntimeRunning, AxionRuntimeResuming, SessionListing {
    let eventBus: EventBus?
    let executor: RunExecuting
    let builder: AgentBuilding
    let sessionStore: SessionStore
    let sessionsDir: String
    private(set) var currentState: AxionRunState = .created
    private(set) var sessionId: String?
    private(set) var createdAt: Date?
    private(set) var externallyModified: Bool = false
    private var externallyModifiedFlag = ExternallyModifiedFlag()
    private(set) var takeoverEvent: RunMemoryProcessor.TakeoverEventContext?
    private(set) var lastRunCompleteContext: RunCompleteContext?
    private var handlers: [any EventHandler] = []
    private var eventSubscriptionId: UUID?

    init(eventBus: EventBus? = nil, executor: RunExecuting = DefaultRunExecutor(), builder: AgentBuilding = DefaultAgentBuilder(), sessionStore: SessionStore? = nil) {
        self.eventBus = eventBus
        self.executor = executor
        self.builder = builder
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        self.sessionsDir = dir
        self.sessionStore = sessionStore ?? SessionStore(sessionsDir: dir)
    }

    struct RunOverrides: Sendable {
        let json: Bool
        let noVisualDelta: Bool
        let noReview: Bool
        let onReviewCompleted: (@Sendable (String) -> Void)?
        let reviewDataContext: ReviewDataContext?

        static let `default` = RunOverrides(
            json: false, noVisualDelta: false, noReview: false, onReviewCompleted: nil, reviewDataContext: nil
        )
    }

    public nonisolated var state: AxionRunState {
        get async { await currentState }
    }

    func run(
        task: String,
        buildResult: AgentBuildResult,
        runConfig: RunOrchestrator.RunConfig,
        resumeSessionId: String? = nil
    ) async throws -> AxionRunResult {
        let sid = resumeSessionId ?? executor.generateRunId()
        let startedAt = Date()
        sessionId = sid
        createdAt = startedAt

        guard currentState.isValidTransition(to: .running) else {
            currentState = .failed
            return AxionRunResult(
                sessionId: sid, task: task, state: .failed,
                totalSteps: 0, durationMs: 0, runSucceeded: false,
                errorMessage: "Invalid state transition from \(currentState) to running",
                createdAt: startedAt
            )
        }
        currentState = .running
        externallyModifiedFlag = ExternallyModifiedFlag()
        try? writeAxionState(
            sessionId: sid, status: AxionRunState.running.rawValue,
            totalSteps: 0, durationMs: 0
        )

        let modifiedConfig = RunOrchestrator.RunConfig(
            task: runConfig.task,
            fast: runConfig.fast,
            dryrun: runConfig.dryrun,
            json: runConfig.json,
            noMemory: runConfig.noMemory,
            noVisualDelta: runConfig.noVisualDelta,
            allowForeground: runConfig.allowForeground,
            maxSteps: runConfig.maxSteps,
            config: runConfig.config,
            noReview: runConfig.noReview,
            onReviewCompleted: runConfig.onReviewCompleted,
            eventBus: eventBus,
            reviewDataContext: runConfig.reviewDataContext
        )

        do {
            let result = try await executor.execute(
                buildResult: buildResult,
                runConfig: modifiedConfig
            )
            externallyModified = result.externallyModified
            takeoverEvent = result.takeoverEvent
            lastRunCompleteContext = result.runCompleteContext
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
            currentState = .failed
            try? writeAxionState(
                sessionId: sid, status: AxionRunState.failed.rawValue,
                totalSteps: 0, durationMs: 0
            )
            try? await saveSessionFirstPrompt(sessionId: sid, task: task)
            return AxionRunResult(
                sessionId: sid,
                task: task,
                state: .failed,
                totalSteps: 0,
                durationMs: 0,
                runSucceeded: false,
                errorMessage: error.localizedDescription,
                createdAt: startedAt
            )
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

        // Inject sessionId + sessionStore into buildConfig so SDK writes transcript.json
        let sessionedBuildConfig = AgentBuilder.BuildConfig(
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
            runId: sid,
            sessionId: sid,
            sessionStore: sessionStore
        )

        let buildResult: AgentBuildResult
        do {
            buildResult = try await builder.build(sessionedBuildConfig, eventBus: eventBus)
        } catch {
            currentState = .failed
            try? writeAxionState(
                sessionId: sid, status: AxionRunState.failed.rawValue,
                totalSteps: 0, durationMs: 0
            )
            return AxionRunResult(
                sessionId: sid, task: buildConfig.task, state: .failed,
                totalSteps: 0, durationMs: 0, runSucceeded: false,
                errorMessage: error.localizedDescription,
                createdAt: startedAt
            )
        }

        let runConfig = RunOrchestrator.RunConfig(
            task: buildConfig.task,
            fast: buildConfig.fast,
            dryrun: buildConfig.dryrun,
            json: runOverrides.json,
            noMemory: buildConfig.noMemory,
            noVisualDelta: runOverrides.noVisualDelta,
            allowForeground: buildConfig.allowForeground,
            maxSteps: buildConfig.maxSteps,
            config: buildConfig.config,
            noReview: runOverrides.noReview,
            onReviewCompleted: runOverrides.onReviewCompleted,
            eventBus: eventBus,
            reviewDataContext: runOverrides.reviewDataContext
        )

        return try await run(task: buildConfig.task, buildResult: buildResult, runConfig: runConfig, resumeSessionId: sid)
    }

    // MARK: - Skill Execution

    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: RunOverrides = .default
    ) async throws -> AxionRunResult {
        let sid = executor.generateRunId()
        let startedAt = Date()
        sessionId = sid
        createdAt = startedAt

        guard currentState.isValidTransition(to: .running) else {
            currentState = .failed
            return AxionRunResult(
                sessionId: sid, task: task, state: .failed,
                totalSteps: 0, durationMs: 0, runSucceeded: false,
                errorMessage: "Invalid state transition from \(currentState) to running",
                createdAt: startedAt
            )
        }
        currentState = .running
        externallyModifiedFlag = ExternallyModifiedFlag()
        try? writeAxionState(
            sessionId: sid, status: AxionRunState.running.rawValue,
            totalSteps: 0, durationMs: 0
        )

        do {
            let (agent, skillRunCompleteBox) = try await builder.buildSkillAgent(
                config: config,
                skill: skill,
                maxSteps: buildConfig.maxSteps,
                verbose: buildConfig.verbose,
                eventBus: eventBus
            )

            let args = RunOrchestrator.parseSkillName(from: task).flatMap { skillName in
                let prefix = "/\(skillName) "
                return task.hasPrefix(prefix) ? String(task.dropFirst(prefix.count)) : nil
            }

            let startTime = ContinuousClock.now
            var totalSteps = 0

            let runMode = runOverrides.json ? "json" : (buildConfig.fast ? "fast" : "standard")
            let outputHandler: any SDKMessageOutputHandler = runOverrides.json
                ? SDKJSONOutputHandler(mode: runMode)
                : SDKTerminalOutputHandler(mode: runMode)
            outputHandler.displayRunStart(runId: sid, task: task)
            fputs("[axion] 执行: Skill (via AxionRuntime)\n", stderr)

            let skillStream = agent.executeSkillStream(skill.name, args: args)
            var lastResponseText: String?
            for await message in skillStream {
                if _Concurrency.Task.isCancelled { break }
                if case .toolUse = message { totalSteps += 1 }
                if case .assistant(let data) = message { lastResponseText = data.text }
                outputHandler.handle(message)
            }

            let elapsed = ContinuousClock.now - startTime
            let durationMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)

            try? await agent.close()
            currentState = .completed
            try? writeAxionState(
                sessionId: sid, status: AxionRunState.completed.rawValue,
                totalSteps: totalSteps, durationMs: durationMs
            )

            let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
            let usageStore = SkillUsageStore(skillsDir: skillsDir)
            try? await usageStore.bumpView(skillName: skill.name)

            fputs("[axion] 运行结束。步数: \(totalSteps), 耗时: \(String(format: "%.1f", Double(durationMs) / 1000))s\n", stderr)

            let ctxWrapper = skillRunCompleteBox.context.map { ctx in
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

            return AxionRunResult(
                sessionId: sid, task: task, state: .completed,
                totalSteps: totalSteps, durationMs: durationMs,
                runSucceeded: true, runCompleteContext: ctxWrapper,
                responseText: lastResponseText, createdAt: startedAt
            )
        } catch {
            currentState = .failed
            try? writeAxionState(
                sessionId: sid, status: AxionRunState.failed.rawValue,
                totalSteps: 0, durationMs: 0
            )
            return AxionRunResult(
                sessionId: sid, task: task, state: .failed,
                totalSteps: 0, durationMs: 0, runSucceeded: false,
                errorMessage: error.localizedDescription, createdAt: startedAt
            )
        }
    }

    // MARK: - Session Resume

    func resumeSession(
        _ sessionId: String,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: RunOverrides = .default
    ) async throws -> AxionRunResult {
        // 1. Validate session exists
        guard let _ = try await sessionStore.load(sessionId: sessionId) else {
            throw AxionError.sessionNotFound(id: sessionId)
        }

        // 2. Validate session is not already running
        if let overlay = loadOverlay(sessionId: sessionId), overlay.status == "running" {
            throw AxionError.sessionAlreadyRunning(id: sessionId)
        }

        // 3. Reset state for this session (run() will set sessionId/createdAt)
        currentState = .created

        // 4. Inject sessionId + sessionStore into BuildConfig for SDK restore
        let resumeBuildConfig = AgentBuilder.BuildConfig(
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
            sessionStore: sessionStore
        )

        // 5. Build agent
        let buildResult: AgentBuildResult
        do {
            buildResult = try await builder.build(resumeBuildConfig, eventBus: eventBus)
        } catch {
            currentState = .failed
            return AxionRunResult(
                sessionId: sessionId, task: buildConfig.task, state: .failed,
                totalSteps: 0, durationMs: 0, runSucceeded: false,
                errorMessage: error.localizedDescription,
                createdAt: Date()
            )
        }

        // 6. Execute via existing run() with resumeSessionId
        let runConfig = RunOrchestrator.RunConfig(
            task: buildConfig.task,
            fast: buildConfig.fast,
            dryrun: buildConfig.dryrun,
            json: runOverrides.json,
            noMemory: buildConfig.noMemory,
            noVisualDelta: runOverrides.noVisualDelta,
            allowForeground: buildConfig.allowForeground,
            maxSteps: buildConfig.maxSteps,
            config: buildConfig.config,
            noReview: runOverrides.noReview,
            onReviewCompleted: runOverrides.onReviewCompleted,
            eventBus: eventBus,
            reviewDataContext: runOverrides.reviewDataContext
        )

        return try await run(
            task: buildConfig.task,
            buildResult: buildResult,
            runConfig: runConfig,
            resumeSessionId: sessionId
        )
    }

    // MARK: - Session Lifecycle

    func createSession(task: String, config: AxionConfig) throws -> String {
        let sid = executor.generateRunId()
        sessionId = sid
        createdAt = Date()
        try writeAxionState(
            sessionId: sid, status: AxionRunState.created.rawValue,
            totalSteps: 0, durationMs: 0
        )
        return sid
    }

    // MARK: - Handler Management

    func registerHandler(_ handler: any EventHandler) {
        handlers.append(handler)
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

    private func dispatchToHandlers(_ event: any AgentEvent) async {
        let context = EventHandlerContext(
            sessionId: sessionId,
            config: AxionConfig(apiKey: ""),
            eventBus: eventBus,
            externallyModified: externallyModified,
            externallyModifiedFlag: externallyModifiedFlag,
            takeoverEvent: takeoverEvent,
            runCompleteContext: lastRunCompleteContext,
            sessionStore: sessionStore
        )
        for handler in handlers {
            let shouldDispatch = await shouldDispatch(event: event, to: handler)
            guard shouldDispatch else { continue }
            do {
                await handler.handle(event, context: context)
            } catch {
                let id = await handler.identifier
                fputs("[axion] handler '\(id)' error: \(error.localizedDescription)\n", stderr)
            }
        }
        // Sync flag back from handlers (e.g. SeatMonitorHandler sets it on external activity)
        if externallyModifiedFlag.value {
            externallyModified = true
        }
    }

    private func shouldDispatch(event: any AgentEvent, to handler: any EventHandler) async -> Bool {
        let types = await handler.subscribedEventTypes
        if types.isEmpty { return true }
        return types.contains { type(of: event) == $0 }
    }

    // MARK: - Session Queries

    func listSessions(limit: Int? = nil) async throws -> [SessionInfo] {
        let metadataList = try await sessionStore.list(limit: limit)
        return metadataList.map { md in
            let overlay = loadOverlay(sessionId: md.id)
            return SessionInfo(
                sessionId: md.id,
                cwd: md.cwd,
                model: md.model,
                createdAt: md.createdAt,
                updatedAt: md.updatedAt,
                messageCount: md.messageCount,
                summary: md.summary ?? md.firstPrompt,
                status: overlay?.status ?? "unknown",
                totalSteps: overlay?.totalSteps ?? 0,
                durationMs: overlay?.durationMs
            )
        }
    }

    func getSession(_ sessionId: String) async throws -> SessionInfo? {
        guard let data = try await sessionStore.load(sessionId: sessionId) else {
            return nil
        }
        let md = data.metadata
        let overlay = loadOverlay(sessionId: md.id)
        return SessionInfo(
            sessionId: md.id,
            cwd: md.cwd,
            model: md.model,
            createdAt: md.createdAt,
            updatedAt: md.updatedAt,
            messageCount: md.messageCount,
            summary: md.summary,
            status: overlay?.status ?? "unknown",
            totalSteps: overlay?.totalSteps ?? 0,
            durationMs: overlay?.durationMs
        )
    }

    // MARK: - Axion State Persistence

    /// Visible for testing — writes axion-state.json for a session.
    func writeAxionState(sessionId: String, status: String, totalSteps: Int, durationMs: Int) throws {
        let sessionDir = (sessionsDir as NSString).appendingPathComponent(sessionId)
        try FileManager.default.createDirectory(
            atPath: sessionDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let overlay = AxionStateOverlay(
            status: status,
            totalSteps: totalSteps,
            durationMs: durationMs,
            updatedAt: formatter.string(from: Date())
        )
        let data = try JSONEncoder().encode(overlay)
        let statePath = (sessionDir as NSString).appendingPathComponent("axion-state.json")
        FileManager.default.createFile(
            atPath: statePath,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
    }

    private func loadOverlay(sessionId: String) -> AxionStateOverlay? {
        let statePath = ((sessionsDir as NSString).appendingPathComponent(sessionId) as NSString)
            .appendingPathComponent("axion-state.json")
        guard let data = FileManager.default.contents(atPath: statePath) else { return nil }
        return try? JSONDecoder().decode(AxionStateOverlay.self, from: data)
    }

    /// Save firstPrompt into the session transcript so `sessions` can display the task.
    /// Re-reads the existing transcript, injects firstPrompt, and saves back.
    private func saveSessionFirstPrompt(sessionId: String, task: String) async throws {
        let transcriptPath = ((sessionsDir as NSString).appendingPathComponent(sessionId) as NSString)
            .appendingPathComponent("transcript.json")
        guard let data = FileManager.default.contents(atPath: transcriptPath),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var metadata = dict["metadata"] as? [String: Any]
        else { return }

        if metadata["firstPrompt"] == nil {
            metadata["firstPrompt"] = task
            dict["metadata"] = metadata
            if let updated = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                FileManager.default.createFile(atPath: transcriptPath, contents: updated, attributes: [.posixPermissions: 0o600])
            }
        }
    }
}
