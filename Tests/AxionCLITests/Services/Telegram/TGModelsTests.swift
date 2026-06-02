import Testing
import Foundation
@testable import AxionCLI

@Suite("TGModels")
struct TGModelsTests {

    // MARK: - TGResponse Codable

    @Test("TGResponse<[TGUpdate]> round-trip")
    func responseUpdateRoundTrip() throws {
        let update = TGUpdate(updateId: 123, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 12345, firstName: "Nick", lastName: nil, username: "nick"),
            chat: TGChat(id: 12345, type: "private"),
            date: 1_700_000_000,
            text: "hello"
        ))
        let response = TGResponse<[TGUpdate]>(ok: true, result: [update], description: nil)

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(TGResponse<[TGUpdate]>.self, from: data)

        #expect(decoded.ok == true)
        #expect(decoded.result?.count == 1)
        #expect(decoded.result?.first?.updateId == 123)
        #expect(decoded.result?.first?.message?.text == "hello")
        #expect(decoded.result?.first?.message?.from?.id == 12345)
        #expect(decoded.result?.first?.message?.chat.id == 12345)
    }

    @Test("TGResponse error response round-trip")
    func responseErrorRoundTrip() throws {
        let response = TGResponse<[TGUpdate]>(ok: false, result: nil, description: "Unauthorized")

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(TGResponse<[TGUpdate]>.self, from: data)

        #expect(decoded.ok == false)
        #expect(decoded.result == nil)
        #expect(decoded.description == "Unauthorized")
    }

    // MARK: - TGUpdate

    @Test("TGUpdate decodes from snake_case JSON")
    func updateDecodesSnakeCase() throws {
        let json = """
        {"update_id": 42, "message": {"message_id": 1, "from": {"id": 99, "first_name": "A"}, "chat": {"id": 99, "type": "private"}, "date": 0, "text": "hi"}}
        """
        let data = try #require(json.data(using: .utf8))
        let update = try JSONDecoder().decode(TGUpdate.self, from: data)

        #expect(update.updateId == 42)
        #expect(update.message?.text == "hi")
        #expect(update.message?.from?.firstName == "A")
    }

    // MARK: - TGUser

    @Test("TGUser round-trip with all fields")
    func userRoundTrip() throws {
        let user = TGUser(id: 100, firstName: "John", lastName: "Doe", username: "johnd")

        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(TGUser.self, from: data)

        #expect(decoded == user)
        #expect(decoded.id == 100)
        #expect(decoded.firstName == "John")
        #expect(decoded.lastName == "Doe")
        #expect(decoded.username == "johnd")
    }

    // MARK: - TGChat

    @Test("TGChat round-trip")
    func chatRoundTrip() throws {
        let chat = TGChat(id: -1001234, type: "group")

        let data = try JSONEncoder().encode(chat)
        let decoded = try JSONDecoder().decode(TGChat.self, from: data)

        #expect(decoded == chat)
    }

    // MARK: - TGSendMessageRequest

    @Test("TGSendMessageRequest encodes snake_case keys")
    func sendMessageRequestEncoding() throws {
        let req = TGSendMessageRequest(chatId: 12345, text: "hello world", parseMode: nil)

        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"chat_id\":12345"))
        #expect(json.contains("\"text\":\"hello world\""))
    }

    // MARK: - Real TG API JSON

    @Test("Parse realistic getUpdates response")
    func parseRealisticResponse() throws {
        let json = """
        {
          "ok": true,
          "result": [
            {
              "update_id": 100,
              "message": {
                "message_id": 1,
                "from": {"id": 99999, "first_name": "Nick", "last_name": "T", "username": "nickt"},
                "chat": {"id": 99999, "type": "private"},
                "date": 1700000000,
                "text": "run ls -la"
              }
            },
            {
              "update_id": 101,
              "message": {
                "message_id": 2,
                "from": {"id": 88888, "first_name": "Other"},
                "chat": {"id": 88888, "type": "private"},
                "date": 1700000001,
                "text": "hello"
              }
            }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(TGResponse<[TGUpdate]>.self, from: data)

        #expect(response.ok)
        #expect(response.result?.count == 2)
        #expect(response.result?[0].message?.from?.username == "nickt")
        #expect(response.result?[1].message?.text == "hello")
    }

    @Test("TGMessage with nil text and nil from")
    func messageWithNilFields() throws {
        let json = """
        {"message_id": 5, "from": null, "chat": {"id": 123, "type": "private"}, "date": 0, "text": null}
        """
        let data = try #require(json.data(using: .utf8))
        let msg = try JSONDecoder().decode(TGMessage.self, from: data)

        #expect(msg.messageId == 5)
        #expect(msg.from == nil)
        #expect(msg.text == nil)
        #expect(msg.photo == nil)
    }

    // MARK: - Photo Support (Story 29.5)

    @Test("TGPhotoSize round-trip")
    func photoSizeRoundTrip() throws {
        let photo = TGPhotoSize(fileId: "abc123", width: 800, height: 600, fileSize: 50000)

        let data = try JSONEncoder().encode(photo)
        let decoded = try JSONDecoder().decode(TGPhotoSize.self, from: data)

        #expect(decoded == photo)
        #expect(decoded.fileId == "abc123")
        #expect(decoded.width == 800)
        #expect(decoded.height == 600)
        #expect(decoded.fileSize == 50000)
    }

    @Test("TGPhotoSize decodes from snake_case JSON")
    func photoSizeDecodeSnakeCase() throws {
        let json = """
        {"file_id": "xyz", "width": 100, "height": 100, "file_size": 2000}
        """
        let data = try #require(json.data(using: .utf8))
        let photo = try JSONDecoder().decode(TGPhotoSize.self, from: data)

        #expect(photo.fileId == "xyz")
        #expect(photo.fileSize == 2000)
    }

    @Test("TGFile round-trip")
    func fileRoundTrip() throws {
        let file = TGFile(fileId: "f1", filePath: "photos/file_0.jpg")

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(TGFile.self, from: data)

        #expect(decoded == file)
        #expect(decoded.filePath == "photos/file_0.jpg")
    }

    @Test("TGFile decodes from snake_case JSON")
    func fileDecodeSnakeCase() throws {
        let json = """
        {"file_id": "f2", "file_path": "documents/report.pdf"}
        """
        let data = try #require(json.data(using: .utf8))
        let file = try JSONDecoder().decode(TGFile.self, from: data)

        #expect(file.fileId == "f2")
        #expect(file.filePath == "documents/report.pdf")
    }

    @Test("TGMessage with photo array decodes correctly")
    func messageWithPhotoDecodes() throws {
        let json = """
        {
            "message_id": 42,
            "from": {"id": 123, "first_name": "Nick"},
            "chat": {"id": 123, "type": "private"},
            "date": 1700000000,
            "text": "check this",
            "photo": [
                {"file_id": "small", "width": 90, "height": 90, "file_size": 2000},
                {"file_id": "big", "width": 800, "height": 600, "file_size": 50000}
            ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let msg = try JSONDecoder().decode(TGMessage.self, from: data)

        #expect(msg.text == "check this")
        #expect(msg.photo?.count == 2)
        #expect(msg.photo?[0].fileId == "small")
        #expect(msg.photo?[1].fileId == "big")
        #expect(msg.photo?[1].width == 800)
    }

    @Test("TGMessage without photo field decodes with nil photo")
    func messageWithoutPhotoDecodes() throws {
        let json = """
        {"message_id": 1, "chat": {"id": 123, "type": "private"}, "date": 0, "text": "hello"}
        """
        let data = try #require(json.data(using: .utf8))
        let msg = try JSONDecoder().decode(TGMessage.self, from: data)

        #expect(msg.text == "hello")
        #expect(msg.photo == nil)
    }

    // MARK: - Callback Query (Story 32.5)

    @Test("TGCallbackQuery round-trip")
    func callbackQueryRoundTrip() throws {
        let query = TGCallbackQuery(
            id: "query123",
            from: TGUser(id: 42, firstName: "Nick", lastName: nil, username: "nick"),
            message: nil,
            data: "approve:run-abc"
        )

        let data = try JSONEncoder().encode(query)
        let decoded = try JSONDecoder().decode(TGCallbackQuery.self, from: data)

        #expect(decoded == query)
        #expect(decoded.id == "query123")
        #expect(decoded.data == "approve:run-abc")
        #expect(decoded.from.id == 42)
        #expect(decoded.message == nil)
    }

    @Test("TGCallbackQuery decodes from snake_case JSON")
    func callbackQueryDecodeSnakeCase() throws {
        let json = """
        {
            "update_id": 500,
            "callback_query": {
                "id": "cb1",
                "from": {"id": 99, "first_name": "User"},
                "message": {
                    "message_id": 10,
                    "chat": {"id": 99, "type": "private"},
                    "date": 1700000000,
                    "text": "Agent paused"
                },
                "data": "deny:run-xyz"
            }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let update = try JSONDecoder().decode(TGUpdate.self, from: data)

        #expect(update.updateId == 500)
        #expect(update.message == nil)
        #expect(update.callbackQuery != nil)
        #expect(update.callbackQuery?.id == "cb1")
        #expect(update.callbackQuery?.data == "deny:run-xyz")
        #expect(update.callbackQuery?.message?.messageId == 10)
        #expect(update.callbackQuery?.from.id == 99)
    }

    @Test("TGUpdate with both message and callbackQuery nil")
    func updateWithNoContent() throws {
        let json = """
        {"update_id": 999}
        """
        let data = try #require(json.data(using: .utf8))
        let update = try JSONDecoder().decode(TGUpdate.self, from: data)

        #expect(update.updateId == 999)
        #expect(update.message == nil)
        #expect(update.callbackQuery == nil)
    }

    // MARK: - Inline Keyboard (Story 32.5)

    @Test("TGInlineKeyboardButton round-trip")
    func inlineKeyboardButtonRoundTrip() throws {
        let button = TGInlineKeyboardButton(text: "Approve", callbackData: "approve:1")

        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(TGInlineKeyboardButton.self, from: data)

        #expect(decoded == button)
        #expect(decoded.text == "Approve")
        #expect(decoded.callbackData == "approve:1")
        #expect(decoded.url == nil)
    }

    @Test("TGInlineKeyboardButton encodes snake_case keys")
    func inlineKeyboardButtonEncoding() throws {
        let button = TGInlineKeyboardButton(text: "Cancel", callbackData: "cancel")

        let data = try JSONEncoder().encode(button)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"text\":\"Cancel\""))
        #expect(json.contains("\"callback_data\":\"cancel\""))
    }

    @Test("TGInlineKeyboardMarkup round-trip")
    func inlineKeyboardMarkupRoundTrip() throws {
        let markup = TGInlineKeyboardMarkup(inlineKeyboard: [
            [
                TGInlineKeyboardButton(text: "Approve", callbackData: "approve"),
                TGInlineKeyboardButton(text: "Deny", callbackData: "deny"),
            ]
        ])

        let data = try JSONEncoder().encode(markup)
        let decoded = try JSONDecoder().decode(TGInlineKeyboardMarkup.self, from: data)

        #expect(decoded == markup)
        #expect(decoded.inlineKeyboard.count == 1)
        #expect(decoded.inlineKeyboard[0].count == 2)
        #expect(decoded.inlineKeyboard[0][0].text == "Approve")
        #expect(decoded.inlineKeyboard[0][1].text == "Deny")
    }

    @Test("TGInlineKeyboardMarkup encodes as inline_keyboard")
    func inlineKeyboardMarkupEncoding() throws {
        let markup = TGInlineKeyboardMarkup(inlineKeyboard: [
            [TGInlineKeyboardButton(text: "OK", callbackData: "ok")]
        ])

        let data = try JSONEncoder().encode(markup)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"inline_keyboard\""))
    }

    @Test("TGSendMessageRequest with replyMarkup encodes correctly")
    func sendMessageWithReplyMarkup() throws {
        let markup = TGInlineKeyboardMarkup(inlineKeyboard: [
            [TGInlineKeyboardButton(text: "Yes", callbackData: "yes")]
        ])
        let req = TGSendMessageRequest(chatId: 123, text: "Approve?", replyMarkup: markup)

        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"reply_markup\""))
        #expect(json.contains("\"inline_keyboard\""))
        #expect(json.contains("\"callback_data\":\"yes\""))
    }

    @Test("TGSendMessageRequest without replyMarkup omits key")
    func sendMessageWithoutReplyMarkup() throws {
        let req = TGSendMessageRequest(chatId: 123, text: "hello")

        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("reply_markup"))
    }

    // MARK: - Edit Message Text Request (Story 32.5)

    @Test("TGEditMessageTextRequest round-trip with chat + message id")
    func editMessageTextRoundTrip() throws {
        let req = TGEditMessageTextRequest(
            chatId: 12345,
            messageId: 42,
            text: "Updated text",
            parseMode: .html
        )

        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(TGEditMessageTextRequest.self, from: data)

        #expect(decoded.chatId == 12345)
        #expect(decoded.messageId == 42)
        #expect(decoded.inlineMessageId == nil)
        #expect(decoded.text == "Updated text")
        #expect(decoded.parseMode == "HTML")
        #expect(decoded.replyMarkup == nil)
    }

    @Test("TGEditMessageTextRequest encodes snake_case keys")
    func editMessageTextEncoding() throws {
        let markup = TGInlineKeyboardMarkup(inlineKeyboard: [
            [TGInlineKeyboardButton(text: "Done", callbackData: "done")]
        ])
        let req = TGEditMessageTextRequest(
            chatId: 99,
            messageId: 5,
            text: "edited",
            replyMarkup: markup
        )

        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"chat_id\":99"))
        #expect(json.contains("\"message_id\":5"))
        #expect(json.contains("\"reply_markup\""))
    }

    // MARK: - Answer Callback Query Request (Story 32.5)

    @Test("TGAnswerCallbackQueryRequest round-trip")
    func answerCallbackQueryRoundTrip() throws {
        let req = TGAnswerCallbackQueryRequest(
            callbackQueryId: "cb123",
            text: "Approved!",
            showAlert: false
        )

        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(TGAnswerCallbackQueryRequest.self, from: data)

        #expect(decoded.callbackQueryId == "cb123")
        #expect(decoded.text == "Approved!")
        #expect(decoded.showAlert == false)
    }

    @Test("TGAnswerCallbackQueryRequest encodes snake_case keys")
    func answerCallbackQueryEncoding() throws {
        let req = TGAnswerCallbackQueryRequest(callbackQueryId: "q1")

        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"callback_query_id\":\"q1\""))
    }
}
