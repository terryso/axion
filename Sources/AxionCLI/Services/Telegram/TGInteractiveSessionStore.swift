import Foundation
import OpenAgentSDK

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

// MARK: - Session Store

actor TGInteractiveSessionStore {
    private var sessions: [String: TGInteractionSession] = [:]

    var activeSessionCount: Int { sessions.count }

    func register(
        pendingId: String,
        chatId: Int64,
        messageId: Int64,
        mode: TGInteractionMode,
        clarifyOptions: [String] = [],
        allowedUserId: Int64,
        ttlSeconds: Int = 300,
        onResume: @escaping @Sendable (String) async throws -> Void
    ) {
        let session = TGInteractionSession(
            pendingId: pendingId,
            chatId: chatId,
            messageId: messageId,
            mode: mode,
            clarifyOptions: clarifyOptions,
            allowedUserId: allowedUserId,
            createdAt: Date(),
            ttlSeconds: ttlSeconds,
            resumeHandler: onResume
        )
        sessions[pendingId] = session
    }

    func resume(pendingId: String, response: String) async throws -> Bool {
        guard let session = sessions[pendingId] else { return false }
        guard !session.isExpired else {
            sessions[pendingId] = nil
            return false
        }
        sessions[pendingId] = nil
        try await session.resumeHandler(response)
        return true
    }

    enum CallbackResolution: Sendable {
        case resumed(context: String)
        case expired
        case unauthorized
        case notFound
    }

    func resolveCallback(pendingId: String, fromUser: Int64) async throws -> CallbackResolution {
        guard let session = sessions[pendingId] else { return .notFound }
        guard !session.isExpired else {
            sessions[pendingId] = nil
            return .expired
        }
        guard session.allowedUserId == fromUser else {
            return .unauthorized
        }
        sessions[pendingId] = nil
        try await session.resumeHandler("callback")
        return .resumed(context: "callback")
    }

    func remove(pendingId: String) -> TGInteractionSession? {
        sessions.removeValue(forKey: pendingId)
    }

    func get(pendingId: String) -> TGInteractionSession? {
        sessions[pendingId]
    }

    func session(for chatId: Int64) -> TGInteractionSession? {
        sessions.values.first { $0.chatId == chatId && !$0.isExpired }
    }

    func purgeExpired() -> [TGInteractionSession] {
        var expired: [TGInteractionSession] = []
        for (key, session) in sessions where session.isExpired {
            expired.append(session)
            sessions.removeValue(forKey: key)
        }
        return expired
    }

    func buildKeyboard(for mode: TGInteractionMode, pendingId: String, clarifyOptions: [String] = []) -> TGInlineKeyboardMarkup {
        switch mode {
        case .approval:
            return TGInlineKeyboardMarkup(inlineKeyboard: [
                [
                    TGInlineKeyboardButton(text: "Allow Once", callbackData: TGCallbackData(action: .approve, detail: "once", pendingId: pendingId).encoded),
                    TGInlineKeyboardButton(text: "Session", callbackData: TGCallbackData(action: .approve, detail: "session", pendingId: pendingId).encoded),
                    TGInlineKeyboardButton(text: "Always", callbackData: TGCallbackData(action: .approve, detail: "always", pendingId: pendingId).encoded),
                ],
                [
                    TGInlineKeyboardButton(text: "Deny", callbackData: TGCallbackData(action: .deny, pendingId: pendingId).encoded),
                ]
            ])
        case .confirm:
            return TGInlineKeyboardMarkup(inlineKeyboard: [
                [
                    TGInlineKeyboardButton(text: "Approve Once", callbackData: TGCallbackData(action: .confirm, detail: "once", pendingId: pendingId).encoded),
                    TGInlineKeyboardButton(text: "Always Approve", callbackData: TGCallbackData(action: .confirm, detail: "always", pendingId: pendingId).encoded),
                ],
                [
                    TGInlineKeyboardButton(text: "Cancel", callbackData: TGCallbackData(action: .cancel, pendingId: pendingId).encoded),
                ]
            ])
        case .clarify:
            var rows: [[TGInlineKeyboardButton]] = []
            for (index, _) in clarifyOptions.enumerated() {
                rows.append([
                    TGInlineKeyboardButton(text: clarifyOptions[index], callbackData: TGCallbackData(action: .clarify, detail: String(index), pendingId: pendingId).encoded)
                ])
            }
            rows.append([
                TGInlineKeyboardButton(text: "Type Answer", callbackData: TGCallbackData(action: .respond, pendingId: pendingId).encoded)
            ])
            return TGInlineKeyboardMarkup(inlineKeyboard: rows)
        case .textCapture:
            return TGInlineKeyboardMarkup(inlineKeyboard: [
                [
                    TGInlineKeyboardButton(text: "Skip", callbackData: TGCallbackData(action: .skip, pendingId: pendingId).encoded),
                ]
            ])
        }
    }
}
