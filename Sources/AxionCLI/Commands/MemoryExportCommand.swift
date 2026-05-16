import ArgumentParser
import Foundation

/// `axion memory export [--app <domain>] <output-file>` — export Memory to JSON.
struct MemoryExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "导出 Memory 到 JSON 文件"
    )

    @Argument(help: "导出文件路径")
    var outputFile: String

    @Option(name: .long, help: "只导出指定 App domain（如 com.apple.finder）")
    var app: String?

    func run() async throws {
        let memoryDir = resolveMemoryDir()
        let store = MemoryFactStore(memoryDir: memoryDir)
        let service = MemoryBundleExportService()

        let bundle: MemoryBundle
        if let app {
            bundle = try await service.exportDomain(store: store, domain: app)
        } else {
            bundle = try await service.exportAll(store: store)
        }

        let outputURL = URL(fileURLWithPath: outputFile)
        try service.writeBundle(bundle, to: outputURL)

        let domainCount = bundle.memories.count
        let factCount = bundle.memories.reduce(0) { $0 + $1.facts.count }
        print("Exported \(factCount) facts from \(domainCount) domain(s) to \(outputFile)")
    }

    // MARK: - Public Static API (for testing)

    static func performExport(memoryDir: String, outputFile: String, app: String?) async throws -> String {
        let store = MemoryFactStore(memoryDir: memoryDir)
        let service = MemoryBundleExportService()

        let bundle: MemoryBundle
        if let app {
            bundle = try await service.exportDomain(store: store, domain: app)
        } else {
            bundle = try await service.exportAll(store: store)
        }

        let outputURL = URL(fileURLWithPath: outputFile)
        try service.writeBundle(bundle, to: outputURL)

        let factCount = bundle.memories.reduce(0) { $0 + $1.facts.count }
        let domainCount = bundle.memories.count
        return "Exported \(factCount) facts from \(domainCount) domain(s) to \(outputFile)"
    }

    // MARK: - Private

    private func resolveMemoryDir() -> String {
        let configDir = ConfigManager.defaultConfigDirectory
        return (configDir as NSString).appendingPathComponent("memory")
    }
}
