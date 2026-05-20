import Foundation

/// Formats active memory facts into a prompt-friendly context string.
///
/// Groups facts by kind (affordance, avoid, observation), caps each group at
/// ``maxFactsPerKind`` entries, and sorts by confidence descending.
public struct MemoryContextProvider {

    /// Maximum number of facts to include per kind category.
    public static let maxFactsPerKind = 5

    public init() {}

    /// Build a context string from active facts for the given domain.
    ///
    /// Returns `nil` if `facts` is empty.
    public func buildContext(domain: String, facts: [MemoryFact]) -> String? {
        let activeFacts = facts.filter { $0.status == .active }
        guard !activeFacts.isEmpty else { return nil }

        let grouped = Dictionary(grouping: activeFacts, by: { $0.kind })
        let cap = Self.maxFactsPerKind

        var sections: [String] = []
        sections.append("These are soft hints, not hard rules. Use judgment when applying them.")

        if let affordances = grouped[.affordance] {
            let sorted = affordances.sorted { $0.confidence > $1.confidence }
            let capped = Array(sorted.prefix(cap))
            let items = capped.map { "- \($0.content) (confidence: \($0.confidence), evidence: \($0.evidenceCount))" }
            sections.append("### Recommended Paths\n" + items.joined(separator: "\n"))
        }

        if let avoids = grouped[.avoid] {
            let sorted = avoids.sorted { $0.confidence > $1.confidence }
            let capped = Array(sorted.prefix(cap))
            let items = capped.map { "- \($0.content) (confidence: \($0.confidence), evidence: \($0.evidenceCount))" }
            sections.append("### Cautions\n" + items.joined(separator: "\n"))
        }

        if let observations = grouped[.observation] {
            let sorted = observations.sorted { $0.confidence > $1.confidence }
            let capped = Array(sorted.prefix(cap))
            let items = capped.map { "- \($0.content) (confidence: \($0.confidence), evidence: \($0.evidenceCount))" }
            sections.append("### Environment Notes\n" + items.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}
