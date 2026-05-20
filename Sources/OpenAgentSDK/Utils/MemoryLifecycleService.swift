import Foundation

/// Pure-computation service for managing the lifecycle of memory facts.
///
/// This struct contains no mutable state and performs no I/O.
/// All methods are pure functions that transform facts.
public struct MemoryLifecycleService {

    /// Create a new service instance.
    public init() {}

    /// Add a fact, either as new or merged with an existing one by id.
    ///
    /// If an existing fact with the same id is found in `existing`, the facts are merged.
    /// If the existing fact is retired, it is reactivated as candidate instead.
    public func addFact(_ fact: MemoryFact, mergingWith existing: [MemoryFact]) -> MemoryFact {
        guard let match = existing.first(where: { $0.id == fact.id }) else {
            return fact
        }

        if match.status == .retired {
            return reactivateRetired(fact: fact)
        }

        return mergeFact(existing: match, incoming: fact)
    }

    /// Merge an incoming fact with an existing one of the same id.
    ///
    /// Takes the max confidence, sums evidence counts, keeps latest timestamps,
    /// then checks for promotion eligibility.
    public func mergeFact(existing: MemoryFact, incoming: MemoryFact) -> MemoryFact {
        let merged = MemoryFact(
            id: existing.id,
            domain: existing.domain,
            content: incoming.content.isEmpty ? existing.content : incoming.content,
            status: existing.status,
            confidence: max(existing.confidence, incoming.confidence),
            evidenceCount: existing.evidenceCount + incoming.evidenceCount,
            source: existing.source,
            kind: existing.kind,
            createdAt: existing.createdAt,
            lastVerifiedAt: max(existing.lastVerifiedAt, incoming.lastVerifiedAt)
        )

        if let promoted = maybePromote(fact: merged) {
            return promoted
        }
        return merged
    }

    /// Attempt to promote a candidate fact to active.
    ///
    /// A candidate is promoted when `evidenceCount >= 2` AND `confidence >= 0.65`.
    /// On promotion, confidence gets a +0.1 boost (capped at 1.0).
    public func maybePromote(fact: MemoryFact) -> MemoryFact? {
        guard fact.status == .candidate else { return nil }
        guard fact.evidenceCount >= 2 && fact.confidence >= 0.65 else { return nil }

        return MemoryFact(
            id: fact.id,
            domain: fact.domain,
            content: fact.content,
            status: .active,
            confidence: min(1.0, fact.confidence + 0.1),
            evidenceCount: fact.evidenceCount,
            source: fact.source,
            kind: fact.kind,
            createdAt: fact.createdAt,
            lastVerifiedAt: fact.lastVerifiedAt
        )
    }

    /// Demote active facts to retired if they haven't been verified recently.
    ///
    /// - Parameters:
    ///   - facts: The facts to check.
    ///   - lastVerifiedBefore: A date; active facts verified before this are demoted.
    /// - Returns: Array of demoted facts.
    public func demoteRetired(facts: [MemoryFact], lastVerifiedBefore: Date) -> [MemoryFact] {
        facts.compactMap { fact in
            guard fact.status == .active else { return nil }
            guard fact.lastVerifiedAt < lastVerifiedBefore else { return nil }

            return MemoryFact(
                id: fact.id,
                domain: fact.domain,
                content: fact.content,
                status: .retired,
                confidence: fact.confidence,
                evidenceCount: fact.evidenceCount,
                source: fact.source,
                kind: fact.kind,
                createdAt: fact.createdAt,
                lastVerifiedAt: fact.lastVerifiedAt
            )
        }
    }

    /// Reactivate a retired fact as a new candidate with evidenceCount=1.
    public func reactivateRetired(fact: MemoryFact, reactivatedAt: Date = Date()) -> MemoryFact {
        MemoryFact(
            id: fact.id,
            domain: fact.domain,
            content: fact.content,
            status: .candidate,
            confidence: fact.confidence,
            evidenceCount: 1,
            source: fact.source,
            kind: fact.kind,
            createdAt: fact.createdAt,
            lastVerifiedAt: reactivatedAt
        )
    }

    /// Select active facts sorted by confidence descending.
    public func selectActiveFacts(domain: String, from facts: [MemoryFact]) -> [MemoryFact] {
        facts
            .filter { $0.domain == domain && $0.status == .active }
            .sorted { $0.confidence > $1.confidence }
    }
}
