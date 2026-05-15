import Foundation
import Testing
@testable import AxionHelper

@Suite("WindowState")
struct WindowStateTests {

    @Test("codable round trip with AX tree")
    func codableRoundTripWithAXTree() throws {
        let tree = AXElement(
            role: "AXWindow",
            title: "Calculator",
            value: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 200, height: 300),
            children: [
                AXElement(role: "AXButton", title: "7", value: nil, bounds: nil, children: [])
            ]
        )
        let original = WindowState(
            windowId: 42,
            pid: 1234,
            title: "Calculator",
            bounds: WindowBounds(x: 100, y: 100, width: 200, height: 300),
            isMinimized: false,
            isFocused: true,
            axTree: tree,
            appName: "Calculator"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowState.self, from: data)
        #expect(decoded == original)
    }

    @Test("codable round trip with nil AX tree")
    func codableRoundTripNilAXTree() throws {
        let original = WindowState(
            windowId: 1,
            pid: 99,
            title: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: true,
            isFocused: false,
            axTree: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowState.self, from: data)
        #expect(decoded == original)
    }

    @Test("AX tree always encoded")
    func axTreeAlwaysEncoded() throws {
        let state = WindowState(
            windowId: 1, pid: 99, title: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: false, axTree: nil
        )
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["ax_tree"] != nil, "ax_tree should always be present in JSON output, even when nil")
    }

    // MARK: - JSON snake_case keys

    @Test("JSON uses snake_case keys")
    func jsonSnakeCaseKeys() throws {
        let state = WindowState(
            windowId: 42, pid: 1234,
            title: "Test", bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: true,
            axTree: AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: [])
        )
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // snake_case keys
        #expect(json["window_id"] != nil)
        #expect(json["is_minimized"] != nil)
        #expect(json["is_focused"] != nil)
        #expect(json["ax_tree"] != nil)
        // NOT camelCase
        #expect(json["windowId"] == nil)
        #expect(json["isMinimized"] == nil)
        #expect(json["isFocused"] == nil)
        #expect(json["axTree"] == nil)
    }

    // MARK: - Equality

    @Test("equality: same values")
    func equalitySame() {
        let a = WindowState(
            windowId: 1, pid: 99, title: "W",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: true, axTree: nil
        )
        let b = WindowState(
            windowId: 1, pid: 99, title: "W",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: true, axTree: nil
        )
        #expect(a == b)
    }

    @Test("equality: different isMinimized")
    func equalityDifferentIsMinimized() {
        let a = WindowState(
            windowId: 1, pid: 99, title: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
            isMinimized: false, isFocused: false, axTree: nil
        )
        let b = WindowState(
            windowId: 1, pid: 99, title: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
            isMinimized: true, isFocused: false, axTree: nil
        )
        #expect(a != b)
    }

    @Test("equality: different isFocused")
    func equalityDifferentIsFocused() {
        let a = WindowState(
            windowId: 1, pid: 99, title: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
            isMinimized: false, isFocused: false, axTree: nil
        )
        let b = WindowState(
            windowId: 1, pid: 99, title: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
            isMinimized: false, isFocused: true, axTree: nil
        )
        #expect(a != b)
    }

    // MARK: - Encoding with non-nil axTree

    @Test("encoding with AX tree produces correct structure")
    func encodingWithAXTreeProducesCorrectStructure() throws {
        let tree = AXElement(
            role: "AXWindow",
            title: "Main",
            value: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            children: [
                AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
            ]
        )
        let state = WindowState(
            windowId: 1, pid: 99, title: "Main",
            bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            isMinimized: false, isFocused: true, axTree: tree
        )
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let axTreeJson = try #require(json["ax_tree"] as? [String: Any])
        #expect(axTreeJson["role"] as? String == "AXWindow")
        #expect(axTreeJson["title"] as? String == "Main")
        #expect((axTreeJson["children"] as? [Any])?.count == 1)
    }

    @Test("encoding nil AX tree produces null")
    func encodingNilAXTreeProducesNull() throws {
        let state = WindowState(
            windowId: 1, pid: 99, title: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: false, axTree: nil
        )
        let data = try JSONEncoder().encode(state)
        let jsonString = String(data: data, encoding: .utf8)!
        #expect(jsonString.contains("\"ax_tree\":null"), "ax_tree should be null in JSON when nil")
    }

    // MARK: - appName field

    @Test("appName round trip")
    func appNameRoundTrip() throws {
        let original = WindowState(
            windowId: 1, pid: 99, title: "Doc",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: true, axTree: nil,
            appName: "TextEdit"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowState.self, from: data)
        #expect(decoded.appName == "TextEdit")
    }

    @Test("appName uses snake_case key")
    func appNameSnakeCaseKey() throws {
        let state = WindowState(
            windowId: 1, pid: 99, title: "Doc",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: false, axTree: nil,
            appName: "Safari"
        )
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["app_name"] as? String == "Safari")
        #expect(json["appName"] == nil)
    }

    @Test("appName backward compatibility with missing field")
    func appNameBackwardCompatibilityMissingField() throws {
        let json = """
        {"window_id": 1, "pid": 99, "bounds": {"x": 0, "y": 0, "width": 100, "height": 100}, "is_minimized": false, "is_focused": false, "ax_tree": null}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(WindowState.self, from: data)
        #expect(decoded.appName == nil)
    }

    @Test("equality: different appName")
    func equalityDifferentAppName() {
        let a = WindowState(
            windowId: 1, pid: 99, title: "W",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: true, axTree: nil,
            appName: "Safari"
        )
        let b = WindowState(
            windowId: 1, pid: 99, title: "W",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: true, axTree: nil,
            appName: "Chrome"
        )
        #expect(a != b)
    }
}
