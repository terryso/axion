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

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    func run() async throws {
        // 1. Load configuration
        let config = try await ConfigManager.loadConfig()

        // 2. Create EventBroadcaster and RunTracker
        let eventBroadcaster = EventBroadcaster()
        let runTracker = RunTracker(eventBroadcaster: eventBroadcaster)

        // 3. Create router and register API routes
        let router = Router()
        AxionAPI.registerRoutes(on: router, runTracker: runTracker, eventBroadcaster: eventBroadcaster, config: config)

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
        print("  Press Ctrl+C to stop")

        // 6. Start server with graceful shutdown on SIGINT/SIGTERM
        try await app.runService()
    }
}
