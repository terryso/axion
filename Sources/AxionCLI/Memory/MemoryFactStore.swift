import Foundation
import OpenAgentSDK

/// Actor-isolated persistence layer for ``AppMemoryFact`` entries.
///
/// Stores facts as JSON files at `{memoryDir}/{domain}-facts.json`.
/// Performs lazy migration from legacy ``KnowledgeEntry`` files when
/// reading old `{domain}.json` data.
actor MemoryFactStore {

    private let memoryDir: URL
    private let fileManager = FileManager.default

    private static let factsSuffix = "-facts.json"

    init(memoryDir: String) {
        self.memoryDir = URL(fileURLWithPath: (memoryDir as NSString).expandingTildeInPath)
    }

    init(memoryDir: URL) {
        self.memoryDir = memoryDir
    }

    // MARK: - CRUD

    /// Save (upsert) a fact for the given domain.
    func save(domain: String, fact: AppMemoryFact) throws {
        var facts = (try? loadFacts(domain: domain)) ?? []
        if let idx = facts.firstIndex(where: { $0.id == fact.id }) {
            facts[idx] = fact
        } else {
            facts.append(fact)
        }
        try writeFacts(domain: domain, facts: facts)
    }

    /// Save multiple facts for a domain in a single write.
    func saveAll(domain: String, facts: [AppMemoryFact]) throws {
        var existing = (try? loadFacts(domain: domain)) ?? []
        for fact in facts {
            if let idx = existing.firstIndex(where: { $0.id == fact.id }) {
                existing[idx] = fact
            } else {
                existing.append(fact)
            }
        }
        try writeFacts(domain: domain, facts: existing)
    }

    /// Query facts for a domain, optionally filtering by status.
    func query(domain: String, filter: FactFilter? = nil) throws -> [AppMemoryFact] {
        var facts = (try? loadFacts(domain: domain)) ?? []
        if let filter {
            if let status = filter.status {
                facts = facts.filter { $0.status == status }
            }
            if let kind = filter.kind {
                facts = facts.filter { $0.kind == kind }
            }
        }
        return facts
    }

    /// List all domains that have fact files.
    ///
    /// Discovers both new-format `*-facts.json` and legacy `*.json` files.
    /// Legacy files are lazily migrated on discovery.
    func listDomains() throws -> [String] {
        guard fileManager.fileExists(atPath: memoryDir.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil)

        var domains = Set<String>()

        for file in files where file.pathExtension == "json" {
            if file.lastPathComponent.hasSuffix(Self.factsSuffix) {
                let name = file.deletingPathExtension().lastPathComponent
                domains.insert(String(name.dropLast(6)))
            } else {
                let domain = file.deletingPathExtension().lastPathComponent
                _ = try? loadFacts(domain: domain)
                domains.insert(domain)
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

    private func legacyURL(domain: String) -> URL {
        memoryDir.appendingPathComponent("\(domain).json")
    }

    private func loadFacts(domain: String) throws -> [AppMemoryFact] {
        let url = factsURL(domain: domain)

        // Try new format first
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([AppMemoryFact].self, from: data)
        }

        // Lazy migration: try legacy KnowledgeEntry format
        let legacy = legacyURL(domain: domain)
        if fileManager.fileExists(atPath: legacy.path) {
            return try migrateLegacy(domain: domain, from: legacy)
        }

        return []
    }

    /// Migrate legacy KnowledgeEntry file to AppMemoryFact format.
    private func migrateLegacy(domain: String, from url: URL) throws -> [AppMemoryFact] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let formatterWithMs = ISO8601DateFormatter()
        formatterWithMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoMs = ISO8601DateFormatter()
        formatterNoMs.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = formatterWithMs.date(from: dateString) ?? formatterNoMs.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Cannot parse date: \(dateString)")
        }

        // KnowledgeEntry array from SDK
        struct LegacyEntry: Decodable {
            let id: String
            let content: String
            let tags: [String]
            let createdAt: Date
        }

        let legacyEntries = try decoder.decode([LegacyEntry].self, from: data)
        let facts: [AppMemoryFact] = legacyEntries.map { entry in
            AppMemoryFact(
                id: entry.id,
                domain: domain,
                kind: .observation,
                status: .candidate,
                confidence: 0.5,
                evidenceCount: 1,
                source: .local,
                scope: nil,
                cause: nil,
                description: entry.content,
                updatedAt: entry.createdAt,
                evidence: []
            )
        }

        // Write migrated data to new format
        if !facts.isEmpty {
            try writeFacts(domain: domain, facts: facts)
        }
        return facts
    }

    private func writeFacts(domain: String, facts: [AppMemoryFact]) throws {
        try fileManager.createDirectory(at: memoryDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(facts)
        try data.write(to: factsURL(domain: domain), options: .atomic)
    }
}

/// Filter for querying facts.
struct FactFilter: Sendable, Equatable {
    let status: MemoryFactStatus?
    let kind: MemoryKind?

    init(status: MemoryFactStatus? = nil, kind: MemoryKind? = nil) {
        self.status = status
        self.kind = kind
    }
}
