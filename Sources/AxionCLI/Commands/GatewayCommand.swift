import ArgumentParser
import Foundation
import Hummingbird
import NIOCore
import OpenAgentSDK

import AxionCore

// MARK: - GatewayCommand

struct GatewayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gateway",
        abstract: "管理 Axion Gateway 长驻进程",
        subcommands: [
            GatewayStartCommand.self,
            GatewayInstallCommand.self,
            GatewayStatusCommand.self,
            GatewayUninstallCommand.self,
        ],
        defaultSubcommand: GatewayStartCommand.self
    )
}

// MARK: - GatewayStartCommand

struct GatewayStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "启动 Gateway 前台进程"
    )

    @Option(name: .long, help: "监听端口")
    var port: Int = 4242

    @Option(name: .long, help: "绑定地址")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "API 认证密钥")
    var authKey: String?

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    func validate() throws {
        guard (1...65535).contains(port) else {
            throw ValidationError("--port must be between 1 and 65535")
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
        let reviewDataContext = ReviewDataContext()

        // Create and load GatewaySessionStore for session-aware review triggering
        let gatewaySessionsPath = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("gateway-sessions.json")
        let gatewaySessionStore = GatewaySessionStore(filePath: gatewaySessionsPath)
        try? await gatewaySessionStore.load()

        let gatewayProfile = HandlerProfile(
            context: .gateway,
            config: config,
            memoryDir: memoryDir,
            traceDir: traceDir,
            noMemory: false,
            noReview: false,
            noVisualDelta: false,
            reviewDataContext: reviewDataContext
        )
        let reviewScheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: traceDir,
            memoryDir: memoryDir,
            gatewaySessionStore: gatewaySessionStore
        )
        let curatorScheduler = Self.makeCuratorScheduler(
            config: config,
            reviewDataContext: reviewDataContext,
            traceDir: traceDir
        )
        let server = AgentHTTPServer(
            agent: placeholderAgent,
            host: host,
            port: port,
            authKey: resolvedAuthKey,
            maxConcurrentRuns: 10,
            dataDir: nil
        )

        let runner = GatewayRunner(server: server)

        server.runHandler = { [infra, runtimeManager, runner, gatewayProfile, reviewScheduler, curatorScheduler] task, request, tracker, broadcaster, persistence, limiter in
            guard await runner.isAcceptingTasks else { return }

            await runner.taskStarted()

            let currentConfig: AxionConfig
            do {
                currentConfig = try await ConfigManager.loadConfig()
            } catch {
                await runner.taskFinished()
                return
            }

            guard let runId = await resolveSDKRunId(from: tracker, task: task) else {
                await runner.taskFinished()
                return
            }

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
                config: currentConfig,
                task: task,
                request: request
            )

            let result: AxionRunResult
            do {
                let runOverrides = AxionRuntime.RunOverrides(
                    json: false,
                    noVisualDelta: false,
                    noReview: false,
                    onReviewCompleted: nil,
                    reviewDataContext: gatewayProfile.reviewDataContext,
                    nonInteractivePause: false, registerResumeHandle: nil
                )
                let extraHandlers: [any EventHandler] = [reviewScheduler] + (curatorScheduler.map { [$0] } ?? [])
                result = try await runtimeManager.executeRun(
                    task: task,
                    buildConfig: buildConfig,
                    eventBus: eventBus,
                    runOverrides: runOverrides,
                    handlerProfile: gatewayProfile,
                    extraHandlers: extraHandlers,
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
                await runner.taskFinished()
                return
            }
            await bridge.stop()
            await handleRunSuccess(
                result: result, runCoordinator: infra.runCoordinator,
                tracker: tracker, limiter: limiter, runId: runId
            )
            await runner.taskFinished()
        }

        server.customRouteBuilder = { [infra, config, runner] router, _, _, _, _ in
            AxionAPI.registerCustomRoutes(
                on: router,
                runCoordinator: infra.runCoordinator,
                eventBroadcaster: infra.eventBroadcaster,
                config: config,
                maxConcurrentRuns: 10,
                skillRegistry: infra.skillRegistry
            )

            // GET /v1/gateway/status — live gateway runtime status
            router.get("gateway/status") { _, _ in
                let status = await runner.getStatus()
                let data = try axionSortedEncoder.encode(status)
                let body = ByteBuffer(data: data)
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: body)
                )
            }
        }

        printServerBanner(
            name: "Axion Gateway",
            host: host,
            port: port,
            authEnabled: resolvedAuthKey != nil
        )

        setupSignalHandlers(runner: runner)

        await setupTelegramAdapter(
            config: config,
            infra: infra,
            runtimeManager: runtimeManager,
            runner: runner,
            reviewScheduler: reviewScheduler,
            curatorScheduler: curatorScheduler,
            gatewaySessionStore: gatewaySessionStore,
            gatewayProfile: gatewayProfile
        )

        try await runner.start()
    }

    private static func makeCuratorScheduler(
        config: AxionConfig,
        reviewDataContext: ReviewDataContext,
        traceDir: String
    ) -> CuratorScheduler? {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            return nil
        }

        let curatorIdleHours = config.gatewayCuratorIdleHours ?? 2.0
        let curatorIntervalHours = config.gatewayCuratorIntervalHours ?? 168.0

        let curatorSkillRegistry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: curatorSkillRegistry)
        _ = curatorSkillRegistry.registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)

        let curatorDeps = AgentBuilder.buildCuratorDeps(
            config: config,
            apiKey: apiKey,
            memoryDir: ConfigManager.memoryDirectory,
            skillsDir: ConfigManager.skillsDirectory,
            skillRegistry: curatorSkillRegistry,
            intervalHours: curatorIntervalHours
        )

        return CuratorScheduler(
            curatorIdleHours: curatorIdleHours,
            curatorIntervalHours: curatorIntervalHours,
            curator: curatorDeps.intelligentCurator,
            agentProvider: { [weak reviewDataContext] in
                reviewDataContext?.agent
            },
            traceDir: traceDir
        )
    }

    // Test seams
    nonisolated(unsafe) static var createRuntimeManager: @Sendable (String) -> any DaemonRuntimeManaging = { DaemonRuntimeManager(traceDir: $0) }
    nonisolated(unsafe) static var createBridge: (@Sendable (EventBus, EventBroadcaster, String) -> EventBusBridge)?
}


// MARK: - Signal Handling

extension GatewayStartCommand {
    nonisolated(unsafe) private static var signalHandlerRunner: GatewayRunner?

    private func setupSignalHandlers(runner: GatewayRunner) {
        Self.signalHandlerRunner = runner

        signal(SIGTERM) { _ in
            _Concurrency.Task { await Self.signalHandlerRunner?.stop(graceful: true) }
        }
        signal(SIGINT) { _ in
            _Concurrency.Task { await Self.signalHandlerRunner?.stop(graceful: false) }
        }
    }
}

