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
    let callbackQuery: TGCallbackQuery?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
        case callbackQuery = "callback_query"
    }

    init(updateId: Int64, message: TGMessage? = nil, callbackQuery: TGCallbackQuery? = nil) {
        self.updateId = updateId
        self.message = message
        self.callbackQuery = callbackQuery
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

// MARK: - Parse Mode

enum TGParseMode: String, Sendable {
    case markdownV2 = "MarkdownV2"
    case html = "HTML"
    case plain = ""
}

// MARK: - Send Message Request

struct TGSendMessageRequest: Codable, Sendable {
    let chatId: Int64
    let text: String
    let parseMode: String?
    let replyToMessageId: Int64?
    let replyMarkup: TGInlineKeyboardMarkup?

    enum CodingKeys: String, CodingKey {
        case chatId = "chat_id"
        case text
        case parseMode = "parse_mode"
        case replyToMessageId = "reply_to_message_id"
        case replyMarkup = "reply_markup"
    }

    init(chatId: Int64, text: String, parseMode: TGParseMode? = nil, replyToMessageId: Int64? = nil, replyMarkup: TGInlineKeyboardMarkup? = nil) {
        self.chatId = chatId
        self.text = text
        self.parseMode = parseMode == .plain ? nil : parseMode?.rawValue
        self.replyToMessageId = replyToMessageId
        self.replyMarkup = replyMarkup
    }
}

// MARK: - Edit Message Text Request

struct TGEditMessageTextRequest: Codable, Sendable {
    let chatId: Int64?
    let messageId: Int64?
    let inlineMessageId: String?
    let text: String
    let parseMode: String?
    let replyMarkup: TGInlineKeyboardMarkup?

    enum CodingKeys: String, CodingKey {
        case chatId = "chat_id"
        case messageId = "message_id"
        case inlineMessageId = "inline_message_id"
        case text
        case parseMode = "parse_mode"
        case replyMarkup = "reply_markup"
    }

    init(chatId: Int64? = nil, messageId: Int64? = nil, inlineMessageId: String? = nil, text: String, parseMode: TGParseMode? = nil, replyMarkup: TGInlineKeyboardMarkup? = nil) {
        self.chatId = chatId
        self.messageId = messageId
        self.inlineMessageId = inlineMessageId
        self.text = text
        self.parseMode = parseMode == .plain ? nil : parseMode?.rawValue
        self.replyMarkup = replyMarkup
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

// MARK: - Callback Query

struct TGCallbackQuery: Codable, Sendable, Equatable {
    let id: String
    let from: TGUser
    let message: TGMessage?
    let data: String?

    enum CodingKeys: String, CodingKey {
        case id, from, message, data
    }
}

// MARK: - Inline Keyboard

struct TGInlineKeyboardMarkup: Codable, Sendable, Equatable {
    let inlineKeyboard: [[TGInlineKeyboardButton]]

    enum CodingKeys: String, CodingKey {
        case inlineKeyboard = "inline_keyboard"
    }

    init(inlineKeyboard: [[TGInlineKeyboardButton]]) {
        self.inlineKeyboard = inlineKeyboard
    }
}

struct TGInlineKeyboardButton: Codable, Sendable, Equatable {
    let text: String
    let callbackData: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case text
        case callbackData = "callback_data"
        case url
    }

    init(text: String, callbackData: String? = nil, url: String? = nil) {
        self.text = text
        self.callbackData = callbackData
        self.url = url
    }
}

// MARK: - Answer Callback Query Request

struct TGAnswerCallbackQueryRequest: Codable, Sendable {
    let callbackQueryId: String
    let text: String?
    let showAlert: Bool?

    enum CodingKeys: String, CodingKey {
        case callbackQueryId = "callback_query_id"
        case text
        case showAlert = "show_alert"
    }

    init(callbackQueryId: String, text: String? = nil, showAlert: Bool? = nil) {
        self.callbackQueryId = callbackQueryId
        self.text = text
        self.showAlert = showAlert
    }
}
