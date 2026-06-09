import ArgumentParser
import Foundation

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
