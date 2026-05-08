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
            axTree: tree
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
}
