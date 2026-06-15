import ArgumentParser
import Foundation

struct ArchitectureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "arch",
        abstract: "扫描本机软件架构，找出 Intel-only App 和命令行包"
    )

    @Argument(help: "可选过滤词，匹配名称、路径、来源或架构")
    var filter: String?

    @Flag(name: .long, help: "显示所有架构；默认只显示 Intel-only 风险项")
    var all: Bool = false

    @Flag(name: .long, help: "包含 /System/Applications")
    var system: Bool = false

    @Flag(name: .long, help: "只扫描 .app 应用")
    var appsOnly: Bool = false

    @Flag(name: .long, help: "只扫描 Homebrew/MacPorts 命令行包")
    var packagesOnly: Bool = false

    @Option(name: .long, help: "最多显示多少行，默认 80")
    var limit: Int = 80

    nonisolated(unsafe) static var createScanner: @Sendable () -> any AppArchitectureScanning = {
        AppArchitectureScanService()
    }

    func validate() throws {
        guard limit > 0 else {
            throw ValidationError("--limit must be greater than 0")
        }
        guard !(appsOnly && packagesOnly) else {
            throw ValidationError("--apps-only and --packages-only cannot be used together")
        }
    }

    func run() async throws {
        let scanner = Self.createScanner()
        let result = await scanner.scan(options: scanOptions())
        print(AppArchitectureFormatter.render(result), terminator: "")
    }

    func scanOptions() -> AppArchitectureScanOptions {
        AppArchitectureScanOptions(
            filter: filter,
            includeSystemApps: system,
            includeAllArchitectures: all,
            scope: scanScope(),
            limit: limit
        )
    }

    private func scanScope() -> AppArchitectureScanScope {
        if appsOnly { return .appsOnly }
        if packagesOnly { return .packagesOnly }
        return .all
    }
}
