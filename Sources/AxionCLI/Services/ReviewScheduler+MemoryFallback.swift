import OpenAgentSDK


extension ReviewScheduler {

    /// Fallback universal-memory extraction when the review agent produces no memory changes.
    /// Scans messages for explicit user preferences and persists them via UniversalMemoryStore.
    static func applyUniversalMemoryFallbackIfNeeded(
        reviewResult: ReviewAgentResult?,
        messages: [SDKMessage],
        config: ReviewAgentConfig,
        memoryDir: String
    ) async -> ReviewAgentResult? {
        guard config.reviewMemory else { return reviewResult }
        if let reviewResult, !reviewResult.memoryChanges.isEmpty { return reviewResult }

        var fallbackMemoryChanges: [String] = []

        if let preference = extractExplicitUserPreference(from: messages) {
            let store = UniversalMemoryStore(memoryDir: memoryDir)
            let existing = await store.read(target: .user)
            if !existing.contains(preference) {
                let scanner = MemorySecurityScanner()
                if case .safe = scanner.scan(content: preference) {
                    let saved = await store.add(target: .user, content: preference)
                    if saved {
                        fallbackMemoryChanges.append("Saved entry to USER.md")
                    }
                }
            }
        }

        guard !fallbackMemoryChanges.isEmpty else { return reviewResult }

        let skillChanges = reviewResult?.skillChanges ?? []
        let reviewMessages = reviewResult?.reviewMessages ?? []
        return ReviewAgentResult(
            memoryChanges: fallbackMemoryChanges,
            skillChanges: skillChanges,
            summary: "Review completed: " + fallbackMemoryChanges.joined(separator: "; "),
            reviewMessages: reviewMessages
        )
    }

    // Fallback: catches explicit Chinese-language preference patterns that the review agent
    // may miss. The primary path is now the review agent using review_save_universal_memory
    // (guided by promptSuffix in ReviewAgentConfig).
    static func extractExplicitUserPreference(from messages: [SDKMessage]) -> String? {
        let styleKeywords = ["回答", "回复", "emoji", "表情", "简洁", "详细", "中文", "英文", "格式", "语气", "解释", "markdown"]
        let futureMarkers = ["以后", "今后", "之后", "后续", "下次"]
        let directPrefixes = ["别", "不要", "请", "用中文", "用英文", "回答", "回复"]

        for message in messages.reversed() {
            guard case .userMessage(let data) = message else { continue }
            let trimmed = data.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let clause = splitPreferenceClause(from: trimmed)
            let hasStyleKeyword = styleKeywords.contains(where: { clause.localizedCaseInsensitiveContains($0) })
            let hasFutureMarker = futureMarkers.contains(where: { clause.contains($0) })
            let hasDirectPrefix = directPrefixes.contains(where: { clause.hasPrefix($0) })

            if hasStyleKeyword && (hasFutureMarker || hasDirectPrefix) {
                return clause
            }
        }

        return nil
    }

    static func splitPreferenceClause(from message: String) -> String {
        let separators = ["，并", "，然后", "，再", ", and", " and then ", " then "]
        for separator in separators {
            if let range = message.range(of: separator, options: [.caseInsensitive]) {
                return String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let range = message.range(of: "，") {
            return String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
