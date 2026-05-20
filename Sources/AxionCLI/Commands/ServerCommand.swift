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
        // Resolve authKey: CLI flag > environment variable > nil
        let resolvedAuthKey = authKey ?? ProcessInfo.processInfo.environment["AXION_AUTH_KEY"]

        // 1. Load configuration
        let config = try await ConfigManager.loadConfig()

        // 2. Create SDK-based persistence, EventBroadcaster, RunTracker, and ConcurrencyLimiter
        let persistenceService = AxionRunPersistence()
        // Pass SDK's RunPersistenceService to EventBroadcaster so SSE events are persisted to disk.
        // Uses Axion's base directory (~/.axion/api-runs/) instead of SDK's default.
        let axionRunDir = persistenceService.runsDirectory()
        let sdkEventPersistence = RunPersistenceService(baseDirectory: axionRunDir)
        let eventBroadcaster = OpenAgentSDK.EventBroadcaster(persistenceService: sdkEventPersistence)
        let runTracker = AxionRunTracker(
            eventBroadcaster: eventBroadcaster,
            persistenceService: persistenceService
        )
        let concurrencyLimiter = OpenAgentSDK.ConcurrencyLimiter(maxConcurrent: maxConcurrent)

        // 2a. Recover persisted runs from previous server instance
        await AxionRunRecovery.recover(
            from: runTracker,
            persistenceService: persistenceService,
            eventBroadcaster: eventBroadcaster
        )

        // 3. Create SkillRegistry for prompt skill support
        let skillRegistry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: skillRegistry)
        skillRegistry.registerDiscoveredSkills()

        // 4. Create router and register API routes
        let router = Router()
        AxionAPI.registerRoutes(
            on: router,
            runTracker: runTracker,
            eventBroadcaster: eventBroadcaster,
            config: config,
            authKey: resolvedAuthKey,
            concurrencyLimiter: concurrencyLimiter,
            maxConcurrent: maxConcurrent,
            skillRegistry: skillRegistry
        )

        // 5. Create Hummingbird Application
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(host, port: port)
            )
        )

        // 6. Display startup message
        print("Axion API server running on port \(port)")
        print("  Listening on \(host):\(port)")
        print("  Auth: \(resolvedAuthKey != nil ? "enabled" : "disabled")")
        print("  Max concurrent tasks: \(maxConcurrent)")
        print("  Press Ctrl+C to stop")
        fflush(stdout)

        // 7. Start server — Hummingbird handles SIGINT/SIGTERM graceful shutdown
        try await app.runService()

        // 8. After server stops, wait for active tasks (max 30s)
        await waitForActiveTasks(limiter: concurrencyLimiter, timeout: 30)
    }
}

/// Wait for active tasks to complete with a timeout.
private func waitForActiveTasks(limiter: OpenAgentSDK.ConcurrencyLimiter, timeout: Int) async {
    let active = await limiter.activeRunCount
    if active > 0 {
        print("Shutting down: waiting for \(active) active task(s) to complete (max \(timeout)s)...")
        let deadline = ContinuousClock.now + .seconds(timeout)
        while await limiter.activeRunCount > 0 {
            if ContinuousClock.now >= deadline {
                print("Shutdown timeout — forcing shutdown with \(await limiter.activeRunCount) task(s) still active.")
                break
            }
            try? await _Concurrency.Task.sleep(for: .milliseconds(200))
        }
    }

    let queued = await limiter.queueDepth
    if queued > 0 {
        print("Dropping \(queued) queued task(s) on shutdown.")
    }

    print("Server shut down complete.")
}
