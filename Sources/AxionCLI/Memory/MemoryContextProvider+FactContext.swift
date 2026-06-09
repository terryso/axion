
// MARK: - Fact-based Memory Context (Story 12.2 + Story 18.2)

extension MemoryContextProvider {

    /// Build a classified Memory context string from SDK `FactStore` data.
    ///
    /// Reads active facts for the inferred domain, groups by kind (affordance / avoid / observation),
    /// and formats them with kind-specific labels and the soft-hints declaration.
    /// Falls back to `nil` if no facts are found (safe degradation).
    func buildFactMemoryContext(
        task: String,
        factStore: AxionFactStore
    ) async -> String? {
        guard let domain = inferDomain(from: task) else { return nil }

        do {
            let allFacts = try await factStore.query(domain: domain)
            let lifecycleService = SDKMemoryLifecycleService()
            let sdkFacts = allFacts.map { $0.toSDKFact() }
            let sdkActiveFacts = lifecycleService.selectActiveFacts(domain: domain, from: sdkFacts)
            let activeIds = Set(sdkActiveFacts.map(\.id))
            let activeFacts = allFacts.filter { activeIds.contains($0.id) }
            guard !activeFacts.isEmpty else { return nil }
            return assembleFactContext(domain: domain, facts: activeFacts)
        } catch {
            return nil
        }
    }

    /// Maximum number of facts to display per kind category.
    static let maxFactsPerKind = 5

    private func assembleFactContext(domain: String, facts: [AppMemoryFact]) -> String {
        var sections: [String] = []
        sections.append("Relevant local app memories. These are soft hints, not hard rules. Cautions should change strategy probabilities, not disable capabilities:")
        sections.append("")
        sections.append("## \(domain) — Memory Context")

        let affordances = facts.filter { $0.kind == .affordance }
            .sorted { $0.confidence > $1.confidence }
        let avoids = facts.filter { $0.kind == .avoid }
            .sorted { $0.confidence > $1.confidence }
        let observations = facts.filter { $0.kind == .observation }
            .sorted { $0.confidence > $1.confidence }

        if !affordances.isEmpty {
            sections.append("")
            sections.append("### 推荐路径")
            for fact in affordances.prefix(Self.maxFactsPerKind) {
                sections.append(formatFactLine(fact: fact, label: "推荐"))
            }
        }

        if !avoids.isEmpty {
            sections.append("")
            sections.append("### 注意事项")
            for fact in avoids.prefix(Self.maxFactsPerKind) {
                sections.append(formatFactLine(fact: fact, label: "警告"))
            }
        }

        if !observations.isEmpty {
            sections.append("")
            sections.append("### 环境备注")
            for fact in observations.prefix(Self.maxFactsPerKind) {
                sections.append(formatFactLine(fact: fact, label: "备注"))
            }
        }

        return sections.joined(separator: "\n")
    }

    /// Format a single fact as a bullet line, handling multi-line descriptions.
    /// The first line goes on the bullet; continuation lines are indented.
    func formatFactLine(fact: AppMemoryFact, label: String) -> String {
        let descLines = fact.description.components(separatedBy: "\n")
        let header = "- [\(label)] (confidence: \(String(format: "%.2f", fact.confidence)), evidence: \(fact.evidenceCount)): \(descLines.first ?? "")"
        let continuation = descLines.dropFirst().map { "  \($0)" }
        return ([header] + continuation).joined(separator: "\n")
    }
}
