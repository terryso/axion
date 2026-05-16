import ArgumentParser
import Foundation
import Hummingbird

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
        // 1. Load configuration
        let config = try await ConfigManager.loadConfig()

        // 2. Create EventBroadcaster, RunTracker, and ConcurrencyLimiter
        let eventBroadcaster = EventBroadcaster()
        let runTracker = RunTracker(eventBroadcaster: eventBroadcaster)
        let concurrencyLimiter = ConcurrencyLimiter(maxConcurrent: maxConcurrent)

        // 3. Create router and register API routes
        let router = Router()
        AxionAPI.registerRoutes(
            on: router,
            runTracker: runTracker,
            eventBroadcaster: eventBroadcaster,
            config: config,
            authKey: authKey,
            concurrencyLimiter: concurrencyLimiter
        )

        // 4. Create Hummingbird Application
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(host, port: port)
            )
        )

        // 5. Display startup message
        print("Axion API server running on port \(port)")
        print("  Listening on \(host):\(port)")
        print("  Auth: \(authKey != nil ? "enabled" : "disabled")")
        print("  Max concurrent tasks: \(maxConcurrent)")
        print("  Press Ctrl+C to stop")

        // 6. Start server — Hummingbird handles SIGINT/SIGTERM graceful shutdown
        try await app.runService()

        // 7. After server stops, wait for active tasks (max 30s)
        await waitForActiveTasks(limiter: concurrencyLimiter, timeout: 30)
    }
}

/// Wait for active tasks to complete with a timeout, then cancel queued tasks.
private func waitForActiveTasks(limiter: ConcurrencyLimiter, timeout: Int) async {
    let active = await limiter.activeRunCount
    if active > 0 {
        print("Shutting down: waiting for \(active) active task(s) to complete (max \(timeout)s)...")
        let deadline = ContinuousClock.now + .seconds(timeout)
        while await limiter.activeRunCount > 0 {
            if ContinuousClock.now >= deadline {
                print("Shutdown timeout — forcing shutdown with \(await limiter.activeRunCount) task(s) still active.")
                break
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    let queuedBeforeCancel = await limiter.queueDepth
    if queuedBeforeCancel > 0 {
        await limiter.cancelAll()
        print("Cancelled \(queuedBeforeCancel) queued task(s).")
    }

    print("Server shut down complete.")
}
