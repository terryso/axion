import Foundation

/// A single domain's facts within an exported memory bundle.
public struct ExportedDomain: Codable, Equatable, Sendable {
    public let domain: String
    public let facts: [MemoryFact]

    public init(domain: String, facts: [MemoryFact]) {
        self.domain = domain
        self.facts = facts
    }
}

/// A portable bundle of memory facts for export/import.
///
/// Uses JSON with snake_case coding keys and ISO 8601 dates.
public struct MemoryBundle: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let memories: [ExportedDomain]

    public init(schemaVersion: Int, exportedAt: Date, memories: [ExportedDomain]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.memories = memories
    }

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case memories
    }
}
