import ArgumentParser
import Foundation
import OpenAgentSDK

/// `axion memory list` — display accumulated Memory for all known Apps.
///
/// Scans the Memory directory for JSON files (one per domain), reads each to
/// count entries and determine the most recent operation timestamp, then
/// outputs a formatted summary.
struct MemoryListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "列出所有 App Memory"
    )

    func run() async throws {
        let memoryDir = resolveMemoryDir()
        let output = try await Self.listMemory(in: memoryDir)
        print(output)
    }

    // MARK: - Public Static API (for testing)

    /// Result type for a single domain's memory summary.
    struct DomainSummary {
        let domain: String
        let entryCount: Int
        let lastUsed: Date?
    }

    /// List all Memory domains and their summaries from the given directory.
    ///
    /// - Parameter memoryDir: The filesystem path to the Memory directory.
    /// - Returns: A formatted string listing all domains with counts and dates.
    static func listMemory(in memoryDir: String) async throws -> String {
        let summaries = loadDomainSummaries(from: memoryDir)

        guard !summaries.isEmpty else {
            return "No App Memory found.\nTotal: 0 apps"
        }

        var lines: [String] = ["App Memory:"]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for summary in summaries.sorted(by: { $0.domain < $1.domain }) {
            let dateStr: String
            if let date = summary.lastUsed {
                dateStr = dateFormatter.string(from: date)
            } else {
                dateStr = "unknown"
            }
            lines.append("  \(summary.domain) — \(summary.entryCount) entries, last used \(dateStr)")
        }

        let totalEntries = summaries.reduce(0) { $0 + $1.entryCount }
        lines.append("Total: \(summaries.count) apps, \(totalEntries) entries")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Load domain summaries by scanning the memory directory for JSON files.
    private static func loadDomainSummaries(from memoryDir: String) -> [DomainSummary] {
        let fm = FileManager.default

        var fileNames: [String]
        do {
            fileNames = try fm.contentsOfDirectory(atPath: memoryDir)
        } catch {
            return []
        }

        var summaries: [DomainSummary] = []

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for fileName in fileNames {
            guard fileName.hasSuffix(".json") else { continue }
            let domain = String(fileName.dropLast(5)) // Remove ".json"
            let filePath = (memoryDir as NSString).appendingPathComponent(fileName)

            guard let data = fm.contents(atPath: filePath),
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { continue }

            let entryCount = jsonArray.count
            var lastUsed: Date?

            for entry in jsonArray {
                if let dateStr = entry["createdAt"] as? String,
                   let date = isoFormatter.date(from: dateStr) {
                    if lastUsed == nil || date > lastUsed! {
                        lastUsed = date
                    }
                }
            }

            summaries.append(DomainSummary(
                domain: domain,
                entryCount: entryCount,
                lastUsed: lastUsed
            ))
        }

        return summaries
    }

    /// Resolve the default Memory directory path.
    private func resolveMemoryDir() -> String {
        let configDir = ConfigManager.defaultConfigDirectory
        return (configDir as NSString).appendingPathComponent("memory")
    }
}
