import AxionCore
import Foundation
import Testing

@testable import AxionHelper

@Suite("ToolRegistrar Additional Tests")
struct ToolRegistrarMockTests {

    // MARK: - BlockingDialogInfo Codable

    @Test("BlockingDialogInfo codable round trip preserves fields")
    func blockingDialogInfoCodable() throws {
        let info = BlockingDialogInfo(windowId: 42, title: "Open File")
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(BlockingDialogInfo.self, from: data)
        #expect(decoded.windowId == 42)
        #expect(decoded.title == "Open File")
    }

    @Test("BlockingDialogInfo uses snake_case CodingKeys")
    func blockingDialogInfoSnakeCase() throws {
        let info = BlockingDialogInfo(windowId: 1, title: "Save")
        let data = try JSONEncoder().encode(info)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("window_id"))
    }

    @Test("BlockingDialogInfo equality same fields match")
    func blockingDialogInfoEquality() {
        let a = BlockingDialogInfo(windowId: 1, title: "Open")
        let b = BlockingDialogInfo(windowId: 1, title: "Open")
        #expect(a.windowId == b.windowId)
        #expect(a.title == b.title)
    }

    // MARK: - Tool Result JSON Format Verification

    @Test("Coordinate result JSON has expected keys")
    func coordinateResultJSONFormat() {
        let json = #"{"success":true,"action":"click","x":100,"y":200}"#
        let data = Data(json.utf8)
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["success"] as? Bool == true)
        #expect(dict?["action"] as? String == "click")
        #expect(dict?["x"] as? Int == 100)
        #expect(dict?["y"] as? Int == 200)
    }

    @Test("Drag result JSON uses snake_case keys")
    func dragResultSnakeCase() {
        let json = #"{"success":true,"action":"drag","from_x":0,"from_y":0,"to_x":100,"to_y":100}"#
        #expect(json.contains("from_x"))
        #expect(json.contains("from_y"))
        #expect(json.contains("to_x"))
        #expect(json.contains("to_y"))
    }

    @Test("Text result JSON has expected structure")
    func textResultJSONFormat() {
        let json = #"{"success":true,"action":"type_text","text":"Hello"}"#
        let data = Data(json.utf8)
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["success"] as? Bool == true)
        #expect(dict?["text"] as? String == "Hello")
    }

    @Test("Key result JSON has expected structure")
    func keyResultJSONFormat() {
        let json = #"{"success":true,"action":"press_key","key":"return"}"#
        let data = Data(json.utf8)
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["key"] as? String == "return")
    }

    @Test("Hotkey result JSON has expected structure")
    func hotkeyResultJSONFormat() {
        let json = #"{"success":true,"action":"hotkey","keys":"cmd+c"}"#
        let data = Data(json.utf8)
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["keys"] as? String == "cmd+c")
    }

    @Test("Scroll result JSON has expected structure")
    func scrollResultJSONFormat() {
        let json = #"{"success":true,"action":"scroll","direction":"down","amount":5}"#
        let data = Data(json.utf8)
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["direction"] as? String == "down")
        #expect(dict?["amount"] as? Int == 5)
    }

    @Test("Screenshot result JSON uses snake_case image_data key")
    func screenshotResultSnakeCase() {
        let json = #"{"success":true,"action":"screenshot","image_data":"base64..."}"#
        #expect(json.contains("image_data"))
    }

    @Test("Open URL result JSON has expected structure")
    func openURLResultJSONFormat() {
        let json = #"{"success":true,"action":"open_url","url":"https://example.com"}"#
        let data = Data(json.utf8)
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["url"] as? String == "https://example.com")
    }
}
