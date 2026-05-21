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

        let server = AgentHTTPServer(
            agent: placeholderAgent,
            host: host,
            port: port,
            authKey: resolvedAuthKey,
            maxConcurrentRuns: maxConcurrent,
            dataDir: nil
        )

        server.runHandler = { [runCoordinator, config] task, request, tracker, broadcaster, persistence, limiter in
            await limiter.acquire()

            let runId = await runCoordinator.submitRun(task: task, request: request)

            let result = await ApiRunner.runAgent(
                config: config,
                task: task,
                options: request,
                runId: runId,
                eventBroadcaster: broadcaster,
                runTracker: runCoordinator,
                verbose: false,
                completion: { _, _, _, _, _, _, _ in }
            )

            await runCoordinator.updateRun(
                runId: runId,
                status: result.finalStatus,
                steps: result.stepSummaries,
                durationMs: result.durationMs,
                replanCount: result.replanCount,
                costTelemetry: result.costTelemetry
            )

            let sdkStatus = OpenAgentSDK.APIRunStatus(rawValue: result.finalStatus.rawValue) ?? .failed
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
