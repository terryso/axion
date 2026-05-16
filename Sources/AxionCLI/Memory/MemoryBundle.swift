import Foundation

/// Top-level container for a Memory export bundle.
struct MemoryBundle: Codable, Equatable {
    let schemaVersion: Int
    let exportedAt: Date
    let memories: [ExportedDomain]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case memories
    }

    init(schemaVersion: Int = 1, exportedAt: Date = Date(), memories: [ExportedDomain]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.memories = memories
    }
}

/// A single domain's facts within a Memory bundle.
struct ExportedDomain: Codable, Equatable {
    let domain: String
    let facts: [AppMemoryFact]
}
