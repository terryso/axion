import ArgumentParser

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "管理 Axion launchd 守护进程",
        subcommands: [
            DaemonInstallCommand.self,
            DaemonStatusCommand.self,
            DaemonUninstallCommand.self,
        ]
    )
}

struct DaemonInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "安装并启动 Axion 守护进程"
    )

    @Option(name: .long, help: "监听地址")
    var host: String = DaemonService.defaultHost

    @Option(name: .long, help: "监听端口")
    var port: Int = DaemonService.defaultPort

    @Option(name: .long, help: "API 认证密钥")
    var authKey: String?

    func validate() throws {
        guard (1...65535).contains(port) else {
            throw ValidationError("--port must be between 1 and 65535")
        }
    }

    func run() async throws {
        let service = DaemonService(
            label: "dev.axion.server",
            subcommand: "server",
            logFileName: "server.log",
            errLogFileName: "server.err.log"
        )
        let path = try service.install(host: host, port: port, authKey: authKey)
        print("Daemon installed successfully")
        print("  Plist: \(path)")
        print("  Host: \(host)")
        print("  Port: \(port)")
        print("  Auth: \(authKey != nil ? "enabled (via AXION_AUTH_KEY)" : "disabled")")
    }
}

struct DaemonStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "查看守护进程状态"
    )

    func run() async throws {
        let service = DaemonService(
            label: "dev.axion.server",
            subcommand: "server"
        )
        let status = service.status()

        switch status.status {
        case .running:
            print("Daemon status: running")
            if let pid = status.pid { print("  PID: \(pid)") }
            if let host = status.host { print("  Host: \(host)") }
            if let port = status.port { print("  Port: \(port)") }
        case .stopped:
            print("Daemon status: stopped")
        case .notInstalled:
            print("Daemon status: not installed")
            print("  Run 'axion daemon install' to install")
        }

        print("  Label: \(status.label)")
        print("  Plist: \(status.plistPath)")
    }
}

struct DaemonUninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "停止并卸载 Axion 守护进程"
    )

    @Flag(name: .long, help: "保留日志文件")
    var keepLogs: Bool = false

    func run() async throws {
        let service = DaemonService(
            label: "dev.axion.server",
            subcommand: "server",
            logFileName: "server.log",
            errLogFileName: "server.err.log"
        )
        try service.uninstall(keepLogs: keepLogs)
        print("Daemon uninstalled successfully")
        if keepLogs {
            print("  Logs preserved at ~/.axion/")
        }
    }
}
