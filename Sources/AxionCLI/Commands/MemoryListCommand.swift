import ArgumentParser
import Foundation

/// `axion memory list` — display accumulated Memory for all known Apps
/// and universal memory (MEMORY.md / USER.md) summary.
struct MemoryListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "列出所有 App Memory"
    )

    func run() async throws {
        let output = await Self.listMemory(in: ConfigManager.memoryDirectory)
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

    /// List all Memory domains and their classified fact entries,
    /// plus universal memory summary.
    static func listMemory(in memoryDir: String) async -> String {
        let store = AxionFactStore(memoryDir: memoryDir)

        let domains: [String]
        do {
            domains = try await store.listDomains()
        } catch {
            return "No App Memory found.\nTotal: 0 apps"
        }

        var lines: [String] = []

        // App Memory section
        if domains.isEmpty {
            lines.append("App Memory: none")
        } else {
            lines.append("App Memory:")
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
        }

        // Universal Memory section
        lines.append("")
        lines.append("Universal Memory:")
        let universalStore = UniversalMemoryStore(readOnlyMemoryDir: memoryDir)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        for target in [MemoryTarget.memory, .user] {
            let info = await universalStore.summary(target: target)
            let entryWord = info.count == 1 ? "entry" : "entries"
            let dateStr: String
            if let date = info.lastModified {
                dateStr = dateFormatter.string(from: date)
            } else {
                dateStr = "never"
            }
            lines.append("  \(target.rawValue) — \(info.count) \(entryWord) (last updated: \(dateStr))")
        }

        return lines.joined(separator: "\n")
    }

}
