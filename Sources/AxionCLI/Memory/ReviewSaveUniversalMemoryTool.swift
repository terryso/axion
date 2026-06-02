import Foundation
import OpenAgentSDK

/// Tool for the review agent to save discovered knowledge into universal memory files.
///
/// Unlike `MemoryTool` (used by the main agent during task execution), this tool
/// is intentionally simpler: the review agent only needs `add` and `replace` —
/// no `remove` or `read`. The review prompt already tells the agent what to look
/// for; it doesn't need to browse existing memory.
final class ReviewSaveUniversalMemoryTool: ToolProtocol, Sendable {

    let name = "review_save_universal_memory"
    let description = "审查代理专用：将对话中发现的用户偏好或环境知识保存到通用记忆。action: 'add'(追加) 或 'replace'(替换)。target: 'memory'(MEMORY.md 环境知识) 或 'user'(USER.md 用户画像)。写入前自动安全扫描。"
    nonisolated(unsafe) let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": [
            "action": [
                "type": "string",
                "enum": ["add", "replace"],
                "description": "Operation to perform",
            ],
            "target": [
                "type": "string",
                "enum": ["memory", "user"],
                "description": "Target file: 'memory' (MEMORY.md) or 'user' (USER.md)",
            ],
            "content": [
                "type": "string",
                "description": "Content to save",
            ],
            "old": [
                "type": "string",
                "description": "Keyword to match for 'replace'",
            ],
        ],
        "required": ["action", "target", "content"],
    ]
    let isReadOnly = false

    private let store: UniversalMemoryStore
    private let scanner = MemorySecurityScanner()

    init(store: UniversalMemoryStore) {
        self.store = store
    }

    func call(input: Any, context: ToolContext) async -> ToolResult {
        guard let params = input as? [String: Any] else {
            return ToolResultHelper.errorResult(toolUseId: context.toolUseId, error: "invalid_input", message: "Input must be a JSON object", suggestion: "Pass a valid JSON object with 'action', 'target', and 'content'")
        }

        guard let action = params["action"] as? String, !action.isEmpty else {
            return ToolResultHelper.errorResult(toolUseId: context.toolUseId, error: "missing_action", message: "Missing required 'action' parameter", suggestion: "Provide 'action' as one of: add, replace")
        }

        guard let targetRaw = params["target"] as? String, !targetRaw.isEmpty else {
            return ToolResultHelper.errorResult(toolUseId: context.toolUseId, error: "missing_target", message: "Missing required 'target' parameter", suggestion: "Provide 'target' as 'memory' or 'user'")
        }

        guard let target = MemoryTarget(rawValue: targetRaw.uppercased() + ".md") else {
            return ToolResultHelper.errorResult(toolUseId: context.toolUseId, error: "invalid_target", message: "Invalid target '\(targetRaw)'", suggestion: "Use 'memory' or 'user'")
        }

        guard let content = params["content"] as? String, !content.isEmpty else {
            return ToolResultHelper.errorResult(toolUseId: context.toolUseId, error: "missing_content", message: "Missing required 'content' parameter", suggestion: "Provide the content to save")
        }

        switch action {
        case "add":
            return await handleAdd(content: content, target: target, toolUseId: context.toolUseId)
        case "replace":
            return await handleReplace(params: params, content: content, target: target, toolUseId: context.toolUseId)
        default:
            return ToolResultHelper.errorResult(toolUseId: context.toolUseId, error: "invalid_action", message: "Unknown action '\(action)'", suggestion: "Use one of: add, replace")
        }
    }

    // MARK: - Action Handlers

    private func handleAdd(content: String, target: MemoryTarget, toolUseId: String) async -> ToolResult {
        let scanResult = scanner.scan(content: content)
        if case .rejected(let reason) = scanResult {
            return ToolResultHelper.errorResult(toolUseId: toolUseId, error: "security_rejection", message: "Content blocked by security scanner: \(reason)", suggestion: "Modify the content to remove the problematic pattern")
        }

        let ok = await store.add(target: target, content: content)
        if !ok {
            return ToolResultHelper.errorResult(toolUseId: toolUseId, error: "char_limit_exceeded", message: "Cannot add entry: target file would exceed character limit. Replace or remove old entries first.", suggestion: "Use 'replace' to update an existing entry instead")
        }

        return ToolResultHelper.savedResult(toolUseId: toolUseId, message: "Saved entry to \(target.rawValue)")
    }

    private func handleReplace(params: [String: Any], content: String, target: MemoryTarget, toolUseId: String) async -> ToolResult {
        guard let old = params["old"] as? String, !old.isEmpty else {
            return ToolResultHelper.errorResult(toolUseId: toolUseId, error: "missing_old", message: "Missing required 'old' parameter for 'replace' action", suggestion: "Provide the keyword to match the existing entry")
        }

        let scanResult = scanner.scan(content: content)
        if case .rejected(let reason) = scanResult {
            return ToolResultHelper.errorResult(toolUseId: toolUseId, error: "security_rejection", message: "Content blocked by security scanner: \(reason)", suggestion: "Modify the content to remove the problematic pattern")
        }

        let ok = await store.replace(target: target, keyword: old, newContent: content)
        if !ok {
            return ToolResultHelper.errorResult(toolUseId: toolUseId, error: "replace_failed", message: "Could not replace entry: keyword not found or result would exceed character limit", suggestion: "Check that the keyword matches an existing entry and the replacement doesn't exceed the limit")
        }

        return ToolResultHelper.savedResult(toolUseId: toolUseId, message: "Saved updated entry to \(target.rawValue)")
    }

}
