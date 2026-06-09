import Foundation
import OpenAgentSDK

// Disambiguate: Axion's enums shadow SDK's, so alias SDK types for conversion helpers.
typealias SDKMemoryFact = OpenAgentSDK.MemoryFact
typealias SDKMemoryFactSource = OpenAgentSDK.MemoryFactSource
typealias SDKMemoryKind = OpenAgentSDK.MemoryKind
typealias SDKMemoryFactStatus = OpenAgentSDK.MemoryFactStatus
typealias SDKMemoryLifecycleService = OpenAgentSDK.MemoryLifecycleService

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

    // MARK: - SDK Lifecycle Merge

    /// Merge a new fact with any existing matching fact via the SDK lifecycle service,
    /// preserving Axion-specific fields (scope, cause, evidence) that are lost in the
    /// SDK round-trip, then persist the merged result.
    ///
    /// This consolidates the duplicated query→merge→save pattern shared by
    /// `RunMemoryProcessor+PostRunProcessing`, `RecordedSkillRunner`, and
    /// `TakeoverLearningService`.
    ///
    /// - Parameters:
    ///   - fact: The new fact to merge.
    ///   - factStore: The store to query for existing facts and save the merged result.
    ///   - lifecycleService: The SDK lifecycle service for fact merging logic.
    static func mergeAndPersist(
        fact: AppMemoryFact,
        into factStore: AxionFactStore,
        lifecycleService: OpenAgentSDK.MemoryLifecycleService
    ) async throws {
        let existing = try await factStore.query(domain: fact.domain)
        let sdkExisting = existing.map { $0.toSDKFact() }
        let sdkResult = lifecycleService.addFact(fact.toSDKFact(), mergingWith: sdkExisting)

        let existingMatch = existing.first(where: { $0.id == fact.id })
        let mergedFact: AppMemoryFact
        if let existingFact = existingMatch {
            var updated = existingFact
            updated.status = MemoryFactStatus(rawValue: sdkResult.status.rawValue) ?? existingFact.status
            updated.confidence = sdkResult.confidence
            updated.evidenceCount = sdkResult.evidenceCount
            updated.updatedAt = sdkResult.lastVerifiedAt
            let newEvidenceItems = fact.evidence.filter { !existingFact.evidence.contains($0) }
            updated.evidence = existingFact.evidence + newEvidenceItems
            mergedFact = updated
        } else {
            mergedFact = AppMemoryFact.fromSDKFact(
                sdkResult,
                scope: fact.scope,
                cause: fact.cause,
                evidence: fact.evidence
            )
        }
        try await factStore.save(domain: fact.domain, fact: AppMemoryFact.normalizeFact(mergedFact))
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

