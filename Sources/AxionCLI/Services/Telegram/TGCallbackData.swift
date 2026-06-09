import Foundation

// MARK: - Interaction Modes

enum TGInteractionMode: String, Sendable {
    case approval
    case confirm
    case clarify
    case textCapture = "text_capture"
}

// MARK: - Pending Session

struct TGInteractionSession: Sendable {
    let pendingId: String
    let chatId: Int64
    let messageId: Int64
    let mode: TGInteractionMode
    let clarifyOptions: [String]
    let allowedUserId: Int64
    let createdAt: Date
    let ttlSeconds: Int
    let resumeHandler: @Sendable (String) async throws -> Void

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > Double(ttlSeconds)
    }
}

// MARK: - Callback Data Encoding

enum TGCallbackAction: String, Sendable {
    case approve
    case deny
    case confirm = "ok"
    case cancel
    case clarify
    case skip
    case respond
    case skillsPage = "skills_page"
    case triggerSkill = "trigger_skill"
}

struct TGCallbackData: Sendable {
    let action: TGCallbackAction
    let detail: String
    let pendingId: String

    var encoded: String {
        "\(action.rawValue):\(detail):\(pendingId)"
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 2)
        guard parts.count >= 2,
              let action = TGCallbackAction(rawValue: String(parts[0]))
        else { return nil }
        self.action = action
        if parts.count == 3 {
            self.detail = String(parts[1])
            self.pendingId = String(parts[2])
        } else {
            self.detail = ""
            self.pendingId = String(parts[1])
        }
    }

    init(action: TGCallbackAction, detail: String = "", pendingId: String) {
        self.action = action
        self.detail = detail
        self.pendingId = pendingId
    }
}
