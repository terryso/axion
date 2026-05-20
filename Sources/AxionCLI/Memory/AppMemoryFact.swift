import Foundation
import OpenAgentSDK

// Disambiguate: Axion's enums shadow SDK's, so alias SDK types for conversion helpers.
typealias SDKMemoryFact = OpenAgentSDK.MemoryFact
typealias SDKMemoryFactSource = OpenAgentSDK.MemoryFactSource
typealias SDKMemoryKind = OpenAgentSDK.MemoryKind
typealias SDKMemoryFactStatus = OpenAgentSDK.MemoryFactStatus

/// Lifecycle status of a memory fact.
enum MemoryFactStatus: String, Codable, Sendable, Equatable {
    case candidate
    case active
    case retired
}

/// Origin of a memory fact.
enum MemoryFactSource: String, Codable, Sendable, Equatable {
    case local
    case imported
}

/// Classification kind for a memory fact.
enum MemoryKind: String, Codable, Sendable, Equatable {
    case affordance
    case avoid
    case observation
}

/// Application-layer memory fact with lifecycle state and confidence scoring.
///
/// This is an AxionCLI-layer model that augments (not replaces) the SDK's
/// ``KnowledgeEntry``. Facts transition through candidate → active → retired
/// based on evidence accumulation and time-based decay.
struct AppMemoryFact: Codable, Equatable, Sendable {
    /// Deterministic ID derived from kind + description.
    let id: String
    /// The App domain (bundle identifier or app name).
    let domain: String
    /// Classification kind.
    let kind: MemoryKind
    /// Lifecycle status.
    var status: MemoryFactStatus
    /// Confidence score (0.0–1.0).
    var confidence: Double
    /// Number of times this fact has been independently observed.
    var evidenceCount: Int
    /// Where this fact came from.
    let source: MemoryFactSource
    /// Optional scope qualifier (e.g., "window-title:X").
    var scope: String?
    /// Optional cause description (e.g., "workaround").
    var cause: String?
    /// Human-readable description of the fact.
    let description: String
    /// When this fact was last updated.
    var updatedAt: Date
    /// Evidence trail (e.g., run IDs or observation summaries).
    var evidence: [String]

    // MARK: - Factory

    /// Create a new fact with sensible defaults for a first observation.
    static func create(
        domain: String,
        kind: MemoryKind,
        description: String,
        confidence: Double = 0.7,
        scope: String? = nil,
        cause: String? = nil,
        source: MemoryFactSource = .local,
        evidence: [String] = []
    ) -> AppMemoryFact {
        let id = Self.factId(kind: kind, description: description)
        let clamped = min(max(confidence, 0.0), 1.0)
        return AppMemoryFact(
            id: id,
            domain: domain,
            kind: kind,
            status: .candidate,
            confidence: clamped,
            evidenceCount: 1,
            source: source,
            scope: scope,
            cause: cause,
            description: description,
            updatedAt: Date(),
            evidence: evidence
        )
    }

    // MARK: - Normalization

    /// Validate and normalize a fact's numeric fields.
    static func normalizeFact(_ fact: AppMemoryFact) -> AppMemoryFact {
        var f = fact
        f.confidence = min(max(f.confidence, 0.0), 1.0)
        f.evidenceCount = max(f.evidenceCount, 0)
        if f.status != .candidate && f.status != .active && f.status != .retired {
            f.status = .candidate
        }
        return f
    }

    // MARK: - ID Generation

    /// Generate a deterministic fact ID from kind and description.
    /// Uses djb2 hash — stable across process launches (unlike hashValue).
    static func factId(kind: MemoryKind, description: String) -> String {
        let normalized = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var h: UInt64 = 5381
        for byte in normalized.utf8 {
            h = ((h << 5) &+ h) &+ UInt64(byte)
        }
        return "\(kind.rawValue)-\(h)"
    }

    // MARK: - SDK Conversion

    /// Convert to SDK's ``OpenAgentSDK.MemoryFact`` for storage via SDK's ``FactStore``.
    ///
    /// Maps Axion fields to SDK equivalents:
    /// - `description` → `content`
    /// - `updatedAt` → `lastVerifiedAt`
    /// - `source: .local` → `.observation`
    /// - `id` is preserved as-is (Axion's `"kind-hash"` format)
    ///
    /// Note: `scope`, `cause`, and `evidence` have no SDK equivalent and are not
    /// preserved through round-trip storage. Use ``fromSDKFact(_:scope:cause:evidence:)``
    /// to reconstruct with caller-supplied context.
    func toSDKFact() -> SDKMemoryFact {
        let sdkSource: SDKMemoryFactSource = source == .imported ? .imported : .observation
        let now = Date()
        return SDKMemoryFact(
            id: id,
            domain: domain,
            content: description,
            status: SDKMemoryFactStatus(rawValue: status.rawValue) ?? .candidate,
            confidence: confidence,
            evidenceCount: evidenceCount,
            source: sdkSource,
            kind: SDKMemoryKind(rawValue: kind.rawValue) ?? .observation,
            createdAt: now,
            lastVerifiedAt: updatedAt
        )
    }

    /// Reconstruct an ``AppMemoryFact`` from an SDK ``OpenAgentSDK.MemoryFact``.
    ///
    /// - Parameters:
    ///   - sdkFact: The SDK fact to convert from.
    ///   - scope: Axion-specific scope qualifier (e.g., `"skill:open_calculator"`).
    ///   - cause: Axion-specific cause description (e.g., `"workaround"`).
    ///   - evidence: Axion-specific evidence trail.
    /// - Returns: An `AppMemoryFact` with SDK fields mapped back and caller-supplied extras.
    static func fromSDKFact(
        _ sdkFact: SDKMemoryFact,
        scope: String? = nil,
        cause: String? = nil,
        evidence: [String] = []
    ) -> AppMemoryFact {
        let axionSource: MemoryFactSource = sdkFact.source == .imported ? .imported : .local
        return AppMemoryFact(
            id: sdkFact.id,
            domain: sdkFact.domain,
            kind: MemoryKind(rawValue: sdkFact.kind.rawValue) ?? .observation,
            status: MemoryFactStatus(rawValue: sdkFact.status.rawValue) ?? .candidate,
            confidence: sdkFact.confidence,
            evidenceCount: sdkFact.evidenceCount,
            source: axionSource,
            scope: scope,
            cause: cause,
            description: sdkFact.content,
            updatedAt: sdkFact.lastVerifiedAt,
            evidence: evidence
        )
    }
}

// MARK: - AxionFactStore

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

    /// Save (upsert) multiple facts for a domain in a single write.
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AppMemoryFact].self, from: data)
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
