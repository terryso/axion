import Foundation

/// Lightweight window information returned by `list_windows`.
struct WindowInfo: Codable, Equatable {
    let windowId: Int
    let pid: Int32
    let title: String?
    let appName: String?
    let bundleId: String?
    let bounds: WindowBounds

    enum CodingKeys: String, CodingKey {
        case windowId = "window_id"
        case pid
        case title
        case appName = "app_name"
        case bundleId = "bundle_id"
        case bounds
    }
}

/// Rectangular bounds for a window or AX element.
struct WindowBounds: Codable, Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}
