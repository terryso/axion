import Foundation

import AxionCore

// MARK: - StopEvaluationResult

/// The result of evaluating stop conditions locally (without LLM assistance).
enum StopEvaluationResult: Equatable {
    case satisfied
    case notSatisfied
    case uncertain
}

// MARK: - StopConditionEvaluator

/// Evaluates stop conditions against captured verification context using local rule matching.
/// Pure function: no MCP calls, no side effects. Only processes data already obtained.
///
/// Evaluation strategy:
/// - Built-in conditions (textAppears, windowAppears, windowDisappears, processExits, maxStepsReached)
///   are evaluated via local pattern matching on AX tree text and executed step history.
/// - Conditions that cannot be locally evaluated (custom, fileExists) return `.uncertain`,
///   signalling that LLM evaluation is needed.
/// - All conditions must be satisfied for the overall result to be `.satisfied`.
struct StopConditionEvaluator {

    // MARK: - Public Interface

    /// Evaluates a set of stop conditions against the available verification context.
    /// - Parameters:
    ///   - stopConditions: The stop conditions from the Plan's `stopWhen` field.
    ///   - screenshot: Base64-encoded screenshot (unused in local evaluation, reserved for future use).
    ///   - axTree: JSON string of the AX accessibility tree.
    ///   - executedSteps: The steps executed so far in this batch.
    ///   - maxSteps: Maximum number of steps allowed (from config).
    /// - Returns: `.satisfied` if all conditions are met, `.notSatisfied` if any condition is
    ///   definitively not met, `.uncertain` if any condition cannot be locally determined.
    func evaluate(
        stopConditions: [StopCondition],
        screenshot: String?,
        axTree: String?,
        executedSteps: [ExecutedStep],
        maxSteps: Int
    ) -> StopEvaluationResult {
        // No conditions means trivially satisfied
        if stopConditions.isEmpty {
            return .satisfied
        }

        var hasUncertain = false

        for condition in stopConditions {
            let result = evaluateSingle(condition: condition, axTree: axTree, executedSteps: executedSteps, maxSteps: maxSteps)
            switch result {
            case .notSatisfied:
                return .notSatisfied
            case .uncertain:
                hasUncertain = true
            case .satisfied:
                break
            }
        }

        return hasUncertain ? .uncertain : .satisfied
    }

    // MARK: - Single Condition Evaluation

    private func evaluateSingle(
        condition: StopCondition,
        axTree: String?,
        executedSteps: [ExecutedStep],
        maxSteps: Int
    ) -> StopEvaluationResult {
        switch condition.type {
        case .textAppears:
            return evaluateTextAppears(value: condition.value, axTree: axTree)
        case .windowAppears:
            return evaluateWindowAppears(value: condition.value, axTree: axTree)
        case .windowDisappears:
            return evaluateWindowDisappears(value: condition.value, axTree: axTree)
        case .processExits:
            return evaluateProcessExits(value: condition.value, executedSteps: executedSteps)
        case .maxStepsReached:
            return evaluateMaxStepsReached(executedSteps: executedSteps, maxSteps: maxSteps)
        case .fileExists:
            // Requires MCP file system access; cannot evaluate locally
            return .uncertain
        case .custom:
            // Requires LLM evaluation; cannot determine locally
            return .uncertain
        }
    }

    // MARK: - Text Appears

    /// Searches for the target text in AX tree value/title fields (case-insensitive substring match).
    private func evaluateTextAppears(value: String?, axTree: String?) -> StopEvaluationResult {
        guard let searchText = value, !searchText.isEmpty else { return .uncertain }
        guard let axTree = axTree else { return .uncertain }

        return searchAXTree(axTree: axTree, searchText: searchText) ? .satisfied : .notSatisfied
    }

    // MARK: - Window Appears

    /// Checks if a window node with the given title exists in the AX tree.
    /// Only matches nodes whose role indicates a window (AXWindow, AXDialog, etc.).
    private func evaluateWindowAppears(value: String?, axTree: String?) -> StopEvaluationResult {
        guard let windowTitle = value, !windowTitle.isEmpty else { return .uncertain }
        guard let axTree = axTree else { return .uncertain }

        return searchAXTreeForWindow(axTree: axTree, searchText: windowTitle) ? .satisfied : .notSatisfied
    }

    // MARK: - Window Disappears

    /// Checks that no window node with the given title exists in the AX tree.
    private func evaluateWindowDisappears(value: String?, axTree: String?) -> StopEvaluationResult {
        guard let windowTitle = value, !windowTitle.isEmpty else { return .uncertain }
        guard let axTree = axTree else { return .uncertain }

        return searchAXTreeForWindow(axTree: axTree, searchText: windowTitle) ? .notSatisfied : .satisfied
    }

    // MARK: - Process Exits

    /// Checks the last `list_apps` result to see if the target process has exited.
    /// Handles both "Calculator" and "Calculator.app" naming conventions.
    private func evaluateProcessExits(value: String?, executedSteps: [ExecutedStep]) -> StopEvaluationResult {
        guard let processName = value, !processName.isEmpty else { return .uncertain }

        // Find the last list_apps result
        let listAppsSteps = executedSteps.filter { $0.tool == ToolNames.listApps && $0.success }
        guard let lastListApps = listAppsSteps.last else { return .uncertain }

        // Parse the result to check if the process is still running
        guard let data = lastListApps.result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .uncertain
        }

        if let apps = json["apps"] as? [[String: Any]] {
            let target = processName.lowercased()
                .replacingOccurrences(of: ".app", with: "")
            let isStillRunning = apps.contains { app in
                guard let appName = app["app_name"] as? String else { return false }
                let normalized = appName.lowercased()
                    .replacingOccurrences(of: ".app", with: "")
                return normalized == target
            }
            return isStillRunning ? .notSatisfied : .satisfied
        }

        return .uncertain
    }

    // MARK: - Max Steps Reached

    /// Checks if the number of executed steps has reached the configured maximum.
    private func evaluateMaxStepsReached(executedSteps: [ExecutedStep], maxSteps: Int) -> StopEvaluationResult {
        return executedSteps.count >= maxSteps ? .satisfied : .notSatisfied
    }

    // MARK: - AX Tree Search

    /// Recursively searches a JSON structure for string values containing the search text.
    /// Only matches against specific text-bearing fields (value, title, text, etc.)
    /// to avoid false positives from structural values like role names or JSON keys.
    private func searchAXTree(axTree: String, searchText: String) -> Bool {
        guard let data = axTree.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return searchJSONObject(json, searchText: searchText)
    }

    /// Searches for a window node whose title/value matches the search text.
    /// Only considers nodes with a role indicating a window type (AXWindow, AXDialog, etc.).
    private func searchAXTreeForWindow(axTree: String, searchText: String) -> Bool {
        guard let data = axTree.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return searchForWindowNode(json, searchText: searchText)
    }

    /// Recursively searches a JSON object tree for matching text in text-bearing fields only.
    private func searchJSONObject(_ object: Any, searchText: String) -> Bool {
        let lowered = searchText.lowercased()

        if let dict = object as? [String: Any] {
            let textFields: Set<String> = ["value", "title", "app_name", "text", "description", "label"]
            for (key, value) in dict {
                if textFields.contains(key), let stringValue = value as? String {
                    if stringValue.lowercased().contains(lowered) {
                        return true
                    }
                }
                if searchJSONObject(value, searchText: searchText) {
                    return true
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if searchJSONObject(item, searchText: searchText) {
                    return true
                }
            }
        }

        return false
    }

    /// Recursively searches for a window-type node with matching title/value.
    private func searchForWindowNode(_ object: Any, searchText: String) -> Bool {
        let lowered = searchText.lowercased()

        if let dict = object as? [String: Any] {
            let role = (dict["role"] as? String)?.lowercased() ?? ""
            if role.contains("window") {
                let title = (dict["title"] as? String)?.lowercased() ?? ""
                let value = (dict["value"] as? String)?.lowercased() ?? ""
                if title.contains(lowered) || value.contains(lowered) {
                    return true
                }
            }
            for (_, value) in dict {
                if searchForWindowNode(value, searchText: searchText) {
                    return true
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if searchForWindowNode(item, searchText: searchText) {
                    return true
                }
            }
        }

        return false
    }
}
