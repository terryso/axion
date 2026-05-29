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
    }
}
