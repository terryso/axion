import AxionCore
import OpenAgentSDK

/// Constructs the safety HookRegistry that blocks foreground tools in shared-seat mode.
enum SafetyHookFactory {

    /// Creates a HookRegistry with preToolUse hook implementing SafetyChecker logic.
    ///
    /// In shared-seat mode, foreground interaction tools (clicks, typing, etc.) are
    /// blocked because a remote user shouldn't control the desktop while someone
    /// else is at the keyboard.
    static func buildSafetyHookRegistry(sharedSeatMode: Bool) async -> HookRegistry {
        let registry = HookRegistry()

        if sharedSeatMode {
            let foregroundTools = ToolNames.foregroundToolNames.map { "mcp__axion-helper__\($0)" }
            let safetyHook = HookDefinition(handler: { input in
                guard let toolName = input.toolName else { return HookOutput(decision: .approve) }

                if foregroundTools.contains(toolName) {
                    return HookOutput(
                        decision: .block,
                        reason: "Tool '\(toolName)' requires foreground interaction and is blocked in shared seat mode for safety. Use --allow-foreground to enable."
                    )
                }
                return HookOutput(decision: .approve)
            })

            await registry.register(.preToolUse, definition: safetyHook)
        }

        return registry
    }
}
