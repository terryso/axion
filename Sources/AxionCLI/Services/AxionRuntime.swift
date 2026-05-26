import Foundation
import OpenAgentSDK

import AxionCore

public actor AxionRuntime {
    let eventBus: EventBus?
    let sessionStore: SessionStore
    private(set) var currentState: AxionRunState = .created
    private(set) var sessionId: String?
    private(set) var createdAt: Date?
    private(set) var externallyModified: Bool = false
    private(set) var takeoverEvent: RunMemoryProcessor.TakeoverEventContext?
    private(set) var lastRunCompleteContext: RunCompleteContext?

    public init(eventBus: EventBus? = nil) {
        self.eventBus = eventBus
        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        self.sessionStore = SessionStore(sessionsDir: sessionsDir)
    }

    struct RunOverrides: Sendable {
        let json: Bool
        let noVisualDelta: Bool
        let noReview: Bool
        let onReviewCompleted: (@Sendable (String) -> Void)?

        static let `default` = RunOverrides(
            json: false, noVisualDelta: false, noReview: false, onReviewCompleted: nil
        )
    }

    public nonisolated var state: AxionRunState {
        get async { await currentState }
    }

    func run(
        task: String,
        buildResult: AgentBuildResult,
        runConfig: RunOrchestrator.RunConfig
    ) async throws -> AxionRunResult {
        let sid = RunOrchestrator.generateRunId()
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
            eventBus: eventBus
        )

        do {
            let result = try await RunOrchestrator.execute(
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
            return AxionRunResult(
                sessionId: sid,
                task: task,
                state: .completed,
                totalSteps: result.totalSteps,
                durationMs: result.durationMs,
                runSucceeded: result.runSucceeded,
                runCompleteContext: ctxWrapper,
                createdAt: startedAt
            )
        } catch {
            currentState = .failed
            try? writeAxionState(
                sessionId: sid, status: AxionRunState.failed.rawValue,
                totalSteps: 0, durationMs: 0
            )
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
        runOverrides: RunOverrides = .default
    ) async throws -> AxionRunResult {
        let sid = RunOrchestrator.generateRunId()
        let startedAt = Date()
        sessionId = sid
        createdAt = startedAt

        let buildResult: AgentBuildResult
        do {
            buildResult = try await AgentBuilder.build(buildConfig)
        } catch {
            currentState = .failed
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
            eventBus: eventBus
        )

        return try await run(task: buildConfig.task, buildResult: buildResult, runConfig: runConfig)
    }

    // MARK: - Session Lifecycle

    func createSession(task: String, config: AxionConfig) throws -> String {
        let sid = RunOrchestrator.generateRunId()
        sessionId = sid
        createdAt = Date()
        try writeAxionState(
            sessionId: sid, status: AxionRunState.created.rawValue,
            totalSteps: 0, durationMs: 0
        )
        return sid
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
                summary: md.summary,
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

    private func writeAxionState(sessionId: String, status: String, totalSteps: Int, durationMs: Int) throws {
        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
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
        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let statePath = ((sessionsDir as NSString).appendingPathComponent(sessionId) as NSString)
            .appendingPathComponent("axion-state.json")
        guard let data = FileManager.default.contents(atPath: statePath) else { return nil }
        return try? JSONDecoder().decode(AxionStateOverlay.self, from: data)
    }
}
