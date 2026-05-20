import Foundation
import OpenAgentSDK

/// Lightweight service that reads accumulated Memory for Apps mentioned in a
/// task description and formats it as a Planner-consumable prompt fragment.
///
/// MemoryContextProvider does NOT write to the MemoryStore — it is purely a
/// read-and-format service used by ``RunCommand`` to inject App Memory context
/// into the system prompt before the LLM Planner runs.
///
/// **Design Decisions:**
/// - **Keyword-based domain inference**: uses a static mapping table of common app names
///   (English + Chinese) to bundle identifiers. This is intentionally simple — keyword matching
///   covers 90% of desktop automation tasks without requiring LLM calls or complex NLP.
///   Future: could use embedding similarity or LLM-based inference for ambiguous cases.
/// - **Safe degradation pattern**: all MemoryStore access is wrapped in do/catch, returning `nil`
///   on any failure. This ensures memory system issues (corrupted files, permission errors, missing
///   directories) never prevent task execution. The planner simply runs without memory context.
/// - **Context structure for LLM consumption**: the assembled context uses markdown headers and
///   bullet lists optimized for LLM readability. Familiarity status triggers different strategy
///   suggestions — familiar apps get compact planning (skip verification steps), unfamiliar apps
///   get full verification recommendations.
/// - **Profile-content coupling**: the field extraction (`extractField`) depends on specific
///   prefixes ("AX特征:", "高频路径:", "已知失败:") that must match `RunCommand.buildProfileContent()`.
///   This textual coupling is intentional — it keeps the memory format human-readable and debuggable
///   without requiring a structured schema.
struct MemoryContextProvider {

    // Disambiguate SDK types that shadow Axion's.
    typealias SDKFactStore = OpenAgentSDK.FactStore
    typealias SDKMemoryLifecycleService = OpenAgentSDK.MemoryLifecycleService

    // MARK: - App Name Mapping

    /// Common App name to domain mapping used for inferring which App a task
    /// description refers to. Keywords are matched case-insensitively.
    static let appNameMap: [(keywords: [String], domain: String)] = [
        (["calculator", "计算器"], "com.apple.calculator"),
        (["finder"], "com.apple.finder"),
        (["textedit", "文本编辑", "文本编辑器"], "com.apple.textedit"),
        (["safari"], "com.apple.safari"),
        (["chrome", "google chrome"], "com.google.chrome"),
        (["notes", "备忘录", "笔记本"], "com.apple.notes"),
        (["terminal", "终端"], "com.apple.terminal"),
        (["preview", "预览"], "com.apple.preview"),
        (["mail", "邮件"], "com.apple.mail"),
        (["calendar", "日历"], "com.apple.calendar"),
        (["photos", "照片"], "com.apple.photos"),
        (["music", "音乐"], "com.apple.music"),
        (["maps", "地图"], "com.apple.maps"),
        (["pages"], "com.apple.pages"),
        (["numbers"], "com.apple.numbers"),
        (["keynote"], "com.apple.keynote"),
    ]

    // MARK: - Public API

    /// Build a Memory context string to inject into the Planner system prompt.
    ///
    /// - Parameters:
    ///   - task: The user's task description (used to infer which App is involved).
    ///   - store: The MemoryStore to query for historical data.
    /// - Returns: A formatted Memory context string, or `nil` if no relevant
    ///   Memory data is found (safe degradation).
    func buildMemoryContext(
        task: String,
        store: any MemoryStoreProtocol
    ) async throws -> String? {
        // 1. Infer domain from task description
        guard let domain = inferDomain(from: task) else {
            return nil
        }

        // 2. Query MemoryStore for this domain
        // Wrap all store access in do-catch for safe degradation
        do {
            let profileEntries = try await store.query(
                domain: domain,
                filter: KnowledgeQueryFilter(tags: ["profile"])
            )

            let familiarEntries = try await store.query(
                domain: domain,
                filter: KnowledgeQueryFilter(tags: ["familiar"])
            )

            let isFamiliar = !familiarEntries.isEmpty

            // 3. If no profile data, try to build from run entries, or return nil
            guard !profileEntries.isEmpty else {
                return nil
            }

            // 4. Parse profile content and assemble prompt — use the latest entry
            guard let latestProfile = profileEntries.max(by: { $0.createdAt < $1.createdAt }) else {
                return nil
            }
            let profileContent = latestProfile.content
            return assembleContext(
                domain: domain,
                profileContent: profileContent,
                isFamiliar: isFamiliar
            )
        } catch {
            // Safe degradation — Memory errors should not block task execution
            return nil
        }
    }

    // MARK: - Fact-based Memory Context (Story 12.2)

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

    // MARK: - Skill-scoped Memory Context (Story 18.2)

    /// Maximum number of skill-scoped facts to inject.
    static let maxSkillFacts = 3

    /// Build a skill-scoped Memory context for injection into a skill's promptTemplate.
    ///
    /// Queries active facts matching `skill:{skillName}` scope for the inferred domain,
    /// selects up to `maxSkillFacts` items prioritized by kind (affordance → avoid → observation),
    /// and formats them with a soft-hints declaration.
    func buildSkillMemoryContext(
        skillName: String,
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
            let scopePrefix = "skill:\(skillName)"
            let skillFacts = activeFacts.filter { $0.scope?.hasPrefix(scopePrefix) == true }
            guard !skillFacts.isEmpty else { return nil }
            return assembleSkillFactContext(skillName: skillName, facts: skillFacts)
        } catch {
            return nil
        }
    }

    private func assembleSkillFactContext(skillName: String, facts: [AppMemoryFact]) -> String {
        var sections: [String] = []
        sections.append("Skill-specific memory for '\(skillName)'. These are soft hints from past executions:")
        sections.append("")

        let affordances = facts.filter { $0.kind == .affordance }.sorted { $0.confidence > $1.confidence }
        let avoids = facts.filter { $0.kind == .avoid }.sorted { $0.confidence > $1.confidence }
        let observations = facts.filter { $0.kind == .observation }.sorted { $0.confidence > $1.confidence }

        var selected: [AppMemoryFact] = []
        selected.append(contentsOf: affordances.prefix(1))
        if selected.count < Self.maxSkillFacts { selected.append(contentsOf: avoids.prefix(1)) }
        if selected.count < Self.maxSkillFacts { selected.append(contentsOf: observations.prefix(min(Self.maxSkillFacts - selected.count, 2))) }

        for fact in selected {
            sections.append(formatFactLine(fact: fact, label: fact.kind.rawValue))
        }
        return sections.joined(separator: "\n")
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
    private func formatFactLine(fact: AppMemoryFact, label: String) -> String {
        let descLines = fact.description.components(separatedBy: "\n")
        let header = "- [\(label)] (confidence: \(String(format: "%.2f", fact.confidence)), evidence: \(fact.evidenceCount)): \(descLines.first ?? "")"
        let continuation = descLines.dropFirst().map { "  \($0)" }
        return ([header] + continuation).joined(separator: "\n")
    }

    // MARK: - Domain Inference

    /// Infer an App domain from the task description by matching keywords.
    /// Returns the first matching domain from the keyword mapping table,
    /// regardless of whether data exists in the MemoryStore for that domain.
    func inferDomain(from task: String) -> String? {
        let lowered = task.lowercased()

        for mapping in Self.appNameMap {
            for keyword in mapping.keywords {
                if lowered.contains(keyword.lowercased()) {
                    return mapping.domain
                }
            }
        }
        return nil
    }

    // MARK: - Context Assembly

    /// Assemble a formatted Memory context string from profile data.
    private func assembleContext(
        domain: String,
        profileContent: String,
        isFamiliar: Bool
    ) -> String {
        var sections: [String] = []

        // Header
        let familiarityLabel = isFamiliar ? "已熟悉" : "初次接触"
        sections.append("# App Memory Context")
        sections.append("")
        sections.append("## \(domain) — 熟悉度: \(familiarityLabel)")

        // Parse profile fields
        // Note: These prefixes must match the labels in RunCommand.buildProfileContent().
        let axCharacteristics = extractField(from: profileContent, prefix: "AX特征:")
        let commonPatterns = extractField(from: profileContent, prefix: "高频路径:")
        let knownFailures = extractField(from: profileContent, prefix: "已知失败:")

        // Reliable operation paths
        if let patterns = commonPatterns, !patterns.isEmpty {
            sections.append("")
            sections.append("### 可靠操作路径")
            let individualPatterns = patterns.components(separatedBy: "; ")
            for pattern in individualPatterns {
                sections.append("- \(pattern)")
            }
        }

        // AX characteristics
        if let axChars = axCharacteristics, !axChars.isEmpty {
            sections.append("")
            sections.append("### AX 特征")
            let parts = axChars.components(separatedBy: ", ")
                .flatMap { $0.components(separatedBy: "，") }
            for part in parts {
                sections.append("- \(part)")
            }
        }

        // Known failures
        if let failures = knownFailures, !failures.isEmpty {
            sections.append("")
            sections.append("### 已知失败（避免重复）")
            let individualFailures = failures.components(separatedBy: "; ")
            for failure in individualFailures {
                sections.append("- \(failure)")
            }
        }

        // Strategy suggestion
        sections.append("")
        sections.append("### 策略建议")
        if isFamiliar {
            sections.append("- 此 App 已熟悉，可使用紧凑规划")
            sections.append("- 省略中间验证步骤（list_windows / get_window_state），直接使用已知可靠的操作路径")
            sections.append("- 如使用 AX selector 且已知按钮标题，可直接 click 而无需先 get_accessibility_tree")
        } else {
            sections.append("- 此 App 尚未熟悉，建议完整验证流程")
        }

        return sections.joined(separator: "\n")
    }

    // MARK: - Field Extraction

    /// Extract a specific field value from profile content text by prefix.
    private func extractField(from content: String, prefix: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                let value = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
