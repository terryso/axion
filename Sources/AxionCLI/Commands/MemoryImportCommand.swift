import ArgumentParser
import Foundation

/// `axion memory import <input-file>` — import Memory from a JSON bundle.
struct MemoryImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "从 JSON 文件导入 Memory"
    )

    @Argument(help: "导入文件路径")
    var inputFile: String

    func run() async throws {
        let memoryDir = resolveMemoryDir()
        let store = MemoryFactStore(memoryDir: memoryDir)
        let service = MemoryBundleImportService()

        let inputURL = URL(fileURLWithPath: inputFile)
        let result = try await service.importBundle(from: inputURL, store: store)

        var lines: [String] = [
            "Import complete:",
            "  Domains processed: \(result.domainsProcessed)",
            "  Facts imported: \(result.factsImported)",
            "  Facts merged: \(result.factsMerged)",
        ]
        if !result.errors.isEmpty {
            lines.append("  Errors: \(result.errors.count)")
            for error in result.errors {
                lines.append("    - \(error)")
            }
        }
        print(lines.joined(separator: "\n"))
    }

    // MARK: - Public Static API (for testing)

    static func performImport(memoryDir: String, inputFile: String) async throws -> String {
        let store = MemoryFactStore(memoryDir: memoryDir)
        let service = MemoryBundleImportService()

        let inputURL = URL(fileURLWithPath: inputFile)
        let result = try await service.importBundle(from: inputURL, store: store)

        var lines: [String] = [
            "Import complete:",
            "  Domains processed: \(result.domainsProcessed)",
            "  Facts imported: \(result.factsImported)",
            "  Facts merged: \(result.factsMerged)",
        ]
        if !result.errors.isEmpty {
            lines.append("  Errors: \(result.errors.count)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func resolveMemoryDir() -> String {
        let configDir = ConfigManager.defaultConfigDirectory
        return (configDir as NSString).appendingPathComponent("memory")
    }
}
