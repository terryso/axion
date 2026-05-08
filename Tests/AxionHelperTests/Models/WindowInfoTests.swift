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
            bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600)
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
            bounds: WindowBounds(x: 10, y: 20, width: 300, height: 200)
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
}
