import Foundation
import OpenAgentSDK

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

    func remove(pendingId: String) -> TGInteractionSession? {
        sessions.removeValue(forKey: pendingId)
    }

    func get(pendingId: String) -> TGInteractionSession? {
        sessions[pendingId]
    }

    func session(for chatId: Int64) -> TGInteractionSession? {
        sessions.values.first { $0.chatId == chatId && !$0.isExpired }
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
