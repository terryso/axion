import Foundation
import OpenAgentSDK

/// Diagnostics handler that logs each tool invocation to stderr — tool name plus its
/// input (e.g. the file path for `Read`, the command for `Bash`) — so **subagent**
/// activity becomes visible.
///
/// Subagents spawned via the Task/Agent tool run through `agent.prompt()` (non-streaming),
/// so their tool calls never reach the main agent's stream renderer. That makes it
/// impossible to tell, for example, whether a `bmad-create-story` subagent actually read
/// `project-context.md` during its activation protocol. Because every tool call — main
/// agent and child alike — is published as a ``ToolStartedEvent`` on the shared
/// ``EventBus`` (via `ToolExecutor`), subscribing here captures the child's calls too,
/// including the `input` field that holds the file path.
///
/// Opt-in via the `AXION_LOG_TOOL_CALLS` env var (any non-empty value) so normal runs
/// stay free of stderr noise. Usage:
///
///     AXION_LOG_TOOL_CALLS=1 swift run AxionCLI
///
/// then grep the output (or `2>tool.log`) for a pattern, e.g. `project-context`.
/// The bracketed session id distinguishes subagent calls (often a different/absent id
/// from the main run).
actor ToolCallLogHandler: EventHandler {
    let identifier = "tool-call-log"
    let subscribedEventTypes: [any AgentEvent.Type] = [ToolStartedEvent.self]

    init() {}

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard let e = event as? ToolStartedEvent else { return }
        Self.log(e)
    }

    // MARK: - Static logging (shared with non-handler callers, e.g. the chat REPL)

    /// Whether `AXION_LOG_TOOL_CALLS` is set (any non-empty value). Read once per process.
    static let isEnabled: Bool = {
        let flag = ProcessInfo.processInfo.environment["AXION_LOG_TOOL_CALLS"]
        return !(flag?.isEmpty ?? true)
    }()

    /// Emits a `[tool] <name>: <input>` line to stderr. No-op when ``isEnabled`` is false.
    /// Shared between the EventHandler path (runtime runs) and the chat REPL, which builds
    /// its agent directly (no runtime/handler registration) and so subscribes the typed
    /// `ToolStartedEvent` stream itself.
    static func log(_ event: ToolStartedEvent) {
        guard isEnabled else { return }
        let raw = (event.input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated: String
        if raw.isEmpty {
            truncated = ""
        } else if raw.count > 200 {
            truncated = String(raw.prefix(200)) + "…"
        } else {
            truncated = raw
        }
        let sid = event.sessionId.map { "[\($0)] " } ?? "[subagent] "
        let detail = truncated.isEmpty ? "" : ": \(truncated)"
        fputs("[tool] \(sid)\(event.toolName)\(detail)\n", stderr)
    }
}
