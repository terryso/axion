import ArgumentParser
import Foundation
import OpenAgentSDK

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
        let output = try await Self.performExport(memoryDir: ConfigManager.memoryDirectory, outputFile: outputFile, app: app)
        print(output)
    }

    // MARK: - Public Static API (for testing)

    static func performExport(memoryDir: String, outputFile: String, app: String?) async throws -> String {
        let store = AxionFactStore(memoryDir: memoryDir)

        let domains: [String]
        if let app {
            domains = [app]
        } else {
            domains = try await store.listDomains()
        }

        var exported: [OpenAgentSDK.ExportedDomain] = []
        for domain in domains {
            let facts = try await store.query(domain: domain)
            guard !facts.isEmpty else { continue }
            let sdkFacts = facts.map { $0.toSDKFact() }
            exported.append(OpenAgentSDK.ExportedDomain(domain: domain, facts: sdkFacts))
        }

        let bundle = OpenAgentSDK.MemoryBundle(
            schemaVersion: 1,
            exportedAt: Date(),
            memories: exported
        )

        let service = OpenAgentSDK.MemoryBundleExportService()
        try service.writeBundle(bundle, to: URL(fileURLWithPath: outputFile))

        let factCount = exported.reduce(0) { $0 + $1.facts.count }
        return "Exported \(factCount) facts from \(exported.count) domain(s) to \(outputFile)"
    }

}
