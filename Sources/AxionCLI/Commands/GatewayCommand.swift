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

        let reviewDataContext = ReviewDataContext()
        let reviewScheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: traceDir
        )

        // CuratorScheduler: assemble IntelligentCurator + dependencies
        let curatorIdleHours = config.gatewayCuratorIdleHours ?? 2.0
        let curatorIntervalHours = config.gatewayCuratorIntervalHours ?? 168.0

        let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
        let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
        let curatorUsageStore = SkillUsageStore(skillsDir: skillsDir)
        let curatorStore = SkillCuratorStore(skillsDir: skillsDir)
        let curatorFactStore = FactStore(memoryDir: memoryDir)
        let curatorSkillRegistry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: curatorSkillRegistry)
        _ = curatorSkillRegistry.registerDiscoveredSkills()
        let curatorConfig = SkillCuratorConfig(
            intervalHours: curatorIntervalHours,
            staleAfterDays: config.curatorStaleAfterDays ?? 30,
            archiveAfterDays: config.curatorArchiveAfterDays ?? 90,
            dryRun: config.curatorDryRun ?? false,
            enabled: config.curatorEnabled ?? true
        )
        let curatorSkillCurator = SkillCurator(
            usageStore: curatorUsageStore,
            curatorStore: curatorStore,
            config: curatorConfig
        )
        let notifyCuratorResults = config.gatewayNotifyCuratorResults ?? false
        let curatorScheduler: CuratorScheduler?
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            let evolverClient = AnthropicClient(apiKey: apiKey, baseURL: config.baseURL)
            let evolutionModel = config.reviewModel ?? AxionConfig.defaultReviewModel
            let curatorEvolver = LLMSkillEvolver(client: evolverClient, evolutionModel: evolutionModel)
            let intelligentCurator = IntelligentCurator(
                skillCurator: curatorSkillCurator,
                factStore: curatorFactStore,
                skillRegistry: curatorSkillRegistry,
                skillEvolver: curatorEvolver,
                usageStore: curatorUsageStore,
                curatorStore: curatorStore
            )
            curatorScheduler = CuratorScheduler(
                curatorIdleHours: curatorIdleHours,
                curatorIntervalHours: curatorIntervalHours,
                curator: intelligentCurator,
                agentProvider: { [weak reviewDataContext] in
                    reviewDataContext?.agent
                },
                traceDir: traceDir
            )
        } else {
            curatorScheduler = nil
        }

        let server = AgentHTTPServer(
            agent: placeholderAgent,
            host: host,
            port: port,
            authKey: resolvedAuthKey,
            maxConcurrentRuns: 10,
            dataDir: nil
        )

        let runner = GatewayRunner(server: server)

        server.runHandler = { [runCoordinator, config, runtimeManager, runner, reviewScheduler, curatorScheduler, reviewDataContext] task, request, tracker, broadcaster, persistence, limiter in
            guard await runner.isAcceptingTasks else { return }

            await runner.taskStarted()

            // SDK boundary limitation: the runHandler callback does not expose the runId
            // it created, so we find it by matching task text + .queued status. This is
            // ambiguous when identical tasks are queued concurrently — a fix requires an
            // SDK API change to pass runId into the callback.
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
                let runOverrides = AxionRuntime.RunOverrides(
                    json: false,
                    noVisualDelta: false,
                    noReview: false,
                    onReviewCompleted: nil,
                    reviewDataContext: reviewDataContext
                )
                result = try await runtimeManager.executeRun(
                    task: task,
                    buildConfig: buildConfig,
                    eventBus: eventBus,
                    runOverrides: runOverrides,
                    extraHandlers: [reviewScheduler] + (curatorScheduler.map { [$0] } ?? []),
                    sessionId: runId
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
        if let tgToken = config.telegramBotToken {
            let allowedUsersStr = config.telegramAllowedUsers ?? ""
            let allowedUsers = Set(allowedUsersStr.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            })

            let tgClient = TGAPIClient(token: tgToken)

            let taskSerialQueue = TaskSerialQueue(
                runtimeManager: runtimeManager,
                config: config,
                runner: runner,
                extraHandlers: [reviewScheduler] + (curatorScheduler.map { [$0] } ?? []),
                replyHandler: { (chatId: Int64, message: String) -> Int64? in
                    // Adapter not yet created; will be wired below
                    return nil
                },
                editHandler: { (chatId: Int64, messageId: Int64, text: String) -> Bool in
                    // Adapter not yet created; will be wired below
                    return false
                }
            )

            let commandRouter = TGCommandRouter(
                statusProvider: { [runner] in await runner.getStatus() },
                skillsProvider: { [skillRegistry] in skillRegistry.userInvocableSkills },
                clearSession: { [taskSerialQueue] chatId in
                    await taskSerialQueue.clearSession(chatId: chatId)
                }
            )

            let adapter = TelegramAdapter(apiClient: tgClient, allowedUsers: allowedUsers, taskQueue: taskSerialQueue, commandRouter: commandRouter)

            // Re-wire replyHandler to use the now-created adapter
            await taskSerialQueue.updateReplyHandler({ [weak adapter] chatId, message in
                guard let adapter else { return nil }
                return await adapter.sendFormatted(message, to: chatId)
            })

            // Re-wire editHandler to use the now-created adapter
            await taskSerialQueue.updateEditHandler({ [weak adapter] chatId, messageId, text in
                guard let adapter else { return false }
                return await adapter.editMessage(chatId: chatId, messageId: messageId, text: text)
            })

            await adapter.setTaskQueue(taskSerialQueue)
            await runner.setTaskSerialQueue(taskSerialQueue)
            await runner.setTelegramAdapter(adapter)

            await runner.setStatusProviders(
                tgStatus: { [weak adapter] in adapter?.statusValue },
                reviewStatus: { [weak reviewScheduler] in reviewScheduler?.lastReviewAtValue },
                reviewSummary: { [weak reviewScheduler] in reviewScheduler?.lastReviewSummaryValue },
                curatorStatus: { [weak curatorScheduler] in curatorScheduler?.lastCuratorAtValue }
            )

            // Wire curator result callback for TG push
            let tgChatIds: [Int64] = allowedUsers.compactMap { Int64($0) }
            if notifyCuratorResults {
                await curatorScheduler?.setOnCuratorResult { [weak adapter] info in
                    guard info.success else {
                        for chatId in tgChatIds {
                            await adapter?.sendReply("⚠️ 后台策展失败: \(info.error ?? "unknown error")", to: chatId)
                        }
                        return
                    }
                    guard info.consolidations > 0 || info.prunings > 0 else { return }
                    var parts: [String] = []
                    if info.consolidations > 0 {
                        parts.append("合并 \(info.consolidations) 个技能")
                    }
                    if info.prunings > 0 {
                        parts.append("归档 \(info.prunings) 个技能")
                    }
                    let message = "🔧 策展完成: \(parts.joined(separator: ", "))"
                    for chatId in tgChatIds {
                        await adapter?.sendReply(message, to: chatId)
                    }
                }
            }

            // Wire review result callback: the per-request EventBus is stopped before
            // the detached review task completes, so we use a direct callback instead.
            await reviewScheduler.setOnReviewResult { [weak adapter] event in
                guard event.success else {
                    for chatId in tgChatIds {
                        await adapter?.sendReply("⚠️ 后台审查失败", to: chatId)
                    }
                    return
                }
                guard !event.memoryChanges.isEmpty || !event.skillChanges.isEmpty else { return }
                var parts: [String] = []
                if !event.memoryChanges.isEmpty {
                    parts.append("新增 \(event.memoryChanges.count) 条记忆")
                }
                if !event.skillChanges.isEmpty {
                    parts.append("更新 \(event.skillChanges.count) 个技能")
                }
                let message = "📊 审查完成: \(parts.joined(separator: ", "))"
                for chatId in tgChatIds {
                    await adapter?.sendReply(message, to: chatId)
                }
            }

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
                reviewStatus: { [weak reviewScheduler] in reviewScheduler?.lastReviewAtValue },
                reviewSummary: { [weak reviewScheduler] in reviewScheduler?.lastReviewSummaryValue },
                curatorStatus: { [weak curatorScheduler] in curatorScheduler?.lastCuratorAtValue }
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
        if let reviewSummary = status.lastReviewSummary {
            print("  Last review summary: \(reviewSummary)")
        }
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
