import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore

struct ServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "server",
        abstract: "启动 HTTP API 服务器"
    )

    // Test seams — overridden in unit tests to inject mocks.
    nonisolated(unsafe) static var createRuntime: @Sendable (EventBus) -> any AxionRuntimeRunning = { AxionRuntime(eventBus: $0) }
    nonisolated(unsafe) static var createBridge: (@Sendable (EventBus, EventBroadcaster, String) -> EventBusBridge)?
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

        let infra = await createServerInfrastructure()

        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))

        let traceDir = ConfigManager.traceDirectory
        let memoryDir = ConfigManager.memoryDirectory
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

        server.runHandler = { [infra, config, runtimeManager, apiProfile] task, request, tracker, broadcaster, persistence, limiter in
            guard let runId = await resolveSDKRunId(from: tracker, task: task) else { return }

            await limiter.acquire()
            await tracker.updateRun(runId: runId, status: .running)
            await infra.runCoordinator.submitRunWithId(runId, task: task, request: request)

            let eventBus = EventBus()
            let bridge: EventBusBridge
            if let factory = Self.createBridge {
                bridge = factory(eventBus, broadcaster, runId)
            } else {
                bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: runId)
            }
            await bridge.start(onComplete: { })

            let buildConfig = AgentBuilder.BuildConfig.forAPI(
                config: config,
                task: task,
                request: request
            )

            let result: AxionRunResult
            do {
                result = try await runtimeManager.executeRun(
                    task: task,
                    buildConfig: buildConfig,
                    eventBus: eventBus,
                    runOverrides: .default,
                    handlerProfile: apiProfile,
                    extraHandlers: [],
                    sessionId: runId,
                    chatId: nil,
                    shouldReviewMemory: false,
                    shouldReviewSkills: false
                )
            } catch {
                await handleRunFailure(
                    bridge: bridge, runCoordinator: infra.runCoordinator,
                    tracker: tracker, broadcaster: broadcaster,
                    limiter: limiter, runId: runId
                )
                return
            }
            await bridge.stop()
            await handleRunSuccess(
                result: result, runCoordinator: infra.runCoordinator,
                tracker: tracker, limiter: limiter, runId: runId
            )
        }

        server.customRouteBuilder = { [infra, config] router, _, _, _, _ in
            AxionAPI.registerCustomRoutes(
                on: router,
                runCoordinator: infra.runCoordinator,
                eventBroadcaster: infra.eventBroadcaster,
                config: config,
                maxConcurrentRuns: maxConcurrent,
                skillRegistry: infra.skillRegistry
            )
        }

        printServerBanner(
            name: "Axion API server",
            host: host,
            port: port,
            authEnabled: resolvedAuthKey != nil,
            extraLines: ["Max concurrent tasks: \(maxConcurrent)"]
        )

        try await server.start()
    }
}
