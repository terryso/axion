import Foundation

/// A single piece of knowledge accumulated by an agent across runs.
///
/// Each entry represents a discrete piece of structured experience that an agent
/// has learned and wishes to persist for future runs.
public struct KnowledgeEntry: Sendable, Equatable {
    /// Unique identifier for this knowledge entry.
    public let id: String
    /// The knowledge text content.
    public let content: String
    /// Categorization tags for filtering.
    public let tags: [String]
    /// When this entry was stored.
    public let createdAt: Date
    /// Which run produced this knowledge, if known.
    public let sourceRunId: String?

    public init(
        id: String,
        content: String,
        tags: [String],
        createdAt: Date,
        sourceRunId: String? = nil
    ) {
        self.id = id
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        self.sourceRunId = sourceRunId
    }
}

/// Filter parameters for querying knowledge entries.
public struct KnowledgeQueryFilter: Sendable, Equatable {
    /// Match entries that have any of these tags. Nil means no tag filter.
    public let tags: [String]?
    /// Only return entries older than this date. Nil means no lower bound.
    public let olderThan: Date?
    /// Only return entries newer than this date. Nil means no upper bound.
    public let newerThan: Date?
    /// Maximum number of entries to return. Nil means no limit.
    public let limit: Int?

    public init(
        tags: [String]? = nil,
        olderThan: Date? = nil,
        newerThan: Date? = nil,
        limit: Int? = nil
    ) {
        self.tags = tags
        self.olderThan = olderThan
        self.newerThan = newerThan
        self.limit = limit
    }
}

/// Protocol for cross-run knowledge accumulation stores.
///
/// Conforming types provide persistent storage for agent knowledge organized by domain.
/// Two implementations are provided:
/// - ``InMemoryStore`` -- volatile, in-process storage (no persistence across restarts)
/// - ``FileBasedMemoryStore`` -- file-backed storage that persists across process restarts
public protocol MemoryStoreProtocol: Sendable {
    /// Store a knowledge entry in the specified domain.
    /// - Parameters:
    ///   - domain: The domain to store the entry under (e.g., "calculator", "navigation").
    ///   - knowledge: The knowledge entry to store.
    func save(domain: String, knowledge: KnowledgeEntry) async throws

    /// Query knowledge entries from a domain, optionally filtering by tags and date range.
    /// - Parameters:
    ///   - domain: The domain to query.
    ///   - filter: Optional filter for tags, date range, and result limit.
    /// - Returns: Array of matching knowledge entries.
    func query(domain: String, filter: KnowledgeQueryFilter?) async throws -> [KnowledgeEntry]

    /// Delete knowledge entries older than the specified date from a domain.
    /// - Parameters:
    ///   - domain: The domain to delete from.
    ///   - olderThan: Entries created before this date will be removed.
    /// - Returns: The number of entries deleted.
    func delete(domain: String, olderThan: Date) async throws -> Int

    /// List all domains that contain knowledge entries.
    /// - Returns: Array of domain names, sorted alphabetically.
    func listDomains() async throws -> [String]
}
