import Foundation

/// Complete window state returned by `get_window_state`.
struct WindowState: Codable, Equatable {
    let windowId: Int
    let pid: Int32
    let title: String?
    let bounds: WindowBounds
    let isMinimized: Bool
    let isFocused: Bool
    let axTree: AXElement?

    enum CodingKeys: String, CodingKey {
        case windowId = "window_id"
        case pid
        case title
        case bounds
        case isMinimized = "is_minimized"
        case isFocused = "is_focused"
        case axTree = "ax_tree"
    }

    /// Custom encode to ensure `ax_tree` is always present (null instead of omitted).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windowId, forKey: .windowId)
        try container.encode(pid, forKey: .pid)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(bounds, forKey: .bounds)
        try container.encode(isMinimized, forKey: .isMinimized)
        try container.encode(isFocused, forKey: .isFocused)
        // Always include ax_tree: encode the value or explicit null
        if let axTree {
            try container.encode(axTree, forKey: .axTree)
        } else {
            try container.encodeNil(forKey: .axTree)
        }
    }
}
