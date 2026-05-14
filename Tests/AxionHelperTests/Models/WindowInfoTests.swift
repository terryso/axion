import XCTest
@testable import AxionHelper

final class WindowInfoTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let original = WindowInfo(
            windowId: 42,
            pid: 1234,
            title: "Main Window",
            appName: "Safari",
            bundleId: "com.apple.Safari",
            bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            zOrder: 3
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowInfo.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTrip_nils() throws {
        let original = WindowInfo(
            windowId: 1,
            pid: 99,
            title: nil,
            appName: nil,
            bundleId: nil,
            bounds: WindowBounds(x: 10, y: 20, width: 300, height: 200),
            zOrder: 0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowInfo.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testWindowBoundsCodableRoundTrip() throws {
        let original = WindowBounds(x: 100, y: 200, width: 640, height: 480)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowBounds.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - JSON snake_case keys

    func testJson_snakeCaseKeys() throws {
        let info = WindowInfo(
            windowId: 42, pid: 1234,
            title: "Test", appName: "Safari", bundleId: "com.apple.Safari",
            bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            zOrder: 5
        )
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // snake_case keys
        XCTAssertNotNil(json["window_id"])
        XCTAssertNotNil(json["app_name"])
        XCTAssertNotNil(json["bundle_id"])
        XCTAssertNotNil(json["z_order"])
        // NOT camelCase
        XCTAssertNil(json["windowId"])
        XCTAssertNil(json["appName"])
        XCTAssertNil(json["bundleId"])
        XCTAssertNil(json["zOrder"])
    }

    // MARK: - Equality

    func testEquality_same() {
        let a = WindowInfo(
            windowId: 1, pid: 100, title: "W", appName: "A", bundleId: "com.a",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100), zOrder: 2
        )
        let b = WindowInfo(
            windowId: 1, pid: 100, title: "W", appName: "A", bundleId: "com.a",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100), zOrder: 2
        )
        XCTAssertEqual(a, b)
    }

    func testEquality_differentWindowId() {
        let a = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0))
        let b = WindowInfo(windowId: 2, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0))
        XCTAssertNotEqual(a, b)
    }

    func testEquality_differentBounds() {
        let a = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100))
        let b = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - zOrder field

    func testZOrder_defaultValue() throws {
        let info = WindowInfo(
            windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100)
        )
        XCTAssertEqual(info.zOrder, 0)
    }

    func testZOrder_backwardCompatibility_missingField() throws {
        let json = """
        {"window_id": 1, "pid": 100, "bounds": {"x": 0, "y": 0, "width": 100, "height": 100}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(WindowInfo.self, from: data)
        XCTAssertEqual(decoded.zOrder, 0)
        XCTAssertEqual(decoded.windowId, 1)
    }

    func testZOrder_differentValues_notEqual() {
        let a = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0), zOrder: 0)
        let b = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0), zOrder: 1)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - WindowBounds

    func testWindowBounds_equality() {
        let a = WindowBounds(x: 10, y: 20, width: 100, height: 200)
        let b = WindowBounds(x: 10, y: 20, width: 100, height: 200)
        let c = WindowBounds(x: 0, y: 0, width: 100, height: 200)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testWindowBounds_zeroValues() throws {
        let bounds = WindowBounds(x: 0, y: 0, width: 0, height: 0)
        let data = try JSONEncoder().encode(bounds)
        let decoded = try JSONDecoder().decode(WindowBounds.self, from: data)
        XCTAssertEqual(decoded, bounds)
    }

    func testWindowBounds_jsonKeys() throws {
        let bounds = WindowBounds(x: 10, y: 20, width: 100, height: 200)
        let data = try JSONEncoder().encode(bounds)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["x"] as? Int, 10)
        XCTAssertEqual(json["y"] as? Int, 20)
        XCTAssertEqual(json["width"] as? Int, 100)
        XCTAssertEqual(json["height"] as? Int, 200)
    }
}
