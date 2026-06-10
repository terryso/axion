import Foundation
import OpenAgentSDK

// MARK: - V2 Approval Handler (AC1–AC4/AC6)

extension PermissionHandler {

    /// Handles v2 approval flow with dynamic options and session/prefix allow.
    static func handleV2Approval(
        tool: ToolProtocol,
        input: Any,
        allowList: SessionAllowListRef,
        readUserInput: @Sendable () -> String?
    ) -> CanUseToolResult {
        let description = extractDescription(tool: tool, input: input)
        let inputDict = input as? [String: Any] ?? [:]

        // AC2: Dynamic options based on tool type
        let options = ApprovalOption.allOptions(toolName: tool.name, input: inputDict)

        // AC5: Render approval prompt with ChatTheme
        let theme = ChatTheme(profile: TerminalColorProfile.detect(), isTTY: true)

        // AC7: Show diff summary for Write/Edit
        if let diffSummary = ApprovalRenderer.renderDiffSummary(
            toolName: tool.name, input: inputDict
        ) {
            fputs(diffSummary + "\n", stderr)
        }

        fputs(
            ApprovalRenderer.renderPrompt(
                toolName: tool.name,
                description: description,
                options: options,
                theme: theme
            ),
            stderr
        )
        fflush(stderr)

        // AC6: Read user input → map to decision
        guard let response = readUserInput() else {
            return .deny("无法读取用户输入")
        }

        let decision = mapInputToDecision(response, options: options)

        // UX: 显示用户选择的确认（readSingleKey 不回显按键，需要视觉反馈）
        switch decision {
        case .decline:
            fputs("  → 拒绝 ✗\n", stderr)
        default:
            fputs("  → \(decision.label) ✓\n", stderr)
        }

        switch decision {
        case .once:
            return .allow()

        case .session:
            // AC3: Register exact match for session allow
            if let key = extractCommandKey(tool: tool, input: input) {
                allowList.addExact(key)
            }
            return .allow()

        case .prefix:
            // AC4: Register prefix rule
            if let key = extractCommandKey(tool: tool, input: input) {
                allowList.addPrefix(for: key)
            }
            return .allow()

        case .decline:
            return .deny("用户拒绝执行 \(tool.name)")
        }
    }

    // MARK: - V1 Prompt (backward compatible)

    /// Handles original [y/n] prompt for backward compatibility.
    static func handleV1Prompt(
        tool: ToolProtocol,
        input: Any,
        readUserInput: @Sendable () -> String?
    ) -> CanUseToolResult {
        let description = extractDescription(tool: tool, input: input)
        fputs("⚠️  \(tool.name): \(description)\n   允许？[y/n] ", stderr)
        fflush(stderr)

        guard let response = readUserInput()?.lowercased() else {
            return .deny("无法读取用户输入")
        }

        if response == "y" || response == "yes" {
            return .allow()
        } else {
            return .deny("用户拒绝执行 \(tool.name)")
        }
    }

    // MARK: - Command Key Extraction (AC3)

    /// Extracts a command key from tool input for session allow list matching.
    ///
    /// - Bash → command string directly
    /// - Write → "Write:{file_path}"
    /// - Edit → "Edit:{file_path}"
    /// - Others → nil (no session tracking)
    static func extractCommandKey(tool: ToolProtocol, input: Any) -> String? {
        guard let dict = input as? [String: Any] else { return nil }
        switch tool.name {
        case "Bash":
            return dict["command"] as? String
        case "Write":
            return (dict["file_path"] as? String).map { "Write:\($0)" }
        case "Edit":
            return (dict["file_path"] as? String).map { "Edit:\($0)" }
        default:
            return nil
        }
    }

    // MARK: - Input → Decision Mapping (AC6)

    /// Maps user input string to an `ApprovalDecision`.
    ///
    /// Checks the first character against option shortcuts.
    /// Empty input or unknown input → decline.
    static func mapInputToDecision(_ input: String, options: [ApprovalOption]) -> ApprovalDecision {
        let trimmed = input.lowercased().trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else {
            return .decline  // Empty input = decline
        }

        for option in options {
            if first == option.decision.shortcut {
                return option.decision
            }
        }

        return .decline  // Unknown input (including ESC key) = decline
    }

    // MARK: - Description Extraction

    /// Extracts a human-readable description from tool input for the permission prompt.
    ///
    /// - Bash → command parameter
    /// - Write → "写入 {file_path}"
    /// - Edit → "编辑 {file_path}"
    /// - Others → tool name
    static func extractDescription(tool: ToolProtocol, input: Any) -> String {
        guard let dict = input as? [String: Any] else {
            return tool.name
        }
        switch tool.name {
        case "Bash":
            return dict["command"] as? String ?? tool.name
        case "Write":
            return "写入 \(dict["file_path"] as? String ?? "文件")"
        case "Edit":
            return "编辑 \(dict["file_path"] as? String ?? "文件")"
        default:
            return tool.name
        }
    }
}
