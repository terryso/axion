import ArgumentParser
import Foundation
import Hummingbird
import OpenAgentSDK

import AxionCore

struct ServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "server",
        abstract: "启动 HTTP API 服务器"
    )

    // Test seams — overridden in unit tests to inject mocks.
    nonisolated(unsafe) static var createRuntime: @Sendable (EventBus) -> any AxionRuntimeRunning = { AxionRuntime(eventBus: $0) }
    nonisolated(unsafe) static var createBridge: (@Sendable (EventBus, EventBroadcaster, String) -> EventBusBridge)? = nil
    nonisolated(unsafe) static var createRuntimeManager: @Sendable (String) -> any DaemonRuntimeManaging = { DaemonRuntimeManager(traceDir: $0) }

    @Option(name: .long, help: "监听端口")
    var port: Int = 4242

    @Option(name: .long, help: "绑定地址")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "API 认证密钥")
    var authKey: String?

    @Option(name: .long, help: "最大并发任务数")
    var maxConcurrent: Int = 10

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    func validate() throws {
        guard maxConcurrent >= 1 else {
            throw ValidationError("--max-concurrent must be >= 1")
        }
    }

    func run() async throws {
        let resolvedAuthKey = authKey ?? ProcessInfo.processInfo.environment["AXION_AUTH_KEY"]

        let config = try await ConfigManager.loadConfig()

        let sdkPersistence = RunPersistenceService(baseDirectory: nil)
        let eventBroadcaster = OpenAgentSDK.EventBroadcaster(persistenceService: sdkPersistence)
        let runCoordinator = RunCoordinator(
            eventBroadcaster: eventBroadcaster,
            persistenceService: sdkPersistence
        )

        let skillRegistry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: skillRegistry)
        skillRegistry.registerDiscoveredSkills()

        await AxionRunRecovery.recover(
            from: runCoordinator,
            persistenceService: sdkPersistence,
            eventBroadcaster: eventBroadcaster
        )

        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))

        let traceDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("runs")
        let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
        let runtimeManager = Self.createRuntimeManager(traceDir)

        let apiProfile = HandlerProfile(
            context: .api,
            config: config,
            memoryDir: memoryDir,
            traceDir: traceDir,
            noMemory: true,
            noReview: true,
            noVisualDelta: true,
            reviewDataContext: nil
        )

        let server = AgentHTTPServer(
            agent: placeholderAgent,
            host: host,
            port: port,
            authKey: resolvedAuthKey,
            maxConcurrentRuns: maxConcurrent,
            dataDir: nil
        )

        server.runHandler = { [runCoordinator, config, runtimeManager, apiProfile] task, request, tracker, broadcaster, persistence, limiter in
            // SDK boundary limitation: the runHandler callback does not expose the runId
            // it created, so we find it by matching task text + .queued status. This is
            // ambiguous when identical tasks are queued concurrently — a fix requires an
            // SDK API change to pass runId into the callback.
            let runs = await tracker.listRuns()
            let sdkRunId = runs.first(where: { $0.task == task && $0.status == .queued })?.runId
            guard let runId = sdkRunId else {
                return
            }

            await limiter.acquire()

            // Mark as running in SDK tracker
            await tracker.updateRun(runId: runId, status: .running)

            // Track in Axion's RunCoordinator using the SDK's runId
            await runCoordinator.submitRunWithId(runId, task: task, request: request)

            // Create per-request EventBus
            let eventBus = EventBus()

            // Create EventBusBridge to forward events → SSE
            let bridge: EventBusBridge
            if let factory = Self.createBridge {
                bridge = factory(eventBus, broadcaster, runId)
            } else {
                bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: runId)
            }
            await bridge.start(onComplete: { })

            // Build config from request
            let buildConfig = AgentBuilder.BuildConfig.forAPI(
                config: config,
                task: task,
                request: request
            )

            // Execute via DaemonRuntimeManager — pass sdkRunId so AxionRuntime
            // uses the same ID for session transcript instead of generating a second one.
            let result: AxionRunResult
            do {
                result = try await runtimeManager.executeRun(
                    task: task,
                    buildConfig: buildConfig,
                    eventBus: eventBus,
                    runOverrides: .default,
                    handlerProfile: apiProfile,
                    extraHandlers: [],
                    sessionId: runId
                )
            } catch {
                await bridge.stop()

                await runCoordinator.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0, costTelemetry: nil)
                await tracker.updateRun(runId: runId, status: .failed)
                await broadcaster.complete(runId: runId)
                await limiter.release()
                return
            }
            await bridge.stop()

            // Map result state to API status
            let apiStatus: APIRunStatus = result.state == .completed ? .completed : .failed

            // Update RunCoordinator (also emits runCompleted SSE and completes stream)
            await runCoordinator.updateRun(
                runId: runId,
                status: apiStatus,
                steps: [],
                totalSteps: result.totalSteps,
                durationMs: result.durationMs,
                replanCount: 0,
                costTelemetry: nil
            )

            // Update SDK tracker
            let sdkStatus = OpenAgentSDK.APIRunStatus(rawValue: apiStatus.rawValue) ?? .failed
            await tracker.updateRun(
                runId: runId,
                status: sdkStatus,
                totalSteps: result.totalSteps,
                durationMs: result.durationMs
            )

            await limiter.release()
        }

        server.customRouteBuilder = { [runCoordinator, eventBroadcaster, config, skillRegistry] router, _, _, _, _ in
            AxionAPI.registerCustomRoutes(
                on: router,
                runCoordinator: runCoordinator,
                eventBroadcaster: eventBroadcaster,
                config: config,
                maxConcurrentRuns: maxConcurrent,
                skillRegistry: skillRegistry
            )
        }

        print("Axion API server running on port \(port)")
        print("  Listening on \(host):\(port)")
        print("  Auth: \(resolvedAuthKey != nil ? "enabled" : "disabled")")
        print("  Max concurrent tasks: \(maxConcurrent)")
        print("  Press Ctrl+C to stop")
        fflush(stdout)

        try await server.start()
    }
}
