import Foundation

import AxionCore

// MARK: - ExecutionContext

/// Tracks runtime state accumulated during step execution.
/// Simplified from OpenClick's ExecutorContext (20+ fields) to pid + windowId for MVP.
public struct ExecutionContext: Equatable {
    public var pid: Int?
    public var windowId: Int?

    public init(pid: Int? = nil, windowId: Int? = nil) {
        self.pid = pid
        self.windowId = windowId
    }
}

// MARK: - PlaceholderResolver

/// Resolves `$pid` and `$window_id` placeholders in step parameters using the accumulated
/// ExecutionContext from prior step results. This is the Axion equivalent of OpenClick's
/// `substitutePlaceholders` function, simplified for MVP.
public struct PlaceholderResolver {

    public init() {}

    /// Replaces `.placeholder("$pid")` and `.placeholder("$window_id")` values in step
    /// parameters with the corresponding values from the execution context.
    /// Unknown placeholders and non-placeholder values are preserved as-is.
    public func resolve(step: Step, context: ExecutionContext) -> Step {
        var resolvedParams: [String: Value] = [:]
        for (key, value) in step.parameters {
            switch value {
            case .placeholder(let name) where name == "$pid" && context.pid != nil:
                resolvedParams[key] = .int(context.pid!)
            case .placeholder(let name) where name == "$window_id" && context.windowId != nil:
                resolvedParams[key] = .int(context.windowId!)
            default:
                resolvedParams[key] = value
            }
        }
        return Step(
            index: step.index,
            tool: step.tool,
            parameters: resolvedParams,
            purpose: step.purpose,
            expectedChange: step.expectedChange
        )
    }

    /// Extracts pid and window_id from MCP tool result JSON and updates the execution context.
    /// Only processes tools that produce pid/window_id: launch_app, list_windows, get_window_state.
    public func absorbResult(tool: String, result: String, context: inout ExecutionContext) {
        let contextProducingTools: Set<String> = [
            ToolNames.launchApp,
            ToolNames.listWindows,
            ToolNames.getWindowState
        ]
        guard contextProducingTools.contains(tool) else { return }

        guard let data = result.data(using: .utf8) else { return }

        // Try parsing as JSON object: {"pid": ..., "window_id": ...}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Direct pid / window_id extraction
            if let pid = json["pid"] as? Int { context.pid = pid }
            if let windowId = json["window_id"] as? Int { context.windowId = windowId }

            // list_windows mock format: {"windows": [...]}
            if let windows = json["windows"] as? [[String: Any]], let first = windows.first {
                if let pid = first["pid"] as? Int { context.pid = pid }
                if let windowId = first["window_id"] as? Int { context.windowId = windowId }
            }
            return
        }

        // Try parsing as JSON array (real MCP list_windows format): [{...}, {...}]
        if let windows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = windows.first {
            if let pid = first["pid"] as? Int { context.pid = pid }
            if let windowId = first["window_id"] as? Int { context.windowId = windowId }
        }
    }
}
