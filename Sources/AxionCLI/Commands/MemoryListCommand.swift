import ArgumentParser
import Foundation
import OpenAgentSDK

/// `axion memory list` — display accumulated Memory for all known Apps.
///
/// Scans the Memory directory for fact files, reads each to display classified
/// memory entries with status icons, kind labels, confidence, and evidence counts.
struct MemoryListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "列出所有 App Memory"
    )

    func run() async throws {
        let memoryDir = resolveMemoryDir()
        let output = await Self.listMemory(in: memoryDir)
        print(output)
    }

    // MARK: - Public Static API (for testing)

    /// Status icon mapping.
    static let statusIcons: [MemoryFactStatus: String] = [
        .active: "✓",
        .candidate: "○",
        .retired: "✗",
    ]

    /// Kind display label mapping.
    static let kindLabels: [MemoryKind: String] = [
        .affordance: "推荐",
        .avoid: "警告",
        .observation: "备注",
    ]

    /// List all Memory domains and their classified fact entries.
    static func listMemory(in memoryDir: String) async -> String {
        let store = AxionFactStore(memoryDir: memoryDir)

        let domains: [String]
        do {
            domains = try await store.listDomains()
        } catch {
            return "No App Memory found.\nTotal: 0 apps"
        }

        guard !domains.isEmpty else {
            return "No App Memory found.\nTotal: 0 apps"
        }

        var lines: [String] = ["App Memory:"]
        var totalFacts = 0

        for domain in domains.sorted() {
            let facts: [AppMemoryFact]
            do {
                facts = try await store.query(domain: domain)
            } catch {
                lines.append("  \(domain) — error reading facts")
                continue
            }

            guard !facts.isEmpty else { continue }
            totalFacts += facts.count
            lines.append("  \(domain) (\(facts.count) facts)")
            lines.append("  ──────────────────────────────")

            for fact in facts {
                let icon = statusIcons[fact.status] ?? "?"
                let kindLabel = kindLabels[fact.kind] ?? fact.kind.rawValue
                let summary = String(fact.description.prefix(80))
                lines.append("    \(icon) [\(kindLabel)] confidence:\(String(format: "%.2f", fact.confidence)) evidence:\(fact.evidenceCount)")
                lines.append("      \(summary)")
            }
            lines.append("")
        }

        lines.append("Total: \(domains.count) apps, \(totalFacts) facts")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Resolve the default Memory directory path.
    private func resolveMemoryDir() -> String {
        let configDir = ConfigManager.defaultConfigDirectory
        return (configDir as NSString).appendingPathComponent("memory")
    }
}
