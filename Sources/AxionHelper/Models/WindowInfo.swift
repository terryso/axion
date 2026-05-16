import Foundation

/// Lightweight window information returned by `list_windows`.
struct WindowInfo: Codable, Equatable {
    let windowId: Int
    let pid: Int32
    let title: String?
    let appName: String?
    let bundleId: String?
    let bounds: WindowBounds
    let zOrder: Int

    enum CodingKeys: String, CodingKey {
        case windowId = "window_id"
        case pid
        case title
        case appName = "app_name"
        case bundleId = "bundle_id"
        case bounds
        case zOrder = "z_order"
    }

    init(windowId: Int, pid: Int32, title: String?, appName: String?, bundleId: String?, bounds: WindowBounds, zOrder: Int = 0) {
        self.windowId = windowId
        self.pid = pid
        self.title = title
        self.appName = appName
        self.bundleId = bundleId
        self.bounds = bounds
        self.zOrder = zOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowId = try container.decode(Int.self, forKey: .windowId)
        pid = try container.decode(Int32.self, forKey: .pid)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        bounds = try container.decode(WindowBounds.self, forKey: .bounds)
        zOrder = try container.decodeIfPresent(Int.self, forKey: .zOrder) ?? 0
    }
}

/// Rectangular bounds for a window or AX element.
struct WindowBounds: Codable, Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}
