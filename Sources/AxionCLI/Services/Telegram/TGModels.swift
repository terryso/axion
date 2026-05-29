import Foundation

// MARK: - TG Bot API Response

struct TGResponse<T: Codable & Sendable>: Codable, Sendable {
    let ok: Bool
    let result: T?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case ok, result, description
    }
}

// MARK: - Update Model

struct TGUpdate: Codable, Sendable, Equatable {
    let updateId: Int64
    let message: TGMessage?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
    }
}

// MARK: - Message Model

struct TGMessage: Codable, Sendable, Equatable {
    let messageId: Int64
    let from: TGUser?
    let chat: TGChat
    let date: Int
    let text: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case from, chat, date, text
    }
}

// MARK: - User Model

struct TGUser: Codable, Sendable, Equatable {
    let id: Int64
    let firstName: String?
    let lastName: String?
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case username
    }
}

// MARK: - Chat Model

struct TGChat: Codable, Sendable, Equatable {
    let id: Int64
    let type: String
}

// MARK: - Send Message Request

struct TGSendMessageRequest: Codable, Sendable {
    let chatId: Int64
    let text: String
    let parseMode: String?

    enum CodingKeys: String, CodingKey {
        case chatId = "chat_id"
        case text
        case parseMode = "parse_mode"
    }
}
