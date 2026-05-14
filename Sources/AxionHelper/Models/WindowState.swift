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
    let appName: String?

    enum CodingKeys: String, CodingKey {
        case windowId = "window_id"
        case pid
        case title
        case bounds
        case isMinimized = "is_minimized"
        case isFocused = "is_focused"
        case axTree = "ax_tree"
        case appName = "app_name"
    }

    init(windowId: Int, pid: Int32, title: String?, bounds: WindowBounds, isMinimized: Bool, isFocused: Bool, axTree: AXElement?, appName: String? = nil) {
        self.windowId = windowId
        self.pid = pid
        self.title = title
        self.bounds = bounds
        self.isMinimized = isMinimized
        self.isFocused = isFocused
        self.axTree = axTree
        self.appName = appName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowId = try container.decode(Int.self, forKey: .windowId)
        pid = try container.decode(Int32.self, forKey: .pid)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        bounds = try container.decode(WindowBounds.self, forKey: .bounds)
        isMinimized = try container.decode(Bool.self, forKey: .isMinimized)
        isFocused = try container.decode(Bool.self, forKey: .isFocused)
        axTree = try container.decodeIfPresent(AXElement.self, forKey: .axTree)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
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
        try container.encodeIfPresent(appName, forKey: .appName)
    }
}
