import ArgumentParser
import Foundation
import Hummingbird
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
        let runtimeManager = Self.createRuntimeManager(traceDir)

        let server = AgentHTTPServer(
            agent: placeholderAgent,
            host: host,
            port: port,
            authKey: resolvedAuthKey,
            maxConcurrentRuns: 10,
            dataDir: nil
        )

        let runner = GatewayRunner(server: server)

        server.runHandler = { [runCoordinator, config, runtimeManager, runner] task, request, tracker, broadcaster, persistence, limiter in
            guard await runner.isAcceptingTasks else { return }

            await runner.taskStarted()

            let runs = await tracker.listRuns()
            let sdkRunId = runs.first(where: { $0.task == task && $0.status == .queued })?.runId
            guard let runId = sdkRunId else {
                await runner.taskFinished()
                return
            }

            await limiter.acquire()
            await tracker.updateRun(runId: runId, status: .running)
            await runCoordinator.submitRunWithId(runId, task: task, request: request)

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
                    runOverrides: .default
                )
            } catch {
                await bridge.stop()
                await runCoordinator.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0, costTelemetry: nil)
                await tracker.updateRun(runId: runId, status: .failed)
                await broadcaster.complete(runId: runId)
                await limiter.release()
                await runner.taskFinished()
                return
            }
            await bridge.stop()

            let apiStatus: APIRunStatus = result.state == .completed ? .completed : .failed
            await runCoordinator.updateRun(
                runId: runId,
                status: apiStatus,
                steps: [],
                totalSteps: result.totalSteps,
                durationMs: result.durationMs,
                replanCount: 0,
                costTelemetry: nil
            )

            let sdkStatus = OpenAgentSDK.APIRunStatus(rawValue: apiStatus.rawValue) ?? .failed
            await tracker.updateRun(
                runId: runId,
                status: sdkStatus,
                totalSteps: result.totalSteps,
                durationMs: result.durationMs
            )

            await limiter.release()
            await runner.taskFinished()
        }

        server.customRouteBuilder = { [runCoordinator, eventBroadcaster, config, skillRegistry] router, _, _, _, _ in
            AxionAPI.registerCustomRoutes(
                on: router,
                runCoordinator: runCoordinator,
                eventBroadcaster: eventBroadcaster,
                config: config,
                maxConcurrentRuns: 10,
                skillRegistry: skillRegistry
            )
        }

        print("Axion Gateway running on port \(port)")
        print("  Listening on \(host):\(port)")
        print("  Auth: \(resolvedAuthKey != nil ? "enabled" : "disabled")")
        print("  Press Ctrl+C to stop")
        fflush(stdout)

        setupSignalHandlers(runner: runner)

        try await runner.start()
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

// MARK: - Placeholder Subcommands

struct GatewayNotImplementedError: Error, CustomStringConvertible {
    let subcommand: String
    var description: String { "'\(subcommand)' is not yet implemented" }
}

struct GatewayInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "安装 Gateway launchd 服务"
    )

    func run() async throws {
        throw GatewayNotImplementedError(subcommand: "gateway install")
    }
}

struct GatewayStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "查看 Gateway 状态"
    )

    func run() async throws {
        throw GatewayNotImplementedError(subcommand: "gateway status")
    }
}

struct GatewayUninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "卸载 Gateway 服务"
    )

    func run() async throws {
        throw GatewayNotImplementedError(subcommand: "gateway uninstall")
    }
}
