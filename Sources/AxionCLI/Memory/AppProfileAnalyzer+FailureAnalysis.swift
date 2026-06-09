import OpenAgentSDK

// MARK: - Failure Patterns Extraction

extension AppProfileAnalyzer {

    /// Extract failure patterns from entries with failure tags.
    func extractKnownFailures(from failureEntries: [KnowledgeEntry]) -> [FailurePattern] {
        var failures: [FailurePattern] = []

        for entry in failureEntries {
            let content = entry.content
            let failedAction = extractField(from: content, prefix: "失败标记:") ?? "Unknown failure"
            let reason: String

            // Try to extract more specific reason from the failure marker
            if failedAction.contains("不可靠") {
                reason = "坐标或元素定位不可靠"
            } else if failedAction.contains("未安装") {
                reason = "应用未安装"
            } else if failedAction.contains("未找到") {
                reason = "目标元素未找到"
            } else {
                reason = "操作失败"
            }

            let workaround = extractField(from: content, prefix: "修正路径:")

            failures.append(FailurePattern(
                failedAction: failedAction,
                reason: reason,
                workaround: workaround
            ))
        }

        return failures
    }

    /// Extract a specific field value from content text by prefix.
    func extractField(from content: String, prefix: String) -> String? {
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
