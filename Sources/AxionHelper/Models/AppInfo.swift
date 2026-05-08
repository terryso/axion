import Foundation

/// Information about a running macOS application.
struct AppInfo: Codable, Equatable {
    let pid: Int32
    let appName: String
    let bundleId: String?

    enum CodingKeys: String, CodingKey {
        case pid
        case appName = "app_name"
        case bundleId = "bundle_id"
    }
}
