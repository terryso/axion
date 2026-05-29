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
    let photo: [TGPhotoSize]?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case from, chat, date, text, photo
    }

    init(messageId: Int64, from: TGUser? = nil, chat: TGChat, date: Int, text: String? = nil, photo: [TGPhotoSize]? = nil) {
        self.messageId = messageId
        self.from = from
        self.chat = chat
        self.date = date
        self.text = text
        self.photo = photo
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

// MARK: - Photo Size

struct TGPhotoSize: Codable, Sendable, Equatable {
    let fileId: String
    let width: Int
    let height: Int
    let fileSize: Int?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case width, height
        case fileSize = "file_size"
    }
}

// MARK: - File

struct TGFile: Codable, Sendable, Equatable {
    let fileId: String
    let filePath: String?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case filePath = "file_path"
    }
}
