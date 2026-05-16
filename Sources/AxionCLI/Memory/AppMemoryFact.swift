import Foundation

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
}
