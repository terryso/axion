import Foundation

struct ValidateWindowResult: Codable, Equatable {
    let windowId: Int
    let exists: Bool
    let actionable: Bool
    let title: String?
    let pid: Int?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case windowId = "window_id"
        case exists, actionable, title, pid, reason
    }
}
