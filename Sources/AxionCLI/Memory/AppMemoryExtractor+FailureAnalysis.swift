
extension AppMemoryExtractor {

    // MARK: - Failure & Workaround Analysis

    /// Extract failure marker from error tool results.
    func extractFailureMarker(from pairs: [ToolPair]) -> String? {
        for pair in pairs {
            let isFailure = pair.toolResult.isError || contentContainsErrorPayload(pair.toolResult.content)
            if isFailure {
                let toolName = stripMcpPrefix(pair.toolUse.toolName)
                let paramSummary = extractToolParamSummary(name: toolName, input: pair.toolUse.input)
                let toolDesc = paramSummary != nil ? "\(toolName)(\(paramSummary!))" : toolName

                let errorMsg = extractErrorMessage(from: pair.toolResult.content)

                if let errorMsg {
                    return "\(toolDesc) 失败: \(errorMsg)"
                } else {
                    return "\(toolDesc) 操作不可靠"
                }
            }
        }
        return nil
    }

    /// Extract workaround when a failed tool is followed by a successful tool.
    /// Prefers a successful tool of the same type as the failed tool, falling back
    /// to the first successful tool of any type.
    func extractWorkaround(from pairs: [ToolPair]) -> String? {
        // Find first error pair
        var errorIndex: Int?
        for (i, pair) in pairs.enumerated() {
            if pair.toolResult.isError || contentContainsErrorPayload(pair.toolResult.content) {
                errorIndex = i
                break
            }
        }

        guard let errorIdx = errorIndex else { return nil }

        let failedTool = stripMcpPrefix(pairs[errorIdx].toolUse.toolName)
        var firstSuccessFallback: String?

        // Look for a successful pair after the failure, preferring same tool type
        for i in (errorIdx + 1)..<pairs.count {
            let nextPair = pairs[i]
            let nextIsSuccess = !nextPair.toolResult.isError && !contentContainsErrorPayload(nextPair.toolResult.content)
            if nextIsSuccess {
                let nextTool = stripMcpPrefix(nextPair.toolUse.toolName)
                let nextParam = extractToolParamSummary(name: nextTool, input: nextPair.toolUse.input)
                let desc = nextParam != nil ? "\(nextTool)(\(nextParam!))" : nextTool

                if nextTool == failedTool {
                    // Same tool type — best match
                    return nextParam != nil
                        ? "使用 \(nextTool)(\(nextParam!)) 代替失败的操作"
                        : "使用 \(nextTool) 重新尝试"
                }

                // Remember first successful tool as fallback
                if firstSuccessFallback == nil {
                    firstSuccessFallback = nextParam != nil
                        ? "使用 \(desc) 代替失败的操作"
                        : "使用 \(nextTool) 重新尝试"
                }
            }
        }

        return firstSuccessFallback
    }

    // MARK: - Error Content Parsing

    /// Extract error message from tool result content.
    func extractErrorMessage(from content: String) -> String? {
        guard let json = parseJSONDict(from: content) else { return nil }

        if let message = json["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }
        return nil
    }

    /// Check if tool result content contains a structured error payload.
    ///
    /// Some tools (e.g., launch_app) catch errors and return structured JSON
    /// with "error" and "message" fields instead of throwing. This makes the
    /// MCP framework set `isError: false` even though the result is an error.
    func contentContainsErrorPayload(_ content: String) -> Bool {
        guard let json = parseJSONDict(from: content) else { return false }
        // ToolErrorPayload has both "error" and "message" keys
        return json["error"] != nil && json["message"] != nil
    }
}
