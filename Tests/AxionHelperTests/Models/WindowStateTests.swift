import XCTest
@testable import AxionHelper

final class WindowStateTests: XCTestCase {

    func testCodableRoundTrip_withAXTree() throws {
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
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTrip_nilAXTree() throws {
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
        XCTAssertEqual(decoded, original)
    }

    func testAXTreeAlwaysEncoded() throws {
        let state = WindowState(
            windowId: 1, pid: 99, title: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: false, axTree: nil
        )
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["ax_tree"], "ax_tree should always be present in JSON output, even when nil")
    }

    // MARK: - JSON snake_case keys

    func testJson_snakeCaseKeys() throws {
        let state = WindowState(
            windowId: 42, pid: 1234,
            title: "Test", bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: true,
            axTree: AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: [])
        )
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // snake_case keys
        XCTAssertNotNil(json["window_id"])
        XCTAssertNotNil(json["is_minimized"])
        XCTAssertNotNil(json["is_focused"])
        XCTAssertNotNil(json["ax_tree"])
        // NOT camelCase
        XCTAssertNil(json["windowId"])
        XCTAssertNil(json["isMinimized"])
        XCTAssertNil(json["isFocused"])
        XCTAssertNil(json["axTree"])
    }

    // MARK: - Equality

    func testEquality_same() {
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
        XCTAssertEqual(a, b)
    }

    func testEquality_differentIsMinimized() {
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
        XCTAssertNotEqual(a, b)
    }

    func testEquality_differentIsFocused() {
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
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Encoding with non-nil axTree

    func testEncoding_withAXTree_producesCorrectStructure() throws {
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

        let axTreeJson = try XCTUnwrap(json["ax_tree"] as? [String: Any])
        XCTAssertEqual(axTreeJson["role"] as? String, "AXWindow")
        XCTAssertEqual(axTreeJson["title"] as? String, "Main")
        XCTAssertEqual((axTreeJson["children"] as? [Any])?.count, 1)
    }

    func testEncoding_nilAXTree_producesNull() throws {
        let state = WindowState(
            windowId: 1, pid: 99, title: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: false, axTree: nil
        )
        let data = try JSONEncoder().encode(state)
        let jsonString = String(data: data, encoding: .utf8)!
        // When axTree is nil, the custom encoder should produce "ax_tree": null
        XCTAssertTrue(jsonString.contains("\"ax_tree\":null"), "ax_tree should be null in JSON when nil")
    }

    // MARK: - appName field

    func testAppName_roundTrip() throws {
        let original = WindowState(
            windowId: 1, pid: 99, title: "Doc",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: true, axTree: nil,
            appName: "TextEdit"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowState.self, from: data)
        XCTAssertEqual(decoded.appName, "TextEdit")
    }

    func testAppName_snakeCaseKey() throws {
        let state = WindowState(
            windowId: 1, pid: 99, title: "Doc",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: false, axTree: nil,
            appName: "Safari"
        )
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["app_name"] as? String, "Safari")
        XCTAssertNil(json["appName"])
    }

    func testAppName_backwardCompatibility_missingField() throws {
        let json = """
        {"window_id": 1, "pid": 99, "bounds": {"x": 0, "y": 0, "width": 100, "height": 100}, "is_minimized": false, "is_focused": false, "ax_tree": null}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(WindowState.self, from: data)
        XCTAssertNil(decoded.appName)
    }

    func testAppName_equality_differentAppName() {
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
        XCTAssertNotEqual(a, b)
    }
}
