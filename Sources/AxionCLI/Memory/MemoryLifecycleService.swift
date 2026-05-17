import Foundation

/// Pure-computation service managing the lifecycle of ``AppMemoryFact`` entries.
///
/// Responsible for candidate→active promotion, active→retired demotion,
/// and retired→candidate reactivation. Does not perform I/O — the caller
/// is responsible for persisting changes via ``MemoryFactStore``.
struct MemoryLifecycleService {

    /// Promotion threshold: minimum evidence count.
    static let promoteEvidenceThreshold = 2
    /// Promotion threshold: minimum confidence.
    static let promoteConfidenceThreshold = 0.65
    /// Confidence boost on promotion.
    static let promoteConfidenceBoost = 0.1
    /// Maximum confidence value.
    static let maxConfidence = 1.0

    /// Demotion interval: 30 days in seconds.
    static let demotionInterval: TimeInterval = 30 * 24 * 60 * 60  // 2_592_000

    // MARK: - Add / Merge

    /// Add a new fact or merge with an existing one by ID.
    ///
    /// - Parameters:
    ///   - newFact: The incoming fact to add or merge.
    ///   - existing: Existing facts for the same domain (used for ID lookup).
    /// - Returns: The resulting fact (either the new one, or the merged one).
    func addFact(
        _ newFact: AppMemoryFact,
        mergingWith existing: [AppMemoryFact]
    ) -> AppMemoryFact {
        guard let match = existing.first(where: { $0.id == newFact.id }) else {
            return newFact
        }

        // Retired facts get reactivated instead of merged
        if match.status == .retired {
            return reactivateRetired(fact: match)
        }

        return mergeFact(existing: match, incoming: newFact)
    }

    /// Merge an incoming fact into an existing one.
    ///
    /// Strategy: max confidence, sum evidence counts, keep latest updatedAt.
    func mergeFact(existing: AppMemoryFact, incoming: AppMemoryFact) -> AppMemoryFact {
        var merged = existing
        merged.confidence = max(existing.confidence, incoming.confidence)
        merged.evidenceCount = existing.evidenceCount + 1
        merged.updatedAt = max(existing.updatedAt, incoming.updatedAt)
        merged.evidence.append(contentsOf: incoming.evidence)

        // Check for promotion after merge — reuse maybePromote to keep logic in one place
        if let promoted = maybePromote(fact: merged) {
            return promoted
        }

        return AppMemoryFact.normalizeFact(merged)
    }

    // MARK: - Promotion

    /// Check if a fact qualifies for promotion from candidate to active.
    ///
    /// - Returns: The promoted fact, or nil if conditions aren't met.
    func maybePromote(fact: AppMemoryFact) -> AppMemoryFact? {
        guard fact.status == .candidate else { return nil }
        guard fact.evidenceCount >= Self.promoteEvidenceThreshold else { return nil }
        guard fact.confidence >= Self.promoteConfidenceThreshold else { return nil }

        var promoted = fact
        promoted.status = .active
        promoted.confidence = min(
            fact.confidence + Self.promoteConfidenceBoost,
            Self.maxConfidence
        )
        promoted.updatedAt = Date()
        return AppMemoryFact.normalizeFact(promoted)
    }

    // MARK: - Demotion

    /// Demote active facts that haven't been verified within the demotion interval.
    func demoteRetired(
        facts: [AppMemoryFact],
        lastVerifiedBefore cutoff: Date
    ) -> [AppMemoryFact] {
        facts.map { fact in
            guard fact.status == .active, fact.updatedAt < cutoff else { return fact }
            var demoted = fact
            demoted.status = .retired
            demoted.updatedAt = Date()
            return demoted
        }
    }

    // MARK: - Reactivation

    /// Reactivate a retired fact by resetting it to candidate with evidenceCount = 1.
    func reactivateRetired(fact: AppMemoryFact) -> AppMemoryFact {
        guard fact.status == .retired else { return fact }
        var reactivated = fact
        reactivated.status = .candidate
        reactivated.evidenceCount = 1
        reactivated.updatedAt = Date()
        return reactivated
    }

    // MARK: - Selection

    /// Select only active facts for a domain, sorted by confidence descending.
    func selectActiveFacts(domain: String, from facts: [AppMemoryFact]) -> [AppMemoryFact] {
        facts
            .filter { $0.domain == domain && $0.status == .active }
            .sorted { $0.confidence > $1.confidence }
    }
}
