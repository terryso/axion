import Foundation
import OpenAgentSDK

/// Lightweight service that reads accumulated Memory for Apps mentioned in a
/// task description and formats it as a Planner-consumable prompt fragment.
///
/// MemoryContextProvider does NOT write to the MemoryStore — it is purely a
/// read-and-format service used by ``RunCommand`` to inject App Memory context
/// into the system prompt before the LLM Planner runs.
struct MemoryContextProvider {

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
            let latestProfile = profileEntries.max(by: { $0.createdAt < $1.createdAt })
            let profileContent = latestProfile!.content
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
