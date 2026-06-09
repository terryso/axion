import ArgumentParser

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
