import Foundation
import OpenAgentSDK

/// Handles tool permission checks for the interactive chat REPL.
///
/// Provides a ``CanUseToolFn`` closure that:
/// - Auto-allows read-only tools (Read, Grep, Glob, etc.)
/// - Auto-allows Write/Edit in acceptEdits mode
/// - Auto-allows all tools in bypassPermissions mode
/// - Checks session allow list for previously approved commands (v2)
/// - Prompts the user with dynamic approval options (v2)
/// - Denies all non-read-only tools in non-TTY environments (safe default)
enum PermissionHandler {

    // MARK: - Public API

    /// Creates a ``CanUseToolFn`` closure for SDK tool permission checks (v1 — backward compatible).
    ///
    /// - Parameters:
    ///   - mode: The effective permission mode for this session.
    ///   - isTTY: Whether stdin is connected to a TTY (defaults to real `isatty` check).
    ///   - readUserInput: Closure to read a line of user input (injectable for testing).
    /// - Returns: A ``CanUseToolFn`` closure suitable for ``AgentOptions/canUseTool``.
    static func createCanUseTool(
        mode: PermissionMode,
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        readUserInput: @Sendable @escaping () -> String? = { readLine(strippingNewline: true) }
    ) -> CanUseToolFn {
        // AC1–AC4/AC6/AC8: v2 overload without session allow list
        return createCanUseTool(
            mode: mode,
            isTTY: isTTY,
            sessionAllowList: nil,
            readUserInput: readUserInput
        )
    }

    /// Creates a ``CanUseToolFn`` closure with session allow list support (v2).
    ///
    /// When `sessionAllowList` is provided, the closure checks it before prompting.
    /// User decisions (session/prefix) update the shared allow list.
    ///
    /// - Parameters:
    ///   - mode: The effective permission mode for this session.
    ///   - isTTY: Whether stdin is connected to a TTY.
    ///   - sessionAllowList: Shared session allow list reference (nil = v1 behavior).
    ///   - readUserInput: Closure to read a line of user input (injectable for testing).
    /// - Returns: A ``CanUseToolFn`` closure suitable for ``AgentOptions/canUseTool``.
    static func createCanUseTool(
        mode: PermissionMode,
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        sessionAllowList: SessionAllowListRef?,
        readUserInput: @Sendable @escaping () -> String? = { readLine(strippingNewline: true) }
    ) -> CanUseToolFn {
        return { tool, input, _ in
            // AC4: Read-only tools auto-allow in all modes
            if tool.isReadOnly {
                return .allow()
            }

            // AC3: bypassPermissions — auto-allow everything
            if mode == .bypassPermissions {
                return .allow()
            }

            // AC2: acceptEdits — auto-allow Write/Edit, others need confirmation
            if mode == .acceptEdits {
                if tool.name == "Write" || tool.name == "Edit" {
                    return .allow()
                }
                // Fall through to prompt for Bash etc.
            }

            // AC3: Session allow list check (v2 — Story 38.3)
            if let allowList = sessionAllowList {
                let commandKey = extractCommandKey(tool: tool, input: input)
                if let key = commandKey, allowList.isAllowed(command: key) {
                    return .allow()  // Already approved in this session
                }
            }

            // AC8: non-TTY safety — deny (cannot interact)
            if !isTTY {
                return .deny("非终端环境，拒绝执行 \(tool.name)")
            }

            // v2: dynamic approval options
            if let allowList = sessionAllowList {
                return handleV2Approval(
                    tool: tool,
                    input: input,
                    allowList: allowList,
                    readUserInput: readUserInput
                )
            }

            // v1: original [y/n] prompt (backward compatible)
            return handleV1Prompt(
                tool: tool,
                input: input,
                readUserInput: readUserInput
            )
        }
    }

    // MARK: - Mode Resolution

    /// Computes the effective ``PermissionMode`` from CLI flags.
    static func resolveMode(
        acceptEdits: Bool,
        dangerouslySkipPermissions: Bool
    ) -> PermissionMode {
        if dangerouslySkipPermissions {
            return .bypassPermissions
        }
        if acceptEdits {
            return .acceptEdits
        }
        return .default
    }

    /// Returns a human-readable display name for the permission mode (used in /config).
    static func modeDisplayName(_ mode: PermissionMode) -> String {
        switch mode {
        case .default: return "default"
        case .acceptEdits: return "acceptEdits"
        case .bypassPermissions: return "bypassPermissions"
        case .plan: return "plan"
        case .dontAsk: return "dontAsk"
        case .auto: return "auto"
        }
    }
}
