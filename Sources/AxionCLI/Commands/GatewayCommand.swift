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

        server.customRouteBuilder = { [runCoordinator, eventBroadcaster, config, skillRegistry, runner] router, _, _, _, _ in
            AxionAPI.registerCustomRoutes(
                on: router,
                runCoordinator: runCoordinator,
                eventBroadcaster: eventBroadcaster,
                config: config,
                maxConcurrentRuns: 10,
                skillRegistry: skillRegistry
            )

            // GET /v1/gateway/status — live gateway runtime status
            router.get("gateway/status") { _, _ in
                let status = await runner.getStatus()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(status)
                let body = ByteBuffer(data: data)
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: body)
                )
            }
        }

        print("Axion Gateway running on port \(port)")
        print("  Listening on \(host):\(port)")
        print("  Auth: \(resolvedAuthKey != nil ? "enabled" : "disabled")")
        print("  Press Ctrl+C to stop")
        fflush(stdout)

        setupSignalHandlers(runner: runner)

        // Telegram adapter setup
        if let tgToken = ProcessInfo.processInfo.environment["AXION_TELEGRAM_BOT_TOKEN"] {
            let allowedUsersStr = ProcessInfo.processInfo.environment["AXION_TELEGRAM_ALLOWED_USERS"] ?? ""
            let allowedUsers = Set(allowedUsersStr.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            })

            let tgClient = TGAPIClient(token: tgToken)

            let commandRouter = TGCommandRouter(
                statusProvider: { [runner] in await runner.getStatus() },
                skillsProvider: { [skillRegistry] in skillRegistry.userInvocableSkills }
            )

            let adapter = TelegramAdapter(apiClient: tgClient, allowedUsers: allowedUsers, commandRouter: commandRouter)

            let taskSerialQueue = TaskSerialQueue(
                runtimeManager: runtimeManager,
                config: config,
                runner: runner,
                replyHandler: { [weak adapter] chatId, message in
                    guard let adapter else { return }
                    await adapter.sendReply(message, to: chatId)
                }
            )

            await adapter.setTaskQueue(taskSerialQueue)
            await runner.setTaskSerialQueue(taskSerialQueue)
            await runner.setTelegramAdapter(adapter)

            await runner.setStatusProviders(
                tgStatus: { [weak adapter] in adapter?.statusValue },
                reviewStatus: nil,
                curatorStatus: nil
            )

            _Concurrency.Task {
                await taskSerialQueue.startProcessing()
            }
            _Concurrency.Task {
                await adapter.start()
            }
            fputs("[axion] Telegram adapter starting\n", stderr)
        } else {
            fputs("[axion] Telegram bot token not configured, adapter disabled\n", stderr)
            await runner.setStatusProviders(
                tgStatus: { "disabled" },
                reviewStatus: nil,
                curatorStatus: nil
            )
        }

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

// MARK: - Gateway Subcommands

struct GatewayInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "安装 Gateway launchd 服务"
    )

    @Option(name: .long, help: "监听地址")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "监听端口")
    var port: Int = 4242

    @Option(name: .long, help: "API 认证密钥")
    var authKey: String?

    func validate() throws {
        guard (1...65535).contains(port) else {
            throw ValidationError("--port must be between 1 and 65535")
        }
    }

    func run() async throws {
        let tgToken = ProcessInfo.processInfo.environment["AXION_TELEGRAM_BOT_TOKEN"]
        let tgUsers = ProcessInfo.processInfo.environment["AXION_TELEGRAM_ALLOWED_USERS"]

        var envVars: [String: String] = [:]
        if let tgToken { envVars["AXION_TELEGRAM_BOT_TOKEN"] = tgToken }
        if let tgUsers { envVars["AXION_TELEGRAM_ALLOWED_USERS"] = tgUsers }

        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: "gateway.log",
            errLogFileName: "gateway.err.log",
            keepAliveCrashOnly: true,
            environmentVariables: envVars.isEmpty ? nil : envVars
        )
        let path = try service.install(host: host, port: port, authKey: authKey)
        print("Gateway installed successfully")
        print("  Plist: \(path)")
        print("  Host: \(host)")
        print("  Port: \(port)")
        print("  Auth: \(authKey != nil ? "enabled (via AXION_AUTH_KEY)" : "disabled")")
        if !envVars.isEmpty {
            print("  TG Bot: configured")
        }
    }
}

struct GatewayStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "查看 Gateway 状态"
    )

    nonisolated(unsafe) static var liveStatusFetcher: (@Sendable (Int) async -> GatewayRunnerStatus?)?

    func run() async throws {
        let logFileName = "gateway.log"
        let errLogFileName = "gateway.err.log"
        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: logFileName,
            errLogFileName: errLogFileName
        )
        let status = service.status()

        // Step 1: If running, try HTTP query for live runtime status
        if status.status == .running {
            let port = status.port ?? 4242
            let liveStatus: GatewayRunnerStatus?

            if let fetcher = Self.liveStatusFetcher {
                liveStatus = await fetcher(port)
            } else {
                liveStatus = try? await Self.queryHTTPStatus(port: port)
            }

            if let live = liveStatus {
                printLiveStatus(live, daemonStatus: status, logFileName: logFileName, errLogFileName: errLogFileName)
                return
            }
        }

        // Step 2: Fallback to DaemonService-level status
        printDaemonStatus(status, logFileName: logFileName, errLogFileName: errLogFileName)
    }

    private static func queryHTTPStatus(port: Int) async throws -> GatewayRunnerStatus {
        let url = URL(string: "http://127.0.0.1:\(port)/v1/gateway/status")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(GatewayRunnerStatus.self, from: data)
    }

    private func printLiveStatus(_ status: GatewayRunnerStatus, daemonStatus: DaemonStatus, logFileName: String, errLogFileName: String) {
        print("Gateway status: \(status.state)")
        if let pid = status.pid ?? daemonStatus.pid { print("  PID: \(pid)") }
        if let host = daemonStatus.host { print("  Host: \(host)") }
        if let port = daemonStatus.port { print("  Port: \(port)") }
        print("  Active tasks: \(status.activeTaskCount)")
        let uptime = Int(status.uptimeSeconds)
        print("  Uptime: \(uptime)s")
        print("  Label: \(status.label)")
        print("  Plist: \(daemonStatus.plistPath)")
        let home = NSHomeDirectory()
        let logDir = (home as NSString).appendingPathComponent(".axion")
        print("  Log: \((logDir as NSString).appendingPathComponent(logFileName))")
        print("  Error log: \((logDir as NSString).appendingPathComponent(errLogFileName))")
        let tgStatus = status.tgConnected ?? "(pending Epic 29/30)"
        print("  TG connection: \(tgStatus)")
        let reviewStatus = status.lastReviewAt ?? "(pending Epic 29/30)"
        print("  Last review: \(reviewStatus)")
        let curatorStatus = status.lastCuratorAt ?? "(pending Epic 29/30)"
        print("  Last curator: \(curatorStatus)")
    }

    private func printDaemonStatus(_ status: DaemonStatus, logFileName: String, errLogFileName: String) {
        switch status.status {
        case .running:
            print("Gateway status: running")
            if let pid = status.pid { print("  PID: \(pid)") }
            if let host = status.host { print("  Host: \(host)") }
            if let port = status.port { print("  Port: \(port)") }
        case .stopped:
            print("Gateway status: stopped")
            if let pid = status.pid { print("  Last PID: \(pid)") }
        case .notInstalled:
            print("Gateway status: not_installed")
            print("  Run 'axion gateway install' to install")
        }

        let home = NSHomeDirectory()
        let logDir = (home as NSString).appendingPathComponent(".axion")
        print("  Label: \(status.label)")
        print("  Plist: \(status.plistPath)")
        print("  Log: \((logDir as NSString).appendingPathComponent(logFileName))")
        print("  Error log: \((logDir as NSString).appendingPathComponent(errLogFileName))")
        print("  TG connection: (pending Epic 29/30)")
        print("  Last review: (pending Epic 29/30)")
        print("  Last curator: (pending Epic 29/30)")
    }
}

struct GatewayUninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "卸载 Gateway 服务"
    )

    @Flag(name: .long, help: "保留日志文件")
    var keepLogs: Bool = false

    func run() async throws {
        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: "gateway.log",
            errLogFileName: "gateway.err.log"
        )
        try service.uninstall(keepLogs: keepLogs)
        print("Gateway uninstalled successfully")
        if keepLogs {
            print("  Logs preserved at ~/.axion/")
        }
    }
}
