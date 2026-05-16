import Foundation
import Testing
@testable import AxionHelper

@Suite("WindowInfo")
struct WindowInfoTests {

    @Test("codable round trip")
    func codableRoundTrip() throws {
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
        #expect(decoded == original)
    }

    @Test("codable round trip with nils")
    func codableRoundTripNils() throws {
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
        #expect(decoded == original)
    }

    @Test("WindowBounds codable round trip")
    func windowBoundsCodableRoundTrip() throws {
        let original = WindowBounds(x: 100, y: 200, width: 640, height: 480)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowBounds.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - JSON snake_case keys

    @Test("JSON uses snake_case keys")
    func jsonSnakeCaseKeys() throws {
        let info = WindowInfo(
            windowId: 42, pid: 1234,
            title: "Test", appName: "Safari", bundleId: "com.apple.Safari",
            bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            zOrder: 5
        )
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // snake_case keys
        #expect(json["window_id"] != nil)
        #expect(json["app_name"] != nil)
        #expect(json["bundle_id"] != nil)
        #expect(json["z_order"] != nil)
        // NOT camelCase
        #expect(json["windowId"] == nil)
        #expect(json["appName"] == nil)
        #expect(json["bundleId"] == nil)
        #expect(json["zOrder"] == nil)
    }

    // MARK: - Equality

    @Test("equality: same values")
    func equalitySame() {
        let a = WindowInfo(
            windowId: 1, pid: 100, title: "W", appName: "A", bundleId: "com.a",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100), zOrder: 2
        )
        let b = WindowInfo(
            windowId: 1, pid: 100, title: "W", appName: "A", bundleId: "com.a",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100), zOrder: 2
        )
        #expect(a == b)
    }

    @Test("equality: different windowId")
    func equalityDifferentWindowId() {
        let a = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0))
        let b = WindowInfo(windowId: 2, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0))
        #expect(a != b)
    }

    @Test("equality: different bounds")
    func equalityDifferentBounds() {
        let a = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100))
        let b = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 200, height: 200))
        #expect(a != b)
    }

    // MARK: - zOrder field

    @Test("zOrder default value")
    func zOrderDefaultValue() throws {
        let info = WindowInfo(
            windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil,
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100)
        )
        #expect(info.zOrder == 0)
    }

    @Test("zOrder backward compatibility with missing field")
    func zOrderBackwardCompatibilityMissingField() throws {
        let json = """
        {"window_id": 1, "pid": 100, "bounds": {"x": 0, "y": 0, "width": 100, "height": 100}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(WindowInfo.self, from: data)
        #expect(decoded.zOrder == 0)
        #expect(decoded.windowId == 1)
    }

    @Test("zOrder different values not equal")
    func zOrderDifferentValuesNotEqual() {
        let a = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0), zOrder: 0)
        let b = WindowInfo(windowId: 1, pid: 100, title: nil, appName: nil, bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0), zOrder: 1)
        #expect(a != b)
    }

    // MARK: - WindowBounds

    @Test("WindowBounds equality")
    func windowBoundsEquality() {
        let a = WindowBounds(x: 10, y: 20, width: 100, height: 200)
        let b = WindowBounds(x: 10, y: 20, width: 100, height: 200)
        let c = WindowBounds(x: 0, y: 0, width: 100, height: 200)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("WindowBounds zero values")
    func windowBoundsZeroValues() throws {
        let bounds = WindowBounds(x: 0, y: 0, width: 0, height: 0)
        let data = try JSONEncoder().encode(bounds)
        let decoded = try JSONDecoder().decode(WindowBounds.self, from: data)
        #expect(decoded == bounds)
    }

    @Test("WindowBounds JSON keys")
    func windowBoundsJsonKeys() throws {
        let bounds = WindowBounds(x: 10, y: 20, width: 100, height: 200)
        let data = try JSONEncoder().encode(bounds)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["x"] as? Int == 10)
        #expect(json["y"] as? Int == 20)
        #expect(json["width"] as? Int == 100)
        #expect(json["height"] as? Int == 200)
    }
}
