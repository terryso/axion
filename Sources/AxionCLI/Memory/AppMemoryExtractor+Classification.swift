
extension AppMemoryExtractor {

    // MARK: - Kind Classification

    /// Direct operation tool names (click, type, hotkey — non-exploratory).
    static let directOpNames: Set<String> = ["click", "type_text", "hotkey", "double_click"]

    /// Exploratory operation tool names (AX tree, screenshot, window listing).
    static let exploreOpNames: Set<String> = ["get_window_state", "get_accessibility_tree", "screenshot", "list_windows"]

    /// Classify the memory kind, confidence, and cause from tool pair outcomes.
    ///
    /// - Parameters:
    ///   - pairs: The tool-use/result pairs for this domain.
    ///   - hasError: Whether any pair indicates an error.
    ///   - workaround: A workaround description if an error was followed by success.
    /// - Returns: A tuple of (kind, confidence, cause).
    func classifyKind(
        pairs: [ToolPair],
        hasError: Bool,
        workaround: String?
    ) -> (kind: MemoryKind, confidence: Double, cause: String?) {
        if hasError && workaround != nil {
            return (.observation, 0.6, "workaround")
        }
        if hasError {
            return (.avoid, 0.5, nil)
        }

        let directOps = pairs.filter { pair in
            let name = stripMcpPrefix(pair.toolUse.toolName)
            return Self.directOpNames.contains(name)
        }
        let exploreOps = pairs.filter { pair in
            let name = stripMcpPrefix(pair.toolUse.toolName)
            return Self.exploreOpNames.contains(name)
        }

        if !directOps.isEmpty && directOps.count >= exploreOps.count && pairs.count <= 5 {
            return (.affordance, 0.72, nil)
        }

        return (.observation, 0.7, nil)
    }
}
