import Foundation

/// Exports ``AppMemoryFact`` entries as a ``MemoryBundle`` JSON file.
struct MemoryBundleExportService {

    /// Export all domains.
    func exportAll(store: MemoryFactStore) async throws -> MemoryBundle {
        let domains = try await store.listDomains()
        var exported: [ExportedDomain] = []
        for domain in domains {
            let facts = try await store.query(domain: domain)
            if !facts.isEmpty {
                exported.append(ExportedDomain(domain: domain, facts: facts))
            }
        }
        return MemoryBundle(memories: exported)
    }

    /// Export a single domain.
    func exportDomain(store: MemoryFactStore, domain: String) async throws -> MemoryBundle {
        let facts = try await store.query(domain: domain)
        return MemoryBundle(memories: [ExportedDomain(domain: domain, facts: facts)])
    }

    /// Write a bundle to disk using JSON (iso8601, sorted keys, pretty-printed).
    func writeBundle(_ bundle: MemoryBundle, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        try data.write(to: url, options: .atomic)
    }
}
