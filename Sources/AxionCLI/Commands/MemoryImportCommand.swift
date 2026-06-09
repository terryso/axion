import ArgumentParser
import Foundation
import OpenAgentSDK

/// `axion memory import <input-file>` — import Memory from a JSON bundle.
struct MemoryImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "从 JSON 文件导入 Memory"
    )

    @Argument(help: "导入文件路径")
    var inputFile: String

    func run() async throws {
        let output = try await Self.performImport(memoryDir: ConfigManager.memoryDirectory, inputFile: inputFile)
        print(output)
    }

    // MARK: - Public Static API (for testing)

    static func performImport(memoryDir: String, inputFile: String) async throws -> String {
        let store = AxionFactStore(memoryDir: memoryDir)
        let lifecycleService = OpenAgentSDK.MemoryLifecycleService()

        let inputURL = URL(fileURLWithPath: inputFile)
        let data = try Data(contentsOf: inputURL)

        let bundle: OpenAgentSDK.MemoryBundle
        do {
            bundle = try axionPersistentDecoder.decode(OpenAgentSDK.MemoryBundle.self, from: data)
        } catch {
            throw OpenAgentSDK.MemoryBundleError.invalidBundle(reason: "Invalid JSON: \(error.localizedDescription)")
        }

        guard bundle.schemaVersion == 1 else {
            throw OpenAgentSDK.MemoryBundleError.invalidBundle(reason: "Unsupported schema_version: \(bundle.schemaVersion)")
        }

        var domainsProcessed = 0
        var factsImported = 0
        var factsMerged = 0

        for exportedDomain in bundle.memories {
            domainsProcessed += 1
            let domain = exportedDomain.domain

            let existingFacts = (try? await store.query(domain: domain)) ?? []
            let sdkExisting = existingFacts.map { $0.toSDKFact() }

            for sdkFact in exportedDomain.facts {
                // Downgrade imported fact
                let downgraded = OpenAgentSDK.MemoryFact(
                    id: sdkFact.id,
                    domain: sdkFact.domain,
                    content: sdkFact.content,
                    status: .candidate,
                    confidence: min(sdkFact.confidence, 0.55),
                    evidenceCount: sdkFact.evidenceCount,
                    source: .imported,
                    kind: sdkFact.kind,
                    createdAt: sdkFact.createdAt,
                    lastVerifiedAt: sdkFact.lastVerifiedAt
                )

                if sdkExisting.contains(where: { $0.id == sdkFact.id }) {
                    let result = lifecycleService.addFact(downgraded, mergingWith: sdkExisting)
                    let axionFact = AppMemoryFact.fromSDKFact(result)
                    try await store.save(domain: domain, fact: AppMemoryFact.normalizeFact(axionFact))
                    factsMerged += 1
                } else {
                    let axionFact = AppMemoryFact.fromSDKFact(downgraded)
                    try await store.save(domain: domain, fact: AppMemoryFact.normalizeFact(axionFact))
                    factsImported += 1
                }
            }
        }

        let lines: [String] = [
            "Import complete:",
            "  Domains processed: \(domainsProcessed)",
            "  Facts imported: \(factsImported)",
            "  Facts merged: \(factsMerged)",
        ]
        return lines.joined(separator: "\n")
    }

}
