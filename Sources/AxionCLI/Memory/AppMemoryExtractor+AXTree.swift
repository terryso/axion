
extension AppMemoryExtractor {

    // MARK: - AX Tree Extraction

    /// Extract AX tree structure summary from get_window_state / get_accessibility_tree tool results.
    func extractAxTreeSummary(from pairs: [ToolPair]) -> String {
        var roleTypes: Set<String> = []

        for pair in pairs {
            let toolName = stripMcpPrefix(pair.toolUse.toolName)
            guard toolName == "get_window_state" || toolName == "get_accessibility_tree" else { continue }

            // Try to parse AX tree JSON from the result
            if let axInfo = parseAxRoles(from: pair.toolResult.content) {
                roleTypes.formUnion(axInfo)
            }
        }

        guard !roleTypes.isEmpty else { return "" }

        let sorted = roleTypes.sorted()
        if sorted.count <= 3 {
            return "窗口包含 \(sorted.joined(separator: "、")) 角色控件"
        } else {
            return "窗口包含 \(sorted.prefix(3).joined(separator: "、")) 等 \(sorted.count) 种角色控件"
        }
    }

    /// Extract key controls (AXButton, AXTextField with titles) from AX tree tool results.
    func extractKeyControls(from pairs: [ToolPair]) -> String {
        var controls: [String] = []

        for pair in pairs {
            let toolName = stripMcpPrefix(pair.toolUse.toolName)
            guard toolName == "get_window_state" || toolName == "get_accessibility_tree" else { continue }

            if let titledControls = parseAxTitledControls(from: pair.toolResult.content) {
                controls.append(contentsOf: titledControls)
            }
        }

        guard !controls.isEmpty else { return "" }

        // Limit to most relevant controls (max 5)
        let limited = Array(controls.prefix(5))
        return limited.joined(separator: ", ")
    }

    // MARK: - AX Tree JSON Parsing

    /// Parse AX tree JSON to extract role types.
    func parseAxRoles(from content: String) -> Set<String>? {
        guard let json = parseJSONDict(from: content) else { return nil }

        var roles = Set<String>()
        collectRoles(from: json, into: &roles, depth: 0)
        return roles.isEmpty ? nil : roles
    }

    static let maxAxDepth = 50

    /// Recursively collect AX role types from JSON tree with depth guard.
    func collectRoles(from node: [String: Any], into roles: inout Set<String>, depth: Int) {
        guard depth <= Self.maxAxDepth else { return }
        if let role = node["role"] as? String, role.hasPrefix("AX") {
            roles.insert(role)
        }
        if let children = node["children"] as? [[String: Any]] {
            for child in children {
                collectRoles(from: child, into: &roles, depth: depth + 1)
            }
        }
        if let windows = node["windows"] as? [[String: Any]] {
            for window in windows {
                collectRoles(from: window, into: &roles, depth: depth + 1)
            }
        }
        if let root = node["root"] as? [String: Any] {
            collectRoles(from: root, into: &roles, depth: depth + 1)
        }
    }

    /// Parse AX tree JSON to extract titled controls (for "关键控件" summary).
    func parseAxTitledControls(from content: String) -> [String]? {
        guard let json = parseJSONDict(from: content) else { return nil }

        var controls: [String] = []
        collectTitledControls(from: json, into: &controls, depth: 0)
        return controls.isEmpty ? nil : controls
    }

    func collectTitledControls(from node: [String: Any], into controls: inout [String], depth: Int) {
        guard depth <= Self.maxAxDepth else { return }
        let role = node["role"] as? String ?? ""
        let title = node["title"] as? String

        if let title, !title.isEmpty,
           role.hasPrefix("AX") && (role.contains("Button") || role.contains("TextField") || role.contains("Menu")) {
            controls.append("\(role)[title=\"\(title)\"]")
        }

        if let children = node["children"] as? [[String: Any]] {
            for child in children {
                collectTitledControls(from: child, into: &controls, depth: depth + 1)
            }
        }
        if let windows = node["windows"] as? [[String: Any]] {
            for window in windows {
                collectTitledControls(from: window, into: &controls, depth: depth + 1)
            }
        }
        if let root = node["root"] as? [String: Any] {
            collectTitledControls(from: root, into: &controls, depth: depth + 1)
        }
    }
}
