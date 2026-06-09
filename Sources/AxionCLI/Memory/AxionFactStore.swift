import Foundation
import OpenAgentSDK

/// Axion-specific persistence layer that serializes ``AppMemoryFact`` with all fields.
///
/// API-compatible with SDK's `FactStore` but preserves Axion-specific fields
/// (`scope`, `cause`, `evidence`) that SDK's `MemoryFact` doesn't have.
/// Uses the same file convention: `{domain}-facts.json`.
actor AxionFactStore {

    private let memoryDir: URL
    private let fileManager = FileManager.default
    private static let factsSuffix = "-facts.json"

    init(memoryDir: String) {
        self.memoryDir = URL(fileURLWithPath: (memoryDir as NSString).expandingTildeInPath)
    }

    init(memoryDir: URL) {
        self.memoryDir = memoryDir
    }

    /// Save (upsert) a single fact for the given domain.
    func save(domain: String, fact: AppMemoryFact) throws {
        var facts = (try? loadFacts(domain: domain)) ?? []
        if let idx = facts.firstIndex(where: { $0.id == fact.id }) {
            facts[idx] = fact
        } else {
            facts.append(fact)
        }
        try writeFacts(domain: domain, facts: facts)
    }

    /// Query facts for a domain, optionally filtering by status and kind.
    func query(domain: String, filter: OpenAgentSDK.FactFilter? = nil) throws -> [AppMemoryFact] {
        var facts = (try? loadFacts(domain: domain)) ?? []
        if let filter {
            if let status = filter.status {
                facts = facts.filter { $0.status.rawValue == status.rawValue }
            }
            if let kind = filter.kind {
                facts = facts.filter { $0.kind.rawValue == kind.rawValue }
            }
        }
        return facts
    }

    /// List all domains that have fact files.
    func listDomains() throws -> [String] {
        guard fileManager.fileExists(atPath: memoryDir.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil)
        var domains = Set<String>()
        for file in files where file.pathExtension == "json" {
            if file.lastPathComponent.hasSuffix(Self.factsSuffix) {
                let name = file.deletingPathExtension().lastPathComponent
                domains.insert(String(name.dropLast(6)))
            }
        }
        return domains.sorted()
    }

    /// Delete all facts for a domain.
    func delete(domain: String) throws {
        let url = factsURL(domain: domain)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Private

    private func factsURL(domain: String) -> URL {
        memoryDir.appendingPathComponent("\(domain)\(Self.factsSuffix)")
    }

    private func loadFacts(domain: String) throws -> [AppMemoryFact] {
        let url = factsURL(domain: domain)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try axionPersistentDecoder.decode([AppMemoryFact].self, from: data)
    }

    private func writeFacts(domain: String, facts: [AppMemoryFact]) throws {
        try fileManager.createDirectory(at: memoryDir, withIntermediateDirectories: true)
        let data = try axionPersistentEncoder.encode(facts)
        try data.write(to: factsURL(domain: domain), options: .atomic)
    }
}
