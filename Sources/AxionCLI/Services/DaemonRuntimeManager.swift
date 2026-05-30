import Foundation
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
        runOverrides: AxionRuntime.RunOverrides = .default
    ) async throws -> AxionRunResult {
        return try await executeRun(
            task: task,
            buildConfig: buildConfig,
            eventBus: eventBus,
            runOverrides: runOverrides,
            extraHandlers: []
        )
    }

    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides = .default,
        extraHandlers: [any EventHandler]
    ) async throws -> AxionRunResult {
        let runtime = runtimeFactory(eventBus)

        await runtime.registerHandler(CostEventHandler())
        await runtime.registerHandler(TraceEventHandler(traceDir: traceDir))
        for handler in extraHandlers {
            await runtime.registerHandler(handler)
        }

        let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

        let result: AxionRunResult
        do {
            result = try await runtime.execute(buildConfig: buildConfig, runOverrides: runOverrides)
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

        // Evict oldest entries when history exceeds limit
        if sessionHistory.count > maxSessionHistory {
            let sortedKeys = sessionHistory.keys.sorted {
                sessionHistory[$0]!.startedAt < sessionHistory[$1]!.startedAt
            }
            let excess = sessionHistory.count - maxSessionHistory
            for key in sortedKeys.prefix(excess) {
                sessionHistory.removeValue(forKey: key)
            }
        }

        return result
    }

    func resumeRun(
        sessionId: String,
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides = .default,
        extraHandlers: [any EventHandler]
    ) async throws -> AxionRunResult {
        let runtime = runtimeFactory(eventBus)

        await runtime.registerHandler(CostEventHandler())
        await runtime.registerHandler(TraceEventHandler(traceDir: traceDir))
        for handler in extraHandlers {
            await runtime.registerHandler(handler)
        }

        let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

        let result: AxionRunResult
        do {
            result = try await runtime.resumeSession(sessionId, buildConfig: buildConfig, runOverrides: runOverrides)
        } catch {
            eventLoopTask.cancel()
            await runtime.stopEventLoop()
            throw error
        }

        await runtime.stopEventLoop()
        _ = await eventLoopTask.result

        sessionHistory[result.sessionId] = DaemonSessionInfo(
            sessionId: result.sessionId,
            task: task,
            startedAt: result.createdAt
        )

        if sessionHistory.count > maxSessionHistory {
            let sortedKeys = sessionHistory.keys.sorted {
                sessionHistory[$0]!.startedAt < sessionHistory[$1]!.startedAt
            }
            let excess = sessionHistory.count - maxSessionHistory
            for key in sortedKeys.prefix(excess) {
                sessionHistory.removeValue(forKey: key)
            }
        }

        return result
    }

    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides = .default
    ) async throws -> AxionRunResult {
        let runtime = runtimeFactory(eventBus)

        await runtime.registerHandler(CostEventHandler())
        await runtime.registerHandler(TraceEventHandler(traceDir: traceDir))

        let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

        let result: AxionRunResult
        do {
            result = try await runtime.executeSkill(
                skill: skill,
                task: task,
                config: config,
                buildConfig: buildConfig,
                runOverrides: runOverrides
            )
        } catch {
            eventLoopTask.cancel()
            await runtime.stopEventLoop()
            throw error
        }

        // Stop the event loop gracefully: finish() on the AsyncStream lets
        // in-flight handler calls complete before the `for await` loop exits.
        await runtime.stopEventLoop()
        _ = await eventLoopTask.result

        sessionHistory[result.sessionId] = DaemonSessionInfo(
            sessionId: result.sessionId,
            task: task,
            startedAt: result.createdAt
        )

        // Evict oldest entries when history exceeds limit
        if sessionHistory.count > maxSessionHistory {
            let sortedKeys = sessionHistory.keys.sorted {
                sessionHistory[$0]!.startedAt < sessionHistory[$1]!.startedAt
            }
            let excess = sessionHistory.count - maxSessionHistory
            for key in sortedKeys.prefix(excess) {
                sessionHistory.removeValue(forKey: key)
            }
        }

        return result
    }

    func listActiveSessions() -> [DaemonSessionInfo] {
        Array(sessionHistory.values)
    }

    func shutdown() async {
        sessionHistory.removeAll()
    }
}
